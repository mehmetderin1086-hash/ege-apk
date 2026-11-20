"""Webapp uçtan uca: yazılıyı tanıt → kâğıdı oku → sonucu incele."""
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

pytest.importorskip("cv2")
pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from sinav_okur.depo import Depo
from sinav_okur.htr import YapayTaniyici
from sinav_okur.modeller import PuanSonucu, Sinav, TanimaSonucu
from sinav_okur.serbest import SerbestKutu, SerbestSablon
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.webapp import uygulama_kur

ORNEK = Path(__file__).parent.parent / "ornekler" / "biyoloji_sinav.yaml"


@pytest.fixture
def hazir_db(tmp_path):
    sinav = Sinav.yaml_yukle(ORNEK)
    veri = tmp_path / "sinav_okur_veri" / "sinavlar" / sinav.kimlik
    veri.mkdir(parents=True)
    temiz = np.full((1200, 850, 3), 255, np.uint8)
    for sira, soru in enumerate(sinav.sorular):
        y = 100 + sira * 210
        cv2.putText(
            temiz,
            f"{soru.no}. Biyoloji sorusu {soru.no}",
            (45, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 0, 0),
            2,
        )
        cv2.rectangle(temiz, (45, y + 25), (805, y + 175), (0, 0, 0), 2)
    kaynak_yolu = veri / "temiz-yazili.png"
    cv2.imwrite(str(kaynak_yolu), temiz)
    sablon_yolu = veri / f"{sinav.kimlik}_serbest.json"
    SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(kaynak_yolu)],
        kutular=[
            SerbestKutu(
                soru.no,
                1,
                45 / 850,
                (100 + sira * 210 + 25) / 1200,
                760 / 850,
                150 / 1200,
            )
            for sira, soru in enumerate(sinav.sorular)
        ],
    ).json_kaydet(sablon_yolu)
    yaml_yolu = veri / f"{sinav.kimlik}.yaml"
    sinav.yaml_kaydet(yaml_yolu)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    db.sinav_dosya_kaydet(
        sinav.kimlik,
        yaml_yolu=yaml_yolu,
        sablon_yolu=sablon_yolu,
        form_pdf_yolu=kaynak_yolu,
    )
    kirp = tmp_path / "kirp"
    kirp.mkdir()
    kutular = []
    for soru in sinav.sorular:
        kirp_yolu = kirp / f"soru_{soru.no}.png"
        cv2.imwrite(str(kirp_yolu), temiz[100:300, 40:810])
        kutular.append(
            KutuSonucu(
                soru_no=soru.no,
                tanima=TanimaSonucu(
                    metin="mitokondri",
                    guven=0.9,
                    uzlasma_guveni=0.9,
                    bagimsiz_motor_sayisi=2,
                ),
                puan=PuanSonucu(
                    puan=soru.puan,
                    max_puan=soru.puan,
                    guven=0.9,
                    detaylar=["Program cevabı anahtara göre değerlendirdi."],
                ),
                kirp_yolu=str(kirp_yolu),
            )
        )
    sonuc = KagitSonucu(
        sinav_kimlik=sinav.kimlik,
        islenen_sayfalar=[1],
        kutular=kutular,
        kalite_raporu=[
            {
                "sayfa": 1,
                "genislik": 850,
                "yukseklik": 1200,
                "netlik": 180.0,
                "parlama_orani": 0.0,
                "golge_sapmasi": 0.0,
                "sayfa_kapsama_orani": 0.95,
                "egiklik_derecesi": 0.0,
                "ogretmen_murekkep_orani": 0.0,
                "kritik": False,
                "uyarilar": [],
                "parmakizi": "",
            }
        ],
    )
    db.kagit_kaydet(
        sonuc,
        ogrenci_ad="Test",
        kaynak_dosya=str(kaynak_yolu),
    )
    return tmp_path


def test_webapp_sayfalari(hazir_db):
    app = uygulama_kur(str(hazir_db / "t.db"), str(hazir_db / "kirp"))
    c = TestClient(app)
    assert c.get("/").status_code == 200
    ana = c.get("/").text
    assert "Sınav değerlendirme merkezi" in ana
    assert "BIYO9-2026-01" in ana
    # Tema düğmesi üç durumlu (sistem/açık/koyu) ve erişilebilir olmalı.
    assert "Tema: sistem, açık veya koyu" in ana
    assert 'href="#ana-icerik"' in ana, "içeriğe atla bağlantısı"
    assert 'id="ana-icerik"' in ana
    assert "Kâğıt yükle ve değerlendir" in ana
    assert "Yeni yazılıyı tanıt" in ana
    assert "Yeni sınav oluştur" not in ana
    sinav = c.get("/sinav/BIYO9-2026-01")
    assert sinav.status_code == 200
    assert "Öğrenci kâğıtları" in sinav.text
    assert "Excel not dökümü" in sinav.text
    kaynak = c.get("/sinav/BIYO9-2026-01/kaynak")
    assert kaynak.status_code == 200
    assert kaynak.headers["content-type"] == "image/png"
    r = c.get("/kagit/1")
    assert r.status_code == 200
    assert "Soru 1" in r.text
    assert "Düzeltmeyi kaydet" in r.text
    assert "Tanıma güveni" in r.text
    assert "OCR metnini geri yükle" in r.text
    assert "Tam puan" in r.text


