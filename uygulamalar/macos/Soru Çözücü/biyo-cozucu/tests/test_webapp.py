from __future__ import annotations

import json

import pytest

pytest.importorskip("fastapi")

from fastapi.testclient import TestClient

from biyo_cozucu.cozucu import Ayarlar
from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.webapp import uygulama_kur


def test_web_kullanici_yolu_olculmus_guvenli_ayarlari_kullanir(tmp_path):
    uygulama = uygulama_kur(tmp_path, motor_turu="yok", gommesiz=True)
    try:
        assert uygulama.state.durum.ayarlar.deneme_sayisi == 3
        assert uygulama.state.durum.ayarlar.inceleme_esigi == pytest.approx(0.70)
    finally:
        uygulama.state.kes_ve_coz_servisi.kapat()


@pytest.fixture
def istemci(tmp_path, ornekler, sahte_gomlemci, monkeypatch):
    """Gerçek model ve gömme modeli yüklenmeden ayağa kalkan uygulama."""
    from biyo_cozucu import gomme as gomme_modulu
    from biyo_cozucu import motor as motor_modulu

    monkeypatch.setattr(gomme_modulu, "gomlemci_yukle", lambda *a, **k: sahte_gomlemci)
    monkeypatch.setattr(
        motor_modulu,
        "motor_yukle",
        lambda *a, **k: SahteMotor(
            json.dumps({"adimlar": ["Adım bir", "Adım iki"], "cevap": "B",
                        "guven": 0.85, "uyari": ""}, ensure_ascii=False)
        ),
    )

    uygulama = uygulama_kur(tmp_path, motor_turu="sahte", ayarlar=Ayarlar())
    durum = uygulama.state.durum
    for ornek in ornekler:
        durum.depo.ornek_ekle(ornek)
    durum.indeksi_yenile()
    return TestClient(uygulama)


def test_kok_coz_sayfasina_yonlendirir(istemci):
    yanit = istemci.get("/")
    assert yanit.status_code == 200
    assert "Soru çöz" in yanit.text


def test_ornek_listesi_kayitlari_gosterir(istemci):
    yanit = istemci.get("/ornekler")
    assert yanit.status_code == 200
    assert "Mitoz bölünme" in yanit.text
    assert "kalitim_hesabi" in yanit.text


def test_ornek_arama_suzer(istemci):
    yanit = istemci.get("/ornekler", params={"ara": "çaprazlan"})
    assert "çaprazlan" in yanit.text
    assert "Enzimlerin çalışmasında" not in yanit.text


def test_ornek_turune_gore_suzme(istemci):
    yanit = istemci.get("/ornekler", params={"tur": "grafik_yorumlama"})
    assert "Fotosentez hızının" in yanit.text
    assert "Aa genotipli" not in yanit.text


