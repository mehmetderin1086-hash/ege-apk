"""Ders kitabı pasaj katmanı: depo, indeks, getirme ve isteme giriş.

Pasaj, hafızanın ikinci birimi: `Ornek` "böyle çözülür" derken `Pasaj`
"bu doğrudur" der. Buradaki testler ikisinin karışmamasını kilitliyor —
pasajın referans çözüm gibi sunulması, modele onu taklit ettirirdi.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.depo import Depo
from biyo_cozucu.hafiza.pasaj import PasajIndeksi, benzer_pasajlar
from biyo_cozucu.istemler import cozum_mesajlari
from biyo_cozucu.modeller import Kanit, Pasaj


@pytest.fixture
def pasajlar() -> list[Pasaj]:
    return [
        Pasaj(
            metin=(
                "Fotosentez kloroplastta gerçekleşir. Işık enerjisi tilakoit "
                "zarlarda yakalanır ve kimyasal enerjiye çevrilir."
            ),
            baslik="Fotosentez",
            kaynak="Campbell Biyoloji",
            sayfa=180,
        ),
        Pasaj(
            metin=(
                "Mitokondride oksidatif fosforilasyon yoluyla ATP üretilir. "
                "Elektron taşıma sistemi iç zarda bulunur."
            ),
            baslik="Hücresel solunum",
            kaynak="Campbell Biyoloji",
            sayfa=195,
        ),
    ]


# --- depo ---


def test_pasaj_eklenir_ve_okunur(tmp_path, pasajlar):
    depo = Depo(tmp_path / "t.db")
    assert depo.pasaj_ekle(pasajlar[0]) is not None
    assert depo.pasaj_say() == 1
    geri = depo.pasajlar()[0]
    assert geri.kaynak == "Campbell Biyoloji"
    assert geri.sayfa == 180


def test_ayni_pasaj_iki_kez_eklenmez(tmp_path, pasajlar):
    """Yinelenen pasaj hata değil beklenen durum: aynı kitap yeniden alınabilir."""
    depo = Depo(tmp_path / "t.db")
    depo.pasaj_ekle(pasajlar[0])
    assert depo.pasaj_ekle(pasajlar[0]) is None
    assert depo.pasaj_say() == 1


def test_bos_pasaj_reddedilir(tmp_path):
    depo = Depo(tmp_path / "t.db")
    assert depo.pasaj_ekle(Pasaj(metin="   ")) is None
    assert depo.pasaj_say() == 0


def test_kaynak_dagilimi(tmp_path, pasajlar):
    depo = Depo(tmp_path / "t.db")
    for p in pasajlar:
        depo.pasaj_ekle(p)
    depo.pasaj_ekle(Pasaj(metin="Başka kitaptan bir metin.", kaynak="MEB 9"))
    assert depo.pasaj_kaynaklari() == {"Campbell Biyoloji": 2, "MEB 9": 1}
    assert depo.pasaj_say(kaynak="MEB 9") == 1


# --- getirme ---


def test_ilgili_pasaj_bulunur(pasajlar):
    indeks = PasajIndeksi.kur(pasajlar)
    bulunan = benzer_pasajlar(indeks, "Kloroplastta hangi olay gerçekleşir?", k=1)
    assert len(bulunan) == 1
    assert "Fotosentez" in bulunan[0].baslik


def test_kitap_yokken_getirme_bos_doner():
    assert benzer_pasajlar(None, "herhangi bir soru") == []
    assert benzer_pasajlar(PasajIndeksi.kur([]), "herhangi bir soru") == []


def test_uzun_pasaj_cumle_sinirinda_kirpilir():
    """Yarım cümlelik bir 'olgu' eksik bilgiyi tam bilgi gibi gösterir."""
    uzun = Pasaj(metin="Birinci cümle burada. " * 100, baslik="Uzun bölüm")
    bulunan = benzer_pasajlar(PasajIndeksi.kur([uzun]), "Birinci cümle", k=1, azami_karakter=100)
    assert bulunan
    metin = bulunan[0].metin
    assert len(metin) <= 101
    assert metin.endswith(".") or metin.endswith("…")


# --- isteme giriş ---


def _kaynak_bloklari(mesajlar: list[dict[str, str]]) -> list[dict[str, str]]:
    """Sistem istemindeki kural metnini değil, gerçek kaynak bloklarını seçer."""
    return [m for m in mesajlar if m["role"] != "system" and "[DERS KİTABI" in m["content"]]


def test_pasaj_isteme_ders_kitabi_blogu_olarak_girer(pasajlar):
    mesajlar = cozum_mesajlari("Kloroplast ne yapar?", [], pasajlar=pasajlar[:1])
    kaynak_mesajlari = _kaynak_bloklari(mesajlar)
    assert len(kaynak_mesajlari) == 1
    assert "Campbell Biyoloji" in kaynak_mesajlari[0]["content"]
    assert "s. 180" in kaynak_mesajlari[0]["content"]
    # Kural yalnız kaynak verildiğinde sistem istemine eklenmeli.
    assert "DERS KİTABI" in mesajlar[0]["content"]


def test_ortak_hafizada_kitap_olgu_ornek_cozumden_sonra_gelir(pasajlar):
    """Model, örneğin cevabını değil en yakın kitaptaki olguyu uygular."""
    kanit = Kanit(
        etiket="Ö1",
        ornek_id=1,
        soru="Eski soru?",
        cozum="Eski çözüm adımı.",
        konu="hücre",
        cozum_turu="ezber_bilgi",
        skor=0.8,
        cevap="B",
    )

    mesajlar = cozum_mesajlari("Yeni soru?", [kanit], pasajlar=pasajlar[:1])
    kaynak_sirasi = next(
        i
        for i, m in enumerate(mesajlar)
        if m["role"] != "system" and "[DERS KİTABI" in m["content"]
    )
    ornek_yaniti_sirasi = next(i for i, m in enumerate(mesajlar) if m["role"] == "assistant")

    assert kaynak_sirasi > ornek_yaniti_sirasi
    assert "ortak hafızandır" in mesajlar[0]["content"]


def test_pasajsiz_istem_degismez(pasajlar):
    """Kitap alınmamış kurulumda istem bit bit eskisi gibi kalmalı."""
    kanit = Kanit(
        etiket="Ö1",
        ornek_id=1,
        soru="S?",
        cozum="1. adım.",
        konu="hücre",
        cozum_turu="ezber_bilgi",
        skor=0.8,
        cevap="B",
    )
    once = cozum_mesajlari("Soru?", [kanit])
    sonra = cozum_mesajlari("Soru?", [kanit], pasajlar=[])
    assert once == sonra
    assert not any("DERS KİTABI" in m["content"] for m in once)


def test_pasaj_referans_cozum_gibi_sunulmaz(pasajlar):
    """Pasaj asistan yanıtı olarak girerse model onu çözüm sanıp taklit eder."""
    mesajlar = cozum_mesajlari("Kloroplast ne yapar?", [], pasajlar=pasajlar)
    assert _kaynak_bloklari(mesajlar)
    for mesaj in _kaynak_bloklari(mesajlar):
        assert mesaj["role"] == "user"
    # Kaynak metin JSON çözüm biçiminde de olmamalı.
    asistan = [m for m in mesajlar if m["role"] == "assistant"]
    for mesaj in asistan:
        assert "DERS KİTABI" not in mesaj["content"]
        json.loads(mesaj["content"])  # asistan mesajları hâlâ geçerli JSON


# --- kitap alma (PDF → pasaj) ---


def test_paragraflara_bol_gurultuyu_atar():
    from biyo_cozucu.veri.kitap import paragraflara_bol

    metin = (
        "151\n\nBÖLÜM 8\n\n"
        + "Fotosentez ışık enerjisini kimyasal enerjiye çevirir. " * 6
        + "\n\nŞEKİL 8.2\n"
    )
    pasajlar = paragraflara_bol(metin)
    assert pasajlar
    birlesik = " ".join(pasajlar)
    assert "151" not in birlesik
    assert "BÖLÜM 8" not in birlesik
    assert "Fotosentez" in birlesik


def test_satir_sonu_tiresi_birlestirilir():
    """OCR 'fotosen-\\ntez' üretir; birleştirilmezse terim aranamaz hale gelir."""
    from biyo_cozucu.veri.kitap import paragraflara_bol

    metin = "Bitkilerde fotosen-\ntez olayı kloroplastta gerçekleşir. " * 5
    assert "fotosentez" in " ".join(paragraflara_bol(metin))


def test_uzun_metin_cumle_sinirindan_bolunur():
    from biyo_cozucu.veri.kitap import AZAMI_KARAKTER, paragraflara_bol

    metin = "Hücre zarı seçici geçirgendir ve maddeleri düzenler. " * 60
    pasajlar = paragraflara_bol(metin)
    assert len(pasajlar) > 1
    for p in pasajlar:
        assert len(p) <= AZAMI_KARAKTER + 60


def test_kitap_alma_sayfa_sayfa_yazar_ve_yinelemez(tmp_path, monkeypatch):
    """Koşu yarıda kesilirse ikinci koşu kaldığı yerden devam etmeli."""
    from biyo_cozucu.veri import kitap as kitap_modulu

    sayfalar = [
        "Fotosentez kloroplastta gerçekleşir ve ışık enerjisini bağlar. " * 5,
        "Mitokondride ATP üretilir; elektron taşıma sistemi iç zardadır. " * 5,
    ]

    class _SahteSayfa:
        def __init__(self, metin: str):
            self._metin = metin

        def get_textpage(self):
            sahte = self

            class _TP:
                def get_text_range(self_inner):
                    return sahte._metin

            return _TP()

    class _SahteBelge:
        def __init__(self, *_a, **_k):
            self._sayfalar = [_SahteSayfa(m) for m in sayfalar]

        def __len__(self):
            return len(self._sayfalar)

        def __getitem__(self, i):
            return self._sayfalar[i]

        def close(self):
            pass

    class _SahtePdfium:
        PdfDocument = _SahteBelge

    monkeypatch.setitem(__import__("sys").modules, "pypdfium2", _SahtePdfium)
    pdf = tmp_path / "kitap.pdf"
    pdf.write_bytes(b"%PDF-1.4 sahte")
    depo = Depo(tmp_path / "t.db")

    ozetler = list(kitap_modulu.kitabi_al(pdf, depo, kaynak="Test Kitabı", ocr="kapali"))
    assert ozetler
    ilk_pasaj = ozetler[-1].pasaj
    assert ilk_pasaj > 0
    assert depo.pasaj_say(kaynak="Test Kitabı") == ilk_pasaj
    # Sayfa numarası atıf için korunmalı.
    assert {p.sayfa for p in depo.pasajlar()} == {1, 2}

    # İkinci koşu aynı metni yeniden yazmamalı.
    ikinci = list(kitap_modulu.kitabi_al(pdf, depo, kaynak="Test Kitabı", ocr="kapali"))
    assert ikinci[-1].pasaj == 0
    assert ikinci[-1].atlanan == ilk_pasaj
    assert depo.pasaj_say(kaynak="Test Kitabı") == ilk_pasaj


# --- inceleme bulguları ---


def test_ilgisiz_pasaj_ders_kitabi_otoritesiyle_dayatilmaz():
    """En kötü hata sınıfı: alakasız bir olgu, kaynak etiketiyle modele sunulur.

    RRF sıralaması göreli olduğu için birinci sonucun oranı daima 1,0'dır;
    mutlak taban olmadan indekste ilgili hiçbir pasaj yokken bile bir metin
    isteme giriyordu.
    """
    difuzyon = Pasaj(
        metin=(
            "Difüzyon, moleküllerin çok yoğun ortamdan az yoğun ortama "
            "geçişidir ve enerji harcanmaz."
        ),
        baslik="Difüzyon",
    )
    indeks = PasajIndeksi.kur([difuzyon])

    assert benzer_pasajlar(indeks, "Mendel çaprazlamasında fenotip oranı nedir?") == []
    # İlgili sorguda hâlâ bulunmalı — filtre her şeyi susturmamalı.
    assert benzer_pasajlar(indeks, "Difüzyonda enerji harcanır mı?")


def test_pasaj_sayisi_sifir_kaynak_metnini_tumden_kapatir():
    """A/B ölçümünün kontrol kolu: 0 iken tek pasaj bile sızmamalı."""
    p = Pasaj(metin="Fotosentez kloroplastta gerçekleşir ve ATP üretilir.", baslik="Fotosentez")
    assert benzer_pasajlar(PasajIndeksi.kur([p]), "Fotosentez nerede olur?", k=0) == []


def test_paragraf_sinirlari_korunur():
    """Gürültü temizliği boş satırları yutarsa tüm sayfa tek gövde olur."""
    from biyo_cozucu.veri.kitap import paragraflara_bol

    metin = (
        "151\n\n"
        + "Fotosentez ışık enerjisini kimyasal enerjiye çevirir ve kloroplastta olur. " * 4
        + "\n\nBÖLÜM 9\n\n"
        + "Hücresel solunum mitokondride gerçekleşir ve ATP üretir bu süreçte. " * 4
    )
    pasajlar = paragraflara_bol(metin)

    assert len(pasajlar) >= 2, "iki ayrı konu tek pasaja birleşmemeli"
    assert any("Fotosentez" in p and "solunum" not in p for p in pasajlar)


def test_kisa_artik_parca_atilmaz():
    """Sessizce düşen metin hiçbir sayaca yazılmıyor; kaybın görünmezi en kötüsü."""
    from biyo_cozucu.veri.kitap import paragraflara_bol

    govde = "Hücre zarı seçici geçirgendir ve madde geçişini düzenler. " * 40
    kuyruk = "Kısa son not."
    pasajlar = paragraflara_bol(govde + kuyruk)

    assert kuyruk in " ".join(pasajlar)


def _sahte_pdf_kur(monkeypatch, sayfa_metinleri: list[str]):
    """Metin katmanı verilen sahte bir PDF belgesi kurar."""

    class _Sayfa:
        def __init__(self, metin: str):
            self._metin = metin

        def get_textpage(self):
            metin = self._metin

            class _TP:
                def get_text_range(self):
                    return metin

            return _TP()

    class _Belge:
        def __init__(self, *_a, **_k):
            self._s = [_Sayfa(m) for m in sayfa_metinleri]

        def __len__(self):
            return len(self._s)

        def __getitem__(self, i):
            return self._s[i]

        def close(self):
            pass

    class _Pdfium:
        PdfDocument = _Belge

    monkeypatch.setitem(__import__("sys").modules, "pypdfium2", _Pdfium)


def test_ocr_bos_donusu_bos_sayfa_sayilmaz(tmp_path, monkeypatch):
    """Gerçek kayıp senaryosu: OCR arka ucu düştü, 650 sayfa 'boş' sayıldı.

    Metinsiz sayfalar OCR'a gidiyor; OCR de boş dönerse bu 'sayfa boşmuş'
    demek DEĞİL. İkisi aynı sayaca yazılırsa koşu hatasız görünüp sonuna
    kadar gider ve kitap alınmamış olur.
    """
    from biyo_cozucu.veri import kitap as kitap_modulu

    _sahte_pdf_kur(monkeypatch, ["", "", ""])
    # OCR hep boş dönüyor (arka uç düşmüş gibi).
    monkeypatch.setattr(
        kitap_modulu,
        "_grubu_oku",
        lambda belge, numaralar, **_k: [(n, "", True) for n in numaralar],
    )
    pdf = tmp_path / "k.pdf"
    pdf.write_bytes(b"%PDF sahte")
    depo = Depo(tmp_path / "t.db")

    ozetler = list(kitap_modulu.kitabi_al(pdf, depo, kaynak="K", ocr="zorla", toplu=1))

    son = ozetler[-1]
    assert son.ocr_bos == 3
    assert son.bos_sayfa == 0, "OCR boşluğu gerçek boş sayfayla karıştırılmamalı"


def test_arka_uc_cokerse_kosu_sessizce_devam_etmez(tmp_path, monkeypatch):
    """Yeniden kurulum işe yaramazsa koşu durmalı, 1000 sayfa boşa okunmamalı."""
    from biyo_cozucu.veri import kitap as kitap_modulu

    sayfa_sayisi = kitap_modulu.ARDISIK_BOS_SINIRI * 3
    _sahte_pdf_kur(monkeypatch, [""] * sayfa_sayisi)
    monkeypatch.setattr(
        kitap_modulu,
        "_grubu_oku",
        lambda belge, numaralar, **_k: [(n, "", True) for n in numaralar],
    )
    sifirlandi = []
    monkeypatch.setattr(kitap_modulu, "_ocr_tanicisini_sifirla", lambda: sifirlandi.append(1))
    pdf = tmp_path / "k.pdf"
    pdf.write_bytes(b"%PDF sahte")

    with pytest.raises(RuntimeError, match="boş"):
        list(kitap_modulu.kitabi_al(pdf, Depo(tmp_path / "t.db"), kaynak="K", ocr="zorla", toplu=1))
    assert sifirlandi, "durmadan önce arka uç bir kez yeniden kurulmalı"


def test_gercek_bos_sayfa_kosuyu_durdurmaz(tmp_path, monkeypatch):
    """Metin katmanı olan boş sayfalar OCR'a gitmiyor; sayaç dolmamalı."""
    from biyo_cozucu.veri import kitap as kitap_modulu

    sayfa_sayisi = kitap_modulu.ARDISIK_BOS_SINIRI * 3
    _sahte_pdf_kur(monkeypatch, [""] * sayfa_sayisi)
    pdf = tmp_path / "k.pdf"
    pdf.write_bytes(b"%PDF sahte")

    ozetler = list(
        kitap_modulu.kitabi_al(pdf, Depo(tmp_path / "t.db"), kaynak="K", ocr="kapali", toplu=1)
    )
    assert ozetler[-1].bos_sayfa == sayfa_sayisi
    assert ozetler[-1].ocr_bos == 0


def test_icindekiler_tablosu_pasaj_olmaz():
    """En zararlı kanıt türü: konu adı taşıdığı için üst sıraya çıkar, olgu taşımaz."""
    from biyo_cozucu.veri.kitap import paragraflara_bol

    icindekiler = (
        "1.10. İskelet Kaslarının Mekanizması....... 98\n"
        "1.10.1. Kaslarda Kasılmanın Kontrolü.. 101\n"
        "Kontrol Noktası............................................. 103\n"
        "1.11. Bağışıklık Sistemi.............................. 104\n"
    )
    assert paragraflara_bol(icindekiler) == []


def test_gercek_metin_tek_nokta_dizisiyle_atilmaz():
    from biyo_cozucu.veri.kitap import paragraflara_bol

    metin = (
        "Fotosentez kloroplastta gerçekleşir ve ışık enerjisini bağlar. " * 4
        + "\nAyrıntı için bkz. Şekil 3........... 45\n"
        + "Calvin döngüsü stromada ilerler ve karbon tutulur. " * 4
    )
    assert paragraflara_bol(metin), "gerçek paragraf atılmamalı"
