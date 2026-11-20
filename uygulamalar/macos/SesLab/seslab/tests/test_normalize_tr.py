"""normalize_tr boru hattı testleri."""
import pytest

from app.core.text.normalize_tr import normalize_tr


def n(text: str) -> str:
    return normalize_tr(text)[0]


# --- Kısaltmalar -----------------------------------------------------------

def test_unvan_kisaltmasi():
    assert n("Dr. Ahmet geldi.") == "Doktor Ahmet geldi."


def test_unvan_zinciri():
    assert n("Prof. Dr. Ayşe Yılmaz") == "Profesör Doktor Ayşe Yılmaz"


def test_tc_kisaltmasi():
    assert n("T.C. Sağlık Bakanlığı") == "Türkiye Cumhuriyeti Sağlık Bakanlığı"


def test_liste_kisaltmasi_cumle_ici():
    assert n("elma, armut vb. meyveler") == "elma, armut ve benzeri meyveler"


def test_liste_kisaltmasi_cumle_sonu_nokta_korunur():
    out = n("Elma, armut vb. Şimdi başka konu.")
    assert out == "Elma, armut ve benzeri. Şimdi başka konu."


def test_adres_kisaltmalari():
    assert n("Atatürk Cad. No. 5") == "Atatürk Cadde Numara beş"


# --- Akronimler --------------------------------------------------------------

def test_sesli_harfsiz_akronim_harf_harf():
    assert n("TBMM toplandı.") == "te be me me toplandı."


def test_sesli_harfli_akronim_dokunulmaz():
    assert n("NATO zirvesi") == "NATO zirvesi"


def test_kisa_akronimler_daima_harf_harf():
    # Sesli harf içerse bile 2-3 harfliler harf harf okunur
    assert n("ABD ve AB anlaştı") == "a be de ve a be anlaştı"
    assert n("MEB duyurdu") == "me e be duyurdu"


def test_buyuk_harfli_kisa_turkce_sozcuk_akronim_degil():
    assert n("HAYATIN İÇİNDE BİR YOLCULUK") == "hayatın içinde bir yolculuk"
    assert n("BU SES ÇOK İYİ VE NET") == "bu ses çok iyi ve net"


def test_buyuk_harf_basliginda_gercek_akronimler_korunur():
    assert n("ABD VE AB RAPORU HAZIRLANDI") == "a be de ve a be raporu hazırlandı"
    assert n("TBMM GENEL KURULU BUGÜN TOPLANDI") == "te be me me genel kurulu bugün toplandı"


def test_beyaz_liste_kelime_okunur():
    assert n("TÜBİTAK ve ASELSAN projesi") == "TÜBİTAK ve ASELSAN projesi"
    assert n("TOKİ konutları") == "TOKİ konutları"


def test_dort_arti_telaffuz_edilebilir_kelime():
    # KOSGEB deseni: sesli oranı yeterli, ardışık 3 sessiz yok → kelime
    assert n("KOSGEB desteği") == "KOSGEB desteği"


def test_dort_arti_telaffuz_edilemez_harf_harf():
    # KPSS: ardışık sessizler → harf harf
    assert n("KPSS sonuçları") == "ke pe se se sonuçları"


# --- Romen rakamları -----------------------------------------------------------

def test_romen_sira_sayisi():
    assert n("II. Abdülhamit dönemi") == "ikinci Abdülhamit dönemi"
    assert n("XV. yüzyılda yaşadı") == "on beşinci yüzyılda yaşadı"


def test_romen_tek_harf_v():
    assert n("V. Murat tahta çıktı") == "beşinci Murat tahta çıktı"


def test_romen_olmayan_bas_harf_dokunulmaz():
    # "D." kişi adı baş harfi olabilir → çevrilmez
    out = n("John D. Rockefeller zengindi")
    assert "beş yüzüncü" not in out


# --- Yabancı kelimeler ------------------------------------------------------------

def test_yabanci_fonetik():
    assert n("WhatsApp ve YouTube yasağı") == "Vatsap ve Yutub yasağı"
    assert n("Google'da ara") == "Gugıl'da ara"


