"""Üretilen çözümü referans çözümle karşılaştırma ve kör değerlendirme koşusu.

Kör değerlendirme (`kor_kosu`) her test örneğini hafızadan DIŞLAYARAK çözer.
Bu olmadan sistem kendi cevabını örnek olarak getirir ve doğruluk yapay şekilde
%100 çıkar — ölçümün tek anlamlı biçimi budur.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean

from .cozucu import Cozucu, cevap_eslesiyor
from .gomme import Gomlemci, kosinus
from .gorsel_zeka import VARSAYILAN_GORSEL_MODU
from .metin import imza as metin_imzasi
from .metin import sadelestir
from .modeller import Cozum, Ornek


@dataclass
class OrnekSonucu:
    ornek_id: int | None
    soru: str
    beklenen_cevap: str
    uretilen_cevap: str
    cevap_dogru: bool
    adim_ortusmesi: float
    guven: float
    incele: bool
    cozum_turu: str
    getirilen_turler: list[str] = field(default_factory=list)
    uretim_yontemi: str = "model"
    # Modelin KENDİ tür tahmini. `cozum_turu` referanstan gelir (rapor doğru
    # türe göre okunmalı), ama kalibrasyon çarpanı çıkarım anında yalnız bu
    # alana bakabilir — tablo da bununla öğrenilmeli, yoksa etiketleyicinin
    # yanıldığı sorularda yanlış türün çarpanı uygulanır.
    uretilen_turu: str = ""


@dataclass
class KosuOzeti:
    toplam: int
    dogru: int
    dogruluk: float
    ortalama_ortusme: float
    ortalama_guven: float
    inceleme_orani: float
    tur_bazli: dict[str, dict[str, float]]
    sonuclar: list[OrnekSonucu]

    def secici(self, esik: float) -> tuple[float, float]:
        """Verilen güven eşiğinde (kapsama, o kümedeki doğruluk).

        Hedef "cevapladığı sorularda %95 doğruluk" olduğunda tek başına
        doğruluk yanıltıcı: kapsamayı düşürerek seçici doğruluğu şişirmek
        kolaydır. İkisi hep birlikte okunmalı.
        """
        cevaplanan = [s for s in self.sonuclar if s.guven >= esik]
        if not self.sonuclar:
            return 0.0, 0.0
        kapsama = len(cevaplanan) / len(self.sonuclar)
        if not cevaplanan:
            return 0.0, 0.0
        dogruluk = sum(1 for s in cevaplanan if s.cevap_dogru) / len(cevaplanan)
        return kapsama, dogruluk

    def risk_kapsama(self, adim: float = 0.05) -> list[tuple[float, float, float]]:
        """(eşik, kapsama, seçici doğruluk) üçlüleri — hedef eşiği bundan okunur."""
        egri = []
        esik = 0.0
        while esik <= 1.0 + 1e-9:
            kapsama, dogruluk = self.secici(esik)
            egri.append((round(esik, 2), round(kapsama, 4), round(dogruluk, 4)))
            esik += adim
        return egri

    def hedef_esigi(self, hedef: float = 0.95) -> tuple[float, float, float] | None:
        """Hedef seçici doğruluğu sağlayan EN DÜŞÜK eşik (yani en yüksek kapsama)."""
        uygun = [u for u in self.risk_kapsama() if u[2] >= hedef and u[1] > 0]
        return max(uygun, key=lambda u: u[1]) if uygun else None

    def yontem_bazli(self, esik: float = 0.70) -> dict[str, dict[str, float]]:
        """Üretim yolu başına doğruluk, güven ve eşiğin üstüne çıkabilme oranı.

        Yalnız hangi yoldan kaç soru geçtiğini bilmek yetmiyor: kurtarma
        yollarının güveni 0,2-0,5 tavanlarına SABİTLENMİŞ durumda, yani
        cevap doğru olsa bile eşiğin altında kalıp kapsamaya katkı vermiyor.
        Tavanın haklı olup olmadığı ancak "bu yoldan gelen cevapların gerçek
        doğruluğu" ölçülerek anlaşılır — `dogruluk` yüksek ama `esik_ustu`
        sıfırsa tavan doğru cevapları boğuyor demektir.
        """
        kirilim: dict[str, dict[str, float]] = {}
        for yontem in sorted({s.uretim_yontemi for s in self.sonuclar}):
            kume = [s for s in self.sonuclar if s.uretim_yontemi == yontem]
            if not kume:
                continue
            esik_ustu = [s for s in kume if s.guven >= esik]
            kirilim[yontem] = {
                "adet": float(len(kume)),
                "dogru": float(sum(1 for s in kume if s.cevap_dogru)),
                "dogruluk": round(
                    sum(1 for s in kume if s.cevap_dogru) / len(kume), 4
                ),
                "ortalama_guven": round(mean(s.guven for s in kume), 4),
                "esik_ustu": float(len(esik_ustu)),
                # Eşiği geçenlerin doğruluğu: tavanı gevşetmenin kapsamaya
                # ne katacağını bu iki sayı birlikte söyler.
                "esik_ustu_dogruluk": round(
                    sum(1 for s in esik_ustu if s.cevap_dogru) / len(esik_ustu), 4
                ) if esik_ustu else 0.0,
            }
        return kirilim

    def rapor(self, esik: float | None = None) -> str:
        satirlar = [
            f"Örnek: {self.toplam} · Doğru: {self.dogru} · "
            f"Doğruluk: {self.dogruluk:.1%}",
            f"Adım örtüşmesi: {self.ortalama_ortusme:.2f} · "
            f"Ortalama güven: {self.ortalama_guven:.2f} · "
            f"İncelemeye düşen: {self.inceleme_orani:.1%}",
        ]
        if esik is not None:
            kapsama, secici_dogruluk = self.secici(esik)
            satirlar.append(
                f"Eşik {esik:.2f} · kapsama {kapsama:.1%} "
                f"({round(kapsama * self.toplam)}/{self.toplam}) · "
                f"cevaplananda doğruluk {secici_dogruluk:.1%}"
            )
        hedef = self.hedef_esigi()
        if hedef:
            satirlar.append(
                f"%95 seçici doğruluk için eşik {hedef[0]:.2f} → kapsama {hedef[1]:.1%}"
            )
        else:
            satirlar.append(
                "%95 seçici doğruluğu hiçbir eşikte sağlanmıyor "
                "(güven kalibrasyonu gerekiyor)."
            )
        if self.tur_bazli:
            satirlar.append("Çözüm türü bazında doğruluk:")
            for tur, veri in sorted(
                self.tur_bazli.items(), key=lambda x: -x[1]["adet"]
            ):
                satirlar.append(
                    f"  {tur:22s} {veri['dogruluk']:.0%}  ({int(veri['adet'])} örnek)"
                )
        yontem = self.yontem_bazli(esik if esik is not None else 0.70)
        if yontem:
            satirlar.append("Üretim yolu bazında (doğruluk · ort. güven · eşiği geçen):")
            for ad, veri in sorted(yontem.items(), key=lambda x: -x[1]["adet"]):
                satirlar.append(
                    f"  {ad:22s} {veri['dogruluk']:>4.0%} · {veri['ortalama_guven']:.2f} · "
                    f"{int(veri['esik_ustu'])}/{int(veri['adet'])}"
                )
        return "\n".join(satirlar)


def _sozcuk_ortusmesi(uretilen: str, beklenen: str) -> float:
    """0-1 arası sözcüksel örtüşme (token Jaccard + karakter benzerliği ortalaması)."""
    from rapidfuzz import fuzz

    u_set = set(sadelestir(uretilen).split())
    b_set = set(sadelestir(beklenen).split())
    if not u_set or not b_set:
        return 0.0
    jaccard = len(u_set & b_set) / len(u_set | b_set)
    karakter = fuzz.token_set_ratio(sadelestir(uretilen), sadelestir(beklenen)) / 100.0
    return round((jaccard + karakter) / 2, 4)


def cozum_puanla(
    uretilen: Cozum, referans: Ornek, gomlemci: Gomlemci | None = None
) -> OrnekSonucu:
    """Tek bir üretilen çözümü referansla karşılaştırır."""
    uretilen_metin = " ".join(uretilen.adimlar)
    ortusme = _sozcuk_ortusmesi(uretilen_metin, referans.cozum)
    if gomlemci is not None and uretilen_metin.strip() and referans.cozum.strip():
        vektorler = gomlemci.gom([uretilen_metin, referans.cozum])
        anlamsal = float(kosinus(vektorler[:1], vektorler[1:])[0][0])
        # Sözcüksel ve anlamsal kanıtı birleştir: biri düşük diğeri yüksekse
        # ortalamaları gerçek durumu tek başına her ikisinden daha iyi anlatıyor.
        ortusme = round((ortusme + max(0.0, anlamsal)) / 2, 4)

    return OrnekSonucu(
        ornek_id=referans.id,
        soru=referans.soru,
        beklenen_cevap=referans.cevap,
        uretilen_cevap=uretilen.cevap,
        cevap_dogru=cevap_eslesiyor(uretilen.cevap, referans.cevap, soru=referans.soru),
        adim_ortusmesi=ortusme,
        guven=round(float(uretilen.guven), 3),
        incele=bool(uretilen.incele),
        cozum_turu=referans.cozum_turu,
        getirilen_turler=[k.cozum_turu for k in uretilen.kanitlar],
        uretim_yontemi=uretilen.uretim_yontemi,
        uretilen_turu=uretilen.cozum_turu or "",
    )


def kor_kosu(
    cozucu: Cozucu,
    test_ornekleri: list[Ornek],
    *,
    ilerleme=None,
    gorsel_modu: str = VARSAYILAN_GORSEL_MODU,
) -> KosuOzeti:
    """Test örneklerini hafızadan dışlayarak çözer ve sonucu özetler."""
    sonuclar: list[OrnekSonucu] = []
    # Bütün test kümesini dışla: yalnız çözülen soruyu dışlamak, aynı kümedeki
    # başka bir test sorusunun sızmasına izin verirdi.
    haric = {metin_imzasi(o.soru) for o in test_ornekleri}

    # Görselsizler önce: karma motorda metin ve görsel model 16 GB'ta aynı anda
    # duramaz, biri diğerini bellekten düşürür. Karışık sırada her görselli soru
    # bir model takası demek; bu sıralamayla tüm koşu tek takasla biter.
    # `sorted` kararlı olduğu için küme içi sıra ve dolayısıyla determinizm
    # korunuyor.
    test_ornekleri = sorted(test_ornekleri, key=lambda o: bool(o.gorsel))

    for sira, ornek in enumerate(test_ornekleri, 1):
        cozum = cozucu.coz(
            ornek.soru,
            secenekler=ornek.secenekler or None,
            cevap_turu=ornek.cevap_turu,
            kaydet=False,
            haric_imzalar=haric,
            # Görsel, gerçek çözüm yolunda veriliyor; ölçüm onu atlarsa şekilli
            # sorular burada şekilsiz çözülür ve koşu, sistemin gerçek
            # performansını değil daha kötüsünü ölçer. Metin motorunda da
            # anlamlı: istem şeklin VAR olduğunu bildirince model eksik veriyi
            # uydurmak yerine güvenini düşürüyor.
            gorsel=ornek.gorsel,
            gorsel_modu=gorsel_modu,
        )
        sonuclar.append(cozum_puanla(cozum, ornek, cozucu.gomlemci))
        if ilerleme:
            ilerleme(sira, len(test_ornekleri), sonuclar[-1])

    return ozetle(sonuclar)


def ozetle(sonuclar: list[OrnekSonucu]) -> KosuOzeti:
    toplam = len(sonuclar)
    if not toplam:
        return KosuOzeti(0, 0, 0.0, 0.0, 0.0, 0.0, {}, [])
    dogru = sum(1 for s in sonuclar if s.cevap_dogru)
    tur_bazli: dict[str, dict[str, float]] = {}
    for sonuc in sonuclar:
        kayit = tur_bazli.setdefault(sonuc.cozum_turu, {"adet": 0.0, "dogru": 0.0})
        kayit["adet"] += 1
        kayit["dogru"] += 1 if sonuc.cevap_dogru else 0
    for kayit in tur_bazli.values():
        kayit["dogruluk"] = kayit["dogru"] / kayit["adet"] if kayit["adet"] else 0.0
    return KosuOzeti(
        toplam=toplam,
        dogru=dogru,
        dogruluk=dogru / toplam,
        ortalama_ortusme=round(mean(s.adim_ortusmesi for s in sonuclar), 4),
        ortalama_guven=round(mean(s.guven for s in sonuclar), 4),
        inceleme_orani=sum(1 for s in sonuclar if s.incele) / toplam,
        tur_bazli=tur_bazli,
        sonuclar=sonuclar,
    )