def test_webapp_bos_durum_ve_bilinmeyen_sinav(tmp_path):
    app = uygulama_kur(str(tmp_path / "bos.db"), str(tmp_path / "kirp"))
    c = TestClient(app)

    ana = c.get("/")

    assert ana.status_code == 200
    assert "İlk yazılınızı tanıtın" in ana.text
    assert "/serbest-yukle" in ana.text
    assert "/sinav-yeni" not in ana.text
    assert "0" in ana.text
    assert c.get("/sinav/bilinmeyen").status_code == 404


def test_kalibrasyon_guncelle_yetersiz_veride_uygulanmaz(tmp_path):
    app = uygulama_kur(str(tmp_path / "bos.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post("/kalibrasyon/guncelle", follow_redirects=False)
    assert r.status_code == 303
    assert "kalibrasyon=uygulanmadi" in r.headers["location"]


def _incelemeli_kagit(tmp_path):
    """İnceleme bekleyen (incele=True) kutular içeren bir kâğıt kurar."""
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    kutular = []
    for i, soru in enumerate(sinav.sorular):
        kutular.append(
            KutuSonucu(
                soru_no=soru.no,
                tanima=TanimaSonucu(metin="mitokondri", guven=0.5),
                puan=PuanSonucu(
                    puan=soru.puan, max_puan=soru.puan, guven=0.5,
                    incele=True, risk=0.3 + i * 0.05,
                ),
            )
        )
    sonuc = KagitSonucu(
        sinav_kimlik=sinav.kimlik, islenen_sayfalar=[1], kutular=kutular,
    )
    kagit_id = db.kagit_kaydet(sonuc, ogrenci_ad="Ayşe")
    return db, sinav, kagit_id


def test_inceleme_kuyrugu_en_supheli_once(tmp_path):
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.get(f"/sinav/{sinav.kimlik}/inceleme")
    assert r.status_code == 200
    assert "İnceleme kuyruğu" in r.text
    # En yüksek riskli kutu (son soru) ilk gösterilir
    assert f"Soru {sinav.sorular[-1].no}" in r.text


def test_kutu_onayla_islemi_incelemeden_cikarir(tmp_path):
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    kutu = db.kutular(kagit_id)[0]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/kutu/{kutu['id']}",
        data={"kagit_id": kagit_id, "metin": "mitokondri", "islem": "onayla"},
        follow_redirects=False,
    )
    assert r.status_code == 303
    guncel = db.kutu(kutu["id"])
    assert guncel["incele"] == 0
    # Puan değişmemeli (yeniden puanlanmadı)
    assert guncel["son_puan"] == kutu["son_puan"]


def test_kutu_onayla_hedefle_kuyruga_doner(tmp_path):
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    kutu = db.kutular(kagit_id)[0]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    hedef = f"/sinav/{sinav.kimlik}/inceleme"
    r = c.post(
        f"/kutu/{kutu['id']}",
        data={"kagit_id": kagit_id, "islem": "onayla", "hedef": hedef},
        follow_redirects=False,
    )
    assert r.status_code == 303
    assert r.headers["location"] == hedef


def test_inceleme_onayla_formu_islem_gizli_inputta(tmp_path):
    """Klavye kısayolu form.requestSubmit() submitter iletmez; islem gizli
    input'ta olmalı, yoksa POST 'elle'ye düşüp 400 verir (gerçek regresyon)."""
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    html = c.get(f"/sinav/{sinav.kimlik}/inceleme").text
    assert '<input type="hidden" name="islem" value="onayla">' in html
    # Butonun name="islem" taşımaması gerekir (aksi halde çift gönderim)
    assert 'value="onayla" id="onayla-dugme"' not in html


def test_geri_bildirim_dogru_cevap_ve_taslak_bandi(tmp_path):
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.get(f"/kagit/{kagit_id}/geri-bildirim")
    assert r.status_code == 200
    assert "Senin cevabın" in r.text
    assert "Doğru cevap" in r.text
    # Onaylanmamış kâğıt → TASLAK bandı
    assert "TASLAK" in r.text


def test_geri_bildirimler_yalniz_onaylilari_gosterir(tmp_path):
    db, sinav, kagit_id = _incelemeli_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    # Onaysızken toplu geri bildirim boş (öğrenci kartı yok)
    r = c.get(f"/sinav/{sinav.kimlik}/geri-bildirimler")
    assert r.status_code == 200
    assert "Ayşe" not in r.text.split("Öğrenci geri bildirimleri")[-1] or "TASLAK" not in r.text
    # Onaylayınca görünür
    for kutu in db.kutular(kagit_id):
        db.kutu_guncelle(kutu["id"], incele=False)
    db.kagit_onayla(kagit_id)
    r2 = c.get(f"/sinav/{sinav.kimlik}/geri-bildirimler")
    assert "Ayşe" in r2.text
    assert "TASLAK" not in r2.text


def test_toplu_onay_bos_metni_atlar(tmp_path):
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    kutular = [
        KutuSonucu(
            soru_no=sinav.sorular[0].no,
            tanima=TanimaSonucu(metin="mitokondri", guven=0.5),
            puan=PuanSonucu(puan=5, max_puan=10, guven=0.5, incele=True),
        ),
        KutuSonucu(
            soru_no=sinav.sorular[1].no,
            tanima=TanimaSonucu(metin="", guven=1.0),
            puan=PuanSonucu(puan=0, max_puan=10, guven=1.0, incele=True),
        ),
    ]
    kagit_id = db.kagit_kaydet(
        KagitSonucu(sinav_kimlik=sinav.kimlik, islenen_sayfalar=[1], kutular=kutular),
        ogrenci_ad="Ayşe",
    )
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/kagit/{kagit_id}/kutulari-onayla", follow_redirects=False
    )
    assert r.status_code == 303
    assert "toplu_onay=1" in r.headers["location"]
    assert "atlanan=1" in r.headers["location"]


