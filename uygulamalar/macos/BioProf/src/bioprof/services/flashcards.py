"""Flashcard çalışma servisi: SM-2 zamanlama, deste yönetimi, Anki/CSV export.

SM-2 durumu kartın üstünde tutulur ("vadesi gelenler" tek tablodan çözülür);
her inceleme ``flashcard_reviews``'a append-only ham kayıt düşer — istatistik
ve olası "geri al" bu günlükten türetilir.
"""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from bioprof.db.models import (
    FlashcardDeckRecord,
    FlashcardRecord,
    FlashcardReviewRecord,
    utc_now_naive,
)

# UI'daki üç düğmenin SM-2 notu karşılıkları.
NOT_ESLEME = {"bilemedim": 2, "zor": 3, "bildim": 5}
_ASGARI_EF = 1.3


@dataclass(frozen=True)
class Sm2Sonucu:
    ease_factor: float
    interval_days: float
    repetitions: int
    lapse: bool


def sm2_guncelle(
    ease_factor: float, interval_days: float, repetitions: int, grade: int
) -> Sm2Sonucu:
    """Saf SM-2 adımı. grade 0-5; <3 başarısızlıktır (tekrar sayacı sıfırlanır).

    Aralıklar klasik SM-2: 1 gün, 6 gün, sonrası interval×EF. EF alt sınırı
    1.3 — altına inen desteler "hep yarın" döngüsüne kilitlenir.
    """
    grade = max(0, min(5, int(grade)))
    if grade < 3:
        return Sm2Sonucu(
            ease_factor=max(_ASGARI_EF, ease_factor - 0.2),
            interval_days=1.0,
            repetitions=0,
            lapse=True,
        )
    yeni_ef = max(
        _ASGARI_EF,
        ease_factor + (0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)),
    )
    yeni_tekrar = repetitions + 1
    if yeni_tekrar == 1:
        yeni_aralik = 1.0
    elif yeni_tekrar == 2:
        yeni_aralik = 6.0
    else:
        yeni_aralik = max(1.0, interval_days) * yeni_ef
    return Sm2Sonucu(
        ease_factor=yeni_ef,
        interval_days=yeni_aralik,
        repetitions=yeni_tekrar,
        lapse=False,
    )


