"""Soruyu içeriğine göre metin veya görsel modele yönlendiren motor.

Neden ayrı bir motor: korpusun yalnız %30'u şekle bağlı, geri kalan %70'i düz
metin. Tek başına `VlmMotor` seçmek görselli soruları kurtarırken görselsiz
çoğunluğu İNCE AYARSIZ tabana düşürüyor — projenin LoRA modeli (`biyo-mlx-v1`)
yalnız metin tarafında var. Bu motor iki modeli tek arayüzde toplar: görüntü
yoksa metin modeli (ince ayarlı), görüntü varsa görsel model.

Bellek: 16 GB'ta iki model aynı anda tutulamaz, alt motorlar birbirini
önbellekten düşürerek takas eder. Takas pahalı olduğu için değerlendirme
koşusu görselsiz soruları öne alır (bkz. `degerlendirme.kor_kosu`) ve tüm koşu
tek takasla biter.
"""

from __future__ import annotations

from collections.abc import Iterator

from .temel import GorselMotor, Motor, MotorHatasi, akisa_dus


class KarmaMotor:
    """Görselsiz → metin motoru, görselli → görsel motor."""

    def __init__(
        self,
        metin: Motor | None = None,
        gorsel: GorselMotor | None = None,
        **secenekler,
    ):
        if metin is None:
            from .mlx_motor import MlxMotor

            metin = MlxMotor(**secenekler)
        if gorsel is None:
            from .vlm_motor import VlmMotor

            gorsel = VlmMotor()
        self.metin = metin
        self.gorsel = gorsel
        self.ad = f"karma({getattr(metin, 'ad', '?')}+{getattr(gorsel, 'ad', '?')})"

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        return self.metin.uret(
            mesajlar, sicaklik=sicaklik, azami_token=azami_token
        )

    def uret_akis(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> Iterator[str]:
        # Akış yalnız metin yolunda anlamlı; görselli soru zaten `gorselle_uret`
        # üzerinden geliyor ve tek parça dönüyor.
        return akisa_dus(
            self.metin, mesajlar, sicaklik=sicaklik, azami_token=azami_token
        )

    def gorselle_uret(
        self,
        mesajlar: list[dict[str, str]],
        gorsel: bytes,
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        # Boş görüntüyle çağrı, görsel modeli boşuna yükleyip metin modelini
        # bellekten düşürürdü; bu durumda metin yoluna dönmek şart.
        if not gorsel:
            return self.uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)
        try:
            return self.gorsel.gorselle_uret(
                mesajlar, gorsel, sicaklik=sicaklik, azami_token=azami_token
            )
        except MotorHatasi:
            # Görsel model kurulu değil ya da üretemedi. Hatayı yukarı bırakmak
            # çözücüyü `_motorsuz_cozum`a düşürür — yani soruyu HİÇ çözmeyip
            # en benzer referansı göstermeye. Ölçümde bu, görselli 16 soruda
            # 11/16'dan 4/16'ya düşmek demekti. Metin modeli şekli göremez ama
            # soruyu gerçekten çözer; doğru geri çekilme yolu budur.
            # Şeklin kullanılmadığı `Cozucu._sonlandir`'da zaten uyarıya
            # dönüşüyor, sessiz kalınmıyor.
            return self.uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)
