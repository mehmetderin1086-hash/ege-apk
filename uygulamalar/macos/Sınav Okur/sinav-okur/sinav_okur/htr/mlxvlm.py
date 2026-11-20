"""Qwen-VL tabanlı kutu-düzeyi tanıyıcı (Apple Silicon, mlx-vlm).

Colab'da Unsloth QLoRA ile eğitilen model mlx formatına çevrilip
(``mlx_vlm.convert``) buraya verilir. VLM satır bölütlemeye ihtiyaç duymaz;
kutunun tamamını okur.

mlx-vlm token olasılığı vermediği için güven doğrudan modelden alınamaz.
Öz-tutarlılık ile vekil bir güven türetilir: kutu iki kez okunur (açgözlü +
küçük sıcaklık), iki okuma ne kadar örtüşürse güven o kadar yüksek olur.
Uyumsuz okumalar puanlama katmanındaki incele eşiğinin altına düşerek kutuyu
insana yönlendirir. Öz-tutarlılık kapatılırsa eski sabit-güven davranışı
korunur (``oz_tutarlilik=False``).
"""

from __future__ import annotations

import inspect

import numpy as np
from PIL import Image
from rapidfuzz import fuzz

from ..metin import eslesme_bicimi, nfc
from ..modeller import TanimaSonucu

# Yerelde kurulu ve biyo-cozucu tarafından da kullanılan model. Eski
# varsayılan (Qwen2.5-VL-7B-4bit) HF önbelleğinde yoktu, yani bu motor
# fiilen ölü koddu.
VARSAYILAN_MODEL = "mlx-community/Qwen3-VL-4B-Instruct-4bit"

# Kırpıntılar 4284×5712 piksele kadar çıkıyor; VLM'ye ham göndermek hem
# yavaş hem gereksiz. Uzun kenar bu değere küçültülür.
#
# ÖLÇÜLDÜ (gerçek Türkçe el yazısı, 2 kutu): 1200 → CER 0.946,
# 1600 → 0.612, 2200 → 0.594. Çözünürlük el yazısında belirleyici;
# 1200'de ince kurşun kalem izleri kayboluyor. 2200 seçildi çünkü bu
# katmanın işi doğru okumak, hız ikinci sırada (Vision zaten hızlı yol).
VARSAYILAN_AZAMI_KENAR = 2200

# Bu orandan daha dar/uzun şeritlerde VLM okumayı bırakıp uydurmaya
# başlıyor (ölçüldü: 48:1 oranlı bir satırda pi sayısı yazdı). Böyle
# girdilerde boş dönmek, uydurma metin döndürmekten güvenlidir — satır
# şeritleri zaten TrOCR/Vision gibi satır motorlarının işidir.
AZAMI_EN_BOY_ORANI = 12.0

KOMUT = (
    "Bu görüntüde Türkçe el yazısıyla yazılmış bir sınav cevabı var. "
    "Metni AYNEN, olduğu gibi yaz. Düzeltme yapma, yorum ekleme, "
    "sadece okuduğun metni ver. Görüntü boşsa hiçbir şey yazma."
)

# Bağlam ipuçları yalnız OKUMAYI kolaylaştırmak içindir; modelin görüntüde
# olmayan bir terimi yazması "dayanaksız üretim"dir ve puanı bozar.
BAGLAM_KOMUTU = (
    "Aşağıdaki terimler bu sorunun konusunda GEÇEBİLİR ve yalnız el yazısını "
    "çözmene yardım etmek için verilmiştir: {terimler}. "
    "UYARI: Görüntüde YAZMAYAN bir terimi ASLA yazma; bu liste bir cevap "
    "değildir. Sadece görüntüde gerçekten yazan metni aynen aktar."
)


