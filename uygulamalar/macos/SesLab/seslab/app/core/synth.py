"""Ortak TTS sentez akışı: normalizasyon → parçalama → üretim → birleştirme.

/api/tts, ses önizlemeleri ve OpenAI-uyumlu uç tarafından paylaşılır.
Uzun metin projeleri parça durumlarını kalıcılaştırdığı için kendi
orkestrasyonunu kullanır (app/core/projects.py) ama aynı motor çağrısını
paylaşır.
"""
from __future__ import annotations

import asyncio
import logging
import os

import numpy as np

log = logging.getLogger("seslab.synth")

from app.audio.postprocess import stitch
from app.config import DEFAULT_LANGUAGE
from app.core.text.chunk_tr import chunk_text
from app.core.text.normalize_tr import normalize_tr
from app.core import voices
from app.engines.manager import manager
from app.jobs import Job, queue


def effective_voice_id(
    voice_id: str | None,
    language: str = DEFAULT_LANGUAGE,
    engine: str = "chatterbox",
) -> str | None:
    """Kullanılacak GERÇEK ses kimliği.

    Ses seçilmemişse (None/"default"): XTTS + Türkçe kombinasyonunda kütüphanedeki
    EN YENİ klon kimliği döner (yerleşik konuşmacılar İngilizce aksanlı). Böylece
    hem referans hem de sese özgü checkpoint aynı kimlikten türetilir.
    """
    if not voice_id or voice_id == "default":
        if engine == "xtts" and language == "tr":
            existing = voices.list_voices()
            if existing:
                return existing[0]["id"]  # en yeni klon
        return None
    return voice_id


def resolve_ref_wav(
    voice_id: str | None,
    language: str = DEFAULT_LANGUAGE,
    engine: str = "chatterbox",
) -> str | None:
    """voice_id → referans wav yolu (ses seçilmemişse en yeni klon veya None)."""
    vid = effective_voice_id(voice_id, language, engine)
    if vid is None:
        return None
    p = voices.ref_path(vid)
    if not p.exists():
        # Açıkça istenen ses yoksa hata; otomatik seçilen klon kaybolmuşsa taban
        if voice_id and voice_id != "default":
            raise KeyError(f"Ses bulunamadı: {voice_id}")
        return None
    return str(p)


def resolve_checkpoint_dir(
    voice_id: str | None,
    language: str = DEFAULT_LANGUAGE,
    engine: str = "chatterbox",
) -> str | None:
    """voice_id → sese özgü fine-tuned XTTS checkpoint dizini (varsa).

    Yalnızca XTTS için anlamlı; Chatterbox bu değeri yok sayar. Ses seçilmemişse
    en yeni klon kimliği üzerinden çözülür — böylece varsayılan ses kendi
    eğitilmiş modeliyle konuşur (ör. Murat). Ses kendi checkpoint'ini
    bildirmiyorsa None → motor genel varsayılana (Emel/taban) düşer.
    """
    if engine != "xtts":
        return None
    vid = effective_voice_id(voice_id, language, engine)
    return voices.resolve_checkpoint_dir(vid)


# API'deki motor adı → EngineManager anahtarı
ENGINE_KEYS = {"chatterbox": "tts", "xtts": "xtts"}

# Noktalamaya duyarlı duraksamalar (insan konuşması tek tip durmaz).
# NOT: Daha cömert değerler (0.90/0.58/0.45/0.30) denendi ama kullanıcı dinleme
# testinde paragrafı kötü buldu (sürüncemeli) → orijinal sıkı tempoya dönüldü.
GAP_PARAGRAPH = 0.80   # paragraf arası — konu geçişi nefesi
GAP_TERMINAL = 0.55    # soru/ünlem sonrası — vurgu boşluğu
GAP_SENTENCE = 0.40    # düz cümle sonu
GAP_CLAUSE = 0.28      # cümle içi bölme (virgülden kırılmış uzun cümle)


def gap_after_chunk(text: str, paragraph_break: bool) -> float:
    """Parçadan SONRAKİ doğal duraksama süresi (noktalamaya göre)."""
    if paragraph_break:
        return GAP_PARAGRAPH
    stripped = text.rstrip("\"'»”’) ")
    if stripped.endswith(("?", "!")):
        return GAP_TERMINAL
    if stripped.endswith((".", "…", ":")):
        return GAP_SENTENCE
    return GAP_CLAUSE


