"""Kitap/çözüm alımı testleri: metin çıkarımı ve soru bölütleme."""

from __future__ import annotations

import builtins

import pytest

from biyo_cozucu.alim import AlimHatasi, adaylari_cikar, metni_cikar
from biyo_cozucu.alim.cikarim import Kaynak, Parca, dosya_turu

# --- bölütleme: gerçekçi kitap düzenleri ---


KLASIK_SORU_BANKASI = """
Biyoloji Soru Bankası - Ünite 3
42

1. Aşağıdakilerden hangisi mitokondride gerçekleşir?
A) Fotosentez
B) Krebs döngüsü
C) Protein sentezi
D) DNA eşlenmesi
ÇÖZÜM
Mitokondri oksijenli solunumun merkezidir.
Krebs döngüsü mitokondri matriksinde gerçekleşir.
Fotosentez kloroplastta olur, bu yüzden A elenir.
CEVAP: B

2. Bir hücrede 2n = 8 kromozom bulunuyorsa mayoz sonucu oluşan
hücrelerde kaç kromozom bulunur?
A) 2
B) 4
C) 8
D) 16
ÇÖZÜM
Mayoz bölünmede kromozom sayısı yarıya iner.
2n = 8 ise n = 4 olur.
CEVAP: B
"""


def test_klasik_soru_bankasi_ayristirilir():
    adaylar = adaylari_cikar(KLASIK_SORU_BANKASI)
    assert len(adaylar) == 2

    ilk = adaylar[0]
    assert "mitokondride gerçekleşir" in ilk.soru
    assert ilk.secenekler == {
        "A": "Fotosentez", "B": "Krebs döngüsü",
        "C": "Protein sentezi", "D": "DNA eşlenmesi",
    }
    assert ilk.cevap == "B"
    assert "Krebs döngüsü mitokondri matriksinde" in ilk.cozum
    assert ilk.cevap_turu == "coktan_secmeli"
    assert ilk.guven >= 0.9
    assert ilk.kullanilabilir_mi()


def test_sayfa_numarasi_gurultusu_atilir():
    adaylar = adaylari_cikar(KLASIK_SORU_BANKASI)
    assert "42" not in adaylar[0].soru
    assert "Soru Bankası" not in adaylar[0].soru


def test_cozum_icindeki_sik_benzeri_satir_sik_sayilmaz():
    """Çözüm metnindeki "A) ... elenir" satırı şık listesine karışmamalı."""
    adaylar = adaylari_cikar(KLASIK_SORU_BANKASI)
    assert len(adaylar[0].secenekler) == 4


SORU_ETIKETLI = """
SORU 12
Enzimlerin çalışma hızını etkileyen faktörler nelerdir?

Çözüm:
Sıcaklık, pH ve substrat derişimi enzim hızını etkiler.
Optimum sıcaklığın üstünde enzim denatüre olur.
Yanıt: Sıcaklık, pH ve substrat derişimi
"""


def test_soru_etiketli_acik_uclu_ayristirilir():
    adaylar = adaylari_cikar(SORU_ETIKETLI)
    assert len(adaylar) == 1
    aday = adaylar[0]
    assert aday.soru.startswith("Enzimlerin çalışma hızını")
    assert aday.cevap_turu == "acik_uclu"
    assert aday.secenekler == {}
    assert "denatüre" in aday.cozum
    assert aday.cevap.startswith("Sıcaklık")
    assert "Yanıt:" not in aday.cozum, "cevap satırı çözümde kalmamalı"


def test_yanit_harfi_farkli_bicimlerde_yakalanir():
    for satir in ("CEVAP: C", "Yanıt C", "Doğru cevap: C", "Cevap C şıkkıdır"):
        metin = (
            "1. Fotosentez hangi organelde gerçekleşir yazınız?\n"
            "A) Mitokondri\nB) Ribozom\nC) Kloroplast\n"
            "ÇÖZÜM\nFotosentez kloroplastta gerçekleşir.\n" + satir + "\n"
        )
        adaylar = adaylari_cikar(metin)
        assert adaylar, f"{satir!r} ayrıştırılamadı"
        assert adaylar[0].cevap == "C", f"{satir!r} yanlış okundu"


