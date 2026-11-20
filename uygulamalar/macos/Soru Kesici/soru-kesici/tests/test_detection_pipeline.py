import io
import json
import os
import shutil
import tempfile
import unittest
import zipfile
from unittest import mock

import fitz
from PIL import Image

import soru_kes as sk


def _sentetik_pdf_uret(yol):
    """OCR ve harici font gerektirmeyen iki soruluk metin PDF'i üretir."""
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=595, height=842)
        sayfa.insert_text((38, 32), "USTBILGI_SORU_DEGIL", fontsize=11)

        satirlar = [
            (100, "1. Asagidakilerden hangisi birinci sorudur?"),
            (126, "A) Alfa"),
            (150, "B) Beta"),
            (174, "C) Gamma"),
            (198, "D) Delta"),
            (222, "E) Epsilon"),
            (430, "2) Asagidakilerden hangisi ikinci sorudur?"),
            (456, "A) Bir"),
            (480, "B) Iki"),
            (504, "C) Uc"),
            (528, "D) Dort"),
            (552, "E) Bes"),
        ]
        for y, metin in satirlar:
            sayfa.insert_text((42, y), metin, fontsize=12)
        belge.save(yol)
    finally:
        belge.close()


def _satir_oncelikli_pdf_uret(yol):
    """1|2 / 3|4 sıralı, iki sütunlu test sayfası üret."""
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=700, height=900)
        for numara, x, y in (
                (1, 42, 90), (2, 372, 94),
                (3, 42, 475), (4, 372, 479)):
            sayfa.insert_text(
                (x, y), f"{numara}. Asagidakilerden hangisi dogrudur?",
                fontsize=11)
            for sira, harf in enumerate("ABCDE", 1):
                sayfa.insert_text(
                    (x + 12, y + sira * 28), f"{harf}) Secenek {sira}",
                    fontsize=10)
        belge.save(yol)
    finally:
        belge.close()


def _sonunda_gorsel_pdf_uret(yol):
    """Son metin satırının altında soru grafiği bulunan PDF üret."""
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=595, height=800)
        sayfa.insert_text((42, 55), "1. Asagidakilerden hangisi dogrudur?", fontsize=12)
        for sira in range(6):
            sayfa.insert_text((54, 78 + sira * 17),
                               f"Soruyu aciklayan bilgi satiri {sira + 1}",
                               fontsize=10)
        for sira, harf in enumerate("ABCDE", 1):
            sayfa.insert_text((54, 178 + sira * 23), f"{harf}) Secenek {sira}",
                               fontsize=11)
        gorsel = Image.new("RGB", (220, 150), "white")
        for x in range(15, 205):
            gorsel.putpixel((x, 130 - (x % 95)), (20, 70, 180))
        akim = io.BytesIO()
        gorsel.save(akim, format="PNG")
        sayfa.insert_image(fitz.Rect(70, 304, 290, 454), stream=akim.getvalue())
        belge.save(yol)
    finally:
        belge.close()


def _soru_ici_buyuk_bosluk_pdf_uret(yol):
    """Numara ile soru kipi arasında büyük şekil boşluğu bulunan PDF üret."""
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=595, height=800)
        sayfa.insert_text(
            (42, 62), "1. Asagidakilerden hangisi dogrudur?", fontsize=12)
        for sira, harf in enumerate("ABCDE", 1):
            sayfa.insert_text(
                (54, 72 + sira * 25), f"{harf}) Secenek {sira}", fontsize=11)

        # İkinci sorunun numarası ve başlangıç cümlesi şeklin üstündedir.
        # Soru kipi ile seçenekler, metin taşımayan büyük şekilden sonradır.
        sayfa.insert_text(
            (42, 292),
            "2. Kutleleri yazili agirliklar teraziye yerlestirilmistir.",
            fontsize=11)
        sayfa.insert_text(
            (58, 312), "Terazi asagidaki konumda dengededir.", fontsize=11)
        sayfa.draw_rect(fitz.Rect(80, 345, 260, 475), width=2)
        sayfa.draw_line(fitz.Point(100, 430), fitz.Point(240, 430), width=2)
        sayfa.draw_line(fitz.Point(170, 365), fitz.Point(170, 455), width=2)
        sayfa.insert_text(
            (58, 525), "Asagidakilerden hangisi teraziyi dengeler?",
            fontsize=11)
        for sira, harf in enumerate("ABCDE", 1):
            sayfa.insert_text(
                (58, 535 + sira * 25), f"{harf}) Agirlik {sira}", fontsize=11)
        belge.save(yol)
    finally:
        belge.close()


