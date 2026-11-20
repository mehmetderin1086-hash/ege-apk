"""Ana çözüm akışı: birebir arşiv → önbellek → getirme → üretim → kontrol → kayıt."""

from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .biyobirikim import coz as biyobirikim_coz
from .cevap import cevap_eslesiyor, sik_harfi, tek_harf  # noqa: F401  (yeniden dışa verim)
from .depo import Depo
from .gomme import Gomlemci, kosinus
from .gorsel_zeka import (
    GORSEL_PIPELINE_SURUMU,
    VARSAYILAN_GORSEL_MODU,
    GorselKaniti,
    gorsel_modunu_dogrula,
    gorseli_hazirla,
    kanit_mesajlari,
    kaniti_ayikla,
)
from .gorsel_zeka import siniflandir as gorseli_siniflandir
from .hafiza.etiketleme import kural_ile_etiketle
from .hafiza.getirme import benzer_ornekler
from .hafiza.indeks import OrnekIndeksi
from .istemler import (
    VARSAYILAN_KANIT_ADIMI,
    cozum_mesajlari,
    gorsel_kurtarma_mesajlari,
    oz_kontrol_mesajlari,
)
from .kalitim.anlatim import adimlar as kalitim_adimlari
from .kalitim.cikarim import caprazlama_cikar
from .kalitim.eslestirme import sonuca_uyan_sik
from .kalitim.punnett import sorgula as punnett_sorgula
from .kalitim.soyagaci import (
    aile_okuma_mesajlari,
    aileyi_ayikla,
    graf_okuma_mesajlari,
    grafi_ayikla,
    olasilik_sorusu_mu,
    uyumluluk_coz,
    uyumluluk_sorusu_mu,
    x_cekinik_olasilik_coz,
)
from .kalitim.tespit import kalitim_adayi_mi
from .metin import esitle, nfc
from .metin import imza as metin_imzasi
from .modeller import Cozum, Kanit, cevap_turu_dogrula, cozum_turu_dogrula
from .motor.temel import (
    GorselMotor,
    Motor,
    MotorHatasi,
    akisa_dus,
    dusunceyi_ayikla,
    json_ayikla,
)
from .soru_turu import bosluk_sayisi, cevap_turunu_cikar

VARSAYILAN_KOK = Path(os.environ.get("BIYO_VERI", Path.home() / ".biyo-cozucu"))

# Cevabı MODEL değil deterministik bir hesap üreten yollar. Bunlar kanıt ve
# tür kalibrasyonundan muaf: o cezalar modelin muhakemesine olan güvensizliği
# ölçüyor, burada muhakeme yapan model değil.
_ARAC_YOLLARI = frozenset({"biyobirikim_araci", "kalitim_araci", "soyagaci_araci"})
# Tür bazlı güven çarpanları burada saklanır (`kalibre` komutu yazar, `kur` okur).
KALIBRASYON_DOSYASI = "kalibrasyon.json"
# ``Ornek.kalite`` 0-1 araliginda, -1 ise hic puanlanmamis demektir. Birebir
# arsiv yolu model uretmekten daha guclu bir yetki oldugu icin yalniz yuksek
# kalite bandi acilir; eski kayitlarin etkisiz -1 varsayilani guvenli kalir.
_TAM_REFERANS_ASGARI_KALITE = 0.90

# Modelin ÜRETTİĞİ (deterministik araç ya da arşiv kaydı olmayan) çözüm
# yolları. Oylama ve kanıtsızlık cezası bu kümeye bakıyor; yeni bir üretim
# yolu eklenip buraya yazılmazsa iki koruma da o yolda sessizce kapanır.
#
# `on_cevap` ve `bicimsiz` burada OLMAK ZORUNDA: ikisi de modelin kendi
# üretimi, yalnız şeması bozulmuş hâli. Dışarıda kaldıklarında üç denemenin
# üçü de kesildiğinde (kesilme soru uzunluğuna bağlı olduğu için denemeler
# arası güçlü korelasyonlu) oylama hiç çalışmaz, azınlık cevabı tam güvenle
# kazanır ve oy oranı çarpanı da uygulanmaz.
MODEL_KOKENLI = frozenset({"model", "kurtarma", "onbellek", "oylama", "on_cevap", "bicimsiz"})

# v2 şemasında `cevap` alanı hiç gelmediğinde, en başta üretilen `on_cevap`
# kullanılır. Tavan gerekli çünkü bu durumda muhakeme YARIM kalmıştır (adımlar
# tamamlansaydı `cevap` da gelirdi) — cevap modelin ilk kanaati, düşünülmüş
# sonucu değil. Tavan kurtarma yollarından (0,35) yüksek: cevap uydurulmuş
# değil, model tarafından açıkça beyan edilmiş. Kesin değeri ölçüm belirleyecek.
ON_CEVAP_TAVANI = 0.60
# `on_cevap` ile nihai `cevap` çelişiyorsa model adımları yazarken fikir
# değiştirmiş demektir. Bu iyiye de işaret olabilir (muhakeme hatayı düzeltti),
# belirsizliğe de; ikisini ayırt edecek ölçüm yok, bu yüzden ceza hafif tutuldu
# ve durum uyarı olarak işaretleniyor ki ölçümde ayrıştırılabilsin.
ON_CEVAP_CELISKI_CARPANI = 0.90