def test_cozum_isareti_yoksa_siklardan_sonrasi_cozum_sayilir():
    metin = (
        "1. Ribozomun görevi aşağıdakilerden hangisidir?\n"
        "A) Sindirim\nB) Protein sentezi\n"
        "Ribozom protein sentezinden sorumludur ve sitoplazmada bulunur.\n"
        "CEVAP: B\n"
    )
    aday = adaylari_cikar(metin)[0]
    assert "protein sentezinden sorumludur" in aday.cozum
    assert aday.secenekler == {"A": "Sindirim", "B": "Protein sentezi"}


def test_cozumsuz_soru_dusuk_guvenle_isaretlenir():
    metin = "1. Mitoz bölünmenin evrelerini sırasıyla yazınız ve açıklayınız.\n"
    adaylar = adaylari_cikar(metin)
    assert len(adaylar) == 1
    assert adaylar[0].guven <= 0.3
    assert any("Çözüm metni bulunamadı" in u for u in adaylar[0].uyarilar)
    assert not adaylar[0].kullanilabilir_mi(), "çözümsüz aday hafızaya girmemeli"


def test_siklarla_eslesmeyen_cevap_uyari_uretir():
    metin = (
        "1. Aşağıdakilerden hangisi doğrudur sizce açıklayınız?\n"
        "A) Birinci\nB) İkinci\n"
        "ÇÖZÜM\nAçıklama burada yer alıyor ve yeterince uzun.\n"
        "CEVAP: D\n"
    )
    aday = adaylari_cikar(metin)[0]
    assert any("eşleşmiyor" in u for u in aday.uyarilar)
    assert aday.guven <= 0.4


def test_pdf_tireli_satir_sonu_birlestirilir():
    metin = (
        "1. Fotosen-\n"
        "tez olayı hangi organelde gerçekleşir?\n"
        "ÇÖZÜM\nKloroplastta gerçekleşir ve klorofil kullanılır.\n"
        "CEVAP: A\n"
    )
    aday = adaylari_cikar(metin)[0]
    assert "Fotosentez" in aday.soru


def test_mevcut_soru_cozum_bicimi_oncelikli():
    """Metin zaten SORU:/ÇÖZÜM: düzenindeyse kesin ayrıştırıcı kullanılmalı."""
    metin = (
        "SORU: Mitokondrinin görevi nedir?\n"
        "ÇÖZÜM: Oksijenli solunumu gerçekleştirir.\n"
        "CEVAP: Enerji üretimi\n"
    )
    adaylar = adaylari_cikar(metin)
    assert len(adaylar) == 1
    assert adaylar[0].guven >= 0.95


def test_bos_metin_aday_uretmez():
    assert adaylari_cikar("") == []
    assert adaylari_cikar("Bu bir kitap önsözüdür, soru içermez.") == []


def test_video_dokumu_numarasiz_metinde_cokmez():
    """Konuşma dökümünde numara/işaret olmayabilir; çökmeden boş dönmeli."""
    dokum = (
        "Evet arkadaşlar şimdi mitoz bölünmeye bakalım. "
        "Kromozom sayısı korunur çünkü önce eşlenme olur."
    )
    assert isinstance(adaylari_cikar(dokum), list)


# --- kaynak künyesi ve konum ---


def test_kaynak_sayfa_konumu_verir():
    kaynak = Kaynak(
        ad="biyoloji.pdf", tur="pdf", imza="abc",
        parcalar=[Parca(metin="birinci sayfa metni", sayfa=1),
                  Parca(metin="ikinci sayfa metni", sayfa=2)],
    )
    assert kaynak.konum_bul(0) == "s. 1"
    assert kaynak.konum_bul(25) == "s. 2"
    assert kaynak.kaynak_adi(0) == "biyoloji.pdf (s. 1)"
    assert kaynak.kaynak_adi() == "biyoloji.pdf"