class SoruNumarasiBicimleriTesti(unittest.TestCase):
    def test_model_kaynagi_icerige_bagli_ve_yoldan_bagimsizdir(self):
        with tempfile.TemporaryDirectory(prefix="soru_kaynak_kimligi_") as d:
            bir = os.path.join(d, "bir.pdf")
            kopya = os.path.join(d, "kopya.pdf")
            farkli = os.path.join(d, "farkli.pdf")
            for yol, veri in ((bir, b"ayni-pdf-icerigi"),
                              (kopya, b"ayni-pdf-icerigi"),
                              (farkli, b"farkli-pdf-icerigi")):
                with open(yol, "wb") as f:
                    f.write(veri)

            self.assertEqual(sk._kaynak_dosya_kimligi(bir),
                             sk._kaynak_dosya_kimligi(kopya))
            self.assertNotEqual(sk._kaynak_dosya_kimligi(bir),
                                sk._kaynak_dosya_kimligi(farkli))

    def test_ayni_icerikli_girdilerin_karar_kimlikleri_cakismaz(self):
        with tempfile.TemporaryDirectory(prefix="soru_karar_kimligi_") as d:
            bir = os.path.join(d, "bir.pdf")
            kopya = os.path.join(d, "farkli-ad.pdf")
            _sentetik_pdf_uret(bir)
            shutil.copyfile(bir, kopya)

            sayfalar = acik = None
            try:
                sayfalar, acik = sk.belge_sayfalari([bir, kopya], 144)
                self.assertEqual(sayfalar[0].kimlik, sayfalar[1].kimlik)
                self.assertNotEqual(
                    sk.karar_kimligi(
                        sayfalar[0], (40, 80, 500, 300), 1),
                    sk.karar_kimligi(
                        sayfalar[1], (40, 80, 500, 300), 1))
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)

            # Aynı yol iki kez girdi olsa da belge_no örnekleri ayırır.
            sayfalar = acik = None
            try:
                sayfalar, acik = sk.belge_sayfalari([bir, bir], 144)
                self.assertNotEqual(
                    sk.karar_kimligi(
                        sayfalar[0], (40, 80, 500, 300), 1),
                    sk.karar_kimligi(
                        sayfalar[1], (40, 80, 500, 300), 1))
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)

    def test_raster_sekil_numarasi_kayip_soru_blok_sinirini_bastirmaz(self):
        onceki = (20.0, 100.0, 560.0, 260.0)
        yeni = (20.0, 500.0, 560.0, 760.0)
        capalar = [
            (12, 0, (42.0, 80.0, 300.0, 105.0)),
            # İki blok arasındaki şekil etiketi; soru şeridinden içeride.
            (1, 0, (190.0, 340.0, 220.0, 365.0)),
        ]
        self.assertFalse(sk._blok_arasi_ust_duzey_capa_var_mi(
            onceki, yeni, 0, capalar, True, 600.0, 1000.0))

        capalar.append((13, 0, (44.0, 470.0, 300.0, 495.0)))
        self.assertTrue(sk._blok_arasi_ust_duzey_capa_var_mi(
            onceki, yeni, 0, capalar, True, 600.0, 1000.0))

    def test_desteklenen_soru_numarasi_bicimleri(self):
        durumlar = {
            "1.": 1,
            "1)": 1,
            "Soru-1 )": 1,
            "Soru-2)10 PUAN": 2,
            "soru-4)15 PUAN": 4,
            "soru 4)": 4,
            "soru 6- )": 6,
        }
        for metin, beklenen in durumlar.items():
            with self.subTest(metin=metin):
                eslesme = sk.SORU_NO_DESENI.match(metin)
                self.assertIsNotNone(eslesme, f"Soru numarasi taninmadi: {metin}")
                self.assertEqual(beklenen, int(eslesme.group(1)))

    def test_ustbilgi_satirlari_soru_capasi_degil(self):
        metinler = [
            "10. Sinif Biyoloji 1. Donem Yazilisi",
            "1. Donem 2. Yazili Sinavi",
            "1. Bu testte 40 soru vardır.",
            "2. Cevaplarınızı cevap kâğıdına işaretleyiniz.",
            "3. DENEME",
            "2025-2026 Egitim Ogretim Yili",
            "Ad Soyad: ................ No: ........",
            "T.C. MILLI EGITIM BAKANLIGI",
        ]
        satirlar = [
            (metin, (20.0, 20.0 + i * 18, 500.0, 34.0 + i * 18), False)
            for i, metin in enumerate(metinler)
        ]
        self.assertEqual([], sk.numara_adaylari(satirlar))

    def test_soru_icindeki_rol_sozcukleri_sayfayi_dislamaz(self):
        satirlar = [
            ("15. Aşağıdakilerden hangisi cevap anahtarında bulunmaz?",
             (35.0, 80.0, 260.0, 94.0), False),
            ("İÇİNDEKİLER ifadesi seçeneklerde yalnız başlıktır.",
             (55.0, 105.0, 260.0, 119.0), False),
            ("A) Birinci  B) İkinci  C) Üçüncü",
             (55.0, 140.0, 260.0, 154.0), False),
        ]
        rol, _guven, _kanit = sk._sayfa_rolu_belirle(satirlar)
        self.assertEqual("soru", rol)

    def test_acik_uclu_yonerge_soru_govdesi_sayilir(self):
        self.assertIsNotNone(sk.SORU_GOVDE.search(
            "Aşağıda kloroplastın şekli verilmiştir; yerleri doldurunuz."))

    def test_acik_uclu_alt_numaralar_ust_duzey_soru_sayilmaz(self):
        satirlar = [
            ("5.", (50.0, 70.0, 58.0, 82.0), True),
            ("1. İlk önerme", (79.0, 260.0, 250.0, 274.0), False),
            ("2. İkinci önerme", (79.0, 285.0, 250.0, 299.0), False),
            ("6.", (50.0, 470.0, 58.0, 482.0), True),
            ("1. Popülasyon yoğunluğu", (147.0, 560.0, 300.0, 574.0), True),
            ("2. Çevre direnci", (147.0, 590.0, 300.0, 604.0), True),
        ]
        adaylar = sk.numara_adaylari(satirlar)
        temiz = sk._yalin_numara_adaylari(satirlar, adaylar)
        self.assertEqual([5, 6], [a[0] for a in temiz])

    def test_govdeyle_ayni_satirdaki_normal_sorular_korunur(self):
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (45.0, 90.0, 330.0, 104.0), True),
            ("2. Aşağıdaki grafiği açıklayınız.",
             (45.0, 420.0, 300.0, 434.0), True),
        ]
        adaylar = sk.numara_adaylari(satirlar)
        self.assertEqual(adaylar, sk._yalin_numara_adaylari(satirlar, adaylar))

    def test_kucuk_harfli_sekil_panelleri_sik_sayilmaz(self):
        satirlar = [
            ("(a) Kutup ayısı", (700, 100, 900, 130), False),
            ("(b) Deve", (700, 250, 850, 280), False),
            ("(c) Balina", (700, 400, 860, 430), False),
            ("(d) Ördek", (700, 550, 860, 580), False),
        ]
        self.assertEqual(
            0, sk.bolge_sik_sayisi(satirlar, 0, 700, 650, 950, 10))
        self.assertEqual({"A"}, sk._sik_harfleri("a) gerçek seçenek"))
        self.assertEqual({"A"}, sk._sik_harfleri(
            "10.\t a.\t Sempatik sinirler"))
        self.assertEqual({"A", "B"}, sk._sik_harfleri(
            "A) Bir seçenek   B) İkinci seçenek"))

    def test_cozum_bolumu_ve_konu_sayfalari_soru_uretmez(self):
        class Sayfa:
            genislik = 600

            def __init__(self, metinler):
                self._satirlar = [
                    (m, (20.0, 20.0 + i * 24, 560.0, 38.0 + i * 24), False)
                    for i, m in enumerate(metinler)
                ]

            def satirlar(self):
                return self._satirlar

        soru = [
            "TEST-1", "1. Aşağıdakilerden hangisi doğrudur?",
            "A) Bir", "B) İki", "C) Üç", "D) Dört", "E) Beş",
        ]
        sayfalar = [
            Sayfa(["KONU ANLATIMI", "1. Sinir sistemi bölümleri"]),
            Sayfa(soru), Sayfa([s.replace("1", "2", 1) for s in soru]),
            Sayfa([s.replace("1", "3", 1) for s in soru]),
            Sayfa(["Mini Sınav Çözümleri"]),
            Sayfa(["MİNİ SINAV - 2", "1. A", "2. B", "3. C"]),
            Sayfa(["DERS NOTLARI"]),
        ]
        disla, soru_sayfalari = sk._belge_sayfa_rolleri(
            sayfalar, fmt="coktan_secmeli")
        self.assertEqual({4, 5}, disla)
        self.assertEqual({1, 2, 3}, soru_sayfalari)

    def test_cozum_kitabinda_cozum_sayfasi_veto_edilmez(self):
        """Sayfa vetosu belgenin AMACINA görelidir.

        Çözüm kitabında çözüm sayfası aykırı değil, kesilmek istenen içeriktir.
        Veto `sorulari_tespit_meta`'dan ÖNCE çalıştığı için, dışlanan sayfa hiç
        aday üretmez; kesim ne çıktı ne de İncele kovasına düşer ("İncele tam
        tümleyendir" güvencesi kırılır). Ölçüldü: cozumler1 s39-47'de tespit 87
        kutu bulurken teslim 21'de kalıyordu.
        """
        class Sayfa:
            genislik = 600

            def __init__(self, metinler):
                self._satirlar = [
                    (m, (20.0, 20.0 + i * 24, 560.0, 38.0 + i * 24), False)
                    for i, m in enumerate(metinler)
                ]

            def satirlar(self):
                return self._satirlar

        cozum = [
            "Soru 1 : ______  ______",
            "Enzimler tepkimeden bozulmadan çıkar.", "Cevap A",
            "Soru 2 : ______  ______",
            "DNA çekirdek zarıyla çevrilidir.", "Cevap B",
            "Soru 3 : ______  ______",
            "Ribozom zarsız organeldir.", "Cevap C",
        ]
        sayfalar = [Sayfa(cozum) for _ in range(4)]

        def elenen(sayfalar_, kalite, fmt):
            """kirpma_plani_meta'nın gerçek ön eleme kuralı (bkz. çağrı yeri):
            hem `disla` hem de pozitif beyaz liste sayfayı öldürebilir."""
            disla, beyaz = sk._belge_sayfa_rolleri(sayfalar_, kalite, fmt=fmt)
            return {i for i in range(len(sayfalar_))
                    if i in disla or (beyaz is not None and i not in beyaz)}

        for kalite in sk.KALITE_MODLARI:
            # Amaç bilinmiyorsa eski davranış korunur: çözüm sayfası vetolu.
            self.assertEqual({0, 1, 2, 3},
                             elenen(sayfalar, kalite, None), kalite)
            # Belge bir çözüm kitabıysa aynı sayfa kesim hattında kalmalı.
            self.assertEqual(set(),
                             elenen(sayfalar, kalite, "cozumlu"), kalite)

        # "ÇÖZÜMLER" başlığı: soru kitabının ekinde bölümü dışlar, çözüm
        # kitabında ise içeriğin başlangıcıdır (ayrı veto kolu).
        baslikli = [Sayfa(["ÇÖZÜMLER"])] + [Sayfa(cozum) for _ in range(3)]
        self.assertEqual({0, 1, 2, 3}, elenen(baslikli, "balanced", None))
        self.assertEqual(set(), elenen(baslikli, "balanced", "cozumlu"))

        # Legacy'nin pozitif beyaz listesi: karma belgede soru sayfası listeyi
        # doldurur; çözüm sayfası `disla`dan çıksa bile listeye giremezse yine
        # sessizce elenir. Amaç istisnası her iki kola da uygulanmalı.
        soru = [
            "TEST-1", "1. Aşağıdakilerden hangisi doğrudur?",
            "A) Bir", "B) İki", "C) Üç", "D) Dört", "E) Beş",
        ]
        karma = [Sayfa(soru)] + [Sayfa(cozum) for _ in range(3)]
        _, beyaz = sk._belge_sayfa_rolleri(karma, "legacy", fmt="cozumlu")
        self.assertIsNotNone(beyaz, "karma belgede beyaz liste dolmalı")
        self.assertEqual(set(), elenen(karma, "legacy", "cozumlu"))

    def test_cozum_kitabinda_teslim_hatti_aday_uretir(self):
        """Uçtan uca: ön eleme gerçek `kirpma_plani_meta` hattında da geçmeli.

        Sessiz kaybın asıl belirtisi burada görünür — dışlanan sayfa boş meta
        aldığı için `sorulari_tespit_meta` hiç çağrılmaz ve kesim iki kovadan
        birine değil, hiçbirine düşer.
        """
        class Sayfa:
            genislik = 600
            yukseklik = 800
            raster = False
            dpi = 72
            belge_no = 0

            def __init__(self, metinler):
                self._satirlar = [
                    (m, (20.0, 20.0 + i * 24, 560.0, 38.0 + i * 24), False)
                    for i, m in enumerate(metinler)
                ]

            def satirlar(self):
                return self._satirlar

        cozum = [
            "Soru 1 : ______  ______",
            "Enzimler tepkimeden bozulmadan çıkar.", "Cevap A",
            "Soru 2 : ______  ______",
            "DNA çekirdek zarıyla çevrilidir.", "Cevap B",
            "Soru 3 : ______  ______",
            "Ribozom zarsız organeldir.", "Cevap C",
        ]
        sayfalar = [Sayfa(cozum) for _ in range(4)]

        def tespit_edilen(fmt, kalite):
            """`sorulari_tespit_meta`'nın ÇAĞRILDIĞI sayfa indeksleri.

            Sessiz kaybın ölçüsü budur: çağrılmayan sayfa aday üretmez, aday
            üretmeyen sayfa hiçbir kovaya düşemez.
            """
            gorulen = []
            orijinal = sk.sorulari_tespit_meta

            def sarmal(sayfa, sayfa_fmt):
                gorulen.append(sayfalar.index(sayfa))
                return ([], [(0.0, sayfa.genislik)], sayfa_fmt)

            sk.sorulari_tespit_meta = sarmal
            try:
                sk.kirpma_plani_meta(sayfalar, fmt, cevap_disla=True,
                                     kalite=kalite)
            finally:
                sk.sorulari_tespit_meta = orijinal
            return set(gorulen)

        for kalite in sk.KALITE_MODLARI:
            # Amaç bilinmiyorsa çözüm sayfası tespite hiç girmez (eski hâl).
            self.assertEqual(set(), tespit_edilen(None, kalite), kalite)
            # Çözüm kitabında dört sayfanın dördü de tespite girmeli.
            self.assertEqual({0, 1, 2, 3}, tespit_edilen("cozumlu", kalite),
                             kalite)