def test_sinav_guncelleme_dosya_baglantisini_korur(tmp_path):
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    yaml_yolu = tmp_path / "sinav.yaml"
    sablon_yolu = tmp_path / "sablon.json"
    kaynak_yolu = tmp_path / "kaynak.pdf"
    db.sinav_dosya_kaydet(
        sinav.kimlik,
        yaml_yolu=yaml_yolu,
        sablon_yolu=sablon_yolu,
        form_pdf_yolu=kaynak_yolu,
    )

    sinav.baslik = "Güncellenmiş sınav"
    db.sinav_kaydet(sinav)

    dosya = db.sinav_dosyasi(sinav.kimlik)
    assert dosya is not None
    assert dosya["yaml_yolu"] == str(yaml_yolu)
    assert dosya["sablon_yolu"] == str(sablon_yolu)
    assert dosya["form_pdf_yolu"] == str(kaynak_yolu)


def test_webapp_sihirbaz_ve_yardim_sayfalari(tmp_path):
    app = uygulama_kur(
        str(tmp_path / "bos.db"),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
        taniyici_fabrikasi=lambda _tur: YapayTaniyici(),
    )
    c = TestClient(app)

    yeni = c.get("/sinav-yeni")
    yukle = c.get("/yukle")
    yardim = c.get("/yardim")

    assert yeni.status_code == 404
    assert yukle.status_code == 200
    assert "Önce yazılıyı tanıtın" in yukle.text
    assert "sablon_dosyasi" not in yukle.text
    assert yardim.status_code == 200
    assert "Başlangıç ve kullanım kılavuzu" in yardim.text
    assert "QR" not in yardim.text
    assert "köşe işaretçisi" not in yardim.text


def test_form_uretme_ve_sablon_indirme_rotalari_kaldirildi(tmp_path):
    app = uygulama_kur(
        str(tmp_path / "arayuz.db"),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
    )
    c = TestClient(app)

    assert c.get("/sinav-yeni").status_code == 404
    assert c.post(
        "/sinav-yeni",
        data={"kimlik": "ESKI-FORM"},
    ).status_code == 404
    assert c.get("/sinav/ESKI-FORM/form.pdf").status_code == 404
    assert c.get("/sinav/ESKI-FORM/sablon.json").status_code == 404


def test_yukleme_gecersiz_dosya_turunu_reddeder(hazir_db):
    db_yolu = hazir_db / "t.db"
    app = uygulama_kur(
        str(db_yolu),
        str(hazir_db / "kirp"),
        taniyici_fabrikasi=lambda _tur: YapayTaniyici(),
    )
    c = TestClient(app)

    yanit = c.post(
        "/yukle",
        data={"sinav_kimlik": "BIYO9-2026-01", "model_turu": "keras-karakter"},
        files={"kagit_dosyasi": ("kagit.exe", b"uygulama", "application/octet-stream")},
    )

    assert yanit.status_code == 400
    assert "Desteklenmeyen dosya türü" in yanit.text