class FlashcardService:
    def __init__(self, session: Session) -> None:
        self.session = session

    # -- deste ---------------------------------------------------------------

    def create_deck_from_artifact(
        self,
        notebook_id: str,
        artifact_id: str | None,
        title: str,
        cards: list[dict[str, Any]],
        description: str = "",
    ) -> FlashcardDeckRecord:
        if not cards:
            raise ValueError("Desteye çevrilecek kart bulunamadı")
        deck = FlashcardDeckRecord(
            notebook_id=notebook_id,
            artifact_id=artifact_id,
            title=title.strip()[:300] or "Adsız deste",
            description=description,
        )
        self.session.add(deck)
        self.session.flush()
        for position, card in enumerate(cards):
            front = str(card.get("front") or "").strip()
            back = str(card.get("back") or "").strip()
            if not front or not back:
                continue
            self.session.add(
                FlashcardRecord(
                    deck_id=deck.id,
                    front=front[:2000],
                    back=back[:4000],
                    citation_label=str(card.get("citation") or "")[:16] or None,
                    citation_id=str(card.get("citation_id") or "")[:64] or None,
                    source_title=str(card.get("source_title") or "")[:500] or None,
                    position=position,
                )
            )
        self.session.commit()
        self.session.refresh(deck)
        return deck

    def list_decks(self, notebook_id: str) -> list[dict[str, Any]]:
        decks = self.session.scalars(
            select(FlashcardDeckRecord)
            .where(FlashcardDeckRecord.notebook_id == notebook_id)
            .order_by(FlashcardDeckRecord.created_at.desc())
        ).all()
        simdi = utc_now_naive()
        sonuc = []
        for deck in decks:
            kartlar = self.session.scalars(
                select(FlashcardRecord).where(FlashcardRecord.deck_id == deck.id)
            ).all()
            sonuc.append(
                {
                    "id": deck.id,
                    "notebook_id": deck.notebook_id,
                    "artifact_id": deck.artifact_id,
                    "title": deck.title,
                    "description": deck.description,
                    "created_at": deck.created_at.isoformat(),
                    "card_count": len(kartlar),
                    "due_count": sum(
                        1 for kart in kartlar if not kart.suspended and kart.due_at <= simdi
                    ),
                }
            )
        return sonuc

    def get_deck(self, deck_id: str) -> FlashcardDeckRecord | None:
        return self.session.get(FlashcardDeckRecord, deck_id)

    def delete_deck(self, deck_id: str) -> bool:
        deck = self.get_deck(deck_id)
        if deck is None:
            return False
        self.session.delete(deck)
        self.session.commit()
        return True

    # -- çalışma -------------------------------------------------------------

    def due_cards(self, deck_id: str, *, limit: int = 20) -> list[dict[str, Any]]:
        simdi = utc_now_naive()
        kartlar = self.session.scalars(
            select(FlashcardRecord)
            .where(
                FlashcardRecord.deck_id == deck_id,
                FlashcardRecord.suspended.is_(False),
                FlashcardRecord.due_at <= simdi,
            )
            .order_by(FlashcardRecord.due_at, FlashcardRecord.position)
            .limit(limit)
        ).all()
        return [self.serialize_card(kart) for kart in kartlar]

    def record_review(self, card_id: str, grade: int) -> dict[str, Any]:
        """Kart durumunu günceller ve incelemeyi loglar — tek transaction."""
        kart = self.session.get(FlashcardRecord, card_id)
        if kart is None:
            raise ValueError("Kart bulunamadı")
        sonuc = sm2_guncelle(kart.ease_factor, kart.interval_days, kart.repetitions, grade)
        log = FlashcardReviewRecord(
            card_id=kart.id,
            grade=int(grade),
            interval_before=kart.interval_days,
            interval_after=sonuc.interval_days,
            ease_before=kart.ease_factor,
            ease_after=sonuc.ease_factor,
        )
        kart.ease_factor = sonuc.ease_factor
        kart.interval_days = sonuc.interval_days
        kart.repetitions = sonuc.repetitions
        if sonuc.lapse:
            kart.lapses += 1
        kart.due_at = utc_now_naive() + timedelta(days=sonuc.interval_days)
        self.session.add(log)
        self.session.commit()
        self.session.refresh(kart)
        return self.serialize_card(kart)

    @staticmethod
    def serialize_card(kart: FlashcardRecord) -> dict[str, Any]:
        return {
            "id": kart.id,
            "deck_id": kart.deck_id,
            "front": kart.front,
            "back": kart.back,
            "citation_label": kart.citation_label,
            "citation_id": kart.citation_id,
            "source_title": kart.source_title,
            "position": kart.position,
            "ease_factor": round(kart.ease_factor, 3),
            "interval_days": round(kart.interval_days, 2),
            "repetitions": kart.repetitions,
            "lapses": kart.lapses,
            "due_at": kart.due_at.isoformat(),
            "suspended": kart.suspended,
        }

    # -- dışa aktarma --------------------------------------------------------

    def export_csv(self, deck_id: str) -> bytes:
        """Anki'nin içe aktarabildiği noktalı virgüllü CSV (ön;arka;etiket)."""
        kartlar = self.session.scalars(
            select(FlashcardRecord)
            .where(FlashcardRecord.deck_id == deck_id)
            .order_by(FlashcardRecord.position)
        ).all()
        tampon = io.StringIO()
        yazici = csv.writer(tampon, delimiter=";")
        for kart in kartlar:
            etiket = " ".join(
                filter(None, [kart.source_title, kart.citation_label])
            ).strip()
            yazici.writerow([kart.front, kart.back, etiket])
        return tampon.getvalue().encode("utf-8")

    def export_apkg(self, deck_id: str) -> bytes:
        """Gerçek Anki paketi; genanki kurulu değilse ImportError yükselir."""
        import random

        import genanki

        deck = self.get_deck(deck_id)
        if deck is None:
            raise ValueError("Deste bulunamadı")
        kartlar = self.session.scalars(
            select(FlashcardRecord)
            .where(FlashcardRecord.deck_id == deck_id)
            .order_by(FlashcardRecord.position)
        ).all()
        # Kimlikler deste id'sinden deterministik türetilir: aynı deste iki kez
        # export edilirse Anki bunları aynı deste olarak günceller.
        tohum = random.Random(deck.id)
        model = genanki.Model(
            tohum.randrange(1 << 30, 1 << 31),
            "BioProf Kartı",
            fields=[{"name": "On"}, {"name": "Arka"}, {"name": "Kaynak"}],
            templates=[
                {
                    "name": "Kart",
                    "qfmt": "{{On}}",
                    "afmt": "{{FrontSide}}<hr id=answer>{{Arka}}<br><small>{{Kaynak}}</small>",
                }
            ],
        )
        anki_deck = genanki.Deck(tohum.randrange(1 << 30, 1 << 31), deck.title)
        for kart in kartlar:
            anki_deck.add_note(
                genanki.Note(
                    model=model,
                    fields=[
                        kart.front,
                        kart.back,
                        " ".join(filter(None, [kart.source_title, kart.citation_label])),
                    ],
                )
            )
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as gecici:
            yol = Path(gecici) / "deste.apkg"
            genanki.Package(anki_deck).write_to_file(str(yol))
            return yol.read_bytes()