class SoruKimligiKararliligiTesti(unittest.TestCase):
    def test_kimlik_belge_geneli_sira_kaymasindan_etkilenmez(self):
        """Kimlik yalnız sayfa + soru numarasına bağlıdır.

        Belgenin başka bir yerinde bir sayfa kesim hattına girip çıktığında
        hem `test_sira` (belge-geneli sıra) hem `test_no` (bölüm dikişine
        bağlı yerel numara) kayar. Kimlik onlara bağlı olsaydı ilgisiz
        soruların etiketleri ve elle cevap düzeltmeleri sahipsiz kalırdı —
        ölçüldü (cozumler1, 101 ortak kesim): t{test_sira}s{no} → 73 kayma,
        p{sayfa}t{test_no}s{no} → 15, p{sayfa}s{no} → 0.
        """
        def kayit(sayfa, test_no, test_sira, soru_no):
            return {"sayfa": sayfa, "test_no": test_no,
                    "test_sira": test_sira, "soru_no": soru_no,
                    "parcalar_idx": [(sayfa - 1, 0)]}

        # Aynı iki soru; ikinci koşumda araya yeni sayfalar girdiği için HEM
        # belge-geneli sıra HEM yerel test numarası kaymış.
        once = [kayit(23, 3, 4, 9), kayit(24, 4, 5, 2)]
        sonra = [kayit(23, 5, 7, 9), kayit(24, 6, 8, 2)]
        self.assertEqual(sk.soru_kimlikleri(once),
                         sk.soru_kimlikleri(sonra))

        # Yerel çapalar farklıysa kimlik de farklı olmalı (çakışma olmasın).
        farkli = [kayit(23, 3, 4, 9), kayit(23, 3, 4, 10),
                  kayit(24, 3, 4, 9)]
        self.assertEqual(3, len(set(sk.soru_kimlikleri(farkli))))

        # Aynı sayfada aynı numara iki kez görünürse '_2' eki ayırır.
        ikiz = [kayit(23, 3, 4, 9), kayit(23, 4, 5, 9)]
        self.assertEqual(2, len(set(sk.soru_kimlikleri(ikiz))))


