"""XTTS-v2 worker — İZOLE .venv-xtts içinde çalışır.

DİKKAT — LİSANS: XTTS-v2 ağırlıkları Coqui Public Model License (CPML)
kapsamındadır ve YALNIZCA TİCARİ OLMAYAN kullanıma izin verir.

Bu betik ana venv'e ASLA import edilmez; ana süreç onu .venv-xtts/bin/python
ile alt süreç olarak çalıştırır (transformers sürüm çakışması nedeniyle).

Protokol (satır başına bir JSON):
  hazır   → {"ready": true, "device": "mps|cpu"}
  istek   ← {"text", "language", "ref_wav": str|null,
             "ref_wavs": [str]|null, "out_path", "speed"}
  yanıt   → {"ok": true, "duration_s": f} | {"ok": false, "error": str}

Referans: `ref_wavs` verilirse ÇOK-KLİPLİ koşullandırma kullanılır — XTTS
konuşmacı gömme vektörünü klipler arası ortalar (gürbüz tını) ve GPT
koşullandırmasını kliplerin birleşiminden alır. Bu, tek 30 sn'lik klibe göre
daha kararlı ve kaynağa sadık ses verir (kullanıcının 11 dk'lık kaydından
üretilen 8 çeşitli klip). Tek `ref_wav` de desteklenir (geriye dönük uyum).

Sentez düşük-seviye `inference()` ile yapılır (yüksek-seviye tts_to_file
yerine): koşullandırma latent'leri referans kümesi başına BİR kez hesaplanıp
önbelleğe alınır → uzun projelerde/kitaplarda çok-klip ek maliyeti sıfırlanır.
Örnekleme parametreleri model config'inden aynen alınır (tts_to_file ile
birebir aynı davranış: temperature=0.75, repetition_penalty=5.0, top_k=50,
top_p=0.85 — Türkçede STT-taramalı doğrulanmış optimal varsayılan).
"""
import json
import os
import sys
import tempfile
import traceback

# Model indirme onayı (kişisel/ticari olmayan kullanım planda onaylandı)
os.environ.setdefault("COQUI_TOS_AGREED", "1")

MODEL_ID = "tts_models/multilingual/multi-dataset/xtts_v2"

# Üretim varsayılanları — STT geri beslemeli tarama ile doğrulandı
# (scripts/tune_xtts.py, 2026-07-16, 96 puanlanmış üretim / 3 aşama):
# Paket/config varsayılanları Türkçede denenen tüm varyantlarla istatistiksel
# olarak eşit veya daha iyi. Bilinçli boş; yeniden ayar gerekirse aynı betikle
# tarayın. Buraya konan anahtarlar inference() çağrısındaki config değerlerini
# EZER (ör. {"temperature": 0.7}).
DEFAULT_GEN_PARAMS: dict = {}

# Koşullandırma latent'leri referans kümesi (yol+mtime) başına önbelleğe alınır.
# Aynı ses için her parçada yeniden hesaplama önlenir (çok-klipte kritik).
_LATENT_CACHE: dict = {}


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _apply_finetuned(model, ckpt_dir: str | None = None) -> str | None:
    """Fine-tuned ağırlıkları CANLI modele yükler.

    Dizin `model.pth` (+ opsiyonel `config.json`/`vocab.json`) içermeli. Taban
    model TTS() ile yüklendikten SONRA GPT ağırlıkları bu checkpoint ile
    değiştirilir; tüm tesisat (config, konuşmacı yöneticisi, örnekleme
    parametreleri, ısınma yolu) korunur. Referans (Emel klipleri) yolu da
    değişmez — fine-tune + referans birlikte en yüksek sadakati verir.

    `ckpt_dir` verilmezse SESLAB_XTTS_CHECKPOINT_DIR'e bakılır (açılış yolu).
    Açıkça verildiğinde ses değişimi için sıcak takas olarak kullanılır.

    Geçersiz/eksikse SESSİZCE taban modelde kalır (gürbüzlük: indirilmemiş model
    yüzünden sentez hiç çökmesin). Dönüş: yüklenen dizin veya None.
    """
    if ckpt_dir is None:
        ckpt_dir = os.environ.get("SESLAB_XTTS_CHECKPOINT_DIR", "")
    ckpt_dir = (ckpt_dir or "").strip()
    if not ckpt_dir:
        return None
    model_pth = os.path.join(ckpt_dir, "model.pth")
    if not os.path.isfile(model_pth):
        _log(f"UYARI: fine-tuned checkpoint yok ({model_pth}); taban model kullanılıyor")
        return None
    vocab = os.path.join(ckpt_dir, "vocab.json")
    xtts = model.synthesizer.tts_model
    cfg = model.synthesizer.tts_config
    config_path = os.path.join(ckpt_dir, "config.json")
    # Bazı eğitim koşuları (özellikle özel mel-token sayısıyla eğitilenler)
    # taban XTTS mimarisinden farklı bir GPT çıkış katmanı üretir. Bu durumda
    # yalnız ağırlıkları taban nesneye bindirmek boyut uyuşmazlığı verir; kendi
    # eğitim config'iyle modeli yeniden kurmak gerekir.
    if os.path.isfile(config_path):
        from TTS.tts.configs.xtts_config import XttsConfig
        from TTS.tts.models.xtts import Xtts

        tuned_cfg = XttsConfig()
        tuned_cfg.load_json(config_path)
        if (
            tuned_cfg.model_args.gpt_num_audio_tokens
            != cfg.model_args.gpt_num_audio_tokens
        ):
            xtts = Xtts.init_from_config(tuned_cfg)
            cfg = tuned_cfg
            model.synthesizer.tts_model = xtts
            model.synthesizer.tts_config = cfg
            model.synthesizer.output_sample_rate = cfg.audio["output_sample_rate"]
    xtts.load_checkpoint(
        cfg,
        checkpoint_path=model_pth,
        vocab_path=vocab if os.path.isfile(vocab) else None,
        eval=True,
        strict=False,          # hifigan/konuşmacı-kodlayıcı anahtarları taban ile aynı; GPT değişir
        use_deepspeed=False,
    )
    _LATENT_CACHE.clear()      # model değişti → eski latent önbelleği geçersiz
    _log(f"Fine-tuned XTTS checkpoint yüklendi: {model_pth}")
    return ckpt_dir


