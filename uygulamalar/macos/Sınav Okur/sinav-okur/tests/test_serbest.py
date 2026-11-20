import json
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from sinav_okur import serbest
from sinav_okur.depo import Depo
from sinav_okur.htr import YapayTaniyici
from sinav_okur.modeller import CevapAnahtari, RubrikKalemi, Sinav, Soru, SoruTipi
from sinav_okur.ocr import OCRMotorSonucu, bloklari_birlestir
from sinav_okur.serbest import (
    OCRBlogu,
    SerbestKutu,
    SerbestSablon,
    SerbestTaslak,
    SerbestTaslakSorusu,
    serbest_kagit_isle,
    sorulari_bul,
)
from sinav_okur.webapp import uygulama_kur


def _blok(metin, x, y, w=0.35, h=0.02, guven=0.95):
    return OCRBlogu(
        text=metin,
        confidence=guven,
        x=x,
        y=y,
        width=w,
        height=h,
    )


def test_ocr_toplulugu_turkce_uzlasmayi_ve_alternatifleri_saklar():
    vision = OCRMotorSonucu(
        "vision",
        [_blok("3. Hücrenin enerji santralı nedir?", 0.08, 0.10, guven=0.78)],
    )
    vision.blocks[0].motor = "vision"
    paddle = OCRMotorSonucu(
        "paddle",
        [_blok("3. Hücrenin enerji santrali nedir?", 0.08, 0.10, guven=0.96)],
    )
    paddle.blocks[0].motor = "paddle"
    easy = OCRMotorSonucu(
        "easyocr",
        [_blok("3. Hucrenin enerji santrali nedir?", 0.08, 0.10, guven=0.88)],
    )
    easy.blocks[0].motor = "easyocr"

    sonuc = bloklari_birlestir([vision, paddle, easy])

    assert sonuc[0].text == "3. Hücrenin enerji santrali nedir?"
    assert {a["motor"] for a in sonuc[0].alternatives} == {
        "vision",
        "paddle",
        "easyocr",
    }
    assert sonuc[0].motor == "topluluk"


def test_ocr_toplulugu_surya_paragrafini_satir_penceresine_indirger():
    anchor = _blok(
        "2) Hücrenin enerji organeli nedir? Puan: 10",
        0.08,
        0.20,
        w=0.75,
        guven=0.91,
    )
    anchor.motor = "vision"
    paragraf = _blok(
        "1) Hücre nedir? Puan: 10 "
        "2) Hücrenin enerji organeli nedir? Puan: 10 "
        "3) Kloroplastın görevini yazınız. Puan: 10",
        0.06,
        0.16,
        w=0.88,
        h=0.18,
        guven=0.99,
    )
    paragraf.motor = "surya"

    sonuc = bloklari_birlestir(
        [OCRMotorSonucu("vision", [anchor]), OCRMotorSonucu("surya", [paragraf])]
    )

    surya = next(a for a in sonuc[0].alternatives if a["motor"] == "surya")
    assert surya["metin"] == "2) Hücrenin enerji organeli nedir? Puan: 10"


def test_trocr_ortami_kurulu_degilse_sessiz_hata(monkeypatch, tmp_path):
    from sinav_okur import ocr as ocr_mod

    monkeypatch.setattr(ocr_mod, "_trocr_hazir", lambda: False)

    sonuc = ocr_mod._trocr_ocr(tmp_path / "yok.png", [])

    assert not sonuc.basarili
    assert sonuc.hata == "Motor ortamı kurulu değil."


def test_trocr_yerel_model_kesfi(monkeypatch, tmp_path):
    from sinav_okur.htr.trocr import yerel_model_yolu

    monkeypatch.delenv("SINAV_OKUR_TROCR_MODEL", raising=False)
    assert yerel_model_yolu(tmp_path) is None

    model_dizini = tmp_path / "modeller" / "trocr-tr"
    model_dizini.mkdir(parents=True)
    (model_dizini / "config.json").write_text("{}")
    assert yerel_model_yolu(tmp_path) == str(model_dizini)

    monkeypatch.setenv("SINAV_OKUR_TROCR_MODEL", "/ozel/model")
    assert yerel_model_yolu(tmp_path) == "/ozel/model"


