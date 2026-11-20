"""Taranmış (görüntü) PDF'ler ve resimler için OCR.

Dört motor desteklenir; hepsi aynı arayüzü uygular ve hangisinin kurulu
olduğuna göre otomatik seçilir. `BIYO_OCR` ile elle sabitlenebilir.

Türkçe için sıralama (kalite ölçütü: baskı kitap taramasında doğruluk):

  surya      En iyi. Çok dilli, satır/okuma sırasını da çözüyor; sütunlu
             soru kitaplarında metni doğru sırayla veriyor. En ağırı.
  easyocr    İyi ve kurulumu kolay. Türkçe (`tr`) desteği olgun.
  paddle     İyi, ama PaddlePaddle Apple Silicon'da kırılgan olabiliyor.
  tesseract  En hafifi ve en hızlısı; temiz baskıda yeterli, bozuk/eğik
             taramada belirgin biçimde geriye düşüyor. `tur` dil verisi şart.

OCR pahalıdır: yalnız metin katmanı bulunmayan sayfalara uygulanır
(bkz. `cikarim._pdf_cikar`), tüm PDF'e körlemesine değil.
"""

from __future__ import annotations

import glob
import os
import re
import shutil
from dataclasses import dataclass
from functools import lru_cache
from html import unescape
from pathlib import Path

from .cikarim import AlimHatasi

# Kalite sırası: otomatik seçim bu listeyi yukarıdan aşağıya dener.
MOTOR_SIRASI = ("surya", "easyocr", "paddle", "tesseract")

# Sayfayı bu DPI'da görüntüye çeviririz. 300 baskı metni için standart;
# daha düşüğü küçük punto şıkları ("A) …") okunamaz hale getiriyor.
VARSAYILAN_DPI = 300


@dataclass
class OcrSonucu:
    metin: str
    motor: str
    guven: float = 0.0


_ETIKET = re.compile(r"<[^>]+>")
_SATIR_ETIKETI = re.compile(r"</(?:p|div|li|tr|h\d)>|<br\s*/?>", re.IGNORECASE)


def _html_metne(html: str) -> str:
    """Surya blokları HTML döndürür; satır yapısını koruyarak düz metne çevirir."""
    if not html:
        return ""
    metin = _SATIR_ETIKETI.sub("\n", html)
    metin = _ETIKET.sub("", metin)
    metin = unescape(metin)
    return "\n".join(s.strip() for s in metin.split("\n") if s.strip())


class _Motor:
    ad = ""

    def hazir_mi(self) -> bool:
        raise NotImplementedError

    def neden_hazir_degil(self) -> str:
        """Motor kullanılamıyorsa nedenini ve çözümünü anlatan tek cümle.

        Genel "kurulu değil, uv sync --extra ocr" mesajı Surya için aktif
        olarak yanıltıcıydı: Python paketi kuruluyken eksik olan `llama-server`
        ikilisi olabiliyor ve kullanıcı boş yere paketi yeniden kuruyordu.
        """
        return f"'{self.ad}' OCR motoru kullanılamıyor. Kurulum: uv sync --extra ocr"

    def oku(self, goruntu) -> OcrSonucu:
        raise NotImplementedError


def _llama_server_bul() -> str:
    """Surya 2 GGUF tabanlıdır ve `llama-server` ikilisini gerektirir.

    Bu makinede brew yok; ikili başka bir projeyle birlikte gelmiş olabilir.
    Bulunca `LLAMA_CPP_BINARY`'yi kendimiz kuruyoruz, yoksa Surya "brew
    install llama.cpp" diye anlamsız bir hata veriyor.

    Arama sırası: `BIYO_LLAMA_SERVER` (projenin kendi bayrağı) → Surya'nın
    kendi `LLAMA_CPP_BINARY`'si → PATH → bilinen kurulum yerleri. Son
    gruptaki `sinav-okur` yolu bu makineye özgü bir kolaylıktır; o proje
    taşınırsa arama sessizce başarısız olmasın diye ilk iki bayrak var.
    """
    for degisken in ("BIYO_LLAMA_SERVER", "LLAMA_CPP_BINARY"):
        mevcut = os.environ.get(degisken, "")
        if mevcut and Path(mevcut).is_file():
            return mevcut
    yoldan = shutil.which("llama-server")
    if yoldan:
        return yoldan
    for desen in (
        Path.home() / "Developer/sinav-okur/.ocr-tools/llama.cpp/*/llama-server",
        Path.home() / ".local/bin/llama-server",
    ):
        for aday in sorted(glob.glob(str(desen)), reverse=True):
            if Path(aday).is_file():
                return aday
    return ""


