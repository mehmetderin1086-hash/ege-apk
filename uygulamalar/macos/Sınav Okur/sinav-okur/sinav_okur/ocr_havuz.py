"""Sayfa OCR alt-süreçleri için sıcak motor havuzu.

Her motor için ``ocr_engine_runner.py --sunucu`` süreci tembel başlatılır ve
istekler satır-JSON ile aynı sürece gider; model bir kez yüklenir. Zaman aşımı
veya çökmede süreç (grubuyla birlikte — Surya'nın llama-server'ı gibi torunlar
dahil) öldürülür, ``HavuzHatasi`` yükselir ve çağıran mevcut tek-atımlık
``subprocess.run`` yoluna düşer — doğruluk davranışı değişmez.
``SINAV_OKUR_SICAK_HAVUZ=1`` ile açılır (ocr.py tarafında).

Kilit düzeni: ``_genel_kilit`` yalnız kayıt haritasını korur, ``kayit.kilit``
yalnız o sürecin borusunu korur ve ikisi ASLA iç içe alınmaz (ölü kilit
riski). Hata temizliği kayıt kimliğiyle yapılır: bu istek sırasında başka
bir iş parçacığı aynı motoru tazelediyse yeni süreç yanlışlıkla düşürülmez.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path


class HavuzHatasi(RuntimeError):
    """Havuz yolu kullanılamadı; çağıran tek-atımlık yola düşmeli."""


# Bellek büyümesine karşı süreç bu kadar istekten sonra tazelenir.
VARSAYILAN_AZAMI_ISTEK = 40


@dataclass
class _MotorSureci:
    surec: subprocess.Popen
    kilit: threading.Lock = field(default_factory=threading.Lock)
    istek_sayisi: int = 0


def _grubu_oldur(surec: subprocess.Popen) -> None:
    """Runner'ı süreç grubuyla birlikte kapatır (torun sızıntısı olmasın)."""
    if surec.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(surec.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        surec.terminate()
    try:
        surec.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(surec.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            surec.kill()
        try:
            surec.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass


class MotorHavuzu:
    def __init__(self, azami_istek: int = VARSAYILAN_AZAMI_ISTEK):
        self._azami_istek = azami_istek
        self._motorlar: dict[str, _MotorSureci] = {}
        self._genel_kilit = threading.Lock()

    def _baslat(self, motor: str, komut: list[str], ortam: dict | None) -> _MotorSureci:
        try:
            surec = subprocess.Popen(
                komut,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                # stderr birikip boru tamponunu doldurursa süreç kilitlenir;
                # model kütüphanelerinin gürültüsü sessizce yutulur.
                stderr=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
                env=ortam,
                # Kendi süreç grubu: torunlar (llama-server) grupça öldürülür.
                start_new_session=True,
            )
        except OSError as exc:
            raise HavuzHatasi(f"{motor} sunucusu başlatılamadı: {exc}") from exc
        return _MotorSureci(surec=surec)

    def _kayit_dusur(self, motor: str, kayit: _MotorSureci | None = None) -> None:
        """Kaydı haritadan çıkarıp sürecini öldürür.

        ``kayit`` verilirse yalnız hâlâ o kayıt haritadaysa düşürülür —
        aradaki bir tazeleme yeni süreç başlattıysa ona dokunulmaz.
        """
        with self._genel_kilit:
            mevcut = self._motorlar.get(motor)
            if mevcut is None or (kayit is not None and mevcut is not kayit):
                hedef = kayit
            else:
                hedef = self._motorlar.pop(motor)
        if hedef is not None:
            _grubu_oldur(hedef.surec)

    def _kayit_getir(
        self, motor: str, komut: list[str], ortam: dict | None
    ) -> _MotorSureci:
        with self._genel_kilit:
            kayit = self._motorlar.get(motor)
            if kayit is not None and (
                kayit.istek_sayisi >= self._azami_istek
                or kayit.surec.poll() is not None
            ):
                self._motorlar.pop(motor)
                eski = kayit
                kayit = None
            else:
                eski = None
            if kayit is None:
                kayit = self._baslat(motor, komut, ortam)
                self._motorlar[motor] = kayit
        if eski is not None:
            _grubu_oldur(eski.surec)
        return kayit

    def oku(
        self,
        motor: str,
        komut: list[str],
        ortam: dict | None,
        gorsel: Path,
        timeout: float,
    ) -> dict:
        """Tek istek gönderir; yanıt JSON sözlüğünü döndürür.

        Motor başına kilit: sayfa hattı zaten sıralıdır, eşzamanlı iki istek
        aynı sürece karışmaz.
        """
        kayit = self._kayit_getir(motor, komut, ortam)
        hata: str | None = None
        satir = ""
        with kayit.kilit:
            surec = kayit.surec
            try:
                surec.stdin.write(
                    json.dumps({"gorsel": str(gorsel)}, ensure_ascii=False) + "\n"
                )
                surec.stdin.flush()
            except (OSError, ValueError) as exc:
                hata = f"{motor} sunucusuna yazılamadı: {exc}"
            else:
                okunan = self._satir_oku(surec, timeout)
                if okunan is None:
                    hata = f"{motor} sunucusu {timeout} sn içinde yanıt vermedi."
                elif not okunan:
                    hata = f"{motor} sunucusu beklenmedik şekilde kapandı."
                else:
                    satir = okunan
                    kayit.istek_sayisi += 1
        if hata is not None:
            self._kayit_dusur(motor, kayit)
            raise HavuzHatasi(hata)
        try:
            return json.loads(satir)
        except ValueError as exc:
            self._kayit_dusur(motor, kayit)
            raise HavuzHatasi(f"{motor} sunucusundan bozuk yanıt: {exc}") from exc

    @staticmethod
    def _satir_oku(surec: subprocess.Popen, timeout: float) -> str | None:
        """Bir yanıt satırını zaman aşımıyla okur; aşımda None döner."""
        sonuc: dict[str, str] = {}

        def hedef() -> None:
            try:
                sonuc["satir"] = surec.stdout.readline()
            except (OSError, ValueError):
                sonuc["satir"] = ""

        okuyucu = threading.Thread(target=hedef, daemon=True)
        okuyucu.start()
        okuyucu.join(timeout)
        if okuyucu.is_alive():
            return None
        return sonuc.get("satir", "").strip()

    def kapat(self) -> None:
        """Tüm süreçleri nazikçe, gerekirse grupça zorla kapatır."""
        with self._genel_kilit:
            kayitlar = list(self._motorlar.items())
            self._motorlar.clear()
        for _, kayit in kayitlar:
            try:
                kayit.surec.stdin.write('{"kapat": true}\n')
                kayit.surec.stdin.flush()
            except (OSError, ValueError):
                pass
        for _, kayit in kayitlar:
            # Kapat mesajını işleyip kendi kendine çıkması için kısa fırsat;
            # çıkmazsa grup öldürülür.
            try:
                kayit.surec.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            _grubu_oldur(kayit.surec)