def test_trocr_oncu_motor_yoksa_hata_doner(monkeypatch, tmp_path):
    from sinav_okur import ocr as ocr_mod

    monkeypatch.setattr(ocr_mod, "_trocr_hazir", lambda: True)

    sonuc = ocr_mod._trocr_ocr(tmp_path / "sayfa.png", [])

    assert not sonuc.basarili
    assert "öncü motor" in sonuc.hata


def test_coklu_ocr_akilli_belirsizlikte_trocr_oncekileri_alir(monkeypatch, tmp_path):
    from sinav_okur import ocr as ocr_mod

    calisanlar = []
    trocr_girdileri = []

    def sahte_alt_surec(motor, gorsel, timeout):
        calisanlar.append(motor)
        return OCRMotorSonucu(motor=motor, hata="Motor ortamı kurulu değil.")

    def sahte_trocr(gorsel, sonuclar, azami_satir=80):
        calisanlar.append("trocr")
        trocr_girdileri.append([s.motor for s in sonuclar])
        return OCRMotorSonucu(motor="trocr", hata="Motor ortamı kurulu değil.")

    monkeypatch.setattr(ocr_mod, "_alt_surec_ocr", sahte_alt_surec)
    monkeypatch.setattr(ocr_mod, "_trocr_ocr", sahte_trocr)
    gorsel = tmp_path / "sayfa.png"
    gorsel.write_bytes(b"")

    ocr_mod.coklu_ocr(
        gorsel,
        vision_cagir=lambda yol: [_blok("okunaksız satır", 0.1, 0.1, guven=0.30)],
        soru_kontrolu=lambda metin: False,
        profil="akilli",
    )

    assert calisanlar == ["tesseract", "easyocr", "paddle", "trocr", "surya"]
    assert trocr_girdileri == [["vision", "tesseract", "easyocr", "paddle"]]


def test_trocr_oncu_satir_geometrisini_yeniden_okur(monkeypatch, tmp_path):
    from sinav_okur import ocr as ocr_mod
    from sinav_okur.modeller import TanimaSonucu

    class SahteTaniyici:
        def kutu_taniy(self, kirp, dpi=300):
            assert kirp.size > 0
            return TanimaSonucu(metin="mitokondri  üretir\n", guven=0.93)

    monkeypatch.setattr(ocr_mod, "_trocr_hazir", lambda: True)
    monkeypatch.setattr(ocr_mod, "_TROCR_TANIYICI", SahteTaniyici())
    gorsel = tmp_path / "sayfa.png"
    cv2.imwrite(str(gorsel), np.full((400, 300, 3), 255, np.uint8))
    vision = OCRMotorSonucu(
        "vision", [_blok("mitokondn uretir", 0.10, 0.20, w=0.5, h=0.05)]
    )

    sonuc = ocr_mod._trocr_ocr(gorsel, [vision])

    assert sonuc.basarili
    blok = sonuc.blocks[0]
    assert blok.text == "mitokondri üretir"
    assert blok.motor == "trocr"
    assert (blok.x, blok.y, blok.width, blok.height) == (0.10, 0.20, 0.5, 0.05)


def test_trocr_el_yazisi_okumasi_toplulukta_kazanir():
    vision = OCRMotorSonucu(
        "vision", [_blok("mitokondrı enerji üretır", 0.08, 0.30, guven=0.42)]
    )
    vision.blocks[0].motor = "vision"
    trocr = OCRMotorSonucu(
        "trocr", [_blok("mitokondri enerji üretir", 0.08, 0.30, guven=0.95)]
    )
    trocr.blocks[0].motor = "trocr"

    sonuc = bloklari_birlestir([vision, trocr])

    assert sonuc[0].text == "mitokondri enerji üretir"
    assert {a["motor"] for a in sonuc[0].alternatives} == {"vision", "trocr"}


def test_trocr_ilgisiz_yuksek_guvenle_toplulugu_ele_geciremez():
    vision = OCRMotorSonucu(
        "vision", [_blok("kavanozda sinekler gözlenir", 0.08, 0.30, guven=0.62)]
    )
    vision.blocks[0].motor = "vision"
    trocr = OCRMotorSonucu(
        "trocr", [_blok("nöron karbonhidrat retikulum", 0.08, 0.30, guven=0.92)]
    )
    trocr.blocks[0].motor = "trocr"

    sonuc = bloklari_birlestir([vision, trocr])

    assert sonuc[0].text == "kavanozda sinekler gözlenir"
    assert {a["motor"] for a in sonuc[0].alternatives} == {"vision", "trocr"}