class SuryaMotoru(_Motor):
    ad = "surya"

    def hazir_mi(self) -> bool:
        try:
            import surya  # noqa: F401
        except ImportError:
            return False
        ikili = _llama_server_bul()
        if not ikili:
            return False
        os.environ.setdefault("LLAMA_CPP_BINARY", ikili)
        return True

    def neden_hazir_degil(self) -> str:
        try:
            import surya  # noqa: F401
        except ImportError:
            return "'surya' kurulu değil. Kurulum: uv sync --extra ocr"
        return (
            "'surya' kurulu ama gerektirdiği `llama-server` ikilisi bulunamadı. "
            "İkilinin yolunu BIYO_LLAMA_SERVER ile verin ya da llama.cpp kurun."
        )

    @staticmethod
    @lru_cache(maxsize=1)
    def _taniyici():
        # Surya 0.22 API'si: `RecognitionPredictor()` tek başına yeterli,
        # ayrı bir DetectionPredictor geçirmek gerekmiyor. (0.x'in erken
        # sürümlerindeki `surya.foundation` yolu artık yok.)
        from surya.recognition import RecognitionPredictor

        return RecognitionPredictor()

    def _sayfayi_cozumle(self, sayfa) -> OcrSonucu:
        satirlar, guvenler = [], []
        blok_listesi = getattr(sayfa, "blocks", None) or []
        # Okuma sırası Surya'nın asıl üstünlüğü: sütunlu soru kitabında
        # metni doğru sırayla vermesini sağlıyor.
        blok_listesi = sorted(
            blok_listesi, key=lambda b: getattr(b, "reading_order", 0) or 0
        )
        for blok in blok_listesi:
            if getattr(blok, "skipped", False) or getattr(blok, "error", None):
                continue
            metin = _html_metne(getattr(blok, "html", "") or "")
            if metin:
                satirlar.append(metin)
                guvenler.append(float(getattr(blok, "confidence", 0.0) or 0.0))
        return OcrSonucu(
            metin="\n".join(satirlar),
            motor=self.ad,
            guven=sum(guvenler) / len(guvenler) if guvenler else 0.0,
        )

    def oku(self, goruntu) -> OcrSonucu:
        return self.okulari([goruntu])[0]

    def okulari(self, goruntuler: list) -> list[OcrSonucu]:
        """Birden çok görüntüyü tek çıkarım çağrısında okur.

        Sayfa başına maliyeti belirgin düşürüyor (ölçüm: 55,5 → 34,5 sn);
        kitap boyu alımda tek fark yaratan optimizasyon bu.
        """
        if not goruntuler:
            return []
        try:
            sonuclar = self._taniyici()(list(goruntuler))
        except Exception as exc:
            raise AlimHatasi(f"Surya OCR başarısız: {exc}") from exc
        cozumlenen = [self._sayfayi_cozumle(s) for s in sonuclar]
        # Motor beklenenden az sonuç dönerse eksik sayfa SESSİZCE boş
        # geçmemeli; çağıran sayfa sırasına göre eşleştirme yapıyor.
        while len(cozumlenen) < len(goruntuler):
            cozumlenen.append(OcrSonucu(metin="", motor=self.ad, guven=0.0))
        return cozumlenen