def _warmup(model, ckpt_dir: str | None, default_speaker: str | None) -> None:
    """Yüklenen ağırlıklarla kısa bir üretim yapar.

    Isınmanın amacı aygıtı değil AĞIRLIKLARI denemektir: bazı MPS operatörleri
    modelin yüklenmesinde değil ilk üretimde patlar. Konuşmacı yoksa (fine-tuned
    model konuşmacı-genel) checkpoint dizinindeki referans klibi kullanılır;
    ikisi de yoksa ısınma atlanır — model yine yüklüdür.
    """
    warm_ref = os.path.join(ckpt_dir, "referans.wav") if ckpt_dir else ""
    if default_speaker:
        kwargs = {"speaker": default_speaker}
    elif warm_ref and os.path.isfile(warm_ref):
        kwargs = {"speaker_wav": warm_ref}
    else:
        return
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        model.tts_to_file(text="Merhaba.", language="tr", file_path=tmp.name, **kwargs)


def _load_model():
    """Modeli yükler; MPS'te ısınma üretimi başarısız olursa CPU'ya düşer.

    SESLAB_XTTS_CHECKPOINT_DIR ayarlıysa taban model yüklendikten sonra
    fine-tuned ağırlıklar bindirilir (bkz. _apply_finetuned).
    """
    import torch
    from TTS.api import TTS

    device = os.environ.get("SESLAB_XTTS_DEVICE", "auto")
    if device == "auto":
        device = "mps" if torch.backends.mps.is_available() else "cpu"

    _log(f"XTTS yükleniyor (aygıt adayı: {device})...")
    model = TTS(MODEL_ID)
    active = _apply_finetuned(model)
    if active:
        _log(f"Aktif ses modeli: fine-tuned ({active})")

    # Isınma konuşmacısı: taban modelde yerleşik konuşmacı vardır; fine-tuned
    # modelde YOKtur (konuşmacı-genel, referansla koşullanır) → checkpoint
    # dizinindeki referans.wav'ı kullan. İkisi de yoksa ısınma atlanır.
    warm_ref = os.path.join(active, "referans.wav") if active else ""

    for candidate in ([device, "cpu"] if device != "cpu" else ["cpu"]):
        try:
            model = model.to(candidate)
            # Isınma: bazı MPS operatörleri yüklemede değil üretimde patlar
            with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
                speakers = getattr(model, "speakers", None) or []
                if speakers:
                    kwargs = {"speaker": speakers[0]}
                elif warm_ref and os.path.isfile(warm_ref):
                    kwargs = {"speaker_wav": warm_ref}
                else:
                    kwargs = None  # konuşmacı yok → ısınmayı atla (model yüklü)
                if kwargs is not None:
                    model.tts_to_file(
                        text="Merhaba.", language="tr", file_path=tmp.name, **kwargs
                    )
            _log(f"XTTS hazır ({candidate})")
            return model, candidate
        except Exception:
            _log(f"{candidate} üzerinde ısınma başarısız:\n{traceback.format_exc()}")
            if candidate == "cpu":
                raise
    raise RuntimeError("XTTS hiçbir aygıtta yüklenemedi")


def _cache_key(paths: list[str]) -> tuple:
    """Referans kümesini yol+mtime ile anahtarlar (dosya güncellenince tazelenir)."""
    out = []
    for p in paths:
        try:
            out.append((p, os.path.getmtime(p)))
        except OSError:
            out.append((p, 0.0))
    return tuple(out)