def test_kaynak_zaman_damgasi_verir():
    kaynak = Kaynak(
        ad="ders.mp4", tur="video", imza="abc",
        parcalar=[Parca(metin="ilk bölüm", baslangic_sn=0.0, bitis_sn=5.0),
                  Parca(metin="ikinci bölüm", baslangic_sn=65.0, bitis_sn=70.0)],
    )
    assert kaynak.konum_bul(0) == "00:00"
    assert kaynak.konum_bul(12) == "01:05"


def test_adaylara_konum_islenir():
    kaynak = Kaynak(
        ad="kitap.pdf", tur="pdf", imza="x",
        parcalar=[Parca(metin=KLASIK_SORU_BANKASI, sayfa=42)],
    )
    adaylar = adaylari_cikar(kaynak.metin, kaynak=kaynak)
    assert adaylar and adaylar[0].konum == "s. 42"


# --- dosya türü ve hata yolları ---


@pytest.mark.parametrize(
    "ad,beklenen",
    [
        ("kitap.pdf", "pdf"), ("notlar.docx", "word"), ("ham.txt", "metin"),
        ("ders.mp3", "ses"), ("ders.m4a", "ses"), ("anlatim.mp4", "video"),
        ("KITAP.PDF", "pdf"),
    ],
)
def test_dosya_turu_tanimlanir(ad, beklenen, tmp_path):
    assert dosya_turu(tmp_path / ad) == beklenen


def test_desteklenmeyen_tur_reddedilir(tmp_path):
    with pytest.raises(AlimHatasi, match="Desteklenmeyen"):
        dosya_turu(tmp_path / "sunum.pptx")


def test_olmayan_dosya_hata_verir(tmp_path):
    with pytest.raises(AlimHatasi, match="bulunamadı"):
        metni_cikar(tmp_path / "yok.pdf")


def test_duz_metin_dosyasi_okunur(tmp_path):
    yol = tmp_path / "sorular.txt"
    yol.write_text(KLASIK_SORU_BANKASI, encoding="utf-8")
    kaynak = metni_cikar(yol)
    assert kaynak.tur == "metin"
    assert kaynak.ad == "sorular.txt"
    assert len(kaynak.imza) == 16
    assert "Krebs" in kaynak.metin
    assert len(adaylari_cikar(kaynak.metin, kaynak=kaynak)) == 2


def test_turkce_kodlamali_metin_okunur(tmp_path):
    yol = tmp_path / "eski.txt"
    yol.write_text("Şıkları ölçün: ağırlık, ısı", encoding="cp1254")
    assert "ağırlık" in metni_cikar(yol).metin


def test_bos_dosya_uyari_uretir(tmp_path):
    yol = tmp_path / "bos.txt"
    yol.write_text("", encoding="utf-8")
    kaynak = metni_cikar(yol)
    assert kaynak.uyarilar and "hiç metin çıkmadı" in kaynak.uyarilar[0]


def test_word_belgesi_okunur(tmp_path):
    docx = pytest.importorskip("docx")
    yol = tmp_path / "notlar.docx"
    belge = docx.Document()
    for satir in KLASIK_SORU_BANKASI.splitlines():
        belge.add_paragraph(satir)
    belge.save(str(yol))

    kaynak = metni_cikar(yol)
    assert kaynak.tur == "word"
    assert "Krebs döngüsü" in kaynak.metin
    assert len(adaylari_cikar(kaynak.metin)) == 2


def test_word_tablosundaki_sorular_da_okunur(tmp_path):
    """Sorular tabloya dizilmişse yalnız paragraf okumak onları kaçırırdı."""
    docx = pytest.importorskip("docx")
    yol = tmp_path / "tablo.docx"
    belge = docx.Document()
    tablo = belge.add_table(rows=1, cols=2)
    tablo.rows[0].cells[0].text = "Soru"
    tablo.rows[0].cells[1].text = "Mitokondrinin görevi nedir?"
    belge.save(str(yol))
    assert "Mitokondrinin görevi" in metni_cikar(yol).metin


