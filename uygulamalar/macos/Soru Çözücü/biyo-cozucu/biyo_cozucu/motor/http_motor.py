"""OpenAI-uyumlu HTTP ucu üzerinden üretim (mlx_lm.server, Ollama, CLI Proxy…).

SDK bağımlılığı yok — saf urllib. Birden çok model adı verildiğinde yalnız
geçici hatalarda (429/kota/5xx/zaman aşımı) sonrakine düşer; kalıcı hatalarda
hemen yükseltir, çünkü sessiz düşme yanlış modelle sonuç üretmeye yol açar.
"""

from __future__ import annotations

import json
import os
import queue
import threading
import urllib.error
import urllib.request

from .temel import MotorHatasi

VARSAYILAN_URL = "http://127.0.0.1:8080/v1"

_GECICI_ISARETLER = (
    "http 429", "quota", "capacity", "rate limit",
    "http 500", "http 502", "http 503", "http 504",
    "upstream", "timeout", "zaman aş", "connection", "bağlantı",
)


def _gecici_mi(hata: str) -> bool:
    alcak = hata.casefold()
    return any(isaret in alcak for isaret in _GECICI_ISARETLER)


class HttpMotor:
    """OpenAI `/chat/completions` uyumlu uç."""

    def __init__(
        self,
        url: str | None = None,
        modeller: list[str] | None = None,
        *,
        anahtar: str | None = None,
        zaman_asimi: float = 180.0,
    ):
        self.url = (url or os.environ.get("BIYO_MOTOR_URL", VARSAYILAN_URL)).rstrip("/")
        ham = modeller or [
            m.strip()
            for m in os.environ.get("BIYO_MOTOR_MODELLER", "yerel").split(",")
            if m.strip()
        ]
        self.modeller = list(dict.fromkeys(ham)) or ["yerel"]
        self.anahtar = anahtar if anahtar is not None else os.environ.get("BIYO_MOTOR_ANAHTARI", "")
        self.zaman_asimi = zaman_asimi
        self.ad = f"{self.modeller[0]}@{self.url}"

    def _istek(self, govde: dict) -> dict:
        veri = json.dumps(govde, ensure_ascii=False).encode("utf-8")
        basliklar = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.anahtar:
            basliklar["Authorization"] = f"Bearer {self.anahtar}"
        istek = urllib.request.Request(
            f"{self.url}/chat/completions", data=veri, headers=basliklar
        )
        try:
            with urllib.request.urlopen(istek, timeout=self.zaman_asimi) as yanit:
                return json.loads(yanit.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            try:
                ayrinti = exc.read().decode("utf-8", errors="replace")[-400:]
            finally:
                exc.close()  # HTTPError bir yanıt nesnesidir; kapatılmazsa fd sızar
            raise MotorHatasi(f"HTTP {exc.code}: {ayrinti or exc.reason}") from exc
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            raise MotorHatasi(f"Motor bağlantısı kurulamadı: {exc}") from exc

    def uret(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ) -> str:
        son_hata: MotorHatasi | None = None
        for model_adi in self.modeller:
            try:
                yanit = self._istek(
                    {
                        "model": model_adi,
                        "stream": False,
                        "temperature": float(sicaklik),
                        "max_tokens": int(azami_token),
                        "messages": mesajlar,
                    }
                )
            except MotorHatasi as exc:
                son_hata = exc
                if not _gecici_mi(str(exc)):
                    raise
                continue
            try:
                return yanit["choices"][0]["message"]["content"] or ""
            except (KeyError, IndexError, TypeError) as exc:
                raise MotorHatasi(f"Beklenmeyen yanıt biçimi: {yanit}") from exc
        raise MotorHatasi(f"Hiçbir model yanıt vermedi: {son_hata}")

    def _akis_istegi(self, govde: dict):
        """SSE gövdesini satır satır verir; bağlantıyı çağıran kapatır."""
        veri = json.dumps(govde, ensure_ascii=False).encode("utf-8")
        basliklar = {"Content-Type": "application/json", "Accept": "text/event-stream"}
        if self.anahtar:
            basliklar["Authorization"] = f"Bearer {self.anahtar}"
        istek = urllib.request.Request(
            f"{self.url}/chat/completions", data=veri, headers=basliklar
        )
        try:
            yanit = urllib.request.urlopen(istek, timeout=self.zaman_asimi)
        except urllib.error.HTTPError as exc:
            try:
                ayrinti = exc.read().decode("utf-8", errors="replace")[-400:]
            finally:
                exc.close()  # HTTPError bir yanıt nesnesidir; kapatılmazsa fd sızar
            raise MotorHatasi(f"HTTP {exc.code}: {ayrinti or exc.reason}") from exc
        except (OSError, urllib.error.URLError) as exc:
            raise MotorHatasi(f"Motor bağlantısı kurulamadı: {exc}") from exc
        try:
            for ham in yanit:
                satir = ham.decode("utf-8", errors="replace").strip()
                if satir.startswith("data:"):
                    yield satir[5:].strip()
        finally:
            yanit.close()

    def uret_akis(
        self,
        mesajlar: list[dict[str, str]],
        *,
        sicaklik: float = 0.2,
        azami_token: int = 1536,
    ):
        """Akışta model düşürme (fallback) YOK.

        `uret()` geçici hatada sıradaki modele geçebiliyor çünkü henüz hiç
        çıktı verilmemiştir. Akışta ilk parça tüketiciye ulaştıktan sonra
        model değiştirmek iki modelin metnini birbirine karıştırırdı.

        MlxMotor'daki gibi işçi iş parçacığı deseni: tüketici akışı yarıda
        bırakırsa bu generator'ın `finally`'si çalışmayabilir (Starlette
        istemci kopunca üreticiyi kapatmıyor); işçi kendi başına bitip
        upstream bağlantısını kapatır, yoksa soket ve uzak üretim asılı kalırdı.
        """
        kuyruk: queue.Queue = queue.Queue()
        bitti = object()
        govde = {
            "model": self.modeller[0],
            "stream": True,
            "temperature": float(sicaklik),
            "max_tokens": int(azami_token),
            "messages": mesajlar,
        }

        def oku_calis() -> None:
            gorulen = 0
            try:
                for veri in self._akis_istegi(govde):
                    if veri == "[DONE]":
                        break
                    try:
                        paket = json.loads(veri)
                    except json.JSONDecodeError:
                        continue  # yorum/keepalive satırı
                    try:
                        parca = paket["choices"][0]["delta"].get("content")
                    except (KeyError, IndexError, TypeError):
                        continue
                    if parca:
                        gorulen += 1
                        kuyruk.put(parca)
                if gorulen == 0:
                    # Uç `stream=True`'yu yok sayıp düz JSON döndürmüş olabilir.
                    # Sessizce boş metin vermek, çözücüde "model yalnız düşünce
                    # üretti" gibi yanlış bir teşhise dönüşüyordu.
                    kuyruk.put(
                        MotorHatasi(
                            "Uç akış (stream) yanıtı vermedi; "
                            "BIYO_MOTOR_URL akışı desteklemiyor olabilir."
                        )
                    )
            except BaseException as exc:  # noqa: BLE001
                kuyruk.put(
                    exc if isinstance(exc, MotorHatasi)
                    else MotorHatasi(f"Akışlı üretim başarısız: {exc}")
                )
            finally:
                kuyruk.put(bitti)

        threading.Thread(
            target=oku_calis, name="biyo-http-akis", daemon=True
        ).start()

        while True:
            oge = kuyruk.get()
            if oge is bitti:
                return
            if isinstance(oge, BaseException):
                raise oge
            yield oge

    def hazir_mi(self) -> bool:
        """Uç ayakta mı — arayüzde durum göstermek için."""
        try:
            istek = urllib.request.Request(f"{self.url}/models")
            if self.anahtar:
                istek.add_header("Authorization", f"Bearer {self.anahtar}")
            with urllib.request.urlopen(istek, timeout=3.0):
                return True
        except Exception:  # noqa: BLE001
            return False
