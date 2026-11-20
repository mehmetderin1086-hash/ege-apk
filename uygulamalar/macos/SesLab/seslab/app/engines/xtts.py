"""XTTS-v2 motoru — izole .venv-xtts'te çalışan alt süreç HAVUZUNA köprü.

Neden alt süreç? coqui-tts, chatterbox'ın pinlediği transformers==5.2.0 ile
aynı ortamda güvenle çalışamaz; ayrıca CPML lisansı (yalnız ticari olmayan
kullanım) gereği motor açıkça ayrı tutulur ve UI'da rozetle işaretlenir.

Neden havuz? İki worker alt süreci MPS'i paylaşarak proje sentezini
hızlandırır (STT denetimi ana süreçte zaten paralel). İkinci worker yalnızca
yeterli boş RAM varsa açılır (adaptif).

BaseEngine arayüzünü uygular: manager'ın "en fazla 1 ağır motor" politikası
XTTS'i de kapsar (yüklenince Chatterbox boşaltılır, tersi de).
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
import threading
import time
import uuid
from pathlib import Path

import numpy as np
import psutil

from app.config import BASE_DIR, DATA_DIR, DEFAULT_LANGUAGE

from .base import BaseEngine

log = logging.getLogger("seslab.engines.xtts")

# Windows paketinde SESLAB_XTTS_PY gömülü ikinci Python'a işaret eder;
# macOS'ta izole .venv-xtts korunur.
VENV_PY = Path(os.environ.get("SESLAB_XTTS_PY") or (BASE_DIR / ".venv-xtts" / "bin" / "python"))
WORKER = BASE_DIR / "app" / "engines" / "xtts_worker.py"
WORKER_LOG = DATA_DIR / "xtts_worker.log"

# Fine-tuned model için yerleşik konum. Kullanıcı Colab'da eğitilen zip'i
# buraya açınca (model.pth + config.json + vocab.json) SesLab onu kendiliğinden
# kullanır; env SESLAB_XTTS_CHECKPOINT_DIR elle geçersiz kılabilir.
FINETUNE_DIR = DATA_DIR / "models" / "xtts_emel_ft"


def _resolve_checkpoint(checkpoint_dir: str | None = None) -> str | None:
    """Etkin fine-tuned checkpoint dizinini çözer (öncelik sırasıyla).

    Öncelik: açık `checkpoint_dir` (sese özgü) > env SESLAB_XTTS_CHECKPOINT_DIR
    (elle geçersiz kılma) > yerleşik FINETUNE_DIR (Emel, geriye dönük uyum).
    Yalnızca `model.pth` içeren dizin geçerli sayılır; hiçbiri geçerli değilse
    None → worker taban XTTS-v2'yi yükler.
    """
    for cand in (checkpoint_dir, os.environ.get("SESLAB_XTTS_CHECKPOINT_DIR"), str(FINETUNE_DIR)):
        if cand and (Path(cand) / "model.pth").is_file():
            return str(cand)
    return None


def _worker_env(resolved_checkpoint: str | None) -> dict:
    """Worker alt süreci ortamı: ÇÖZÜLMÜŞ checkpoint'i env'e koyar.

    `resolved_checkpoint` zaten _resolve_checkpoint'ten geçmiş somut bir dizin
    (ya da taban için None) olmalı — burada yeniden çözülmez ki motorun "taban
    modeli kullan" kararı (None) yanlışlıkla varsayılana dönmesin.
    """
    env = os.environ.copy()
    if resolved_checkpoint:
        env["SESLAB_XTTS_CHECKPOINT_DIR"] = resolved_checkpoint
    else:
        env.pop("SESLAB_XTTS_CHECKPOINT_DIR", None)
    return env


def active_checkpoint_dir() -> str | None:
    """Varsayılan (ses seçilmemiş) fine-tuned checkpoint dizini — UI/log için."""
    return _resolve_checkpoint(None)

# İkinci worker için gereken asgari boş RAM. A/B testinde 6 GB eşiğiyle
# ikinci worker bellek baskısında sessizce öldürüldü (macOS jetsam) →
# eşik yükseltildi; ayrıca havuz kendini onarır (ölen worker yeniden doğar).
MIN_FREE_GB_FOR_SECOND = 8.0
MAX_WORKERS = 2

# XTTS-v2'nin desteklediği diller (Chatterbox listesinden farklıdır)
XTTS_LANGUAGES = {
    "ar", "cs", "de", "en", "es", "fr", "hi", "hu", "it", "ja",
    "ko", "nl", "pl", "pt", "ru", "tr", "zh-cn",
}


def _multiclip_refs(ref_wav_path: str | None) -> list[str] | None:
    """Sesin çok-klipli referans kümesini döndürür (varsa).

    Klon dizininde `clips/ref_*.wav` altında birden çok temiz klip tutulursa
    (kullanıcının uzun kaydından üretilmiş çeşitli parçalar) XTTS konuşmacı
    gömme vektörünü bunların ortalamasından kurar — tek 30 sn'lik klibe göre
    daha gürbüz ve kaynağa sadık tını. Yoksa None → tek klip yolu kullanılır.
    """
    if not ref_wav_path:
        return None
    clips_dir = Path(ref_wav_path).parent / "clips"
    if not clips_dir.is_dir():
        return None
    clips = sorted(str(p) for p in clips_dir.glob("ref_*.wav"))
    return clips or None


class _XTTSWorker:
    """Tek alt süreç: kendi kilidi ve stdin/stdout boru hattı.

    Bellek baskısında macOS süreci sessizce öldürebilir → respawn() ile
    yerinde yeniden doğar (kendini onaran havuz).
    """

    def __init__(self, idx: int, checkpoint_dir: str | None = None) -> None:
        self.idx = idx
        self.checkpoint_dir = checkpoint_dir   # bu worker'ın doğduğu ÇÖZÜLMÜŞ checkpoint
        self.lock = threading.Lock()
        self._spawn()

    def _spawn(self) -> None:
        WORKER_LOG.parent.mkdir(parents=True, exist_ok=True)
        ek_args: dict = {}
        if os.name == "nt":
            ek_args["creationflags"] = 0x08000000  # CREATE_NO_WINDOW — konsol açılmasın
        self.proc = subprocess.Popen(
            [str(VENV_PY), "-u", str(WORKER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open(WORKER_LOG, "a"),
            cwd=str(BASE_DIR),
            env=_worker_env(self.checkpoint_dir),   # sese özgü fine-tuned modeli worker'a geçir
            text=True,
            encoding="utf-8",
            **ek_args,
        )
        ready_line = self.proc.stdout.readline()  # model yüklenene dek bloklar
        try:
            ready = json.loads(ready_line)
        except (json.JSONDecodeError, TypeError):
            ready = {}
        if not ready.get("ready"):
            self.terminate()
            raise RuntimeError(
                f"XTTS worker-{self.idx} başlatılamadı (günlük: {WORKER_LOG})"
            )

    def alive(self) -> bool:
        return self.proc.poll() is None

    def respawn(self) -> None:
        """Ölen/desenkron worker'ı yerinde yeniden doğurur (kilit tutulmalı)."""
        self.terminate()
        self._spawn()

    def request(self, req: dict) -> dict:
        """Kilit ÇAĞIRAN tarafından tutulmuş olmalı."""
        self.proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        try:
            return json.loads(line)
        except (json.JSONDecodeError, TypeError):
            return {}

    def terminate(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
            self.proc.terminate()
            self.proc.wait(timeout=10)
        except Exception:  # noqa: BLE001
            self.proc.kill()


class XTTSEngine(BaseEngine):
    name = "xtts"
    est_mem_gb = 3.5
    heavy = True
    # Yeniden yükleme 30-60 sn kaybettirir → XTTS bellekte daha uzun kalır
    idle_timeout_s = float(os.environ.get("SESLAB_XTTS_IDLE_S", "1800"))

    sr: int = 24000  # XTTS-v2 çıkışı

    def __init__(self) -> None:
        super().__init__()
        self._workers: list[_XTTSWorker] = []
        self._sem: threading.Semaphore | None = None
        self._inflight = 0
        self._active_checkpoint: str | None = None  # havuzun doğduğu ÇÖZÜLMÜŞ checkpoint
        self._initial_checkpoint: str | None = None

    def prepare_initial_checkpoint(self, checkpoint_dir: str) -> None:
        """Henüz yüklenmemiş havuzu doğrudan istenen ses modeliyle başlat.

        EngineManager bunu ``load()`` öncesinde çağırır. Yüklü bir havuzda
        değişiklik yapmaz; o durumda ``generate()`` güvenli checkpoint takasını
        zaten yönetir.
        """
        resolved = _resolve_checkpoint(checkpoint_dir)
        with self.lock:
            if self._model is None:
                self._initial_checkpoint = resolved

    @staticmethod
    def available() -> bool:
        return VENV_PY.exists()

    @staticmethod
    def planned_pool_size() -> int:
        """Havuz boyutu.

        A/B ölçümü (2026-07-16, M4/16GB, 10 bölümlük proje, doğrulama açık):
        havuz=1 → 166 sn; havuz=2 → 535 sn (3.2× YAVAŞ — MPS çekişmesi +
        bellek baskısı). Bu donanımda auto=1 doğru varsayılandır; daha fazla
        RAM/GPU'lu makinelerde SESLAB_XTTS_WORKERS=2 ile zorlanabilir.
        """
        raw = os.environ.get("SESLAB_XTTS_WORKERS", "auto")
        if raw != "auto":
            try:
                return max(1, min(MAX_WORKERS, int(raw)))
            except ValueError:
                return 1
        return 1

    def busy(self) -> bool:
        return self._inflight > 0

    def _load(self) -> None:
        if not self.available():
            raise RuntimeError(
                "XTTS kurulu değil. Kurulum: uv venv .venv-xtts --python 3.11 && "
                "uv pip install --python .venv-xtts/bin/python "
                "'coqui-tts[codec]==0.27.5' 'transformers>=4.57,<5' "
                "'torch==2.8.0' 'torchaudio==2.8.0'"
            )
        # Sese özgü ilk istek varsa doğrudan o modeli yükle. Hazırlanmış değer
        # yoksa geriye dönük varsayılan (Emel/env/taban) çözümlemesine dön.
        resolved = self._initial_checkpoint or _resolve_checkpoint(None)
        self._initial_checkpoint = None
        log.info("XTTS ses modeli: %s", f"fine-tuned ({resolved})" if resolved else "taban XTTS-v2")
        n = self.planned_pool_size()
        self._workers = [_XTTSWorker(i, resolved) for i in range(n)]
        self._active_checkpoint = resolved
        self._sem = threading.Semaphore(n)
        self._model = self._workers  # is_loaded() işareti

    def _unload(self) -> None:
        for w in self._workers:
            w.terminate()
        self._workers = []
        self._sem = None

    @property
    def pool_size(self) -> int:
        return len(self._workers)

    def _acquire_worker(self) -> _XTTSWorker:
        """Semafor bir worker'ın boş olduğunu garantiler; boş olanı bul."""
        for w in self._workers:
            if w.lock.acquire(blocking=False):
                return w
        # Teorik olarak ulaşılmaz (semafor korur); emniyet: ilkini blokla
        self._workers[0].lock.acquire()
        return self._workers[0]

    def _swap_checkpoint(self, resolved: str | None) -> None:
        """Havuzu yeni (çözülmüş) checkpoint'e geçirir.

        self.lock TUTULMUŞ ve inflight==0 olmalı (hiçbir worker üretimde değil →
        worker kilitleri boşta).

        Önce SICAK TAKAS denenir: üç sesin hepsi aynı taban XTTS-v2'yi paylaşır,
        yalnız GPT ağırlıkları farklıdır, dolayısıyla süreci yeniden doğurmaya
        gerek yoktur. Ölçüldü (2026-08-06): respawn ~33 sn; üç sesli bir
        podcast'te iki takas + ilk yükleme, 7 dakikalık işin ~1,9 dakikasıydı.
        Takas herhangi bir nedenle başarısız olursa respawn'a düşülür — yanlış
        sesle konuşmaktansa yavaş olmak yeğdir.
        """
        log.info("XTTS checkpoint değişimi: %s → %s",
                 self._active_checkpoint or "taban", resolved or "taban")
        for w in self._workers:
            w.checkpoint_dir = resolved
            with w.lock:
                sicak = False
                if w.alive():
                    t0 = time.time()
                    try:
                        cevap = w.request({"cmd": "swap", "checkpoint_dir": resolved or ""})
                        sicak = bool(cevap.get("ok"))
                    except Exception:  # noqa: BLE001 — respawn zaten yedek yol
                        sicak = False
                    if sicak:
                        log.info("XTTS sıcak takas: worker-%d (%.1f sn)",
                                 w.idx, time.time() - t0)
                if not sicak:
                    log.info("XTTS sıcak takas başarısız; worker-%d yeniden doğuruluyor", w.idx)
                    w.respawn()
        self._active_checkpoint = resolved

    def generate(
        self,
        text: str,
        language: str = DEFAULT_LANGUAGE,
        ref_wav_path: str | None = None,
        speed: float = 1.0,
        exaggeration: float | None = None,  # Chatterbox'a özgü — yok sayılır
        cfg_weight: float | None = None,    # Chatterbox'a özgü — yok sayılır
        temperature: float | None = None,   # Chatterbox'a özgü — yok sayılır
        checkpoint_dir: str | None = None,  # sese özgü fine-tuned model (varsa)
    ) -> np.ndarray:
        from app.audio.io import read_wav

        if language not in XTTS_LANGUAGES:
            raise ValueError(
                f"XTTS bu dili desteklemiyor: {language}. "
                f"Desteklenenler: {', '.join(sorted(XTTS_LANGUAGES))}"
            )

        # Yüklü değilse hata; inflight sayacı boşta-boşaltmayı erteler.
        # Ses değişince (farklı fine-tuned checkpoint) havuzu yeniden doğur —
        # ancak hiçbir üretim uçuşta değilken (inflight==0), yoksa mevcut modeli
        # kullan (uygulama üretimleri tek kuyruktan geçirdiği için çakışma nadir).
        with self.lock:
            if self._model is None or self._sem is None:
                raise RuntimeError("Motor yüklü değil (önce load())")
            resolved = _resolve_checkpoint(checkpoint_dir)
            if resolved != self._active_checkpoint:
                if self._inflight == 0:
                    self._swap_checkpoint(resolved)
                else:
                    log.warning(
                        "XTTS checkpoint değişimi ertelendi (inflight=%d); "
                        "mevcut model kullanılıyor: %s",
                        self._inflight, self._active_checkpoint or "taban",
                    )
            self._inflight += 1

        out_path = DATA_DIR / "outputs" / f"_xtts_{uuid.uuid4().hex[:8]}.wav"
        request = {
            "text": text,
            "language": language,
            "out_path": str(out_path),
            "speed": speed,
        }
        # Çok-klipli referans varsa onu gönder (konuşmacı gömme ortalaması);
        # yoksa tek klibe düş.
        ref_wavs = _multiclip_refs(str(ref_wav_path) if ref_wav_path else None)
        if ref_wavs:
            request["ref_wavs"] = ref_wavs
        elif ref_wav_path:
            request["ref_wav"] = str(ref_wav_path)
        try:
            with self._sem:
                worker = self._acquire_worker()
                try:
                    response = worker.request(request)
                    # Boş yanıt = worker öldü (bellek baskısı) veya desenkron
                    # → yerinde yeniden doğur, isteği BİR kez tekrarla
                    if not response:
                        log.warning(
                            "XTTS worker-%d yanıtsız (canlı=%s) — yeniden doğuruluyor",
                            worker.idx, worker.alive(),
                        )
                        worker.respawn()
                        response = worker.request(request)
                finally:
                    worker.lock.release()
        finally:
            with self.lock:
                self._inflight -= 1
                self.gen_count += 1
                self.touch()

        if not response.get("ok"):
            raise RuntimeError(
                f"XTTS üretim hatası: {response.get('error', 'worker yanıt vermedi')} "
                f"(günlük: {WORKER_LOG})"
            )
        try:
            audio, sr = read_wav(out_path)
            self.sr = sr
            return audio
        finally:
            out_path.unlink(missing_ok=True)
