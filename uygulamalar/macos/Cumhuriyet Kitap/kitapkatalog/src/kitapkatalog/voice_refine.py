"""İkinci geçiş: yabancı dilde yanlış anlaşılmış alanları hedefli yeniden okuma.

Kural katmanı Türkçe dil modeliyle "dı greyt gatsbi" gibi fonetik yazımlar
üretebilir. Bu modül kural iddiasının kapsadığı ses dilimini kesip whisper'ı
başka bir dille (örn. ``en``) yeniden çağırır ve sonucu ÖNERİ olarak döndürür.
Öneriler kanıt sözleşmesine tabi değildir (``claims``'e hiç girmez); kullanıcı
onayı olmadan hiçbir alanı değiştirmezler — fail-open bir katmandır: whisper
hata verirse veya sonuç şüpheliyse sessizce boş liste döner, kayıt akışını
kesmez.
"""

from __future__ import annotations

import re
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from kitapkatalog.audio import WAV_SAMPLE_RATE, slice_wav, wav_sample_count
from kitapkatalog.domain import VoiceAlias
from kitapkatalog.voice_extractor import VoiceParseResult
from kitapkatalog.voice_protocol import (
    BookUtterance,
    filter_hallucinations,
    fold_text,
    utterance_pieces,
)

DEFAULT_REFINE_FIELDS: tuple[str, ...] = ("title", "author")
_SAME_TEXT_RATIO = 0.95
_RUNAWAY_RATIO = 3.0
_ALIAS_FIELDS = frozenset({"title", "author", "publisher"})


@dataclass(frozen=True, slots=True)
class FieldSuggestion:
    field_path: str
    value: str
    origin: str
    language: str
    score: float


def span_to_sample_range(
    utterance: BookUtterance,
    start_char: int,
    end_char: int,
    *,
    pad_seconds: float = 0.3,
    sample_rate: int,
    total_samples: int,
) -> tuple[int, int]:
    """Karakter aralığını (birleştirilmiş metinde) örnek (sample) aralığına çevir.

    ``utterance_pieces`` ile aynı birleştirme sırası ve tek-boşluk ayracı
    izlenir; span'la kesişen her parçada karakter-oran interpolasyonu yapılır
    (``t = seg.start + (char-piece_start)/len(piece) * (seg.end-seg.start)``),
    kesişenlerin en erken başlangıcı / en geç bitişi alınır, ±pad uygulanır ve
    örnek sınırlarına clamp edilir.
    """

    pieces = utterance_pieces(utterance)
    if not pieces:
        raise ValueError("Söylemde parça yok")

    cursor = 0
    earliest: float | None = None
    latest: float | None = None
    for text, segment in pieces:
        piece_start = cursor
        piece_end = piece_start + len(text)
        cursor = piece_end + 1  # utterance_pieces() tek boşlukla birleştirir
        if piece_end <= start_char or piece_start >= end_char:
            continue
        length = len(text) or 1
        local_start = max(0, start_char - piece_start)
        local_end = min(length, end_char - piece_start)
        duration = segment.end_seconds - segment.start_seconds
        t_start = segment.start_seconds + (local_start / length) * duration
        t_end = segment.start_seconds + (local_end / length) * duration
        if earliest is None or t_start < earliest:
            earliest = t_start
        if latest is None or t_end > latest:
            latest = t_end

    if earliest is None or latest is None:
        # Span metnin dışında kaldı (savunma amaçlı): tüm söylemi kapsa.
        earliest = pieces[0][1].start_seconds
        latest = pieces[-1][1].end_seconds

    start_sample = max(0, min(int((earliest - pad_seconds) * sample_rate), total_samples))
    end_sample = max(0, min(int((latest + pad_seconds) * sample_rate), total_samples))
    if end_sample <= start_sample:
        end_sample = min(total_samples, start_sample + 1)
    return start_sample, end_sample


def _transcribe_text(
    whisper: Any, wav_path: str | Path, *, language: str
) -> str:
    segments = filter_hallucinations(
        whisper.transcribe(wav_path, language=language, temperature=0.0, temperature_inc=0.2)
    )
    return " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()


def _is_suspicious(candidate: str, original: str, prompt: str | None) -> bool:
    if not candidate:
        return True
    if fold_text(candidate) == fold_text(original):
        return True
    similarity = SequenceMatcher(None, fold_text(candidate), fold_text(original)).ratio()
    if similarity >= _SAME_TEXT_RATIO:
        return True
    if original and len(candidate) > len(original) * _RUNAWAY_RATIO:
        return True
    return bool(prompt and fold_text(candidate) == fold_text(prompt.strip()))