def test_coklu_ocr_tam_denetim_profili_trocr_dahil_calistirir(monkeypatch, tmp_path):
    from sinav_okur import ocr as ocr_mod

    calisanlar = []

    def sahte_alt_surec(motor, gorsel, timeout):
        calisanlar.append(motor)
        return OCRMotorSonucu(motor=motor, hata="Motor ortamı kurulu değil.")

    def sahte_trocr(gorsel, sonuclar, azami_satir=80):
        calisanlar.append("trocr")
        return OCRMotorSonucu(motor="trocr", hata="Motor ortamı kurulu değil.")

    monkeypatch.setattr(ocr_mod, "_alt_surec_ocr", sahte_alt_surec)
    monkeypatch.setattr(ocr_mod, "_trocr_ocr", sahte_trocr)
    gorsel = tmp_path / "sayfa.png"
    gorsel.write_bytes(b"")

    _, rapor = ocr_mod.coklu_ocr(
        gorsel,
        vision_cagir=lambda yol: [_blok("1. Soru nedir?", 0.1, 0.1)],
        soru_kontrolu=lambda metin: True,
        profil="besli",
    )

    assert calisanlar == ["tesseract", "easyocr", "paddle", "surya", "trocr"]
    assert {r["motor"] for r in rapor} == {
        "vision",
        "tesseract",
        "easyocr",
        "paddle",
        "surya",
        "trocr",
    }


def test_sorulari_bul_tek_ve_cift_sutun_puanlari_okur():
    bloklar = [
        _blok("soru-4 )15 PUAN", 0.08, 0.10),
        _blok("ATP molekülünün kısımlarını yazınız.", 0.08, 0.14),
        _blok("soru-5= 10 PUAN", 0.58, 0.10),
        _blok("Fotosentez deneyini açıklayınız.", 0.58, 0.14),
        _blok("soru 6- ) 30PUAN", 0.08, 0.48),
        _blok("Kloroplast şemasını doldurunuz.", 0.08, 0.52),
    ]

    sorular = sorulari_bul(bloklar, sayfa=1)

    assert [(s.no, s.puan) for s in sorular] == [(4, 15.0), (5, 10.0), (6, 30.0)]
    assert sorular[0].kutu.x < 0.5
    assert sorular[1].kutu.x == 0.5
    assert sorular[0].kutu.height < sorular[2].kutu.y


def test_acik_soru_basliklari_alt_maddeleri_yeni_soru_saymaz():
    bloklar = [
        _blok("Soru 1: (20 Puan) Altı belgeyi yorumlayınız.", 0.08, 0.10, w=0.8),
        _blok("1) Mikrop teorisi belgesi", 0.08, 0.15, w=0.8),
        _blok("2) Hücrenin keşfi belgesi", 0.08, 0.20, w=0.8),
        _blok("Soru 2: (20 Puan) Deneyi açıklayınız.", 0.08, 0.40, w=0.8),
        _blok("1) Açık kavanoz", 0.08, 0.45, w=0.8),
        _blok("2) Kapalı kavanoz", 0.08, 0.50, w=0.8),
    ]

    sorular = sorulari_bul(bloklar, sayfa=1)

    assert [s.no for s in sorular] == [1, 2]
    assert "Hücrenin keşfi" in sorular[0].metin
    assert "Kapalı kavanoz" in sorular[1].metin
    assert round(sorular[0].kutu.y + sorular[0].kutu.height, 6) == 0.40


