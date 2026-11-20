from __future__ import annotations

import asyncio
import contextlib
import csv
import html
import io
import json
import os
import re
import tempfile
import uuid
import wave
from collections.abc import Awaitable, Callable, Iterable
from copy import copy
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

ArtifactKind = Literal[
    "summary",
    "faq",
    "glossary",
    "timeline",
    "study_guide",
    "quiz",
    "flashcards",
    "mind_map",
    "slides",
    "ders_plani",
    "table",
    "audio_lesson",
    "audio_lecture",
    "video_overview",
    "podcast",
]


class StudioExportError(RuntimeError):
    pass


class StudioServiceRequired(StudioExportError):
    def __init__(self, service: str) -> None:
        super().__init__(f"Bu medya çıktısı için '{service}' servisi hazır olmalıdır")
        self.service = service


class StudioEvidence(BaseModel):
    model_config = ConfigDict(extra="allow")

    label: str
    text: str = Field(min_length=1)
    source_title: str
    citation_id: str
    section: str | None = None
    page: int | None = None
    timestamp_start: float | None = None
    timestamp_end: float | None = None

    @property
    def citation(self) -> str:
        return f"[{self.label}]"


class StudioArtifact(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    notebook_id: str | None = None
    kind: ArtifactKind
    title: str
    content_markdown: str
    structured_data: dict[str, Any] = Field(default_factory=dict)
    citations: list[StudioEvidence] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    provenance_complete: bool = True
    warnings: list[str] = Field(default_factory=list)


def _sentences(value: str) -> list[str]:
    cleaned = " ".join(value.split())
    return [item.strip() for item in re.split(r"(?<=[.!?])\s+", cleaned) if item.strip()]


def _claim(evidence: StudioEvidence, *, limit: int = 360) -> str:
    sentences = _sentences(evidence.text)
    value = sentences[0] if sentences else evidence.text.strip()
    if len(value) > limit:
        value = value[: limit - 1].rstrip() + "…"
    return f"{value} {evidence.citation}"


# Soru üretiminde anlam taşımayan sözcükler; odak/boşluk seçilirken atlanır.
_QUIZ_ATLANAN = frozenset({
    "bir", "bu", "şu", "ile", "ve", "veya", "için", "olarak", "olan", "gibi",
    "daha", "çok", "kadar", "ancak", "ise", "de", "da", "ki", "her", "en",
    "the", "and", "for", "with", "that", "this", "from",
})
_QUIZ_TERIM = re.compile(r"[^\W\d_]{6,}", re.UNICODE)
_QUIZ_SAYI = re.compile(r"\b\d+(?:[.,]\d+)*\b")


def _zorluk(iddia: str) -> str:
    """Kaba ama savunulabilir bir zorluk göstergesi.

    Uydurma bir ölçek değil: sayı içeren ve uzun cümleler öğrenciden daha
    fazla iz sürme ister. Öğretmenin sıralama yapmasına yeter, iddiası
    bundan fazlası değil.
    """
    sozcuk = len(iddia.split())
    sayi_var = bool(_QUIZ_SAYI.search(iddia))
    if sozcuk > 28 or (sayi_var and sozcuk > 18):
        return "zor"
    if sozcuk > 14 or sayi_var:
        return "orta"
    return "kolay"


def _belirgin_terim(iddia: str) -> str:
    """Cümlenin en ayırt edici terimi: boşluk doldurmanın cevabı olur."""
    adaylar = [
        kelime
        for kelime in _QUIZ_TERIM.findall(iddia)
        if kelime.casefold() not in _QUIZ_ATLANAN
    ]
    if not adaylar:
        return ""
    return max(adaylar, key=len)


def _odak_ifadesi(iddia: str) -> str:
    terim = _belirgin_terim(iddia)
    return terim if terim else "bu bulgu"


def _bosluk_doldurma(iddia: str) -> tuple[str, str] | None:
    terim = _belirgin_terim(iddia)
    if not terim:
        return None
    govde = iddia.replace(terim, "______", 1)
    if govde == iddia:
        return None
    return govde, terim


def _coktan_secmeli_secenekler(
    iddia: str, digerleri: list[StudioEvidence]
) -> tuple[dict[str, str], str] | None:
    """Doğru şık + aynı defterin başka kanıtlarından çeldiriciler.

    Çeldirici uydurmak, kanıta bağlılık ilkesini quiz yüzeyinden delerdi:
    öğrenciye gösterilen her cümlenin bir kaynağı olmalı.
    """
    dogru = _kisalt(iddia)
    celdiriciler: list[str] = []
    for other in digerleri:
        cumleler = _sentences(other.text)
        if not cumleler:
            continue
        aday = _kisalt(cumleler[0])
        if aday and aday != dogru and aday not in celdiriciler:
            celdiriciler.append(aday)
        if len(celdiriciler) == 3:
            break
    if len(celdiriciler) < 2:
        return None
    secenekler = [dogru, *celdiriciler]
    harfler = dict(zip("ABCD", secenekler, strict=False))
    return harfler, dogru


def _kisalt(value: str, *, limit: int = 160) -> str:
    temiz = " ".join(value.split())
    if len(temiz) > limit:
        temiz = temiz[: limit - 1].rstrip() + "…"
    return temiz


def _source_note(evidence: StudioEvidence) -> str:
    location = []
    if evidence.page is not None:
        location.append(f"s. {evidence.page}")
    if evidence.timestamp_start is not None:
        location.append(f"{evidence.timestamp_start:.1f} sn")
    suffix = f" — {', '.join(location)}" if location else ""
    return f"{evidence.citation} {evidence.source_title}{suffix}"


class StudioEngine:
    """Build useful, citation-complete fallbacks from retrieved evidence.

    An LLM-facing service may replace the wording, but the deterministic engine
    means Studio remains functional offline and provides a testable grounding
    floor.  Empty evidence fails closed rather than producing model-only facts.
    """

    supported_kinds: tuple[ArtifactKind, ...] = (
        "summary",
        "faq",
        "glossary",
        "timeline",
        "study_guide",
        "quiz",
        "flashcards",
        "mind_map",
        "slides",
        "ders_plani",
        "table",
        "audio_lesson",
        "audio_lecture",
        "video_overview",
        "podcast",
    )

    def generate(
        self,
        kind: ArtifactKind,
        *,
        title: str,
        evidence: Iterable[StudioEvidence],
        notebook_id: str | None = None,
        options: dict[str, Any] | None = None,
    ) -> StudioArtifact:
        records = self._unique_evidence(evidence)
        if not records:
            raise ValueError("Studio artifact requires at least one cited evidence block")
        generator = getattr(self, f"_{kind}", None)
        if generator is None:
            raise ValueError(f"Unsupported Studio artifact kind: {kind}")
        if kind == "ders_plani":
            # Tek seçenek alan üreteç: sınıf/süre/kazanım seçimi payload'dan gelir.
            markdown, structured, warnings = self._ders_plani(
                title, records, options or {}
            )
        else:
            markdown, structured, warnings = generator(title, records)
        labels = {record.citation for record in records}
        used = {label for label in labels if label in markdown}
        provenance_complete = bool(used) and self._structured_has_citations(structured)
        return StudioArtifact(
            notebook_id=notebook_id,
            kind=kind,
            title=title,
            content_markdown=markdown,
            structured_data=structured,
            citations=records,
            provenance_complete=provenance_complete,
            warnings=warnings,
        )

    @staticmethod
    def _unique_evidence(evidence: Iterable[StudioEvidence]) -> list[StudioEvidence]:
        seen: set[str] = set()
        output: list[StudioEvidence] = []
        for record in evidence:
            if record.citation_id in seen:
                continue
            seen.add(record.citation_id)
            output.append(record)
        return output[:50]

    @staticmethod
    def _structured_has_citations(value: Any) -> bool:
        if isinstance(value, dict):
            if "citation" in value:
                return bool(value["citation"])
            return any(StudioEngine._structured_has_citations(item) for item in value.values())
        if isinstance(value, list):
            return any(StudioEngine._structured_has_citations(item) for item in value)
        return False

    @staticmethod
    def _footer(records: list[StudioEvidence]) -> str:
        return "\n\n## Kaynaklar\n\n" + "\n".join(f"- {_source_note(item)}" for item in records)

    def _summary(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        bullets = [
            {"text": _claim(item), "citation": item.citation, "citation_id": item.citation_id}
            for item in records[:10]
        ]
        markdown = f"# {title}\n\n" + "\n".join(f"- {item['text']}" for item in bullets)
        return markdown + self._footer(records[:10]), {"bullets": bullets}, []

    def _faq(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        entries = []
        for index, item in enumerate(records[:10], 1):
            subject = item.section or item.source_title
            entries.append(
                {
                    "question": f"{subject} için kaynaklarda öne çıkan {index}. bulgu nedir?",
                    "answer": _claim(item),
                    "citation": item.citation,
                    "citation_id": item.citation_id,
                }
            )
        markdown = f"# {title}\n\n" + "\n\n".join(
            f"### {entry['question']}\n\n{entry['answer']}" for entry in entries
        )
        return markdown + self._footer(records[:10]), {"faq": entries}, []

    def _glossary(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        stop = {"bir", "ve", "veya", "ile", "için", "the", "and", "that", "this", "from"}
        terms: list[dict[str, str]] = []
        used: set[str] = set()
        for item in records:
            candidates = re.findall(r"\b[A-ZÇĞİÖŞÜ][A-Za-zÇĞİÖŞÜçğıöşü0-9-]{3,}\b", item.text)
            if not candidates and item.section:
                candidates = [item.section]
            for term in candidates:
                key = term.casefold()
                if key in stop or key in used:
                    continue
                used.add(key)
                terms.append(
                    {
                        "term": term,
                        "definition": _claim(item),
                        "citation": item.citation,
                        "citation_id": item.citation_id,
                    }
                )
                break
            if len(terms) >= 20:
                break
        if not terms:
            terms.append(
                {
                    "term": records[0].section or "Ana kavram",
                    "definition": _claim(records[0]),
                    "citation": records[0].citation,
                    "citation_id": records[0].citation_id,
                }
            )
        markdown = f"# {title}\n\n" + "\n\n".join(
            f"**{item['term']}** — {item['definition']}" for item in terms
        )
        return markdown + self._footer(records), {"terms": terms}, []

    def _timeline(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        events = []
        for item in records:
            for year in re.findall(r"\b(?:18|19|20)\d{2}\b", item.text):
                events.append(
                    {
                        "date": year,
                        "event": _claim(item),
                        "citation": item.citation,
                        "citation_id": item.citation_id,
                    }
                )
                break
        events.sort(key=lambda item: item["date"])
        warnings = []
        if not events:
            warnings.append("Seçili kanıtlarda doğrulanabilir bir yıl bulunamadı")
            events = [
                {
                    "date": "Tarih belirtilmemiş",
                    "event": _claim(item),
                    "citation": item.citation,
                    "citation_id": item.citation_id,
                }
                for item in records[:5]
            ]
        markdown = f"# {title}\n\n" + "\n".join(
            f"- **{item['date']}** — {item['event']}" for item in events
        )
        return markdown + self._footer(records), {"events": events}, warnings

    def _study_guide(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        sections: dict[str, list[dict[str, str]]] = {}
        for item in records:
            heading = item.section or item.source_title
            sections.setdefault(heading, []).append(
                {"text": _claim(item), "citation": item.citation, "citation_id": item.citation_id}
            )
        markdown_parts = [
            f"# {title}",
            "## Öğrenme hedefi\n\nKaynaklardaki ana bulguları kanıtlarıyla açıklayabilmek.",
        ]
        for heading, points in sections.items():
            markdown_parts.append(
                f"## {heading}\n\n" + "\n".join(f"- {point['text']}" for point in points)
            )
        markdown_parts.append(
            "## Öz denetim\n\n"
            "Her yanıtınızın hangi kaynak bloğuna dayandığını ve kanıtın sınırlılığını belirtin."
        )
        return "\n\n".join(markdown_parts) + self._footer(records), {"sections": sections}, []

    def _quiz(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        """Kanıtlardan sınav üretir.

        Eskiden her soru birebir aynı cümleydi ("… kaynağındaki ana bulguyu
        açıklayın"), yani on iki kanıt on iki özdeş soru veriyordu ve çıktı
        sınıfta kullanılamıyordu.

        Üç soru biçimi dönüşümlü üretilir. Çoktan seçmelinin çeldiricileri
        UYDURULMAZ: aynı defterin diğer kanıtlarından alınır. Böylece hem
        makul hem de kaynağa bağlı kalırlar; hiçbir seçenek modelin kendi
        bilgisinden gelmez.
        """
        selected = records[:12]
        questions: list[dict[str, Any]] = []
        for index, item in enumerate(selected, 1):
            digerleri = [other for other in selected if other is not item]
            questions.append(self._quiz_sorusu(index, item, digerleri))

        satirlar = [f"# {title}", "", "## Sorular", ""]
        for soru in questions:
            satirlar.append(f"{soru['id']}. {soru['question']}")
            for harf, secenek in soru.get("options", {}).items():
                satirlar.append(f"   {harf}) {secenek}")
            satirlar.append("")
        satirlar += ["## Cevap anahtarı", ""]
        for soru in questions:
            anahtar = soru.get("answer_option") or soru["answer"]
            satirlar.append(
                f"**{soru['id']}.** ({soru['difficulty']}) {anahtar} {soru['citation']}"
            )
        markdown = "\n".join(satirlar)
        return (
            markdown + self._footer(selected),
            {"questions": questions},
            [],
        )

    def _quiz_sorusu(
        self, index: int, item: StudioEvidence, digerleri: list[StudioEvidence]
    ) -> dict[str, Any]:
        temel = {
            "id": index,
            "citation": item.citation,
            "citation_id": item.citation_id,
            "source": item.section or item.source_title,
        }
        iddia = _sentences(item.text)[0] if _sentences(item.text) else item.text.strip()
        temel["difficulty"] = _zorluk(iddia)

        bicim = index % 3
        if bicim == 1:
            secenekler = _coktan_secmeli_secenekler(iddia, digerleri)
            if secenekler:
                harfler, dogru = secenekler
                return {
                    **temel,
                    "type": "multiple_choice",
                    "question": (
                        f"{temel['source']} kaynağına göre aşağıdakilerden "
                        "hangisi doğrudur?"
                    ),
                    "options": harfler,
                    "answer_option": dogru,
                    "answer": _claim(item),
                }
        elif bicim == 2:
            bosluklu = _bosluk_doldurma(iddia)
            if bosluklu:
                govde, terim = bosluklu
                return {
                    **temel,
                    "type": "cloze",
                    "question": f"Boşluğu doldurun: {govde}",
                    "answer_option": terim,
                    "answer": _claim(item),
                }
        return {
            **temel,
            "type": "short_answer",
            "question": (
                f"{temel['source']} kaynağına göre "
                f"{_odak_ifadesi(iddia)} hakkında ne söylenebilir? Yanıtınızı "
                "kaynağa dayandırın."
            ),
            "answer": _claim(item),
        }

    def _flashcards(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        cards = [
            {
                "front": item.section or f"{item.source_title}: ana bulgu",
                "back": _claim(item),
                "citation": item.citation,
                "citation_id": item.citation_id,
            }
            for item in records[:30]
        ]
        markdown = f"# {title}\n\n" + "\n\n---\n\n".join(
            f"### {card['front']}\n\n{card['back']}" for card in cards
        )
        return markdown + self._footer(records[:30]), {"cards": cards}, []

    def _mind_map(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        """Gerçek kavram grafı: kök → bölüm kümeleri → ayırt edici kavramlar.

        Aynı kavram iki ayrı kümede geçiyorsa ``capraz`` kenarla bağlanır ve
        kanıtları birleşir — biyoloji müfredatındaki kavram ilişkileri tam da
        bu kesişimlerde yaşar. Her düğüm kanıt chunk kimliklerini taşır;
        arayüz tıklanınca kanıtı gösterir ve o kavramdan sohbet başlatabilir.
        """
        nodes: list[dict[str, Any]] = [
            {
                "id": "root",
                "label": title,
                "level": 0,
                "parent": None,
                "citation": records[0].citation,
                "citation_id": records[0].citation_id,
                "evidence_chunk_ids": [],
            }
        ]
        edges: list[dict[str, str]] = []
        kumeler: dict[str, list[StudioEvidence]] = {}
        for item in records[:24]:
            kumeler.setdefault(item.section or item.source_title, []).append(item)
        kavram_dugumleri: dict[str, dict[str, Any]] = {}
        for kume_sira, (baslik, kume) in enumerate(list(kumeler.items())[:10], 1):
            kume_id = f"k{kume_sira}"
            nodes.append(
                {
                    "id": kume_id,
                    "label": baslik,
                    "level": 1,
                    "parent": "root",
                    "citation": kume[0].citation,
                    "citation_id": kume[0].citation_id,
                    "evidence_chunk_ids": [item.citation_id for item in kume[:6]],
                }
            )
            edges.append({"source": "root", "target": kume_id, "kind": "hiyerarsi"})
            eklenen = 0
            for item in kume[:4]:
                if eklenen >= 4:
                    break
                for cumle in _sentences(item.text)[:3]:
                    terim = _belirgin_terim(cumle)
                    if len(terim) < 4:
                        continue
                    anahtar = terim.casefold()
                    mevcut = kavram_dugumleri.get(anahtar)
                    if mevcut is not None:
                        if mevcut["parent"] != kume_id:
                            edges.append(
                                {"source": kume_id, "target": mevcut["id"], "kind": "capraz"}
                            )
                            if item.citation_id not in mevcut["evidence_chunk_ids"]:
                                mevcut["evidence_chunk_ids"].append(item.citation_id)
                        continue
                    dugum = {
                        "id": f"{kume_id}t{eklenen + 1}",
                        "label": terim,
                        "level": 2,
                        "parent": kume_id,
                        "citation": item.citation,
                        "citation_id": item.citation_id,
                        "evidence_chunk_ids": [item.citation_id],
                    }
                    kavram_dugumleri[anahtar] = dugum
                    nodes.append(dugum)
                    edges.append(
                        {"source": kume_id, "target": dugum["id"], "kind": "hiyerarsi"}
                    )
                    eklenen += 1
                    if eklenen >= 4:
                        break
        # Mermaid temsili md export için korunur (geriye uyum).
        lines = ["mindmap", f"  root(({_mermaid_label(title)}))"]
        for node in nodes:
            if node["level"] == 1:
                etiket = _mermaid_label(str(node["label"]))
                lines.append(f"    {node['id']}[{etiket} {node['citation']}]")
        markdown = f"# {title}\n\n```mermaid\n" + "\n".join(lines) + "\n```"
        capraz = sum(1 for edge in edges if edge["kind"] == "capraz")
        if capraz:
            markdown += f"\n\n> {capraz} kavram birden çok bölümde geçiyor (çapraz bağlantı)."
        structured = {"nodes": nodes, "edges": edges}
        return markdown + self._footer(records[:24]), structured, []

    def _slides(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        """Gerçek slayt yapısı: başlık + maddeler + konuşmacı notu + kaynak dipnotu.

        Kanıtlar bölüm/kaynak başlığına göre kümelenir; her küme bir slayt olur.
        Maddeler kanıt cümleleridir (atıf alanlarıyla), konuşmacı notu kümenin
        ilk kanıtından gelir — LLM cilası maddeleri akıcılaştırabilir ama
        deterministik taban tek başına da derste kullanılabilir.
        """
        kumeler: dict[str, list[StudioEvidence]] = {}
        for item in records[:36]:
            anahtar = item.section or item.source_title
            kumeler.setdefault(anahtar, []).append(item)

        slides: list[dict[str, Any]] = [
            {
                "index": 1,
                "title": title,
                "bullets": [],
                "speaker_notes": (
                    f"{title} konulu ders sunumu. İçerik yalnız seçili "
                    "kaynaklara dayanır; her maddenin atıfı slaytında görünür."
                ),
                "kaynak_dipnotu": _source_note(records[0]),
                "citation": records[0].citation,
                "citation_id": records[0].citation_id,
            }
        ]
        for baslik, kume in list(kumeler.items())[:12]:
            bullets = [
                {
                    "text": _claim(item).removesuffix(f" {item.citation}"),
                    "citation": item.citation,
                    "citation_id": item.citation_id,
                }
                for item in kume[:4]
            ]
            notlar = _sentences(kume[0].text)[:3]
            slides.append(
                {
                    "index": len(slides) + 1,
                    "title": baslik,
                    "bullets": bullets,
                    "speaker_notes": " ".join(notlar),
                    "kaynak_dipnotu": "; ".join(
                        dict.fromkeys(_source_note(item) for item in kume[:4])
                    ),
                    "citation": kume[0].citation,
                    "citation_id": kume[0].citation_id,
                }
            )
        ozet_basliklari = [str(slide["title"]) for slide in slides[1:]]
        slides.append(
            {
                "index": len(slides) + 1,
                "title": "Özet",
                "bullets": [
                    {
                        "text": baslik,
                        "citation": slides[sira + 1]["citation"],
                        "citation_id": slides[sira + 1]["citation_id"],
                    }
                    for sira, baslik in enumerate(ozet_basliklari)
                ],
                "speaker_notes": "Bugün işlenen başlıkların kısa tekrarı.",
                "kaynak_dipnotu": "",
                "citation": records[0].citation,
                "citation_id": records[0].citation_id,
            }
        )
        markdown_parcalar = [f"# {title}"]
        for slide in slides:
            markdown_parcalar.append(f"\n## Slayt {slide['index']}: {slide['title']}\n")
            for bullet in slide["bullets"]:
                markdown_parcalar.append(f"- {bullet['text']} {bullet['citation']}")
            if slide["speaker_notes"]:
                markdown_parcalar.append(
                    f"\n> Konuşmacı notu: {slide['speaker_notes']}"
                )
        markdown = "\n".join(markdown_parcalar)
        structured = {"slides": slides, "suggested_formats": ["pptx", "pdf", "md"]}
        return markdown + self._footer(records[:36]), structured, []

    def _table(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        rows = [
            {
                "source": item.source_title,
                "section": item.section or "—",
                "finding": _claim(item),
                "citation": item.citation,
                "citation_id": item.citation_id,
            }
            for item in records[:50]
        ]
        markdown = f"# {title}\n\n| Kaynak | Bölüm | Bulgu |\n|---|---|---|\n" + "\n".join(
            f"| {_cell(row['source'])} | {_cell(row['section'])} | {_cell(row['finding'])} |"
            for row in rows
        )
        structured = {"columns": ["source", "section", "finding"], "rows": rows}
        return markdown + self._footer(records), structured, []

    def _ders_plani(
        self, title: str, records: list[StudioEvidence], options: dict[str, Any]
    ) -> tuple[str, dict[str, Any], list[str]]:
        """MEB günlük plan biçiminde ders planı.

        Kazanım kodları gömülü 2018 programı tablosundan gövde-örtüşmesiyle
        ÖNERİLİR; seçim ve doğrulama öğretmenindir (uyarı kalıcı). İşleniş
        gövdesi kanıt alıntılıdır, ölçme bölümü quiz üretecinden gelir.
        """
        from bioprof.studio.meb_kazanimlar import KAZANIMLAR, kazanim_oner

        sure = int(options.get("sure_dakika") or 40)
        sinif = options.get("sinif")
        sinif = int(sinif) if sinif else None
        istenen_kodlar = [str(kod) for kod in (options.get("kazanim_kodlari") or [])]
        if istenen_kodlar:
            kazanimlar = [item for item in KAZANIMLAR if item.kod in istenen_kodlar]
        else:
            kazanimlar = kazanim_oner(
                [item.text for item in records[:20]], sinif=sinif, adet=3
            )
        secilen = records[:10]
        ilk_cumleler = _sentences(secilen[0].text)
        giris_kavrami = _odak_ifadesi(ilk_cumleler[0] if ilk_cumleler else title)
        islenis_giris = (
            f"Derse '{title}' konusuna dikkat çeken bir soruyla başlanır: "
            f"\"{giris_kavrami} denince aklınıza ne geliyor?\" Ön bilgiler alınır."
        )
        gelisme = [
            {
                "text": _claim(item).removesuffix(f" {item.citation}"),
                "citation": item.citation,
                "citation_id": item.citation_id,
            }
            for item in secilen
        ]
        _, quiz_yapisi, _ = self._quiz(title, secilen[:6])
        olcme = quiz_yapisi["questions"][:3]
        plan = {
            "ders": "Biyoloji",
            "konu": title,
            "sinif": sinif or (kazanimlar[0].sinif if kazanimlar else None),
            "sure_dakika": sure,
            "kazanim_onerileri": [
                {"kod": item.kod, "sinif": item.sinif, "unite": item.unite, "metin": item.metin}
                for item in kazanimlar
            ],
            "yontem_teknikler": ["Soru-cevap", "Anlatım", "Tartışma", "Kavram haritası"],
            "arac_gerec": ["Ders kitabı", "Seçili kaynak dökümleri", "Tahta/projeksiyon"],
            "islenis": {
                "giris": islenis_giris,
                "gelisme": gelisme,
                "sonuc": (
                    "İşlenen kavramlar öğrencilere özetletilir; yanlış anlamalar "
                    "düzeltilir ve bir sonraki dersin konusuyla bağ kurulur."
                ),
            },
            "olcme_degerlendirme": olcme,
        }
        satirlar = [
            f"# Günlük Ders Planı — {title}",
            "",
            f"**Ders:** Biyoloji · **Sınıf:** {plan['sinif'] or '—'} · **Süre:** {sure} dk",
            "",
            "## Kazanımlar (öneri — öğretmen doğrulamalı)",
        ]
        satirlar += [
            f"- **{item.kod}** {item.metin or item.unite}" for item in kazanimlar
        ] or ["- (Eşleşen kazanım önerisi bulunamadı)"]
        satirlar += [
            "",
            f"## Yöntem ve Teknikler\n{', '.join(plan['yontem_teknikler'])}",
            "",
            f"## Araç ve Gereçler\n{', '.join(plan['arac_gerec'])}",
            "",
            "## İşleniş",
            f"**Giriş:** {islenis_giris}",
            "",
            "**Gelişme:**",
        ]
        satirlar += [f"- {madde['text']} {madde['citation']}" for madde in gelisme]
        satirlar += ["", f"**Sonuç:** {plan['islenis']['sonuc']}", "", "## Ölçme ve Değerlendirme"]
        for soru in olcme:
            satirlar.append(f"{soru['id']}. {soru['question']} {soru['citation']}")
        markdown = "\n".join(satirlar)
        return (
            markdown + self._footer(secilen),
            {"ders_plani": plan, "suggested_formats": ["docx", "pdf", "md"]},
            [
                "Kazanım kodları gömülü 2018 programı tablosundan ÖNERİDİR; "
                "resmî programla öğretmen doğrulamalıdır."
            ],
        )

    def _audio_lesson(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        segments = []
        opening = (
            f"{title} başlıklı BioProf sesli dersine hoş geldiniz. "
            "Bu anlatım yalnız seçili kaynaklara dayalı eğitim ve araştırma içeriğidir."
        )
        segments.append(
            {
                "index": 0,
                "text": opening,
                "citation": records[0].citation,
                "citation_id": records[0].citation_id,
            }
        )
        for index, item in enumerate(records[:18], 1):
            segments.append(
                {
                    "index": index,
                    "text": _claim(item).removesuffix(f" {item.citation}"),
                    "citation": item.citation,
                    "citation_id": item.citation_id,
                    "source_title": item.source_title,
                }
            )
        closing = "Dersi bitirirken, ayrıntılar için ekrandaki kaynak alıntılarını inceleyin."
        segments.append(
            {
                "index": len(segments),
                "text": closing,
                "citation": records[-1].citation,
                "citation_id": records[-1].citation_id,
            }
        )
        markdown = f"# {title}\n\n## Murat anlatım metni\n\n" + "\n\n".join(
            f"{segment['text']} {segment['citation']}" for segment in segments
        )
        structured = {
            "segments": segments,
            "voice": "Murat",
            "service": "seslab",
            "render_status": "needs_service",
            "suggested_formats": ["wav", "mp3"],
        }
        return (
            markdown + self._footer(records),
            structured,
            ["Ses oluşturmak için yerel SesLab ve Murat sesi hazır olmalıdır"],
        )

    def _audio_lecture(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        return self._audio_lesson(title, records)

    def _podcast(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        """LLM'siz kalıp senaryo; asıl senaryoyu ``PodcastScriptBuilder`` yazar."""
        from bioprof.studio.podcast import UZUNLUK_PRESETLERI, _iskelet, script_markdown

        segments = _iskelet(title, records, UZUNLUK_PRESETLERI["orta"])
        structured = {
            "segments": segments,
            "voices": {"emel": "emel", "mazlum": "Mazlum Kiper", "murat": "Murat"},
            "service": "seslab",
            "render_status": "needs_service",
            "suggested_formats": ["mp3", "wav", "srt"],
            "llm_polished": False,
        }
        return (
            script_markdown(title, segments) + self._footer(records),
            structured,
            ["Podcast sesi için yerel SesLab ve Emel, Mazlum Kiper, Murat sesleri hazır olmalıdır"],
        )

    def _video_overview(
        self, title: str, records: list[StudioEvidence]
    ) -> tuple[str, dict[str, Any], list[str]]:
        slides: list[dict[str, Any]] = []
        current = 0.0
        for index, item in enumerate(records[:12], 1):
            narration = _claim(item).removesuffix(f" {item.citation}")
            duration = max(5.0, min(18.0, len(narration) / 14.0))
            slides.append(
                {
                    "index": index,
                    "title": item.section or item.source_title,
                    "finding": narration,
                    "citation": item.citation,
                    "citation_id": item.citation_id,
                    "source_title": item.source_title,
                    "start": round(current, 3),
                    "end": round(current + duration, 3),
                }
            )
            current += duration
        markdown = f"# {title}\n\n## Video planı\n\n" + "\n\n".join(
            f"### {slide['index']}. {slide['title']}\n\n{slide['finding']} {slide['citation']}"
            for slide in slides
        )
        structured = {
            "slides": slides,
            "voice": "Murat",
            "speech_service": "seslab",
            "video_renderer": "pyav_optional",
            "render_status": "needs_service",
            "duration_seconds": round(current, 3),
        }
        return (
            markdown + self._footer(records[:12]),
            structured,
            ["MP4 anlatımı için SesLab gerekir; PyAV yoksa plan ve SRT yine dışa aktarılabilir"],
        )


def _cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def _mermaid_label(value: str) -> str:
    return re.sub(r"[\[\](){}\"'`]", "", value)[:100]


def _srt_time(seconds: float) -> str:
    milliseconds = max(0, round(seconds * 1000))
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, millis = divmod(remainder, 1_000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


Exporter = Callable[[StudioArtifact, Path], None]


class ArtifactExporter:
    """Extensible exporters; optional document libraries fail with guidance."""

    def __init__(self) -> None:
        self._exporters: dict[str, Exporter] = {
            "md": self._markdown,
            "json": self._json,
            "csv": self._csv,
            "html": self._html,
            "xlsx": self._xlsx,
            "docx": self._docx,
            "pptx": self._pptx,
            "pdf": self._pdf,
            "srt": self._srt,
            "manifest": self._media_manifest,
        }

    def register(self, format_name: str, exporter: Exporter) -> None:
        key = format_name.casefold().lstrip(".")
        if not re.fullmatch(r"[a-z0-9]+", key):
            raise StudioExportError("Invalid export format name")
        self._exporters[key] = exporter

    def formats(self) -> list[str]:
        return sorted(self._exporters)

    def export(self, artifact: StudioArtifact, destination: Path, *, format_name: str) -> Path:
        key = format_name.casefold().lstrip(".")
        exporter = self._exporters.get(key)
        if not exporter:
            raise StudioExportError(f"Unsupported export format: {format_name}")
        destination = destination.with_suffix(f".{key}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            exporter(artifact, destination)
        except StudioExportError:
            raise
        except Exception as exc:
            raise StudioExportError(f"{key.upper()} export failed: {exc}") from exc
        return destination

    @staticmethod
    def _atomic_bytes(path: Path, content: bytes) -> None:
        descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
        except Exception:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary)
            raise

    def _markdown(self, artifact: StudioArtifact, destination: Path) -> None:
        self._atomic_bytes(destination, artifact.content_markdown.encode("utf-8"))

    def _json(self, artifact: StudioArtifact, destination: Path) -> None:
        self._atomic_bytes(
            destination,
            json.dumps(artifact.model_dump(mode="json"), ensure_ascii=False, indent=2).encode(),
        )

    def _csv(self, artifact: StudioArtifact, destination: Path) -> None:
        rows = _rows(artifact)
        buffer = io.StringIO()
        columns = sorted({key for row in rows for key in row})
        writer = csv.writer(buffer)
        writer.writerow([_spreadsheet_cell(column) for column in columns])
        for row in rows:
            writer.writerow([_spreadsheet_cell(row.get(column)) for column in columns])
        self._atomic_bytes(destination, buffer.getvalue().encode("utf-8-sig"))

    def _html(self, artifact: StudioArtifact, destination: Path) -> None:
        body = "\n".join(
            f"<p>{html.escape(line)}</p>" if line else ""
            for line in artifact.content_markdown.splitlines()
        )
        document = (
            "<!doctype html><html lang='tr'><meta charset='utf-8'>"
            f"<title>{html.escape(artifact.title)}</title><body>{body}</body></html>"
        )
        self._atomic_bytes(destination, document.encode())

    def _xlsx(self, artifact: StudioArtifact, destination: Path) -> None:
        try:
            from openpyxl import Workbook  # type: ignore[import-untyped]
        except ImportError as exc:
            raise StudioExportError("XLSX export requires the optional openpyxl package") from exc
        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "BioProf"
        rows = _rows(artifact)
        columns = sorted({key for row in rows for key in row})
        sheet.append([_spreadsheet_cell(column) for column in columns])
        for row in rows:
            sheet.append([_spreadsheet_cell(row.get(column)) for column in columns])
        for cell in sheet[1]:
            font = copy(cell.font)
            font.bold = True
            cell.font = font
        workbook.save(destination)

    def _docx(self, artifact: StudioArtifact, destination: Path) -> None:
        try:
            from docx import Document
        except ImportError as exc:
            raise StudioExportError(
                "DOCX export requires the optional python-docx package"
            ) from exc
        document = Document()
        plan = artifact.structured_data.get("ders_plani")
        if artifact.kind == "ders_plani" and isinstance(plan, dict):
            # MEB günlük plan düzeni: üst bilgi tablosu + bölüm başlıkları.
            document.add_heading(f"Günlük Ders Planı — {plan.get('konu', artifact.title)}", level=0)
            tablo = document.add_table(rows=0, cols=2)
            tablo.style = "Table Grid"
            kazanim_metni = "\n".join(
                f"{item['kod']} {item['metin'] or item['unite']}"
                for item in plan.get("kazanim_onerileri", [])
            ) or "—"
            for etiket, deger in (
                ("Ders", plan.get("ders", "Biyoloji")),
                ("Konu", plan.get("konu", artifact.title)),
                ("Sınıf", str(plan.get("sinif") or "—")),
                ("Süre", f"{plan.get('sure_dakika', 40)} dakika"),
                ("Kazanımlar (öneri)", kazanim_metni),
                ("Yöntem-Teknikler", ", ".join(plan.get("yontem_teknikler", []))),
                ("Araç-Gereç", ", ".join(plan.get("arac_gerec", []))),
            ):
                hucre = tablo.add_row().cells
                hucre[0].text = etiket
                hucre[1].text = str(deger)
            islenis = plan.get("islenis", {})
            document.add_heading("İşleniş", level=1)
            document.add_paragraph(f"Giriş: {islenis.get('giris', '')}")
            for madde in islenis.get("gelisme", []):
                document.add_paragraph(
                    f"{madde.get('text', '')} {madde.get('citation', '')}",
                    style="List Bullet",
                )
            document.add_paragraph(f"Sonuç: {islenis.get('sonuc', '')}")
            document.add_heading("Ölçme ve Değerlendirme", level=1)
            for soru in plan.get("olcme_degerlendirme", []):
                document.add_paragraph(
                    f"{soru.get('id')}. {soru.get('question')} {soru.get('citation', '')}"
                )
            document.add_paragraph(
                "Not: Kazanım kodları öneridir; resmî programla öğretmen doğrulamalıdır."
            )
            document.save(str(destination))
            return
        document.add_heading(artifact.title, level=0)
        for line in artifact.content_markdown.splitlines()[1:]:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("## "):
                document.add_heading(stripped[3:], level=1)
            elif stripped.startswith("### "):
                document.add_heading(stripped[4:], level=2)
            elif stripped.startswith("- "):
                document.add_paragraph(stripped[2:], style="List Bullet")
            else:
                document.add_paragraph(stripped.replace("**", ""))
        document.save(str(destination))

    def _pptx(self, artifact: StudioArtifact, destination: Path) -> None:
        try:
            from pptx import Presentation
        except ImportError as exc:
            raise StudioExportError(
                "PPTX export requires the optional python-pptx package"
            ) from exc
        presentation = Presentation()
        yapili = artifact.structured_data.get("slides")
        if artifact.kind == "slides" and isinstance(yapili, list) and yapili:
            # Gerçek slayt yapısı: başlık + maddeler + konuşmacı notu +
            # küçük puntolu kaynak dipnotu. Eski satır-bölme yolu diğer
            # tipler için aynen aşağıda duruyor.
            from pptx.util import Pt

            for slide_data in yapili:
                bullets = list(slide_data.get("bullets") or [])
                layout = presentation.slide_layouts[1 if bullets else 0]
                slide = presentation.slides.add_slide(layout)
                slide.shapes.title.text = str(slide_data.get("title") or artifact.title)
                if bullets:
                    frame = slide.placeholders[1].text_frame
                    frame.clear()
                    for index, bullet in enumerate(bullets):
                        paragraph = (
                            frame.paragraphs[0] if index == 0 else frame.add_paragraph()
                        )
                        paragraph.text = (
                            f"{bullet.get('text', '')} {bullet.get('citation', '')}".strip()
                        )
                    dipnot = str(slide_data.get("kaynak_dipnotu") or "")
                    if dipnot:
                        son = frame.add_paragraph()
                        son.text = dipnot
                        son.font.size = Pt(10)
                else:
                    slide.placeholders[1].text = (
                        "BioProf · kaynaklı eğitim/araştırma çıktısı"
                    )
                notlar = str(slide_data.get("speaker_notes") or "")
                if notlar:
                    slide.notes_slide.notes_text_frame.text = notlar
            presentation.save(str(destination))
            return
        title_slide = presentation.slides.add_slide(presentation.slide_layouts[0])
        title_slide.shapes.title.text = artifact.title
        title_slide.placeholders[1].text = "BioProf · kaynaklı eğitim/araştırma çıktısı"
        chunks = [line for line in artifact.content_markdown.splitlines() if line.startswith("- ")]
        if not chunks:
            chunks = [_claim(item) for item in artifact.citations]
        for offset in range(0, min(len(chunks), 35), 5):
            slide = presentation.slides.add_slide(presentation.slide_layouts[1])
            slide.shapes.title.text = f"{artifact.title} · {offset // 5 + 1}"
            frame = slide.placeholders[1].text_frame
            frame.clear()
            for index, value in enumerate(chunks[offset : offset + 5]):
                paragraph = frame.paragraphs[0] if index == 0 else frame.add_paragraph()
                paragraph.text = value.removeprefix("- ")
        presentation.save(str(destination))

    def _pdf(self, artifact: StudioArtifact, destination: Path) -> None:
        try:
            from reportlab.lib.pagesizes import A4  # type: ignore[import-untyped]
            from reportlab.lib.styles import getSampleStyleSheet  # type: ignore[import-untyped]
            from reportlab.lib.utils import simpleSplit  # type: ignore[import-untyped]
            from reportlab.pdfgen import canvas  # type: ignore[import-untyped]
        except ImportError as exc:
            raise StudioExportError("PDF export requires the optional reportlab package") from exc
        pdf = canvas.Canvas(str(destination), pagesize=A4)
        width, height = A4
        styles = getSampleStyleSheet()
        y = height - 54
        for raw in artifact.content_markdown.replace("**", "").splitlines():
            text = raw.lstrip("#- ")
            if not text:
                y -= 8
                continue
            for line in simpleSplit(text, styles["BodyText"].fontName, 10, width - 90):
                if y < 54:
                    pdf.showPage()
                    y = height - 54
                pdf.setFont(styles["BodyText"].fontName, 10)
                pdf.drawString(45, y, line)
                y -= 14
        pdf.save()

    def _srt(self, artifact: StudioArtifact, destination: Path) -> None:
        if artifact.kind != "video_overview":
            raise StudioExportError("SRT export is only available for video overviews")
        entries = []
        for index, slide in enumerate(artifact.structured_data.get("slides", []), 1):
            interval = f"{_srt_time(float(slide['start']))} --> {_srt_time(float(slide['end']))}"
            entries.append(f"{index}\n{interval}\n{slide['finding']} {slide['citation']}\n")
        self._atomic_bytes(destination, "\n".join(entries).encode("utf-8"))

    def _media_manifest(self, artifact: StudioArtifact, destination: Path) -> None:
        if artifact.kind not in {"audio_lesson", "audio_lecture", "video_overview", "podcast"}:
            raise StudioExportError("Media manifest is only available for audio/video artifacts")
        payload = {
            "artifact_id": artifact.id,
            "kind": artifact.kind,
            "title": artifact.title,
            "pipeline": artifact.structured_data,
            "citations": [item.model_dump(mode="json") for item in artifact.citations],
        }
        self._atomic_bytes(
            destination, json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        )


def _rows(artifact: StudioArtifact) -> list[dict[str, Any]]:
    for key in ("rows", "faq", "terms", "events", "questions", "cards", "nodes", "bullets"):
        value = artifact.structured_data.get(key)
        if isinstance(value, list) and all(isinstance(item, dict) for item in value):
            return value
    return [
        {
            "label": item.label,
            "source": item.source_title,
            "citation_id": item.citation_id,
            "text": item.text,
        }
        for item in artifact.citations
    ]


def _scalar(value: Any) -> str | int | float | bool | None:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return json.dumps(value, ensure_ascii=False)


def _spreadsheet_cell(value: Any) -> str | int | float | bool | None:
    """Force attacker-controlled formula-like strings to remain inert cell data."""

    scalar = _scalar(value)
    if not isinstance(scalar, str):
        return scalar
    probe = scalar.lstrip()
    if probe.startswith(("=", "+", "-", "@")) or scalar.startswith(("\t", "\r", "\n")):
        return f"'{scalar}"
    return scalar


class MediaRenderResult(BaseModel):
    artifact_id: str
    status: Literal["completed", "completed_with_sidecar", "needs_service"]
    files: list[str] = Field(default_factory=list)
    media_types: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


SynthesizerCallback = Callable[[str, str, bool], Awaitable[tuple[bytes, str]]]
# (wav parçaları, aralık ms, biçim) -> ustalanmış ses; None ise ham birleştirme.
MasteringCallback = Callable[[list[bytes], int, str], Awaitable["MasteredAudio | None"]]


@dataclass(slots=True)
class MasteredAudio:
    data: bytes
    metadata: dict[str, Any] = field(default_factory=dict)
ProgressCallback = Callable[[float, str], Awaitable[None]]
# Türkçe konuşma pratikte ~14-16 karakter/saniye; bu tavan hızlı okuma için
# bile fazlasıyla cömert, yani yalnız gerçekten kesilmiş sesi yakalar.
_AZAMI_KARAKTER_HIZI = 40.0
# Bir replik için seslendirme denemesi (zaman aşımı ve kesik/sessiz ses dahil).
_SES_DENEME = 3
# Denemeler arası bekleme. XTTS ses değiştirirken worker havuzunu yeniden
# doğuruyor (30-60 sn) ve bu pencerede gelen isteklere 500 dönüyor; ardışık ve
# hızlı denemeler bu pencerenin tamamına denk gelip repliği boşuna atlatıyordu.
_SES_BEKLEME = (6.0, 25.0)
# Bundan fazlası atlanırsa bölüm eksik sayılır ve iş kırmızı yanar.
_AZAMI_ATLAMA_ORANI = 0.15


def _wav_duration(chunk: bytes) -> float:
    try:
        with wave.open(io.BytesIO(chunk), "rb") as source:
            rate = source.getframerate()
            return source.getnframes() / rate if rate else 0.0
    except (wave.Error, EOFError):
        return 0.0


def _wav_is_silent(chunk: bytes, *, threshold: int = 64) -> bool:
    """Doğru süreli ama tamamen sessiz WAV'ı yakalar.

    Süre kapıları böyle bir dosyayı geçirir: uzunluk beklendiği gibidir, ses
    yoktur. Motor bir repliği üretemediğinde tam boyda sessizlik döndürmesi
    gözlenmiş bir davranış olduğu için genlik ayrıca ölçülür.
    """
    try:
        with wave.open(io.BytesIO(chunk), "rb") as source:
            if source.getsampwidth() != 2 or source.getcomptype() != "NONE":
                return False  # yalnız 16-bit PCM ölçülebilir; diğerleri elenmez
            frames = source.readframes(source.getnframes())
    except (wave.Error, EOFError):
        return False
    if not frames:
        return True
    peak = max(
        abs(int.from_bytes(frames[index : index + 2], "little", signed=True))
        for index in range(0, len(frames) - 1, 2)
    )
    return peak < threshold


def _mp3_duration(data: bytes) -> float:
    """MPEG çerçeve başlıklarını sayarak süre çıkarır (bağımlılıksız).

    Amaç tam süre değil, yarıda kesilmiş kodlamayı yakalamak.
    """
    # MPEG-1 ile MPEG-2/2.5 hem bit hızı tablosunu hem çerçeve başına örnek
    # sayısını değiştirir. SesLab 24 kHz üretiyor, yani MPEG-2: MPEG-1 tablosu
    # kullanılırsa süre tam iki katı çıkıyordu.
    bitrates_v1 = (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0)
    bitrates_v2 = (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0)
    rates_v1 = {0: 44100, 1: 48000, 2: 32000}
    rates_v2 = {0: 22050, 1: 24000, 2: 16000}
    rates_v25 = {0: 11025, 1: 12000, 2: 8000}
    offset = 0
    if data[:3] == b"ID3" and len(data) > 10:
        size = 0
        for byte in data[6:10]:
            size = (size << 7) | (byte & 0x7F)
        offset = 10 + size
    total = 0.0
    limit = len(data) - 4
    while offset < limit:
        if data[offset] != 0xFF or (data[offset + 1] & 0xE0) != 0xE0:
            offset += 1
            continue
        version = (data[offset + 1] >> 3) & 0x03  # 3=MPEG-1, 2=MPEG-2, 0=MPEG-2.5
        header = data[offset + 2]
        index = (header >> 4) & 0x0F
        rate_index = (header >> 2) & 0x03
        if version == 3:
            bitrate = bitrates_v1[index] * 1000
            rate = rates_v1.get(rate_index)
            samples, coefficient = 1152, 144
        elif version == 2:
            bitrate = bitrates_v2[index] * 1000
            rate = rates_v2.get(rate_index)
            samples, coefficient = 576, 72
        elif version == 0:
            bitrate = bitrates_v2[index] * 1000
            rate = rates_v25.get(rate_index)
            samples, coefficient = 576, 72
        else:
            offset += 1
            continue
        if not bitrate or not rate:
            offset += 1
            continue
        padding = (header >> 1) & 0x01
        frame = int(coefficient * bitrate / rate) + padding
        if frame <= 0:
            offset += 1
            continue
        total += samples / rate
        offset += frame
    return total


def _silence_like(reference: bytes, milliseconds: int) -> bytes:
    """Referans WAV ile aynı PCM biçiminde sessizlik üretir."""
    with wave.open(io.BytesIO(reference), "rb") as source:
        channels, width, rate = (
            source.getnchannels(),
            source.getsampwidth(),
            source.getframerate(),
        )
    frames = int(rate * max(0, milliseconds) / 1000)
    target = io.BytesIO()
    with wave.open(target, "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(width)
        output.setframerate(rate)
        output.writeframes(b"\x00" * frames * channels * width)
    return target.getvalue()


def _srt_timestamp(seconds: float) -> str:
    milliseconds = int(round(seconds * 1000))
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    secs, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{milliseconds:03d}"


def _podcast_srt(
    planned: list[tuple[int, str, str]], durations: list[float], gap_ms: int
) -> str:
    names = {"murat": "Murat", "emel": "Emel", "mazlum": "Mazlum"}
    blocks: list[str] = []
    cursor = 0.0
    for order, ((_, speaker, text), duration) in enumerate(
        zip(planned, durations, strict=True), start=1
    ):
        start, end = cursor, cursor + duration
        blocks.append(
            f"{order}\n{_srt_timestamp(start)} --> {_srt_timestamp(end)}\n"
            f"{names.get(speaker, speaker)}: {text}\n"
        )
        cursor = end + gap_ms / 1000.0
    return "\n".join(blocks) + "\n"


class StudioMediaRenderer:
    """Injectable Murat synthesis and optional PyAV video rendering.

    The callable boundary avoids importing SesLab in Studio.  The application
    supplies a tiny adapter around ``SesLabAdapter.synthesize``.  Audio is
    requested as WAV and validated before concatenation; invalid or mismatched
    chunks never become a supposedly successful lesson.
    """

    async def render_audio(
        self,
        artifact: StudioArtifact,
        destination: Path,
        *,
        synthesizer: SynthesizerCallback | None,
        strict_verification: bool = False,
    ) -> MediaRenderResult:
        if artifact.kind not in {"audio_lesson", "audio_lecture", "video_overview"}:
            raise StudioExportError("Artifact has no narration script")
        if synthesizer is None:
            return MediaRenderResult(
                artifact_id=artifact.id,
                status="needs_service",
                warnings=["Yerel SesLab/Murat servisi kullanılamıyor"],
            )
        key = "slides" if artifact.kind == "video_overview" else "segments"
        segments = artifact.structured_data.get(key, [])
        texts = [
            str(item.get("finding") or item.get("text") or "").strip()
            for item in segments
            if isinstance(item, dict)
        ]
        texts = [item for item in texts if item]
        if not texts:
            raise StudioExportError("Narration script is empty")
        chunks: list[bytes] = []
        for text in texts:
            data, media_type = await synthesizer(text, "Murat", strict_verification)
            if media_type.split(";", 1)[0] not in {"audio/wav", "audio/x-wav"}:
                raise StudioExportError("Studio narration callback must return WAV audio")
            chunks.append(data)
        audio = _join_wav(chunks)
        destination = destination.with_suffix(".wav")
        destination.parent.mkdir(parents=True, exist_ok=True)
        ArtifactExporter._atomic_bytes(destination, audio)
        return MediaRenderResult(
            artifact_id=artifact.id,
            status="completed",
            files=[str(destination)],
            media_types=["audio/wav"],
        )

    async def render_podcast(
        self,
        artifact: StudioArtifact,
        destination: Path,
        *,
        synthesizer: SynthesizerCallback | None,
        mastering: MasteringCallback | None = None,
        progress: ProgressCallback | None = None,
        gap_ms: int = 320,
        retry_delays: tuple[float, ...] = _SES_BEKLEME,
    ) -> MediaRenderResult:
        """İki sesli podcast: konuşmacıya göre sentez, senaryo sırasında montaj.

        XTTS worker havuzu ses değişiminde yeniden doğduğu için (30-60 sn)
        replikler konuşmacıya göre gruplanır; sıra montajda segment kimliğine
        göre kurulur, üretim sırasına göre değil.
        """
        if artifact.kind != "podcast":
            raise StudioExportError("Only a podcast artifact can be rendered as a podcast")
        if synthesizer is None:
            return MediaRenderResult(
                artifact_id=artifact.id,
                status="needs_service",
                warnings=["Yerel SesLab servisi kullanılamıyor"],
            )
        segments = [
            item for item in artifact.structured_data.get("segments", []) if isinstance(item, dict)
        ]
        planned = [
            (int(item.get("index", order)), str(item.get("speaker") or "murat"), text)
            for order, item in enumerate(segments)
            if (text := str(item.get("text") or "").strip())
        ]
        if not planned:
            raise StudioExportError("Podcast senaryosu boş")

        warnings: list[str] = []
        rendered: dict[int, bytes] = {}
        done = 0
        # Konuşmacı başına tek checkpoint takası: her sesin tüm replikleri
        # arka arkaya sentezlenir. Replik replik geçiş, ses başına 30-60 sn
        # worker respawn demek olurdu.
        from bioprof.studio.podcast import SES_ADLARI

        speakers = [item[1] for item in planned]
        for speaker in dict.fromkeys(speakers):
            voice = SES_ADLARI.get(speaker, speaker)
            group = [item for item in planned if item[1] == speaker]
            for index, _, text in group:
                # Segment başına makullük: XTTS bir repliği sessizce yarıda
                # kesip milisaniyelik parça döndürebiliyor. Toplam süre kapısı
                # bunu göremez (toplam yine tutar), bu yüzden her replik ayrı
                # sınanır ve bir kez yeniden denenir.
                floor = len(text) / _AZAMI_KARAKTER_HIZI
                data = None
                for attempt in range(_SES_DENEME):
                    try:
                        data, media_type = await synthesizer(text, voice, False)
                    except Exception as exc:
                        # Uzun bölümlerde tek bir zaman aşımı bütün üretimi
                        # düşürüyordu: yüzlerce seslendirilmiş replik çöpe
                        # gidiyordu. Replik yeniden denenir, ısrar ederse
                        # atlanır ve iş devam eder.
                        if attempt + 1 < _SES_DENEME:
                            warnings.append(
                                f"{index}. replik seslendirilemedi "
                                f"({exc.__class__.__name__}), yeniden deneniyor."
                            )
                            data = None
                            await asyncio.sleep(retry_delays[min(attempt, len(retry_delays) - 1)])
                            continue
                        warnings.append(
                            f"{index}. replik atlandı: {exc.__class__.__name__}."
                        )
                        data = None
                        break
                    if media_type.split(";", 1)[0] not in {"audio/wav", "audio/x-wav"}:
                        raise StudioExportError("Podcast seslendirme çağrısı WAV döndürmeli")
                    if not data:
                        raise StudioExportError(
                            f"{voice} sesi {index}. replik için boş WAV döndürdü"
                        )
                    duration = _wav_duration(data)
                    sessiz = _wav_is_silent(data)
                    if duration >= floor and not sessiz:
                        break
                    if attempt + 1 >= _SES_DENEME:
                        sebep = (
                            "tamamen sessiz geldi"
                            if sessiz
                            else (
                                f"eksik seslendirildi: {len(text)} karakter için "
                                f"{duration:.2f} sn (en az {floor:.2f} sn beklenir)"
                            )
                        )
                        raise StudioExportError(f"{index}. replik ({voice}) {sebep}")
                    warnings.append(
                        f"{index}. replik {'sessiz' if sessiz else 'kesik'} geldi, "
                        "yeniden seslendirildi."
                    )
                if data:
                    rendered[index] = data
                done += 1
                if progress is not None:
                    await progress(done / len(planned), f"{voice} seslendiriliyor")

        # Atlanan replikler senaryodan da düşer ki altyazı sesle hizalı kalsın.
        atlanan = [item for item in planned if item[0] not in rendered]
        if atlanan:
            if len(atlanan) > max(1, len(planned) * _AZAMI_ATLAMA_ORANI):
                raise StudioExportError(
                    f"{len(atlanan)}/{len(planned)} replik seslendirilemedi; "
                    "podcast eksik kalırdı"
                )
            warnings.append(
                f"{len(atlanan)} replik seslendirilemediği için bölümden çıkarıldı."
            )
            planned = [item for item in planned if item[0] in rendered]
        if not planned:
            raise StudioExportError("Hiçbir replik seslendirilemedi")

        ordered = [rendered[index] for index, _, _ in planned]
        durations = [_wav_duration(chunk) for chunk in ordered]

        audio: bytes | None = None
        mp3: bytes | None = None
        if mastering is not None:
            try:
                mastered = await mastering(ordered, gap_ms, "wav")
                if mastered is not None:
                    audio = mastered.data
                    # Mastering kenar sessizliğini kırpar; altyazı zaman
                    # damgaları ham TTS sürelerinden hesaplanırsa kayar.
                    reported = mastered.metadata.get("segment_durations")
                    if isinstance(reported, list) and len(reported) == len(ordered):
                        durations = [float(value) for value in reported]
                    else:
                        warnings.append(
                            "Mastering segment sürelerini bildirmedi; "
                            "altyazı zamanları ham seslerden hesaplandı."
                        )
                    encoded = await mastering(ordered, gap_ms, "mp3")
                    mp3 = encoded.data if encoded is not None else None
            except Exception as exc:  # SesLab ucu yoksa ya da hata verirse
                warnings.append(f"Mastering yapılamadı, ham birleştirme kullanıldı: {exc}")
                audio = None
                mp3 = None
        if audio is None:
            silence = _silence_like(ordered[0], gap_ms)
            joined: list[bytes] = []
            for position, chunk in enumerate(ordered):
                if position:
                    joined.append(silence)
                joined.append(chunk)
            audio = _join_wav(joined)
            # Uyarı, geri çağırımın varlığına değil sonucuna bakmalı: eski bir
            # SesLab'da uç 404 döndürüp None veriyor ve mastering sessizce
            # atlanmış oluyordu.
            warnings.append("SesLab mastering uygulanmadı; ses seviyesi eşitlenmedi.")

        # Sessiz kayıp kapısı: çıktı süresi parçaların toplamını tutmalı.
        expected = sum(durations) + (len(ordered) - 1) * gap_ms / 1000.0
        actual = _wav_duration(audio)
        if actual <= 0 or abs(actual - expected) > max(1.0, expected * 0.1):
            raise StudioExportError(
                f"Podcast süresi tutarsız: beklenen ~{expected:.1f} sn, üretilen {actual:.1f} sn"
            )
        if _wav_is_silent(audio):
            raise StudioExportError("Birleştirilen podcast sesi tamamen sessiz")

        destination.parent.mkdir(parents=True, exist_ok=True)
        files: list[str] = []
        media_types: list[str] = []
        if mp3:
            # MP3 birincil dosya olacağı için WAV'la aynı kapılardan geçmeli;
            # kodlama yarıda kesilirse doğru süreli WAV'ın yanında üç saniyelik
            # bir MP3 sessizce "tamamlanmış" sayılırdı.
            mp3_seconds = _mp3_duration(mp3)
            if mp3_seconds <= 0:
                warnings.append("MP3 süresi okunamadı; yalnız WAV yayımlandı.")
            elif abs(mp3_seconds - actual) > max(1.0, actual * 0.1):
                warnings.append(
                    f"MP3 süresi tutarsız ({mp3_seconds:.1f} sn ≠ {actual:.1f} sn); "
                    "yalnız WAV yayımlandı."
                )
            else:
                mp3_path = destination.with_suffix(".mp3")
                ArtifactExporter._atomic_bytes(mp3_path, mp3)
                files.append(str(mp3_path))
                media_types.append("audio/mpeg")
        wav_path = destination.with_suffix(".wav")
        ArtifactExporter._atomic_bytes(wav_path, audio)
        files.append(str(wav_path))
        media_types.append("audio/wav")

        srt_path = destination.with_suffix(".srt")
        srt_text = _podcast_srt(planned, durations, gap_ms)
        if srt_text.count("\n\n") < len(planned):
            raise StudioExportError("SRT altyazısı replik sayısıyla eşleşmiyor")
        ArtifactExporter._atomic_bytes(srt_path, srt_text.encode("utf-8"))
        files.append(str(srt_path))
        media_types.append("application/x-subrip")

        return MediaRenderResult(
            artifact_id=artifact.id,
            status="completed",
            files=files,
            media_types=media_types,
            warnings=warnings,
        )

    async def render_video(
        self,
        artifact: StudioArtifact,
        destination: Path,
        *,
        synthesizer: SynthesizerCallback | None,
        strict_verification: bool = False,
    ) -> MediaRenderResult:
        if artifact.kind != "video_overview":
            raise StudioExportError("Only a video_overview can be rendered as MP4")
        audio_result = await self.render_audio(
            artifact,
            destination.with_suffix(".narration.wav"),
            synthesizer=synthesizer,
            strict_verification=strict_verification,
        )
        if audio_result.status == "needs_service":
            return audio_result
        audio_path = Path(audio_result.files[0])
        destination = destination.with_suffix(".mp4")
        try:
            _render_mp4_with_pyav(artifact, destination, audio_path)
        except ImportError:
            srt_path = ArtifactExporter().export(
                artifact, destination.with_suffix(".srt"), format_name="srt"
            )
            return MediaRenderResult(
                artifact_id=artifact.id,
                status="completed_with_sidecar",
                files=[str(audio_path), str(srt_path)],
                media_types=["audio/wav", "application/x-subrip"],
                warnings=["PyAV/Pillow kurulmadığı için MP4 yerine WAV ve SRT üretildi"],
            )
        return MediaRenderResult(
            artifact_id=artifact.id,
            status="completed",
            files=[str(destination)],
            media_types=["video/mp4"],
        )


def _join_wav(chunks: list[bytes]) -> bytes:
    if not chunks:
        raise StudioExportError("No WAV chunks were produced")
    target = io.BytesIO()
    expected: tuple[int, int, int] | None = None
    frame_data: list[bytes] = []
    for chunk in chunks:
        try:
            with wave.open(io.BytesIO(chunk), "rb") as source:
                parameters = (source.getnchannels(), source.getsampwidth(), source.getframerate())
                if expected is None:
                    expected = parameters
                elif parameters != expected:
                    raise StudioExportError("Murat WAV chunks use incompatible PCM parameters")
                if source.getcomptype() != "NONE":
                    raise StudioExportError("Compressed WAV chunks are not supported")
                frames = source.readframes(source.getnframes())
                if not frames:
                    raise StudioExportError("SesLab returned an empty WAV chunk")
                frame_data.append(frames)
        except (wave.Error, EOFError) as exc:
            raise StudioExportError(f"SesLab returned an invalid WAV chunk: {exc}") from exc
    assert expected is not None
    with wave.open(target, "wb") as output:
        output.setnchannels(expected[0])
        output.setsampwidth(expected[1])
        output.setframerate(expected[2])
        for frames in frame_data:
            output.writeframes(frames)
    return target.getvalue()


def _render_mp4_with_pyav(artifact: StudioArtifact, destination: Path, audio_path: Path) -> None:
    try:
        import av  # type: ignore[import-not-found]
        import numpy as np
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        raise ImportError("PyAV, NumPy and Pillow are required") from exc
    with wave.open(str(audio_path), "rb") as wav:
        channels = wav.getnchannels()
        sample_width = wav.getsampwidth()
        sample_rate = wav.getframerate()
        raw_audio = wav.readframes(wav.getnframes())
    if sample_width != 2:
        raise StudioExportError("MP4 renderer currently requires 16-bit PCM Murat WAV")
    samples = np.frombuffer(raw_audio, dtype="<i2").reshape(-1, channels)
    mono = samples.astype(np.int32).mean(axis=1).clip(-32768, 32767).astype(np.int16)
    duration = len(mono) / sample_rate
    slides = artifact.structured_data.get("slides", [])
    if not slides:
        raise StudioExportError("Video overview has no slides")
    destination.parent.mkdir(parents=True, exist_ok=True)
    container = av.open(str(destination), mode="w")
    try:
        video = container.add_stream("libx264", rate=1)
        video.width = 1280
        video.height = 720
        video.pix_fmt = "yuv420p"
        audio = container.add_stream("aac", rate=48_000)
        audio.layout = "mono"
        font = ImageFont.load_default(size=32) if hasattr(ImageFont, "load_default") else None
        seconds_per_slide = max(1.0, duration / len(slides))
        for slide in slides:
            canvas = Image.new("RGB", (1280, 720), "#071421")
            draw = ImageDraw.Draw(canvas)
            draw.rounded_rectangle((55, 55, 1225, 665), radius=28, fill="#10283b")
            draw.text(
                (100, 105),
                str(slide.get("title", artifact.title))[:70],
                fill="#f6fbff",
                font=font,
            )
            lines = _wrap_text(str(slide.get("finding", "")), 72)[:8]
            draw.multiline_text((100, 205), "\n".join(lines), fill="#c8d9e8", spacing=16, font=font)
            draw.text((100, 610), str(slide.get("citation", "")), fill="#58dfb5", font=font)
            frame = av.VideoFrame.from_ndarray(np.asarray(canvas), format="rgb24")
            repeat = max(1, round(seconds_per_slide))
            for _ in range(repeat):
                for packet in video.encode(frame):
                    container.mux(packet)
        for packet in video.encode():
            container.mux(packet)
        source_frame = av.AudioFrame.from_ndarray(mono.reshape(1, -1), format="s16p", layout="mono")
        source_frame.sample_rate = sample_rate
        resampler = av.AudioResampler(format="fltp", layout="mono", rate=48_000)
        for resampled in resampler.resample(source_frame):
            for packet in audio.encode(resampled):
                container.mux(packet)
        for packet in audio.encode():
            container.mux(packet)
    finally:
        container.close()


def _wrap_text(value: str, width: int) -> list[str]:
    words = value.split()
    lines: list[str] = []
    current: list[str] = []
    for word in words:
        if current and len(" ".join([*current, word])) > width:
            lines.append(" ".join(current))
            current = [word]
        else:
            current.append(word)
    if current:
        lines.append(" ".join(current))
    return lines
