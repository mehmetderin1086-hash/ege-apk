"""Web arayüzünün uçtan uca testleri.

Her sayfa gerçekten üretiliyor mu, formlar veriyi kaydediyor mu ve indirilen
dosyalar geçerli mi — şablon hataları ancak böyle yakalanır.
"""

from __future__ import annotations

import json
from datetime import date

import pytest

from ogretmen_cantasi import servis
from ogretmen_cantasi import servis_olcme as so
from ogretmen_cantasi.web import sunucu as web_sunucu


@pytest.fixture
def kurulu(istemci):
    """Öğretim yılı, şube, öğrenciler ve ders programı hazır bir kurulum."""
    istemci.post(
        "/kurulum/yil",
        data={
            "ad": "2026-2027",
            "d1_baslangic": "2026-09-14",
            "d1_bitis": "2027-01-16",
            "d2_baslangic": "2027-02-02",
            "d2_bitis": "2027-06-18",
        },
        follow_redirects=False,
    )
    istemci.post("/kurulum/sube", data={"ad": "9-A", "sinif": 9}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        sube = servis.subeleri_oku(baglanti, yil.id)[0]
        servis.ogrenci_ekle(
            baglanti, sube.id, [("101", "Ayşe Yılmaz"), ("102", "Mehmet Kaya")]
        )
        servis.ders_programi_yaz(baglanti, [(sube.id, 2, 3), (sube.id, 2, 4)])
    finally:
        baglanti.close()
    return sube


def test_kurulum_yoksa_ana_sayfa_kuruluma_yonlendirir(istemci) -> None:
    yanit = istemci.get("/", follow_redirects=False)
    assert yanit.status_code == 303
    assert yanit.headers["location"] == "/kurulum"


def test_kurulum_sayfasi_acilir(istemci) -> None:
    yanit = istemci.get("/kurulum")
    assert yanit.status_code == 200
    assert "Öğretim yılı" in yanit.text
    assert "Ders programı" in yanit.text


def test_saglik_ucu_imza_dondurur(istemci) -> None:
    """Masaüstü başlatıcısı portta bu imzayı arıyor."""
    veri = istemci.get("/saglik").json()
    assert veri["uygulama"] == "ogretmen-cantasi"
    assert veri["surum"] == "0.3.0"
    assert veri["durum"] == "hazır"


def test_csrf_olmadan_ve_yabanci_kokenden_degisim_reddedilir(istemci) -> None:
    once = istemci.get("/kurulum").text
    belirtec = istemci.headers.pop("X-CSRF-Token")
    try:
        eksik = istemci.post("/kurulum/sube", data={"ad": "9-Z", "sinif": 9})
        yabanci = istemci.post(
            "/kurulum/sube",
            data={"ad": "9-Y", "sinif": 9},
            headers={"X-CSRF-Token": belirtec, "Origin": "https://ornek.com"},
        )
    finally:
        istemci.headers["X-CSRF-Token"] = belirtec
    assert eksik.status_code == 403
    assert yabanci.status_code == 403
    assert istemci.get("/kurulum").text == once


def test_bugun_ekrani_gunun_derslerini_gosterir(istemci, kurulu) -> None:
    sali = date(2026, 9, 15)
    assert sali.isoweekday() == 2
    yanit = istemci.get(f"/?tarih={sali.isoformat()}")
    assert yanit.status_code == 200
    assert "9-A" in yanit.text
    assert "3-4. ders" in yanit.text


def test_sube_sayfasi_ogrencileri_listeler(istemci, kurulu) -> None:
    yanit = istemci.get(f"/sube/{kurulu.id}")
    assert yanit.status_code == 200
    assert "Ayşe Yılmaz" in yanit.text
    assert "Mehmet Kaya" in yanit.text


def test_ogrenci_yapistirarak_eklenir(istemci, kurulu) -> None:
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir",
        data={"metin": "103 Ali Demir\n104 Zeynep Şahin"},
        follow_redirects=False,
    )
    yanit = istemci.get(f"/sube/{kurulu.id}")
    assert "Ali Demir" in yanit.text
    assert "Zeynep Şahin" in yanit.text


