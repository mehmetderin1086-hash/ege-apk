"""Apple Silicon üzerinde yerel çıkarım (mlx-lm).

Model belleğe bir kez yüklenir ve süreç boyunca paylaşılır: 4-bit 9B model
~5-6 GB tutuyor, her istekte yeniden yüklemek 16 GB'lik bir makinede
kullanılamaz. LoRA adaptörü `adaptor_yolu` ile takılır.
"""

from __future__ import annotations

import os
import queue
import threading

from .temel import MotorHatasi

VARSAYILAN_MODEL = "mlx-community/Qwen3.5-4B-MLX-4bit"

_kilit = threading.Lock()
# Aynı model nesnesi üzerinde eşzamanlı üretim, 16 GB'lik bir makinede bellek
# baskısını katlar ve MLX'in paylaşılan hesap grafiğiyle güvenli değildir;
# üretimler seri koşar (web arayüzünde ikinci istek sırada bekler).
_uretim_kilidi = threading.Lock()
_onbellek: dict[tuple[str, str], tuple[object, object]] = {}


def _yukle(model_yolu: str, adaptor_yolu: str) -> tuple[object, object]:
    anahtar = (model_yolu, adaptor_yolu)
    with _kilit:
        if anahtar in _onbellek:
            return _onbellek[anahtar]
        try:
            from mlx_lm import load
        except ImportError as exc:  # pragma: no cover - ortam bağımlı
            raise MotorHatasi(
                "mlx-lm kurulu değil. Yerel çıkarım için: uv sync --extra mlx"
            ) from exc

        # Görsel model bellekteyse bırak. `vlm_motor` zaten ters yönde aynısını
        # yapıyor; karma motorda takas ÇİFT yönlü olmazsa iki model 16 GB'ta
        # aynı anda kalır ve ikinci üretim takas alanına düşerek dakikalarca
        # sürer. Simetri burada bir eniyileme değil, çalışabilirlik koşulu.
        try:
            from . import vlm_motor

            vlm_motor.onbellegi_bosalt()
        except ImportError:  # pragma: no cover
            pass

        try:
            model, tokenizer = load(
                model_yolu, adapter_path=adaptor_yolu or None
            )
        # Geniş yakalama kasıtlı: indirme, ağ ve sürüm uyumsuzluğu hatalarının
        # hepsi burada tek bir MotorHatasi'na çevrilir.
        except Exception as exc:
            raise MotorHatasi(f"Model yüklenemedi ({model_yolu}): {exc}") from exc
        _onbellek[anahtar] = (model, tokenizer)
        return model, tokenizer


def onbellegi_bosalt() -> None:
    """Yüklü modelleri bırakır (model değiştirdikten sonra çağrılır)."""
    with _kilit:
        _onbellek.clear()