def test_yabanci_buyuk_kucuk_duyarsiz():
    assert n("WHATSAPP grubu") == "Vatsap grubu"


def test_yabanci_url_icinde_korunur():
    out = n("https://youtube.com/watch adresi")
    assert "youtube.com" in out  # URL koruması yabancı kuralından önce


# --- Para --------------------------------------------------------------------

def test_para_tl_sembol():
    assert n("₺1.250,50 ödedi.") == "bin iki yüz elli lira elli kuruş ödedi."


def test_para_tl_sonek():
    assert n("25 TL tuttu.") == "yirmi beş lira tuttu."


def test_para_kurussuz():
    assert n("₺100") == "yüz lira"


# --- Yüzde -------------------------------------------------------------------

def test_yuzde():
    assert n("%25 indirim") == "yüzde yirmi beş indirim"


def test_yuzde_ondalik():
    assert n("%12,5 faiz") == "yüzde on iki virgül beş faiz"


# --- Saat / tarih ------------------------------------------------------------

def test_saat():
    assert n("Saat 14:30 gibi.") == "Saat on dört otuz gibi."


def test_saat_sifirli_dakika():
    assert n("09:05 vapuru") == "dokuz sıfır beş vapuru"


def test_saat_tam():
    assert n("Toplantı 14:00 başlıyor") == "Toplantı on dört başlıyor"


def test_tarih_noktali():
    assert n("15.07.2026 tarihinde") == "on beş Temmuz iki bin yirmi altı tarihinde"


def test_tarih_gecersiz_ay_dokunulmaz():
    # 45. ay yok → tarih değil; sayılar yine de okunur ama ay adına dönüşmez
    out = n("13.45.2026")
    assert "Temmuz" not in out and "Nisan" not in out


# --- Telefon -----------------------------------------------------------------

def test_telefon():
    out = n("0532 123 45 67 numaralı")
    assert out == (
        "sıfır beş yüz otuz iki, yüz yirmi üç, kırk beş, altmış yedi numaralı"
    )


# --- Sıra sayıları -----------------------------------------------------------

def test_sira_noktali():
    assert n("1. sırada bitirdi.") == "birinci sırada bitirdi."


def test_sira_ekli_kesme():
    assert n("3'üncü kat") == "üçüncü kat"


def test_sira_ekli_dort():
    # num2words ordinal ünsüz yumuşamasını doğru yapar: dördüncü (dörtüncü değil)
    assert n("4'üncü sıra") == "dördüncü sıra"


# --- Kesme ekli sayılar --------------------------------------------------------

def test_kesme_ekli_yil():
    assert n("1923'te kuruldu.") == "bin dokuz yüz yirmi üçte kuruldu."


def test_kesme_ekli_den():
    assert n("100'den fazla") == "yüzden fazla"


# --- Ondalık / binlik / düz sayılar --------------------------------------------

def test_ondalik():
    assert n("Pi sayısı 3,14 olarak") == "Pi sayısı üç virgül on dört olarak"


def test_ondalik_bastaki_sifir():
    assert n("0,05 oranında") == "sıfır virgül sıfır beş oranında"


def test_binlik():
    assert n("1.000.000 kişi") == "bir milyon kişi"


def test_duz_sayi():
    assert n("42 yaşında") == "kırk iki yaşında"


# --- Birimler ------------------------------------------------------------------

def test_birim_km():
    assert n("5 km yol") == "beş kilometre yol"


def test_birim_derece():
    assert n("Hava 25°C") == "Hava yirmi beş derece"


# --- Kesme eki genişletmeleri ---------------------------------------------------

def test_yuzde_kesme_eki():
    assert n("%25'lik katılım") == "yüzde yirmi beşlik katılım"


def test_tarih_kesme_eki():
    assert n("15.07.2026'da yapıldı") == "on beş Temmuz iki bin yirmi altıda yapıldı"


# --- Kesir --------------------------------------------------------------------------

def test_kesir():
    assert n("1/2 oranında") == "bir bölü iki oranında"


