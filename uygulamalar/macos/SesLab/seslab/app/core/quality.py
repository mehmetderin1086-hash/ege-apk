"""STT geri beslemeli üretim doğrulama ve onarım.

XTTS ara sıra cümle sonuna kısa bir halüsinasyon sesi ekler ("...bağlar dağ").
Bu modül her üretimi Whisper'la deşifre eder, kaynakla kelime düzeyinde
hizalar ve:
  1. çekirdek sağlam + kuyrukta fazlalık varsa → sesi son eşleşen kelimenin
     bitiminde keser (cerrahî onarım, yeniden üretim gerekmez);
  2. benzerlik eşiğin altındaysa → çağırana "yeniden üret" der.
"""
from __future__ import annotations

import difflib
import re

import numpy as np

from app.core.text.normalize_tr import normalize_tr

# Karar eşikleri (canlı denetim verisiyle kalibre edildi, 2026-07-16:
# mükemmel=1.00, küçük ek farkı=0.985, gerçek telaffuz sapması=0.933)
SIM_OK = 0.98          # bunun üstü: hiç dokunma
SIM_RETRY = 0.95       # bunun altı: kötü örnekleme, yeniden üret
TRIM_PAD_S = 0.15      # fazla kelime kesiminde bırakılan pay
END_PAD_S = 0.25       # temiz üretimde kuyruk sesi kesim payı (doğal düşüş korunur)
LONG_TAIL_S = 0.45     # son kelimeden sonra bundan uzun ses varsa kuyruk kes
MIN_CORE_COVERAGE = 0.85  # kuyruk kesimi için kaynağın en az bu kadarı eşleşmeli


def _norm(s: str) -> str:
    s = normalize_tr(s)[0]
    s = s.lower().replace("â", "a").replace("î", "i").replace("û", "u")
    return re.sub(r"[^a-zçğıöşü ]", "", s).strip()


def similarity(source: str, transcript: str) -> float:
    # autojunk=False ŞART: varsayılan sezgisel, 200+ karakterlik metinlerde
    # boşluk karakterini "junk" sayıp oranı çökertir (0.98'lik eşleşmeyi
    # 0.69 gösterir) — uzun parçalarda sahte yeniden üretimlere yol açar.
    return difflib.SequenceMatcher(
        None, _norm(source), _norm(transcript), autojunk=False
    ).ratio()


def find_trailing_cut(
    source: str, hyp_words: list[dict], audio_dur_s: float | None = None
) -> float | None:
    """Kuyruk kesim zamanını (sn) döndürür, kesim gerekmiyorsa None.

    İki durumda keser:
    1. Fazla kelime: transkript kaynağın sonrasında kelime içeriyor
       (halüsinasyon) → son eşleşen kelime + TRIM_PAD_S.
    2. Uzun ses kuyruğu: kelime fazlası yok ama son kelimeden sonra
       LONG_TAIL_S'den uzun ses var (nefes/mırıltı artefaktı) → son kelime
       + END_PAD_S. (audio_dur_s verilmişse denetlenir.)

    hyp_words: [{"word", "start", "end"}, ...] (Whisper kelime zamanları)
    """
    src_tokens = _norm(source).split()
    # Boş normalize olan kelimeleri ele ama orijinal indeksi koru
    hyp: list[tuple[int, str]] = []
    for i, w in enumerate(hyp_words):
        t = _norm(w.get("word", ""))
        if t:
            hyp.append((i, t))
    if not src_tokens or not hyp:
        return None

    sm = difflib.SequenceMatcher(None, src_tokens, [t for _, t in hyp])
    blocks = [b for b in sm.get_matching_blocks() if b.size]
    if not blocks:
        return None

    matched_src = sum(b.size for b in blocks)
    if matched_src / len(src_tokens) < MIN_CORE_COVERAGE:
        return None  # çekirdek zaten sorunlu → kesim çözüm değil

    last_hyp_idx = max(b.b + b.size for b in blocks) - 1  # hyp listesinde
    last_end = float(hyp_words[hyp[last_hyp_idx][0]]["end"])
    extra = len(hyp) - 1 - last_hyp_idx

    if extra >= 1:
        return last_end + TRIM_PAD_S
    if audio_dur_s is not None and audio_dur_s - last_end > LONG_TAIL_S:
        return last_end + END_PAD_S
    return None