class EasyOcrMotoru(_Motor):
    ad = "easyocr"

    def hazir_mi(self) -> bool:
        try:
            import easyocr  # noqa: F401
        except ImportError:
            return False
        return True

    @staticmethod
    @lru_cache(maxsize=1)
    def _okuyucu():
        import easyocr

        # Türkçe + İngilizce birlikte: kitaplarda Latince tür adları ve
        # İngilizce kısaltmalar sık geçiyor.
        return easyocr.Reader(["tr", "en"], gpu=False, verbose=False)

    def oku(self, goruntu) -> OcrSonucu:
        import numpy as np

        try:
            sonuc = self._okuyucu().readtext(np.array(goruntu))
        except Exception as exc:
            raise AlimHatasi(f"EasyOCR başarısız: {exc}") from exc
        satirlar = [str(k[1]).strip() for k in sonuc if str(k[1]).strip()]
        guvenler = [float(k[2]) for k in sonuc if len(k) > 2]
        return OcrSonucu(
            metin="\n".join(satirlar),
            motor=self.ad,
            guven=sum(guvenler) / len(guvenler) if guvenler else 0.0,
        )


class PaddleMotoru(_Motor):
    ad = "paddle"

    def hazir_mi(self) -> bool:
        try:
            import paddleocr  # noqa: F401
        except ImportError:
            return False
        return True

    @staticmethod
    @lru_cache(maxsize=1)
    def _okuyucu():
        from paddleocr import PaddleOCR

        # Türkçe ayrı bir rec modeli değil; Latin alfabesi modeli kullanılır.
        return PaddleOCR(use_angle_cls=True, lang="latin", show_log=False)

    def oku(self, goruntu) -> OcrSonucu:
        import numpy as np

        try:
            sonuc = self._okuyucu().ocr(np.array(goruntu), cls=True)
        except Exception as exc:
            raise AlimHatasi(f"PaddleOCR başarısız: {exc}") from exc
        satirlar, guvenler = [], []
        for sayfa in sonuc or []:
            for satir in sayfa or []:
                try:
                    metin, guven = satir[1][0], float(satir[1][1])
                except (IndexError, TypeError, ValueError):
                    continue
                if str(metin).strip():
                    satirlar.append(str(metin).strip())
                    guvenler.append(guven)
        return OcrSonucu(
            metin="\n".join(satirlar),
            motor=self.ad,
            guven=sum(guvenler) / len(guvenler) if guvenler else 0.0,
        )


class TesseractMotoru(_Motor):
    ad = "tesseract"

    def hazir_mi(self) -> bool:
        try:
            import pytesseract
        except ImportError:
            return False
        try:
            diller = pytesseract.get_languages(config="")
        except Exception:  # noqa: BLE001 - ikili yoksa
            return False
        # `tur` dil verisi olmadan Türkçe metin belirgin biçimde bozuluyor.
        return "tur" in diller

    def neden_hazir_degil(self) -> str:
        try:
            import pytesseract
        except ImportError:
            return (
                "'tesseract' için Python sarmalayıcısı kurulu değil. "
                "Kurulum: uv sync --extra ocr-tesseract"
            )
        try:
            diller = pytesseract.get_languages(config="")
        except Exception:  # noqa: BLE001
            return (
                "'tesseract' Python paketi kurulu ama `tesseract` ikilisi "
                "sistemde bulunamadı; ikiliyi ayrıca kurun."
            )
        if "tur" not in diller:
            return (
                "'tesseract' kurulu ama `tur` dil verisi yok; Türkçe metin "
                "onsuz belirgin biçimde bozuluyor. tessdata'ya tur.traineddata ekleyin."
            )
        return super().neden_hazir_degil()

    def oku(self, goruntu) -> OcrSonucu:
        import pytesseract

        try:
            metin = pytesseract.image_to_string(goruntu, lang="tur+eng")
        except Exception as exc:
            raise AlimHatasi(f"Tesseract başarısız: {exc}") from exc
        return OcrSonucu(metin=metin.strip(), motor=self.ad)


_MOTORLAR: dict[str, _Motor] = {
    SuryaMotoru.ad: SuryaMotoru(),
    EasyOcrMotoru.ad: EasyOcrMotoru(),
    PaddleMotoru.ad: PaddleMotoru(),
    TesseractMotoru.ad: TesseractMotoru(),
}


def kullanilabilir_motorlar() -> list[str]:
    """Kurulu ve çalışabilir motorlar — kalite sırasıyla."""
    return [ad for ad in MOTOR_SIRASI if _MOTORLAR[ad].hazir_mi()]


