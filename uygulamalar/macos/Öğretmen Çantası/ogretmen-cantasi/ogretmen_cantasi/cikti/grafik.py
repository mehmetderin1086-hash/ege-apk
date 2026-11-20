"""Sunucu tarafında üretilen inline SVG grafikler.

JS çerçevesi olmayan arayüzde grafikler de sunucuda üretilir ve şablona gömülür.
Renkler CSS değişkenlerinden okunur (inline SVG sayfanın stilini miras alır);
böylece koyu tema kendiliğinden çalışır ve grafik paleti arayüz paletinden
ayrışamaz. Tek seri kuralı bilinçli: iki ölçek/iki eksen yok, karşılaştırma
gerekirse iki ayrı grafik çizilir. Her işaretin üzerinde tarayıcının kendi
araç ipucu (<title>) vardır; veri ayrıca sayfadaki tabloda durur — grafik
hiçbir bilginin tek taşıyıcısı değildir.
"""

from __future__ import annotations

from html import escape

_KENAR_SOL = 40.0
_KENAR_SAG = 14.0
_KENAR_UST = 12.0
_KENAR_ALT = 24.0


def _aralik(degerler: list[float]) -> tuple[float, float]:
    """Y eksenine, uçlara yapışmayan bir değer aralığı seçer."""
    alt, ust = min(degerler), max(degerler)
    if alt == ust:
        # Tek değerli seri: düz çizgiyi ortalamak için simetrik pay ver.
        pay = max(1.0, abs(alt) * 0.1)
        return alt - pay, ust + pay
    pay = (ust - alt) * 0.12
    return alt - pay, ust + pay


def _bicimle(deger: float) -> str:
    return f"{deger:g}"