def test_sinif_yuklemesi_ogrenci_sayfalarini_gruplar(hazir_db):
    app = uygulama_kur(
        str(hazir_db / "t.db"),
        str(hazir_db / "kirp"),
        taniyici_fabrikasi=lambda _tur: YapayTaniyici(
            metin="mitokondri", guven=0.91
        ),
    )
    c = TestClient(app)
    kaynak_yolu = Path(
        Depo(hazir_db / "t.db").sinav_dosyasi("BIYO9-2026-01")["form_pdf_yolu"]
    )
    kaynak = kaynak_yolu.read_bytes()

    yanit = c.post(
        "/yukle",
        data={
            "sinav_kimlik": "BIYO9-2026-01",
            "islem_modu": "sinif",
            "model_turu": "keras-karakter",
        },
        files=[
            (
                "kagit_dosyalari",
                ("101_Ayse_Yilmaz__1.png", kaynak, "image/png"),
            ),
            (
                "kagit_dosyalari",
                ("101_Ayse_Yilmaz__2.png", kaynak, "image/png"),
            ),
            (
                "kagit_dosyalari",
                ("102_Mehmet_Kaya.png", kaynak, "image/png"),
            ),
        ],
        follow_redirects=False,
    )

    assert yanit.status_code == 303, yanit.text
    konum = yanit.headers["location"]
    assert konum.startswith("/toplu-sonuc/")
    token = konum.rsplit("/", 1)[-1]

    # Sınıf modu artık arka planda işlenir; durum.json ile tamamlanmayı bekle.
    import time

    for _ in range(100):
        durum = c.get(f"/toplu-sonuc/{token}/durum.json").json()
        if durum.get("durum") == "bitti":
            break
        time.sleep(0.05)
    else:
        raise AssertionError("Toplu işlem süresinde bitmedi")

    sonuc = c.get(konum)
    assert sonuc.status_code == 200
    assert "Ayse Yilmaz" in sonuc.text
    assert "Mehmet Kaya" in sonuc.text
    kagitlar = Depo(hazir_db / "t.db").kagitlar("BIYO9-2026-01")
    assert {k["ogrenci_no"] for k in kagitlar} >= {"101", "102"}