def default_engine() -> str:
    """Varsayılan TTS motoru.

    Kullanıcı dinleme testinde XTTS-v2'nin Türkçesini belirgin şekilde daha
    iyi buldu → kuruluysa XTTS varsayılandır; değilse Chatterbox'a düşülür.
    """
    return "xtts" if manager.engines["xtts"].available() else "chatterbox"


def _generate_once(
    text: str,
    language: str,
    ref_wav: str | None,
    exaggeration: float,
    cfg_weight: float,
    temperature: float,
    speed: float,
    engine_name: str,
    checkpoint_dir: str | None = None,
) -> tuple[np.ndarray, int]:
    from app.core.text.chunk_tr import tts_sanitize

    engine_key = ENGINE_KEYS.get(engine_name, "tts")
    engine = manager.ensure(
        engine_key,
        checkpoint_dir=checkpoint_dir if engine_key == "xtts" else None,
    )
    audio = engine.generate(
        tts_sanitize(text),
        language=language,
        ref_wav_path=ref_wav,
        exaggeration=exaggeration,
        cfg_weight=cfg_weight,
        temperature=temperature,
        speed=speed,
        checkpoint_dir=checkpoint_dir,  # XTTS sese özgü modele yönlendirir; Chatterbox yok sayar
    )
    manager.watchdog()
    return audio, engine.sr


def finalize_chunk_sync(
    audio: np.ndarray,
    sr: int,
    text: str,
    language: str,
    gen_args: tuple,
) -> tuple[np.ndarray, int]:
    """Üretilmiş parçayı STT ile doğrular/onarır (thread içinde çalışır).

    Onarım döngüsü: baş/kuyruk fazlalığı → kelime zamanıyla kes;
    benzerlik < eşik veya ara-ekleme/kaynaşma → yeniden üret (en çok 3 deneme),
    en temiz örneği tut.
    """
    from app.core.quality import verify_and_repair

    MAX_ATTEMPTS = 3  # kısa cümlelerde artefaktlar inatçı olabiliyor

    audio, report = verify_and_repair(audio, sr, text, language)

    def sentence_fallback() -> tuple[np.ndarray, int] | None:
        """Başarısız çok-cümleli paketi doğrulanmış cümlelere ayır.

        Normal yol çok-cümleli kaldığı için prozodi korunur. Yalnız içerik
        atlama/değiştirme saptanan pakette güvenlik ağı olarak çalışır.
        """
        from app.core.text.chunk_tr import split_sentences

        sentences = split_sentences(text)
        if len(sentences) <= 1:
            return None
        fallback_parts: list[np.ndarray] = []
        fallback_gaps: list[float] = []
        fallback_sr = sr
        for sentence in sentences:
            sentence_args = (sentence, *gen_args[1:])
            candidates: list[tuple[np.ndarray, int, dict]] = []
            for _attempt in range(MAX_ATTEMPTS):
                candidate, candidate_sr = _generate_once(*sentence_args)
                candidate, candidate_report = verify_and_repair(
                    candidate, candidate_sr, sentence, language
                )
                candidates.append((candidate, candidate_sr, candidate_report))
                if candidate_report["action"] != "retry":
                    break
            best = max(
                candidates,
                key=lambda a: (a[2]["action"] != "retry", a[2]["similarity"]),
            )
            if best[2]["action"] == "retry":
                raise RuntimeError(
                    "Ses parçası metne sadık üretilemedi: " + sentence[:80]
                )
            fallback_parts.append(best[0])
            fallback_sr = best[1]
            fallback_gaps.append(gap_after_chunk(sentence, False))
        log.info("Başarısız paket %d doğrulanmış cümleye ayrıldı", len(sentences))
        return stitch(
            fallback_parts,
            fallback_sr,
            gaps_s=fallback_gaps,
            normalize=False,
        ), fallback_sr

    # Yapısal hata aynı uzun paketi tekrar örneklemekle sıkça tekrarlanır.
    # Doğrudan cümle güvenlik ağına geçmek hem daha hızlı hem daha güvenilir.
    if report.get("reason") in {
        "kelime-atlama", "belirsiz-telaffuz", "ara-ekleme", "kuyruk-kaynaşması"
    }:
        fallback = sentence_fallback()
        if fallback is not None:
            return fallback

    attempts: list[tuple[np.ndarray, int, dict]] = [(audio, sr, report)]
    while report["action"] == "retry" and len(attempts) < MAX_ATTEMPTS:
        log.warning("Yeniden üretim %d/%d (%s, benzerlik %.2f): %.40s...",
                    len(attempts), MAX_ATTEMPTS - 1,
                    report.get("reason", "düşük-benzerlik"),
                    report["similarity"], text)
        audio2, sr2 = _generate_once(*gen_args)
        audio2, report = verify_and_repair(audio2, sr2, text, language)
        attempts.append((audio2, sr2, report))

    # Önce temiz olan (retry gerektirmeyen), eşitlikte benzerliği yüksek olan
    audio, sr, report = max(
        attempts,
        key=lambda a: (a[2]["action"] != "retry", a[2]["similarity"]),
    )
    if report["action"] == "retry":
        fallback = sentence_fallback()
        if fallback is not None:
            return fallback
        raise RuntimeError("Ses parçası metne sadık üretilemedi: " + text[:80])
    if report["action"] == "trimmed":
        log.info("Kuyruk fazlalığı kesildi (%.2f sn): %.40s...",
                 report.get("cut_s", 0), text)
    return audio, sr


