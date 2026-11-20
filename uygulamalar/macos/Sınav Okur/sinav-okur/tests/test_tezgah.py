"""Altın örnek regresyon tezgâhı: üretim, ölçüm, süpürme ve gerileme farkı."""
from __future__ import annotations

import numpy as np

from sinav_okur.htr import YapayTaniyici
from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.tezgah import (
    altin_ornekleri_uret,
    anlik_goruntu_yaz,
    gerileme_karsilastir,
    kapsam_supurmesi,
    karakter_hata_orani,
    tezgah_calistir,
)


def _onayli_kagit(depo, sinav, kirp_yolu, metin="mitokondri", puan=5.0) -> int:
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=sinav.sorular[0].no,
                    tanima=TanimaSonucu(metin=metin, guven=0.9),
                    puan=PuanSonucu(
                        puan=puan, max_puan=sinav.sorular[0].puan, guven=0.9
                    ),
                    kirp_yolu=str(kirp_yolu),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
        yazar_grubu="yazar-01",
    )
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(kutu["id"], son_puan=puan, incele=False)
    depo.kagit_onayla(kagit_id)
    return kagit_id


def test_karakter_hata_orani() -> None:
    assert karakter_hata_orani("mitokondri", "mitokondri") == 0.0
    assert karakter_hata_orani("", "") == 0.0
    assert karakter_hata_orani("", "x") == 1.0
    assert 0.0 < karakter_hata_orani("mitokondri", "rnitokondn") < 1.0


def test_altin_uret_onayli_kagittan_ve_cift_kayit_yok(
    depo, ornek_sinav, tmp_path
) -> None:
    depo.sinav_kaydet(ornek_sinav)
    kirp = tmp_path / "soru_1.png"
    kirp.write_bytes(b"x")
    _onayli_kagit(depo, ornek_sinav, kirp)
    ilk = altin_ornekleri_uret(depo)
    tekrar = altin_ornekleri_uret(depo)
    assert ilk["eklenen"] == 1
    assert tekrar["eklenen"] == 0  # aynı kırpıntı ikinci kez eklenmez
    assert tekrar["toplam"] == 1


def test_altin_ornek_sonraki_duzeltmeyle_guncellenir(
    depo, ornek_sinav, tmp_path
) -> None:
    depo.sinav_kaydet(ornek_sinav)
    kirp = tmp_path / "soru_1.png"
    kirp.write_bytes(b"x")
    kagit_id = _onayli_kagit(depo, ornek_sinav, kirp, metin="ilk okuma")
    altin_ornekleri_uret(depo)
    # Öğretmen etiketi sonradan düzeltir; altın set eski etikette kalmamalı.
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(kutu["id"], duzeltilmis_metin="doğru metin")
    depo.kagit_onayla(kagit_id)
    tekrar = altin_ornekleri_uret(depo)
    assert tekrar["guncellenen"] == 1
    assert depo.altin_ornekler()[0]["beklenen_metin"] == "doğru metin"


def test_tezgah_calistir_metrikleri(depo, ornek_sinav, tmp_path) -> None:
    depo.sinav_kaydet(ornek_sinav)
    kirp = tmp_path / "soru_1.png"
    kirp.write_bytes(b"x")
    _onayli_kagit(depo, ornek_sinav, kirp, metin="hücre zarı")
    altin_ornekleri_uret(depo)
    sonuc = tezgah_calistir(
        depo,
        YapayTaniyici(metin="hücre zarı", guven=0.97),
        gorsel_yukleyici=lambda yol: np.zeros((8, 8), np.uint8),
        taniyici_adi="yapay",
    )
    m = sonuc["metrikler"]
    assert m["ornek"] == 1
    assert m["ort_cer"] == 0.0
    assert m["tam_eslesme_orani"] == 1.0
    assert any("küçük" in u for u in sonuc["uyarilar"])
    assert any("yazar" in u.lower() for u in sonuc["uyarilar"])