def test_toplu_yukleme_beklenmeyen_hatada_takilmaz(hazir_db):
    """Bir kâğıt beklenmeyen istisna atsa bile arka plan bitip durum yazmalı."""
    class _PatlarTaniyici:
        def kutu_taniy(self, kirp, dpi=300):
            raise RuntimeError("model çöktü")  # _grubu_isle'nin yakalamadığı tip

    app = uygulama_kur(
        str(hazir_db / "t.db"), str(hazir_db / "kirp"),
        taniyici_fabrikasi=lambda _tur: _PatlarTaniyici(),
    )
    c = TestClient(app)
    kaynak = Path(
        Depo(hazir_db / "t.db").sinav_dosyasi("BIYO9-2026-01")["form_pdf_yolu"]
    ).read_bytes()
    yanit = c.post(
        "/yukle",
        data={"sinav_kimlik": "BIYO9-2026-01", "islem_modu": "sinif",
              "model_turu": "keras-karakter"},
        files=[("kagit_dosyalari", ("101_Ayse.png", kaynak, "image/png"))],
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    token = yanit.headers["location"].rsplit("/", 1)[-1]
    import time

    for _ in range(100):
        durum = c.get(f"/toplu-sonuc/{token}/durum.json").json()
        if durum.get("durum") in {"bitti", "hata"}:
            break
        time.sleep(0.05)
    else:
        raise AssertionError("Arka plan takıldı — durum yazılmadı")
    # İşleniyor'da takılı kalmadı; başarısız öğrenci kaydı üretildi
    assert durum["durum"] in {"bitti", "hata"}
    assert any(not s.get("basarili") for s in durum["sonuclar"])


def test_referans_kitabi_yukler_ve_yerel_indeks_olusturur(tmp_path):
    veri = tmp_path / "veri"
    app = uygulama_kur(
        str(tmp_path / "bos.db"),
        str(tmp_path / "kirp"),
        str(veri),
    )
    c = TestClient(app)

    yanit = c.post(
        "/referans",
        files={
            "kitap_dosyalari": (
                "biyoloji-notu.txt",
                (
                    "Mitokondri ökaryot hücrelerde hücresel solunum yapar. "
                    "Besinlerdeki kimyasal enerjiyi ATP biçiminde kullanılabilir "
                    "enerjiye dönüştürür. Kloroplast fotosentez yapar."
                ).encode("utf-8"),
                "text/plain",
            )
        },
    )

    assert yanit.status_code == 200
    assert "1 kaynak eklendi" in yanit.text
    assert "biyoloji-notu.txt" in yanit.text
    assert (veri / "referans" / "yerel_indeks" / "yerel_pasajlar.jsonl").is_file()


def test_webapp_kutu_kaydet_ve_onayla(hazir_db):
    app = uygulama_kur(str(hazir_db / "t.db"), str(hazir_db / "kirp"))
    c = TestClient(app)
    db = Depo(str(hazir_db / "t.db"))
    ilk_kutu = db.kutular(1)[0]
    r = c.post(f"/kutu/{ilk_kutu['id']}",
               data={
                   "kagit_id": 1, "metin": "düzeltilmiş", "puan": 8.0,
                   "donus": "soru-1",
               },
               follow_redirects=False)
    assert r.status_code == 303
    assert r.headers["location"] == "/kagit/1#soru-1"
    guncel = db.kutular(1)[0]
    assert guncel["son_puan"] == 8.0
    assert guncel["duzeltilmis_metin"] == "düzeltilmiş"

    r2 = c.post("/kagit/1/onayla", follow_redirects=False)
    assert r2.status_code == 303
    assert db.kagit(1)["onaylandi"] == 1


def test_webapp_ogrenci_kimligini_duzeltir_ve_gosterir(hazir_db):
    app = uygulama_kur(str(hazir_db / "t.db"), str(hazir_db / "kirp"))
    c = TestClient(app)

    yanit = c.post(
        "/kagit/1/kimlik",
        data={
            "ogrenci_ad": "Ece",
            "ogrenci_soyad": "Kara",
            "ogrenci_no": "122",
            "sinif": "9",
            "sube": "A",
        },
        follow_redirects=False,
    )

    assert yanit.status_code == 303
    assert yanit.headers["location"] == "/kagit/1?kimlik_kaydedildi=1#ogrenci-kimligi"
    kagit = Depo(hazir_db / "t.db").kagit(1)
    assert kagit["ogrenci_soyad"] == "Kara"
    assert kagit["sinif"] == "9"
    assert kagit["sube"] == "A"
    assert kagit["kimlik_guveni"] == 1
    sayfa = c.get("/kagit/1")
    assert "Ece Kara" in sayfa.text
    assert "Öğretmen doğruladı" in sayfa.text


def test_duzeltilmis_metin_anahtara_gore_otomatik_yeniden_puanlanir(hazir_db):
    app = uygulama_kur(str(hazir_db / "t.db"), str(hazir_db / "kirp"))
    c = TestClient(app)
    db = Depo(str(hazir_db / "t.db"))
    ilk_kutu = db.kutular(1)[0]

    yanit = c.post(
        f"/kutu/{ilk_kutu['id']}",
        data={
            "kagit_id": 1,
            "metin": "mitokondri",
            "puan": 0,
            "islem": "otomatik",
            "donus": "soru-1",
        },
        follow_redirects=False,
    )

    assert yanit.status_code == 303
    guncel = db.kutular(1)[0]
    assert guncel["otomatik_puan"] == guncel["max_puan"]
    assert guncel["son_puan"] == guncel["max_puan"]


def test_mevcut_sinavin_rag_anahtari_kaynaklariyla_yenilenir(
    tmp_path, monkeypatch
):
    from sinav_okur.modeller import (
        CevapAnahtari,
        RubrikKalemi,
        Sinav,
        Soru,
        SoruTipi,
    )
    from sinav_okur.rag_anahtar import RAGAnahtarCevabi

    db_yolu = tmp_path / "t.db"
    db = Depo(db_yolu)
    db.sinav_kaydet(
        Sinav(
            kimlik="RAG-YENILE",
            baslik="Biyoloji",
            sorular=[
                Soru(
                    no=1,
                    tip=SoruTipi.ACIK_UCLU,
                    metin="Hücre teorisi nedir?",
                    puan=10,
                    anahtar=CevapAnahtari(
                        rubrik=[RubrikKalemi("eski anahtar", 10)]
                    ),
                )
            ],
        )
    )
    monkeypatch.setattr(
        "sinav_okur.rag_anahtar.rag_anahtarlari_uret",
        lambda *args, **kwargs: [
            RAGAnahtarCevabi(
                1,
                "Canlıların temel birimi hücredir.",
                ["Canlıların temel birimi hücredir."],
                ["biyoloji.pdf · pasaj 2"],
                "Yerel kitap RAG",
                True,
                "",
                [["hücre teorisi"]],
            )
        ],
    )
    app = uygulama_kur(
        str(db_yolu),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
    )
    c = TestClient(app)

    yanit = c.post(
        "/sinav/RAG-YENILE/rag-anahtar-yenile",
        follow_redirects=False,
    )

    assert yanit.status_code == 303
    anahtar = db.sinav_yukle("RAG-YENILE").soru(1).anahtar
    assert anahtar.otomatik_uretildi is True
    assert anahtar.kaynaklar == ["biyoloji.pdf · pasaj 2"]
    assert anahtar.rubrik[0].esanlamlilar == ["hücre teorisi"]


def test_webapp_okunamayan_kutuyu_onaylatmaz(hazir_db):
    import sqlite3

    db_yolu = hazir_db / "t.db"
    db = Depo(db_yolu)
    ilk = db.kutular(1)[0]
    with sqlite3.connect(db_yolu) as con:
        con.execute(
            "UPDATE kutu SET taninan_metin='', tanima_guveni=0, "
            "duzeltilmis_metin=NULL, incele=1 WHERE id=?",
            (ilk["id"],),
        )
    app = uygulama_kur(str(db_yolu), str(hazir_db / "kirp"))
    c = TestClient(app)

    yanit = c.post("/kagit/1/onayla", follow_redirects=False)

    assert yanit.status_code == 303
    assert yanit.headers["location"] == "/kagit/1?onay_hata=1#soru-1"
    assert db.kagit(1)["onaylandi"] == 0
    sayfa = c.get(yanit.headers["location"])
    assert "Kâğıt onaylanmadı" in sayfa.text
    assert "Metin algılanmadı" in sayfa.text
    assert "yüzde 100" not in sayfa.text


def test_webapp_excel_raporu_indirir(hazir_db):
    app = uygulama_kur(str(hazir_db / "t.db"), str(hazir_db / "kirp"))
    c = TestClient(app)

    r = c.get("/sinav/BIYO9-2026-01/rapor.xlsx")

    assert r.status_code == 200
    assert r.headers["content-type"].startswith(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert "BIYO9-2026-01_notlar.xlsx" in r.headers["content-disposition"]
    assert r.content.startswith(b"PK")


def test_webapp_gelismis_analiz_roster_ve_gizlilik(hazir_db):
    db_yolu = hazir_db / "t.db"
    app = uygulama_kur(str(db_yolu), str(hazir_db / "kirp"))
    c = TestClient(app)

    analiz = c.get("/sinav/BIYO9-2026-01/analiz")
    karsilastir = c.get("/sinav/BIYO9-2026-01/soru/1")
    gizlilik = c.get("/gizlilik")
    kagit = c.get("/kagit/1")
    yukle = c.get("/yukle?sinav=BIYO9-2026-01")

    assert analiz.status_code == 200
    assert "Sınav analizi ve tutarlılık" in analiz.text
    assert karsilastir.status_code == 200
    assert "cevaplarını karşılaştır" in karsilastir.text
    assert gizlilik.status_code == 200
    assert "Yerel" in gizlilik.text
    assert "Tarama kalite kapısı" in kagit.text
    assert "program puanı" in kagit.text
    assert "Çoklu OCR uzlaşması" in yukle.text

    liste = c.post(
        "/sinav/BIYO9-2026-01/ogrenci-listesi",
        files={
            "liste_dosyasi": (
                "liste.csv",
                "Öğrenci No;Ad;Soyad;Sınıf;Şube\n122;Ece;Kara;9;A\n",
                "text/csv",
            )
        },
        follow_redirects=False,
    )
    assert liste.status_code == 303
    assert "liste_yuklendi=1" in liste.headers["location"]
    assert Depo(db_yolu).ogrenci_listesi("BIYO9-2026-01")[0]["ad"] == "Ece"


def _cozulmus_kagit(tmp_path, ad="Veli", metin="mitokondri"):
    """İnceleme beklemeyen (onaya hazır) bir kâğıt ekler; mevcut depoyu kullanır."""
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    kutular = [
        KutuSonucu(
            soru_no=soru.no,
            tanima=TanimaSonucu(metin=metin, guven=0.95),
            puan=PuanSonucu(
                puan=soru.puan, max_puan=soru.puan, guven=0.95, incele=False
            ),
        )
        for soru in sinav.sorular
    ]
    sonuc = KagitSonucu(
        sinav_kimlik=sinav.kimlik, islenen_sayfalar=[1], kutular=kutular
    )
    return db, sinav, db.kagit_kaydet(sonuc, ogrenci_ad=ad)


def test_toplu_onay_secilen_kagitlari_onaylar(tmp_path):
    db, sinav, birinci = _cozulmus_kagit(tmp_path, ad="Ali")
    _, _, ikinci = _cozulmus_kagit(tmp_path, ad="Ayşe")
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/toplu-islem",
        data={"kagit_id": [birinci, ikinci], "islem": "onayla"},
        follow_redirects=False,
    )
    assert r.status_code == 303
    assert "toplu=2" in r.headers["location"]
    assert db.kagit(birinci)["onaylandi"] == 1
    assert db.kagit(ikinci)["onaylandi"] == 1


def test_toplu_onay_cozulmemis_kagidi_atlar(tmp_path):
    db, sinav, hazir = _cozulmus_kagit(tmp_path, ad="Ali")
    # Metni okunamamış kutu = çözülmemiş; toplu onay bunu mühürleyemez.
    bekleyen = db.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=sinav.sorular[0].no,
                    tanima=TanimaSonucu(metin="", guven=0.1),
                    puan=PuanSonucu(
                        puan=0, max_puan=sinav.sorular[0].puan,
                        guven=0.1, incele=True,
                    ),
                )
            ],
        ),
        ogrenci_ad="Zeynep",
    )
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/toplu-islem",
        data={"kagit_id": [hazir, bekleyen], "islem": "onayla"},
        follow_redirects=False,
    )
    assert "toplu=1" in r.headers["location"]
    assert "atlanan=1" in r.headers["location"]
    assert db.kagit(bekleyen)["onaylandi"] == 0