def test_yillik_plan_uretilir_ve_gorunur(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/plan/{kurulu.id}")
    assert yanit.status_code == 200
    assert "BİY.9.1.1" in yanit.text
    assert "YAŞAM" in yanit.text


def test_aylik_gorunum(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/plan/{kurulu.id}?gorunum=aylik")
    assert "Aylık dağılım" in yanit.text
    assert "Eylül" in yanit.text


@pytest.mark.parametrize(
    ("sorgu", "imza"),
    [
        ("bicim=pdf&sablon=meb", b"%PDF"),
        ("bicim=pdf&sablon=maarif", b"%PDF"),
        ("bicim=docx", b"PK"),
        ("bicim=xlsx", b"PK"),
    ],
)
def test_plan_indirilebilir(istemci, kurulu, sorgu: str, imza: bytes) -> None:
    yanit = istemci.get(f"/plan/{kurulu.id}/indir?{sorgu}")
    assert yanit.status_code == 200
    assert yanit.content.startswith(imza)
    assert len(yanit.content) > 1000


def test_gunluk_plan_sayfasi(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/gunluk/{kurulu.id}?tarih=2026-09-15&saatler=3,4")
    assert yanit.status_code == 200
    assert "Ders akışı" in yanit.text
    assert "80 dakika" in yanit.text


def test_gunluk_plan_pdf_indirilir(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/gunluk/{kurulu.id}/indir?tarih=2026-09-15&saatler=3,4")
    assert yanit.content.startswith(b"%PDF")


def test_yoklama_kaydedilir(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenciler = servis.ogrencileri_oku(baglanti, kurulu.id)
    finally:
        baglanti.close()

    veri = {"tarih": "2026-09-15", "saat": "3"}
    veri[f"o_{ogrenciler[0]['id']}"] = "yok"
    veri[f"o_{ogrenciler[1]['id']}"] = "var"
    istemci.post(f"/yoklama/{kurulu.id}", data=veri, follow_redirects=False)

    yanit = istemci.get(f"/yoklama/{kurulu.id}?tarih=2026-09-15&saat=3")
    assert yanit.status_code == 200
    assert "Ayşe Yılmaz" in yanit.text
    sube_sayfasi = istemci.get(f"/sube/{kurulu.id}")
    assert "Gelmedi (saat)" in sube_sayfasi.text


def test_eski_yoklama_formu_yeni_kaydi_ezemez(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()
    ilk = {
        "tarih": "2026-09-15",
        "saat": "3",
        "_revizyon": "0",
        f"o_{ogrenci}": "yok",
    }
    assert istemci.post(f"/yoklama/{kurulu.id}", data=ilk).status_code == 200
    ikinci = ilk | {f"o_{ogrenci}": "var"}
    yanit = istemci.post(f"/yoklama/{kurulu.id}", data=ikinci)
    assert yanit.status_code == 409
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.gunun_yoklamasi(
            baglanti, kurulu.id, date(2026, 9, 15), 3
        )[ogrenci] == "yok"
    finally:
        baglanti.close()


def test_notlar_girilir_ve_ortalama_hesaplanir(istemci, kurulu) -> None:
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "1. Yazılı", "tur": "yazili", "donem": 1, "tarih": ""},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        degerlendirme = servis.degerlendirmeleri_oku(baglanti, kurulu.id)[0]
        ogrenciler = servis.ogrencileri_oku(baglanti, kurulu.id)
    finally:
        baglanti.close()

    istemci.post(
        f"/notlar/{kurulu.id}/kaydet",
        data={f"n_{degerlendirme['id']}_{ogrenciler[0]['id']}": "85"},
        follow_redirects=False,
    )
    yanit = istemci.get(f"/notlar/{kurulu.id}")
    assert "85" in yanit.text
    assert "Ortalama" in yanit.text


def test_notlar_excel_indirilir(istemci, kurulu) -> None:
    yanit = istemci.get(f"/notlar/{kurulu.id}/indir")
    assert yanit.content.startswith(b"PK")


def test_soru_eklenir_ve_sinav_uretilir(istemci, kurulu) -> None:
    for tema in (1, 2):
        for kazanim in range(1, 4):
            for n in range(2):
                istemci.post(
                    "/sorular/ekle",
                    data={
                        "sinif": 9,
                        "kazanim_kodu": f"BİY.9.{tema}.{kazanim}",
                        "metin": f"Soru {tema}{kazanim}{n}: açıklayınız.",
                        "rubrik": "Tam 10",
                        "zorluk": "orta",
                    },
                    follow_redirects=False,
                )
    liste = istemci.get("/sorular?sinif=9")
    assert "Soru 110" in liste.text

    istemci.post(
        f"/sinavlar/{kurulu.id}/uret",
        data={
            "ad": "1. Yazılı",
            "soru_sayisi": 6,
            "sure_dk": 40,
            "ab_grubu": "on",
            "t_BİY.9.1": "50",
            "t_BİY.9.2": "50",
        },
        follow_redirects=False,
    )
    sayfa = istemci.get(f"/sinavlar/{kurulu.id}")
    assert "1. Yazılı" in sayfa.text

    baglanti = web_sunucu._baglanti()
    try:
        sinav_id = so.sinavlari_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    detay = istemci.get(f"/sinav/{sinav_id}")
    assert "Belirtke tablosu" in detay.text
    assert "Puanlama" in detay.text

    for tur in ("kagit", "anahtar"):
        yanit = istemci.get(f"/sinav/{sinav_id}/indir?tur={tur}")
        assert yanit.content.startswith(b"%PDF"), tur


def test_sinav_puanlanir_ve_kazanim_analizi_cikar(istemci, kurulu) -> None:
    for kazanim in range(1, 3):
        istemci.post(
            "/sorular/ekle",
            data={
                "sinif": 9,
                "kazanim_kodu": f"BİY.9.1.{kazanim}",
                "metin": f"Soru {kazanim}",
                "rubrik": "Tam",
            },
            follow_redirects=False,
        )
    istemci.post(
        f"/sinavlar/{kurulu.id}/uret",
        data={"ad": "Yazılı", "soru_sayisi": 2, "t_BİY.9.1": "100"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        sinav_id = so.sinavlari_oku(baglanti, kurulu.id)[0]["id"]
        sinav = so.sinavi_yukle(baglanti, sinav_id)
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    veri = {f"p_{sinav.sorular[0].id}_{ogrenci}": str(sinav.sorular[0].puan)}
    veri[f"p_{sinav.sorular[1].id}_{ogrenci}"] = "0"
    istemci.post(f"/sinav/{sinav_id}/puanla", data=veri, follow_redirects=False)

    detay = istemci.get(f"/sinav/{sinav_id}")
    assert "Kazanım bazlı başarı" in detay.text
    assert "%100.0" in detay.text
    analiz = istemci.get(f"/sinav/{sinav_id}/indir?tur=analiz")
    assert analiz.content.startswith(b"PK")


def test_deneme_elle_girilir_ve_gelisim_gorunur(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenciler = servis.ogrencileri_oku(baglanti, kurulu.id)
    finally:
        baglanti.close()

    istemci.post(
        f"/denemeler/{kurulu.id}/elle",
        data={
            "ad": "Deneme 1",
            "tarih": "2026-10-10",
            f"d_{ogrenciler[0]['id']}": "10",
            f"y_{ogrenciler[0]['id']}": "4",
            f"b_{ogrenciler[0]['id']}": "2",
        },
        follow_redirects=False,
    )
    yanit = istemci.get(f"/denemeler/{kurulu.id}")
    assert "Deneme 1" in yanit.text
    assert "9.0" in yanit.text  # net = 10 - 4/4


def test_deneme_gelisim_grafigi_iki_denemeden_sonra_cizilir(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()
    for ad, tarih, dogru in (("D1", "2026-10-10", "8"), ("D2", "2026-11-10", "12")):
        istemci.post(
            f"/denemeler/{kurulu.id}/elle",
            data={"ad": ad, "tarih": tarih, f"d_{ogrenci}": dogru, f"y_{ogrenci}": "0"},
            follow_redirects=False,
        )
    yanit = istemci.get(f"/denemeler/{kurulu.id}")
    assert yanit.status_code == 200
    # Sınıf ortalaması çizgisi ve öğrenci satırındaki kıvılcım inline SVG olmalı.
    assert "<polyline" in yanit.text
    assert yanit.text.count("<svg") >= 2
    # Öğrenci sayfası da net gelişim grafiğini göstermeli.
    ogrenci_sayfasi = istemci.get(f"/ogrenci/{ogrenci}")
    assert "<polyline" in ogrenci_sayfasi.text


def test_sube_not_dagilimi_grafigi(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenciler = servis.ogrencileri_oku(baglanti, kurulu.id)
        d_id = servis.degerlendirme_ekle(baglanti, kurulu.id, 1, "yazili", "1. Yazılı")
        servis.not_yaz(
            baglanti, d_id, {ogrenciler[0]["id"]: 45.0, ogrenciler[1]["id"]: 92.0}
        )
    finally:
        baglanti.close()
    yanit = istemci.get(f"/sube/{kurulu.id}")
    assert yanit.status_code == 200
    assert "Not dağılımı" in yanit.text
    assert "0–49: 1" in yanit.text
    assert "85–100: 1" in yanit.text


def test_takvim_sayfasi_tarihli_sinavlari_ve_uyarilari_gosterir(istemci, kurulu) -> None:
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "1. Yazılı", "tur": "yazili", "donem": 1, "tarih": "2026-10-20"},
        follow_redirects=False,
    )
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "2. Yazılı", "tur": "yazili", "donem": 1, "tarih": "2026-10-20"},
        follow_redirects=False,
    )
    yanit = istemci.get("/takvim")
    assert yanit.status_code == 200
    assert "1. Yazılı" in yanit.text
    assert "aynı gün 2 değerlendirme" in yanit.text


def test_materyal_eklenir_ve_suzulur(istemci) -> None:
    # Başlık, şablondaki örnek metinlerden farklı seçildi: aksi hâlde süzgeç
    # boş dönse bile form yer tutucusu testi yanlışlıkla geçirir.
    baslik = "Kloroplast şeması v2"
    istemci.post(
        "/materyaller/ekle",
        data={"baslik": baslik, "kazanim_kodu": "BİY.10.1.3", "sinif": 10},
        follow_redirects=False,
    )
    assert baslik in istemci.get("/materyaller").text
    assert baslik in istemci.get("/materyaller?kazanim=BİY.10").text
    assert baslik not in istemci.get("/materyaller?kazanim=BİY.9").text


def test_ayarlar_kaydedilir_ve_belgelere_gecer(istemci, kurulu) -> None:
    istemci.post(
        "/ayarlar",
        data={"okul_adi": "Örnek Anadolu Lisesi", "ogretmen_adi": "Mehmet Derin"},
        follow_redirects=False,
    )
    assert "Örnek Anadolu Lisesi" in istemci.get("/ayarlar").text

    import pymupdf

    yanit = istemci.get(f"/plan/{kurulu.id}/indir?bicim=pdf")
    with pymupdf.open(stream=yanit.content, filetype="pdf") as belge:
        # İmza bloğu belgenin sonunda; tüm sayfalar taranmalı.
        metin = "\n".join(sayfa.get_text() for sayfa in belge)
    assert "Örnek Anadolu Lisesi" in metin
    assert "Mehmet Derin" in metin


def test_takvime_ozel_gun_eklenince_plana_yansir(istemci, kurulu) -> None:
    istemci.post(
        "/kurulum/tatil",
        data={
            "baslangic": "2026-09-15",
            "bitis": "2026-09-15",
            "aciklama": "Okul gezisi",
            "tur": "okul_ozel",
        },
        follow_redirects=False,
    )
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/plan/{kurulu.id}")
    assert "Okul gezisi" in yanit.text


def test_yedek_disa_aktarilir(istemci, kurulu) -> None:
    yanit = istemci.get("/yedek/disa-aktar")
    assert yanit.content.startswith(b"PK")
    import io
    import zipfile

    with zipfile.ZipFile(io.BytesIO(yanit.content)) as paket:
        assert "veri.db" in paket.namelist()
        assert "künye.json" in paket.namelist()
        metadata = json.loads(paket.read("künye.json"))
        assert metadata["surum"] == "0.3.0"
        assert metadata["veri_sha256"]


def test_ders_programi_izgaradan_kaydedilir(istemci, kurulu) -> None:
    istemci.post(
        "/kurulum/program/izgara",
        data={"h_1_1": "9-A", "h_1_2": "9-A", "h_4_5": "9-A"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 2, 4: 1}
    finally:
        baglanti.close()


def test_12_sinif_plan_sayfasi_mufredat_yokken_de_acilir(istemci, kurulu) -> None:
    """12. sınıf 2018 programına tabi; belgesi yokken sayfa çökmemeli."""
    istemci.post("/kurulum/sube", data={"ad": "12-A", "sinif": 12}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        oniki = next(s for s in servis.subeleri_oku(baglanti, yil.id) if s.ad == "12-A")
    finally:
        baglanti.close()

    yanit = istemci.get(f"/plan/{oniki.id}")
    assert yanit.status_code == 200
    assert "2018 öğretim programı" in yanit.text
    assert "henüz yüklenmemiş" in yanit.text
    # Not ve yoklama modülleri bu şube için çalışmaya devam etmeli.
    assert istemci.get(f"/notlar/{oniki.id}").status_code == 200
    assert istemci.get(f"/yoklama/{oniki.id}").status_code == 200


def test_ders_kaydi_bugun_ekranindan_kaydedilir(istemci, kurulu) -> None:
    """Deftere işlenen ders kaydedilmeli ve Bugün ekranında rozet olarak görünmeli."""
    yanit = istemci.post(
        f"/ders-kaydi/{kurulu.id}",
        data={
            "tarih": "2026-09-15",
            "saatler": "3,4",
            "kazanim_kodlari": "BİY.9.1.1, BİY.9.1.2",
            "durum": "islendi",
        },
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    baglanti = web_sunucu._baglanti()
    try:
        kayit = servis.gunun_ders_kaydi(baglanti, kurulu.id, date(2026, 9, 15))
    finally:
        baglanti.close()
    assert kayit["kazanim_kodlari"] == "BİY.9.1.1, BİY.9.1.2"
    # 2026-09-15 Salı; kurulu ders programı o güne ders koyuyor (isoweekday 2).
    sayfa = istemci.get("/?tarih=2026-09-15")
    assert sayfa.status_code == 200
    assert "✓ işlendi" in sayfa.text

    # Geçersiz durum 500 vermemeli, mesajla geri dönmeli ve kaydı bozmamalı.
    kotu = istemci.post(
        f"/ders-kaydi/{kurulu.id}",
        data={"tarih": "2026-09-15", "durum": "iptal"},
        follow_redirects=False,
    )
    assert kotu.status_code == 303
    baglanti = web_sunucu._baglanti()
    try:
        kayit = servis.gunun_ders_kaydi(baglanti, kurulu.id, date(2026, 9, 15))
    finally:
        baglanti.close()
    assert kayit["durum"] == "islendi"
    assert kayit["kazanim_kodlari"] == "BİY.9.1.1, BİY.9.1.2"


def test_plan_sayfasi_gerceklesme_bolumunu_gosterir(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    istemci.post(
        f"/ders-kaydi/{kurulu.id}",
        data={"tarih": "2026-09-16", "kazanim_kodlari": "BİY.9.1.1", "durum": "islendi"},
        follow_redirects=False,
    )
    sayfa = istemci.get(f"/plan/{kurulu.id}")
    assert sayfa.status_code == 200
    assert "Gerçekleşme" in sayfa.text
    # Şube sayfası da özet kartını göstermeli (plan üretildi, kayıt var).
    assert istemci.get(f"/sube/{kurulu.id}").status_code == 200


def test_12_sinif_soru_havuzu_sinav_sayfasiyla_ayni_surumu_kullanir(istemci, kurulu) -> None:
    """Havuz varsayılan sürümü kullanınca 12. sınıfa Maarif kazanımı atanabiliyordu
    ama şube 2018 programında olduğu için o kazanımla sınav üretilemiyordu."""
    yanit = istemci.get("/sorular?sinif=12")
    assert yanit.status_code == 200
    # 2018 belgesi yokken Maarif'in 12. sınıf kazanımları listelenmemeli.
    assert "BİY.12." not in yanit.text
    assert "mfp_2018" in yanit.text
    assert "yüklenmemiş" in yanit.text
    # 9. sınıf havuzu Maarif kazanımlarıyla çalışmaya devam etmeli.
    assert "BİY.9." in istemci.get("/sorular?sinif=9").text

    # Eklenen soru da aktif yılın sürüm eşlemesiyle kaydedilmeli.
    istemci.post(
        "/sorular/ekle",
        data={"sinif": 12, "kazanim_kodu": "12.1.1", "metin": "Deneme sorusu"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        satir = baglanti.execute("SELECT mufredat_surumu FROM soru WHERE sinif = 12").fetchone()
    finally:
        baglanti.close()
    assert satir["mufredat_surumu"] == "mfp_2018"


def test_eksik_ders_programinda_plan_sayfasi_uyari_verir(istemci, kurulu) -> None:
    """Takvim müfredatı kaldıramıyorsa kazanımlar sessizce düşmemeli."""
    istemci.post("/kurulum/sube", data={"ad": "11-C", "sinif": 11}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        onbir = next(s for s in servis.subeleri_oku(baglanti, yil.id) if s.ad == "11-C")
        # 11. sınıf 144 saat ister; haftada yalnız 2 saat girilirse yetmez.
        servis.ders_programi_yaz(baglanti, [(onbir.id, 2, 1), (onbir.id, 2, 2)])
    finally:
        baglanti.close()

    istemci.post(f"/plan/{onbir.id}/uret", follow_redirects=False)
    yanit = istemci.get(f"/plan/{onbir.id}")
    assert "müfredatın tamamı işlenemiyor" in yanit.text


def test_yeterli_programda_uyari_cikmaz(istemci, kurulu) -> None:
    istemci.post(f"/plan/{kurulu.id}/uret", follow_redirects=False)
    assert "müfredatın tamamı işlenemiyor" not in istemci.get(f"/plan/{kurulu.id}").text


def test_deneme_elle_negatif_ve_yabanci_ogrenci_500_vermez(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    negatif = istemci.post(
        f"/denemeler/{kurulu.id}/elle",
        data={"ad": "D", f"d_{ogrenci}": "-3", f"y_{ogrenci}": "1"},
        follow_redirects=False,
    )
    assert negatif.status_code == 303
    assert "Negatif" in negatif.headers["location"]

    yabanci = istemci.post(
        f"/denemeler/{kurulu.id}/elle",
        data={"ad": "D", "d_99999": "5"},
        follow_redirects=False,
    )
    assert yabanci.status_code == 303
    baglanti = web_sunucu._baglanti()
    try:
        assert so.denemeleri_oku(baglanti, kurulu.id) == []
    finally:
        baglanti.close()


def test_ders_kaydi_olmayan_subede_500_vermez(istemci, kurulu) -> None:
    yanit = istemci.post(
        "/ders-kaydi/99999",
        data={"tarih": "2026-09-15", "kazanim_kodlari": "BİY.9.1.1"},
        follow_redirects=False,
    )
    assert yanit.status_code == 303