class BelgeFormatiAyrimiTesti(unittest.TestCase):
    def test_cevap_dipnotlu_soru_bankasi_cozum_kitabi_sanilmaz(self):
        """'cozumlu' kararı çoktan seçmeli kanıtından önce verilemez.

        COZUM_DESENI satır başındaki "çözüm/cevap/yanıt" ile eşleşir; her
        sorunun altına "Cevap: A" basan bir soru bankası sayfalarının çoğunda
        bunu tetikler. Yanlış 'cozumlu' etiketinin etkisi geniştir: sayfa
        vetosunda çözüm rolü bağışıklık kazanır, aday puanlamasında çözüm
        cezası kalkar, COZUM_NO_DESENI ek çapa üretir.
        """
        def satirlar(metinler):
            return [(m, (20.0, 20.0 + i * 24, 560.0, 38.0 + i * 24), False)
                    for i, m in enumerate(metinler)]

        # Şıkları tam basılı, altında cevabı yazan soru bankası sayfası.
        banka = satirlar([
            "1. Aşağıdakilerden hangisi doğrudur?",
            "A) Bir", "B) İki", "C) Üç", "D) Dört", "E) Beş",
            "Cevap: A",
            "2. Hangisi yanlıştır?",
            "A) Bir", "B) İki", "C) Üç", "D) Dört", "E) Beş",
            "Cevap: C",
        ])
        self.assertEqual("coktan_secmeli",
                         sk.belge_formatini_belirle([banka] * 6))

        # Gerçek çözüm kitabı: çözüm metni baskın, şık kümesi zayıf.
        kitap = satirlar([
            "Soru 1 :", "Enzimler tepkimeden bozulmadan çıkar.", "Cevap A",
            "Soru 2 :", "DNA çekirdek zarıyla çevrilidir.", "Cevap B",
            "Soru 3 :", "Ribozom zarsız organeldir.", "Cevap C",
        ])
        self.assertEqual("cozumlu", sk.belge_formatini_belirle([kitap] * 6))