def taniyicilari_sifirla() -> None:
    """Önbelleklenmiş tanıyıcıları atar; sonraki çağrı yeniden kurar.

    Uzun koşularda gerekiyor: Surya'nın arkasındaki `llama-server` süreci
    düştüğünde tanıyıcı aynı ölü bağlantıyı kullanmayı sürdürüyor ve her
    sayfa sessizce boş dönüyor. Kitap alımında bu, yüzlerce sayfanın
    "boş sayfa" sayılıp koşunun hatasız görünmesine yol açmıştı.
    """
    for motor in _MOTORLAR.values():
        temizle = getattr(getattr(motor, "_taniyici", None), "cache_clear", None)
        if callable(temizle):
            temizle()


def motor_sec(istenen: str = "") -> _Motor:
    """`BIYO_OCR` ya da parametre; yoksa kalite sırasına göre ilk kurulu olan."""
    istenen = (istenen or os.environ.get("BIYO_OCR", "")).strip().casefold()
    if istenen:
        if istenen not in _MOTORLAR:
            raise AlimHatasi(
                f"Bilinmeyen OCR motoru: {istenen}. "
                f"Seçenekler: {', '.join(MOTOR_SIRASI)}"
            )
        motor = _MOTORLAR[istenen]
        if not motor.hazir_mi():
            raise AlimHatasi(motor.neden_hazir_degil())
        return motor

    for ad in MOTOR_SIRASI:
        if _MOTORLAR[ad].hazir_mi():
            return _MOTORLAR[ad]
    raise AlimHatasi(
        "Hiçbir OCR motoru kurulu değil. Taranmış PDF okumak için: "
        "uv sync --extra ocr"
    )


def sayfalari_oku(
    sayfalar: list, *, motor: str = "", dpi: int = VARSAYILAN_DPI
) -> list[OcrSonucu]:
    """Birden çok sayfayı TEK çağrıda okur — kitap boyu alımın hızlı yolu.

    Ölçüldü (Campbell, surya/llama.cpp, Apple Silicon): sayfa başına tek tek
    55,5 sn, dörderli gruplarla 34,5 sn. Fark modelin yeniden yüklenmesinden
    değil (tanıyıcı zaten önbellekli), toplu çıkarımın çağrı başına sabit
    maliyeti paylaştırmasından geliyor. 1101 sayfalık bir kitapta bu, 17
    saatlik bir farka karşılık geliyor.

    Motoru tek sayfalık okumaya düşen bir geri yolu var: tüm motorlar toplu
    çağrıyı desteklemiyor.
    """
    if not sayfalar:
        return []
    secilen = motor_sec(motor)
    goruntuler = []
    for sayfa in sayfalar:
        try:
            goruntuler.append(sayfa.render(scale=dpi / 72).to_pil())
        except Exception as exc:
            raise AlimHatasi(f"Sayfa görüntüye çevrilemedi: {exc}") from exc

    topluca = getattr(secilen, "okulari", None)
    if callable(topluca):
        return topluca(goruntuler)
    return [secilen.oku(g) for g in goruntuler]


def sayfayi_oku(sayfa, *, motor: str = "", dpi: int = VARSAYILAN_DPI) -> OcrSonucu:
    """Tek bir pypdfium2 sayfasını görüntüye çevirip OCR'dan geçirir."""
    secilen = motor_sec(motor)
    try:
        # pypdfium2 ölçeği 72 dpi tabanlıdır.
        bitmap = sayfa.render(scale=dpi / 72)
        goruntu = bitmap.to_pil()
    except Exception as exc:
        raise AlimHatasi(f"Sayfa görüntüye çevrilemedi: {exc}") from exc
    return secilen.oku(goruntu)


def goruntuyu_oku(yol, *, motor: str = "") -> OcrSonucu:
    """Bir resim dosyasını (fotoğraf, ekran görüntüsü) OCR'dan geçirir."""
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover
        raise AlimHatasi("Görüntü okumak için: uv sync --extra ocr") from exc
    secilen = motor_sec(motor)
    try:
        with Image.open(str(yol)) as goruntu:
            return secilen.oku(goruntu.convert("RGB"))
    except AlimHatasi:
        raise
    except Exception as exc:
        raise AlimHatasi(f"Görüntü açılamadı: {exc}") from exc