# Konuşma temposu sınırı (harf/sn, hız 1,0'a göre). Olağan Türkçe anlatım 12-16 harf/sn'dir; XTTS iki cümleden birini
# atladığında ~25'e çıkar (11 Eki 2026: aynı gün üç kez). Sınır aşılırsa parça en çok iki kez yeniden üretilir.
PACE_LIMIT = float(os.environ.get("SESLAB_PACE_LIMIT", "21"))
PACE_TYPICAL = 14.0   # olağan tempo; yeniden üretilen örnekler buna yakınlığa göre seçilir
PACE_FLOOR = 8.0      # yeniden üretilen örnek bundan yavaşsa (kuyrukta tekrar/uydurma) bir kez daha denenir
PACE_RETRIES = 2


def speech_pace(audio: np.ndarray, sr: int, text: str, speed: float = 1.0) -> float:
    """Sesin konuşma temposu (harf/sn, hız 1,0'a göre); kısa metinde ölçü güvenilmez olduğundan 0 döner."""
    from app.core.text.chunk_tr import tts_sanitize

    # Motorun gerçekten okuduğu metin sayılır (üretimde de aynı temizleme uygulanır).
    letters = sum(ch.isalnum() for ch in tts_sanitize(text))
    if letters < 30 or len(audio) == 0:
        return 0.0
    import librosa

    trimmed, _ = librosa.effects.trim(audio, top_db=35)
    return letters / max(len(trimmed) / sr, 0.1) / max(speed or 1.0, 0.5)


def should_verify(language: str, verify: bool = True) -> bool:
    from app.config import TTS_VERIFY

    return verify and TTS_VERIFY and language == "tr"


def _generate_chunk_sync(
    text: str,
    language: str,
    ref_wav: str | None,
    exaggeration: float,
    cfg_weight: float,
    temperature: float,
    speed: float,
    engine_name: str = "chatterbox",
    verify: bool = True,
    checkpoint_dir: str | None = None,
) -> tuple[np.ndarray, int]:
    """Thread içinde çalışır: üretir + (etkinse) doğrular/onarır."""
    args = (text, language, ref_wav, exaggeration, cfg_weight,
            temperature, speed, engine_name, checkpoint_dir)
    audio, sr = _generate_once(*args)
    if should_verify(language, verify):
        audio, sr = finalize_chunk_sync(audio, sr, text, language, args)
    else:
        # STT'siz hızlı yolda içerik atlamaya karşı güvenlik ağı. Olağan tempoya en yakın örnek tutulur: çok hızlı örnek içerik
        # atlamıştır, çok yavaş örneğin kuyruğunda tekrar ya da uydurma vardır.
        pace = speech_pace(audio, sr, text, speed)
        for attempt in range(PACE_RETRIES):
            if pace <= PACE_LIMIT and (attempt == 0 or pace >= PACE_FLOOR):
                break
            log.warning("Olağan dışı tempo (%.1f harf/sn; içerik atlanmış olabilir), yeniden üretim %d/%d: %.40s...",
                        pace, attempt + 1, PACE_RETRIES, text)
            try:
                audio2, sr2 = _generate_once(*args)
            except Exception:  # noqa: BLE001 — eldeki örnek kullanılabilir; yeniden üretim hatası parçayı düşürmesin
                log.exception("Yeniden üretim başarısız; eldeki örnek kullanılıyor")
                break
            pace2 = speech_pace(audio2, sr2, text, speed)
            if abs(pace2 - PACE_TYPICAL) < abs(pace - PACE_TYPICAL):
                audio, sr, pace = audio2, sr2, pace2
    return audio, sr