def test_toplu_incelemeye_alma_onayi_kaldirir(tmp_path):
    db, sinav, kagit_id = _cozulmus_kagit(tmp_path, ad="Ali")
    db.kagit_onayla(kagit_id)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    c.post(
        f"/sinav/{sinav.kimlik}/toplu-islem",
        data={"kagit_id": [kagit_id], "islem": "incelemeye_al"},
        follow_redirects=False,
    )
    assert db.kagit(kagit_id)["onaylandi"] == 0
    assert all(k["incele"] == 1 for k in db.kutular(kagit_id))


def test_toplu_islem_bilinmeyen_islemi_reddeder(tmp_path):
    db, sinav, kagit_id = _cozulmus_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/toplu-islem",
        data={"kagit_id": [kagit_id], "islem": "sil"},
    )
    assert r.status_code == 400


def test_geri_bildirim_secilen_kagitlari_basar(tmp_path):
    db, sinav, birinci = _cozulmus_kagit(tmp_path, ad="Ali")
    _, _, ikinci = _cozulmus_kagit(tmp_path, ad="Ayşe")
    db.kagit_onayla(birinci)
    db.kagit_onayla(ikinci)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    hepsi = c.get(f"/sinav/{sinav.kimlik}/geri-bildirimler").text
    assert "Ali" in hepsi and "Ayşe" in hepsi
    secili = c.get(f"/sinav/{sinav.kimlik}/geri-bildirimler?kagit={birinci}").text
    assert "Ali" in secili and "Ayşe" not in secili