def kalibrasyonu_oku(kok: Path, *, model: str = "") -> dict[str, float]:
    """Diskteki tür güvenilirliği tablosu; yoksa boş (katman etkisiz).

    Tablo hangi modelle öğrenildiyse yalnız onunla anlamlıdır: çarpanlar o
    modelin tür bazlı zayıflığını ölçer. Model değiştiğinde tablo sessizce
    uygulanmaya devam ederse yeni modelin güveni eski modelin hatalarına
    göre kırpılır. `model` verilir ve kayıttaki modelle uyuşmazsa tablo
    yok sayılır.
    """
    yol = Path(kok) / KALIBRASYON_DOSYASI
    if not yol.exists():
        return {}
    try:
        veri = json.loads(yol.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if model and isinstance(veri, dict):
        kayitli = str(veri.get("model") or "")
        if kayitli and kayitli != model:
            return {}
    turler = veri.get("tur_guvenilirligi", veri)
    if not isinstance(turler, dict):
        return {}
    return {
        str(t): max(0.0, min(1.0, float(c)))
        for t, c in turler.items()
        if isinstance(c, (int, float))
    }


@dataclass
class Ayarlar:
    """Çözücü davranışını belirleyen eşikler."""

    ornek_sayisi: int = 3
    # Üretimde soru + şıklar yerel, kaynaklı çözüm arşiviyle birebir aynıysa
    # modeli yeniden çalıştırma. Kör değerlendirme ``haric_imzalar`` verdiğinde
    # bu yol otomatik kapanır; görsel bilgi gereken sorularda da kullanılmaz.
    tam_referans_aktif: bool = True
    onbellek_esigi: float = 0.92  # bu benzerliğin üstünde model çalıştırılmaz
    onbellek_aktif: bool = True
    oz_kontrol: bool = False  # ikinci bir model geçişi (yavaş ama daha güvenli)
    # Bu güvenin altındaki çözüm insana düşer. Kütüphane varsayılanı 0,55;
    # kullanıcıya giden yollarda 0,70 (bkz. `cli.VARSAYILAN_INCELEME_ESIGI`).
    # Eşik ölçümden OKUNDU — 40 soruluk oylamalı koşu: 0,70'te kapsama %40 /
    # doğruluk %87,5, 0,55'te kapsama %82 / doğruluk %73. Hedef "cevapladığında
    # yanılmamak" olduğu için kullanıcı yolunda yüksek eşik doğru seçim, ama
    # `Ayarlar()` diyen çağıranın davranışı sessizce değişmemeli: eşiği
    # yükseltmek incelemeye düşen çözümleri artırır ve onlar önbelleğe girmez.
    inceleme_esigi: float = 0.55
    sicaklik: float = 0.2
    # Düşünme kapalıyken (varsayılan) 1600 token bol yetiyor. BIYO_DUSUNME=1
    # ile düşünme açılırsa bu değer birkaç kat artırılmalı, yoksa üretim
    # düşüncenin ortasında kesilir ve JSON hiç gelmez.
    azami_token: int = 1600
    kanitsiz_ceza: float = 0.25  # hiç referans örnek yoksa güvenden düşülür
    # Kalıtım sorularında deterministik Punnett çözücüsü denensin mi. Açık
    # olması ölçüldü: 4B model Punnett karesini ve olasılık çarpımını yapamıyor
    # (kalitim_hesabi türünde doğruluk %18). Kapatmak yalnız A/B ölçümü için.
    kalitim_araci: bool = True
    tur_uyumsuzluk_cezasi: float = 0.10
    # Bu benzerliğin altındaki en iyi kanıt "zayıf" sayılır ve güven oranla
    # düşürülür. Erişim skorları RRF sonrası 0-1 aralığında; ölçümde doğru
    # çözümlerin kanıt skoru belirgin biçimde daha yüksek çıkıyor.
    zayif_kanit_esigi: float = 0.60
    # İsteme giren ders kitabı pasajı sayısı. 2'de tutuluyor: pasajlar örnek
    # çözümlerden uzun ve bağlamı şişirmek üretimi token sınırında kestiriyor —
    # kapsamayı düşüren ana mekanizma buydu. 0 = kaynak metni hiç kullanma.
    pasaj_sayisi: int = 2
    # --- geri düşüş yollarının güven tavanları ---
    #
    # Bunlar ayarlanabilir çünkü hiçbiri ÖLÇÜLMÜŞ değil; elle seçilmiş
    # değerler. Üçü de `inceleme_esigi`nin (kullanıcı yolunda 0,70) ALTINDA
    # olduğu için bu yollardan gelen her cevap incelemeye düşüyor ve
    # kapsamaya sıfır katkı veriyor — cevap doğru olsa bile. Tavanın haklı
    # olup olmadığı ancak `KosuOzeti.yontem_bazli()` kırılımı okunarak
    # anlaşılır: doğruluk yüksek ama `esik_ustu` sıfırsa tavan doğru
    # cevapları boğuyor demektir.
    kurtarma_tavani: float = 0.35  # cevap/görsel kurtarma, soyağacı model yolu
    onarim_tavani: float = 0.5  # JSON kısmen onarıldı
    bicimsiz_tavani: float = 0.2  # JSON hiç gelmedi, metinden çıkarıldı
    on_cevap_tavani: float = 0.60  # v2 şemasında nihai cevap yerine ön cevap
    # Aynı soruyu kaç kez çözüp oylayacağı (1 = oylama yok). Oy oranı, güven
    # için modelin kendi beyanından çok daha dürüst bir sinyal: 3/3 birleşen
    # cevap ile 2/3 bölünen cevap aynı değil.
    #
    # Varsayılan 3, çünkü ÖLÇÜM bunu gerektiriyor: tek atışta güven doğruyu
    # yanlıştan ayırmıyor (doğru 0,891 / yanlış 0,872 — sistem yanılırken de
    # "eminim" diyor), oylamayla fark 0,254'e çıkıyor (0,784 / 0,530).
    # 3/3 birleşen sorularda doğruluk %87,5, çok bölünenlerde %14.
    # Bedeli soru başına 3 üretim: MLX'te üretimler seri koştuğu için cevap
    # ~3 kat geç geliyor. Hız doğruluğa yeğleniyorsa `--deneme 1`.
    #
    # KÜTÜPHANE varsayılanı yine de 1: `Ayarlar()` diyen çağıran, sessizce üç
    # kat maliyet üstlenmemeli. Kullanıcıya giden yollarda (CLI ve sunucu)
    # varsayılan 3'tür — bkz. `cli.VARSAYILAN_DENEME`.
    deneme_sayisi: int = 1
    # Oylamanın çeşitlilik sıcaklığı. İlk deneme daima `sicaklik` ile (yani
    # ölçümde 0, deterministik) yapılır; bu değer yalnız sonraki denemelere
    # uygulanır. 0 olsaydı üç deneme de aynı yanıtı verir, oylama maliyeti
    # ödenip hiçbir bilgi alınmazdı.
    deneme_sicakligi: float = 0.7
    # Çözüm türü → güven çarpanı. Sistemin bazı muhakeme türlerinde
    # diğerlerinden belirgin şekilde zayıf olduğu ölçüldü (125 soruluk koşu:
    # sınıflandırma %88, mekanizma %63, grafik %31, kalıtım %18) ve model
    # ZAYIF olduğu türde de 0,9 güven bildiriyor. Bu tablo o farkı güvene
    # taşır; seçici doğruluk hedefinde doğru davranış, zayıf türde kendini
    # frenleyip insana devretmektir.
    #
    # Tablo TEST kümesinden değil, `kalibre` komutuyla DOĞRULAMA diliminden
    # öğrenilir — test kümesinden öğrenmek ölçümü kendi kendini doğrulayan bir
    # şeye çevirirdi. Boş bırakılırsa katman tümüyle etkisizdir.
    tur_guvenilirligi: dict[str, float] = field(default_factory=dict)
    # Kanıt yanıtlarının isteme girecek azami adım sayısı (0 = sınırsız).
    # Few-shot örneğinin uzunluğu üretilen yanıtın uzunluğunu belirliyor:
    # hafızaya 14 adım ortalamalı soru bankası çözümleri girdikten sonra model
    # aynı uzunlukta yanıt üretmeye çalışıp `azami_token` sınırında kesilmeye
    # başladı. Sıcaklık 0'daki ölçümde 6 adım sınırı doğruluğu 5/12'den
    # 6/12'ye, güveni 0.75'ten 0.82'ye çıkardı; `azami_token`ı 1600'den 3000'e
    # çıkarmak ise sonucu hiç değiştirmedi.
    kanit_azami_adim: int = VARSAYILAN_KANIT_ADIMI


@dataclass
class _Baglam:
    """Bir çözüm isteğinin ön hazırlıkta üretilen, son işlemde gereken durumu."""

    soru: str
    secenekler: dict[str, str] = field(default_factory=dict)
    cevap_turu: str | None = None
    beklenen_tur: str = ""
    kimlik: str = ""
    baglam_imza: str = ""
    onbellek_kullanilabilir: bool = True
    sorgu_vektoru: np.ndarray | None = None
    konu: str = ""
    tur: str = ""
    kanitlar: list[Kanit] = field(default_factory=list)
    kaydet: bool = True
    gorsel_imza: str = ""
    gorsel_veri: bytes = b""
    gorsel_modu: str = VARSAYILAN_GORSEL_MODU
    gorsel_turu: str = ""
    gorsel_gerekli: bool = False
    gorsel_karar_guveni: float = 0.0
    gorsel_karar_nedeni: str = ""
    # Kalıtım kural katmanına başvurulduysa sonucu: "" (hiç denenmedi) |
    # "hesaplandi_baglanamadi". Ölçümde bu boşluğun büyüklüğünü görmenin
    # tek yolu; çözüm uyarısına da yazılır.
    kalitim_bagvurusu: str = ""
    gorsel_kaniti: GorselKaniti | None = None
    # Ucuz regex ön süzgeci deterministik kalıtım çözücüsünü işaret etti mi.
    # `_hazirla` model çağırmaz; bu bayrak da saf metin denetiminden geliyor.
    kalitim_adayi: bool = False
    # Sorunun kaynağından (soru kesici/OCR) gelen güven. 0 = bilinmiyor.
    kaynak_guveni: float = 0.0
    # Soruyla ilgili ders kitabı pasajları (varsa). `_hazirla`da BİR KEZ
    # getiriliyor: oylama 3 deneme yapıyor ve her denemede yeniden aramak
    # gömlemciyi üç kez çalıştırırdı.
    pasajlar: list = field(default_factory=list)


@dataclass
class Cozucu:
    depo: Depo
    indeks: OrnekIndeksi
    motor: Motor | None = None
    gomlemci: Gomlemci | None = None
    ayarlar: Ayarlar = field(default_factory=Ayarlar)
    # Görsel deposu; verilmezse görselli soru metin olarak çözülür.
    gorsel_deposu: object | None = None
    # Ders kitabı pasaj indeksi; None = kitap alınmamış, akış aynen eskisi gibi.
    pasaj_indeksi: object | None = None

    # --- kurulum ---

    @classmethod
    def kur(
        cls,
        kok: str | Path | None = None,
        *,
        motor: Motor | None = None,
        gomlemci: Gomlemci | None = None,
        gomme_yukle: bool = True,
        ayarlar: Ayarlar | None = None,
    ) -> Cozucu:
        kok = Path(kok or VARSAYILAN_KOK)
        depo = Depo(kok / "biyo.db")
        indeks_dizini = kok / "indeks"
        if gomlemci is None and gomme_yukle:
            # Modül üzerinden: ad import anında bağlanırsa testlerin yerine
            # koyduğu sahte gömlemci devreye girmez (bkz. webapp/durum.py).
            from . import gomme as gomme_modulu

            gomlemci = gomme_modulu.gomlemci_yukle()
        if OrnekIndeksi.hazir_mi(indeks_dizini):
            indeks = OrnekIndeksi.yukle(indeks_dizini)
        else:
            indeks = OrnekIndeksi.kur(depo.ornekler(), gomlemci)
        from .gorsel import GorselDeposu

        ayarlar = ayarlar or Ayarlar()
        # Diskteki kalibrasyon, çağıran açıkça bir tablo vermediyse yüklenir:
        # `kalibre` komutunun ürettiği tablo böylece her çalıştırmada kendiliğinden
        # devreye girer, ayrıca bayrak gerekmez.
        if not ayarlar.tur_guvenilirligi:
            ayarlar.tur_guvenilirligi = kalibrasyonu_oku(
                kok, model=str(getattr(motor, "ad", "") or "")
            )
        # Pasaj indeksi yalnız kitap alınmışsa kuruluyor: boş bir indeks
        # kurmak gömlemciyi bir kez daha çalıştırıp açılışı yavaşlatırdı.
        pasaj_indeksi = None
        if depo.pasaj_say():
            from .hafiza.pasaj import PasajIndeksi

            pasaj_indeksi = PasajIndeksi.kur(depo.pasajlar(), gomlemci)
        return cls(depo, indeks, motor, gomlemci, ayarlar, GorselDeposu(kok), pasaj_indeksi)

    def indeksi_yenile(self, kok: str | Path | None = None) -> OrnekIndeksi:
        """Depodaki örneklerden indeksi yeniden kurar ve diske yazar."""
        self.indeks = OrnekIndeksi.kur(self.depo.ornekler(), self.gomlemci)
        if kok:
            self.indeks.kaydet(Path(kok) / "indeks")
        return self.indeks

    def _gorsel_modele_gidiyor(self, gorsel_veri: bytes) -> bool:
        """Görüntü gerçekten modele veriliyor mu?

        Yalnız dosyanın okunabilmesi yetmez: metin motoru görüntüyü almıyor.
        İsteme "şekildeki veriyi oku" talimatı eklemek o durumda modeli
        var olmayan bir veriyi aramaya itiyor — ölçümde boş cevabı artırdı.
        Motorun görsel okuyamadığı `_sonlandir`'da ayrıca uyarıya çevriliyor.
        """
        return bool(gorsel_veri) and isinstance(self.motor, GorselMotor)

    def _gorsel_oku(self, imza: str) -> bytes:
        """Görüntü baytları; okunamazsa boş döner ve soru metinle çözülür.

        Eksik bir dosya yüzünden çözümü tümden reddetmek doğru değil: metin
        yolu hâlâ işe yarar bir cevap üretebilir. Ama sessiz de kalınmaz —
        `_sonlandir` bunu uyarıya çevirip çözümü incelemeye düşürür.
        """
        if not imza or self.gorsel_deposu is None:
            return b""
        try:
            return self.gorsel_deposu.oku(imza)
        except Exception:  # noqa: BLE001 - dosya yok, izin yok, bozuk
            return b""

    # --- önbellek ---

    @staticmethod
    def onbellek_kimligi(
        soru: str,
        secenekler: dict[str, str] | None,
        cevap_turu: str | None,
        gorsel: str = "",
        model: str = "",
        kitap_baglam: str = "",
    ) -> str:
        """Çözümü tek belirleyen metin.

        Şıklar ve cevap türü anahtarın parçasıdır: aynı soru gövdesi farklı
        şıklarla sorulduğunda eski şık harfi geçerli olmaz. Aynı gerekçeyle
        GÖRSEL de anahtara girer: "Grafikteki eğri neyi gösterir?" metni iki
        farklı şekille sorulduğunda ikincisi birincinin cevabını önbellekten
        alırdı — sessiz ve ciddi bir hata.

        MODEL de anahtara girer: aynı soru farklı bir modelle sorulduğunda eski
        modelin cevabı dönerse sürüm karşılaştırması anlamını yitirir. LoRA
        eğitimi sonrası kör koşuda tam bunu yaşadık — eğitilmiş model hiç
        çalıştırılmadan taban modelin önbellekteki çözümü geri geldi.
        """
        parcalar = [soru.strip()]
        if model:
            parcalar.append(f"[model:{model}]")
        if gorsel:
            parcalar.append(f"[gorsel:{gorsel}]")
        if secenekler:
            parcalar.append(" | ".join(f"{h}={m}" for h, m in sorted(secenekler.items())))
        if cevap_turu:
            parcalar.append(f"[{cevap_turu}]")
        if kitap_baglam:
            parcalar.append(f"[kitap:{kitap_baglam}]")
        return "\n".join(parcalar)

    @staticmethod
    def baglam_imzasi(
        secenekler: dict[str, str] | None,
        cevap_turu: str | None,
        gorsel: str = "",
        model: str = "",
        kitap_baglam: str = "",
    ) -> str:
        """Şık eşlemesi + cevap türü + görsel + modelin kararlı özeti.

        Yakın eşleşmede kapı olarak kullanılır: gömme, şıkları yer değiştirmiş
        iki soruyu ayırt edemez (aynı kelimeler, farklı harfler), bu yüzden
        eşleme birebir tutmayan önbellek girdileri hiç değerlendirilmez.
        Görsel de aynı kapıdan geçer: metni benzeyen iki soru farklı şekiller
        taşıyorsa yakın eşleşme sayılmamalı.

        MODEL de kapının parçası. Tam eşleşmeyi `onbellek_kimligi` zaten modele
        göre ayırıyor, ama yakın eşleşme ondan bağımsız çalışıyor: model
        değiştikten sonra birebir aynı soru sorulduğunda benzerlik 1,0 çıkıp
        eski modelin çözümü geri geliyordu ve sürüm karşılaştırması sessizce
        anlamını yitiriyordu.
        """
        parcalar = [f"{h}={m.strip()}" for h, m in sorted((secenekler or {}).items())]
        parcalar.append(f"[{cevap_turu or ''}]")
        if gorsel:
            parcalar.append(f"[gorsel:{gorsel}]")
        if model:
            parcalar.append(f"[model:{model}]")
        if kitap_baglam:
            parcalar.append(f"[kitap:{kitap_baglam}]")
        return metin_imzasi(" | ".join(parcalar))

    @staticmethod
    def kitap_baglam_imzasi(pasajlar: list) -> str:
        """İsteme giren kitap olgularının önbellek kimliği.

        Aynı soru, kitap alımından önce çözülmüş olabilir. Eski önbelleği
        doğrudan döndürmek o yeni kitabı yalnız kaynak listesinde bırakır;
        bu imza, Campbell/Guyton pasajları değiştiğinde ortak hafızadan
        yeniden çözüm üretilmesini zorunlu kılar.
        """
        if not pasajlar:
            return ""
        return metin_imzasi(
            "\n".join(
                f"{pasaj.kaynak}|{pasaj.sayfa}|{pasaj.baslik}|{pasaj.metin}" for pasaj in pasajlar
            )
        )

    def _onbellekten(
        self, kimlik: str, soru: str, baglam_imza: str = ""
    ) -> tuple[Cozum | None, np.ndarray | None]:
        if not self.ayarlar.onbellek_aktif:
            return None, None
        tam = self.depo.onbellek_tam_eslesme(kimlik)
        if tam is not None:
            tam.uretim_yontemi = "onbellek"
            return tam, None

        vektor: np.ndarray | None = None
        if self.gomlemci is not None:
            # Gömme yalnız soru gövdesinden alınır: şık metinlerini de katmak
            # ayırt edici sözcüğü ("hangisi doğrudur"/"yanlıştır") uzun bir
            # dizenin içinde eritip olumsuz ikizleri eşiğin üstüne taşırdı.
            # Şık eşlemesini `baglam_imza` zaten birebir denetliyor.
            vektor = np.asarray(self.gomlemci.gom([soru], sorgu=True), dtype=np.float32)[0]
            girdiler = self.depo.onbellek_girdileri(baglam_imza)
            uyumlu = [(a, v, j) for a, v, j in girdiler if v.shape == vektor.shape]
            if uyumlu:
                matris = np.stack([v for _a, v, _j in uyumlu])
                benzerlikler = kosinus(vektor[None, :], matris)[0]
                en_iyi = int(np.argmax(benzerlikler))
                if float(benzerlikler[en_iyi]) >= self.ayarlar.onbellek_esigi:
                    import json as _json

                    cozum = Cozum.sozlukten(_json.loads(uyumlu[en_iyi][2]))
                    cozum.uretim_yontemi = "onbellek"
                    # Soru birebir aynı değil; çağıran soru/şık alanlarını yeni
                    # soruyla değiştiriyor. İncelemeye düşürmezsek bu karma kayıt
                    # onaylanıp "yeni soru + eski çözüm" diye referans örnek olur.
                    cozum.incele = True
                    cozum.uyarilar = [
                        *list(cozum.uyarilar),
                        f"Neredeyse aynı bir soru daha önce çözülmüştü "
                        f"(benzerlik {float(benzerlikler[en_iyi]):.2f}). "
                        f"Çözüm o soruya aittir, onaylamadan önce doğrulayın.",
                    ]
                    self.depo._isabet_artir(uyumlu[en_iyi][0])  # noqa: SLF001
                    return cozum, vektor
        return None, vektor

    @staticmethod
    def _tam_metin(metin: str) -> str:
        """Exact arsiv karsilastirmasi icin yalniz Unicode/bosluk normalize et.

        ``sadelestir`` arama ve benzerlik icin dogru olsa da ``<``/``>``,
        ``+``/``-`` ve ``/`` gibi anlami degistiren operatorleri atar. Burada
        noktalama, buyuk-kucuk harf ve operatorler aynen korunur.
        """
        return " ".join(nfc(metin).split())

    @classmethod
    def _secenekler_birebir(cls, gelen: dict[str, str] | None, kayitli: dict[str, str]) -> bool:
        if not gelen or not kayitli or set(gelen) != set(kayitli):
            return False
        return all(cls._tam_metin(gelen[harf]) == cls._tam_metin(kayitli[harf]) for harf in gelen)

    def _tam_referanstan(
        self,
        soru: str,
        secenekler: dict[str, str] | None,
        *,
        gorsel: str,
        haric_imzalar: set[str] | None,
    ) -> Cozum | None:
        """Yerel arşivdeki birebir, kaynaklı çözümü model çalıştırmadan kullan."""
        if not self.ayarlar.tam_referans_aktif or haric_imzalar is not None or gorsel:
            return None
        ornek = self.depo.ornek_sorusuyla(soru)
        if (
            ornek is None
            or ornek.gorsel.strip()
            or not (_TAM_REFERANS_ASGARI_KALITE <= ornek.kalite <= 1.0)
            or not ornek.cevap.strip()
            or not ornek.cozum.strip()
            or self._tam_metin(soru) != self._tam_metin(ornek.soru)
            or not self._secenekler_birebir(secenekler, ornek.secenekler)
        ):
            return None
        cevap = sik_harfi(ornek.cevap, ornek.secenekler, soru=ornek.soru)
        if not cevap or cevap not in {harf.upper() for harf in ornek.secenekler}:
            return None
        from .istemler import cozumu_adimlara_bol

        kanit = Kanit(
            etiket="Yerel arşiv",
            ornek_id=ornek.id,
            soru=ornek.soru,
            cozum=ornek.cozum,
            konu=ornek.konu,
            cozum_turu=ornek.cozum_turu,
            cevap=cevap,
            skor=1.0,
            tur_uyumlu=True,
        )
        return Cozum(
            soru=soru,
            adimlar=cozumu_adimlara_bol(ornek.cozum),
            cevap=cevap,
            cevap_turu=ornek.cevap_turu,
            secenekler=dict(secenekler or {}),
            guven=0.99,
            kanitlar=[kanit],
            uyarilar=[
                "Soru ve şıklar, yerel kaynaklı çözüm arşivindeki kayıtla "
                "birebir eşleşti; model yeniden çalıştırılmadı."
            ],
            uretim_yontemi="tam_referans",
            konu=ornek.konu,
            cozum_turu=ornek.cozum_turu,
            dogrulama={
                "tam_referans": True,
                "ornek_id": ornek.id,
                "kaynak": ornek.kaynak,
            },
        )

    # --- ana akış ---

    def _hazirla(
        self,
        soru: str,
        secenekler: dict[str, str] | None,
        cevap_turu: str | None,
        kaydet: bool,
        haric_imzalar: set[str] | None,
        gorsel: str = "",
        kaynak_guveni: float = 0.0,
        gorsel_modu: str = VARSAYILAN_GORSEL_MODU,
    ) -> tuple[_Baglam, Cozum | None]:
        """Ortak ön hazırlık: doğrulama → önbellek → etiketleme → kanıt getirme.

        `coz()` ve `coz_akis()` bu tek yolu paylaşır; ikinci bir doğruluk yolu
        açmak, önbellek/sızıntı korumalarının birinde unutulmasına yol açardı.
        """
        soru = soru.strip()
        if not soru:
            raise ValueError("Boş soru çözülemez.")
        gorsel_modu = gorsel_modunu_dogrula(gorsel_modu)
        ham_gorsel = self._gorsel_oku(gorsel)
        gorsel_karari = gorseli_siniflandir(
            soru,
            secenekler,
            gorsel_var=bool(gorsel),
            mod=gorsel_modu,
        )
        gorsel_veri = (
            gorseli_hazirla(ham_gorsel)
            if ham_gorsel and gorsel_karari.gerekli
            else b""
        )

        # Tür verilmediyse metinden çıkarılır. Eskiden yalnız "şık var mı"
        # bakılıyordu; boşluk doldurma, eşleştirme, sıralama ve doğru/yanlış
        # soruları sessizce açık uçlu sayılıp modele yanlış biçim talimatı
        # gidiyordu.
        beklenen_tur = cevap_turu_dogrula(cevap_turu or cevap_turunu_cikar(soru, secenekler))
        # Kitap ve soru çözümü hafızası aynı çözüm bağlamını oluşturur.
        # Kitap getirimi önbellekten ÖNCE yapılmalı: aksi halde Guyton ya da
        # Campbell sonradan eklense bile eski, kitap görmemiş yanıt dönerdi.
        pasajlar = self._pasajlari_getir(soru)
        kitap_baglam = self.kitap_baglam_imzasi(pasajlar)
        gorsel_onbellek = ""
        if gorsel:
            gorsel_onbellek = (
                f"{gorsel}:{GORSEL_PIPELINE_SURUMU}:{gorsel_modu}:"
                f"{gorsel_karari.tur}:{int(gorsel_karari.gerekli)}"
            )
        kimlik = self.onbellek_kimligi(
            soru,
            secenekler,
            beklenen_tur,
            gorsel_onbellek,
            getattr(self.motor, "ad", ""),
            kitap_baglam,
        )
        baglam_imza = self.baglam_imzasi(
            secenekler,
            beklenen_tur,
            gorsel_onbellek,
            getattr(self.motor, "ad", ""),
            kitap_baglam,
        )

        # Kaynakli, pozitif kalite kapisindan gecen birebir arsiv kaydi; modelin
        # onceki bir uretiminden kalan onbellekten daha yetkilidir. Kor kosuda
        # bos kume dahi bilincli bir sinyaldir ve iki kisa yol da kapanir.
        tam_referans = self._tam_referanstan(
            soru,
            secenekler,
            gorsel=gorsel,
            haric_imzalar=haric_imzalar,
        )
        if tam_referans is not None:
            # Erken dönüş `_sonlandir`/`_oz_kontrol`e uğramıyor; tavan
            # burada elle uygulanmazsa kesme kalitesi bu yolda yok sayılır.
            self._kaynak_tavanini_uygula(tam_referans, kaynak_guveni)
            if kaydet:
                tam_referans.id = self.depo.cozum_kaydet(tam_referans)
            return _Baglam(soru=soru), tam_referans

        # Kör değerlendirmede önbellek atlanır: aynı soru daha önce arayüzden
        # çözülmüşse cevabı doğrudan dönerdi ve ölçüm anlamsızlaşırdı.
        onbellek_kullanilabilir = haric_imzalar is None
        onbellekten, sorgu_vektoru = (
            self._onbellekten(kimlik, soru, baglam_imza)
            if onbellek_kullanilabilir
            else (None, None)
        )
        if onbellekten is not None:
            onbellekten.soru = soru
            onbellekten.secenekler = dict(secenekler or {})
            onbellekten.gorsel = gorsel
            # Aynı soru daha önce temiz metinle yüksek güvenle çözülüp
            # önbelleğe girmiş olabilir; kötü kesilmiş hâliyle geldiğinde
            # o eski güveni miras almamalı.
            self._kaynak_tavanini_uygula(onbellekten, kaynak_guveni)
            if kaydet:
                onbellekten.id = self.depo.cozum_kaydet(onbellekten)
            return _Baglam(soru=soru), onbellekten

        konu, tur = kural_ile_etiketle(soru)
        kanitlar = benzer_ornekler(
            self.indeks,
            soru,
            gomlemci=self.gomlemci,
            k=self.ayarlar.ornek_sayisi,
            cozum_turu=tur,
            konu=konu,
            haric_imzalar=haric_imzalar,
        )
        baglam = _Baglam(
            soru=soru,
            secenekler=dict(secenekler or {}),
            cevap_turu=cevap_turu,
            beklenen_tur=beklenen_tur,
            kimlik=kimlik,
            baglam_imza=baglam_imza,
            onbellek_kullanilabilir=onbellek_kullanilabilir,
            sorgu_vektoru=sorgu_vektoru,
            konu=konu,
            tur=tur,
            kanitlar=kanitlar,
            kaydet=kaydet,
            gorsel_imza=gorsel,
            gorsel_veri=gorsel_veri,
            gorsel_modu=gorsel_modu,
            gorsel_turu=gorsel_karari.tur,
            gorsel_gerekli=gorsel_karari.gerekli,
            gorsel_karar_guveni=gorsel_karari.guven,
            gorsel_karar_nedeni=gorsel_karari.neden,
            kalitim_adayi=(
                self.ayarlar.kalitim_araci and kalitim_adayi_mi(soru, secenekler or None)
            ),
            kaynak_guveni=kaynak_guveni,
            pasajlar=pasajlar,
        )
        return baglam, None

    def _pasajlari_getir(self, soru: str) -> list:
        """Soruyla ilgili ders kitabı pasajları; kitap alınmamışsa boş."""
        if self.pasaj_indeksi is None:
            return []
        from .hafiza.pasaj import benzer_pasajlar

        return benzer_pasajlar(
            self.pasaj_indeksi,  # type: ignore[arg-type]
            soru,
            gomlemci=self.gomlemci,
            k=self.ayarlar.pasaj_sayisi,
        )

    def _sonlandir(self, baglam: _Baglam, cozum: Cozum) -> Cozum:
        """Ortak son işlem: tür normalizasyonu → öz-kontrol → kayıt → önbellek."""
        secenekler = baglam.secenekler or None
        # Beklenen tür `_hazirla`da bir kez belirlendi; burada yeniden
        # türetmek modelin bildirdiği türle çelişip biçim denetimini bozardı.
        cozum.cevap_turu = baglam.beklenen_tur or cevap_turu_dogrula(
            baglam.cevap_turu or cozum.cevap_turu
        )
        cozum.secenekler = dict(baglam.secenekler)
        if baglam.kalitim_bagvurusu == "hesaplandi_baglanamadi":
            cozum.uyarilar.append(
                "Kalıtım kural katmanı çaprazlamayı hesapladı ama sonucu "
                "şıklarla eşleştiremedi (şıklar önerme listesi olabilir); "
                "cevap model yolundan geldi."
            )
        cozum.gorsel = baglam.gorsel_imza
        cozum.gorsel_turu = baglam.gorsel_turu
        cozum.gorsel_kullanildi = bool(baglam.gorsel_veri) and isinstance(
            self.motor, GorselMotor
        )
        if baglam.gorsel_kaniti is not None:
            cozum.gorsel_kanit_ozeti = baglam.gorsel_kaniti.ozet
            cozum.algilama_guveni = baglam.gorsel_kaniti.guven
        elif baglam.gorsel_imza:
            cozum.algilama_guveni = baglam.gorsel_karar_guveni
        if baglam.gorsel_imza and not baglam.gorsel_gerekli:
            cozum.dogrulama_durumu = "metin_yolu"
        elif cozum.gorsel_kullanildi and baglam.gorsel_kaniti is not None:
            cozum.dogrulama_durumu = "gorsel_kanitli"
        elif baglam.gorsel_gerekli:
            cozum.dogrulama_durumu = "gorsel_dogrulanamadi"
        # Modele gerçekten verilen pasajları çözümle birlikte sakla. Yalnız
        # kaynak adı/sayfa taşınır; uzun pasaj metnini her çözüm JSON'unda
        # çoğaltmak veritabanını gereksiz büyütürdü.
        cozum.kitap_kaynaklari = list(
            dict.fromkeys(pasaj.kaynak_adi() for pasaj in baglam.pasajlar)
        )
        # Görsel istendi ama modele ulaşmadıysa (dosya okunamadı ya da motor
        # görsel desteklemiyor) cevap eksik bilgiyle üretilmiştir. Sessiz
        # kalmak, kullanıcının şekle bakılarak çözüldüğünü sanmasına yol açar.
        if baglam.gorsel_imza and baglam.gorsel_gerekli and not baglam.gorsel_veri:
            cozum.uyarilar.append(
                "Soruya iliştirilen görsel okunamadı; cevap yalnız metne dayanıyor."
            )
            cozum.incele = True
        elif baglam.gorsel_veri and not isinstance(self.motor, GorselMotor):
            cozum.uyarilar.append(
                "Yüklü motor görsel okuyamıyor; şekildeki veri kullanılmadı. "
                "Görsel çıkarım için: BIYO_MOTOR=vlm"
            )
            cozum.incele = True
        elif baglam.gorsel_imza and not baglam.gorsel_gerekli:
            cozum.uyarilar.append(
                "Görüntüde eklenmiş soru kırpımı bulundu; metin ve şıklar tam "
                "olduğu için çözüm ince ayarlı metin motorunda yapıldı."
            )
        self._oz_kontrol(cozum, secenekler, baglam.kaynak_guveni)

        if baglam.kaydet:
            cozum.id = self.depo.cozum_kaydet(cozum)
            if self.ayarlar.onbellek_aktif and baglam.onbellek_kullanilabilir and not cozum.incele:
                self.depo.onbellek_yaz(
                    baglam.kimlik, cozum, baglam.sorgu_vektoru, baglam.baglam_imza
                )
        return cozum

    def coz(
        self,
        soru: str,
        *,
        secenekler: dict[str, str] | None = None,
        cevap_turu: str | None = None,
        kaydet: bool = True,
        haric_imzalar: set[str] | None = None,
        gorsel: str = "",
        kaynak_guveni: float = 0.0,
        gorsel_modu: str = VARSAYILAN_GORSEL_MODU,
    ) -> Cozum:
        baglam, onbellekten = self._hazirla(
            soru,
            secenekler,
            cevap_turu,
            kaydet,
            haric_imzalar,
            gorsel,
            kaynak_guveni,
            gorsel_modu,
        )
        if onbellekten is not None:
            return onbellekten

        biyobirikim_cozumu = self._biyobirikim_yolu(baglam)
        if biyobirikim_cozumu is not None:
            return self._sonlandir(baglam, biyobirikim_cozumu)

        # Soyağacında VLM'ye sonucu sordurmak yerine yalnız görsel olguları
        # okut, standart kalıtım kurallarını Python ile uygula. Katman yalnız
        # desteklediği dar soru tipinde ve tek şık bulduğunda konuşur.
        soyagaci_cozumu = self._soyagaci_yolu(baglam)
        if soyagaci_cozumu is not None:
            return self._sonlandir(baglam, soyagaci_cozumu)

        # Deterministik kalıtım yolu `_coklu_coz`den ÖNCE denenir: başarılı
        # olduğunda 3 üretim çağrısı yerine 1 çıkarım çağrısı harcanır, yani
        # kalıtım soruları hem daha doğru hem daha hızlı çözülür.
        if baglam.kalitim_adayi and self.motor is not None:
            arac_cozumu = self._kalitim_yolu(baglam)
            if arac_cozumu is not None:
                return self._sonlandir(baglam, arac_cozumu)

        if self.motor is None:
            cozum = self._motorsuz_cozum(
                baglam.soru, baglam.kanitlar, baglam.konu, baglam.tur, baglam.pasajlar
            )
        else:
            self._gorsel_kaniti_cikar(baglam)
            cozum = self._coklu_coz(
                baglam.soru,
                baglam.kanitlar,
                baglam.secenekler or None,
                baglam.konu,
                baglam.tur,
                cevap_turu=baglam.beklenen_tur,
                gorsel_veri=baglam.gorsel_veri,
                pasajlar=baglam.pasajlar,
                gorsel_kanit=baglam.gorsel_kaniti,
            )
        return self._sonlandir(baglam, cozum)

    def coz_akis(
        self,
        soru: str,
        *,
        secenekler: dict[str, str] | None = None,
        cevap_turu: str | None = None,
        kaydet: bool = True,
        haric_imzalar: set[str] | None = None,
        gorsel: str = "",
        kaynak_guveni: float = 0.0,
        gorsel_modu: str = VARSAYILAN_GORSEL_MODU,
    ) -> Iterator[tuple[str, object]]:
        """`coz()` ile aynı sonucu üretir, ama üretimi parça parça bildirir.

        Olaylar: ``("durum", mesaj)``, ``("parca", metin)``, ``("bitti", Cozum)``.
        Ayrıştırma ve kayıt `coz()` ile birebir aynı kodu (`_sonlandir`)
        kullanır — akış yalnız gösterim katmanıdır.
        """
        yield "durum", "hafızadan örnek getiriliyor"
        baglam, onbellekten = self._hazirla(
            soru,
            secenekler,
            cevap_turu,
            kaydet,
            haric_imzalar,
            gorsel,
            kaynak_guveni,
            gorsel_modu,
        )
        if onbellekten is not None:
            yield "durum", "önbellekten yanıtlandı"
            yield "bitti", onbellekten
            return

        biyobirikim_cozumu = self._biyobirikim_yolu(baglam)
        if biyobirikim_cozumu is not None:
            yield "durum", "toksik birikim kuralları denetleniyor"
            yield "bitti", self._sonlandir(baglam, biyobirikim_cozumu)
            return

        soyagaci_cozumu = self._soyagaci_yolu(baglam)
        if soyagaci_cozumu is not None:
            yield "durum", "soyağacı kuralları denetleniyor"
            yield "bitti", self._sonlandir(baglam, soyagaci_cozumu)
            return

        # `coz()` ile aynı deterministik yol; akış yalnız gösterim katmanı
        # olduğu için burada da denenmesi ŞART, yoksa aynı soru arayüzden
        # farklı cevaplanır.
        if baglam.kalitim_adayi and self.motor is not None:
            yield "durum", "çaprazlama hesaplanıyor"
            arac_cozumu = self._kalitim_yolu(baglam)
            if arac_cozumu is not None:
                yield "bitti", self._sonlandir(baglam, arac_cozumu)
                return

        if self.motor is None:
            cozum = self._motorsuz_cozum(
                baglam.soru, baglam.kanitlar, baglam.konu, baglam.tur, baglam.pasajlar
            )
            yield "bitti", self._sonlandir(baglam, cozum)
            return

        self._gorsel_kaniti_cikar(baglam)
        mesajlar = cozum_mesajlari(
            baglam.soru,
            baglam.kanitlar,
            secenekler=baglam.secenekler or None,
            cevap_turu=baglam.beklenen_tur,
            gorselli=self._gorsel_modele_gidiyor(baglam.gorsel_veri),
            kanit_azami_adim=self.ayarlar.kanit_azami_adim,
            pasajlar=baglam.pasajlar,
            gorsel_kanit=(
                baglam.gorsel_kaniti.istem_metni() if baglam.gorsel_kaniti else ""
            ),
        )
        yield "durum", "model yazıyor"
        parcalar: list[str] = []
        try:
            # Görselli üretim akış DEĞİL: mlx-vlm token akışı vermiyor.
            # Kullanıcı boşlukta kalmasın diye durum mesajı ayrıca veriliyor.
            gorsel_kurtarma = False
            if baglam.gorsel_veri and isinstance(self.motor, GorselMotor):
                yield "durum", "şekil okunuyor"
                ham_yanit, gorsel_kurtarma = self._gorsel_ham_uret(
                    mesajlar,
                    baglam.gorsel_veri,
                    soru=baglam.soru,
                    secenekler=baglam.secenekler or None,
                    cevap_turu=baglam.beklenen_tur,
                    sicaklik=self.ayarlar.sicaklik,
                )
                if gorsel_kurtarma:
                    yield "durum", "görsel yanıt kısa istemle kurtarıldı"
                parcalar.append(ham_yanit)
                yield "parca", ham_yanit
            else:
                for parca in akisa_dus(
                    self.motor,
                    mesajlar,
                    sicaklik=self.ayarlar.sicaklik,
                    azami_token=self.ayarlar.azami_token,
                ):
                    parcalar.append(parca)
                    yield "parca", parca
        except MotorHatasi as exc:
            cozum = self._motorsuz_cozum(
                baglam.soru, baglam.kanitlar, baglam.konu, baglam.tur, baglam.pasajlar
            )
            cozum.uyarilar.append(f"Model çalıştırılamadı: {exc}")
            yield "bitti", self._sonlandir(baglam, cozum)
            return

        yield "durum", "çözüm denetleniyor"
        cozum = self._yaniti_cozumle(
            "".join(parcalar), baglam.soru, baglam.kanitlar, baglam.konu, baglam.tur
        )
        if gorsel_kurtarma:
            self._gorsel_kurtarmayi_isaretle(cozum)
        if (
            baglam.gorsel_veri
            and baglam.secenekler
            and uyumluluk_sorusu_mu(baglam.soru, baglam.secenekler)
        ):
            self._soyagaci_model_yolunu_isaretle(cozum)
        yield "bitti", self._sonlandir(baglam, cozum)

    # --- üretim yolları ---

    def _gorsel_kaniti_cikar(self, baglam: _Baglam) -> GorselKaniti | None:
        """Görüntüyü çözmeden önce cevap içermeyen yapılandırılmış olgu çıkar."""
        if baglam.gorsel_kaniti is not None:
            return baglam.gorsel_kaniti
        if not baglam.gorsel_veri or not isinstance(self.motor, GorselMotor):
            return None
        gorsel_motor = getattr(self.motor, "gorsel", self.motor)
        kanit_uret = getattr(gorsel_motor, "gorsel_kaniti_uret", None)
        if not isinstance(gorsel_motor, GorselMotor) or not callable(kanit_uret):
            return None
        try:
            ham = kanit_uret(
                kanit_mesajlari(baglam.gorsel_turu or "uncertain"),  # type: ignore[arg-type]
                baglam.gorsel_veri,
                sicaklik=0.0,
                azami_token=700,
            )
        except MotorHatasi:
            baglam.gorsel_kaniti = GorselKaniti(
                tur=(baglam.gorsel_turu or "uncertain"),  # type: ignore[arg-type]
                okunamayanlar=["Görsel algılama modeli çalıştırılamadı."],
                guven=0.0,
            )
            return baglam.gorsel_kaniti
        baglam.gorsel_kaniti = kaniti_ayikla(
            ham, (baglam.gorsel_turu or "uncertain")  # type: ignore[arg-type]
        )
        return baglam.gorsel_kaniti

    @staticmethod
    def _biyobirikim_yolu(baglam: _Baglam) -> Cozum | None:
        """Dar toksik birikim sorusunu saf trofik sıralamayla çöz."""
        sonuc = biyobirikim_coz(baglam.soru, baglam.secenekler or None)
        if sonuc is None:
            return None
        return Cozum(
            soru=baglam.soru,
            adimlar=list(sonuc.adimlar),
            cevap=sonuc.cevap,
            guven=sonuc.guven,
            konu=baglam.konu or "ekoloji",
            cozum_turu="siniflandirma",
            cevap_turu=baglam.beklenen_tur or "coktan_secmeli",
            kanitlar=baglam.kanitlar,
            uyarilar=list(sonuc.uyarilar),
            incele=sonuc.incele,
            uretim_yontemi="biyobirikim_araci",
        )

    def _soyagaci_yolu(self, baglam: _Baglam) -> Cozum | None:
        """VLM gözlemi + saf kuralla dar soyağacı uyumluluk çözümü.

        Görsel okuma, kesin bir sensör değildir. Bu yüzden başarılı sonuç
        bile 0,65 güven tavanı ve zorunlu inceleme taşır; önbelleğe girmez.
        """
        if not baglam.gorsel_veri or not baglam.secenekler or not isinstance(
            self.motor, GorselMotor
        ):
            return None
        assert self.motor is not None  # noqa: S101 - protokol denetimi yukarıda
        # KarmaMotor genel sorularda VLM hatasını metin modeline düşürür.
        # Bu gözlem yolunda metin modeli sembolleri göremediği için o geri
        # çekilme kullanılamaz: varsa doğrudan alt görsel motoru çağırız.
        gorsel_motor = getattr(self.motor, "gorsel", self.motor)
        if not isinstance(gorsel_motor, GorselMotor):
            return None
        olasilik = olasilik_sorusu_mu(baglam.soru, baglam.secenekler)
        uyumluluk = uyumluluk_sorusu_mu(baglam.soru, baglam.secenekler)
        if not olasilik and not uyumluluk:
            return None
        try:
            if olasilik:
                ham = gorsel_motor.gorselle_uret(
                    graf_okuma_mesajlari(),
                    baglam.gorsel_veri,
                    sicaklik=0.0,
                    azami_token=900,
                )
                graf = grafi_ayikla(ham)
                sonuc = x_cekinik_olasilik_coz(
                    baglam.soru, baglam.secenekler, graf
                )
                if sonuc is not None:
                    baglam.gorsel_kaniti = GorselKaniti(
                        tur="pedigree",
                        ozet=f"{len(graf)} birey ve hedef çocuk yapılandırılmış graf olarak okundu.",
                        veriler=[
                            f"{b.kimlik}: {b.cinsiyet}, {b.durum}"
                            for b in graf
                            if not b.hedef
                        ],
                        iliskiler=[
                            f"{b.kimlik} ebeveynleri: {', '.join(b.ebeveynler)}"
                            for b in graf
                            if b.ebeveynler
                        ],
                        guven=0.75,
                    )
            else:
                ham = gorsel_motor.gorselle_uret(
                    aile_okuma_mesajlari(),
                    baglam.gorsel_veri,
                    sicaklik=0.0,
                    azami_token=120,
                )
                aile = aileyi_ayikla(ham)
                sonuc = (
                    uyumluluk_coz(baglam.soru, baglam.secenekler, aile)
                    if aile is not None
                    else None
                )
                if aile is not None and sonuc is not None:
                    baglam.gorsel_kaniti = GorselKaniti(
                        tur="pedigree",
                        ozet="Çekirdek aile cinsiyet ve hastalık durumları okundu.",
                        guven=0.75,
                    )
        except MotorHatasi:
            return None
        if sonuc is None:
            return None
        return Cozum(
            soru=baglam.soru,
            adimlar=list(sonuc.adimlar),
            cevap=sonuc.cevap,
            guven=0.65,
            konu=baglam.konu or "kalıtım",
            cozum_turu="kalitim_hesabi",
            cevap_turu=baglam.beklenen_tur or "coktan_secmeli",
            kanitlar=baglam.kanitlar,
            uyarilar=[
                "Soyağacındaki aile grafı görsel modelle okundu; sonuç "
                "standart kalıtım kuralları ve olasılık hesabıyla üretildi. Sembol okuması "
                "insan tarafından doğrulanmalıdır."
            ],
            incele=True,
            uretim_yontemi="soyagaci_araci",
            model=getattr(self.motor, "ad", ""),
            ham_yanit=ham[:1000],
        )

    def _kalitim_yolu(self, baglam: _Baglam) -> Cozum | None:
        """Deterministik kalıtım çözücüsü; çözemezse None (mevcut yol çalışır).

        Zincirin her halkası çekilebilir: çıkarım tanım üretemezse, hesap
        sonuç vermezse ya da sonuç tek bir şıkka oturmazsa `None` dönülür.
        Kendinden emin yanlış cevap, cevapsızlıktan zararlıdır.
        """
        if not baglam.secenekler:
            # Çözücü serbest cevap üretmiyor, şıklara çözüyor (bkz. eslestirme).
            return None
        tanim = caprazlama_cikar(self.motor, baglam.soru, baglam.secenekler)
        if tanim is None:
            return None
        sonuc = punnett_sorgula(tanim)
        if sonuc.bos_mu():
            return None
        harf, guven, uyarilar = sonuca_uyan_sik(sonuc, baglam.secenekler, soru=baglam.soru)
        if not harf:
            # Kural katmanı hesabı YAPTI ama şıkka bağlayamadı — neredeyse
            # her zaman şıklar önerme listesi olduğu için ("Yalnız I",
            # "I ve III"). Sessizce model yoluna düşmek bu boşluğu ölçümde
            # görünmez kılıyordu: `yontem_bazli` yalnız `model` gösteriyor,
            # kural katmanının denendiği hiçbir yerde yazmıyordu.
            baglam.kalitim_bagvurusu = "hesaplandi_baglanamadi"
            return None
        return Cozum(
            soru=baglam.soru,
            adimlar=kalitim_adimlari(tanim, sonuc),
            cevap=harf,
            guven=round(float(guven), 4),
            konu=baglam.konu,
            cozum_turu="kalitim_hesabi",
            cevap_turu=baglam.beklenen_tur or "coktan_secmeli",
            kanitlar=baglam.kanitlar,
            uyarilar=list(uyarilar),
            uretim_yontemi="kalitim_araci",
        )

    def _coklu_coz(
        self,
        soru: str,
        kanitlar: list[Kanit],
        secenekler: dict[str, str] | None,
        konu: str,
        tur: str,
        cevap_turu: str = "",
        gorsel_veri: bytes = b"",
        pasajlar: list | None = None,
        gorsel_kanit: GorselKaniti | None = None,
    ) -> Cozum:
        """Aynı soruyu N kez çözüp cevaplara göre oylar (self-consistency).

        Kazanan, en kalabalık cevap kümesi. Güven oy oranıyla çarpılır: bu,
        seçici doğruluğun aradığı sinyalin ta kendisi — modelin "0,9 eminim"
        demesi ucuz, üç bağımsız denemede aynı cevaba varması değil.
        """
        deneme = max(1, int(self.ayarlar.deneme_sayisi))
        if deneme == 1:
            return self._model_ile_coz(
                soru,
                kanitlar,
                secenekler,
                konu,
                tur,
                cevap_turu=cevap_turu,
                gorsel_veri=gorsel_veri,
                pasajlar=pasajlar,
                gorsel_kanit=gorsel_kanit,
            )

        adaylar: list[Cozum] = []
        for sira in range(deneme):
            # İlk deneme ayarlardaki sıcaklıkla: ölçümde bu 0'dır ve tek atışlı
            # koşuyla karşılaştırılabilir kalır. Çeşitlilik sonraki denemelerden
            # gelir.
            sicaklik = self.ayarlar.sicaklik if sira == 0 else self.ayarlar.deneme_sicakligi
            adaylar.append(
                self._model_ile_coz(
                    soru,
                    kanitlar,
                    secenekler,
                    konu,
                    tur,
                    cevap_turu=cevap_turu,
                    gorsel_veri=gorsel_veri,
                    sicaklik=sicaklik,
                    pasajlar=pasajlar,
                    gorsel_kanit=gorsel_kanit,
                )
            )

        return self.cozumleri_oyla(soru, adaylar)

    def cozumleri_oyla(self, soru: str, adaylar: list[Cozum]) -> Cozum:
        """Önceden üretilmiş bağımsız çözüm adaylarını cevaplarına göre oyla.

        Kes ve Çöz hattı, cevap anahtarı uyuşmazlığında ilk kör çözümü çöpe
        atmadan yalnız eksik adayları üretir. Anahtarın değeri bu metoda da
        verilmez; yalnız modelin ürettiği cevaplar kümelenir.
        """
        if not adaylar:
            raise ValueError("Oylanacak çözüm adayı yok.")

        # Model hiç çalışmadıysa (motor hatası / yalnız kural yolu) oylamanın
        # anlamı yok. ``kurtarma`` ve ``onbellek`` model kökenlidir; bunları
        # sırf etiketleri "model" değil diye oylama dışı bırakma.
        if all(a.uretim_yontemi not in MODEL_KOKENLI for a in adaylar):
            return adaylar[0]

        kumeler: list[list[Cozum]] = []
        for aday in adaylar:
            for kume in kumeler:
                if cevap_eslesiyor(aday.cevap, kume[0].cevap, soru=soru):
                    kume.append(aday)
                    break
            else:
                kumeler.append([aday])

        # Beraberlikte ilk (deterministik) denemenin kümesi kazanır: rastgele
        # seçim, aynı girdide farklı cevaplar üretip koşuları kıyaslanamaz
        # yapardı.
        en_cok = max(len(k) for k in kumeler)
        kazanan = next(k for k in kumeler if len(k) == en_cok)
        # Kazanan küme içinde en yüksek güvenli çözümü temsilci al; adımları en
        # gerekçeli olanı taşısın.
        cozum = max(kazanan, key=lambda c: c.guven)
        oy_orani = len(kazanan) / len(adaylar)
        cozum.guven = round(max(0.0, min(1.0, cozum.guven * oy_orani)), 4)
        # Kurtarma etiketinin üzerine yazma: "cevap modelin kendi metninden
        # çıkarıldı" bilgisi oylandığında da geçerli ve raporda ayrı okunmalı.
        if cozum.uretim_yontemi == "model":
            cozum.uretim_yontemi = "oylama"
        if oy_orani < 1.0:
            digerleri = sorted({k[0].cevap or "—" for k in kumeler if k is not kazanan})
            cozum.uyarilar.append(
                f"{len(adaylar)} denemeden {len(kazanan)}'i bu cevapta birleşti "
                f"(diğerleri: {', '.join(digerleri)})."
            )
        return cozum

    def _gorsel_ham_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel_veri: bytes,
        *,
        soru: str,
        secenekler: dict[str, str] | None,
        cevap_turu: str,
        sicaklik: float,
    ) -> tuple[str, bool]:
        """Tam VLM istemi boşsa few-shot'sız bir kez daha dene.

        ``bool`` ikinci, kısa istemin kullanıldığını bildirir. Çağıran
        bu sonucu düşük güven + zorunlu inceleme ile işaretler; kurtarma
        sessizce normal model yanıtına dönüşmez.
        """
        assert self.motor is not None and isinstance(self.motor, GorselMotor)  # noqa: S101
        ham = self.motor.gorselle_uret(
            mesajlar,
            gorsel_veri,
            sicaklik=sicaklik,
            azami_token=self.ayarlar.azami_token,
        )
        _dusunce, govde = dusunceyi_ayikla(ham)
        if govde.strip():
            return ham, False
        kisa = gorsel_kurtarma_mesajlari(soru, secenekler=secenekler, cevap_turu=cevap_turu)
        ikinci = self.motor.gorselle_uret(
            kisa,
            gorsel_veri,
            sicaklik=0.0,
            azami_token=min(800, max(256, int(self.ayarlar.azami_token))),
        )
        return ikinci, True

    def _gorsel_kurtarmayi_isaretle(self, cozum: Cozum) -> None:
        """Boş yanıttan sonraki ikinci VLM sonucunu güvenli alanda tut."""
        cozum.guven = min(cozum.guven, self.ayarlar.kurtarma_tavani)
        cozum.incele = True
        cozum.uyarilar.append(
            "Görsel model tam istemde görünür yanıt üretmedi; soru kısa "
            "bir istemle yeniden çözüldü. Cevap doğrulanmalıdır."
        )

    def _soyagaci_model_yolunu_isaretle(self, cozum: Cozum) -> None:
        """Kural katmanı doğrulayamadıysa serbest VLM cevabına güvenme."""
        cozum.guven = min(cozum.guven, self.ayarlar.kurtarma_tavani)
        cozum.incele = True
        cozum.uyarilar.append(
            "Soyağacındaki aile yapısı kural katmanınca tek anlamlı "
            "doğrulanamadı; model cevabı insan incelemesine bırakıldı."
        )

    def _model_ile_coz(
        self,
        soru: str,
        kanitlar: list[Kanit],
        secenekler: dict[str, str] | None,
        konu: str,
        tur: str,
        cevap_turu: str = "",
        gorsel_veri: bytes = b"",
        sicaklik: float | None = None,
        pasajlar: list | None = None,
        gorsel_kanit: GorselKaniti | None = None,
    ) -> Cozum:
        sicaklik = self.ayarlar.sicaklik if sicaklik is None else sicaklik
        mesajlar = cozum_mesajlari(
            soru,
            kanitlar,
            secenekler=secenekler,
            cevap_turu=cevap_turu,
            gorselli=self._gorsel_modele_gidiyor(gorsel_veri),
            kanit_azami_adim=self.ayarlar.kanit_azami_adim,
            pasajlar=pasajlar,
            gorsel_kanit=gorsel_kanit.istem_metni() if gorsel_kanit else "",
        )
        # Tür daraltma: çağıran yollar motorun varlığını zaten denetliyor.
        assert self.motor is not None  # noqa: S101
        try:
            gorsel_kurtarma = False
            if gorsel_veri and isinstance(self.motor, GorselMotor):
                ham, gorsel_kurtarma = self._gorsel_ham_uret(
                    mesajlar,
                    gorsel_veri,
                    soru=soru,
                    secenekler=secenekler,
                    cevap_turu=cevap_turu,
                    sicaklik=sicaklik,
                )
            else:
                ham = self.motor.uret(
                    mesajlar,
                    sicaklik=sicaklik,
                    azami_token=self.ayarlar.azami_token,
                )
        except MotorHatasi as exc:
            cozum = self._motorsuz_cozum(soru, kanitlar, konu, tur, pasajlar)
            cozum.uyarilar.append(f"Model çalıştırılamadı: {exc}")
            return cozum
        cozum = self._yaniti_cozumle(ham, soru, kanitlar, konu, tur)
        if not cozum.cevap.strip() and secenekler:
            self._cevabi_kurtar(cozum, ham, soru, secenekler)
        if gorsel_kurtarma:
            self._gorsel_kurtarmayi_isaretle(cozum)
        if gorsel_veri and secenekler and uyumluluk_sorusu_mu(soru, secenekler):
            self._soyagaci_model_yolunu_isaretle(cozum)
        return cozum

    def _cevabi_kurtar(
        self,
        cozum: Cozum,
        ham: str,
        soru: str,
        secenekler: dict[str, str],
    ) -> None:
        """Muhakeme üretilip cevap alanı boş kaldığında son bir kısa çağrı.

        Ölçümde 125 sorunun 29'unda (%23) model sayfalarca çözüm yazıp `cevap`
        alanını hiç doldurmadı — muhakeme vardı, sonuç yoktu. Bu çağrı yeniden
        çözmez, modelin KENDİ metnini önüne koyup yalnız şık harfini ister;
        bu yüzden ucuzdur (birkaç token) ve yalnız bu %23'te çalışır.

        Kurtarılan cevap DÜŞÜK güvenle işaretlenir. Sebebi seçici doğruluk:
        boş cevap zaten incelemeye düşüyordu, yani zararsızdı. Kurtarılanı
        yüksek güvenle geri koymak kapsamayı şişirip doğruluğu bozardı —
        öğrenci bir cevap görsün ama sistem ona "eminim" demesin.
        """
        if self.motor is None:
            return
        _dusunce, govde = dusunceyi_ayikla(ham)
        if not govde.strip():
            return
        harfler = "/".join(sorted(h.upper() for h in secenekler))
        istek = [
            {
                "role": "system",
                "content": (
                    "Aşağıda bir biyoloji sorusuna ait yarım kalmış çözüm var. "
                    f"Bu çözümün vardığı sonucu tek bir şık harfi ({harfler}) "
                    "olarak yaz. Yalnız harfi yaz, başka hiçbir şey yazma. "
                    "Çözüm bir sonuca varmıyorsa yalnız '-' yaz."
                ),
            },
            {"role": "user", "content": f"SORU:\n{soru}\n\nYARIM ÇÖZÜM:\n{govde[-2500:]}"},
        ]
        try:
            yanit = self.motor.uret(istek, sicaklik=0.0, azami_token=8)
        except MotorHatasi as exc:
            cozum.uyarilar.append(f"Cevap kurtarma çağrısı başarısız: {exc}")
            return
        harf = sik_harfi(yanit, secenekler, soru=soru)
        if not harf:
            return
        cozum.cevap = harf
        cozum.guven = min(cozum.guven, self.ayarlar.kurtarma_tavani)
        cozum.incele = True
        # Koşu raporunda ayrışsın: kurtarılan cevapların doğruluğu, modelin
        # doğrudan verdiği cevaplardan ayrı okunmazsa ikisi birbirini maskeler.
        cozum.uretim_yontemi = "kurtarma"
        cozum.uyarilar.append(
            "Model cevap alanını boş bıraktı; cevap kendi çözüm metninden "
            "kurtarıldı — doğrulanması gerekir."
        )

    def _yaniti_cozumle(
        self,
        ham: str,
        soru: str,
        kanitlar: list[Kanit],
        konu: str,
        tur: str,
    ) -> Cozum:
        """Ham model metnini `Cozum`'a çevirir (akışlı ve akışsız yol ortak)."""
        dusunce, _govde = dusunceyi_ayikla(ham)
        try:
            veri = json_ayikla(ham)
        except ValueError:
            return self._bicimsiz_yaniti_kurtar(ham, soru, kanitlar, konu, tur, dusunce)

        # Model "adimlar" yerine tek bir dize döndürebiliyor; üzerinde doğrudan
        # dönmek çözümü harf harf "adım"lara böler. Dize gelirse satırlara ayır.
        ham_adimlar = veri.get("adimlar") or []
        if isinstance(ham_adimlar, str):
            from .istemler import cozumu_adimlara_bol

            ham_adimlar = cozumu_adimlara_bol(ham_adimlar)
        elif not isinstance(ham_adimlar, list):
            ham_adimlar = []
        adimlar = [str(a).strip() for a in ham_adimlar if str(a).strip()]
        uyari = str(veri.get("uyari", "")).strip()
        try:
            guven = float(veri.get("guven", 0.0))
        except (TypeError, ValueError):
            guven = 0.0
        # Onarılmış yanıt, modelin şemayı bozduğu yanıttır: kurtarılan alanlar
        # gerçek ama yanıtın bütünlüğü kanıtlanmış değil. Güven tavanı olmadan
        # bu çözümler tam güvenle geçer ve seçici doğruluğu bozardı.
        if veri.get("_onarildi"):
            tavan = self.ayarlar.onarim_tavani
            guven = min(guven or tavan, tavan)

        uyarilar = [uyari] if uyari else []
        cevap = str(veri.get("cevap", "")).strip()
        on_cevap = str(veri.get("on_cevap", "")).strip()
        yontem = "model"
        if not cevap and on_cevap:
            # Asıl kazanç burada: eskiden bu yanıt cevapsız sayılıp incelemeye
            # düşüyordu; artık modelin beyan ettiği ilk kanaat kurtarılıyor.
            cevap = on_cevap
            yontem = "on_cevap"
            tavan = self.ayarlar.on_cevap_tavani
            guven = min(guven or tavan, tavan)
            uyarilar.append("Nihai cevap alanı gelmedi; ön cevap kullanıldı (muhakeme yarım).")
        elif cevap and on_cevap and not cevap_eslesiyor(cevap, on_cevap, soru=soru):
            guven *= ON_CEVAP_CELISKI_CARPANI
            uyarilar.append(f"Model ön cevabını değiştirdi ({on_cevap} → {cevap}).")
        return Cozum(
            soru=soru,
            adimlar=adimlar,
            cevap=cevap,
            guven=max(0.0, min(1.0, guven)),
            kanitlar=kanitlar,
            uyarilar=uyarilar,
            uretim_yontemi=yontem,
            model=getattr(self.motor, "ad", ""),
            konu=str(veri.get("konu", "")).strip() or konu,
            cozum_turu=cozum_turu_dogrula(str(veri.get("cozum_turu", "")) or tur),
            ham_yanit=(dusunce or "")[:6000],
        )

    def _bicimsiz_yaniti_kurtar(
        self,
        ham: str,
        soru: str,
        kanitlar: list[Kanit],
        konu: str,
        tur: str,
        dusunce: str,
    ) -> Cozum:
        """Model JSON üretemediğinde elde kalanı değerlendirir.

        Yarım kalmış JSON'u satır satır "adım" diye göstermek kullanıcıya
        çöp sunmak olur; bu yüzden yalnız JSON'a hiç benzemeyen düz metin
        adımlara bölünür, kesilmiş üretim ayrıca işaretlenir.
        """
        _dusunce, govde = dusunceyi_ayikla(ham)
        govde = govde.strip()
        uyarilar = ["Model JSON biçiminde yanıt vermedi."]
        adimlar: list[str] = []

        yarim_json = govde.startswith("{") or govde.startswith("```")
        if yarim_json:
            uyarilar.append(
                "Yanıt JSON gibi başlayıp tamamlanmamış — üretim büyük olasılıkla "
                "token sınırında kesildi. Ayarlar.azami_token değerini artırın ya da "
                "BIYO_DUSUNME=0 ile düşünme modunu kapatın."
            )
        elif govde:
            adimlar = [s.strip() for s in govde.splitlines() if s.strip()][:12]
        else:
            uyarilar.append(
                "Model yalnız düşünce üretti, görünür yanıt yok — token bütçesi yetmedi."
            )

        return Cozum(
            soru=soru,
            adimlar=adimlar,
            cevap="",
            guven=self.ayarlar.bicimsiz_tavani,
            kanitlar=kanitlar,
            uyarilar=uyarilar,
            incele=True,
            # "model" DEĞİL: bu yol modelin ürettiği geçerli bir çözüm değil,
            # şema bozulduktan sonra elde kalanı toplama işlemi. Ölçüm
            # kırılımında ikisi aynı kovaya düşerse, model yolunun gerçek
            # doğruluğu bu yolun sıfırlarıyla seyreltilip okunamaz hale gelir.
            uretim_yontemi="bicimsiz",
            model=getattr(self.motor, "ad", ""),
            konu=konu,
            cozum_turu=tur,
            ham_yanit=(dusunce or ham)[:6000],
        )

    def _motorsuz_cozum(
        self,
        soru: str,
        kanitlar: list[Kanit],
        konu: str,
        tur: str,
        pasajlar: list | None = None,
    ) -> Cozum:
        """Model yokken en benzer referans çözümü göstererek çalışmaya devam et.

        Bu bir çözüm ÜRETİMİ değildir; kullanıcıya en yakın çözülmüş örneği
        sunar ve her zaman incelemeye düşer.
        """
        if pasajlar:
            return Cozum(
                soru=soru,
                adimlar=[],
                guven=0.0,
                kanitlar=kanitlar,
                uyarilar=[
                    "İlgili ders kitabı pasajları bulundu; ancak model çalışmadığı için "
                    "kitaptaki olgular yeni soruya güvenle uyarlanamadı."
                ],
                incele=True,
                uretim_yontemi="kitap_rag_uyari",
                konu=konu,
                cozum_turu=tur,
            )
        if not kanitlar:
            return Cozum(
                soru=soru,
                adimlar=[],
                guven=0.0,
                uyarilar=["Model yok ve hafızada benzer örnek bulunamadı."],
                incele=True,
                uretim_yontemi="ragsiz",
                konu=konu,
                cozum_turu=tur,
            )
        en_yakin = kanitlar[0]
        from .istemler import cozumu_adimlara_bol

        return Cozum(
            soru=soru,
            adimlar=cozumu_adimlara_bol(en_yakin.cozum),
            cevap=en_yakin.cevap,
            guven=0.25,
            kanitlar=kanitlar,
            uyarilar=[
                "Model çalıştırılmadı; en benzer referans çözüm gösteriliyor. "
                "Bu çözüm yeni soruya uyarlanmamıştır."
            ],
            incele=True,
            uretim_yontemi="yerel_rag",
            konu=konu or en_yakin.konu,
            cozum_turu=en_yakin.cozum_turu or tur,
        )

    # --- öz-kontrol ---

    @staticmethod
    def _cevap_bicimini_denetle(cozum: Cozum, secenekler: dict[str, str] | None) -> None:
        """Cevabı türüne göre doğrular ve mümkünse kanonik biçime çeker.

        Her tür ayrı ele alınır: eskiden yalnız çoktan seçmeli denetleniyor,
        boşluk doldurma/eşleştirme/sıralama/doğru-yanlış cevapları hiç
        sınanmadan geçiyordu — model paragraf döndürse bile "cevap var" sayılıp
        tam güvenle onaya çıkıyordu.
        """
        ham = (cozum.cevap or "").strip()
        if not ham:
            return
        tur = cozum.cevap_turu

        if tur == "coktan_secmeli" and secenekler:
            harf = sik_harfi(ham, secenekler, soru=cozum.soru)
            if not harf:
                cozum.uyarilar.append(f"Cevap ({cozum.cevap!r}) verilen şıklarla eşleşmiyor.")
                cozum.guven = min(cozum.guven, 0.3)
            else:
                cozum.cevap = harf

        elif tur == "dogru_yanlis":
            # `esitle` ğ/ş'yi korur, yalnız "ı"yı "i" yapar: "Yanlış" → "yanliş".
            alcak = esitle(ham).strip(".() ")
            if alcak in {"d", "doğru", "true", "evet"}:
                cozum.cevap = "Doğru"
            elif alcak in {"y", "yanliş", "false", "hayir"}:
                cozum.cevap = "Yanlış"
            else:
                cozum.uyarilar.append(f"Cevap ({cozum.cevap!r}) 'Doğru' ya da 'Yanlış' değil.")
                cozum.guven = min(cozum.guven, 0.35)

        elif tur == "bosluk_doldurma":
            beklenen = bosluk_sayisi(cozum.soru)
            verilen = [p.strip() for p in re.split(r"[,;]| - ", ham) if p.strip()]
            if beklenen and len(verilen) != beklenen:
                cozum.uyarilar.append(
                    f"Soruda {beklenen} boşluk var ama {len(verilen)} cevap verildi."
                )
                cozum.guven = min(cozum.guven, 0.4)
            cozum.cevap = ", ".join(verilen) if verilen else ham

        elif tur == "eslestirme":
            ciftler = re.findall(r"([IVX]{1,4}|\d{1,2})\s*[-–:/]\s*([a-eA-E])", ham)
            if not ciftler:
                cozum.uyarilar.append('Cevap eşleştirme çifti biçiminde değil (ör. "I-c, II-a").')
                cozum.guven = min(cozum.guven, 0.35)
            else:
                cozum.cevap = ", ".join(f"{sol.upper()}-{sag.lower()}" for sol, sag in ciftler)

        elif tur == "siralama":
            ogeler = [p.strip() for p in re.split(r"[,;>→-]", ham) if p.strip()]
            if len(ogeler) < 2:
                cozum.uyarilar.append('Sıralama cevabı en az iki öğe içermeli (ör. "III, I, II").')
                cozum.guven = min(cozum.guven, 0.35)
            else:
                cozum.cevap = ", ".join(ogeler)

        elif tur == "kisa_cevap" and len(ham.split()) > 12:
            # Kısa cevap sorusuna paragraf dönmesi, modelin biçim talimatını
            # yok saydığını gösterir; cevabı otomatik denetlemek imkânsızlaşır.
            cozum.uyarilar.append("Kısa cevap beklenirken uzun bir açıklama döndü.")
            cozum.guven = min(cozum.guven, 0.5)

    @staticmethod
    def _kaynak_tavanini_uygula(cozum: Cozum, kaynak_guveni: float) -> None:
        """Çözüm güvenini sorunun kaynak güvenilirliğiyle sınırlar.

        Soru bir kesme/OCR hattından geldiyse çözüm kaynağından daha
        güvenilir olamaz: yarım kesilmiş bir metni ya da kayık bir şık
        listesini model yine de kendinden emin biçimde cevaplayabiliyor.
        Zincirin en zayıf halkası tavanı belirler — çarpım değil tavan:
        kaynak %80 güvenilirse sonuç en fazla %80 güvenilirdir.

        0 veya negatif "kaynak güveni bilinmiyor" demektir (arşivde
        `kalibre_guven` alanı yoksa varsayılan budur) ve tavan uygulanmaz;
        aksi hâlde puanlanmamış tek bir arşiv bütün cevapları susturur.

        Ayrı bir metot olması şart: `_oz_kontrol` çözüm yollarının yalnız
        bir kısmından geçiyor. Önbellek isabeti ve birebir arşiv kaydı
        `_hazirla` içinde erken dönüyor ve oraya hiç uğramıyor — tavan
        yalnız `_oz_kontrol` içinde kalsaydı, aynı soru önbellekten
        geldiğinde kesme kalitesi sessizce yok sayılırdı.
        """
        if kaynak_guveni <= 0:
            return
        if cozum.guven > kaynak_guveni:
            cozum.uyarilar.append(
                f"Soru {kaynak_guveni:.0%} güvenle kesilmiş; çözüm güveni kaynağıyla sınırlandı."
            )
        cozum.guven = min(cozum.guven, kaynak_guveni)

    def _oz_kontrol(
        self,
        cozum: Cozum,
        secenekler: dict[str, str] | None,
        kaynak_guveni: float = 0.0,
    ) -> None:
        """Üretilen çözümün iç tutarlılığını denetler ve güveni düzeltir."""
        self._kaynak_tavanini_uygula(cozum, kaynak_guveni)

        if not cozum.adimlar:
            cozum.uyarilar.append("Çözüm adımı üretilmedi.")
            cozum.guven = min(cozum.guven, 0.2)

        if not cozum.cevap:
            cozum.uyarilar.append("Nihai cevap boş.")
            cozum.guven = min(cozum.guven, 0.3)

        self._cevap_bicimini_denetle(cozum, secenekler)

        # Deterministik araç yolu kanıt/tür kalibrasyonundan MUAF. Üç cezanın
        # üçü de modelin muhakemesine olan güvensizliği ölçüyor; burada
        # muhakeme yapan model değil, saf Python hesabı.
        #
        # Muafiyet olmasaydı: diskteki tabloda `kalitim_hesabi` çarpanı 0,442
        # ve 0,95 güvenli DOĞRU bir cevap 0,42'ye inip `inceleme_esigi`nin
        # (0,70) altında kalırdı. Doğruluk artar, kapsama çöker, kullanıcı
        # hiçbir fark görmez — kazanılan her cevap incelemeye düşerdi.
        arac_yolu = cozum.uretim_yontemi in _ARAC_YOLLARI
        if not arac_yolu:
            # Küme denetimi (yalnız == "model" değil): şeması bozulmuş bir
            # üretim de modelin kendi bilgisine dayanıyor ve kanıtsızsa aynı
            # cezayı hak ediyor. Tek etikete bakmak, `on_cevap`/`bicimsiz`
            # yollarını cezadan sessizce muaf tutuyordu.
            if not cozum.kanitlar and cozum.uretim_yontemi in MODEL_KOKENLI - {
                "onbellek",
                "oylama",
            }:
                cozum.uyarilar.append(
                    "Hafızada benzer referans örnek yoktu; çözüm yalnız modelin "
                    "kendi bilgisine dayanıyor."
                )
                cozum.guven = max(0.0, cozum.guven - self.ayarlar.kanitsiz_ceza)
            elif cozum.kanitlar:
                cozum.guven = self._kanit_kalibrasyonu(cozum)

            # Tür güvenilirliği kanıttan BAĞIMSIZ uygulanır: sistemin bir
            # muhakeme türündeki zayıflığı, o soruda referans bulunup
            # bulunmamasıyla ilgili değil. Kanıtsız dalda atlanırsa tam da en
            # kırılgan durumda (hafızada örnek yokken) fren devre dışı kalırdı.
            cozum.guven = self._tur_kalibrasyonu(cozum)

        if self.ayarlar.oz_kontrol and self.motor is not None and cozum.adimlar and not arac_yolu:
            self._model_oz_kontrolu(cozum, secenekler)

        cozum.incele = cozum.incele or cozum.guven < self.ayarlar.inceleme_esigi

    def _kanit_kalibrasyonu(self, cozum: Cozum) -> float:
        """Erişim sinyallerini güvene katar.

        Modelin kendi bildirdiği güven kalibre DEĞİL: ölçümde eşik 0,20'den
        0,90'a çıkarıldığında kapsama ve doğruluk hiç değişmedi, çünkü model
        neredeyse her çözüme 0,90 veriyor. Oysa erişim katmanı iki gerçek
        sinyal üretiyor ve ikisi de kullanılmıyordu:

        - `Kanit.skor`: hedef soruyla kanıt arasındaki benzerlik. "0,43
          benzerlikte 3 kanıt" ile "0,95 benzerlikte 3 kanıt" arasındaki fark
          güvene hiç yansımıyordu.
        - `Kanit.tur_uyumlu`: kanıtın muhakeme yapısı soruyla eşleşiyor mu.
          Eskiden yalnız "hiçbiri uymuyorsa" sabit ceza vardı; kaç tanesinin
          uyduğu bilgisi atılıyordu.

        Ceza çarpımsal: zayıf kanıt güveni oranla düşürür, güçlü kanıt olduğu
        gibi bırakır. Böylece iyi çalışan durumlar cezalandırılmaz.
        """
        en_iyi = max((k.skor for k in cozum.kanitlar), default=0.0)
        uyumlu = sum(1 for k in cozum.kanitlar if k.tur_uyumlu)

        carpan = 1.0
        if en_iyi < self.ayarlar.zayif_kanit_esigi:
            # Doğrusal azalma: eşiğin yarısındaki benzerlik güveni yarıya indirir.
            carpan *= max(0.35, en_iyi / self.ayarlar.zayif_kanit_esigi)
            cozum.uyarilar.append(
                f"En yakın referans örnek zayıf (benzerlik {en_iyi:.2f}); "
                "çözüm büyük ölçüde modelin kendi bilgisine dayanıyor."
            )
        if not uyumlu:
            carpan *= 1.0 - self.ayarlar.tur_uyumsuzluk_cezasi
        elif uyumlu < len(cozum.kanitlar):
            # Kısmi uyum: kademeli, çünkü 1/3 ile 3/3 aynı değil.
            carpan *= 1.0 - self.ayarlar.tur_uyumsuzluk_cezasi * (
                1.0 - uyumlu / len(cozum.kanitlar)
            )

        return max(0.0, min(1.0, cozum.guven * carpan))

    def _tur_kalibrasyonu(self, cozum: Cozum) -> float:
        """Çözüm türünün ölçülmüş güvenilirliğini güvene taşır.

        Model, zayıf olduğu türde de 0,9 güven bildiriyor (kalıtım hesabında
        3/17 doğru, güvenler 0,9 bandında). Tablo `kalibre` komutuyla DOĞRULAMA
        diliminden öğrenilir; boşken bu katman etkisizdir.
        """
        carpan = self.ayarlar.tur_guvenilirligi.get(cozum.cozum_turu)
        if carpan is None or carpan >= 1.0:
            return cozum.guven
        cozum.uyarilar.append(
            f"Bu soru türünde ({cozum.cozum_turu}) sistemin ölçülmüş başarısı "
            "düşük; güven buna göre indirildi."
        )
        return max(0.0, min(1.0, cozum.guven * carpan))

    def _model_oz_kontrolu(self, cozum: Cozum, secenekler: dict[str, str] | None) -> None:
        """İkinci bir model geçişiyle çözümü denetler ve gerekirse cevabı DÜZELTİR.

        Düzeltmenin uygulanması bilinçli: eskiden `duzeltilmis_cevap` yalnız
        uyarıya yazılıyordu, yani ikinci model çağrısının maliyeti ödenip
        faydası alınmıyordu. Düzeltme ancak geçerli bir şıkka çözülüyorsa
        uygulanır; her durumda güven düşürülüp çözüm incelemeye çıkar, çünkü
        iki geçişin çeliştiği bir soru insan gözü hak eder.
        """
        # Tür daraltma: çağıran yollar motorun varlığını zaten denetliyor.
        assert self.motor is not None  # noqa: S101
        try:
            ham = self.motor.uret(
                oz_kontrol_mesajlari(cozum.soru, cozum.metin(), cozum.cevap),
                sicaklik=0.0,
                azami_token=512,
            )
            veri = json_ayikla(ham)
        except (MotorHatasi, ValueError) as exc:
            cozum.uyarilar.append(f"Öz-kontrol yapılamadı: {exc}")
            return
        if not bool(veri.get("tutarli", True)):
            gerekce = str(veri.get("gerekce", "")).strip() or "belirtilmedi"
            cozum.uyarilar.append(f"Öz-kontrol tutarsızlık bildirdi: {gerekce}")
            cozum.guven = min(cozum.guven, 0.4)
            duzeltme = str(veri.get("duzeltilmis_cevap", "")).strip()
            if duzeltme and duzeltme != cozum.cevap:
                # Düzeltme YALNIZ doğrulanabilir olduğunda uygulanır: çoktan
                # seçmelide öneri bir şıkka çözülüyorsa. Açık uçlu cevapta
                # "düzeltilmiş cevap" serbest metindir ve sınanamaz; onu sessizce
                # uygulamak ikinci geçişin hatasını birincinin üstüne yazardı.
                yeni_cevap = (
                    sik_harfi(duzeltme, secenekler, soru=cozum.soru)
                    if cozum.cevap_turu == "coktan_secmeli" and secenekler
                    else ""
                )
                if yeni_cevap and yeni_cevap != cozum.cevap:
                    cozum.uyarilar.append(
                        f"Öz-kontrol cevabı {cozum.cevap!r} → {yeni_cevap!r} olarak düzeltti."
                    )
                    cozum.cevap = yeni_cevap
                else:
                    cozum.uyarilar.append(f"Öz-kontrol önerisi: {duzeltme}")


# `tek_harf`, `sik_harfi` ve `cevap_eslesiyor` `cevap` modülüne taşındı ve
# buradan yeniden dışa veriliyor: kalıtım çözücüsü ve kanıt kalite kapısı
# bunlara muhtaç ama `cozucu`'ya import edemezler (döngü). Mevcut çağıranlar
# (`degerlendirme`, testler) değişmeden çalışsın diye ad burada kalıyor.