def test_serbest_kagit_ana_sayfayi_cikarip_incelemeye_gonderir(tmp_path):
    ana = np.full((900, 700, 3), 255, np.uint8)
    for i in range(12):
        cv2.putText(
            ana,
            f"{i + 1}. Biyoloji sorusu ve basilmis metin",
            (45, 70 + i * 60),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (0, 0, 0),
            2,
        )
    ogrenci = ana.copy()
    cv2.putText(
        ogrenci,
        "mitokondri",
        (100, 420),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX,
        1.1,
        (80, 20, 10),
        2,
    )
    ana_yolu = tmp_path / "ana.png"
    ogrenci_yolu = tmp_path / "ogrenci.png"
    cv2.imwrite(str(ana_yolu), ana)
    cv2.imwrite(str(ogrenci_yolu), ogrenci)
    sinav = Sinav(
        kimlik="SERBEST-1",
        baslik="Serbest",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Organeli yazınız.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("mitokondri", 10)],
                    ornek_cevap="mitokondri",
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.04, 0.25, 0.92, 0.45)],
    )

    sonuc = serbest_kagit_isle(
        ogrenci_yolu,
        sinav,
        sablon,
        YapayTaniyici("mitokondri", 0.9),
        kirp_dizini=tmp_path / "kirp",
    )

    assert len(sonuc.kutular) == 1
    assert sonuc.kutular[0].tanima.metin == "mitokondri"
    assert sonuc.kutular[0].puan.incele is True
    assert Path(sonuc.kutular[0].kirp_yolu).is_file()


def test_serbest_cevapli_sablonda_ocr_dener_ama_dusuk_guvenle_inceletir(tmp_path):
    ana = np.full((700, 500, 3), 255, np.uint8)
    cv2.putText(
        ana,
        "1. Basilmis soru",
        (40, 100),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 0, 0),
        2,
    )
    cv2.putText(
        ana,
        "elle cevap",
        (80, 260),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX,
        1.0,
        (50, 50, 50),
        2,
    )
    ana_yolu = tmp_path / "cevapli-ana.png"
    cv2.imwrite(str(ana_yolu), ana)
    sinav = Sinav(
        kimlik="AYNI-1",
        baslik="Aynı sayfa",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Soruyu yanıtlayınız.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("cevap", 10)],
                    ornek_cevap="cevap",
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.04, 0.10, 0.92, 0.50)],
    )

    sonuc = serbest_kagit_isle(
        ana_yolu,
        sinav,
        sablon,
        YapayTaniyici("yanlış otomatik metin", 1.0),
        kirp_dizini=tmp_path / "kirp",
    )

    kutu = sonuc.kutular[0]
    assert kutu.tanima.metin == "yanlış otomatik metin"
    assert kutu.tanima.guven <= 0.62
    assert kutu.puan.incele is True
    assert any("ana şablonla aynı" in uyari for uyari in sonuc.uyarilar)
    kayitli = cv2.imread(kutu.kirp_yolu, cv2.IMREAD_GRAYSCALE)
    assert kayitli is not None
    assert float(kayitli.mean()) < 254.0


def test_serbest_karisik_on_arka_sayfalari_esler_ve_tek_soruda_birlestirir(
    tmp_path,
):
    sayfalar = []
    for no in (1, 2):
        ana = np.full((800, 600, 3), 255, np.uint8)
        rng = np.random.default_rng(1000 + no)
        for _ in range(70):
            x, y = rng.integers([20, 20], [580, 780])
            yaricap = int(rng.integers(2, 12))
            cv2.circle(ana, (int(x), int(y)), yaricap, (0, 0, 0), -1)
        for i in range(12):
            cv2.putText(
                ana,
                f"SAYFA {no} SATIR {i} Biyoloji deney yontem",
                (30, 50 + i * 55),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 0, 0),
                1,
            )
        cv2.circle(ana, (100 + no * 120, 720), 35 + no * 4, (0, 0, 0), 3)
        yol = tmp_path / f"ana-{no}.png"
        cv2.imwrite(str(yol), ana)
        sayfalar.append(yol)
    sinav = Sinav(
        kimlik="ON-ARKA",
        baslik="Ön arka",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Yöntemi açıklayın.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("doğru yöntem", 10)],
                    ornek_cevap="doğru yöntem",
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(p) for p in sayfalar],
        kutular=[
            SerbestKutu(1, 1, 0.05, 0.10, 0.90, 0.25),
            SerbestKutu(1, 2, 0.05, 0.10, 0.90, 0.25),
        ],
    )

    sonuc = serbest_kagit_isle(
        [sayfalar[1], sayfalar[0]],
        sinav,
        sablon,
        YapayTaniyici("doğru yöntem", 0.9),
        kirp_dizini=tmp_path / "kirp-cok",
    )

    assert sonuc.islenen_sayfalar == [1, 2]
    assert len(sonuc.kutular) == 1
    assert sonuc.kutular[0].puan.max_puan == 10
    assert "2 bölge" in sonuc.kutular[0].puan.detaylar[-1]
    assert any("görsel içeriğe göre" in u for u in sonuc.uyarilar)