def _asgari_pdf(sayfa_metinleri: list[str]) -> bytes:
    """Elle yazılmış asgari geçerli PDF.

    Kütüphaneyle üretmek yerine elle yazılıyor: pypdfium2'nin metin yazma
    API'si sürümden sürüme değişiyor ve test o yüzden atlanıyordu — oysa
    doğrulanmak istenen şey tam olarak PDF'ten metin ÇIKARMA yolu.
    """
    nesneler: list[bytes] = []
    sayfa_kimlikleri = [3 + 2 * i for i in range(len(sayfa_metinleri))]
    kids = " ".join(f"{k} 0 R" for k in sayfa_kimlikleri).encode()
    nesneler.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    nesneler.append(
        b"<< /Type /Pages /Kids [" + kids + b"] /Count "
        + str(len(sayfa_metinleri)).encode() + b" >>"
    )
    yazi_kimligi = 3 + 2 * len(sayfa_metinleri)
    for sira, metin in enumerate(sayfa_metinleri):
        icerik = (
            f"BT /F1 12 Tf 40 700 Td ({metin}) Tj ET".encode("latin-1", "replace")
        )
        nesneler.append(
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources "
            b"<< /Font << /F1 " + str(yazi_kimligi).encode() + b" 0 R >> >> "
            b"/Contents " + str(4 + 2 * sira).encode() + b" 0 R >>"
        )
        nesneler.append(
            b"<< /Length " + str(len(icerik)).encode() + b" >>\nstream\n"
            + icerik + b"\nendstream"
        )
    nesneler.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    cikti = bytearray(b"%PDF-1.4\n")
    konumlar: list[int] = []
    for sira, govde in enumerate(nesneler, 1):
        konumlar.append(len(cikti))
        cikti += f"{sira} 0 obj\n".encode() + govde + b"\nendobj\n"
    xref = len(cikti)
    cikti += f"xref\n0 {len(nesneler) + 1}\n".encode() + b"0000000000 65535 f \n"
    for konum in konumlar:
        cikti += f"{konum:010d} 00000 n \n".encode()
    cikti += (
        f"trailer\n<< /Size {len(nesneler) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode()
    return bytes(cikti)


def test_pdf_okunur(tmp_path):
    pytest.importorskip("pypdfium2")
    yol = tmp_path / "kitap.pdf"
    yol.write_bytes(_asgari_pdf(["Mitokondri sorusu 42"]))

    # ocr="kapali": bu test METİN KATMANINI sınıyor. Varsayılan "oto" ile sayfa
    # metni OCR_ESIGI_KARAKTER'in (40) altında kaldığı için sessizce OCR'a
    # düşüyor, gerçek motoru yüklüyor ve test 11 saniye sürüyordu — ölçtüğü şeyi
    # de artık ölçmüyordu.
    kaynak = metni_cikar(yol, ocr="kapali")
    assert kaynak.tur == "pdf"
    assert kaynak.parcalar[0].sayfa == 1
    assert "Mitokondri sorusu" in kaynak.metin


def test_pdf_sayfa_numaralari_korunur(tmp_path):
    """Atıf "s. 2" diyebilsin diye her sayfa ayrı parça olmalı."""
    pytest.importorskip("pypdfium2")
    yol = tmp_path / "iki_sayfa.pdf"
    yol.write_bytes(_asgari_pdf(["Birinci sayfa icerigi", "Ikinci sayfa icerigi"]))

    kaynak = metni_cikar(yol, ocr="kapali")  # bkz. test_pdf_okunur — sayfa metni kısa
    assert [p.sayfa for p in kaynak.parcalar] == [1, 2]
    ikinci_konum = kaynak.metin.find("Ikinci")
    assert kaynak.konum_bul(ikinci_konum) == "s. 2"


def test_bozuk_pdf_anlamli_hata_verir(tmp_path):
    pytest.importorskip("pypdfium2")
    yol = tmp_path / "bozuk.pdf"
    yol.write_bytes(b"bu bir PDF degil")
    with pytest.raises(AlimHatasi, match="PDF açılamadı"):
        metni_cikar(yol)


def test_cok_buyuk_dosya_reddedilir(tmp_path, monkeypatch):
    from biyo_cozucu.alim import cikarim

    monkeypatch.setattr(cikarim, "AZAMI_BOYUT_MB", 0.0001)
    yol = tmp_path / "buyuk.txt"
    yol.write_text("x" * 5000, encoding="utf-8")
    with pytest.raises(AlimHatasi, match="çok büyük"):
        metni_cikar(yol)


# --- konuşma dökümü (ses/video) ---


DERS_DOKUMU = (
    "Birinci soru. Aşağıdakilerden hangisi kloroplastta gerçekleşir? "
    "Çözüm. Kloroplast fotosentezin gerçekleştiği organeldir. "
    "Krebs döngüsü mitokondride olur. Cevap B. "
    "İkinci soru. Enzimlerin aktivasyon enerjisine etkisi nedir? "
    "Çözüm. Enzimler aktivasyon enerjisini düşürerek tepkimeyi hızlandırır."
)


def test_konusma_dokumu_ayristirilir():
    """Ders videosunda "1." denmez, "Birinci soru" denir; satır yapısı da yoktur."""
    adaylar = adaylari_cikar(DERS_DOKUMU)
    assert len(adaylar) == 2

    ilk = adaylar[0]
    assert ilk.soru == "Aşağıdakilerden hangisi kloroplastta gerçekleşir?"
    assert "fotosentezin gerçekleştiği organeldir" in ilk.cozum
    assert ilk.cevap == "B"

    assert adaylar[1].soru.startswith("Enzimlerin aktivasyon")
    assert "hızlandırır" in adaylar[1].cozum


@pytest.mark.parametrize(
    "giris",
    ["Birinci soru.", "İkinci soruya geçelim.", "Üçüncü soru:", "Soru 4."],
)
def test_konusma_soru_isaretleri_taninir(giris):
    metin = f"{giris} Mitoz bölünme nasıl gerçekleşir? Çözüm. Profaz ile başlar ve telofaz ile biter."
    adaylar = adaylari_cikar(metin)
    assert adaylar, f"{giris!r} soru başlangıcı sayılmadı"
    assert "Mitoz bölünme" in adaylar[0].soru
    assert giris.split()[0] not in adaylar[0].soru, "sıra sözcüğü soruda kalmamalı"


def test_konusma_dokumune_zaman_damgasi_islenir():
    kaynak = Kaynak(
        ad="ders.mp4", tur="video", imza="x",
        parcalar=[
            Parca(metin="Birinci soru. Mitoz nasıl gerçekleşir? Çözüm. Profaz ile başlar burada.",
                  baslangic_sn=0.0, bitis_sn=8.0),
            Parca(metin="İkinci soru. Mayoz nasıl gerçekleşir? Çözüm. Kromozom sayısı yarıya iner.",
                  baslangic_sn=95.0, bitis_sn=104.0),
        ],
    )
    adaylar = adaylari_cikar(kaynak.metin, kaynak=kaynak)
    assert len(adaylar) == 2
    assert adaylar[0].konum == "00:00"
    assert adaylar[1].konum == "01:35"


def test_kitap_bicimi_konusma_desenlerinden_etkilenmez():
    """Konuşma desenleri eklendi diye kitap ayrıştırması bozulmamalı."""
    adaylar = adaylari_cikar(KLASIK_SORU_BANKASI)
    assert len(adaylar) == 2
    assert adaylar[0].cevap == "B"
    assert len(adaylar[0].secenekler) == 4


# --- OCR (taranmış PDF ve görüntü) ---


def _ocr_test_goruntusu():
    """Türkçe soru metnini görüntüye basar (gerçek OCR için)."""
    Image = pytest.importorskip("PIL.Image")
    from PIL import ImageDraw, ImageFont

    yaziyuzu = None
    for aday in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        try:
            yaziyuzu = ImageFont.truetype(aday, 34)
            break
        except OSError:
            continue
    if yaziyuzu is None:
        pytest.skip("uygun yazı yüzü bulunamadı")

    satirlar = [
        "1. Asagidakilerden hangisi kloroplastta gerceklesir?",
        "A) Krebs dongusu",
        "B) Fotosentez",
        "COZUM",
        "Kloroplast fotosentezin gerceklestigi organeldir.",
        "CEVAP: B",
    ]
    goruntu = Image.new("RGB", (1240, 620), "white")
    cizici = ImageDraw.Draw(goruntu)
    for sira, satir in enumerate(satirlar):
        cizici.text((60, 50 + sira * 60), satir, fill="black", font=yaziyuzu)
    return goruntu


def test_ocr_motor_sirasi_kaliteye_gore():
    from biyo_cozucu.alim.ocr import MOTOR_SIRASI

    assert MOTOR_SIRASI[0] == "surya", "Türkçe için en iyi motor başta olmalı"
    assert set(MOTOR_SIRASI) == {"surya", "easyocr", "paddle", "tesseract"}


def test_ocr_bilinmeyen_motor_reddedilir():
    from biyo_cozucu.alim.ocr import motor_sec

    with pytest.raises(AlimHatasi, match="Bilinmeyen OCR motoru"):
        motor_sec("yokboyle")


def test_ocr_kurulu_olmayan_motor_anlamli_hata_verir(monkeypatch):
    from biyo_cozucu.alim import ocr as ocr_modulu

    monkeypatch.setattr(ocr_modulu._MOTORLAR["tesseract"], "hazir_mi", lambda: False)
    # İki geçerli neden var ve hangisinin döneceği ORTAMA bağlı: Python
    # sarmalayıcısı yoksa "kurulu değil", sarmalayıcı varken sistem ikilisi
    # yoksa "bulunamadı". Tek metne bağlanmak, testi kurulu paket kümesine
    # göre kırılgan yapıyordu — sınanan şey mesajın kendisi değil, hatanın
    # kullanıcıya ne yapacağını söylemesi.
    with pytest.raises(AlimHatasi, match=r"kurulu değil|bulunamadı"):
        ocr_modulu.motor_sec("tesseract")


def test_ocr_hicbiri_yokken_kurulum_onerir(monkeypatch):
    from biyo_cozucu.alim import ocr as ocr_modulu

    for motor in ocr_modulu._MOTORLAR.values():
        monkeypatch.setattr(motor, "hazir_mi", lambda: False)
    monkeypatch.delenv("BIYO_OCR", raising=False)
    with pytest.raises(AlimHatasi, match="extra ocr"):
        ocr_modulu.motor_sec()


def test_ocr_env_degiskeni_motoru_sabitler(monkeypatch):
    from biyo_cozucu.alim import ocr as ocr_modulu

    monkeypatch.setenv("BIYO_OCR", "easyocr")
    monkeypatch.setattr(ocr_modulu._MOTORLAR["easyocr"], "hazir_mi", lambda: True)
    assert ocr_modulu.motor_sec().ad == "easyocr"


# --- Surya'nın harici `llama-server` bağımlılığı ---


def test_llama_server_biyo_bayragindan_bulunur(tmp_path, monkeypatch):
    """Projenin kendi bayrağı, Surya'nın LLAMA_CPP_BINARY'sinden önce gelmeli."""
    from biyo_cozucu.alim.ocr import _llama_server_bul

    bizim = tmp_path / "bizim-llama-server"
    bizim.write_text("")
    digeri = tmp_path / "digeri"
    digeri.write_text("")
    monkeypatch.setenv("BIYO_LLAMA_SERVER", str(bizim))
    monkeypatch.setenv("LLAMA_CPP_BINARY", str(digeri))
    assert _llama_server_bul() == str(bizim)


def test_llama_server_var_olmayan_yolu_yok_sayar(tmp_path, monkeypatch):
    """Bayrak eski bir yolu gösteriyorsa arama devam etmeli, orada durmamalı."""
    from biyo_cozucu.alim import ocr as ocr_modulu

    monkeypatch.setenv("BIYO_LLAMA_SERVER", str(tmp_path / "silinmis"))
    monkeypatch.delenv("LLAMA_CPP_BINARY", raising=False)
    bulunan = tmp_path / "yoldaki"
    bulunan.write_text("")
    monkeypatch.setattr(ocr_modulu.shutil, "which", lambda ad: str(bulunan))
    assert ocr_modulu._llama_server_bul() == str(bulunan)


def test_surya_ikili_eksikken_paketi_suclamaz(monkeypatch):
    """Yanıltıcı mesaj regresyonu: paket kuruluyken eksik olan ikili olabilir.

    Eski mesaj her durumda "kurulu değil, uv sync --extra ocr" diyordu ve
    kullanıcı boş yere paketi yeniden kuruyordu.
    """
    pytest.importorskip("surya")
    from biyo_cozucu.alim import ocr as ocr_modulu

    monkeypatch.setattr(ocr_modulu, "_llama_server_bul", lambda: "")
    with pytest.raises(AlimHatasi) as bilgi:
        ocr_modulu.motor_sec("surya")
    mesaj = str(bilgi.value)
    assert "llama-server" in mesaj
    assert "BIYO_LLAMA_SERVER" in mesaj
    assert "uv sync" not in mesaj, "paketi yeniden kurmaya yönlendirmemeli"


def test_surya_paketi_yokken_kurulum_onerir(monkeypatch):
    from biyo_cozucu.alim import ocr as ocr_modulu

    gercek_import = builtins.__import__

    def engelli_import(ad, *args, **kwargs):
        if ad == "surya":
            raise ImportError("surya yok")
        return gercek_import(ad, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", engelli_import)
    with pytest.raises(AlimHatasi, match="uv sync --extra ocr"):
        ocr_modulu.motor_sec("surya")


def test_surya_html_metne_cevrilir():
    """Surya blokları HTML döndürür; satır yapısı korunmalı."""
    from biyo_cozucu.alim.ocr import _html_metne

    assert _html_metne("<p>Birinci satır</p><p>İkinci satır</p>") == (
        "Birinci satır\nİkinci satır"
    )
    assert _html_metne("<b>Kalın</b> metin") == "Kalın metin"
    assert _html_metne("A &amp; B") == "A & B"
    assert _html_metne("") == ""


def test_metin_katmanli_pdf_ocr_calistirmaz(tmp_path, monkeypatch):
    """OCR pahalı: metin katmanı olan sayfada hiç çağrılmamalı."""
    pytest.importorskip("pypdfium2")
    from biyo_cozucu.alim import ocr as ocr_modulu

    cagrildi = []
    monkeypatch.setattr(
        ocr_modulu, "sayfayi_oku",
        lambda *a, **k: cagrildi.append(1) or ocr_modulu.OcrSonucu("", "sahte"),
    )
    yol = tmp_path / "metinli.pdf"
    yol.write_bytes(_asgari_pdf(["Bu sayfada gercek bir metin katmani bulunuyor burada"]))
    metni_cikar(yol)
    assert cagrildi == [], "metin katmanı varken OCR çalıştırılmamalı"


def test_ocr_kapaliyken_taranmis_pdf_uyarir(tmp_path):
    """Boş sayfalı PDF + ocr=kapali → net bir yönlendirme mesajı."""
    pytest.importorskip("pypdfium2")
    yol = tmp_path / "bos.pdf"
    yol.write_bytes(_asgari_pdf([""]))
    kaynak = metni_cikar(yol, ocr="kapali")
    assert any("OCR kapalı" in u for u in kaynak.uyarilar)


@pytest.mark.yavas
def test_taranmis_pdf_ocr_ile_okunur(tmp_path):
    """Gerçek OCR: metin katmanı olmayan PDF'ten Türkçe soru çıkmalı."""
    pytest.importorskip("pypdfium2")
    from biyo_cozucu.alim.ocr import kullanilabilir_motorlar

    if not kullanilabilir_motorlar():
        pytest.skip("kurulu OCR motoru yok")

    yol = tmp_path / "taranmis.pdf"
    _ocr_test_goruntusu().save(yol, "PDF", resolution=150)

    # Metin katmanı gerçekten yok olmalı, yoksa test OCR'ı sınamıyor demektir.
    import pypdfium2
    belge = pypdfium2.PdfDocument(str(yol))
    assert len(belge[0].get_textpage().get_text_range().strip()) == 0
    belge.close()

    kaynak = metni_cikar(yol, ocr_motoru="easyocr")
    assert "kloroplastta" in kaynak.metin.casefold()
    assert any("OCR uygulandı" in u for u in kaynak.uyarilar)

    adaylar = adaylari_cikar(kaynak.metin, kaynak=kaynak)
    assert adaylar, "OCR metninden soru çıkarılabilmeli"
    assert adaylar[0].cevap == "B"


@pytest.mark.yavas
def test_goruntu_dosyasi_ocr_ile_okunur(tmp_path):
    from biyo_cozucu.alim.ocr import kullanilabilir_motorlar

    if not kullanilabilir_motorlar():
        pytest.skip("kurulu OCR motoru yok")
    yol = tmp_path / "soru.png"
    _ocr_test_goruntusu().save(yol)

    kaynak = metni_cikar(yol, ocr_motoru="easyocr")
    assert kaynak.tur == "goruntu"
    assert "kloroplastta" in kaynak.metin.casefold()


def test_goruntu_uzantilari_taninir(tmp_path):
    for ad in ("foto.png", "tarama.jpg", "sayfa.jpeg", "ekran.webp", "eski.tiff"):
        assert dosya_turu(tmp_path / ad) == "goruntu"


# --- OCR noktalama kaybı ---


def test_ocr_noktasiz_soru_numarasi_yakalanir():
    """OCR soru numarasından sonraki noktayı sık düşürüyor.

    Ayracı zorunlu tutmak, taranmış sayfadaki soruların TAMAMININ
    kaçırılmasına yol açıyordu — OCR çalışıp metni doğru çıkarsa bile
    "0 aday bulundu" deniyordu.
    """
    ocr_ciktisi = (
        "2 Mayoz bolunmede kromozom sayisi nasil degisir?\n"
        "A) Iki katina cikar\nB) Yariya iner\nC) Degismez\n"
        "COZUM\nMayozda homolog kromozomlar ayrilir ve sayi yariya iner .\n"
        "CEVAP: B\n"
    )
    adaylar = adaylari_cikar(ocr_ciktisi)
    assert len(adaylar) == 1
    aday = adaylar[0]
    assert aday.soru.startswith("Mayoz bolunmede"), "numara soruda kalmamalı"
    assert len(aday.secenekler) == 3
    assert aday.cevap == "B"


@pytest.mark.parametrize(
    "satir",
    [
        "8 kromozom bulunan bir hucrede",   # küçük harf → soru değil
        "2n = 8 kromozom bulunuyor",        # sayı+harf bitişik
        "1990 yilinda kesfedilmistir",      # yıl, küçük harfle devam
    ],
)
def test_ayracsiz_numara_yanlis_eslesmez(satir):
    """Ayraçsız biçim gevşetildi; metin içi sayılar soru sanılmamalı."""
    metin = f"{satir}\nCOZUM\nYeterince uzun bir cozum metni burada bulunuyor.\n"
    assert adaylari_cikar(metin) == []


def test_ayracli_ve_ayracsiz_biçim_ayni_sonucu_verir():
    govde = (
        "{}Fotosentez hangi organelde gerceklesir?\n"
        "COZUM\nKloroplastta gerceklesir ve klorofil kullanilir.\nCEVAP: A\n"
    )
    ayracli = adaylari_cikar(govde.format("1. "))[0]
    ayracsiz = adaylari_cikar(govde.format("1 "))[0]
    assert ayracli.soru == ayracsiz.soru
    assert ayracli.cevap == ayracsiz.cevap == "A"
