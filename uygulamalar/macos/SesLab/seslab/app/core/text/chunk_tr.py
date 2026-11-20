"""Türkçe farkındalıklı cümle bölme ve TTS parça paketleme.

Chatterbox uzun girdilerde bozulduğu için metin ≤CHUNK_TARGET karakterlik
parçalara bölünür. Cümle sınırı tespiti kısaltma vetoludur:
"Dr. Ahmet geldi." tek cümledir, "A. Hamdi" bölünmez, "2. katta" bölünmez.

Kullanım:
    chunks = chunk_text(uzun_metin)   # [Chunk(i, text, chars, paragraph_break)]
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from app.config import CHUNK_HARD, CHUNK_TARGET

from .abbreviations_tr import NEVER_SENTENCE_END

# Cümle sonu adayı: bitiş noktalaması (+ kapanış tırnak/parantez) + boşluk +
# (açılış tırnağı olabilir) + büyük TR harfi veya rakam
_BOUNDARY_RE = re.compile(
    r"([.!?…]+[\"'\)\]»”’]*)\s+(?=[\"'\(«“‘]*[A-ZÇĞİÖŞÜ0-9])"
)

# Vetolar
_SINGLE_INITIAL_RE = re.compile(r"^(?:[A-ZÇĞİÖŞÜ]\.)+$")  # "A." / "A.H." (baş harfler)
_NUMBER_DOT_RE = re.compile(r"^\d+\.$")                    # "2." (sıra sayısı)
_SURROUND_PUNCT = "()[]{}\"'«»“”‘’"


def _last_token(text: str) -> str:
    """Metnin sonundaki belirteci, çevre noktalamadan arındırıp döndürür.

    "(Dr." → "Dr." ; '"vb.' → "vb." — vetolar sarmalayıcı işaretlerden etkilenmez.
    """
    m = re.search(r"(\S+)$", text)
    return m.group(1).strip(_SURROUND_PUNCT) if m else ""


def split_sentences(paragraph: str) -> list[str]:
    """Tek bir paragrafı kısaltma vetolu cümlelere böler."""
    text = re.sub(r"\s+", " ", paragraph).strip()
    if not text:
        return []

    sentences: list[str] = []
    start = 0
    for m in _BOUNDARY_RE.finditer(text):
        candidate_end = m.end(1)
        token = _last_token(text[:candidate_end])
        if token in NEVER_SENTENCE_END:
            continue  # "Dr. Ahmet" → bölme
        if _SINGLE_INITIAL_RE.match(token):
            continue  # "A. Hamdi" → bölme
        if _NUMBER_DOT_RE.match(token):
            continue  # "2. Dünya Savaşı" → bölme (sıra sayısı yorumu)
        sentences.append(text[start:candidate_end].strip())
        start = m.end()
    tail = text[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences


def _split_long(sentence: str, hard: int) -> list[str]:
    """CHUNK_HARD'ı aşan tek cümleyi orta noktaya en yakın ayraçtan böler."""
    if len(sentence) <= hard:
        return [sentence]
    mid = len(sentence) // 2
    for seps in (";", ":", ",", "—", " "):
        best: int | None = None
        for m in re.finditer(re.escape(seps), sentence):
            pos = m.end()
            # Uçlara çok yakın bölme noktalarını eleme
            if pos < 20 or pos > len(sentence) - 20:
                continue
            if best is None or abs(pos - mid) < abs(best - mid):
                best = pos
        if best is not None:
            left = sentence[:best].strip()
            right = sentence[best:].strip()
            return _split_long(left, hard) + _split_long(right, hard)
    return [sentence]  # bölünemedi (boşluksuz aşırı uzun dizi) → olduğu gibi


@dataclass
class Chunk:
    i: int
    text: str
    chars: int
    paragraph_break: bool  # bu parçadan SONRA paragraf duraklaması gelir


# TTS mırıltı tetikleyicileri: üç nokta ve tire türevleri modelde uzun,
# denetimsiz duraksamalar üretir → güvenli eşdeğerlerine sadeleştir.
_TTS_SANITIZE = [
    (re.compile(r"\.{2,}|…"), "."),
    (re.compile(r"[!?]{2,}"), "!"),
    (re.compile(r"\s*[—–]\s*"), ", "),
    (re.compile(r";"), ","),
    (re.compile(r",\s*,+"), ","),
]


def tts_sanitize(text: str) -> str:
    """Parça metnini sentez öncesi duraksama-güvenli hâle getirir."""
    for pattern, repl in _TTS_SANITIZE:
        text = pattern.sub(repl, text)
    return re.sub(r"\s{2,}", " ", text).strip()


def chunk_text(
    text: str,
    target: int = CHUNK_TARGET,
    hard: int = CHUNK_HARD,
    pack: bool = True,
    max_pieces: int | None = None,
) -> list[Chunk]:
    """Metni paragraf sınırlarına saygılı parçalara böler.

    pack=True: cümleler ≤target karaktere kadar paketlenir (Chatterbox modu).
    pack=False: her cümle AYRI parçadır (XTTS modu) — cümle arası duraksamayı
    model değil, birleştirme aşamasındaki saf dijital sessizlik üretir; böylece
    duraksama mırıltısı/ek kelime artefaktı imkânsızlaşır ve her cümle sonu
    kuyruk kesiciden geçer.
    """
    chunks: list[Chunk] = []
    paragraphs = [p for p in re.split(r"\n\s*\n", text) if p.strip()]

    for p_idx, para in enumerate(paragraphs):
        pieces: list[str] = []
        for sentence in split_sentences(para):
            pieces.extend(_split_long(sentence, hard))

        if pack:
            current = ""
            current_pieces = 0
            para_chunks: list[str] = []
            for piece in pieces:
                candidate = f"{current} {piece}".strip()
                piece_limit_hit = bool(
                    current and max_pieces and current_pieces >= max_pieces
                )
                if current and (len(candidate) > target or piece_limit_hit):
                    para_chunks.append(current)
                    current = piece
                    current_pieces = 1
                else:
                    current = candidate
                    current_pieces += 1
            if current:
                para_chunks.append(current)
        else:
            para_chunks = pieces

        is_last_para = p_idx == len(paragraphs) - 1
        for c_idx, c in enumerate(para_chunks):
            chunks.append(
                Chunk(
                    i=len(chunks),
                    text=c,
                    chars=len(c),
                    paragraph_break=(c_idx == len(para_chunks) - 1)
                    and not is_last_para,
                )
            )
    return chunks