def _cok_sayfali_sinav_ve_sablon(tmp_path):
    sayfalar = []
    for no in (1, 2):
        ana = np.full((800, 600, 3), 255, np.uint8)
        for i in range(12):
            cv2.putText(ana, f"SAYFA {no} SATIR {i} deney", (30, 50 + i * 55),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 1)
        yol = tmp_path / f"ana-{no}.png"
        cv2.imwrite(str(yol), ana)
        sayfalar.append(yol)
    sinav = Sinav(
        kimlik="ON-ARKA-MOD", baslik="x",
        sorular=[Soru(no=1, tip=SoruTipi.ACIK_UCLU, metin="Yöntem?", puan=10,
                      anahtar=CevapAnahtari(rubrik=[RubrikKalemi("doğru yöntem", 10)],
                                            ornek_cevap="doğru yöntem"))],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik, dpi=200,
        sayfa_gorselleri=[str(p) for p in sayfalar],
        kutular=[SerbestKutu(1, 1, 0.05, 0.10, 0.90, 0.25),
                 SerbestKutu(1, 2, 0.05, 0.10, 0.90, 0.25)],
    )
    return sinav, sablon, sayfalar


def test_birlesik_kutu_kapali_modda_kapi_cagirmaz(tmp_path):
    sinav, sablon, sayfalar = _cok_sayfali_sinav_ve_sablon(tmp_path)
    sonuc = serbest_kagit_isle(
        [sayfalar[0], sayfalar[1]], sinav, sablon,
        YapayTaniyici("doğru yöntem", 0.9), kirp_dizini=tmp_path / "k",
        guvenlik_kapisi_modu="kapali",
    )
    kutu = sonuc.kutular[0]
    assert kutu.puan.incele is True
    # Kapalı modda birleşik kutu için de kapı telemetrisi yazılmamalı
    assert not any(k.get("tur") == "guvenlik_kapisi" for k in kutu.puan.kararlar)


def test_birlesik_kutu_golge_modda_telemetri_yazar_incele_kalir(tmp_path):
    sinav, sablon, sayfalar = _cok_sayfali_sinav_ve_sablon(tmp_path)
    sonuc = serbest_kagit_isle(
        [sayfalar[0], sayfalar[1]], sinav, sablon,
        YapayTaniyici("doğru yöntem", 0.9), kirp_dizini=tmp_path / "k",
        guvenlik_kapisi_modu="golge",
    )
    kutu = sonuc.kutular[0]
    assert kutu.puan.incele is True
    assert kutu.puan.otomatik_kabul is False
    kapi = [k for k in kutu.puan.kararlar if k.get("tur") == "guvenlik_kapisi"]
    assert kapi and kapi[0]["mod"] == "golge"


@pytest.mark.parametrize(
    ("kaynak_donusu", "beklenen_derece"),
    [
        (cv2.ROTATE_180, 180),
        (cv2.ROTATE_90_COUNTERCLOCKWISE, 90),
    ],
)
def test_serbest_ters_cekilmis_fotografi_duzeltip_okur(
    tmp_path, kaynak_donusu, beklenen_derece
):
    ana = np.full((900, 620, 3), 255, np.uint8)
    for sira in range(14):
        cv2.putText(
            ana,
            f"1. Biyoloji yazili satiri {sira}",
            (35, 55 + sira * 45),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 0, 0),
            1,
        )
    cv2.circle(ana, (115, 770), 42, (0, 0, 0), 3)
    ogrenci = ana.copy()
    cv2.putText(
        ogrenci,
        "mitokondri",
        (190, 790),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX,
        1.1,
        (25, 25, 25),
        3,
    )
    ana_yolu = tmp_path / "ana-duz.png"
    ters_yolu = tmp_path / "ogrenci-ters.png"
    cv2.imwrite(str(ana_yolu), ana)
    cv2.imwrite(str(ters_yolu), cv2.rotate(ogrenci, kaynak_donusu))
    sinav = Sinav(
        kimlik="TERS-FOTO",
        baslik="Ters fotoğraf",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Organeli yazınız.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("mitokondri", 10)]
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.20, 0.68, 0.72, 0.24)],
    )

    sonuc = serbest_kagit_isle(
        ters_yolu,
        sinav,
        sablon,
        YapayTaniyici("mitokondri", 0.9),
    )

    assert len(sonuc.kutular) == 1
    assert sonuc.sayfa_eslesmeleri[0]["donus_derecesi"] == beklenen_derece
    assert any(
        f"{beklenen_derece}° döndürülerek" in uyari
        for uyari in sonuc.uyarilar
    )