def find_leading_cut(source: str, hyp_words: list[dict]) -> float | None:
    """Parça BAŞINA sızmış artefakt varsa kesim başlangıcını (sn) döndürür.

    (find_trailing_cut'ın aynadaki eşi: ilk eşleşen kelimeden önce fazladan
    kelime varsa, ses ilk gerçek kelimenin hemen öncesinden başlatılır.)
    """
    src_tokens = _norm(source).split()
    hyp: list[tuple[int, str]] = []
    for i, w in enumerate(hyp_words):
        t = _norm(w.get("word", ""))
        if t:
            hyp.append((i, t))
    if not src_tokens or not hyp:
        return None

    sm = difflib.SequenceMatcher(None, src_tokens, [t for _, t in hyp])
    blocks = [b for b in sm.get_matching_blocks() if b.size]
    if not blocks:
        return None
    if sum(b.size for b in blocks) / len(src_tokens) < MIN_CORE_COVERAGE:
        return None

    first_hyp_idx = min(b.b for b in blocks)
    if first_hyp_idx < 1:
        return None  # başta fazlalık yok
    start = float(hyp_words[hyp[first_hyp_idx][0]]["start"])
    return max(0.0, start - 0.05)


def has_tail_fusion(source: str, transcript: str) -> bool:
    """Son kelimeye kaynaşmış ek yakalar: "çıktı" → "çıktıda", "ol" → "olduğunu".

    Kelime hizalaması bunu 'fazla kelime' olarak göremez (tek belirteçtir);
    tespit edilirse tek çare yeniden üretimdir (alt-kelime zamanı yok).
    """
    src = _norm(source).split()
    hyp = _norm(transcript).split()
    if not src or not hyp:
        return False
    s_last, h_last = src[-1], hyp[-1]
    return (
        len(s_last) >= 2   # "ol" → "olduğunu" gibi kısa emir kipleri de kapsanır
        and h_last != s_last
        and h_last.startswith(s_last)
        and len(h_last) - len(s_last) >= 2
    )


def has_mid_insertion(source: str, transcript: str) -> bool:
    """Kaynak sağlamken transkriptin ORTASINA sızmış saf eklemeyi yakalar.

    Saf ekleme = SequenceMatcher "insert" opcode'u (kaynak tarafı boş):
    "birbirine bağlar" → "birbirine falan bağlar" gibi halüsinasyonlar.
    Whisper'ın kelime bölmeleri ("başarıyla"→"başarı ile") "replace" ürettiği
    için yanlış pozitif vermez. Sondaki eklemeler kuyruk kesicinin işidir,
    burada sayılmaz.
    """
    src = _norm(source).split()
    hyp = _norm(transcript).split()
    if not src or not hyp:
        return False
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, src, hyp).get_opcodes():
        if tag != "insert":
            continue
        if j2 >= len(hyp):  # kuyruk eklemesi → trailing cut halleder
            continue
        if sum(len(w) for w in hyp[j1:j2]) >= 3:
            return True
    return False


def has_material_omission(source: str, transcript: str) -> bool:
    """Kaynakta olup seste kaybolmuş anlamlı sözcükleri yakala.

    Bir sözcüğün Whisper tarafından komşusuyla birleştirilmesi olağandır;
    ancak iki veya daha fazla sözcüğün ya da en az sekiz harflik saf bir
    parçanın silinmesi gerçek TTS atlamasıdır. Son üretimdeki
    ``Söz veriyorum.`` kaybı bu denetim olmadan 0.95-0.98 gri bandında
    kabul edilmişti.
    """
    src = _norm(source).split()
    hyp = _norm(transcript).split()
    if not src or not hyp:
        return bool(src and not hyp)
    for tag, i1, i2, _j1, _j2 in difflib.SequenceMatcher(None, src, hyp).get_opcodes():
        if tag != "delete":
            continue
        missing = src[i1:i2]
        if len(missing) >= 2 or sum(len(w) for w in missing) >= 8:
            return True
    return False


