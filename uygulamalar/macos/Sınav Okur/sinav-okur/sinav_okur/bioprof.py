"""Çalışan BioProf'un yerel evidence modelini Sınav Okur RAG'ına bağlar."""

from __future__ import annotations

import os
from urllib.parse import urlparse

from .referans import YerelRAGCevabi, YerelRAGDeposu
from .yapay_zeka import YapayZekaHatasi, _json_istek


def _aday_adresler() -> list[str]:
    ozel = os.environ.get("SINAV_OKUR_BIOPROF_URL", "").strip().rstrip("/")
    if ozel:
        return [ozel]
    return [f"http://127.0.0.1:{port}" for port in [8766, 8765, *range(8767, 8776)]]


def bioprof_bul() -> str | None:
    for adres in _aday_adresler():
        parsed = urlparse(adres)
        if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
            continue
        try:
            hazir = _json_istek(f"{adres}/readyz", timeout=0.5)
            if not hazir.get("ready"):
                continue
            modeller = _json_istek(f"{adres}/v1/models", timeout=1.0)
            kimlikler = {x.get("id") for x in modeller.get("data", [])}
            if "local_evidence/bioprof-evidence" in kimlikler:
                return adres
        except YapayZekaHatasi:
            continue
    return None


def bioprof_durumu() -> dict:
    adres = bioprof_bul()
    notebook = bioprof_kaynakli_notebook(adres) if adres else None
    return {
        "hazir": adres is not None,
        "kaynak_hazir": notebook is not None,
        "kaynak_sayisi": len(notebook[1]) if notebook else 0,
        "mesaj": (
            (
                f"BioProf yerel evidence modeli hazır · "
                f"{len(notebook[1])} kitap/not kaynağı"
            )
            if notebook
            else f"BioProf yerel evidence modeli hazır · {adres}"
            if adres
            else "BioProf kapalı; Sınav Okur yerel kitap RAG kullanılacak."
        ),
    }


def bioprof_kaynakli_notebook(
    adres: str | None = None,
) -> tuple[str, list[dict]] | None:
    """Hazır kaynağı olan BioProf notebook'unu bulur; biyoloji kaynağını öne alır."""
    adres = adres or bioprof_bul()
    if not adres:
        return None
    try:
        notebooklar = _json_istek(f"{adres}/api/v1/notebooks", timeout=2.0)
        adaylar = []
        for notebook in notebooklar:
            kimlik = str(notebook.get("id", ""))
            if not kimlik:
                continue
            kaynaklar = _json_istek(
                f"{adres}/api/v1/notebooks/{kimlik}/sources", timeout=2.0
            )
            hazir = [x for x in kaynaklar if x.get("status") == "ready"]
            if not hazir:
                continue
            aranabilir = " ".join(
                [
                    str(notebook.get("name", "")),
                    *(str(x.get("title", "")) for x in hazir),
                ]
            ).casefold()
            oncelik = int(any(k in aranabilir for k in ("biyoloji", "biology", "campbell")))
            adaylar.append((oncelik, kimlik, hazir))
        if not adaylar:
            return None
        _oncelik, kimlik, kaynaklar = max(adaylar, key=lambda x: (x[0], len(x[2])))
        return kimlik, kaynaklar
    except (YapayZekaHatasi, TypeError, AttributeError):
        return None


def bioprof_notebook_ile_cevapla(
    sorular: list[tuple[int, str, float]],
) -> list[YerelRAGCevabi]:
    """BioProf'a daha önce yüklenmiş kitaplardan strict, yerel ve kaynaklı yanıt alır."""
    adres = bioprof_bul()
    secim = bioprof_kaynakli_notebook(adres)
    if not adres or not secim:
        raise ValueError("BioProf'ta kullanıma hazır kitap/not kaynağı bulunamadı.")
    notebook_id, _kaynaklar = secim
    sonuclar = []
    for no, soru, _puan in sorular:
        try:
            yanit = _json_istek(
                f"{adres}/api/v1/notebooks/{notebook_id}/ask",
                veri={
                    "question": soru,
                    "mode": "strict",
                    "provider": "local_evidence",
                    "model": "bioprof-evidence",
                    "speak": False,
                },
                timeout=45.0,
            )
            cevap = str(yanit.get("answer_markdown", "")).strip()
            if not cevap:
                raise ValueError(f"{no}. soru için BioProf yanıt üretemedi.")
            rubrik = [
                str(x.get("text", "")).strip()[:220]
                for x in yanit.get("claims", [])
                if x.get("supported") and str(x.get("text", "")).strip()
            ][:4]
            kaynaklar = list(
                dict.fromkeys(
                    (
                        f"{x.get('source_title', 'BioProf kaynağı')}"
                        + (f" · sayfa {x['page']}" if x.get("page") else "")
                    )
                    for x in yanit.get("citations", [])
                )
            )
            sonuclar.append(
                YerelRAGCevabi(
                    soru_no=no,
                    cevap=cevap,
                    rubrik=rubrik or [cevap[:220]],
                    kaynaklar=kaynaklar or ["BioProf yerel kitaplığı"],
                )
            )
        except (YapayZekaHatasi, KeyError, TypeError, AttributeError) as exc:
            raise ValueError(f"{no}. soru BioProf ile yanıtlanamadı: {exc}") from exc
    return sonuclar


def bioprof_ile_cevapla(
    depo: YerelRAGDeposu,
    sorular: list[tuple[int, str, float]],
) -> list[YerelRAGCevabi]:
    """BioProf'a yalnız yerel kitap kanıtı verir; dış sağlayıcı kullanılmaz."""
    adres = bioprof_bul()
    yerel = {x.soru_no: x for x in depo.cevap_uret(sorular)}
    if not adres:
        return list(yerel.values())
    sonuclar = []
    for no, soru, _puan in sorular:
        kanitlar = [
            {
                "label": f"S{i}",
                "text": pasaj.metin,
                "source": pasaj.kaynak,
            }
            for i, (pasaj, _skor) in enumerate(depo.ilgili(soru, k=5), 1)
        ]
        try:
            yanit = _json_istek(
                f"{adres}/v1/chat/completions",
                veri={
                    "model": "local_evidence/bioprof-evidence",
                    "provider": "local_evidence",
                    "stream": False,
                    "messages": [{"role": "user", "content": soru}],
                    "metadata": {"evidence": kanitlar},
                },
                timeout=20.0,
            )
            metin = str(yanit["choices"][0]["message"]["content"]).strip()
            if "yeterli kanıt bulamadım" in metin.casefold():
                metin = yerel[no].cevap
        except (YapayZekaHatasi, KeyError, IndexError, TypeError):
            metin = yerel[no].cevap
        sonuclar.append(
            YerelRAGCevabi(
                soru_no=no,
                cevap=metin,
                rubrik=yerel[no].rubrik,
                kaynaklar=yerel[no].kaynaklar,
            )
        )
    return sonuclar