def cizgi_grafigi(
    noktalar: list[tuple[str, float]],
    *,
    en: int = 560,
    boy: int = 200,
    baslik: str = "",
) -> str:
    """Tek serilik gelişim çizgisi: (etiket, değer) noktaları sırayla.

    Boş seride boş dize döner — kartı gizlemek şablonun işidir. Tek noktada
    çizgi yerine yalnız işaret ve değer çizilir.
    """
    if not noktalar:
        return ""
    degerler = [d for _, d in noktalar]
    alt, ust = _aralik(degerler)
    ic_en = en - _KENAR_SOL - _KENAR_SAG
    ic_boy = boy - _KENAR_UST - _KENAR_ALT

    def x(sira: int) -> float:
        if len(noktalar) == 1:
            return _KENAR_SOL + ic_en / 2
        return _KENAR_SOL + ic_en * sira / (len(noktalar) - 1)

    def y(deger: float) -> float:
        return _KENAR_UST + ic_boy * (1 - (deger - alt) / (ust - alt))

    parcalar: list[str] = []
    # Sessiz ızgara: yalnız üç yatay çizgi ve değerleri.
    for oran in (0.0, 0.5, 1.0):
        deger = alt + (ust - alt) * oran
        cy = y(deger)
        parcalar.append(
            f'<line x1="{_KENAR_SOL}" y1="{cy:.1f}" x2="{en - _KENAR_SAG}" y2="{cy:.1f}" '
            'stroke="var(--cizgi)" stroke-width="1"/>'
            f'<text x="{_KENAR_SOL - 6}" y="{cy + 3.5:.1f}" text-anchor="end" '
            f'font-size="11" fill="var(--soluk)">{_bicimle(round(deger, 1))}</text>'
        )

    if len(noktalar) > 1:
        yol = " ".join(f"{x(i):.1f},{y(d):.1f}" for i, (_, d) in enumerate(noktalar))
        parcalar.append(
            f'<polyline points="{yol}" fill="none" stroke="var(--vurgu)" '
            'stroke-width="2" stroke-linejoin="round"/>'
        )

    adim = max(1, (len(noktalar) + 5) // 6)  # en fazla ~6 x etiketi
    for sira, (etiket, deger) in enumerate(noktalar):
        cx, cy = x(sira), y(deger)
        parcalar.append(
            f'<g><circle cx="{cx:.1f}" cy="{cy:.1f}" r="4" fill="var(--vurgu)" '
            'stroke="var(--yuzey)" stroke-width="2"/>'
            f"<title>{escape(etiket)}: {_bicimle(deger)}</title></g>"
        )
        if sira % adim == 0 or sira == len(noktalar) - 1:
            parcalar.append(
                f'<text x="{cx:.1f}" y="{boy - 6}" text-anchor="middle" '
                f'font-size="11" fill="var(--soluk)">{escape(etiket)}</text>'
            )
    # Seçici doğrudan etiket: yalnız son değer yazılır, gerisi araç ipucunda.
    son_x, son_y = x(len(noktalar) - 1), y(degerler[-1])
    parcalar.append(
        f'<text x="{min(son_x + 8, en - 2):.1f}" y="{son_y - 8:.1f}" '
        f'text-anchor="end" font-size="12" font-weight="bold" '
        f'fill="var(--ikincil)">{_bicimle(degerler[-1])}</text>'
    )

    aciklama = escape(baslik or "gelişim grafiği")
    return (
        f'<svg viewBox="0 0 {en} {boy}" width="100%" role="img" '
        f'aria-label="{aciklama}" style="max-width:{en}px">' + "".join(parcalar) + "</svg>"
    )


def sutun_grafigi(
    kutular: list[tuple[str, int]],
    *,
    en: int = 560,
    boy: int = 190,
    baslik: str = "",
) -> str:
    """(etiket, adet) kutularından tek serilik dağılım grafiği."""
    if not kutular or all(adet == 0 for _, adet in kutular):
        return ""
    tavan = max(adet for _, adet in kutular)
    ic_en = en - _KENAR_SOL - _KENAR_SAG
    ic_boy = boy - _KENAR_UST - _KENAR_ALT
    taban = _KENAR_UST + ic_boy
    bosluk = 2.0  # işaretler arası yüzey aralığı
    genislik = ic_en / len(kutular) - bosluk

    parcalar: list[str] = [
        f'<line x1="{_KENAR_SOL}" y1="{taban:.1f}" x2="{en - _KENAR_SAG}" '
        f'y2="{taban:.1f}" stroke="var(--cizgi)" stroke-width="1"/>'
    ]
    for sira, (etiket, adet) in enumerate(kutular):
        sol = _KENAR_SOL + sira * (genislik + bosluk) + bosluk / 2
        yukseklik = ic_boy * adet / tavan if adet else 0.0
        ust = taban - yukseklik
        r = min(4.0, genislik / 2, yukseklik) if adet else 0.0
        # Uç yuvarlatma yalnız üstte: taban düz kalır, sütun tabana oturur.
        yol = (
            f"M {sol:.1f} {taban:.1f} L {sol:.1f} {ust + r:.1f} "
            f"Q {sol:.1f} {ust:.1f} {sol + r:.1f} {ust:.1f} "
            f"L {sol + genislik - r:.1f} {ust:.1f} "
            f"Q {sol + genislik:.1f} {ust:.1f} {sol + genislik:.1f} {ust + r:.1f} "
            f"L {sol + genislik:.1f} {taban:.1f} Z"
        )
        parcalar.append(
            f'<g><path d="{yol}" fill="var(--vurgu)"/>'
            f"<title>{escape(etiket)}: {adet}</title></g>"
        )
        if adet == tavan:
            parcalar.append(
                f'<text x="{sol + genislik / 2:.1f}" y="{ust - 5:.1f}" text-anchor="middle" '
                f'font-size="11" fill="var(--ikincil)">{adet}</text>'
            )
        parcalar.append(
            f'<text x="{sol + genislik / 2:.1f}" y="{boy - 6}" text-anchor="middle" '
            f'font-size="11" fill="var(--soluk)">{escape(etiket)}</text>'
        )

    aciklama = escape(baslik or "dağılım grafiği")
    return (
        f'<svg viewBox="0 0 {en} {boy}" width="100%" role="img" '
        f'aria-label="{aciklama}" style="max-width:{en}px">' + "".join(parcalar) + "</svg>"
    )


def kivilcim(degerler: list[float], *, en: int = 120, boy: int = 28) -> str:
    """Tablo satırına gömülecek eksensiz mini çizgi; son nokta işaretlidir."""
    if not degerler:
        return ""
    alt, ust = _aralik(degerler)
    pay = 4.0

    def x(sira: int) -> float:
        if len(degerler) == 1:
            return en / 2
        return pay + (en - 2 * pay) * sira / (len(degerler) - 1)

    def y(deger: float) -> float:
        return pay + (boy - 2 * pay) * (1 - (deger - alt) / (ust - alt))

    yol = " ".join(f"{x(i):.1f},{y(d):.1f}" for i, d in enumerate(degerler))
    cizgi = (
        f'<polyline points="{yol}" fill="none" stroke="var(--vurgu)" stroke-width="1.5"/>'
        if len(degerler) > 1
        else ""
    )
    return (
        f'<svg viewBox="0 0 {en} {boy}" width="{en}" height="{boy}" role="img" '
        f'aria-label="gelişim: son değer {_bicimle(degerler[-1])}">'
        + cizgi
        + f'<circle cx="{x(len(degerler) - 1):.1f}" cy="{y(degerler[-1]):.1f}" r="2.5" '
        'fill="var(--vurgu)"/></svg>'
    )
