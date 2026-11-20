"""Dil modeli motoru soyutlaması.

İki gerçekleme var: yerel `mlx_motor` (Apple Silicon, in-process) ve
`http_motor` (OpenAI-uyumlu herhangi bir uç: mlx_lm.server, Ollama, CLI Proxy).
Çözücü yalnız bu protokole bakar.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from typing import Protocol, runtime_checkable


class MotorHatasi(RuntimeError):
    """Model çağrısı yapılamadığında veya yanıt kullanılamadığında oluşur."""


class Motor(Protocol):
    ad: str

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str: ...


@runtime_checkable
class AkanMotor(Protocol):
    """Üretimi parça parça verebilen motor.

    Ayrı bir protokol: her motor akış desteklemek zorunda değil. Çözücü
    `isinstance(motor, AkanMotor)` ile yoklar, desteklenmiyorsa tek parça
    üreten `uret()`e düşer — böylece akış bir hızlandırma katmanı olarak
    kalır, doğruluğun ön koşulu olmaz.
    """

    def uret_akis(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> Iterator[str]: ...


@runtime_checkable
class GorselMotor(Protocol):
    """Soruya iliştirilmiş bir görüntüyü de okuyabilen motor.

    `AkanMotor` ile aynı gerekçeyle AYRI bir protokol: her motor görsel
    desteklemek zorunda değil ve `Motor.uret` imzasına görüntü eklemek
    `SahteMotor` ile `HttpMotor`'u kırardı. Çözücü `isinstance(motor,
    GorselMotor)` ile yokluyor; desteklenmiyorsa görüntü yok sayılıp soru
    metinle çözülür ve çözüm incelemeye düşürülür.
    """

    def gorselle_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel: bytes,
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str: ...


def akisa_dus(
    motor: Motor,
    mesajlar: list[dict[str, str]],
    *,
    sicaklik: float = 0.2,
    azami_token: int = 1536,
) -> Iterator[str]:
    """Motor akış desteklemiyorsa tam yanıtı tek parça olarak veren köprü."""
    if isinstance(motor, AkanMotor):
        yield from motor.uret_akis(
            mesajlar, sicaklik=sicaklik, azami_token=azami_token
        )
    else:
        yield motor.uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)


_CIT = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE | re.MULTILINE)
_DUSUNCE = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


def dusunceyi_ayikla(metin: str) -> tuple[str, str]:
    """(düşünce, görünür yanıt) — düşünce bloğunu yanıttan ayırır.

    Üç biçim de karşılanır:
    - Tam blok: ``<think>…</think>`` (yanıtın kendi ürettiği etiketler)
    - **Yalnız kapanış**: Qwen3.5'in sohbet şablonu istemi ``<think>\\n`` ile
      bitirir, yani AÇILIŞ etiketi istemde kalır ve üretilen metinde yalnız
      ``</think>`` görünür. Bu durumda kapanıştan öncesi düşüncedir.
    - Kapanmamış açılış: üretim token sınırında kesilmiştir; tamamı düşünce
      sayılır, aksi halde ham düşünce yanıt diye sunulurdu.
    """
    dusunceler = _DUSUNCE.findall(metin)
    kalan = _DUSUNCE.sub("", metin).strip()

    alcak = kalan.casefold()
    if "</think>" in alcak and "<think>" not in alcak:
        son = alcak.rindex("</think>")
        dusunceler.append(kalan[:son].strip())
        kalan = kalan[son + len("</think>") :].strip()
        alcak = kalan.casefold()

    if "<think>" in alcak:
        bas = alcak.index("<think>")
        dusunceler.append(kalan[bas:])
        kalan = kalan[:bas].strip()
    return "\n".join(d for d in dusunceler if d).strip(), kalan


def json_ayikla(metin: str) -> dict:
    """Model yanıtından JSON nesnesi çıkarır (kod çiti ve düşünce bloğu toleranslı)."""
    _, govde = dusunceyi_ayikla(metin)
    govde = _CIT.sub("", govde.strip()).strip()
    try:
        veri = json.loads(govde)
    except json.JSONDecodeError:
        bas = govde.find("{")
        if bas < 0:
            raise ValueError("Model geçerli JSON döndürmedi.") from None
        son = govde.rfind("}")
        veri = None
        if son > bas:
            try:
                veri = json.loads(govde[bas : son + 1])
            except json.JSONDecodeError:
                veri = None
        if veri is None:
            # Kapanış ayracı hiç gelmemiş olabilir (üretim ortada kesildiğinde);
            # bu durumda da onarım denenmeli, yoksa yanıt tümden atılır.
            veri = _bozuk_jsonu_onar(govde[bas:])
            if veri is None:
                raise ValueError("Model yanıtı çözümlenemedi.") from None
    if not isinstance(veri, dict):
        raise ValueError("Model yanıtı JSON nesnesi değil.")
    return veri


# `"cevap": "C"` — bozuk JSON'da bile alan tek başına okunabiliyor.
# Sınır (`\b`) şart: `"on_cevap"` da `"cevap"` ile bitiyor, sınırsız kalıp
# ön cevabı nihai cevap sanıp ikisini birbirine karıştırırdı.
_CEVAP_ALANI = re.compile(r'(?<!on_)"cevap"\s*:\s*"((?:[^"\\]|\\.){0,120})"')
# v2 şemasının sigortası: en başta üretildiği için kesilmiş yanıtta bile
# neredeyse her zaman hayatta kalır.
_ON_CEVAP_ALANI = re.compile(r'"on_cevap"\s*:\s*"((?:[^"\\]|\\.){0,120})"')
_GUVEN_ALANI = re.compile(r'"guven"\s*:\s*([01](?:\.\d+)?)')
# `adimlar` dizisinin tamamlanmış öğeleri: açılıştan sonraki her kapalı dize.
_ADIMLAR_ALANI = re.compile(r'"adimlar"\s*:\s*\[(.*)', re.DOTALL)
_DIZE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def _bozuk_jsonu_onar(parca: str) -> dict | None:
    """Şemayı bozan yanıttan kurtarılabilecek alanları toplar.

    Ölçümde görülen baskın bozulma: model `adimlar` dizisini KAPATMADAN
    (`]` yazmadan) objeyi `}` ile bitiriyor ve `cevap` alanını hiç üretmiyor.
    125 soruluk koşuda yanıtların %23'ü buydu — hepsi tümden atılıyor,
    üretilmiş muhakeme de cevap da çöpe gidiyordu.

    Onarım yalnız VERİ kurtarır, cevap UYDURMAZ: `cevap` alanı gerçekten
    yoksa boş döner ve çözüm incelemeye düşer. Aksi hâlde onarım, sistemi
    "bilmiyorum" diyemez hâle getirirdi.
    """
    adimlar: list[str] = []
    eslesme = _ADIMLAR_ALANI.search(parca)
    if eslesme:
        # Dizi kapanmışsa yalnız kapanışa kadarki bölüm; kapanmamışsa elde ne
        # varsa o. `][` içeren adım metni olasılığı yok sayılabilir.
        govde = eslesme.group(1)
        kapanis = govde.find("]")
        if kapanis >= 0:
            govde = govde[:kapanis]
        adimlar = [
            a.strip() for a in (m.group(1) for m in _DIZE.finditer(govde)) if a.strip()
        ]

    cevap_eslesme = _CEVAP_ALANI.search(parca)
    on_cevap_eslesme = _ON_CEVAP_ALANI.search(parca)
    guven_eslesme = _GUVEN_ALANI.search(parca)
    if not adimlar and not cevap_eslesme and not on_cevap_eslesme:
        return None
    return {
        "adimlar": adimlar,
        "cevap": cevap_eslesme.group(1).strip() if cevap_eslesme else "",
        "on_cevap": on_cevap_eslesme.group(1).strip() if on_cevap_eslesme else "",
        "guven": float(guven_eslesme.group(1)) if guven_eslesme else 0.0,
        "uyari": "Model JSON şemasını bozdu; yanıttan kurtarılabilen alanlar alındı.",
        "_onarildi": True,
    }


class SahteMotor:
    """Testler ve model yokken kuru çalıştırma için sabit yanıt döndüren motor."""

    ad = "sahte"

    def __init__(self, yanitlar: list[str] | str | None = None, *, parca_boyu: int = 0):
        if isinstance(yanitlar, str):
            yanitlar = [yanitlar]
        self.yanitlar = list(yanitlar or [])
        self.cagrilar: list[list[dict[str, str]]] = []
        # 0 = tek parça. Pozitifse akış testlerinde yanıt bu boyda dilimlenir.
        self.parca_boyu = parca_boyu
        # Görselli çağrıda alınan görüntüler — testler "görüntü gerçekten
        # modele gitti mi" sorusunu bunun üzerinden doğrular.
        self.gorseller: list[bytes] = []

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        self.cagrilar.append(mesajlar)
        if not self.yanitlar:
            raise MotorHatasi("SahteMotor'un yanıtı tükendi.")
        return self.yanitlar.pop(0) if len(self.yanitlar) > 1 else self.yanitlar[0]

    def uret_akis(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> Iterator[str]:
        tam = self.uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)
        if self.parca_boyu <= 0:
            yield tam
            return
        for bas in range(0, len(tam), self.parca_boyu):
            yield tam[bas : bas + self.parca_boyu]


class SahteGorselMotor(SahteMotor):
    """Görsel destekleyen sahte motor — testler çevrimdışı kalsın diye.

    Gerçek VLM birkaç GB indirir ve saniyeler sürer; testin sınadığı şey
    görüntünün DOĞRU YERE ULAŞMASI, modelin ne dediği değil.
    """

    ad = "sahte-gorsel"

    def gorselle_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel: bytes,
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        self.gorseller.append(gorsel)
        return self.uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)
