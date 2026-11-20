"""Görsel soru çıkarımı (mlx-vlm, Apple Silicon).

Yalnız ÇIKARIM. Görsel LoRA eğitimi kapsam dışı: mlx-vlm #824 nedeniyle
Qwen3.5/Gemma VLM LoRA eğitimi görüntüsüz koşuyor ve loss takılıyor
(bkz. `docs/egitim_runbook.md`).

Bellek notu: bu makine 16 GB. VLM (4-bit, ~3 GB), metin modeli (~2,5 GB) ve
gömme modeli aynı anda bellekte tutulabilir görünse de MLX'in üretim
sırasındaki tepe kullanımı bunu riskli kılıyor. Bu yüzden görsel motoru
yüklenmeden önce metin modeli bırakılıyor (`mlx_motor.onbellegi_bosalt`).
"""

from __future__ import annotations

import io
import os
import threading

from .temel import MotorHatasi

# 16 GB makinedeki 50 gerçek görselli kör testte 9B'den daha iyi çıkan
# MLX portu (4-bit, ~3 GB). Model boyutu değil ölçülen doğruluk esas alındı.
VARSAYILAN_MODEL = "mlx-community/Qwen3.5-4B-MLX-4bit"

# mlx-vlm bu sürümden önce Qwen3-VL'i tanımıyor; pyproject'teki alt sınır da
# buna göre. Sürüm eskiyse hata "model bulunamadı" gibi görünüp yanıltıyor.
ASGARI_MLX_VLM = "0.6.8"

_kilit = threading.Lock()
_uretim_kilidi = threading.Lock()
_onbellek: dict[str, tuple[object, object, object]] = {}


def _yukle(model_yolu: str):
    with _kilit:
        if model_yolu in _onbellek:
            return _onbellek[model_yolu]
        try:
            from mlx_vlm import load
            from mlx_vlm.utils import load_config
        except ImportError as exc:  # pragma: no cover - ortam bağımlı
            raise MotorHatasi(
                "mlx-vlm kurulu değil. Görsel soru desteği için: "
                f"uv sync --extra vizyon (mlx-vlm >= {ASGARI_MLX_VLM} gerekir)"
            ) from exc

        # Metin modeli bellekte duruyorsa bırak: 16 GB'da ikisinin tepe
        # kullanımı aynı anda sığmıyor. Görselli sorular azınlıkta olduğundan
        # geçiş maliyeti kabul edilebilir.
        try:
            from . import mlx_motor

            mlx_motor.onbellegi_bosalt()
        except ImportError:  # pragma: no cover
            pass

        try:
            model, islemci = load(model_yolu)
            yapilandirma = load_config(model_yolu)
        # Geniş yakalama kasıtlı: indirme, ağ ve sürüm uyumsuzluğu hatalarının
        # hepsi burada tek bir MotorHatasi'na çevrilir.
        except Exception as exc:
            raise MotorHatasi(
                f"Görsel model yüklenemedi ({model_yolu}): {exc}. "
                f"mlx-vlm sürümünüz {ASGARI_MLX_VLM} veya üstü mü?"
            ) from exc
        _onbellek[model_yolu] = (model, islemci, yapilandirma)
        return _onbellek[model_yolu]


def onbellegi_bosalt() -> None:
    """Yüklü görsel modeli bırakır (metin modeline dönerken çağrılır)."""
    with _kilit:
        _onbellek.clear()


class VlmMotor:
    """mlx-vlm ile süreç içi görsel çıkarım."""

    def __init__(self, model_yolu: str | None = None):
        self.model_yolu = model_yolu or os.environ.get(
            "BIYO_VLM_MODEL", VARSAYILAN_MODEL
        )
        self.ad = self.model_yolu
        self.dusunme_modu = os.environ.get("BIYO_VLM_DUSUNME", "adaptive").strip() or "adaptive"
        if self.dusunme_modu not in {"enabled", "disabled", "adaptive"}:
            self.dusunme_modu = "adaptive"

    def _metin_istemi(self, mesajlar: list[dict[str, str]]) -> str:
        """Çok turlu mesajları tek metne indirger.

        Görselli few-shot BİLİNÇLİ olarak kullanılmıyor: her örnek görüntüsü
        bağlamı ve belleği katlıyor, 16 GB'da sürdürülemez. Kanıt örnekleri
        metin olarak veriliyor, görüntü yalnız çözülecek soruya ait.
        """
        parcalar = []
        for mesaj in mesajlar:
            rol = mesaj.get("role", "user")
            icerik = mesaj.get("content", "")
            if rol == "system":
                parcalar.append(icerik)
            elif rol == "assistant":
                parcalar.append(f"Örnek çözüm: {icerik}")
            else:
                parcalar.append(icerik)
        return "\n\n".join(p for p in parcalar if p)

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        """Görüntüsüz çağrı — görsel motor metin sorusunu da çözebilir."""
        return self.gorselle_uret(
            mesajlar, b"", sicaklik=sicaklik, azami_token=azami_token
        )

    def gorselle_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel: bytes,
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        model, islemci, yapilandirma = _yukle(self.model_yolu)
        try:
            from mlx_vlm import generate
            from mlx_vlm.prompt_utils import apply_chat_template
        except ImportError as exc:  # pragma: no cover
            raise MotorHatasi("mlx-vlm kurulu değil.") from exc

        goruntuler = []
        if gorsel:
            try:
                from PIL import Image

                goruntuler = [Image.open(io.BytesIO(gorsel)).convert("RGB")]
            except Exception as exc:
                raise MotorHatasi(f"Görüntü açılamadı: {exc}") from exc

        duz_istem = self._metin_istemi(mesajlar)
        # Algılama JSON'u kısa ve nesnel olmalı; düşünme bütçesi kanıtı
        # kesmeden tüketmesin. Nihai çözümde Qwen3.5'in uyarlanabilir modu
        # kullanılabilir.
        dusunme = "disabled" if "Yalnız görsel algılama yap" in duz_istem else self.dusunme_modu
        try:
            istem = apply_chat_template(
                islemci,
                yapilandirma,
                duz_istem,
                num_images=len(goruntuler),
                thinking_mode=dusunme,
            )
        except TypeError:
            istem = apply_chat_template(
                islemci, yapilandirma, duz_istem, num_images=len(goruntuler)
            )
        try:
            # Üretimler seri koşar: MLX'in paylaşılan hesap grafiğiyle
            # eşzamanlı üretim güvenli değil (metin motorunda da aynı kural).
            with _uretim_kilidi:
                sonuc = generate(
                    model,
                    islemci,
                    istem,
                    goruntuler or None,
                    max_tokens=int(azami_token),
                    temperature=float(sicaklik),
                    verbose=False,
                )
        except Exception as exc:
            raise MotorHatasi(f"Görsel üretim başarısız: {exc}") from exc
        # mlx-vlm sürümleri kimi zaman metin, kimi zaman (metin, istatistik)
        # döndürüyor; ikisi de karşılanmalı.
        if isinstance(sonuc, tuple):
            sonuc = sonuc[0]
        return getattr(sonuc, "text", sonuc) or ""

    def gorsel_kaniti_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel: bytes,
        *,
        sicaklik: float = 0.0,
        azami_token: int = 700,
    ) -> str:
        """Çözümden ayrı algılama çağrısı; test/fallback motorlarında yoktur."""
        return self.gorselle_uret(
            mesajlar,
            gorsel,
            sicaklik=sicaklik,
            azami_token=azami_token,
        )
