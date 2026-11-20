"""Rotalar arası ortak yardımcılar."""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import HTMLResponse

from .durum import Uygulama


def hata_yaniti(
    sablon,
    durum: Uygulama,
    istek: Request,
    mesaj: str,
    *,
    kod: int = 400,
    baslik: str = "",
    oneri: str = "",
    geri: str = "",
) -> HTMLResponse:
    """Stilli, gezinilebilir hata sayfası.

    Çıplak `HTMLResponse("...", status_code=...)` kullanıcıyı navigasyonsuz
    beyaz bir sayfada bırakıp tarayıcı geri düğmesine mahkûm ediyordu.
    """
    return sablon.TemplateResponse(
        istek,
        "hata.html",
        {
            "durum": durum.durum(),
            "mesaj": mesaj,
            "baslik": baslik,
            "oneri": oneri,
            "geri": geri,
        },
        status_code=kod,
    )


def guvenli_geri(yol: str, varsayilan: str = "/coz") -> str:
    """Yalnız site içi göreli yolları kabul eder (açık yönlendirme koruması).

    Ters eğik çizgi de ayraç sayılır: tarayıcılar "special scheme"lerde `\\`
    ile `/` karakterini denk görür, bu yüzden `/\\kotu.example.com` başlığı
    `//kotu.example.com` gibi çözülüp site dışına yönlendirirdi. Yalnız
    `//` kontrolü yapmak bu yüzden yetmiyor.
    """
    yol = (yol or "").strip()
    if not yol.startswith("/"):
        return varsayilan
    if len(yol) > 1 and yol[1] in "/\\":
        return varsayilan
    # Satır sonu enjeksiyonu başlığı bölebilir.
    if any(k in yol for k in ("\r", "\n")):
        return varsayilan
    return yol


def sayfa_araligi(sayfa: int, boyut: int, toplam: int) -> dict[str, int | bool]:
    """Sayfalama şablonlarının beklediği hazır değerler."""
    boyut = max(1, boyut)
    son = max(1, -(-toplam // boyut))  # tavana bölme
    sayfa = min(max(1, sayfa), son)
    return {
        "sayfa": sayfa,
        "boyut": boyut,
        "toplam": toplam,
        "son_sayfa": son,
        "offset": (sayfa - 1) * boyut,
        "onceki_var": sayfa > 1,
        "sonraki_var": sayfa < son,
        "ilk_sira": 0 if toplam == 0 else (sayfa - 1) * boyut + 1,
        "son_sira": min(sayfa * boyut, toplam),
    }