def has_material_replacement(source: str, transcript: str) -> bool:
    """Belirgin tek-sözcük telaffuz sapmasını yakala.

    Yakın biçimler (``neyden``/``neden``) ve Whisper'ın sözcük bölmeleri
    (``başarıyla``/``başarı ile``) kabul edilir. Çok farklı biçimler
    (gerçek kayıttaki ``İşte``/``Üçte`` gibi) yeniden üretim ister.
    """
    src = _norm(source).split()
    hyp = _norm(transcript).split()
    if not src or not hyp:
        return False
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, src, hyp).get_opcodes():
        if tag != "replace":
            continue
        left = "".join(src[i1:i2])
        right = "".join(hyp[j1:j2])
        if min(len(left), len(right)) < 3 or max(len(left), len(right)) < 4:
            continue
        closeness = difflib.SequenceMatcher(None, left, right, autojunk=False).ratio()
        if closeness < 0.62:
            return True
    return False


def verify_and_repair(
    audio: np.ndarray, sr: int, source: str, language: str = "tr"
) -> tuple[np.ndarray, dict]:
    """Üretimi deşifre edip gerekirse kuyruğu keser.

    Dönüş: (ses, {"similarity", "action": ok|trimmed|retry, "transcript"})
    Thread içinde çağrılmalıdır (STT motoru yükleyebilir).
    """
    import librosa

    from app.engines.manager import manager

    audio16 = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    engine = manager.ensure("stt")
    result = engine.transcribe(audio16, language=language, word_timestamps=True)
    transcript = (result.get("text") or "").strip()
    words = [w for seg in result.get("segments", []) for w in seg.get("words", [])]

    sim = similarity(source, transcript)
    report = {"similarity": round(sim, 4), "transcript": transcript, "action": "ok"}

    if sim < SIM_RETRY:
        report["action"] = "retry"
        return audio, report

    # Benzerlik eşiği geçse bile ortaya sızmış ek kelime kabul edilemez
    # (kısa eklemeler uzun cümlede oranı az düşürür ama kulağa batar)
    if has_mid_insertion(source, transcript):
        report["action"] = "retry"
        report["reason"] = "ara-ekleme"
        return audio, report

    if has_material_omission(source, transcript):
        report["action"] = "retry"
        report["reason"] = "kelime-atlama"
        return audio, report

    if has_material_replacement(source, transcript):
        report["action"] = "retry"
        report["reason"] = "belirsiz-telaffuz"
        return audio, report

    # Son kelimeye kaynaşmış ek ("çıktı"→"çıktıda"): kesilemez → yeniden üret
    if has_tail_fusion(source, transcript):
        report["action"] = "retry"
        report["reason"] = "kuyruk-kaynaşması"
        return audio, report

    # Baş artefaktı: ilk gerçek kelimeden öncesini at
    lead = find_leading_cut(source, words)
    if lead is not None and lead > 0.1:
        audio = audio[int(lead * sr):]
        report["action"] = "trimmed"
        report["lead_cut_s"] = round(lead, 2)

    cut = find_trailing_cut(source, words, audio_dur_s=len(audio) / sr + (lead or 0))
    if cut is not None:
        cut -= lead or 0.0  # baş kesildiyse zaman ekseni kaydı
        if 0.5 < cut < len(audio) / sr:
            audio = audio[: int(cut * sr)]
            report["action"] = "trimmed"
            report["cut_s"] = round(cut, 2)
    return audio, report