class SentetikPdfUctanUcaTesti(unittest.TestCase):
    def test_dikey_birlestirme_dar_parcayi_buyutmez(self):
        genis = Image.new("RGB", (300, 80), (220, 20, 20))
        dar = Image.new("RGB", (120, 40), (20, 40, 220))
        birlesik = sk.dikey_birlestir([genis, dar], bosluk_px=10)
        self.assertEqual((300, 130), birlesik.size)
        # Dar parça 120 px kalır; geri kalan tuval beyaz dolgudur.
        self.assertEqual((20, 40, 220), birlesik.getpixel((119, 95)))
        self.assertEqual((255, 255, 255), birlesik.getpixel((121, 95)))

    def test_tespit_kesim_ve_zip_sozlesmesi(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_test_") as gecici:
            pdf_yolu = os.path.join(gecici, "sentetik.pdf")
            zip_yolu = os.path.join(gecici, "Arsiv.zip")
            _sentetik_pdf_uret(pdf_yolu)

            sayfalar = acik = None
            try:
                sayfalar, acik, belge_formati, _ = sk.belge_hazirla(
                    [pdf_yolu], dpi=144
                )
                self.assertEqual("coktan_secmeli", belge_formati)
                kirpmalar, sorular, uyarilar = sk.kirpma_seti(
                    sayfalar,
                    belge_formati,
                    girdiler=[pdf_yolu],
                    cevap_disla=True,
                )
                self.assertEqual([], uyarilar)
                self.assertEqual(2, len(kirpmalar))
                self.assertEqual([1, 2], [soru["soru_no"] for soru in sorular])
                self.assertTrue(all("USTBILGI_SORU_DEGIL" not in soru["metin"]
                                    for soru in sorular))
                self.assertIn("birinci sorudur", sorular[0]["metin"])
                self.assertIn("ikinci sorudur", sorular[1]["metin"])

                self.assertEqual(2, sk.zip_yaz(
                    kirpmalar, zip_yolu, sorular=sorular
                ))
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)

            with zipfile.ZipFile(zip_yolu) as arsiv:
                adlar = arsiv.namelist()
                png_adlari = [ad for ad in adlar if ad.endswith(".png")]
                self.assertEqual(["soru_01.png", "soru_02.png"], png_adlari)
                self.assertEqual(1, adlar.count("sorular.json"))

                metadata = json.loads(arsiv.read("sorular.json"))
                self.assertEqual(png_adlari, [soru["dosya"] for soru in metadata])
                self.assertEqual([1, 2], [soru["soru_no"] for soru in metadata])
                self.assertEqual(
                    ["sentetik.pdf", "sentetik.pdf"],
                    [soru["kaynak"] for soru in metadata],
                )

                png_icerikleri = []
                for ad in png_adlari:
                    veri = arsiv.read(ad)
                    png_icerikleri.append(veri)
                    with Image.open(io.BytesIO(veri)) as gorsel:
                        self.assertEqual("PNG", gorsel.format)
                        gorsel.load()
                        self.assertGreater(gorsel.width, 100)
                        self.assertGreater(gorsel.height, 100)
                self.assertNotEqual(png_icerikleri[0], png_icerikleri[1])

    def test_iki_sutundan_tam_genislige_gecen_raster_sayfa(self):
        class SahteRaster:
            raster = True
            belge_no = 0
            genislik = 1654
            yukseklik = 2339

            def satirlar(self):
                return [
                    ("soru-4)15 PUAN", (98, 248, 336, 279), False),
                    ("Aşağıda ATP şemasını açıklayınız.",
                     (122, 340, 700, 375), False),
                    ("soru-5)10 PUAN", (937, 248, 1178, 282), False),
                    ("5. Aşağıda iki deney verilmiştir.",
                     (876, 330, 1494, 364), False),
                    ("Bu deneylerden hangi sonuca ulaşılır?",
                     (883, 880, 1470, 915), False),
                    ("soru 6-)30 PUAN aşağıda kloroplastın",
                     (95, 1078, 655, 1112), False),
                    ("şekli verilmiştir; numaralı yerleri doldurunuz.",
                     (648, 1078, 1419, 1116), False),
                    ("1 2 3 4 5 6 7 8 9 10 11",
                     (180, 1200, 1420, 1900), False),
                ]

            def resim_kutulari(self):
                return []

        sayfa = SahteRaster()
        bantlar = [(120.0, 829.0), (829.0, 1538.0)]
        kal = sk.SutunKalibrasyonu(
            bantlar=tuple(bantlar), guven=0.9, ayraclar=(829.0,),
            bolgesel_gecis=True)
        sayfa._v3_duzen_bolgeleri = tuple(
            b.to_dict() for b in sk.duzen_bolgeleri_uret(sayfa, kal))
        with mock.patch.object(sk, "sayfa_sutunlari", return_value=bantlar), \
                mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                                  return_value=kal), \
                mock.patch.object(sk, "_ml_sekil_kutulari", return_value=[]):
            meta, _, _ = sk.sorulari_tespit_meta(sayfa, "acik_uclu")
        gercek = [m for m in meta if not m.devam_aday]
        self.assertEqual([4, 5, 6], [m.numara for m in gercek])
        soru5, soru6 = gercek[1], gercek[2]
        self.assertLessEqual(soru5.kutu[3], 1078)
        self.assertLess(soru6.kutu[1], 1078)
        self.assertLessEqual(soru6.kutu[0], 98)
        self.assertGreaterEqual(soru6.kutu[2], 1419)
        self.assertNotIn("sutun_tasma_riski", soru6.uyarilar)

    def test_satir_oncelikli_iki_sutun_sorularin_tumunu_korur(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_satir_") as gecici:
            pdf_yolu = os.path.join(gecici, "satir-oncelikli.pdf")
            _satir_oncelikli_pdf_uret(pdf_yolu)
            sayfalar = acik = None
            try:
                sayfalar, acik, belge_formati, _ = sk.belge_hazirla([pdf_yolu])
                meta, bantlar, _ = sk.sorulari_tespit_meta(
                    sayfalar[0], belge_formati)
                gercek = [m for m in meta if not m.devam_aday]
                self.assertGreaterEqual(len(bantlar), 2)
                self.assertEqual([1, 2, 3, 4], [m.numara for m in gercek])
                _, parca_meta, _ = sk.kirpma_plani_meta(
                    sayfalar, belge_formati, birlestir=False)
                self.assertEqual([1, 2, 3, 4],
                                 [m["soru_no"] for m in parca_meta])
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)

    def test_son_sorunun_altindaki_gomulu_gorsel_kesime_girer(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_gorsel_") as gecici:
            pdf_yolu = os.path.join(gecici, "gorselli.pdf")
            _sonunda_gorsel_pdf_uret(pdf_yolu)
            sayfalar = acik = None
            try:
                sayfalar, acik, belge_formati, _ = sk.belge_hazirla([pdf_yolu])
                meta, _, _ = sk.sorulari_tespit_meta(sayfalar[0], belge_formati)
                gercek = [m for m in meta if not m.devam_aday]
                self.assertEqual(1, len(gercek))
                self.assertGreaterEqual(gercek[0].kutu[3], 454)
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)

    def test_okunan_numara_soru_ici_gorsel_boslugunda_bolunmez(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_ara_gorsel_") as gecici:
            pdf_yolu = os.path.join(gecici, "ara-gorselli.pdf")
            _soru_ici_buyuk_bosluk_pdf_uret(pdf_yolu)
            sayfalar = acik = None
            try:
                sayfalar, acik, belge_formati, _ = sk.belge_hazirla([pdf_yolu])
                meta, _, _ = sk.sorulari_tespit_meta(
                    sayfalar[0], belge_formati)
                gercek = [m for m in meta if not m.devam_aday]
                self.assertEqual([1, 2], [m.numara for m in gercek])
                ikinci = gercek[1]
                self.assertLessEqual(ikinci.kutu[1], 292)
                self.assertGreaterEqual(ikinci.kutu[3], 650)
            finally:
                if acik is not None:
                    sk.belge_kapat(acik)


if __name__ == "__main__":
    unittest.main()


class CozumKitabiRolCezasiTesti(unittest.TestCase):
    """'Soru dışı sayfa' cezası belgenin AMACINA göreli olmalı.

    Ölçülen gerçek vaka: cozumler1 (çözüm kitabı) s41'de motor 11 aday buluyor,
    11'i de blok geçerliliğinden geçiyor, kanıt listeleri kusursuz
    (soru_numarasi + yeterli_metin + uygun_geometri + belge_numara_hizasi) —
    ama sayfa rolü 'çözüm' olduğu için güven 0,20'ye tavanlanıp hepsi
    reddediliyordu. Sayfa TÜMÜYLE boş kalıyordu. Bir çözüm kitabında çözüm
    sayfası aykırı sayfa değil, kesilecek içeriğin ta kendisidir.
    Düzeltmeyle count_recall 0,437 → 0,845.
    """

    class _Sayfa:
        genislik = 570.0
        yukseklik = 797.0
        raster = False

    def _satirlar(self):
        govde = [
            "Soru 7 :",
            "Enzimler aktif bölgelerinden substratlarına bağlanır ve",
            "çeşitli şekillerde substratı etkileyerek ürün oluşmasını",
            "sağlar. Bu nedenle enzim-substrat uyumu zorunludur.",
            "Cevap C",
        ]
        return [(m, (37.0, 300.0 + i * 18, 269.0, 316.0 + i * 18), False)
                for i, m in enumerate(govde)]

    def _meta(self):
        return [sk.SoruKutu(
            kutu=(37.0, 297.0, 269.0, 390.0), bant_idx=0, numara=7,
            devam_aday=False, sik_harfler=frozenset(), son_metin="Cevap C",
            govde_var=True, numara_kutu=(37.0, 297.0, 269.0, 307.0))]

    def _guven(self, fmt):
        sonuc = sk._adaylari_zenginlestir(
            self._Sayfa(), self._satirlar(), self._meta(), fmt,
            sayfa_rolu="çözüm")
        gorunen = [m for m in sonuc if not m.devam_aday]
        self.assertEqual(1, len(gorunen))
        return gorunen[0]

    def test_cozum_kitabinda_cozum_sayfasi_cezalandirilmaz(self):
        m = self._guven("cozumlu")
        self.assertNotIn("soru_disinda_sayfa", m.uyarilar)
        self.assertGreater(m.guven, sk.GUVEN_INCELE,
                           "çözüm kitabındaki çözüm bloğu teslim edilmeli")
        self.assertTrue(sk.aday_tespit_edildi(m))

    def test_soru_kitabinda_cozum_sayfasi_hala_cezalandirilir(self):
        """Daralma yalnız fmt='cozumlu' iken geçerli: bir SORU kitabının
        arkasındaki cevap/çözüm bölümünden soru kesilmemeye devam etmeli."""
        m = self._guven("coktan_secmeli")
        self.assertIn("soru_disinda_sayfa", m.uyarilar)
        self.assertLessEqual(m.guven, 0.20)
        self.assertFalse(sk.aday_tespit_edildi(m))


class EslestirmeGridiFormatiTesti(unittest.TestCase):
    """Eşleştirme gridi PAYLAŞILAN UYARANDIR, per-soru şık değildir.

    Ölçülen gerçek vaka (12meb s186): sayfanın ortasında a) … o) harfli
    15 kutucuktan oluşan bir eşleştirme gridi var; altındaki 15 soru düz
    metin boşluk-doldurma. Grid 15 küçük şık harfi ürettiği için sayfa
    'coktan_secmeli' sanılıyordu ve iki şey birden bozuluyordu:
      * blok_gecerli_mi her blokta şık kanıtı arıyor (bu sorularda şık yok),
      * zincir çapası devre dışı kalıyor (fmt != 'coktan_secmeli' koşulu).
    22 sorunun 3'ü teslim ediliyordu. Daraltmayla count_recall 0,154 → 0,462.
    """

    @staticmethod
    def _satirlar(metinler):
        return [(m, (40.0, 60.0 + i * 17, 500.0, 74.0 + i * 17), False)
                for i, m in enumerate(metinler)]

    def test_turkce_harfli_grid_coktan_secmeli_sayilmaz(self):
        grid = ["a) Kambiyum", "b) Fotoperiyodizm", "c) Gövde",
                "ç) Kaspari şeridi", "d) Tüp (vejetatif)", "e) Giberellin",
                "f) Makro elementler", "g) Hidatot", "ğ) Absisik asit"]
        sorular = ["27. Bitkilerde boyca uzamadan sorumlu hücre hangisidir?",
                   "28. Toprak üstü kısmı hangileridir?"]
        fmt = sk._sayfa_formati(self._satirlar(grid + sorular), "karisik")
        self.assertNotEqual("coktan_secmeli", fmt)

    def test_gercek_siklar_hala_coktan_secmeli(self):
        """Daralma yalnız seçenek-listesi vetosu ateşlendiğinde geçerli:
        gerçek A–E şıklı sayfa çoktan seçmeli olarak kalmalı, aksi halde
        korpusun en büyük ailesi (ÖSYM/soru bankası) bozulurdu."""
        soru = ["1. Aşağıdakilerden hangisi doğrudur?",
                "A) Birinci", "B) İkinci", "C) Üçüncü", "D) Dördüncü",
                "E) Beşinci"]
        self.assertEqual(
            "coktan_secmeli",
            sk._sayfa_formati(self._satirlar(soru), "karisik"))

    def test_alti_alt_madde_harfi_de_veto_eder(self):
        """Veto iki yoldan ateşlenir: Türkçe harf VEYA ≥6 farklı alt madde."""
        grid = [f"{h}) Terim {h}" for h in "abcdefg"]
        self.assertNotEqual(
            "coktan_secmeli",
            sk._sayfa_formati(self._satirlar(grid + ["30. Hangisidir?"]),
                              "karisik"))


class ZincirUyeligiKanitiTesti(unittest.TestCase):
    """Zincir üyeliği bağımsız bir güven kanıtıdır — ve üç koruması vardır.

    Ölçülen gerçek vaka (12meb s186): doğru-yanlış tablosunun satırları için
    kutular DOĞRU kuruluyordu ama hiçbir uyarı taşımadan 0,520 ile
    GUVEN_INCELE'nin (0,55) 0,03 altında kalıp tümüyle reddediliyorlardı.
    Zincirin doğrulanmış üyesi olan bir kutuyu 20 kardeşi doğrular.
    """

    class _Sayfa:
        genislik = 553.0
        yukseklik = 779.5
        raster = False

    @staticmethod
    def _meta(numaralar, x0=47.0, adim=17.0):
        return [sk.SoruKutu(
            kutu=(x0, 60.0 + i * adim, 500.0, 60.0 + (i + 1) * adim),
            bant_idx=0, numara=n, devam_aday=False, sik_harfler=frozenset(),
            son_metin="", govde_var=False,
            numara_kutu=(x0, 60.0 + i * adim, x0 + 14, 71.0 + i * adim))
            for i, n in enumerate(numaralar)]

    def test_hizali_uzun_zincir_uye_kutularini_dondurur(self):
        meta = self._meta([20, 21, 22, 23, 24, 25, 26])
        uyeler = sk._guclu_zincir_uyeleri(meta, self._Sayfa.genislik)
        self.assertEqual(7, len(uyeler))
        self.assertIn(tuple(meta[0].kutu), uyeler)

    def test_kisa_zincir_kanit_uretmez(self):
        """≥5 üye şartı: tek tük numara (şekil etiketi, sayfa no) zincir
        sayılmamalı."""
        meta = self._meta([1, 2, 3])
        self.assertEqual(
            frozenset(), sk._guclu_zincir_uyeleri(meta, self._Sayfa.genislik))

    def test_hizasiz_numaralar_kanit_uretmez(self):
        """Şekil içindeki '1. Tur, 2. Tur…' etiketleri artan bir dizi kurar
        ama ortak sol hizaları yoktur."""
        meta = self._meta([1, 2, 3, 4, 5, 6])
        dagilmis = [m._replace(kutu=(m.kutu[0] + i * 40, *m.kutu[1:]))
                    for i, m in enumerate(meta)]
        self.assertEqual(
            frozenset(),
            sk._guclu_zincir_uyeleri(dagilmis, self._Sayfa.genislik))

    def test_mukerrer_numara_ikinci_kutuya_kanit_yazmaz(self):
        """Dönüş numara DEĞERİ değil kutu KİMLİĞİ kümesidir. Aynı soru
        bölünme hatasıyla iki kutu üretirse (ölçüldü: 9pdf s113,
        numaralar [1,2,2,3,3,4,5,6]) numaraya göre eşleşme mükerrer kutuya
        da kanıt yazar ve precision düşerdi."""
        meta = self._meta([1, 2, 2, 3, 4, 5, 6])
        uyeler = sk._guclu_zincir_uyeleri(meta, self._Sayfa.genislik)
        ikinci_iki = tuple(meta[2].kutu)
        self.assertNotIn(ikinci_iki, uyeler)
        self.assertIn(tuple(meta[1].kutu), uyeler)

    def test_etkinlik_sayfasi_vetosu(self):
        """Ders kitabında '11. Etkinlik' sayfasındaki numaralı maddeler soru
        değil uygulama adımıdır ve bunlar da düzgün zincir kurar (ölçüldü:
        9pdf s69, altın 0 soru / motor 6 kutu)."""
        etkinlik = [("11. Etkinlik", (40.0, 20.0, 200.0, 34.0), False),
                    ("Yönerge", (40.0, 40.0, 120.0, 54.0), False)]
        self.assertTrue(sk._etkinlik_sayfasi_mi(etkinlik))

    def test_yonerge_tek_basina_veto_etmez(self):
        """'Yönerge:' gerçek soru sayfalarında da var (9pdf s89, s113);
        tek başına veto ederse meşru sorular kanıtsız kalırdı."""
        soru_sayfasi = [
            ("Yönerge: Aşağıdaki bulmacayı doldurarak inorganik moleküller "
             "hakkında edindiğiniz bilgileri kontrol ediniz.",
             (40.0, 20.0, 500.0, 34.0), False)]
        self.assertFalse(sk._etkinlik_sayfasi_mi(soru_sayfasi))


class CapaAraligiTesti(unittest.TestCase):
    def test_p25_siki_blogu_gorur_medyan_gormez(self):
        """Aynı sayfada sıkı paketli bir liste (17 pt) ile seyrek yerleşimli
        sorular (28-45 pt) birlikte bulunabiliyor; medyan sıkı bloğu göremez
        ve min_yuk eşiği yine yüksek kalırdı (ölçüldü: 12meb s186)."""
        ys = [0, 17, 34, 51, 68, 85, 300, 345, 390, 435]
        kutular = [(0.0, y, 100.0, y + 10) for y in ys]
        p25 = sk.capa_araligi_p25(kutular)
        self.assertAlmostEqual(17.0, p25, places=1)

    def test_az_capa_none_doner(self):
        self.assertIsNone(sk.capa_araligi_p25([(0, 0, 1, 1), (0, 20, 1, 21)]))