def _get_latents(xtts, cfg, ref_paths: list[str]):
    """Koşullandırma latent'lerini önbellekten getirir veya hesaplar.

    Çok-klipte konuşmacı gömme vektörü klipler arası ortalanır (gürbüz tını);
    GPT koşullandırması kliplerin birleşiminden ilk gpt_cond_len saniyeyi alır.
    Parametreler model config'inden (tts_to_file ile aynı davranış).
    """
    key = _cache_key(ref_paths)
    cached = _LATENT_CACHE.get(key)
    if cached is None:
        cached = xtts.get_conditioning_latents(
            audio_path=ref_paths,
            gpt_cond_len=cfg.gpt_cond_len,
            gpt_cond_chunk_len=cfg.gpt_cond_chunk_len,
            max_ref_length=cfg.max_ref_len,
            sound_norm_refs=cfg.sound_norm_refs,
        )
        _LATENT_CACHE[key] = cached
    return cached


def _base_params(cfg) -> dict:
    """Modelin tts_to_file'da kullandığı örnekleme parametreleri (config'ten)."""
    return {
        "temperature": cfg.temperature,
        "length_penalty": cfg.length_penalty,
        "repetition_penalty": float(cfg.repetition_penalty),
        "top_k": cfg.top_k,
        "top_p": cfg.top_p,
    }


def main() -> None:
    import soundfile as sf

    model, device = _load_model()
    xtts = model.synthesizer.tts_model          # Xtts örneği (düşük-seviye API)
    cfg = model.synthesizer.tts_config
    base_params = _base_params(cfg)
    speakers = getattr(model, "speakers", None) or []
    default_speaker = speakers[0] if speakers else None
    print(json.dumps({"ready": True, "device": device}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)

            if req.get("cmd") == "swap":
                # Ses değişimi: üç sesin hepsi aynı taban XTTS-v2'yi paylaşır,
                # yalnız GPT ağırlıkları farklıdır. Süreci yeniden doğurmak
                # (ölçüldü: ~33 sn — Python açılışı + torch import + taban model
                # + ısınma) yerine ağırlıklar canlı modelde değiştirilir.
                hedef = req.get("checkpoint_dir") or ""
                yuklenen = _apply_finetuned(model, hedef)
                if hedef and yuklenen is None:
                    # Dizin geçersiz: sessizce taban modelde kalmak, YANLIŞ SESLE
                    # konuşan bir podcast demek. Ana süreç respawn'a düşsün.
                    raise RuntimeError(f"checkpoint yüklenemedi: {hedef}")
                # load_checkpoint içeride init_models() çağırıp modülleri CPU'da
                # yeniden kuruyor → cihaza geri taşımak ZORUNLU.
                model.to(device)
                xtts = model.synthesizer.tts_model
                cfg = model.synthesizer.tts_config
                base_params = _base_params(cfg)
                speakers = getattr(model, "speakers", None) or []
                default_speaker = speakers[0] if speakers else None
                # Isınma, soğuk yolda "bazı MPS operatörleri yüklemede değil
                # ÜRETİMDE patlar" diye konmuştu; sıcak takas da yeni ağırlıklarla
                # ilk üretimi yapıyor, dolayısıyla aynı koruma gerekli. Ölçümde
                # ısınmasız takasların birinde 0,04 sn'lik kesik ses geldi.
                _warmup(model, yuklenen, default_speaker)
                print(
                    json.dumps({"ok": True, "swapped": yuklenen or "taban"}),
                    flush=True,
                )
                continue

            text = req["text"]
            language = req.get("language", "tr")
            out_path = req["out_path"]
            speed = float(req.get("speed", 1.0))

            # Referans kümesi: çok-klip (ref_wavs) > tek klip (ref_wav) > yerleşik
            ref_paths = req.get("ref_wavs")
            if not ref_paths and req.get("ref_wav"):
                ref_paths = [req["ref_wav"]]

            if ref_paths:
                gpt_cond_latent, speaker_embedding = _get_latents(
                    xtts, cfg, list(ref_paths)
                )
                params = dict(base_params)
                params.update(DEFAULT_GEN_PARAMS)
                params.update(req.get("params") or {})
                out = xtts.inference(
                    text,
                    language,
                    gpt_cond_latent,
                    speaker_embedding,
                    speed=speed,
                    # KRİTİK: dahili cümle bölmesini kapat — çok cümleli parça
                    # TEK GPT geçişinde üretilir, cümleler arası tonlama bağı
                    # (doğal prozodi) ancak böyle oluşur. Parça uzunluğunu ana
                    # süreç Türkçe tavanına (226) göre sınırlar.
                    enable_text_splitting=False,
                    **params,
                )
                wav = out["wav"]
                sf.write(out_path, wav, 24000)
                duration = len(wav) / 24000
            else:
                # Referanssız: yerleşik konuşmacı (yalnız ısınma/uç durum)
                model.tts_to_file(
                    text=text, language=language, file_path=out_path,
                    speed=speed, split_sentences=False,
                    **({"speaker": default_speaker} if default_speaker else {}),
                )
                duration = sf.info(out_path).duration

            print(json.dumps({"ok": True, "duration_s": duration}), flush=True)
        except Exception as e:  # noqa: BLE001 — hata ana sürece taşınır
            _log(traceback.format_exc())
            print(json.dumps({"ok": False, "error": str(e)}), flush=True)


if __name__ == "__main__":
    main()