def test_serbest_bir_ogrencide_dort_sayfa_sinirini_uygular(tmp_path):
    ana = np.full((600, 400, 3), 255, np.uint8)
    cv2.putText(
        ana, "Soru 1", (30, 80), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2
    )
    yol = tmp_path / "sayfa.png"
    cv2.imwrite(str(yol), ana)
    sinav = Sinav(
        kimlik="DORT-SINIR",
        baslik="Dört sayfa",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Yanıtlayınız.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("cevap", 10)]
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(yol)],
        kutular=[SerbestKutu(1, 1, 0.05, 0.10, 0.90, 0.30)],
    )

    with pytest.raises(ValueError, match="en fazla 4 sayfa"):
        serbest_kagit_isle(
            [yol, yol, yol, yol, yol],
            sinav,
            sablon,
            YapayTaniyici("cevap", 0.9),
        )


def test_serbest_yazili_tanimi_sayfa_ve_bolge_sinirlarini_dogrular():
    with pytest.raises(ValueError, match="1–4 ana sayfa"):
        SerbestSablon(
            sinav_kimlik="BES-SAYFA",
            dpi=200,
            sayfa_gorselleri=["1.png", "2.png", "3.png", "4.png", "5.png"],
            kutular=[],
        )

    with pytest.raises(ValueError, match="sayfa sınırlarının dışında"):
        SerbestSablon(
            sinav_kimlik="TASAN-BOLGE",
            dpi=200,
            sayfa_gorselleri=["1.png"],
            kutular=[SerbestKutu(1, 1, 0.80, 0.10, 0.30, 0.20)],
        )