class MlxVlmTaniyici:
    def __init__(
        self,
        model_yolu: str = VARSAYILAN_MODEL,
        sabit_guven: float = 0.8,
        oz_tutarlilik: bool = True,
        ikinci_sicaklik: float = 0.4,
        azami_kenar: int = VARSAYILAN_AZAMI_KENAR,
    ):
        from mlx_vlm import generate, load
        from mlx_vlm.prompt_utils import apply_chat_template

        self._generate = generate
        self._apply_chat_template = apply_chat_template
        self.model, self.islemci = load(model_yolu)
        self.sabit_guven = sabit_guven
        self.oz_tutarlilik = oz_tutarlilik
        self.ikinci_sicaklik = ikinci_sicaklik
        self.azami_kenar = int(azami_kenar)
        # mlx-vlm sürümüne göre sıcaklık argümanı adı değişir (temp/temperature).
        try:
            parametreler = set(inspect.signature(generate).parameters)
        except (TypeError, ValueError):
            parametreler = set()
        self._sicaklik_arg = (
            "temperature" if "temperature" in parametreler
            else "temp" if "temp" in parametreler
            else None
        )

    def _komut(self, baglam: list[str] | None) -> str:
        temiz = [
            str(t).strip()
            for t in (baglam or [])
            if str(t).strip() and len(str(t).strip()) >= 3
        ]
        if not temiz:
            return KOMUT
        # Uzun listeler istemin kendisini boğar ve sızma riskini büyütür.
        secilen = list(dict.fromkeys(temiz))[:40]
        return KOMUT + "\n" + BAGLAM_KOMUTU.format(terimler=", ".join(secilen))

    def _asiri_dar_mi(self, kirp: np.ndarray) -> bool:
        """En-boy oranı aşırıysa VLM halüsinasyona giriyor.

        ÖLÇÜLDÜ: 3889×81 (oran 48:1) bir satır şeridinde model, görüntüyle
        hiç ilgisi olmayan pi sayısını yazdı. Böyle bir çıktı "okuma hatası"
        değil uydurmadır; puanlamaya girmesi tehlikelidir.
        """
        if kirp is None or kirp.ndim < 2:
            return True
        y, x = kirp.shape[:2]
        if min(y, x) <= 0:
            return True
        return max(y, x) / min(y, x) > AZAMI_EN_BOY_ORANI

    def _gorsele_cevir(self, kirp: np.ndarray) -> Image.Image:
        rgb = kirp[..., ::-1] if kirp.ndim == 3 else np.stack([kirp] * 3, -1)
        gorsel = Image.fromarray(rgb.astype(np.uint8))
        uzun = max(gorsel.size)
        if self.azami_kenar and uzun > self.azami_kenar:
            oran = self.azami_kenar / uzun
            gorsel = gorsel.resize(
                (max(1, int(gorsel.width * oran)), max(1, int(gorsel.height * oran))),
                Image.LANCZOS,
            )
        return gorsel

    def serbest_birak(self) -> None:
        """Modeli bellekten düşür (16 GB'ta OCR havuzuyla birlikte sığmıyor)."""
        self.model = None
        self.islemci = None
        try:
            import mlx.core as mx

            mx.clear_cache()
        except (ImportError, AttributeError):
            pass

    def _oku(
        self, gorsel: Image.Image, sicaklik: float, baglam: list[str] | None = None
    ) -> str:
        prompt = self._apply_chat_template(
            self.islemci, self.model.config, self._komut(baglam), num_images=1
        )
        ek = {}
        if sicaklik and self._sicaklik_arg:
            ek[self._sicaklik_arg] = sicaklik
        cikti = self._generate(
            self.model, self.islemci, prompt, image=[gorsel],
            max_tokens=256, verbose=False, **ek,
        )
        metin = cikti.text if hasattr(cikti, "text") else str(cikti)
        return nfc(metin.strip())

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        return self.kutu_taniy_baglamli(kirp, dpi, None)

    def kutu_taniy_baglamli(
        self,
        kirp: np.ndarray,
        dpi: int = 300,
        baglam: list[str] | None = None,
    ) -> TanimaSonucu:
        if self._asiri_dar_mi(kirp):
            return TanimaSonucu(
                metin="",
                guven=0.0,
                belirsizlik_nedeni=(
                    "Görüntü VLM için aşırı dar/uzun; uydurma riski nedeniyle "
                    "okunmadı (satır şeritleri satır motorlarının işidir)."
                ),
            )
        gorsel = self._gorsele_cevir(kirp)
        birinci = self._oku(gorsel, 0.0, baglam)

        # Öz-tutarlılık kapalıysa veya sıcaklık desteklenmiyorsa eski davranış.
        if not self.oz_tutarlilik or self._sicaklik_arg is None:
            guven = self.sabit_guven if birinci else 0.0
            return TanimaSonucu(metin=birinci, guven=guven)

        ikinci = self._oku(gorsel, self.ikinci_sicaklik, baglam)
        if not birinci and not ikinci:
            return TanimaSonucu(metin="", guven=0.0)

        uyum = fuzz.ratio(eslesme_bicimi(birinci), eslesme_bicimi(ikinci)) / 100.0
        guven = 0.30 + 0.65 * uyum
        alternatifler = []
        if eslesme_bicimi(ikinci) != eslesme_bicimi(birinci):
            alternatifler = [{"metin": ikinci, "guven": round(guven, 3)}]
        return TanimaSonucu(
            metin=birinci,
            guven=round(guven, 3),
            alternatifler=alternatifler,
            uzlasma_guveni=round(uyum, 3),
            karar_marji=round(uyum, 3),
        )