async def synth_text(
    text: str,
    language: str = DEFAULT_LANGUAGE,
    voice_id: str | None = None,
    exaggeration: float = 0.5,
    cfg_weight: float = 0.5,
    temperature: float = 0.8,
    speed: float | None = None,   # None → DEFAULT_SPEECH_SPEED (insan temposu)
    normalize: bool = True,
    verify: bool = True,
    engine: str = "chatterbox",
    job: Job | None = None,
) -> tuple[np.ndarray, int, str]:
    """Metni (gerekirse parçalayarak) seslendirir.

    Dönüş: (float32 mono dizi, örnekleme hızı, normalize edilmiş metin)
    """
    if not text or not text.strip():
        raise ValueError("Metin boş olamaz")

    if speed is None:
        from app.config import DEFAULT_SPEECH_SPEED

        speed = DEFAULT_SPEECH_SPEED

    if normalize and language == "tr":
        norm_text, _ = normalize_tr(text)
    else:
        norm_text = text

    # Hızlı modda daha önce yüklenmiş Whisper/MLX modeli 2+ GB birleşik bellek
    # ve MPS bant genişliği tüketmesin. XTTS tek başına belirgin hızlıdır.
    if not verify and manager.engines["stt"].is_loaded():
        log.info("Hızlı TTS: STT doğrulama motoru bellekten çıkarılıyor")
        manager.unload("stt")

    # XTTS: ≤226 karakterlik ÇOK CÜMLELİ gruplar, tek GPT geçişi → cümleler
    # arası doğal tonlama akışı. (Cümle-başına mod robotik "liste okuma" hissi
    # veriyordu; artefaktları artık STT doğrulama ağı yakalar.)
    if engine == "xtts":
        from app.config import XTTS_CHUNK_HARD, XTTS_CHUNK_TARGET

        # Tek geçişte çok fazla kısa cümle XTTS'in son cümleyi atlamasına yol
        # açabiliyor (canlı kayıtta 190 karakter/5 cümlede "Söz veriyorum"
        # kayboldu). Prozodi bağını koruyacak kadar paketle, en fazla üç cümle.
        chunks = chunk_text(
            norm_text,
            target=XTTS_CHUNK_TARGET,
            hard=XTTS_CHUNK_HARD,
            max_pieces=3,
        )
    else:
        chunks = chunk_text(norm_text)
    if not chunks:
        raise ValueError("Seslendirilecek metin bulunamadı")

    ref_wav = resolve_ref_wav(voice_id, language, engine)
    checkpoint_dir = resolve_checkpoint_dir(voice_id, language, engine)
    parts: list[np.ndarray] = []
    gaps: list[float] = []
    sr = 24000
    for idx, chunk in enumerate(chunks):
        if job:
            await queue.update(
                job,
                progress=idx / len(chunks),
                message=f"Bölüm {idx + 1}/{len(chunks)} sentezleniyor",
            )
        audio, sr = await asyncio.to_thread(
            _generate_chunk_sync,
            chunk.text, language, ref_wav,
            exaggeration, cfg_weight, temperature, speed, engine,
            verify, checkpoint_dir,
        )
        parts.append(audio)
        gaps.append(gap_after_chunk(chunk.text, chunk.paragraph_break))

    # stitch tek parçada da doğru çalışır ve peak normalizasyonu uygular —
    # tek/çok parça arasında ses seviyesi tutarlılığı için koşulsuz çağrılır.
    combined = stitch(parts, sr, gaps_s=gaps)
    return combined, sr, norm_text
