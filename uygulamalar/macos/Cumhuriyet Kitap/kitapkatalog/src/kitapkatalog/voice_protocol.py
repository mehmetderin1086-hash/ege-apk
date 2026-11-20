"""Sesli kitap kaydı konuşma protokolü: metin mekaniği katmanı.

Bu modül modelden bağımsızdır; Whisper transkriptini kitap söylemlerine böler,
alan anahtar kelimelerini bulur ve Türkçe sayı sözcüklerini rakama çevirir.
Sayı normalizasyonu YALNIZCA tanınmış alan aralıkları (span) içinde uygulanır;
serbest metinde "bir" gibi sözcükler asla değiştirilmez (başlık/isim bozulmasın).
ISBN için tek bir deterministik yorum yerine aday kafesi üretilir; sağlama
(checksum) geçen TEK aday kabul edilir, aksi hâlde insan incelemesi gerekir.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from kitapkatalog.domain import TranscriptSegment
from kitapkatalog.isbn import canonical_isbn, compact_identifier

BOOK_SEPARATORS: tuple[str, ...] = (
    "yeni kitap",
    "siradaki kitap",
    "sonraki kitap",
    "kitap bitti",
)

# Alan -> katlanmış (aksansız/küçük) anahtar kelime öbekleri; uzun öbek önce
# denenir ki "basim yili" tek başına "yil"dan önce eşleşsin.
FIELD_KEYWORDS: dict[str, tuple[str, ...]] = {
    "isbn": ("isbn", "i s b n", "isbn numarasi"),
    "title": ("kitabin adi", "kitap adi", "baslik", "basligi", "adi", "ismi"),
    "author": ("yazari", "yazar", "yazarlar"),
    "translator": ("cevirmeni", "ceviren", "cevirmen"),
    "publisher": ("yayinevi", "yayin evi", "yayincisi", "yayinci"),
    "publication_date": (
        "basim yili",
        "baski yili",
        "yayin yili",
        "yili",
        "yil",
    ),
    "page_count": ("sayfa sayisi", "sayfasi", "sayfa"),
    "language": ("dili", "dil"),
    "category": ("kategorisi", "kategori", "turu", "tur", "raf"),
    "location": ("dolap numarasi", "dolabi", "dolap", "raf numarasi"),
    "copy_count": ("adet", "tane", "kopya", "nusha"),
}

_FOLD_ONE: dict[str, str] = {
    "İ": "i",
    "I": "i",
    "ı": "i",
    "Ç": "c",
    "ç": "c",
    "Ğ": "g",
    "ğ": "g",
    "Ö": "o",
    "ö": "o",
    "Ş": "s",
    "ş": "s",
    "Ü": "u",
    "ü": "u",
    "Â": "a",
    "â": "a",
    "Î": "i",
    "î": "i",
    "Û": "u",
    "û": "u",
}

_UNITS = {
    "sifir": 0,
    "bir": 1,
    "iki": 2,
    "uc": 3,
    "dort": 4,
    "bes": 5,
    "alti": 6,
    "yedi": 7,
    "sekiz": 8,
    "dokuz": 9,
}
_TENS = {
    "on": 10,
    "yirmi": 20,
    "otuz": 30,
    "kirk": 40,
    "elli": 50,
    "altmis": 60,
    "yetmis": 70,
    "seksen": 80,
    "doksan": 90,
}
_SCALES = {"yuz": 100, "bin": 1000}
_NUMBER_WORDS = frozenset(_UNITS) | frozenset(_TENS) | frozenset(_SCALES)
_COMPOUND = re.compile(rf"^({'|'.join(_UNITS)}|{'|'.join(_TENS)})({'|'.join(_SCALES)})$")
_WORD = re.compile(r"\w+", re.UNICODE)
_DIGIT_RUN = re.compile(r"\d+")
_MAX_ISBN_COMBINATIONS = 64


def fold_text(text: str) -> str:
    """Türkçe aksanları katla ve küçült; eşleşme HEP bu biçim üzerinde yapılır.

    Karakter konumları katlanmış metinde bulunup ORİJİNAL metin dilimlendiği
    için katlama UZUNLUK KORUMALIDIR: çok karaktere açılan küçültmelerde
    ("İ" -> "i" + birleşen nokta, "ß" -> "ss") yalnız ilk karakter alınır.
    """

    folded: list[str] = []
    for character in text:
        mapped = _FOLD_ONE.get(character)
        if mapped is None:
            lowered = character.casefold()
            mapped = lowered if len(lowered) == 1 else lowered[0]
        folded.append(mapped)
    return "".join(folded)


@dataclass(frozen=True, slots=True)
class FieldSpan:
    field: str
    keyword: str
    raw_value: str
    start: int
    end: int


@dataclass(frozen=True, slots=True)
class BookUtterance:
    ordinal: int
    start_seconds: float
    end_seconds: float
    segments: tuple[TranscriptSegment, ...]

    @property
    def text(self) -> str:
        return " ".join(piece for piece, _segment in utterance_pieces(self))


def utterance_pieces(utterance: BookUtterance) -> tuple[tuple[str, TranscriptSegment], ...]:
    """Boş olmayan, kırpılmış (metin, kaynak segment) ikilileri — tek kaynaklı join.

    ``BookUtterance.text`` ve karakter aralığından örnek zamana eşleyen
    ``voice_refine.span_to_sample_range`` AYNI birleştirme mantığını kullanır;
    burada değişirse ikisi de senkron kalır, ofsetler sessizce kaymaz.
    """

    return tuple(
        (segment.text.strip(), segment) for segment in utterance.segments if segment.text.strip()
    )


def _tokenize_folded(text: str) -> list[tuple[str, int, int]]:
    folded = fold_text(text)
    tokens: list[tuple[str, int, int]] = []
    for match in _WORD.finditer(folded):
        token = match.group()
        split = _COMPOUND.match(token)
        if split:
            # "ikibin" -> "iki"+"bin"; karakter aralığı bileşik sözcüğü paylaşır.
            head, tail = split.group(1), split.group(2)
            cut = match.start() + len(head)
            tokens.append((head, match.start(), cut))
            tokens.append((tail, cut, match.end()))
        else:
            tokens.append((token, match.start(), match.end()))
    return tokens


def _numeric_token_value(token: str, *, numeric_slot: bool) -> int | None:
    if numeric_slot and token == "bi":
        token = "bir"
    if token in _UNITS:
        return _UNITS[token]
    if token in _TENS:
        return _TENS[token]
    return None


def parse_number_words(words: list[str]) -> int | None:
    """Türkçe bileşik sayı gramerini SIRA DOĞRULAYARAK çöz.

    "iki bin yirmi dort" -> 2024; ama "iki uc", "yirmi otuz", "yuz doksan iki
    on" gibi Türkçede tek sayı olmayan diziler REDDEDİLİR (None). Bu katılık,
    paylaşılan sayı koşusu bölünürken yanlış-ama-makul değerlerin sessizce
    üretilmesini engeller (örn. "yüz doksan iki | on iki" doğru bölünür).
    Grup grameri: [birlik] yüz? onluk? birlik?; "bin" grubu kapatır ve en
    fazla bir kez geçer; "sıfır" yalnız tek başına geçerlidir.
    """

    if not words:
        return None
    total = 0
    current = 0
    seen_any = False
    seen_bin = False
    # Grup içi konum: 0=başlangıç, 1=yüz-çarpanı birlik alındı, 2=yüz alındı,
    # 3=onluk alındı, 4=birlik alındı (grup kapalı; yalnız 'bin' gelebilir).
    position = 0
    for word in words:
        if word == "bi":
            word = "bir"
        if word == "sifir":
            if len(words) != 1:
                return None
            return 0
        if word in _UNITS:
            if position in {1, 4}:
                return None
            if position == 0:
                current += _UNITS[word]
                position = 1
            else:  # yüz/onluk sonrası birlik: grubu kapatır
                current += _UNITS[word]
                position = 4
            seen_any = True
        elif word in _TENS:
            if position not in {0, 2}:
                return None
            current += _TENS[word]
            position = 3
            seen_any = True
        elif word == "yuz":
            if position not in {0, 1}:
                return None
            current = (current or 1) * 100
            position = 2
            seen_any = True
        elif word == "bin":
            if seen_bin:
                return None
            total += (current or 1) * 1000
            current = 0
            position = 0
            seen_bin = True
            seen_any = True
        else:
            return None
    if not seen_any:
        return None
    return total + current


def parse_int_span(raw_value: str) -> int | None:
    """Alan aralığındaki metinden tam sayı çıkar (rakam öncelikli, sonra sözcük).

    Whisper'ın "1.002" / "1,002" biçimleri rakam modunda bitiştirilir.
    """

    folded = fold_text(raw_value)
    digit_runs = _DIGIT_RUN.findall(folded)
    if digit_runs:
        return int("".join(digit_runs))
    words = [token for token, _, _ in _tokenize_folded(raw_value)]
    number_words = [word for word in words if word in _NUMBER_WORDS or word == "bi"]
    if not number_words:
        return None
    return parse_number_words(number_words)


def parse_year_span(raw_value: str) -> int | None:
    value = parse_int_span(raw_value)
    if value is None:
        return None
    return value if 1400 <= value <= 2100 else None


def isbn_candidates_from_span(raw_value: str) -> tuple[str, ...]:
    """Konuşulan ISBN aralığından sağlaması geçen benzersiz adayları üret.

    Rakam ve sayı-sözcüğü koşuları için iki yorum denenir: tek-basamak
    bitiştirme ("dokuz yedi sekiz" -> 978) ve gruplu değer ("dokuz yuz yetmis
    sekiz" -> 978). Koşular arası kombinasyonlar sınırlandırılır; yalnız 10/13
    haneli ve checksum geçen değerler döner.
    """

    tokens = _tokenize_folded(raw_value)
    runs: list[list[str]] = []
    for token, _, _ in tokens:
        if token.isdigit():
            runs.append([token])
        elif token in _NUMBER_WORDS or token == "bi":
            if runs and isinstance(runs[-1], list) and runs[-1] and not runs[-1][0].isdigit():
                runs[-1].append(token)
            else:
                runs.append([token])
        # sayı olmayan sözcükler koşuları böler
        elif runs and runs[-1]:
            runs.append([])
    runs = [run for run in runs if run]

    def _per_word_digits(words: list[str]) -> str | None:
        concatenated: list[str] = []
        for word in words:
            value = _numeric_token_value(word, numeric_slot=True)
            if value is None:
                return None
            concatenated.append(str(value))
        return "".join(concatenated) if concatenated else None

    def _interpretations(run: list[str]) -> list[str]:
        if run and run[0].isdigit():
            return ["".join(run)]
        results: list[str] = []
        per_word = _per_word_digits(run)
        if per_word is not None:
            results.append(per_word)
        grouped = parse_number_words(list(run))
        if grouped is not None:
            text = str(grouped)
            if text not in results:
                results.append(text)
        # Yaygın okuma: önek grupla ("dokuz yuz yetmis sekiz" -> 978), kalan
        # rakamları tek tek söyle. Yalnız 978/979 önekleri için denenir.
        for prefix_length in (4,):
            if len(run) > prefix_length:
                prefix_value = parse_number_words(run[:prefix_length])
                if prefix_value in (978, 979):
                    remainder = _per_word_digits(run[prefix_length:])
                    if remainder is not None:
                        combined = f"{prefix_value}{remainder}"
                        if combined not in results:
                            results.append(combined)
        return results or [""]

    combos: list[str] = [""]
    for run in runs:
        options = _interpretations(run)
        combos = [prefix + option for prefix in combos for option in options][
            :_MAX_ISBN_COMBINATIONS
        ]

    combos.append("".join(_DIGIT_RUN.findall(fold_text(raw_value))))
    valid: list[str] = []
    for combo in combos:
        digits = compact_identifier(combo)
        if len(digits) not in (10, 13):
            continue
        canonical = canonical_isbn(digits)
        if canonical and canonical not in valid:
            valid.append(canonical)
    return tuple(valid)


def _keyword_positions(folded: str) -> list[tuple[int, int, str, str]]:
    """(start, end, field, keyword) listesi; uzun anahtar kelime önceliklidir."""

    matches: list[tuple[int, int, str, str]] = []
    claimed: list[tuple[int, int]] = []
    keywords = sorted(
        ((keyword, field) for field, options in FIELD_KEYWORDS.items() for keyword in options),
        key=lambda item: len(item[0]),
        reverse=True,
    )
    for keyword, field in keywords:
        pattern = re.compile(rf"(?<!\w){re.escape(keyword)}(?!\w)")
        for match in pattern.finditer(folded):
            span = (match.start(), match.end())
            if any(start < span[1] and span[0] < end for start, end in claimed):
                continue
            claimed.append(span)
            matches.append((span[0], span[1], field, keyword))
    matches.sort()
    return matches


def extract_field_spans(text: str) -> tuple[FieldSpan, ...]:
    """Alan anahtar kelimelerine göre söylem metnini değer aralıklarına böl.

    Genel kural: değer, anahtar kelimeden sonra bir sonraki anahtar kelimeye
    kadar sürer. "adet/tane" gibi sayım sözcüklerinde Türkçe düzen tersinedir
    ("uc adet"); bu alan için değer anahtar kelimenin ÖNÜNDEKİ sayı koşusudur.
    """

    folded = fold_text(text)
    positions = _keyword_positions(folded)
    bounds: list[tuple[int, int]] = []
    for index, (start, end, field, _) in enumerate(positions):
        if field == "copy_count":
            value_start, value_end = _numeric_run_before(text, start)
            if value_end <= value_start:
                value_start, value_end = _value_bounds(positions, index, end, text)
        else:
            value_start, value_end = _value_bounds(positions, index, end, text)
        bounds.append((value_start, value_end))

    _split_shared_numeric_runs(text, positions, bounds)

    strip_characters = " .,;:!?-–—"
    spans: list[FieldSpan] = []
    for (_start, _end, field, keyword), (value_start, value_end) in zip(
        positions, bounds, strict=True
    ):
        value_end = _trim_at_sentence_end(text, value_start, value_end)
        window = text[value_start:value_end]
        raw_value = window.strip(strip_characters)
        if not raw_value:
            continue
        # Kanıt sözleşmesi: raw_value == text[start:end] birebir sağlanır.
        leading = len(window) - len(window.lstrip(strip_characters))
        adjusted_start = value_start + leading
        spans.append(
            FieldSpan(
                field=field,
                keyword=keyword,
                raw_value=raw_value,
                start=adjusted_start,
                end=adjusted_start + len(raw_value),
            )
        )
    return tuple(spans)


def _value_bounds(
    positions: list[tuple[int, int, str, str]],
    index: int,
    keyword_end: int,
    text: str,
) -> tuple[int, int]:
    next_start = len(text)
    for start, _, field, _ in positions[index + 1 :]:
        # "uc adet" düzeninde adet'in değeri kendinden önce durur; bir önceki
        # alanın değerini sayı koşusunun başında kesmek için copy_count
        # konumundan geriye taşınmış sınırı kullan.
        if field == "copy_count":
            run_start, run_end = _numeric_run_before(text, start)
            next_start = run_start if run_end > run_start else start
        else:
            next_start = start
        break
    return keyword_end, next_start


_SENTENCE_END = re.compile(r"[.!?](?:\s|$)")


def _trim_at_sentence_end(text: str, start: int, end: int) -> int:
    """Değeri ilk cümle sonunda kes — ama yalnız devamında ≥2 kelime varsa.

    "Yayınevi İletişim. Sonra rafa geçiyorum" -> değer "İletişim" olur;
    "Başlık Dr. Jivago" gibi tek kelimelik devamlar kesilmez (kısaltma/başlık).
    """

    window = text[start:end]
    for match in _SENTENCE_END.finditer(window):
        tail = window[match.end() :]
        if len(_WORD.findall(tail)) >= 2:
            return start + match.start()
    return end


def _numeric_run_before(text: str, keyword_start: int) -> tuple[int, int]:
    """Anahtar kelimenin hemen önündeki sayı koşusu; noktalama koşuyu keser.

    "sayfa yüz doksan, iki adet" -> virgül sınırında durulur, adet=2.
    """

    tokens = _tokenize_folded(text)
    run_start = keyword_start
    run_end = keyword_start
    previous_start = keyword_start
    for token, start, end in reversed(tokens):
        if end > keyword_start:
            continue
        gap = text[end:previous_start]
        if any(character in ".,;:!?" for character in gap):
            break
        is_numeric = token.isdigit() or token in _NUMBER_WORDS or token == "bi"
        if is_numeric:
            run_start = start
            if run_end == keyword_start:
                run_end = end
            run_end = max(run_end, end)
            previous_start = start
        else:
            break
    return run_start, run_end if run_end != keyword_start else run_start


_NUMERIC_FIELDS_BEFORE_COUNT = frozenset({"page_count", "publication_date"})


def _split_shared_numeric_runs(
    text: str,
    positions: list[tuple[int, int, str, str]],
    bounds: list[tuple[int, int]],
) -> None:
    """ "sayfa yüz doksan iki adet" belirsizliğini çöz.

    Adet'in sayı koşusu, hemen önceki sayısal alanın (sayfa/yıl) değerini
    tamamen yuttuysa koşu sondan bölünür: en kısa son ek (1, sonra 2 kelime)
    geçerli bir adet (≤99) veriyorsa ve kalan baş kısım da geçerli bir sayıysa
    baş önceki alana, son ek adete verilir. Hiçbir bölme tutmazsa dokunulmaz;
    aşırı adet değeri zaten inceleme nedeni üretir (uydurma yok).
    """

    for index, (_kw_start, _kw_end, field, _keyword) in enumerate(positions):
        if field != "copy_count" or index == 0:
            continue
        prev_field = positions[index - 1][2]
        if prev_field not in _NUMERIC_FIELDS_BEFORE_COUNT:
            continue
        run_start, run_end = bounds[index]
        if run_end <= run_start:
            continue
        prev_start, prev_end = bounds[index - 1]
        if text[prev_start:prev_end].strip(" .,;:!?-–—"):
            continue  # önceki alanın değeri zaten dolu; bölmeye gerek yok
        run_tokens = [
            (token, token_start, token_end)
            for token, token_start, token_end in _tokenize_folded(text)
            if run_start <= token_start and token_end <= run_end
        ]
        if len(run_tokens) < 2:
            continue
        for suffix_length in (1, 2):
            if suffix_length >= len(run_tokens):
                break
            head = [token for token, _, _ in run_tokens[:-suffix_length]]
            tail = [token for token, _, _ in run_tokens[-suffix_length:]]
            copy_value = (
                parse_number_words(tail)
                if not tail[0].isdigit()
                else (int("".join(tail)) if all(t.isdigit() for t in tail) else None)
            )
            head_value = (
                parse_number_words(head)
                if not head[0].isdigit()
                else (int("".join(head)) if all(t.isdigit() for t in head) else None)
            )
            if (
                copy_value is not None
                and 1 <= copy_value <= 99
                and head_value is not None
                and head_value > 0
            ):
                split_at = run_tokens[-suffix_length][1]
                bounds[index - 1] = (bounds[index - 1][0], split_at)
                bounds[index] = (split_at, run_end)
                break


def filter_hallucinations(
    segments: tuple[TranscriptSegment, ...] | list[TranscriptSegment],
    *,
    no_speech_threshold: float = 0.6,
    repeat_limit: int = 3,
) -> tuple[TranscriptSegment, ...]:
    """Sessizlik halüsinasyonlarını ve takılı tekrar döngülerini ele.

    ``no_speech_prob`` sunucu yanıtında yoksa (None) eşik uygulanmaz; ardışık
    birebir aynı metinden en fazla ``repeat_limit - 1`` kopya tutulur,
    devamı düşürülür.
    """

    kept: list[TranscriptSegment] = []
    repeat_text = ""
    repeat_count = 0
    for segment in segments:
        text = segment.text.strip()
        if not text:
            continue
        if segment.no_speech_prob is not None and segment.no_speech_prob >= no_speech_threshold:
            continue
        folded = fold_text(text)
        if folded == repeat_text:
            repeat_count += 1
            if repeat_count >= repeat_limit:
                continue
        else:
            repeat_text = folded
            repeat_count = 1
        kept.append(segment)
    return tuple(kept)


def segment_books(
    segments: tuple[TranscriptSegment, ...] | list[TranscriptSegment],
    *,
    separators: tuple[str, ...] = BOOK_SEPARATORS,
) -> tuple[BookUtterance, ...]:
    """Transkripti YALNIZ açık ayraçlarla kitap söylemlerine böl.

    Ayraç bir segmentin ortasında geçiyorsa segment metni o noktadan ikiye
    ayrılır; süre, karakter oranıyla yaklaşık paylaştırılır (asıl hassas
    zamanlar kanonik WAV örnek indeksleriyle ayrıca tutulur).
    """

    utterances: list[BookUtterance] = []
    bucket: list[TranscriptSegment] = []

    def _flush() -> None:
        nonlocal bucket
        cleaned = [item for item in bucket if item.text.strip()]
        if cleaned:
            utterances.append(
                BookUtterance(
                    ordinal=len(utterances),
                    start_seconds=cleaned[0].start_seconds,
                    end_seconds=cleaned[-1].end_seconds,
                    segments=tuple(cleaned),
                )
            )
        bucket = []

    separator_pattern = re.compile(
        "|".join(rf"(?<!\w){re.escape(item)}(?!\w)" for item in separators)
    )
    for segment in segments:
        remaining = segment
        while True:
            folded = fold_text(remaining.text)
            match = separator_pattern.search(folded)
            if match is None:
                bucket.append(remaining)
                break
            before_text = remaining.text[: match.start()].strip()
            after_text = remaining.text[match.end() :].strip()
            duration = remaining.end_seconds - remaining.start_seconds
            ratio = match.start() / max(1, len(remaining.text))
            cut_time = remaining.start_seconds + duration * ratio
            if before_text:
                bucket.append(
                    TranscriptSegment(
                        start_seconds=remaining.start_seconds,
                        end_seconds=cut_time,
                        text=before_text,
                        avg_logprob=remaining.avg_logprob,
                        no_speech_prob=remaining.no_speech_prob,
                    )
                )
            _flush()
            if not after_text:
                remaining = TranscriptSegment(
                    start_seconds=cut_time,
                    end_seconds=remaining.end_seconds,
                    text="",
                )
                break
            remaining = TranscriptSegment(
                start_seconds=cut_time,
                end_seconds=remaining.end_seconds,
                text=after_text,
                avg_logprob=remaining.avg_logprob,
                no_speech_prob=remaining.no_speech_prob,
            )
    _flush()
    return tuple(utterances)


def boundary_warnings(text: str) -> tuple[str, ...]:
    """Ayraç unutulmuş olabilir sinyalleri: 2+ geçerli ISBN veya alan tekrarı."""

    warnings: list[str] = []
    spans = extract_field_spans(text)
    isbn_values: set[str] = set()
    for span in spans:
        if span.field == "isbn":
            isbn_values.update(isbn_candidates_from_span(span.raw_value))
    if len(isbn_values) >= 2:
        warnings.append("Aynı söylemde birden fazla geçerli ISBN var")
    for field in ("isbn", "title", "author"):
        occurrences = sum(1 for span in spans if span.field == field)
        if occurrences >= 2:
            warnings.append(
                f"'{field}' alanı aynı söylemde {occurrences} kez geçiyor; ayraç unutulmuş olabilir"
            )
    return tuple(warnings)
