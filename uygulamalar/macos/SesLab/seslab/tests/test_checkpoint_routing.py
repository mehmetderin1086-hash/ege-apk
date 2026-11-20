"""Sese-göre fine-tuned XTTS checkpoint yönlendirmesinin birim testleri.

İki fine-tuned sesin (ör. Emel, Murat) ayrı model.pth'leriyle bir arada
yaşayabilmesi için: her ses meta.json'unda `checkpoint_dir` bildirir; sentez
zinciri bunu çözüp XTTS motoruna geçirir, motor da ses değişince worker havuzunu
o checkpoint ile yeniden doğurur. Testler worker SPAWN ETMEDEN yalnız çözümleme
mantığını doğrular.
"""
import json

import numpy as np

from app.config import DATA_DIR, VOICES_DIR
from app.core import synth, voices
from app.engines import xtts


def _make_voice(voice_id: str, name: str, checkpoint_dir=None) -> None:
    vdir = VOICES_DIR / voice_id
    vdir.mkdir(parents=True, exist_ok=True)
    (vdir / "ref.wav").write_bytes(b"RIFF\x00\x00\x00\x00WAVE")  # varlık yeterli
    meta = {"id": voice_id, "name": name, "created_at": 1.0}
    if checkpoint_dir is not None:
        meta["checkpoint_dir"] = checkpoint_dir
    (vdir / "meta.json").write_text(json.dumps(meta), encoding="utf-8")


def _make_checkpoint(rel_name: str) -> str:
    d = DATA_DIR / "models" / rel_name
    d.mkdir(parents=True, exist_ok=True)
    (d / "model.pth").write_bytes(b"\x00")  # sadece varlık kontrol edilir
    return rel_name


def test_voices_resolve_checkpoint_present(tmp_path):
    _make_checkpoint("xtts_murat_ft")
    _make_voice("aaaaaaaaaaaa", "Murat", checkpoint_dir="xtts_murat_ft")
    got = voices.resolve_checkpoint_dir("aaaaaaaaaaaa")
    assert got == str(DATA_DIR / "models" / "xtts_murat_ft")


def test_voices_resolve_checkpoint_missing_field():
    _make_voice("bbbbbbbbbbbb", "Klon", checkpoint_dir=None)
    assert voices.resolve_checkpoint_dir("bbbbbbbbbbbb") is None


def test_voices_resolve_checkpoint_dir_without_model_pth():
    # checkpoint_dir bildirilmiş ama dizinde model.pth yok → None (gürbüz)
    _make_voice("cccccccccccc", "Eksik", checkpoint_dir="yok_boyle_model")
    assert voices.resolve_checkpoint_dir("cccccccccccc") is None


def test_voices_resolve_checkpoint_default_is_none():
    assert voices.resolve_checkpoint_dir(None) is None
    assert voices.resolve_checkpoint_dir("default") is None


def test_synth_resolve_checkpoint_ignored_for_chatterbox():
    _make_checkpoint("xtts_murat_ft")
    _make_voice("dddddddddddd", "Murat", checkpoint_dir="xtts_murat_ft")
    # Chatterbox fine-tune kullanmaz → her zaman None
    assert synth.resolve_checkpoint_dir("dddddddddddd", "tr", "chatterbox") is None


def test_synth_resolve_checkpoint_explicit_voice_xtts():
    _make_checkpoint("xtts_murat_ft")
    _make_voice("eeeeeeeeeeee", "Murat", checkpoint_dir="xtts_murat_ft")
    got = synth.resolve_checkpoint_dir("eeeeeeeeeeee", "tr", "xtts")
    assert got == str(DATA_DIR / "models" / "xtts_murat_ft")


def test_xtts_resolve_checkpoint_precedence():
    # Açık argüman geçerli model.pth içeriyorsa kazanır
    _make_checkpoint("xtts_murat_ft")
    explicit = str(DATA_DIR / "models" / "xtts_murat_ft")
    assert xtts._resolve_checkpoint(explicit) == explicit
    # Geçersiz açık argüman + env/FINETUNE yoksa None
    assert xtts._resolve_checkpoint(str(DATA_DIR / "models" / "yok")) is None