def test_kesir_tarihi_bozmaz():
    # gg/aa/yyyy tarih kuralınca tüketilir, kesir kuralına düşmez
    assert n("15/07/2026 günü") == "on beş Temmuz iki bin yirmi altı günü"


# --- Yeni kısaltmalar / birimler --------------------------------------------------------

def test_sn_sayin_ve_saniye_ayrimi():
    assert n("Sn. Yılmaz geldi") == "Sayın Yılmaz geldi"
    assert n("5 sn. bekleyin") == "beş saniye bekleyin"


def test_dakika_birimi():
    assert n("15 dk. sürdü") == "on beş dakika sürdü"


def test_ay_kisaltmasi():
    assert n("12 Eki. tarihli yazı") == "on iki Ekim tarihli yazı"


def test_metrekare():
    assert n("120 m² daire") == "yüz yirmi metrekare daire"


# --- İnceleme düzeltmeleri regresyonları -------------------------------------------

def test_para_tek_haneli_ondalik_kurus():
    # 32,5 TL = 32 lira 50 kuruş (5 kuruş DEĞİL)
    assert n("32,5 TL ödedi") == "otuz iki lira elli kuruş ödedi"


def test_para_kesme_eki_uyumu():
    # TL'ye → liraya (ünlü uyumu: ye→ya)
    assert n("100 TL'ye aldım") == "yüz liraya aldım"


def test_ondalik_kesme_sirasi():
    # Ondalık kural kesme kuralından önce: kesir hanesi yutulmamalı
    out = n("3,5'lik artış")
    assert "üç virgül beş" in out


def test_dort_unsuz_yumusamasi():
    assert n("4'ü geldi") == "dördü geldi"
    assert n("24'ü aldı") == "yirmi dördü aldı"


def test_saat_nokta_ayracli():
    # TDK yazımı: 14.30
    assert n("Saat 14.30 gibi") == "Saat on dört otuz gibi"


def test_saat_kesme_ekli():
    assert n("14:30'da buluşalım") == "on dört otuzda buluşalım"


def test_tarih_nokta_saatten_once():
    # Nokta ayraçlı saat desteği tarihleri bozmamalı
    assert n("15.07.2026 günü") == "on beş Temmuz iki bin yirmi altı günü"


def test_negatif_sayi():
    assert n("Sıcaklık -5 derece") == "Sıcaklık eksi beş derece"


def test_sayi_araligi_bozulmaz():
    # "5-10" aralığındaki tire eksi okunmamalı
    out = n("5-10 arası")
    assert "eksi" not in out


def test_romen_rakami_noktali_harflenmez():
    out = n("XV. yüzyılda yaşadı")
    assert "iks" not in out


def test_cd_harflenir():
    # Nokta takip etmeyen sessiz kısaltma harf harf okunur
    assert n("CD çalar") == "ce de çalar"


def test_buyuk_bkz():
    assert n("Bkz. sayfa 5") == "Bakınız sayfa beş"


def test_vb_tirnakli_cumle_sonu():
    out = n('Elma, armut vb. "Şimdi" dedi.')
    assert 've benzeri. "Şimdi"' in out


# --- Koruma ----------------------------------------------------------------------

def test_url_korunur():
    out = n("Site: https://ornek.com/sayfa?id=25 adresinde")
    assert "https://ornek.com/sayfa?id=25" in out


def test_eposta_korunur():
    out = n("Mail: test25@ornek.com yazın")
    assert "test25@ornek.com" in out


# --- Tıbbi terimler -----------------------------------------------------------------

def test_i_buyuk_harf_cokme_regresyonu():
    # 'İ'.lower() = 'i̇' (i + U+0307); eskiden KeyError ile tüm hattı çökertirdi
    assert n("İnstagram hesabı açtı.") == "İnstagram hesabı açtı."
    assert n("İnsulin dozu ayarlandı.") == "insülin dozu ayarlandı."