class MlxMotor:
    """mlx-lm ile süreç içi yerel üretim."""

    def __init__(
        self,
        model_yolu: str | None = None,
        adaptor_yolu: str | None = None,
        *,
        dusunme: bool | None = None,
    ):
        self.model_yolu = model_yolu or os.environ.get("BIYO_MLX_MODEL", VARSAYILAN_MODEL)
        self.adaptor_yolu = adaptor_yolu or os.environ.get("BIYO_MLX_ADAPTOR", "")
        # Düşünme VARSAYILAN OLARAK KAPALI. Qwen3.5'in sohbet şablonu istemi
        # `<think>` ile açar; 4B model bu bloğu makul bir token bütçesi içinde
        # kapatmıyor, üretim düşüncenin ortasında kesiliyor ve JSON hiç gelmiyor
        # (ölçüldü: 3000 token / 88 sn → çıktı yok). Kapalıyken aynı soru 13
        # saniyede doğru cevaplanıyor — few-shot örnekler muhakemeyi zaten
        # taşıyor. Açmak için BIYO_DUSUNME=1 ve azami_token'ı belirgin artır.
        if dusunme is None:
            dusunme = os.environ.get("BIYO_DUSUNME", "0").strip() in {"1", "evet", "acik"}
        self.dusunme = dusunme
        self.ad = self.model_yolu + (f"+{self.adaptor_yolu}" if self.adaptor_yolu else "")

    def _istem_kur(self, tokenizer, mesajlar: list[dict[str, str]]):
        # enable_thinking parametresi yalnız destekleyen sohbet şablonlarında geçerli;
        # desteklemeyen modelde TypeError yerine sessizce yok sayılması için ayrı denenir.
        try:
            return tokenizer.apply_chat_template(
                mesajlar, add_generation_prompt=True, enable_thinking=self.dusunme
            )
        except TypeError:
            return tokenizer.apply_chat_template(mesajlar, add_generation_prompt=True)
        except Exception as exc:
            raise MotorHatasi(f"Sohbet şablonu uygulanamadı: {exc}") from exc

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        model, tokenizer = _yukle(self.model_yolu, self.adaptor_yolu)
        try:
            from mlx_lm import generate
            from mlx_lm.sample_utils import make_sampler
        except ImportError as exc:  # pragma: no cover
            raise MotorHatasi("mlx-lm kurulu değil.") from exc

        istem = self._istem_kur(tokenizer, mesajlar)
        try:
            sampler = make_sampler(temp=float(sicaklik))
            with _uretim_kilidi:
                return generate(
                    model,
                    tokenizer,
                    prompt=istem,
                    max_tokens=int(azami_token),
                    sampler=sampler,
                    verbose=False,
                )
        except Exception as exc:
            raise MotorHatasi(f"Yerel üretim başarısız: {exc}") from exc

    def uret_akis(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ):
        """Token'ları geldikçe verir.

        Üretim ayrı bir iş parçacığında koşar ve token'ları sınırsız bir
        kuyruğa yazar; bu generator yalnız kuyruğu boşaltır.

        Gerekçesi kilit güvenliği: kilidi doğrudan `yield` sınırları boyunca
        tutmak, tüketici akışı yarıda bıraktığında (kullanıcı Esc'e bastı,
        sekmeyi kapattı, SSE koptu) kilidin sızmasına yol açıyordu — Starlette
        istemci kopunca üreticiyi `close()` etmiyor, dolayısıyla `finally`
        çalışmıyor ve sonraki HER üretim isteği süresiz asılıyordu (canlı
        uvicorn ile üretilip doğrulandı). İşçi iş parçacığı tüketiciden
        bağımsız olarak sonuna kadar koşar ve kilidi kendi `finally`'sinde
        bırakır; terk edilen bir akışın bedeli en fazla bir boşa üretimdir.

        Kuyruk sınırsız: `azami_token` zaten üst sınır olduğundan bellek
        maliyeti birkaç KB'dir. Sınırlı kuyruk, tüketici gittiğinde `put`
        üzerinde bloklayıp kilidi yeniden sızdırırdı.
        """
        model, tokenizer = _yukle(self.model_yolu, self.adaptor_yolu)
        try:
            from mlx_lm import stream_generate
            from mlx_lm.sample_utils import make_sampler
        except ImportError as exc:  # pragma: no cover
            raise MotorHatasi("mlx-lm kurulu değil.") from exc

        istem = self._istem_kur(tokenizer, mesajlar)
        try:
            sampler = make_sampler(temp=float(sicaklik))
        except Exception as exc:
            raise MotorHatasi(f"Örnekleyici kurulamadı: {exc}") from exc

        kuyruk: queue.Queue = queue.Queue()
        bitti = object()

        def uret_calis() -> None:
            try:
                with _uretim_kilidi:
                    for adim in stream_generate(
                        model,
                        tokenizer,
                        prompt=istem,
                        max_tokens=int(azami_token),
                        sampler=sampler,
                    ):
                        parca = getattr(adim, "text", None)
                        if parca:
                            kuyruk.put(parca)
            except Exception as exc:  # noqa: BLE001
                kuyruk.put(MotorHatasi(f"Yerel akışlı üretim başarısız: {exc}"))
            finally:
                kuyruk.put(bitti)

        threading.Thread(
            target=uret_calis, name="biyo-mlx-akis", daemon=True
        ).start()

        while True:
            oge = kuyruk.get()
            if oge is bitti:
                return
            if isinstance(oge, BaseException):
                raise oge
            yield oge