def test_yeni_ornek_eklenir_ve_indekse_girer(istemci):
    yanit = istemci.post(
        "/ornek/yeni",
        data={
            "soru": "Bakteriler hangi âlemde sınıflandırılır?",
            "cozum": "Bakteriler prokaryot canlılardır.\nBakteri âleminde yer alırlar.",
            "cevap": "Bakteri âlemi",
            "secenekler": "",
            "konu": "",
            "cozum_turu": "",
            "kaynak": "test",
        },
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    durum = istemci.app.state.durum
    assert durum.depo.ornek_sayisi() == 6
    assert len(durum.indeks) == 6, "yeni örnek indekse hemen girmeli"


def test_ayni_soruyu_ikinci_kez_eklemek_catisir(istemci, ornekler):
    yanit = istemci.post(
        "/ornek/yeni",
        data={"soru": ornekler[0].soru, "cozum": "başka çözüm"},
        follow_redirects=False,
    )
    assert yanit.status_code == 409


def test_eksik_alanla_ornek_eklenemez(istemci):
    yanit = istemci.post("/ornek/yeni", data={"soru": "  ", "cozum": "  "})
    assert yanit.status_code == 400


def test_toplu_yapistirma_bloklari_ekler(istemci):
    metin = (
        "SORU: Ribozomun görevi nedir?\n"
        "ÇÖZÜM: Ribozom protein sentezler.\n"
        "CEVAP: Protein sentezi\n\n"
        "SORU: Lizozom ne yapar?\n"
        "ÇÖZÜM: Lizozom hücre içi sindirimden sorumludur.\n"
    )
    yanit = istemci.post("/ornek/toplu", data={"metin": metin, "uzerine_yaz": ""})
    assert yanit.status_code == 200
    assert "Eklenen: <strong>2</strong>" in yanit.text
    assert istemci.app.state.durum.depo.ornek_sayisi() == 7


def test_toplu_yapistirma_yinelenen_soruyu_atlar(istemci, ornekler):
    metin = f"SORU: {ornekler[0].soru}\nÇÖZÜM: Farklı bir çözüm.\n"
    yanit = istemci.post("/ornek/toplu", data={"metin": metin, "uzerine_yaz": ""})
    assert "Atlanan: <strong>1</strong>" in yanit.text


def test_ornek_guncelleme(istemci):
    istemci.post(
        "/ornek/1",
        data={
            "soru": "Güncellenmiş soru?",
            "cozum": "Güncellenmiş çözüm.",
            "cevap": "Yeni cevap",
            "secenekler": "",
            "konu": "hücre",
            "cozum_turu": "ezber_bilgi",
            "kaynak": "",
        },
        follow_redirects=False,
    )
    ornek = istemci.app.state.durum.depo.ornek(1)
    assert ornek.soru == "Güncellenmiş soru?"
    assert ornek.cozum_turu == "ezber_bilgi"


def test_ornek_silme_pasife_alir(istemci):
    istemci.post("/ornek/2/sil", follow_redirects=False)
    durum = istemci.app.state.durum
    assert durum.depo.ornek_sayisi() == 4
    assert durum.depo.ornek(2) is not None


# --- artımlı indeksleme (arayüz tarafı) ---


def _gom_sayaci(durum, monkeypatch) -> list[int]:
    """Gömlemciye kaç metin verildiğini kaydeder."""
    sayac: list[int] = []
    gercek = durum.gomlemci.gom

    def sayan_gom(metinler, *, sorgu: bool = False):
        sayac.append(len(metinler))
        return gercek(metinler, sorgu=sorgu)

    monkeypatch.setattr(durum.gomlemci, "gom", sayan_gom)
    return sayac


def test_ornek_ekleme_tum_koleksiyonu_yeniden_gommez(istemci, monkeypatch):
    """Tam yeniden kurulum her eklemede HER örneği yeniden gömdürüyordu.

    Hafıza 200 örneğe çıktığında bu, tek bir kayıt için dakikalara mal olur.
    """
    durum = istemci.app.state.durum
    sayac = _gom_sayaci(durum, monkeypatch)

    istemci.post(
        "/ornek/yeni",
        data={"soru": "Ribozomun görevi nedir?", "cozum": "Protein sentezler."},
        follow_redirects=False,
    )

    assert sayac == [1], "yalnız yeni örnek gömülmeli"
    assert len(durum.indeks) == 6


def test_ornek_silme_indeksten_de_cikarir(istemci, monkeypatch):
    durum = istemci.app.state.durum
    sayac = _gom_sayaci(durum, monkeypatch)

    istemci.post("/ornek/2/sil", follow_redirects=False)

    assert len(durum.indeks) == 4
    assert durum.indeks.anlamsal_hazir, "gömme satırı da düşmeli, indeks bayatlamamalı"
    assert sayac == [], "silme hiçbir şeyi yeniden gömdürmemeli"


def test_ornek_guncelleme_yalniz_o_ornegi_yeniden_gomer(istemci, monkeypatch):
    durum = istemci.app.state.durum
    sayac = _gom_sayaci(durum, monkeypatch)

    istemci.post(
        "/ornek/1",
        data={"soru": "Güncellenmiş soru?", "cozum": "Güncellenmiş çözüm."},
        follow_redirects=False,
    )

    assert sayac == [1]
    assert len(durum.indeks) == 5
    assert durum.indeks.ornekler[0].soru == "Güncellenmiş soru?"


def test_indeks_bayatken_artimli_yol_tam_kuruluma_duser(istemci):
    """Tutarsız bir indeks, yavaş bir indeksten kötüdür: uyuşmazlıkta
    artımlı yol reddedilip her şey baştan kurulmalı."""
    durum = istemci.app.state.durum
    # Indeksi elle bozarak depo ile arasındaki sayı bağını kopar.
    durum._indeks.ornekler.pop()
    durum._indeks.ornekler.pop()

    istemci.post(
        "/ornek/yeni",
        data={"soru": "Ribozomun görevi nedir?", "cozum": "Protein sentezler."},
        follow_redirects=False,
    )

    assert len(durum.indeks) == durum.depo.ornek_sayisi() == 6
    assert durum.indeks.anlamsal_hazir


def test_coz_akisi_cozum_uretir(istemci):
    yanit = istemci.post(
        "/coz",
        data={"soru": "Mayoz bölünmede kromozom sayısı nasıl değişir?",
              "secenekler": "", "ornek_sayisi": 3, "oz_kontrol": ""},
    )
    assert yanit.status_code == 200
    assert "Adım bir" in yanit.text
    assert "güven 0.85" in yanit.text or "güven" in yanit.text
    assert "Kullanılan referans örnekler" in yanit.text


def test_bos_soru_400_dondurur(istemci):
    yanit = istemci.post(
        "/coz", data={"soru": "   ", "secenekler": "", "ornek_sayisi": 3, "oz_kontrol": ""}
    )
    assert yanit.status_code == 400
    assert "boş olamaz" in yanit.text


def test_siklar_ayristirilir_ve_cevap_dogrulanir(istemci):
    yanit = istemci.post(
        "/coz",
        data={"soru": "Hangisi doğrudur?", "secenekler": "A) bir\nB) iki\nC) üç",
              "ornek_sayisi": 2, "oz_kontrol": ""},
    )
    assert yanit.status_code == 200
    # Model "B" döndürüyor ve B geçerli bir şık: uyarı çıkmamalı.
    assert "şıklarla eşleşmiyor" not in yanit.text


def test_cozum_onayi_yeni_ornek_yaratir(istemci):
    istemci.post(
        "/coz",
        data={"soru": "Kloroplastın görevi nedir?", "secenekler": "",
              "ornek_sayisi": 2, "oz_kontrol": ""},
    )
    durum = istemci.app.state.durum
    cozum_id = durum.depo.cozumler(limit=1)[0]["id"]
    onceki = durum.depo.ornek_sayisi()

    yanit = istemci.post(
        f"/cozum/{cozum_id}/onay", data={"islem": "onayla"}, follow_redirects=False
    )
    assert yanit.status_code == 303
    assert durum.depo.ornek_sayisi() == onceki + 1
    _cozum, satir = durum.depo.cozum(cozum_id)
    assert satir["onay_durumu"] == "onaylandi"


def test_duzeltme_ornege_duzeltilmis_metni_yazar(istemci):
    istemci.post(
        "/coz",
        data={"soru": "Golgi aygıtı ne yapar?", "secenekler": "",
              "ornek_sayisi": 2, "oz_kontrol": ""},
    )
    durum = istemci.app.state.durum
    cozum_id = durum.depo.cozumler(limit=1)[0]["id"]
    istemci.post(
        f"/cozum/{cozum_id}/onay",
        data={"islem": "duzelt", "duzeltilmis_cozum": "Doğru çözüm budur.",
              "duzeltilmis_cevap": "Salgı paketleme"},
        follow_redirects=False,
    )
    yeni = [o for o in durum.depo.ornekler() if o.soru == "Golgi aygıtı ne yapar?"]
    assert yeni and yeni[0].cozum == "Doğru çözüm budur."
    assert yeni[0].cevap == "Salgı paketleme"


def test_bos_duzeltme_reddedilir(istemci):
    istemci.post(
        "/coz",
        data={"soru": "Vakuol nedir?", "secenekler": "", "ornek_sayisi": 1,
              "oz_kontrol": ""},
    )
    durum = istemci.app.state.durum
    cozum_id = durum.depo.cozumler(limit=1)[0]["id"]
    yanit = istemci.post(
        f"/cozum/{cozum_id}/onay",
        data={"islem": "duzelt", "duzeltilmis_cozum": "   ", "duzeltilmis_cevap": ""},
    )
    assert yanit.status_code == 400


def test_reddedilen_cozum_ornege_donusmez(istemci):
    istemci.post(
        "/coz",
        data={"soru": "Peroksizom nedir?", "secenekler": "", "ornek_sayisi": 1,
              "oz_kontrol": ""},
    )
    durum = istemci.app.state.durum
    cozum_id = durum.depo.cozumler(limit=1)[0]["id"]
    onceki = durum.depo.ornek_sayisi()
    istemci.post(f"/cozum/{cozum_id}/onay", data={"islem": "reddet"},
                 follow_redirects=False)
    assert durum.depo.ornek_sayisi() == onceki


def test_bilinmeyen_islem_reddedilir(istemci):
    istemci.post("/coz", data={"soru": "Sentrozom nedir?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    cozum_id = istemci.app.state.durum.depo.cozumler(limit=1)[0]["id"]
    yanit = istemci.post(f"/cozum/{cozum_id}/onay", data={"islem": "sil"})
    assert yanit.status_code == 400


def test_olmayan_cozum_404(istemci):
    assert istemci.get("/cozum/9999").status_code == 404


def test_cozum_listesi_ve_suzme(istemci):
    istemci.post("/coz", data={"soru": "Bir soru?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    assert istemci.get("/cozumler").status_code == 200
    yanit = istemci.get("/cozumler", params={"onay": "onaylandi"})
    assert yanit.status_code == 200


def test_egitim_disa_aktarma_dosya_uretir(istemci, tmp_path):
    yanit = istemci.post(
        "/egitim/disa-aktar",
        data={"etiket": "v1", "kanitli": "evet", "kanit_sayisi": 2},
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    assert (tmp_path / "egitim" / "v1" / "train.jsonl").exists()
    assert istemci.get("/egitim").status_code == 200


def test_etiket_dizin_kacisina_izin_vermez(istemci, tmp_path):
    """Ayraçlar düşer, baştaki noktalar kırpılır: çıktı egitim/ altında ve gizli değil."""
    istemci.post(
        "/egitim/disa-aktar",
        data={"etiket": "../../kacis", "kanitli": "hayir", "kanit_sayisi": 0},
        follow_redirects=False,
    )
    assert not (tmp_path.parent / "kacis").exists()
    assert (tmp_path / "egitim" / "kacis" / "train.jsonl").exists()


def test_yalniz_noktadan_olusan_etiket_varsayilana_duser(istemci, tmp_path):
    """'..' tümüyle kırpılınca boş kalır; hedef egitim/ dizininin kendisi olmamalı."""
    istemci.post(
        "/egitim/disa-aktar",
        data={"etiket": "..", "kanitli": "hayir", "kanit_sayisi": 0},
        follow_redirects=False,
    )
    assert (tmp_path / "egitim" / "surum" / "train.jsonl").exists()


def test_indirme_yalniz_bilinen_dosyalara_izin_verir(istemci):
    istemci.post("/egitim/disa-aktar",
                 data={"etiket": "v1", "kanitli": "hayir", "kanit_sayisi": 0},
                 follow_redirects=False)
    surum_id = istemci.app.state.durum.depo.egitim_surumleri()[0]["id"]
    assert istemci.get(f"/egitim/indir/{surum_id}/train.jsonl").status_code == 200
    assert istemci.get(f"/egitim/indir/{surum_id}/biyo.db").status_code == 400


def test_pano_olcumleri_gosterir(istemci):
    istemci.post("/coz", data={"soru": "Pano sorusu?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    yanit = istemci.get("/pano")
    assert yanit.status_code == 200
    assert "referans örnek" in yanit.text
    assert "düzeltmesiz onay" in yanit.text


def test_pano_degerlendirme_yokken_orani_bos_birakir(istemci):
    """Bakılmamış çözümler 'yanlış' gibi görünmemeli."""
    istemci.post("/coz", data={"soru": "Değerlendirilmemiş?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    yanit = istemci.get("/pano")
    assert "—" in yanit.text


def test_coz_api_json_doner(istemci):
    yanit = istemci.post("/coz/api", data={"soru": "API sorusu?", "secenekler": ""})
    assert yanit.status_code == 200
    veri = yanit.json()
    assert veri["adimlar"] == ["Adım bir", "Adım iki"]
    assert "kaynaklar" in veri


# --- akış (SSE) ucu ---


def _sse_olaylari(metin: str) -> list[tuple[str, dict]]:
    """Ham SSE gövdesini (olay_adı, veri) çiftlerine ayrıştırır."""
    olaylar = []
    for cerceve in metin.split("\n\n"):
        if not cerceve.strip():
            continue
        ad, veri = "mesaj", []
        for satir in cerceve.split("\n"):
            if satir.startswith("event:"):
                ad = satir[6:].strip()
            elif satir.startswith("data:"):
                veri.append(satir[5:].lstrip(" "))
        if veri:
            olaylar.append((ad, json.loads("\n".join(veri))))
    return olaylar


def test_akis_ucu_sse_olaylari_dondurur(istemci):
    yanit = istemci.post(
        "/coz/akis",
        data={"soru": "Mitoz nedir?", "secenekler": "", "ornek_sayisi": 1,
              "oz_kontrol": ""},
    )
    assert yanit.status_code == 200
    assert yanit.headers["content-type"].startswith("text/event-stream")

    olaylar = _sse_olaylari(yanit.text)
    adlar = [ad for ad, _ in olaylar]
    assert "durum" in adlar
    assert adlar[-1] == "bitti"
    assert "hata" not in adlar

    bitti = next(v for ad, v in olaylar if ad == "bitti")
    assert "Adım bir" in bitti["html"]
    assert "Çözüm" in bitti["html"]


def test_akis_ucu_bos_soruyu_hata_olayiyla_bildirir(istemci):
    """Akış başladıktan sonra durum kodu değişemez; hata olay olarak gelmeli."""
    yanit = istemci.post(
        "/coz/akis",
        data={"soru": "   ", "secenekler": "", "ornek_sayisi": 1, "oz_kontrol": ""},
    )
    assert yanit.status_code == 200
    olaylar = _sse_olaylari(yanit.text)
    assert olaylar == [("hata", {"mesaj": "Soru boş olamaz."})]


def test_akis_ucu_cozumu_kaydeder(istemci):
    istemci.post(
        "/coz/akis",
        data={"soru": "Akıştan kaydedilen soru?", "secenekler": "",
              "ornek_sayisi": 1, "oz_kontrol": ""},
    )
    satirlar = istemci.app.state.durum.depo.cozumler(limit=10)
    assert any("Akıştan kaydedilen" in s["soru"] for s in satirlar)


def test_akis_ve_senkron_yol_ayni_cevabi_verir(istemci):
    """Aynı soru iki yoldan da aynı sonucu vermeli (önbellek devrede olsa bile)."""
    senkron = istemci.post(
        "/coz",
        data={"soru": "İki yol aynı mı?", "secenekler": "", "ornek_sayisi": 1,
              "oz_kontrol": ""},
    )
    assert "Adım bir" in senkron.text

    akis = istemci.post(
        "/coz/akis",
        data={"soru": "İki yol aynı mı?", "secenekler": "", "ornek_sayisi": 1,
              "oz_kontrol": ""},
    )
    bitti = next(v for ad, v in _sse_olaylari(akis.text) if ad == "bitti")
    assert "Adım bir" in bitti["html"]


def test_statik_stil_dosyasi_sunuluyor(istemci):
    yanit = istemci.get("/statik/stil.css")
    assert yanit.status_code == 200
    assert "--vurgu" in yanit.text


def test_statik_betik_sunuluyor(istemci):
    yanit = istemci.get("/statik/app.js")
    assert yanit.status_code == 200
    assert "data-akis-formu" in yanit.text


def test_indeks_yenileme_ucu_calisir(istemci):
    yanit = istemci.post("/indeks/yenile", data={"geri": "/ornekler"},
                         follow_redirects=False)
    assert yanit.status_code == 303
    # `geri` gerçekten okunmalı: Form(...) yerine query parametresi olarak
    # bırakıldığında gövdedeki değer yok sayılıp her zaman /pano dönüyordu,
    # yani koruma testleri yanlış sebeple yeşildi.
    assert yanit.headers["location"] == "/ornekler"


@pytest.mark.parametrize(
    "kotu",
    [
        "//kotu.example.com",
        "/\\kotu.example.com",   # tarayıcılar ters eğik çizgiyi / gibi çözer
        "https://kotu.example.com",
        "/iyi\r\nSet-Cookie: x=1",
        "",
    ],
)
def test_indeks_yenileme_disari_yonlendirmez(istemci, kotu):
    yanit = istemci.post("/indeks/yenile", data={"geri": kotu},
                         follow_redirects=False)
    assert yanit.headers["location"] == "/pano", f"{kotu!r} kabul edildi"


def test_indeks_yenileme_formu_bulundugu_sayfayi_gonderir(istemci):
    """Düğme hangi sayfadan basılırsa oraya dönmeli."""
    durum = istemci.app.state.durum
    from biyo_cozucu.modeller import Ornek
    durum.depo.ornek_ekle(Ornek(soru="İndeksi bayatlatan soru?", cozum="ç"))
    sayfa = istemci.get("/cozumler")
    assert 'name="geri" value="/cozumler"' in sayfa.text


# --- sayfalama, süzme ve hata sayfaları ---


def test_ornek_listesi_sayfalar(istemci):
    durum = istemci.app.state.durum
    from biyo_cozucu.modeller import Ornek
    for i in range(60):
        durum.depo.ornek_ekle(Ornek(soru=f"Sayfalama sorusu {i}?", cozum="çözüm"))

    ilk = istemci.get("/ornekler")
    assert "Sonraki" in ilk.text
    assert "sayfa 1/" in ilk.text

    ikinci = istemci.get("/ornekler", params={"sayfa": 2})
    assert "Önceki" in ikinci.text
    assert "sayfa 2/" in ikinci.text


def test_sayfalama_suzgeci_korur(istemci):
    durum = istemci.app.state.durum
    from biyo_cozucu.modeller import Ornek
    for i in range(60):
        durum.depo.ornek_ekle(Ornek(soru=f"Mitoz sayfalama {i}?", cozum="çözüm"))

    yanit = istemci.get("/ornekler", params={"ara": "mitoz", "sayfa": 2})
    assert "ara=mitoz" in yanit.text, "sayfa değişince süzgeç kaybolmamalı"


def test_asiri_sayfa_numarasi_son_sayfaya_kirpilir(istemci):
    yanit = istemci.get("/ornekler", params={"sayfa": 9999})
    assert yanit.status_code == 200
    assert "sayfa 1/1" in yanit.text


def test_olmayan_ornek_stilli_hata_sayfasi_dondurur(istemci):
    yanit = istemci.get("/ornek/9999")
    assert yanit.status_code == 404
    assert "Örnek bulunamadı" in yanit.text
    # Çıplak metin değil, gezinilebilir tam sayfa olmalı.
    assert "Geri dön" in yanit.text
    assert "<nav" in yanit.text


def test_olmayan_cozum_stilli_hata_sayfasi_dondurur(istemci):
    yanit = istemci.get("/cozum/9999")
    assert yanit.status_code == 404
    assert "Çözüm bulunamadı" in yanit.text
    assert "<nav" in yanit.text


def test_yinelenen_ornek_hatasi_stilli(istemci, ornekler):
    yanit = istemci.post(
        "/ornek/yeni", data={"soru": ornekler[0].soru, "cozum": "başka çözüm"},
        follow_redirects=False,
    )
    assert yanit.status_code == 409
    assert "zaten hafızada" in yanit.text
    assert "<nav" in yanit.text


def test_cozum_listesi_metinde_arar(istemci):
    istemci.post("/coz", data={"soru": "Ribozom ne yapar?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    istemci.post("/coz", data={"soru": "Lizozom ne yapar?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    yanit = istemci.get("/cozumler", params={"ara": "ribozom"})
    assert "Ribozom" in yanit.text
    assert "Lizozom" not in yanit.text


def test_yikici_islemler_onay_ister(istemci):
    """Geri dönüşü zor işlemler tek tıkla çalışmamalı."""
    ornek = istemci.get("/ornek/1")
    assert "data-onay" in ornek.text

    istemci.post("/coz", data={"soru": "Onay testi?", "secenekler": "",
                               "ornek_sayisi": 1, "oz_kontrol": ""})
    cozum_id = istemci.app.state.durum.depo.cozumler(limit=1)[0]["id"]
    sayfa = istemci.get(f"/cozum/{cozum_id}")
    assert "data-onay" in sayfa.text


# --- kaynaktan alım (PDF/Word/ses/video) ---


_KITAP_METNI = (
    "Biyoloji Soru Bankası\n17\n\n"
    "1. Aşağıdakilerden hangisi kloroplastta gerçekleşir?\n"
    "A) Krebs döngüsü\nB) Fotosentez\nC) Protein sentezi\n"
    "ÇÖZÜM\nKloroplast fotosentezin gerçekleştiği organeldir.\n"
    "Krebs döngüsü mitokondride olur, bu yüzden A elenir.\n"
    "CEVAP: B\n"
)


def test_alim_sayfasi_acilir(istemci):
    yanit = istemci.get("/alim")
    assert yanit.status_code == 200
    assert "Kaynaktan referans al" in yanit.text
    assert ".pdf" in yanit.text and ".mp3" in yanit.text and ".mp4" in yanit.text


def test_alim_metin_dosyasindan_aday_cikarir(istemci):
    yanit = istemci.post(
        "/alim",
        files={"dosya": ("kitap.txt", _KITAP_METNI.encode("utf-8"), "text/plain")},
    )
    assert yanit.status_code == 200
    assert "1 aday" in yanit.text
    assert "kloroplastta" in yanit.text
    # Önizleme aşamasında hiçbir şey yazılmamalı.
    assert istemci.app.state.durum.depo.ornek_sayisi() == 5


def test_alim_desteklenmeyen_turu_reddeder(istemci):
    yanit = istemci.post(
        "/alim", files={"dosya": ("sunum.pptx", b"x", "application/octet-stream")}
    )
    assert yanit.status_code == 400
    assert "desteklenmiyor" in yanit.text


def test_alim_secilenleri_hafizaya_yazar(istemci):
    yuk = json.dumps([{
        "soru": "Kloroplastta hangi olay gerçekleşir?",
        "cozum": "Kloroplast fotosentezin gerçekleştiği organeldir.",
        "cevap": "B",
        "secenekler": {"A": "Krebs", "B": "Fotosentez"},
        "cevap_turu": "coktan_secmeli",
        "konum": "s. 17",
        "kaynak": "kitap.txt",
    }], ensure_ascii=False)

    durum = istemci.app.state.durum
    onceki = durum.depo.ornek_sayisi()
    yanit = istemci.post(
        "/alim/aktar", data={"yuk": yuk, "secilenler": ["0"], "uzerine_yaz": ""}
    )
    assert yanit.status_code == 200
    assert durum.depo.ornek_sayisi() == onceki + 1

    yeni = next(o for o in durum.depo.ornekler() if "Kloroplastta hangi" in o.soru)
    assert yeni.cevap == "B"
    assert yeni.secenekler == {"A": "Krebs", "B": "Fotosentez"}
    assert "s. 17" in yeni.kaynak, "atıf sayfa numarasını taşımalı"
    assert len(durum.indeks) == durum.depo.ornek_sayisi(), "indeks yenilenmeli"


def test_alim_secilmeyen_aday_yazilmaz(istemci):
    yuk = json.dumps([
        {"soru": "Alınacak soru nedir peki?", "cozum": "Yeterince uzun bir çözüm metni."},
        {"soru": "Alınmayacak soru nedir?", "cozum": "Bu da yeterince uzun bir çözüm."},
    ], ensure_ascii=False)
    durum = istemci.app.state.durum
    istemci.post("/alim/aktar", data={"yuk": yuk, "secilenler": ["0"]})
    sorular = [o.soru for o in durum.depo.ornekler()]
    assert any("Alınacak soru" in s for s in sorular)
    assert not any("Alınmayacak" in s for s in sorular)


def test_alim_bozuk_yuk_stilli_hata_verir(istemci):
    yanit = istemci.post("/alim/aktar", data={"yuk": "{bozuk", "secilenler": ["0"]})
    assert yanit.status_code == 400
    assert "<nav" in yanit.text


def test_alim_dosya_adi_dizin_kacisina_izin_vermez(istemci):
    """Yüklenen ad yol parçası içeremez."""
    from biyo_cozucu.webapp.alim import _guvenli_ad
    assert _guvenli_ad("../../etc/passwd") == "passwd"
    assert _guvenli_ad("/mutlak/yol/kitap.pdf") == "kitap.pdf"
    assert _guvenli_ad("") == "yukleme"


def test_alim_word_belgesinden_okur(istemci, tmp_path):
    docx = pytest.importorskip("docx")
    yol = tmp_path / "notlar.docx"
    belge = docx.Document()
    for satir in _KITAP_METNI.splitlines():
        belge.add_paragraph(satir)
    belge.save(str(yol))

    yanit = istemci.post(
        "/alim",
        files={"dosya": ("notlar.docx", yol.read_bytes(),
                         "application/vnd.openxmlformats-officedocument.wordprocessingml.document")},
    )
    assert yanit.status_code == 200
    assert "kloroplastta" in yanit.text


# --- soru türü seçimi (çoktan seçmeli dışındaki biçimler) ---


def test_coz_formunda_tur_secici_var(istemci):
    yanit = istemci.get("/coz")
    assert "Soru türü" in yanit.text
    for ad in ("Doğru / Yanlış", "Boşluk doldurma", "Eşleştirme",
               "Sıralama", "Kısa cevap", "Açık uçlu"):
        assert ad in yanit.text, f"{ad} seçeneği yok"


def test_ornek_formunda_tur_secici_var(istemci):
    yanit = istemci.get("/ornek/yeni")
    assert "Soru türü" in yanit.text
    assert "Eşleştirme" in yanit.text


def test_elle_secilen_tur_cozume_islenir(istemci):
    istemci.post("/coz", data={
        "soru": "Mitozda kromozom sayısı korunur mu?", "secenekler": "",
        "ornek_sayisi": 1, "oz_kontrol": "", "cevap_turu": "dogru_yanlis",
    })
    cozum, _satir = istemci.app.state.durum.depo.cozum(
        istemci.app.state.durum.depo.cozumler(limit=1)[0]["id"]
    )
    assert cozum.cevap_turu == "dogru_yanlis"


def test_tur_secilmezse_sorudan_cikarilir(istemci):
    istemci.post("/coz", data={
        "soru": "Mitoz evrelerini sırasıyla sıralayınız.", "secenekler": "",
        "ornek_sayisi": 1, "oz_kontrol": "", "cevap_turu": "",
    })
    cozum, _satir = istemci.app.state.durum.depo.cozum(
        istemci.app.state.durum.depo.cozumler(limit=1)[0]["id"]
    )
    assert cozum.cevap_turu == "siralama"


def test_siksiz_ornek_turu_metinden_alir(istemci):
    """Şıksız diye her şey açık uçlu sayılmamalı."""
    istemci.post("/ornek/yeni", data={
        "soru": "Fotosentez …… organelinde gerçekleşir.",
        "cozum": "Fotosentez kloroplastta gerçekleşir.",
        "cevap": "kloroplast", "secenekler": "", "konu": "",
        "cozum_turu": "", "cevap_turu": "", "kaynak": "",
    }, follow_redirects=False)
    durum = istemci.app.state.durum
    ornek = next(o for o in durum.depo.ornekler() if "……" in o.soru)
    assert ornek.cevap_turu == "bosluk_doldurma"


def test_akis_ucu_tur_parametresini_kabul_eder(istemci):
    yanit = istemci.post("/coz/akis", data={
        "soru": "Organelleri görevleriyle eşleştiriniz.", "secenekler": "",
        "ornek_sayisi": 1, "oz_kontrol": "", "cevap_turu": "eslestirme",
    })
    assert yanit.status_code == 200
    assert [ad for ad, _ in _sse_olaylari(yanit.text)][-1] == "bitti"


# --- pano: hafıza kapsamı ---


def test_pano_kapsam_bolumunu_gosterir(istemci):
    yanit = istemci.get("/pano")
    assert yanit.status_code == 200
    assert "Hafıza kapsamı" in yanit.text
    assert "RAG eşiğine kalan" in yanit.text
    # 5 örneklik fixture'da çoğu çözüm türü boş; bunlar açıkça sayılmalı.
    assert "Hiç örneği olmayan çözüm türleri" in yanit.text
    assert "deney_kurgusu" in yanit.text


def test_pano_kapsam_ornek_eklendikce_guncellenir(istemci):
    istemci.post(
        "/ornek/yeni",
        data={
            "soru": "Kontrol grubu olmayan bir deneyin sonucu neden güvenilmezdir?",
            "cozum": "Karşılaştırma noktası yoktur.\nDeğişkenin etkisi ayrıştırılamaz.",
            "cozum_turu": "deney_kurgusu",
        },
        follow_redirects=False,
    )
    yanit = istemci.get("/pano")
    assert "deney_kurgusu" not in yanit.text.split("Hiç örneği olmayan çözüm türleri")[1].split("</p>")[0]


# --- kör değerlendirme arayüzü ---


def test_degerlendirme_sayfasi_acilir(istemci):
    yanit = istemci.get("/degerlendirme")
    assert yanit.status_code == 200
    assert "Kör değerlendirme" in yanit.text
    # Dışlama kuralı kullanıcıya açıklanmalı: ölçümün anlamı buna bağlı.
    assert "dışlanarak" in yanit.text


def _test_dilimi_dolana_kadar_ekle(istemci) -> int:
    """`bol()` her örneği imzasına göre bağımsız atıyor; 5 örnekle test dilimi
    boş kalıyor. Ölçümü sınayabilmek için dilim dolana kadar örnek eklenir."""
    from biyo_cozucu.modeller import Ornek
    from biyo_cozucu.veri.disa_aktar import bol

    durum = istemci.app.state.durum
    for i in range(60):
        durum.depo.ornek_ekle(
            Ornek(
                soru=f"Değerlendirme sorusu {i} nasıl açıklanır?",
                cozum=f"Bu olay {i} numaralı mekanizmayla açıklanır.",
                cevap=f"cevap {i}",
            )
        )
        _egitim, _dogrulama, test = bol(durum.depo.ornekler())
        if len(test) >= 2:
            return len(test)
    raise AssertionError("test dilimi doldurulamadı")


def test_degerlendirme_kosusu_akisla_calisir_ve_kaydedilir(istemci):
    _test_dilimi_dolana_kadar_ekle(istemci)
    with istemci.stream(
        "POST", "/degerlendirme/akis", data={"etiket": "taban"}
    ) as yanit:
        assert yanit.status_code == 200
        govde = "".join(yanit.iter_text())

    assert "event: ilerleme" in govde, "koşu canlı ilerleme bildirmeli"
    assert "event: bitti" in govde

    kosular = istemci.app.state.durum.depo.kosular()
    assert len(kosular) == 1
    assert kosular[0]["etiket"] == "taban"
    assert kosular[0]["ornek_sayisi"] >= 1


def test_degerlendirme_gecmisi_listelenir(istemci):
    _test_dilimi_dolana_kadar_ekle(istemci)
    with istemci.stream("POST", "/degerlendirme/akis", data={"etiket": "ilk"}) as y:
        "".join(y.iter_text())
    yanit = istemci.get("/degerlendirme")
    assert "ilk" in yanit.text
    assert "Koşu geçmişi" in yanit.text


def test_bos_test_kumesinde_anlamli_uyari(istemci):
    """Hafıza küçükken test dilimi boş kalabilir; sessiz sıfır sonuç yerine
    ne yapılacağını söyleyen bir mesaj gelmeli."""
    durum = istemci.app.state.durum
    for ornek in durum.depo.ornekler():
        durum.depo.ornek_sil(ornek.id)

    yanit = istemci.get("/degerlendirme")
    assert "Test kümesi boş" in yanit.text
    assert "30 referans örnek" in yanit.text, "kaç örnek gerektiği söylenmeli"

    with istemci.stream("POST", "/degerlendirme/akis", data={"etiket": ""}) as y:
        govde = "".join(y.iter_text())
    assert "event: hata" in govde
    assert "Test kümesi boş" in govde


def test_onaydan_turemis_test_ornekleri_uyari_olarak_gosterilir(istemci):
    """Onaydan gelen örnek, modelin kendi çıktısını referans yapar.

    Kör koşu bunların HAFIZADAN GETİRİLMESİNİ engelliyor, ama puanlamanın
    karşılaştırdığı metin yine modelin kendi eski çıktısı; doğruluk olduğundan
    yüksek çıkar. Ölçüm bunu gizlememeli.
    """
    from biyo_cozucu.modeller import Ornek
    from biyo_cozucu.veri.disa_aktar import bol

    durum = istemci.app.state.durum
    for i in range(60):
        durum.depo.ornek_ekle(
            Ornek(
                soru=f"Sızıntı sorusu {i} nasıl açıklanır?",
                cozum=f"Mekanizma {i}.",
                kaynak="öğretmen onayı",
            )
        )
        _e, _d, test = bol(durum.depo.ornekler())
        if sum(1 for o in test if o.kaynak == "öğretmen onayı") >= 1:
            break

    yanit = istemci.get("/degerlendirme")
    assert "onay döngüsünden geliyor" in yanit.text
    assert "olduğundan yüksek gösterir" in yanit.text


def test_cozum_onayi_artimli_indeksler(istemci, monkeypatch):
    """Onay döngüsü de tüm koleksiyonu yeniden gömdürmemeli."""
    istemci.post(
        "/coz",
        data={"soru": "Kloroplastta hangi olay gerçekleşir?", "secenekler": "",
              "ornek_sayisi": 3, "oz_kontrol": ""},
    )
    durum = istemci.app.state.durum
    cozum_id = durum.depo.cozumler(limit=1)[0]["id"]
    sayac = _gom_sayaci(durum, monkeypatch)

    istemci.post(
        f"/cozum/{cozum_id}/onay", data={"islem": "onayla"}, follow_redirects=False
    )
    assert sayac == [1], "yalnız onaylanan örnek gömülmeli"


# --- görsel soru (arayüz) ---


def _kucuk_png() -> bytes:
    import io

    from PIL import Image

    tampon = io.BytesIO()
    Image.new("RGB", (20, 12), (0, 160, 90)).save(tampon, format="PNG")
    return tampon.getvalue()


def test_coz_formu_gorsel_alani_tasir(istemci):
    yanit = istemci.get("/coz")
    assert 'name="gorsel"' in yanit.text
    assert "multipart/form-data" in yanit.text


def test_gorselli_soru_yuklenip_cozulur(istemci):
    pytest.importorskip("PIL")
    yanit = istemci.post(
        "/coz",
        data={"soru": "Grafikte fotosentez hızı nasıl değişiyor?", "secenekler": "",
              "ornek_sayisi": 3, "oz_kontrol": ""},
        files={"gorsel": ("sekil.png", _kucuk_png(), "image/png")},
    )
    assert yanit.status_code == 200
    durum = istemci.app.state.durum
    kayit = durum.depo.cozumler(limit=1)[0]
    cozum, _satir = durum.depo.cozum(kayit["id"])
    assert cozum.gorsel, "görsel imzası çözüme yazılmalı"
    assert (durum.kok / "gorseller" / f"{cozum.gorsel}.png").is_file()


def test_gorsel_desteklemeyen_motorda_uyari_gosterilir(istemci):
    """Sahte motor görsel okuyamaz; kullanıcı şekle bakıldığını sanmamalı."""
    pytest.importorskip("PIL")
    yanit = istemci.post(
        "/coz",
        data={"soru": "Şekilde ne görülüyor?", "secenekler": "",
              "ornek_sayisi": 3, "oz_kontrol": ""},
        files={"gorsel": ("sekil.png", _kucuk_png(), "image/png")},
    )
    assert "görsel okuyamıyor" in yanit.text


def test_bozuk_gorsel_anlamli_hata_verir(istemci):
    yanit = istemci.post(
        "/coz",
        data={"soru": "Soru?", "secenekler": "", "ornek_sayisi": 3, "oz_kontrol": ""},
        files={"gorsel": ("bozuk.png", b"bu bir goruntu degil", "image/png")},
    )
    assert yanit.status_code == 400
    assert "okunamadı" in yanit.text


def test_gorselsiz_gonderim_calismaya_devam_eder(istemci):
    """Boş dosya alanı tarayıcıdan yine de gelir; görselsiz akış bozulmamalı."""
    yanit = istemci.post(
        "/coz",
        data={"soru": "Mitoz nedir?", "secenekler": "", "ornek_sayisi": 3,
              "oz_kontrol": ""},
        files={"gorsel": ("", b"", "application/octet-stream")},
    )
    assert yanit.status_code == 200
    assert "Adım bir" in yanit.text


def test_gorselli_akis_ucu_calisir(istemci):
    pytest.importorskip("PIL")
    with istemci.stream(
        "POST", "/coz/akis",
        data={"soru": "Grafikte ne var?", "secenekler": "", "ornek_sayisi": 3,
              "oz_kontrol": "", "cevap_turu": ""},
        files={"gorsel": ("sekil.png", _kucuk_png(), "image/png")},
    ) as yanit:
        govde = "".join(yanit.iter_text())
    assert "event: bitti" in govde


def test_akista_bozuk_gorsel_olay_olarak_bildirilir(istemci):
    """Akış açıldıktan sonra HTTP durum kodu değiştirilemez; hata olay olmalı."""
    with istemci.stream(
        "POST", "/coz/akis",
        data={"soru": "Soru?", "secenekler": "", "ornek_sayisi": 3,
              "oz_kontrol": "", "cevap_turu": ""},
        files={"gorsel": ("bozuk.png", b"gecersiz", "image/png")},
    ) as yanit:
        govde = "".join(yanit.iter_text())
    assert "event: hata" in govde
    assert "okunamadı" in govde


def test_bayat_indekste_guncelleme_ornegi_iki_kez_yazmaz(istemci):
    """Regresyon: "ekleme mi güncelleme mi" kararı örnek SAYISINA dayanıyordu.

    İndeks depodan bir örnek geride kalınca (ör. CLI'da `ornek-ekle
    --indekssiz` kullanıldıktan sonra) güncelleme, ekleme sanılıyor ve zaten
    indekste olan örnek ikinci kez yazılıyordu. Yinelenen kayıt kanıt
    yuvalarını yiyor (`benzer_ornekler` havuzu id'ye değil KONUMA anahtarlı)
    ve sayılar eşitlendiği için bayatlık göstergesi de susuyordu.
    """
    from biyo_cozucu.modeller import Ornek

    durum = istemci.app.state.durum
    # İndekse yazmadan depoya kayıt: indeks bir örnek geride kalır.
    durum.depo.ornek_ekle(Ornek(soru="İndekssiz soru?", cozum="Çözüm."))
    assert len(durum.indeks) == durum.depo.ornek_sayisi() - 1

    istemci.post(
        "/ornek/1",
        data={"soru": "Güncellenmiş soru?", "cozum": "Güncellenmiş çözüm."},
        follow_redirects=False,
    )

    idler = [o.id for o in durum.indeks.ornekler]
    assert len(idler) == len(set(idler)), f"örnek indekse iki kez girdi: {idler}"
    # Tutarlılık denetimi ayrı: işlem başarılı olsa da sayılar tutmuyorsa
    # indeks başka bir nedenle bayattır ve tam kurulumla onarılır.
    assert len(durum.indeks) == durum.depo.ornek_sayisi()
    assert not durum.durum()["indeks_bayat"], "bayat indeks onarılmalı"


def test_zaten_indekste_olmayan_ornegi_silmek_yeniden_gommez(istemci, monkeypatch):
    """Silme düğmesine iki kez tıklamak tüm koleksiyonu yeniden gömdürmemeli."""
    durum = istemci.app.state.durum
    istemci.post("/ornek/2/sil", follow_redirects=False)
    sayac = _gom_sayaci(durum, monkeypatch)

    istemci.post("/ornek/2/sil", follow_redirects=False)

    assert sayac == [], "ikinci silme hiçbir şeyi yeniden gömdürmemeli"


def test_eszamanli_ekleme_gomme_satirlarini_kaydirmaz(istemci, monkeypatch):
    """Regresyon: kilit yalnız `_indeks` OKUNURKEN tutuluyordu.

    FastAPI'nin senkron rotaları iş parçacığı havuzunda gerçekten paralel
    koşuyor ve gömme çağrısı yavaş; iki eşzamanlı ekleme gömme satırlarını
    örneklerle kaydırıyordu. Uzunluklar tuttuğu için `anlamsal_hazir` True
    kalıyor ve hiçbir denetim uyarmıyordu — anlamsal arama sessizce yanlış
    örneği kanıt gösteriyordu.
    """
    import threading
    import time

    import numpy as np

    from biyo_cozucu.modeller import Ornek

    durum = istemci.app.state.durum
    gercek = durum.gomlemci.gom

    def yavas_gom(metinler, *, sorgu: bool = False):
        time.sleep(0.05)  # yarış penceresini aç
        return gercek(metinler, sorgu=sorgu)

    monkeypatch.setattr(durum.gomlemci, "gom", yavas_gom)

    def ekle(n: int) -> None:
        ornek = Ornek(soru=f"Eşzamanlı soru {n}?", cozum=f"Çözüm {n}.")
        ornek.id = durum.depo.ornek_ekle(ornek)
        durum.ornegi_indeksle(ornek)

    is_parcaciklari = [threading.Thread(target=ekle, args=(n,)) for n in (10, 11)]
    for i in is_parcaciklari:
        i.start()
    for i in is_parcaciklari:
        i.join()

    indeks = durum.indeks
    assert len(indeks) == durum.depo.ornek_sayisi()
    assert indeks.anlamsal_hazir
    beklenen = gercek([o.indeks_metni() for o in indeks.ornekler])
    for sira in range(len(indeks.ornekler)):
        assert np.allclose(indeks.gomme[sira], beklenen[sira], atol=1e-6), (
            f"{sira}. satırdaki vektör başka bir örneğe ait"
        )


def test_soruyu_baska_ornekle_ayni_yapmak_500_vermez(istemci, ornekler):
    """Güncelleme `soru_imza` UNIQUE kısıtını düşürebiliyordu → HTTP 500.

    Yeni örnek yolunda aynı durum zaten 409 veriyordu; güncelleme de aynı
    davranmalı.
    """
    yanit = istemci.post(
        "/ornek/1",
        data={"soru": ornekler[1].soru, "cozum": "Başka bir çözüm."},
        follow_redirects=False,
    )
    assert yanit.status_code == 409
    assert "zaten hafızada" in yanit.text