def _tezgah_kagitlari(tmp_path):
    """Aynı soruya iki özdeş, bir farklı cevap veren üç kâğıt kurar."""
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    soru = sinav.sorular[0]
    metinler = [
        "mitokondri hücrenin enerji merkezidir",
        "mitokondri hücrenin enerji merkezidir",
        "kloroplast fotosentez organelidir",
    ]
    for sira, metin in enumerate(metinler):
        db.kagit_kaydet(
            KagitSonucu(
                sinav_kimlik=sinav.kimlik,
                islenen_sayfalar=[1],
                kutular=[
                    KutuSonucu(
                        soru_no=soru.no,
                        tanima=TanimaSonucu(metin=metin, guven=0.6),
                        puan=PuanSonucu(
                            puan=0.0, max_puan=soru.puan, guven=0.6, incele=True
                        ),
                    )
                ],
            ),
            ogrenci_ad=f"Öğrenci{sira}",
        )
    return db, sinav, soru


def test_tezgah_kumeleri_gosterir(tmp_path):
    db, sinav, soru = _tezgah_kagitlari(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.get(f"/sinav/{sinav.kimlik}/soru/{soru.no}/tezgah")
    assert r.status_code == 200
    assert "toplu puanlama tezgâhı" in r.text
    assert "Küme 1 · 2 cevap" in r.text


def test_tezgah_toplu_puan_kumeye_uygular(tmp_path):
    db, sinav, soru = _tezgah_kagitlari(tmp_path)
    kutular = [
        s for s in db.sinav_cevaplari(sinav.kimlik) if int(s["soru_no"]) == soru.no
    ]
    hedefler = [k["id"] for k in kutular[:2]]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/soru/{soru.no}/toplu-puan",
        data={"kutu_id": hedefler, "puan": "7.5", "islem": "elle"},
        follow_redirects=False,
    )
    assert r.status_code == 303
    for kid in hedefler:
        guncel = db.kutu(kid)
        assert guncel["son_puan"] == 7.5
        assert guncel["incele"] == 0


def test_tezgah_toplu_puan_duzeltme_ogrenimine_yazar(tmp_path):
    db, sinav, soru = _tezgah_kagitlari(tmp_path)
    kutu = [
        s for s in db.sinav_cevaplari(sinav.kimlik) if int(s["soru_no"]) == soru.no
    ][0]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    c.post(
        f"/sinav/{sinav.kimlik}/soru/{soru.no}/toplu-puan",
        data={"kutu_id": [kutu["id"]], "puan": "6", "islem": "elle"},
        follow_redirects=False,
    )
    ornekler = db.duzeltme_ornekleri(sinav.kimlik)
    assert any(o["ogretmen_puani"] == 6 for o in ornekler)


def test_tezgah_puan_sinir_disi_reddedilir(tmp_path):
    db, sinav, soru = _tezgah_kagitlari(tmp_path)
    kutu = [
        s for s in db.sinav_cevaplari(sinav.kimlik) if int(s["soru_no"]) == soru.no
    ][0]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/soru/{soru.no}/toplu-puan",
        data={"kutu_id": [kutu["id"]], "puan": str(soru.puan + 5), "islem": "elle"},
    )
    assert r.status_code == 400


def _tutarsiz_kagitlar(tmp_path):
    """Aynı cevabı yazıp farklı puan almış iki kâğıt kurar."""
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    soru = sinav.sorular[0]
    metin = "mitokondri hücrenin enerji üreten organelidir"
    for ad, puan in (("Ali", soru.puan), ("Ayşe", 0.0)):
        db.kagit_kaydet(
            KagitSonucu(
                sinav_kimlik=sinav.kimlik,
                islenen_sayfalar=[1],
                kutular=[
                    KutuSonucu(
                        soru_no=soru.no,
                        tanima=TanimaSonucu(metin=metin, guven=0.8),
                        puan=PuanSonucu(
                            puan=puan, max_puan=soru.puan, guven=0.8
                        ),
                    )
                ],
            ),
            ogrenci_ad=ad,
        )
    return db, sinav, soru