def test_tibbi_latince_terimler():
    assert n("Escherichia coli üredi.") == "eşerihya koli üredi."
    assert n("Helicobacter pylori pozitif.") == "helikobakter pilori pozitif."
    assert n("Candida albicans saptandı.") == "kandida albikans saptandı."


def test_tibbi_ilac_ve_molekul():
    assert n("Warfarin başlandı.") == "varfarin başlandı."
    assert n("Paracetamol verildi.") == "parasetamol verildi."
    assert n("Kolesterol ve glucose yüksek.") == "Kolesterol ve glikoz yüksek."


def test_tibbi_vitamin_rakamli():
    assert n("B12 vitamini düşük.") == "be on iki vitamini düşük."
    assert n("D3 ve omega-3 önerildi.") == "de üç ve omega üç önerildi."


def test_covid_rakamli():
    assert n("COVID-19 aşısı yapıldı.") == "kovid on dokuz aşısı yapıldı."


def test_tansiyon_mmhg_datif():
    assert n("Tansiyon 120/80 mmHg ölçüldü.") == \
        "Tansiyon yüz yirmiye seksen milimetre cıva ölçüldü."
    assert n("Tansiyon 90/60 mmHg idi.") == \
        "Tansiyon doksana altmış milimetre cıva idi."


def test_tansiyon_kesme_ekli():
    assert n("Tansiyonu 140/90 mmHg'ye çıktı.") == \
        "Tansiyonu yüz kırka doksan milimetre cıvaya çıktı."


def test_tibbi_birimler():
    assert n("Şeker 110 mg/dl bulundu.") == "Şeker yüz on miligram desilitre bulundu."
    assert n("Kreatinin 1,2 mg/dL idi.") == "Kreatinin bir virgül iki miligram desilitre idi."
    assert n("Günde 400 IU verildi.") == "Günde dört yüz ünite verildi."


def test_mikrogram_iki_codepoint():
    # µ (U+00B5, mikro işareti) ve μ (U+03BC, Yunan mu) — ikisi de mikrogram
    assert n("Doz 500 µg ayarlandı.") == "Doz beş yüz mikrogram ayarlandı."
    assert n("Doz 500 μg ayarlandı.") == "Doz beş yüz mikrogram ayarlandı."
    assert n("5 mcg eklendi.") == "beş mikrogram eklendi."


def test_ph_case_sensitive():
    assert n("pH 7,35 ölçüldü.") == "pe haş yedi virgül otuz beş ölçüldü."
    # 'Ph.D.' yanlış eşleşmemeli (pH değil)
    assert "pe haş" not in n("Ali Ph.D. yaptı.")


def test_akronim_mr_emar():
    assert n("MR ve BT çekildi.") == "emar ve be te çekildi."
    assert n("EKG normaldi.") == "e ke ge normaldi."


def test_akronim_pet_kelime():
    # PET kelime gibi okunur (harf harf değil); LASIK de öyle
    assert n("PET taraması yapıldı.") == "PET taraması yapıldı."
    assert n("LASIK ameliyatı oldu.") == "LASIK ameliyatı oldu."


def test_saglik_akronim_lexicon():
    assert n("HIV testi negatif.") == "eyç ay vi testi negatif."
    assert n("AIDS tanısı kondu.") == "eyts tanısı kondu."


def test_duz_birim_bozulmadi():
    # Tıbbi kural genel birim kuralını bozmamalı
    assert n("Yol 5 km sürdü.") == "Yol beş kilometre sürdü."
    assert n("500 mg parasetamol.") == "beş yüz miligram parasetamol."


# --- Bilim / matematik -----------------------------------------------------------------

def test_matematik_operatorler():
    assert n("2 + 2 = 4") == "iki artı iki eşittir dört"
    assert n("10 × 5 = 50") == "on çarpı beş eşittir elli"
    assert n("8 ÷ 2") == "sekiz bölü iki"


def test_matematik_iliskiler():
    assert n("3 ≤ x") == "üç küçük eşittir x"
    assert n("a ≥ b") == "a büyük eşittir b"
    assert n("x ≠ y") == "x eşit değildir y"
    assert n("a ≈ b") == "a yaklaşık eşittir b"