def refine_foreign_fields(
    whisper: Any,
    wav_path: str | Path,
    utterance: BookUtterance,
    result: VoiceParseResult,
    *,
    language: str,
    scratch_dir: str | Path,
    fields: tuple[str, ...] = DEFAULT_REFINE_FIELDS,
    prompt: str | None = None,
) -> list[FieldSuggestion]:
    """Kural katmanının bulduğu alan span'larını ikinci dille yeniden oku.

    Yalnız ``source == "rule"`` iddiaları hedeflenir (form/qwen değerleri
    span'a bağlı değildir). Şüpheli sonuçlar (boş, orijinalle ~aynı, aşırı
    uzun, istem metniyle birebir aynı) sessizce elenir — inceleme nedeni
    ÜRETMEZ, yalnızca öneri üretmez.
    """

    wav_path = Path(wav_path)
    total_samples = wav_sample_count(wav_path)
    scratch = Path(scratch_dir)
    scratch.mkdir(parents=True, exist_ok=True)
    suggestions: list[FieldSuggestion] = []
    for claim in result.claims:
        if claim.field_path not in fields or claim.source != "rule":
            continue
        if claim.end_char <= claim.start_char:
            continue
        try:
            start_sample, end_sample = span_to_sample_range(
                utterance,
                claim.start_char,
                claim.end_char,
                sample_rate=WAV_SAMPLE_RATE,
                total_samples=total_samples,
            )
        except ValueError:
            continue
        if end_sample <= start_sample:
            continue
        piece_path = scratch / f"refine-{uuid.uuid4().hex}.wav"
        try:
            slice_wav(wav_path, piece_path, start_sample=start_sample, end_sample=end_sample)
            candidate = _transcribe_text(whisper, piece_path, language=language)
        finally:
            piece_path.unlink(missing_ok=True)
        original = claim.value.strip()
        if _is_suspicious(candidate, original, prompt):
            continue
        similarity = SequenceMatcher(None, fold_text(candidate), fold_text(original)).ratio()
        suggestions.append(
            FieldSuggestion(
                field_path=claim.field_path,
                value=candidate,
                origin="second_pass",
                language=language,
                score=similarity,
            )
        )
    return suggestions


def refine_missing_title(
    whisper: Any,
    wav_path: str | Path,
    *,
    language: str,
    prompt: str | None = None,
) -> FieldSuggestion | None:
    """Kural katmanı başlık bulamadığında tüm söylemi ikinci dille yeniden oku.

    Hedefli bir span yok (anahtar kelime hiç bulunamadı); tüm ses tek parça
    olarak yeniden çözülür ve ham metin doğrudan öneri değeri olur.
    """

    candidate = _transcribe_text(whisper, wav_path, language=language)
    if not candidate:
        return None
    if prompt and fold_text(candidate) == fold_text(prompt.strip()):
        return None
    return FieldSuggestion(
        field_path="title",
        value=candidate,
        origin="second_pass",
        language=language,
        score=0.0,
    )


def alias_suggestions(
    aliases: Sequence[VoiceAlias], result: VoiceParseResult
) -> list[FieldSuggestion]:
    """Kullanıcı onaylı "duyulan -> kanonik" sözlüğünü metinsel iddialara uygula.

    İki eşleşme biçimi vardır: (a) tam eşleşme (``fold_text(value) == alias.heard``)
    kanonik değeri BÜTÜNÜYLE önerir; (b) kelime sınırlı alt-dize eşleşmesi yalnız
    o parçayı kanonikle değiştirip TAM öneri değerini üretir — ``fold_text`` uzunluk
    koruyucu olduğu için katlanmış metindeki eşleşme konumu orijinal metne doğrudan
    eşlenir. ``field_scope == "any"`` her metinsel alana uygulanır; diğer kapsamlar
    yalnız kendi alanına. Sözlük kullanıcı onaylı olduğundan öneri her zaman en
    yüksek güvenle (``score=1.0``) işaretlenir.
    """

    if not aliases:
        return []
    suggestions: list[FieldSuggestion] = []
    for claim in result.claims:
        if claim.field_path not in _ALIAS_FIELDS:
            continue
        folded_value = fold_text(claim.value)
        for alias in aliases:
            if alias.field_scope not in ("any", claim.field_path):
                continue
            if folded_value == alias.heard:
                new_value = alias.canonical
            else:
                match = re.search(rf"(?<!\w){re.escape(alias.heard)}(?!\w)", folded_value)
                if match is None:
                    continue
                new_value = (
                    claim.value[: match.start()] + alias.canonical + claim.value[match.end() :]
                )
            if new_value.strip() == claim.value.strip():
                continue
            suggestions.append(
                FieldSuggestion(
                    field_path=claim.field_path,
                    value=new_value,
                    origin="alias",
                    language="",
                    score=1.0,
                )
            )
    return suggestions
