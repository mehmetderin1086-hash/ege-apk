"""Çekirdek veri modelleri: referans örnek, kanıt, üretilen çözüm."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import Any

# --- Sabit sözlükler -------------------------------------------------------

# Sorunun ne tür bir cevap beklediği. Tür yalnız etiket değil: istemi
# (`istemler.cevap_bicimi`), öz-kontroldeki doğrulamayı ve alım sırasındaki
# ayrıştırmayı belirler. Yeni tür eklenirken üçünün de güncellenmesi gerekir.
CEVAP_TURLERI = (
    "coktan_secmeli",    # A/B/C/D şıkları, cevap tek harf
    "dogru_yanlis",      # D/Y ya da Doğru/Yanlış
    "bosluk_doldurma",   # "…… organelinde gerçekleşir" — sıralı sözcükler
    "eslestirme",        # I-a, II-c gibi çiftler
    "siralama",          # olayları sıraya dizme
    "kisa_cevap",        # tek sözcük/sayı ("kaç ATP?", "adını yazınız")
    "acik_uclu",         # serbest açıklama (varsayılan)
)

# Kullanıcıya gösterilecek adlar; arayüzde ham enum yerine bunlar görünür.
CEVAP_TURU_ADLARI = {
    "coktan_secmeli": "Çoktan seçmeli",
    "dogru_yanlis": "Doğru / Yanlış",
    "bosluk_doldurma": "Boşluk doldurma",
    "eslestirme": "Eşleştirme",
    "siralama": "Sıralama",
    "kisa_cevap": "Kısa cevap",
    "acik_uclu": "Açık uçlu",
}

# Sorunun hangi muhakeme yapısıyla çözüldüğü. Araştırma bulgusu: örnek seçiminde
# yüzeysel anlamsal benzerlik yetersiz; getirilen örneğin ÇÖZÜM YAPISI hedef
# soruyla aynı olduğunda üretilen çözüm belirgin şekilde iyileşiyor.
COZUM_TURLERI = (
    "kalitim_hesabi",       # çaprazlama, olasılık, soyağacı
    "grafik_yorumlama",     # grafik/tablo/şema okuma ve çıkarım
    "deney_kurgusu",        # kontrol grubu, değişken, hipotez değerlendirme
    "siniflandirma",        # canlı grupları, karşılaştırma, ayırt edici özellik
    "mekanizma_aciklama",   # süreç/olay zinciri (fotosentez, mitoz, sinir iletimi)
    "hesaplama",            # sayısal işlem (ATP, kromozom sayısı, derişim)
    "ezber_bilgi",          # doğrudan tanım/olgu bilgisi
)

VARSAYILAN_COZUM_TURU = "mekanizma_aciklama"


def cevap_turu_dogrula(deger: str | None) -> str:
    deger = (deger or "").strip()
    return deger if deger in CEVAP_TURLERI else "acik_uclu"


def cozum_turu_dogrula(deger: str | None) -> str:
    deger = (deger or "").strip()
    return deger if deger in COZUM_TURLERI else VARSAYILAN_COZUM_TURU


# --- Modeller --------------------------------------------------------------


@dataclass
class Ornek:
    """Kullanıcının verdiği referans soru + çözüm çifti (hafızanın birimi)."""

    soru: str
    cozum: str                       # adım adım çözüm metni
    cevap: str = ""                  # nihai cevap (şık harfi veya kısa ifade)
    cevap_turu: str = "acik_uclu"
    secenekler: dict[str, str] = field(default_factory=dict)  # {"A": "...", ...}
    konu: str = ""                   # "mitoz", "fotosentez", "kalıtım" …
    cozum_turu: str = VARSAYILAN_COZUM_TURU
    etiketler: list[str] = field(default_factory=list)
    kaynak: str = ""                 # kitap/deneme adı, isteğe bağlı
    id: int | None = None
    etiket_kaynagi: str = "elle"     # elle | model | kural
    olusturma: str = ""
    # Soruya ait şekil/grafik/tablo görüntüsünün imzası. Görüntünün kendisi
    # `<kök>/gorseller/<imza>.png` dosyasında; bkz. `gorsel.GorselDeposu`.
    gorsel: str = ""
    # Kanıt havuzundan dışlanmış mı (kalite kapısı). `aktif=0`'dan farklı:
    # örnek hafızada kalır, yalnız RAG kanıtı olarak kullanılmaz.
    kanit_disi: bool = False
    # 0-1 arası kanıt kalite skoru; -1 = hiç puanlanmadı.
    kalite: float = -1.0
    # MEB Maarif Modeli öğrenme çıktısı kodu (ör. "BİY.9.1.1"); boş = etiketsiz.
    kazanim: str = ""

    def __post_init__(self) -> None:
        self.cevap_turu = cevap_turu_dogrula(self.cevap_turu)
        self.cozum_turu = cozum_turu_dogrula(self.cozum_turu)

    def indeks_metni(self) -> str:
        """Erişim indeksine giren metin: soru + şıklar + konu ipuçları.

        Çözüm metni bilinçli olarak DIŞARIDA: hedef soru henüz çözülmemişken
        onun çözümüyle eşleşme aranamaz; sorgu ile belge aynı uzayda olmalı.
        """
        parcalar = [self.soru]
        if self.secenekler:
            parcalar.append(
                " ".join(f"{harf}) {metin}" for harf, metin in sorted(self.secenekler.items()))
            )
        if self.konu:
            parcalar.append(self.konu)
        if self.etiketler:
            parcalar.append(" ".join(self.etiketler))
        return "\n".join(p for p in parcalar if p.strip())

    def sozluk(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class Pasaj:
    """Ders kitabından alınmış kavram metni — hafızanın İKİNCİ birimi.

    `Ornek` bir soru+çözüm çiftidir ve modele "böyle çözülür" der. `Pasaj`
    ise bir olgu kaynağıdır ve "bu doğrudur" der. İkisi ayrı tutuluyor
    çünkü isteme farklı rollerde giriyorlar: örnek taklit edilecek bir
    çözüm ÜSLUBU, pasaj ise dayanılacak bir BİLGİ. Pasajı `Ornek` olarak
    saklamak, modele soru-cevap sanıp taklit ettirirdi.
    """

    metin: str
    kaynak: str = ""                 # "Campbell Biyoloji" gibi kitap adı
    baslik: str = ""                 # bölüm/konu başlığı (varsa)
    sayfa: int | None = None
    konu: str = ""                   # biyo-cozucu konu etiketi
    id: int | None = None
    olusturma: str = ""

    def indeks_metni(self) -> str:
        """Erişim indeksine giren metin.

        Başlık metnin önüne konuyor: sorgu çoğu zaman konu adıyla eşleşiyor
        ve gövdede konu adı hiç geçmeyebiliyor.
        """
        parcalar = [self.baslik, self.konu, self.metin]
        return "\n".join(p for p in parcalar if p and p.strip())

    def kaynak_adi(self) -> str:
        parcalar = [p for p in (self.kaynak, f"s. {self.sayfa}" if self.sayfa else "") if p]
        return " · ".join(parcalar) or "ders kitabı"


@dataclass
class Kanit:
    """Çözüm üretiminde kullanılan referans örnek (atıf zincirinin halkası)."""

    etiket: str              # "Ö1", "Ö2" …
    ornek_id: int | None
    soru: str
    cozum: str
    konu: str
    cozum_turu: str
    skor: float
    cevap: str = ""
    tur_uyumlu: bool = False   # sorunun muhakeme yapısıyla eşleşiyor mu

    def kaynak_adi(self) -> str:
        kimlik = f"örnek #{self.ornek_id}" if self.ornek_id else "örnek"
        etiketler = " · ".join(x for x in (self.konu, self.cozum_turu) if x)
        return f"{kimlik} ({etiketler})" if etiketler else kimlik

    def siralama_notu(self) -> str:
        """`skor` yalnız benzerliktir; sıralamayı yapı uyumu belirler.

        İşaret olmadan liste "sıralı ama skorları artan" görünüp hata sanılıyor.
        """
        return "yapı uyumlu" if self.tur_uyumlu else ""


@dataclass
class Cozum:
    """Sistemin ürettiği çözüm."""

    soru: str
    adimlar: list[str] = field(default_factory=list)
    cevap: str = ""
    cevap_turu: str = "acik_uclu"
    # Şıklar çözümle birlikte saklanır: "B" cevabı şıklar olmadan anlamsızdır,
    # ve onaylanan çözüm referans örneğe dönüşürken şıkları taşımalıdır.
    secenekler: dict[str, str] = field(default_factory=dict)
    guven: float = 0.0
    kanitlar: list[Kanit] = field(default_factory=list)
    # Yanıt üretilirken isteme giren ders kitabı sayfaları. Referans örnek
    # kanıtlarından ayrı tutulur; yine de dışa aktarılan `kaynaklar` listesine
    # katılır ki kullanıcı olgunun hangi kitaba dayandığını görebilsin.
    kitap_kaynaklari: list[str] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)
    # Cevap anahtarı değerini taşımadan, çözümün nasıl doğrulandığını denetim
    # için yapılandırılmış biçimde saklar.
    dogrulama: dict[str, Any] = field(default_factory=dict)
    incele: bool = False              # insan gözden geçirmeli mi
    uretim_yontemi: str = "model"     # model | onbellek | ragsiz | yerel_rag
    model: str = ""
    # Sorunun görseli. Çözümle birlikte saklanır: aynı metin farklı şekille
    # sorulduğunda hangi şeklin çözüldüğü sonradan anlaşılamazdı.
    gorsel: str = ""
    # Görüntünün çözümdeki gerçek rolü. Eski kayıtlarda alanlar yoktur;
    # dataclass varsayılanlarıyla geriye uyumlu okunurlar.
    gorsel_turu: str = ""
    gorsel_kullanildi: bool = False
    gorsel_kanit_ozeti: str = ""
    algilama_guveni: float = 0.0
    dogrulama_durumu: str = ""
    konu: str = ""
    cozum_turu: str = VARSAYILAN_COZUM_TURU
    ham_yanit: str = ""
    id: int | None = None

    def kaynaklar(self) -> list[str]:
        kaynaklar = [k.kaynak_adi() for k in self.kanitlar]
        kaynaklar.extend(self.kitap_kaynaklari)
        return list(dict.fromkeys(kaynaklar))

    def soru_metni(self) -> str:
        """Soru + şıklar — önbellek kimliği ve gösterim için."""
        if not self.secenekler:
            return self.soru
        siklar = "\n".join(
            f"{harf}) {metin}" for harf, metin in sorted(self.secenekler.items())
        )
        return f"{self.soru}\n{siklar}"

    def metin(self) -> str:
        """İnsan okunur çözüm metni."""
        satirlar = [f"{i}. {adim}" for i, adim in enumerate(self.adimlar, 1)]
        if self.cevap:
            satirlar.append(f"Cevap: {self.cevap}")
        return "\n".join(satirlar)

    def sozluk(self) -> dict[str, Any]:
        veri = asdict(self)
        veri["kaynaklar"] = self.kaynaklar()
        return veri

    def json(self) -> str:
        return json.dumps(self.sozluk(), ensure_ascii=False)

    @classmethod
    def sozlukten(cls, veri: dict[str, Any]) -> Cozum:
        veri = dict(veri)
        veri.pop("kaynaklar", None)
        kanitlar = [Kanit(**k) for k in veri.pop("kanitlar", []) or []]
        bilinen = set(cls.__dataclass_fields__)
        return cls(kanitlar=kanitlar, **{k: v for k, v in veri.items() if k in bilinen})