def test_matematik_semboller():
    assert n("√16") == "karekök on altı"
    assert n("∑ değerleri") == "toplam değerleri"
    assert n("x ± 5") == "x artı eksi beş"
    assert n("∞ sonsuzdur") == "sonsuz sonsuzdur"


def test_usler_unicode():
    assert n("x² alanı") == "x kare alanı"
    assert n("y³ hacmi") == "y küp hacmi"
    assert n("E = mc²") == "E eşittir mc kare"


def test_usler_caret():
    assert n("10^-9 metre") == "on üzeri eksi dokuz metre"
    assert n("x^2 fonksiyonu") == "x üzeri iki fonksiyonu"


def test_kimya_formul_ascii():
    assert n("Su yani H2O içilir.") == "Su yani su içilir."
    assert n("CO2 salınımı arttı.") == "karbondioksit salınımı arttı."
    assert n("NaCl tuzdur.") == "sodyum klorür tuzdur."


def test_kimya_formul_unicode_altsimge():
    assert n("H₂SO₄ asittir.") == "sülfürik asit asittir."
    assert n("CO₂ gazı.") == "karbondioksit gazı."


def test_yunan_harfler():
    assert n("α ışını") == "alfa ışını"
    assert n("β bozunumu ve γ ışını") == "beta bozunumu ve gama ışını"
    assert n("π sayısı") == "pi sayısı"


def test_bilesik_birim():
    assert n("Hız 100 km/h idi.") == "Hız yüz kilometre saat idi."
    assert n("İvme 9,8 m/s² olur.") == "İvme dokuz virgül sekiz metre bölü saniye kare olur."
    assert n("Motor 3000 rpm döndü.") == "Motor üç bin devir dakika döndü."


def test_fizik_birimleri():
    assert n("Frekans 50 Hz.") == "Frekans elli hertz."
    assert n("Güç 100 kW.") == "Güç yüz kilovat."
    assert n("Sıcaklık 300 K.") == "Sıcaklık üç yüz kelvin."
    assert n("Ses 40 dB.") == "Ses kırk desibel."


def test_bilim_lexicon_element():
    assert n("Sodium ve potassium.") == "sodyum ve potasyum."
    assert n("Tungsten elementi.") == "volfram elementi."


def test_unicode_kesir():
    assert n("Yarısı ½ kadar.") == "Yarısı yarım kadar."
    assert n("¾ oranında.") == "dörtte üç oranında."


def test_bilim_regresyon_carpismalar():
    # Yeni kurallar mevcut aralık/tarih/bileşik-birim davranışını bozmamalı
    assert n("5-10 yaş arası") == "beş-on yaş arası"
    assert "on beş Temmuz iki bin yirmi altı" in n("15/07/2026 günü")
    assert n("Yol 5 km sürdü.") == "Yol beş kilometre sürdü."
    assert n("Oran 3/4 tür.") == "Oran üç bölü dört tür."


# --- Genişletilmiş bilim/tıp/biyoloji kapsamı -------------------------------------

def test_immunoloji_terimleri():
    assert n("Macrophage ve neutrophil hücreleri.") == "makrofaj ve nötrofil hücreleri."
    assert n("Phagocytosis ile pathogen yutulur.") == "fagositoz ile patojen yutulur."
    assert n("Lymphocyte ve monocyte.") == "lenfosit ve monosit."
    assert n("Cytokine salınımı.") == "sitokin salınımı."


def test_immunoglobulin_siniflari():
    assert n("IgG ve IgM antikorları.") == "i ge ge ve i ge me antikorları."
    assert n("IgA, IgE ve IgD.") == "i ge a, i ge e ve i ge de."


def test_hucre_biyolojisi():
    assert n("Mitochondrion ve lysosome.") == "mitokondri ve lizozom."
    assert n("Receptor ve membrane.") == "reseptör ve membran."
    assert n("Neuron ve synapse.") == "nöron ve sinaps."


