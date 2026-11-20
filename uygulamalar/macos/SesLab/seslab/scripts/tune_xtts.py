"""XTTS-v2 üretim parametresi taraması — STT geri beslemeli nesnel puanlama.

Akış: her yapılandırma × her test cümlesi → XTTS worker'da üret →
mlx-whisper ile deşifre et → kaynakla benzerlik + artefakt cezaları → puan.

Kullanım:
    uv run python scripts/tune_xtts.py --stage 0   # ham vs yoğun referans (enhance_ref)
    uv run python scripts/tune_xtts.py --stage 1
    uv run python scripts/tune_xtts.py --stage 2 --temperature 0.65
Çıktılar: data/outputs/tune/<etiket>_<cümle>.wav + data/outputs/tune/results_stageN.json
"""
from __future__ import annotations

import argparse
import difflib
import itertools
import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.audio.io import decode_audio  # noqa: E402
from app.config import BASE_DIR, VOICES_DIR  # noqa: E402
from app.core.text.normalize_tr import normalize_tr  # noqa: E402

TUNE_DIR = BASE_DIR / "data" / "outputs" / "tune"
VENV_PY = BASE_DIR / ".venv-xtts" / "bin" / "python"
WORKER = BASE_DIR / "app" / "engines" / "xtts_worker.py"

# Çeşitlilik: düz anlatı, soru vurgusu, yumuşak g, uzun cümle, özel ad, sayı sözcükleri
CORPUS = [
    ("duz", "Bugün hava çok güzel; sahilde uzun bir yürüyüş yaptık."),
    ("teknik", "Yapay zekâ teknolojileri hayatımızın her alanına giriyor."),
    ("saat", "Yarın saat on dört otuzda toplantımız var, lütfen geç kalma."),
    ("yumusakg", "Ağaçların gölgesinde oturup soğuk bir ayran içtik."),
    ("soru", "Bu projeyi başarıyla tamamlayabilecek miyiz?"),
    ("ozelad", "Türkiye'nin en kalabalık şehri İstanbul, iki kıtayı birbirine bağlar."),
]


def norm_text(s: str) -> str:
    # Whisper rakamlaştırabilir ("on dört otuzda" → "14.30'da"); haksız ceza
    # olmasın diye transkript önce kendi normalizasyonumuzdan geçer.
    s = normalize_tr(s)[0]
    s = s.lower().replace("â", "a").replace("î", "i").replace("û", "u")
    return re.sub(r"[^a-zçğıöşü ]", "", s).strip()


def has_word_loop(text: str, n: int = 3) -> bool:
    """Aynı sözcüğün n+ kez art arda tekrarı → GPT döngü artefaktı."""
    words = norm_text(text).split()
    run = 1
    for a, b in zip(words, words[1:]):
        run = run + 1 if a == b else 1
        if run >= n:
            return True
    return False


def score_one(source: str, transcript: str, duration_s: float) -> dict:
    sim = difflib.SequenceMatcher(None, norm_text(source), norm_text(transcript)).ratio()
    rate = len(source) / duration_s if duration_s > 0 else 0  # karakter/sn
    penalties = 0.0
    flags = []
    if has_word_loop(transcript):
        penalties += 0.30
        flags.append("döngü")
    if rate < 8:
        penalties += 0.15
        flags.append("çok-yavaş/uzamış")
    if rate > 22:
        penalties += 0.15
        flags.append("çok-hızlı/kırpılmış")
    if len(norm_text(transcript)) < len(norm_text(source)) * 0.6:
        penalties += 0.20
        flags.append("eksik")
    return {
        "similarity": round(sim, 4),
        "rate_cps": round(rate, 1),
        "score": round(max(0.0, sim - penalties), 4),
        "flags": flags,
        "transcript": transcript.strip(),
    }


class Worker:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(VENV_PY), "-u", str(WORKER)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=open(TUNE_DIR / "worker.log", "a"),
            cwd=str(BASE_DIR), text=True,
        )
        ready = json.loads(self.proc.stdout.readline())
        assert ready.get("ready"), "worker başlatılamadı"
        print(f"worker hazır ({ready['device']})", flush=True)

    def generate(self, text: str, out_path: Path, ref_wav: str | None, params: dict) -> float:
        req = {"text": text, "language": "tr", "ref_wav": ref_wav,
               "out_path": str(out_path), "speed": 1.0, "params": params}
        self.proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        resp = json.loads(self.proc.stdout.readline())
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        return resp["duration_s"]

    def close(self) -> None:
        self.proc.stdin.close()
        self.proc.terminate()


def transcribe(path: Path) -> str:
    import mlx_whisper

    audio, _ = decode_audio(path.read_bytes(), target_sr=16000)
    result = mlx_whisper.transcribe(
        audio, path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
        language="tr", word_timestamps=False,
    )
    return result["text"]