def test_web_arayuzu_hazir_sinavi_aktarir_ve_kagidi_yukler(tmp_path, monkeypatch):
    def sahte_cozumleyici(kaynak, hedef, token):
        ana = np.full((500, 400, 3), 255, np.uint8)
        cv2.putText(
            ana,
            "1. Hucrenin enerji organeli nedir? (10 puan)",
            (20, 80),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            (0, 0, 0),
            1,
        )
        ana_yolu = hedef / "ana_sayfa_1.png"
        cv2.imwrite(str(ana_yolu), ana)
        return SerbestTaslak(
            token=token,
            kaynak_dosya=str(kaynak),
            dpi=200,
            sayfa_gorselleri=[str(ana_yolu)],
            sorular=[
                SerbestTaslakSorusu(
                    no=1,
                    sayfa=1,
                    metin="Hücrenin enerji organeli nedir?",
                    puan=10,
                    kutu=SerbestKutu(1, 1, 0.04, 0.10, 0.92, 0.80),
                    guven=0.95,
                )
            ],
        )

    app = uygulama_kur(
        str(tmp_path / "t.db"),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
        taniyici_fabrikasi=lambda _tur: YapayTaniyici("mitokondri", 0.9),
        serbest_cozumleyici=sahte_cozumleyici,
    )
    c = TestClient(app)
    bos_png = cv2.imencode(".png", np.full((500, 400, 3), 255, np.uint8))[1].tobytes()

    form = c.get("/serbest-yukle")
    assert form.status_code == 200
    assert "6 motorlu Türkçe OCR" in form.text
    assert all(
        ad in form.text
        for ad in (
            "Apple Vision",
            "Tesseract Türkçe",
            "EasyOCR Türkçe",
            "PaddleOCR",
            "Surya OCR",
            "TrOCR El Yazısı",
        )
    )

    aktar = c.post(
        "/serbest-yukle",
        data={
            "kimlik": "HAZIR-BIO-1",
            "baslik": "Hazır Biyoloji",
            "ders": "Biyoloji",
            "ocr_profili": "besli",
        },
        files={"kaynak_dosyasi": ("bos.png", bos_png, "image/png")},
        follow_redirects=False,
    )
    assert aktar.status_code == 303
    incele = c.get(aktar.headers["location"])
    assert "Algılanan soruları doğrulayın" in incele.text
    token = aktar.headers["location"].rsplit("/", 1)[-1]

    from sinav_okur.yapay_zeka import YapayZekaCevabi

    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.claude_api_durumu",
        lambda: {"hazir": True, "mesaj": "Hazır · test"},
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.cevap_anahtarlari_uret",
        lambda *a, **k: [
            YapayZekaCevabi(1, "Mitokondri ATP üretir.", ["Mitokondri", "ATP üretimi"])
        ],
    )
    yapay_zeka = c.post(
        f"/serbest/{token}/yapay-zeka-cevaplari",
        data={
            "soru_no": "1",
            "soru_metin": "Hücrenin enerji organeli nedir?",
            "soru_puan": "10",
        },
        follow_redirects=True,
    )
    assert yapay_zeka.status_code == 200
    assert "Mitokondri ATP üretir." in yapay_zeka.text
    assert "ATP üretimi" in yapay_zeka.text

    kaydet = c.post(
        f"/serbest/{token}",
        data={
            "soru_no": "1",
            "soru_tip": "acik_uclu",
            "soru_metin": "Hücrenin enerji organeli nedir?",
            "soru_puan": "10",
            "soru_anahtar": "mitokondri",
            "kutu_x": "0.04",
            "kutu_y": "0.10",
            "kutu_width": "0.92",
            "kutu_height": "0.80",
        },
        follow_redirects=False,
    )
    assert kaydet.status_code == 303
    db = Depo(tmp_path / "t.db")
    dosya = db.sinav_dosyasi("HAZIR-BIO-1")
    assert json.loads(Path(dosya["sablon_yolu"]).read_text())["tur"] == "serbest_v1"

    ana_png = Path(
        json.loads(Path(dosya["sablon_yolu"]).read_text())["sayfa_gorselleri"][0]
    ).read_bytes()
    yukle = c.post(
        "/yukle",
        data={
            "sinav_kimlik": "HAZIR-BIO-1",
            "model_turu": "keras-karakter",
            "dpi": "200",
        },
        files={"kagit_dosyasi": ("ogrenci.png", ana_png, "image/png")},
        follow_redirects=False,
    )
    assert yukle.status_code == 303
    assert yukle.headers["location"].startswith("/kagit/")


def test_model_kur_zipten_kurar_ve_guvensiz_arsivi_reddeder(tmp_path, capsys):
    import zipfile
    from argparse import Namespace

    from sinav_okur.cli import _cmd_modelkur

    iyi = tmp_path / "trocr-tr.zip"
    with zipfile.ZipFile(iyi, "w") as z:
        z.writestr("trocr-tr/config.json", "{}")
        z.writestr("trocr-tr/model.safetensors", "ikili")
    hedef = tmp_path / "modeller" / "trocr-tr"

    assert _cmd_modelkur(Namespace(zip=str(iyi), hedef=str(hedef))) == 0
    assert (hedef / "config.json").is_file()
    assert (hedef / "model.safetensors").is_file()

    kotu = tmp_path / "kotu.zip"
    with zipfile.ZipFile(kotu, "w") as z:
        z.writestr("../kacak/config.json", "{}")
    assert _cmd_modelkur(Namespace(zip=str(kotu), hedef=str(hedef))) == 1
    assert not (tmp_path.parent / "kacak").exists()

    yok = tmp_path / "olmayan.zip"
    assert _cmd_modelkur(Namespace(zip=str(yok), hedef=str(hedef))) == 1


