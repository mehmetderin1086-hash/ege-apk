"""Testler arası ortak fixture'lar.

Modül düzeyinde ağır/opsiyonel bağımlılık (cv2, PIL, fastapi) import edilmez;
görüntü üreten fixture'lar gövdede ``pytest.importorskip`` çağırır, böylece bu
bağımlılıklar kurulu olmayan ortamda toplama (collection) kırılmaz.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
)

ORNEK_YAML = Path(__file__).parent.parent / "ornekler" / "biyoloji_sinav.yaml"


def soru_yap(
    tip: SoruTipi = SoruTipi.BOSLUK_DOLDURMA,
    no: int = 1,
    puan: float = 10.0,
    metin: str = "Örnek soru",
    **anahtar_alanlari,
) -> Soru:
    """Tek satırda test sorusu üretir.

    ``anahtar_alanlari`` doğrudan :class:`CevapAnahtari`'na geçer; ``rubrik``
    içine dict verilirse otomatik :class:`RubrikKalemi`'ne çevrilir.
    """
    rubrik = anahtar_alanlari.pop("rubrik", [])
    rubrik = [RubrikKalemi(**r) if isinstance(r, dict) else r for r in rubrik]
    anahtar = CevapAnahtari(rubrik=rubrik, **anahtar_alanlari)
    return Soru(no=no, tip=tip, metin=metin, puan=puan, anahtar=anahtar)


@pytest.fixture
def ornek_sinav() -> Sinav:
    """Depoya kaydedilmiş örnek biyoloji sınavı (ornekler/biyoloji_sinav.yaml)."""
    return Sinav.yaml_yukle(ORNEK_YAML)


@pytest.fixture
def depo(tmp_path):
    """Geçici SQLite deposu."""
    from sinav_okur.depo import Depo

    return Depo(tmp_path / "test.db")


class SahteGomlemci:
    """Deterministik gömlemci: metni karakter histogramına gömer.

    Gerçek sentence-transformers modeline gerek kalmadan anlamsal katmanı
    tetikler; aynı sözcükleri paylaşan cevaplar yüksek kosinüs benzerliği verir.
    """

    def gom(self, metinler: list[str]) -> np.ndarray:
        vekt = np.zeros((len(metinler), 32), dtype=float)
        for i, metin in enumerate(metinler):
            for ch in metin.lower():
                vekt[i, ord(ch) % 32] += 1.0
        return vekt


@pytest.fixture
def sahte_gomlemci() -> SahteGomlemci:
    return SahteGomlemci()


def beyaz_sayfa(yukseklik: int = 1200, genislik: int = 850, renk: int = 255):
    """Düz renkli BGR sayfa (cv2 gerektirir)."""
    return np.full((yukseklik, genislik, 3), renk, np.uint8)


def basili_sayfa(sorular, yukseklik: int = 1200, genislik: int = 850, kutulu: bool = True):
    """Her soru için başlık + boş cevap kutusu içeren basılı sayfa üretir.

    Döner: ``(goruntu, kutu_gecmisi)`` — kutu_gecmisi her sorunun kutu üst-y
    pikselini tutar, çağıran taraf öğrenci "el yazısını" bu koordinatlara çizer.
    """
    import cv2

    goruntu = beyaz_sayfa(yukseklik, genislik)
    kutu_gecmisi = {}
    for sira, soru in enumerate(sorular):
        y = 100 + sira * 210
        cv2.putText(
            goruntu,
            f"{soru.no}. Biyoloji sorusu {soru.no}",
            (45, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 0, 0),
            2,
        )
        if kutulu:
            cv2.rectangle(goruntu, (45, y + 25), (805, y + 175), (0, 0, 0), 2)
        kutu_gecmisi[soru.no] = y + 25
    return goruntu, kutu_gecmisi


@pytest.fixture
def serbest_ortam(tmp_path, ornek_sinav):
    """Serbest akış için hazır ortam: kaydedilmiş sınav + ana sayfa + şablon.

    Döner: ``(depo, sinav, sablon, ana_yolu)``. Çağıran taraf ana sayfayı
    kopyalayıp "el yazısı" ekleyerek öğrenci kâğıdı üretir.
    """
    import cv2

    from sinav_okur.depo import Depo
    from sinav_okur.serbest import SerbestKutu, SerbestSablon

    veri = tmp_path / "sinav_okur_veri" / "sinavlar" / ornek_sinav.kimlik
    veri.mkdir(parents=True)
    goruntu, _ = basili_sayfa(ornek_sinav.sorular)
    ana_yolu = veri / "temiz-yazili.png"
    cv2.imwrite(str(ana_yolu), goruntu)

    sablon = SerbestSablon(
        sinav_kimlik=ornek_sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[
            SerbestKutu(
                soru.no,
                1,
                45 / 850,
                (100 + sira * 210 + 25) / 1200,
                760 / 850,
                150 / 1200,
            )
            for sira, soru in enumerate(ornek_sinav.sorular)
        ],
    )
    sablon_yolu = veri / f"{ornek_sinav.kimlik}_serbest.json"
    sablon.json_kaydet(sablon_yolu)
    yaml_yolu = veri / f"{ornek_sinav.kimlik}.yaml"
    ornek_sinav.yaml_kaydet(yaml_yolu)

    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(ornek_sinav)
    db.sinav_dosya_kaydet(
        ornek_sinav.kimlik,
        yaml_yolu=yaml_yolu,
        sablon_yolu=sablon_yolu,
        form_pdf_yolu=ana_yolu,
    )
    return db, ornek_sinav, sablon, ana_yolu


@pytest.fixture(autouse=True)
def yalitilmis_motor_sagligi(tmp_path_factory, monkeypatch):
    """Motor sağlık kaydı testler arasında ve gerçek kurulumdan yalıtılır.

    Kayıt kalıcı olduğu için yalıtılmazsa iki yönlü kirlenir: testler
    geliştiricinin gerçek dosyasını yazar, ve bir testin bıraktığı "paddle
    sağlıksız" kaydı sonraki testin motor listesini sessizce değiştirir.
    """
    dizin = tmp_path_factory.mktemp("motor-saglik")
    monkeypatch.setenv(
        "SINAV_OKUR_MOTOR_SAGLIK", str(dizin / "motor_saglik.json")
    )


@pytest.fixture(autouse=True)
def yalitilmis_claude_anahtari(tmp_path_factory, monkeypatch):
    """Gerçek Claude API anahtarı testlerden yalıtılır.

    Anahtar varsayılan konumda duruyorsa, ağı sahtelemeyi unutan bir test
    ücretli gerçek istek atardı. Anahtar yolu var olmayan bir dosyaya çevrilir
    ve ortam değişkeni silinir; anahtar isteyen test kendisi kurar.
    """
    dizin = tmp_path_factory.mktemp("claude-anahtar")
    monkeypatch.setenv(
        "SINAV_OKUR_CLAUDE_API_KEY_FILE", str(dizin / "claude-api.key")
    )
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