def run_configs(configs: list[tuple], ref_wav: str | None, stage: int) -> None:
    """configs: (etiket, params) veya (etiket, params, ref_override) demetleri."""
    TUNE_DIR.mkdir(parents=True, exist_ok=True)
    worker = Worker()
    results = []
    try:
        for cfg in configs:
            label, params, cfg_ref = cfg if len(cfg) == 3 else (*cfg, None)
            per_sentence = []
            t0 = time.time()
            for key, sentence in CORPUS:
                out = TUNE_DIR / f"{label}_{key}.wav"
                try:
                    dur = worker.generate(sentence, out, cfg_ref or ref_wav, params)
                    entry = score_one(sentence, transcribe(out), dur)
                except Exception as e:  # noqa: BLE001
                    entry = {"score": 0.0, "similarity": 0.0, "flags": [f"HATA: {e}"],
                             "rate_cps": 0, "transcript": ""}
                entry["sentence"] = key
                per_sentence.append(entry)
                print(f"  {label}/{key}: puan={entry['score']} "
                      f"{'⚑' + ','.join(entry['flags']) if entry['flags'] else ''}",
                      flush=True)
            mean = round(sum(e["score"] for e in per_sentence) / len(per_sentence), 4)
            results.append({"label": label, "params": params, "mean_score": mean,
                            "elapsed_s": round(time.time() - t0, 1),
                            "sentences": per_sentence})
            print(f"► {label}: ORTALAMA={mean} ({results[-1]['elapsed_s']} sn)", flush=True)
    finally:
        worker.close()

    results.sort(key=lambda r: -r["mean_score"])
    out_file = TUNE_DIR / f"results_stage{stage}.json"
    out_file.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print("\n=== SIRALAMA ===")
    for r in results:
        print(f"  {r['mean_score']:.4f}  {r['label']}  {r['params']}")
    print(f"\nSonuçlar: {out_file}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=None,
                        help="2. aşamada sabitlenecek en iyi sıcaklık")
    parser.add_argument("--repeats", type=int, default=1,
                        help="cümle başına örnekleme tekrarı (gürültü azaltma)")
    parser.add_argument("--voice-ref", default="auto",
                        help="klon referans wav yolu | auto | none")
    args = parser.parse_args()

    ref_wav: str | None
    if args.voice_ref == "none":
        ref_wav = None
    elif args.voice_ref == "auto":
        refs = sorted(VOICES_DIR.glob("*/ref.wav"))
        ref_wav = str(refs[0]) if refs else None
    else:
        ref_wav = args.voice_ref
    print(f"referans: {ref_wav or 'yerleşik konuşmacı'}")

    if args.stage == 0:
        # Aşama 0: ham referans vs yoğunlaştırılmış referans düellosu
        # (paket varsayılan paramlarla; önce scripts/enhance_ref.py çalıştırın)
        assert ref_wav, "aşama 0 için klon referansı gerekli (--voice-ref)"
        vdir = Path(ref_wav).parent
        ham = vdir / "ref_raw.wav"
        if not ham.exists():
            ham = vdir / "ref.wav"
        enh = vdir / "ref_enhanced.wav"
        assert enh.exists(), f"bulunamadı: {enh} — önce scripts/enhance_ref.py"
        configs = [("ham", {}, str(ham)), ("enh", {}, str(enh))]
    elif args.stage == 1:
        # Aşama 1: yalnız sıcaklık taraması (XTTS varsayılanı ~0.75 civarı)
        configs = [
            (f"t{t}", {"temperature": t, "repetition_penalty": 5.0})
            for t in (0.55, 0.65, 0.75, 0.85)
        ]
        configs.insert(0, ("varsayilan", {}))  # taban çizgisi: paket varsayılanları
    elif args.stage == 2:
        # Aşama 2: gerçek varsayılanların (t=0.75, rp=10.0, top_p=0.85)
        # ETRAFINDA arama — aşama 1'de varsayılan tüm rp=5.0 varyantlarını yendi
        configs = [
            ("varsayilan", {}),
            ("t0.65_r10", {"temperature": 0.65, "repetition_penalty": 10.0}),
            ("t0.75_r10_p0.80",
             {"temperature": 0.75, "repetition_penalty": 10.0, "top_p": 0.80}),
            ("t0.60_r10_p0.80",
             {"temperature": 0.60, "repetition_penalty": 10.0, "top_p": 0.80}),
            ("t0.75_r7", {"temperature": 0.75, "repetition_penalty": 7.0}),
        ]
    else:
        # Aşama 3 (final): en iyi iki adayın tekrarlı düellosu — --repeats ile
        assert args.temperature is not None, "--temperature verin"
        configs = [
            ("varsayilan", {}),
            (f"aday_t{args.temperature}",
             {"temperature": args.temperature, "repetition_penalty": 10.0,
              "top_p": 0.80}),
        ]
    if args.repeats > 1:
        global CORPUS
        CORPUS = [
            (f"{key}_{i}", sentence)
            for key, sentence in CORPUS
            for i in range(args.repeats)
        ]
    run_configs(configs, ref_wav, args.stage)


if __name__ == "__main__":
    main()