def test_worker_env_none_clears_checkpoint(monkeypatch):
    # Çözülmüş None → env'de checkpoint anahtarı BULUNMAMALI (taban model)
    monkeypatch.setenv("SESLAB_XTTS_CHECKPOINT_DIR", "/eski/deger")
    env = xtts._worker_env(None)
    assert "SESLAB_XTTS_CHECKPOINT_DIR" not in env
    # Çözülmüş somut dizin → env'e AYNEN konur
    env2 = xtts._worker_env("/somut/dizin")
    assert env2["SESLAB_XTTS_CHECKPOINT_DIR"] == "/somut/dizin"


def test_generate_once_prepares_voice_checkpoint_before_first_load(monkeypatch):
    """İlk Murat isteği manager'a checkpoint ile gitmeli (çift yükleme yok)."""
    seen = {}

    class FakeEngine:
        sr = 24000

        def generate(self, text, **kwargs):
            seen["generate_checkpoint"] = kwargs["checkpoint_dir"]
            return np.zeros(240, dtype=np.float32)

    def fake_ensure(name, checkpoint_dir=None):
        seen["ensure"] = (name, checkpoint_dir)
        return FakeEngine()

    monkeypatch.setattr(synth.manager, "ensure", fake_ensure)
    monkeypatch.setattr(synth.manager, "watchdog", lambda: None)

    checkpoint = "/models/xtts_murat_ft"
    audio, sr = synth._generate_once(
        "Merhaba dünya", "tr", "/voices/murat.wav",
        0.5, 0.5, 0.8, 1.0, "xtts", checkpoint,
    )

    assert seen["ensure"] == ("xtts", checkpoint)
    assert seen["generate_checkpoint"] == checkpoint
    assert sr == 24000
    assert len(audio) == 240


class _SahteWorker:
    """Worker taklidi: sıcak takas cevabını ve respawn sayısını izler."""

    def __init__(self, cevap, idx: int = 0, canli: bool = True):
        import threading

        self.idx = idx
        self.lock = threading.Lock()
        self.checkpoint_dir = None
        self._cevap = cevap          # dict, Exception ya da None
        self._canli = canli
        self.istekler: list[dict] = []
        self.respawn_sayisi = 0

    def alive(self) -> bool:
        return self._canli

    def request(self, req: dict) -> dict:
        self.istekler.append(req)
        if isinstance(self._cevap, Exception):
            raise self._cevap
        return self._cevap or {}

    def respawn(self) -> None:
        self.respawn_sayisi += 1


def _motor(worker) -> "xtts.XTTSEngine":
    engine = xtts.XTTSEngine()
    engine._workers = [worker]
    engine._active_checkpoint = "/eski/ckpt"
    return engine


def test_sicak_takas_respawn_yapmaz():
    """Üç ses aynı taban modeli paylaşır; süreç yeniden doğmamalı."""
    w = _SahteWorker({"ok": True, "swapped": "/yeni/ckpt"})
    _motor(w)._swap_checkpoint("/yeni/ckpt")
    assert w.respawn_sayisi == 0
    assert w.istekler == [{"cmd": "swap", "checkpoint_dir": "/yeni/ckpt"}]


def test_takas_basarisizsa_respawn_edilir():
    """Takas reddedilirse yavaş ama doğru yola düşülmeli.

    Sessizce eski ağırlıklarda kalmak, podcast'in YANLIŞ SESLE konuşması demek.
    """
    for cevap in ({"ok": False, "error": "checkpoint yüklenemedi"}, {}, RuntimeError("boru koptu")):
        w = _SahteWorker(cevap)
        _motor(w)._swap_checkpoint("/yeni/ckpt")
        assert w.respawn_sayisi == 1, f"{cevap!r} için respawn yapılmadı"


def test_olu_worker_takas_denenmeden_respawn_edilir():
    w = _SahteWorker({"ok": True}, canli=False)
    _motor(w)._swap_checkpoint("/yeni/ckpt")
    assert w.istekler == []
    assert w.respawn_sayisi == 1


def test_takas_sonrasi_aktif_checkpoint_guncellenir():
    w = _SahteWorker({"ok": True})
    engine = _motor(w)
    engine._swap_checkpoint("/yeni/ckpt")
    assert engine._active_checkpoint == "/yeni/ckpt"
    assert w.checkpoint_dir == "/yeni/ckpt"