def test_korpus_benzersiz_ve_cesitli_uretir():
    from sinav_okur.veri import korpus_uret

    tekrarli = korpus_uret(3000, tohum=1)
    benzersiz = korpus_uret(3000, tohum=1, benzersiz=True)

    assert len(benzersiz) == len(set(benzersiz))
    # çeşitlilik: tekrarlı üretimde bile eski 10 şablonun çok ötesinde olmalı
    assert len(set(tekrarli)) > 1500
    # dil modeli kısayolunu kıran dilbilgisiz diziler ve rakamlar bulunmalı
    assert any(any(ch.isdigit() for ch in m) for m in benzersiz)


def test_metin_ayrik_bol_sizinti_birakmaz():
    from sinav_okur.veri import metin_ayrik_bol

    kayitlar = [
        {"image": f"img/{i}.png", "text": f"cumle {i % 20}"} for i in range(200)
    ]

    egitim, test = metin_ayrik_bol(kayitlar, test_orani=0.25, tohum=3)

    egitim_metin = {k["text"] for k in egitim}
    test_metin = {k["text"] for k in test}
    assert egitim_metin & test_metin == set()
    assert len(egitim) + len(test) == len(kayitlar)
    assert test_metin


def test_sozluk_hatta_ocr_terimini_duzeltir(tmp_path):
    """Uçtan uca: OCR 'mitokondi' okusa da sözlük anahtardan düzeltir."""
    ana = np.full((900, 700, 3), 255, np.uint8)
    cv2.putText(
        ana, "1. Organeli yaziniz.", (45, 70),
        cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 2,
    )
    ogrenci = ana.copy()
    cv2.putText(
        ogrenci, "cevap", (100, 420),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX, 1.1, (80, 20, 10), 2,
    )
    ana_yolu = tmp_path / "ana.png"
    ogrenci_yolu = tmp_path / "ogrenci.png"
    cv2.imwrite(str(ana_yolu), ana)
    cv2.imwrite(str(ogrenci_yolu), ogrenci)
    sinav = Sinav(
        kimlik="SOZLUK-1",
        baslik="Sözlük",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Hücrenin enerji merkezi?",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.04, 0.25, 0.92, 0.45)],
    )
    sonuc = serbest_kagit_isle(
        ogrenci_yolu, sinav, sablon, YapayTaniyici("mitokondi", 0.9),
        kirp_dizini=tmp_path / "kirp",
    )
    kutu = sonuc.kutular[0]
    assert kutu.tanima.metin == "mitokondri"
    assert kutu.sozluk_duzeltmeleri
    assert kutu.puan.puan == 10


def test_sozluk_kapatilinca_ham_metin_kalir(tmp_path):
    ana = np.full((900, 700, 3), 255, np.uint8)
    cv2.putText(
        ana, "1. Organeli yaziniz.", (45, 70),
        cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 2,
    )
    ogrenci = ana.copy()
    cv2.putText(
        ogrenci, "cevap", (100, 420),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX, 1.1, (80, 20, 10), 2,
    )
    ana_yolu = tmp_path / "ana.png"
    ogrenci_yolu = tmp_path / "ogrenci.png"
    cv2.imwrite(str(ana_yolu), ana)
    cv2.imwrite(str(ogrenci_yolu), ogrenci)
    sinav = Sinav(
        kimlik="SOZLUK-2",
        baslik="Sözlük",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Hücrenin enerji merkezi?",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.04, 0.25, 0.92, 0.45)],
    )
    sonuc = serbest_kagit_isle(
        ogrenci_yolu, sinav, sablon, YapayTaniyici("mitokondi", 0.9),
        kirp_dizini=tmp_path / "kirp", sozluk_kullan=False,
    )
    assert sonuc.kutular[0].tanima.metin == "mitokondi"
    assert not sonuc.kutular[0].sozluk_duzeltmeleri


def test_vision_araci_darwin_disinda_hic_derlenmez(monkeypatch, tmp_path):
    """Windows'ta xcrun/swiftc hiç çağrılmadan açık bir hata verilmeli."""
    monkeypatch.setattr(sys, "platform", "win32")

    def cagrilirsa_patlat(*_a, **_k):
        raise AssertionError("derleme denenmemeli")

    monkeypatch.setattr(serbest.subprocess, "run", cagrilirsa_patlat)
    with pytest.raises(ValueError, match="macOS"):
        serbest._vision_araci(tmp_path, tmp_path / "araclar")