def test_tezgah_eksik_kirpintiyi_raporlar(depo, ornek_sinav, tmp_path) -> None:
    depo.sinav_kaydet(ornek_sinav)
    kirp = tmp_path / "silinecek.png"
    kirp.write_bytes(b"x")
    _onayli_kagit(depo, ornek_sinav, kirp)
    altin_ornekleri_uret(depo)
    kirp.unlink()
    sonuc = tezgah_calistir(
        depo, YapayTaniyici(metin="x"),
        gorsel_yukleyici=lambda yol: np.zeros((8, 8), np.uint8),
    )
    assert sonuc["metrikler"]["ornek"] == 0
    assert len(sonuc["atlanan"]) == 1


def test_kapsam_supurmesi() -> None:
    satirlar = [
        {"guven": 0.95, "cer": 0.0, "tam_eslesme": True},
        {"guven": 0.55, "cer": 0.5, "tam_eslesme": False},
    ]
    sonuc = {s["esik"]: s for s in kapsam_supurmesi(satirlar, esikler=(0.5, 0.9))}
    assert sonuc[0.5]["kapsam"] == 1.0
    assert sonuc[0.9]["kapsam"] == 0.5
    assert sonuc[0.9]["ort_cer"] == 0.0


def test_perf_ozeti_taslaklardan_toplar(tmp_path) -> None:
    import json

    from sinav_okur.tezgah import perf_ozeti

    dizin = tmp_path / "serbest_taslaklar"
    (dizin / "a").mkdir(parents=True)
    (dizin / "a" / "taslak.json").write_text(
        json.dumps(
            {
                "ocr_raporu": [
                    {"sayfa": 1, "motor": "vision", "sure_ms": 3000, "hata": ""},
                    {"sayfa": 1, "motor": "paddle", "sure_ms": 340000,
                     "hata": "SIGKILL"},
                    {"sayfa": 2, "motor": "vision", "sure_ms": 1000, "hata": ""},
                ]
            }
        ),
        encoding="utf-8",
    )
    (dizin / "bozuk").mkdir()
    (dizin / "bozuk" / "taslak.json").write_text("{bozuk", encoding="utf-8")
    ozet = perf_ozeti(dizin)
    assert ozet["taslak_sayisi"] == 1
    assert ozet["sayfa_sayisi"] == 2
    assert ozet["ort_sayfa_ms"] == round((343000 + 1000) / 2)
    motorlar = {m["motor"]: m for m in ozet["motorlar"]}
    assert motorlar["vision"]["istek"] == 2
    assert motorlar["vision"]["ort_ms"] == 2000
    assert motorlar["paddle"]["hata"] == 1
    assert ozet["motorlar"][0]["motor"] == "paddle"  # toplam süreye göre sıralı


def test_gerileme_uyarisi_ve_anlik_goruntu(tmp_path) -> None:
    eski = {
        "taniyici": "yapay",
        "zaman": "2026-08-05T10:00:00",
        "metrikler": {"ort_cer": 0.10, "tam_eslesme_orani": 0.90},
    }
    yeni = {
        "taniyici": "yapay",
        "metrikler": {"ort_cer": 0.20, "tam_eslesme_orani": 0.80},
    }
    fark = gerileme_karsilastir(eski, yeni)
    assert len(fark["gerilemeler"]) == 2
    # Farklı tanıyıcıyla karşılaştırma yapılmaz (elmayla armut).
    assert gerileme_karsilastir({**eski, "taniyici": "vision"}, yeni) == {
        "onceki": None, "gerilemeler": [],
    }
    # Anlık görüntü zinciri: ikinci yazım öncekiyle karşılaştırılır.
    ilk_sonuc = {
        "taniyici": "yapay",
        "zaman": "a",
        "metrikler": {"ort_cer": 0.0, "tam_eslesme_orani": 1.0},
    }
    anlik_goruntu_yaz(tmp_path / "olcumler", ilk_sonuc)
    ikinci = anlik_goruntu_yaz(
        tmp_path / "olcumler",
        {
            "taniyici": "yapay",
            "zaman": "b",
            "metrikler": {"ort_cer": 0.5, "tam_eslesme_orani": 0.4},
        },
    )
    import json

    veri = json.loads(ikinci.read_text(encoding="utf-8"))
    assert veri["karsilastirma"]["gerilemeler"]