def test_hastalik_ek_terimler():
    assert n("Meningitis ve bronchitis.") == "menenjit ve bronşit."
    assert n("Metastasis ve necrosis.") == "metastaz ve nekroz."


def test_bilim_element_ek():
    assert n("Selenium, zinc ve carbon.") == "selenyum, çinko ve karbon."
    assert n("Bismuth ve strontium.") == "bizmut ve stronsiyum."


def test_parcacik_fizigi():
    assert n("Electron, photon ve muon.") == "elektron, foton ve müon."
    assert n("Neutrino ve positron.") == "nötrino ve pozitron."


def test_kimya_iyon_ve_bilesikler():
    assert n("Bir cation ve bir anion.") == "Bir katyon ve bir anyon."
    assert n("Hydroxide ve sulfate.") == "hidroksit ve sülfat."
    assert n("ion dengesi") == "iyon dengesi"


def test_kimya_formul_ek():
    assert n("H2S kokar.") == "hidrojen sülfür kokar."
    assert n("Ca(OH)2 bazdır.") == "kalsiyum hidroksit bazdır."
    assert n("KCl ve AgNO3.") == "potasyum klorür ve gümüş nitrat."
    assert n("SiO2 kumdur.") == "silisyum dioksit kumdur."


def test_matematik_mantik_kume():
    assert n("∀x ∃y") == "her x vardır y"
    assert n("x ⇒ y") == "x ise y"
    assert n("ℝ ⊂ ℂ") == "reel sayılar alt kümesidir karmaşık sayılar"


def test_ek_fizik_birimleri():
    assert n("Doz 5 Gy.") == "Doz beş grey."
    assert n("Aktivite 200 Bq.") == "Aktivite iki yüz bekerel."
    assert n("Basınç 2 atm.") == "Basınç iki atmosfer."
    assert n("Direnç 10 Ω.") == "Direnç on om."


def test_genisletilmis_regresyon():
    # Yeni girişler normal Türkçe metni bozmamalı
    assert n("Milyonlarca hücre var.") == "Milyonlarca hücre var."
    assert n("On beş kişi geldi.") == "On beş kişi geldi."
    assert n("Bağışıklık iyon dengesini korur.") == "Bağışıklık iyon dengesini korur."


# --- Kural seçimi -----------------------------------------------------------------

def test_kural_kapatma():
    out, applied = normalize_tr("%25 indirim ve 42 elma", enabled_rules={"yuzde"})
    assert "yüzde yirmi beş" in out
    assert "42" in out  # 'sayi' kuralı kapalı → düz sayı dokunulmadan kalır
    assert applied == ["yuzde"]


def test_applied_listesi():
    _, applied = normalize_tr("Dr. Ahmet %25 indirim yaptı.")
    assert "kisaltma" in applied
    assert "yuzde" in applied


# --- Campbell biyoloji terimleri (Latince tür/takson, OCR ile küratörlendi) -------

def test_biyoloji_latince_tur_adlari():
    assert n("Drosophila melanogaster bir sinektir.") == \
        "drozofila melanogaster bir sinektir."
    assert n("Caenorhabditis elegans model organizmadır.") == \
        "senorabditis elegans model organizmadır."
    assert n("Saccharomyces cerevisiae bir mayadır.") == \
        "sakaromises serevizye bir mayadır."
    assert n("Panthera pardus ve Australopithecus.") == \
        "pantera pardus ve avustralopitekus."


def test_biyoloji_taksonomik_gruplar():
    assert n("Arthropoda ve Platyhelminthes.") == "artropoda ve platihelmintes."
    assert n("Rhodophyta ve Phaeophyta.") == "rodofita ve feofita."
    assert n("Chondrichthyes sınıfı.") == "kondriktiyes sınıfı."
    assert n("Cephalopoda ve Cephalochordata.") == "sefalopoda ve sefalokordata."


def test_biyoloji_patojen_turleri():
    assert n("Trichomonas vaginalis bir parazittir.") == \
        "trikomonas vajinalis bir parazittir."
    assert n("Entamoeba histolytica enfeksiyonu.") == \
        "entamiba histolitika enfeksiyonu."