def test_tutarlilik_kuyrugu_cifti_gosterir(tmp_path):
    db, sinav, soru = _tutarsiz_kagitlar(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.get(f"/sinav/{sinav.kimlik}/tutarlilik")
    assert r.status_code == 200
    assert "Tutarlılık kuyruğu" in r.text
    assert "Ali" in r.text and "Ayşe" in r.text


def test_tutarlilik_kuyrugu_temizse_bos_durum(tmp_path):
    db, sinav, kagit_id = _cozulmus_kagit(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.get(f"/sinav/{sinav.kimlik}/tutarlilik")
    assert r.status_code == 200
    assert "Tutarsızlık yok" in r.text


def test_kutu_guncelleme_tutarlilik_kuyruguna_doner(tmp_path):
    db, sinav, soru = _tutarsiz_kagitlar(tmp_path)
    kutu = db.sinav_cevaplari(sinav.kimlik)[0]
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    hedef = f"/sinav/{sinav.kimlik}/tutarlilik?cift=0"
    r = c.post(
        f"/kutu/{kutu['id']}",
        data={
            "kagit_id": kutu["kagit_id"],
            "metin": "mitokondri hücrenin enerji üreten organelidir",
            "puan": "5",
            "islem": "elle",
            "hedef": hedef,
        },
        follow_redirects=False,
    )
    assert r.status_code == 303
    assert r.headers["location"] == hedef
    assert db.kutu(kutu["id"])["son_puan"] == 5


def test_kabul_yazimi_tarama_ve_onay_akisi(tmp_path):
    """Öğretmen düzeltmelerinden öneri üretilir, onaylanınca kabul edilir."""
    sinav = Sinav.yaml_yukle(ORNEK)
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(sinav)
    bosluk = next(
        s for s in sinav.sorular if s.tip.value == "bosluk_doldurma"
    )
    # İki kâğıtta da öğretmen anahtar-dışı yazıma tam puan vermiş.
    for _ in range(2):
        kagit_id = db.kagit_kaydet(
            KagitSonucu(
                sinav_kimlik=sinav.kimlik,
                islenen_sayfalar=[1],
                kutular=[
                    KutuSonucu(
                        soru_no=bosluk.no,
                        tanima=TanimaSonucu(metin="plazma zarı", guven=0.9),
                        puan=PuanSonucu(
                            puan=0.0, max_puan=bosluk.puan, guven=0.9, incele=True
                        ),
                    )
                ],
            ),
            ogrenci_ad="Öğrenci",
        )
        kutu = db.kutular(kagit_id)[0]
        db.kutu_guncelle(
            kutu_id=kutu["id"],
            son_puan=bosluk.puan,
            duzeltilmis_metin="plazma zarı",
            incele=False,
        )
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    c = TestClient(app)
    r = c.post(
        f"/sinav/{sinav.kimlik}/kabul-yazimlari-tara", follow_redirects=False
    )
    assert r.status_code == 303
    oneriler = db.ogrenilmis_kabuller(sinav.kimlik, bosluk.no)
    assert len(oneriler) == 1
    assert oneriler[0]["onay_durumu"] == "oneri"

    c.post(
        f"/kabul-yazimi/{oneriler[0]['id']}",
        data={"karar": "onayla", "kimlik": sinav.kimlik},
        follow_redirects=False,
    )
    onayli = db.ogrenilmis_kabuller(
        sinav.kimlik, bosluk.no, onay_durumu="onayli"
    )
    assert len(onayli) == 1
    sayfa = c.get(f"/sinav/{sinav.kimlik}").text
    assert "Öğrenilmiş kabul yazımları" in sayfa
    assert "plazma zarı" in sayfa


# --- Windows taşınabilirlik: /healthz + model_yollari platform/env desteği ---


def test_healthz_yalniz_loopback_token_gerekmez(tmp_path):
    from sinav_okur import __version__

    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    with TestClient(app, client=("127.0.0.1", 54321)) as istemci:
        yanit = istemci.get("/healthz")
    assert yanit.status_code == 200
    assert yanit.json() == {
        "app": "sinav-okur",
        "status": "ready",
        "version": __version__,
    }

    with TestClient(app, client=("203.0.113.8", 54322)) as istemci:
        assert istemci.get("/healthz").status_code == 403


def test_model_yollari_windowsta_apple_vision_kapali(monkeypatch, tmp_path):
    monkeypatch.setattr(sys, "platform", "win32")
    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    model_yollari = app.state.baglam.model_yollari
    assert not model_yollari["coklu"].exists()
    assert not model_yollari["vision"].exists()


def test_model_yollari_env_gecersiz_kilar(monkeypatch, tmp_path):
    ozel_trocr = tmp_path / "ozel-trocr"
    ozel_karakter = tmp_path / "ozel-karakter.keras"
    monkeypatch.setenv("SINAV_OKUR_TROCR_MODEL", str(ozel_trocr))
    monkeypatch.setenv("SINAV_OKUR_KARAKTER_MODEL", str(ozel_karakter))
    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    model_yollari = app.state.baglam.model_yollari
    assert model_yollari["trocr"] == ozel_trocr
    assert model_yollari["keras-karakter"] == ozel_karakter
