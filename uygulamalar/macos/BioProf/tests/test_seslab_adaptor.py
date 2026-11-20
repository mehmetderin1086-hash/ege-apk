"""SesLab adaptörünün sınır davranışları.

SesLab'ın /v1/audio/speech ucu speed'i 0.5-2.0 ile sınırlar; adaptörün
aynı sınırı uygulaması 422 sürprizini istemci hatasına çevirir.
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx
import pytest

from bioprof.providers.base import ProviderError
from bioprof.voice.seslab import SesLabAdapter


def _adapter(handler) -> SesLabAdapter:
    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    return SesLabAdapter(base_url="http://127.0.0.1:8010", client=client)


def _wav_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, content=b"RIFFxxxx", headers={"content-type": "audio/wav"})


def test_speed_sinir_disi_reddedilir() -> None:
    adapter = _adapter(_wav_handler)
    for speed in (0.4, 2.1, 0.25, 4.0):
        with pytest.raises(ProviderError):
            asyncio.run(adapter.synthesize("Merhaba", speed=speed))


def test_speed_sinir_ici_gecer_ve_language_gonderilir() -> None:
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        return _wav_handler(request)

    adapter = _adapter(handler)
    payload = asyncio.run(adapter.synthesize("Merhaba", speed=2.0))
    assert payload.data == b"RIFFxxxx"
    assert captured["language"] == "tr"
    assert captured["speed"] == 2.0
    assert "verify" not in captured


def test_bos_ses_verisi_hata() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"", headers={"content-type": "audio/wav"})

    adapter = _adapter(handler)
    with pytest.raises(ProviderError):
        asyncio.run(adapter.synthesize("Merhaba"))


def test_bos_metin_hata() -> None:
    adapter = _adapter(_wav_handler)
    with pytest.raises(ProviderError):
        asyncio.run(adapter.synthesize("   "))


class TestPartiliMastering:
    """200 parça sınırının üstü iki seviyede birleşir; süre ve boşluk korunur."""

    def _sayac_handler(self, sayac: dict, *, grup_sure_bozuk: bool = False):
        import json as _json

        def handler(request: httpx.Request) -> httpx.Response:
            govde = request.content
            n = govde.count(b'name="files"')
            seviye2 = b"\r\nfalse\r\n" in govde  # normalize=false yalnız 2. seviyede
            if not seviye2:
                bas = sayac["sonraki"]
                sureler = [float(i) for i in range(bas, bas + n)]
                if grup_sure_bozuk and sayac["grup_istekleri"]:
                    sureler = sureler[:-1]  # ikinci grupta eksik liste
                sayac["sonraki"] += n
                sayac["grup_istekleri"].append(n)
                return httpx.Response(
                    200,
                    content=b"GRUPWAV",
                    headers={
                        "content-type": "audio/wav",
                        "X-Segment-Durations": _json.dumps(sureler),
                    },
                )
            sayac["birlesim"] += 1
            sayac["birlesim_parca"] = n
            return httpx.Response(
                200, content=b"SONWAV", headers={"content-type": "audio/wav"}
            )

        return handler

    def test_sinir_alti_tek_istekte_birlesir(self) -> None:
        sayac = {"sonraki": 0, "grup_istekleri": [], "birlesim": 0}
        adapter = _adapter(self._sayac_handler(sayac))
        payload = asyncio.run(adapter.master([b"CHUNK"] * 5))
        assert payload is not None and payload.data == b"GRUPWAV"
        assert sayac["grup_istekleri"] == [5]
        assert sayac["birlesim"] == 0

    def test_240_parca_iki_grupta_master_edilir_sira_korunur(self) -> None:
        sayac = {"sonraki": 0, "grup_istekleri": [], "birlesim": 0}
        adapter = _adapter(self._sayac_handler(sayac))
        payload = asyncio.run(adapter.master([b"CHUNK"] * 240))
        assert payload is not None and payload.data == b"SONWAV"
        assert sayac["grup_istekleri"] == [160, 80]
        # Seviye 2 tam olarak grup WAV'larını birleştirir.
        assert sayac["birlesim"] == 1 and sayac["birlesim_parca"] == 2
        sureler = payload.metadata["segment_durations"]
        assert len(sureler) == 240
        assert sureler == sorted(sureler)  # sıra korunuyor

    def test_grup_sure_listesi_eksikse_sure_hic_verilmez(self) -> None:
        # Kısmi liste altyazıyı sessizce kaydırır; hiç yokmuş gibi davranılmalı.
        sayac = {"sonraki": 0, "grup_istekleri": [], "birlesim": 0}
        adapter = _adapter(self._sayac_handler(sayac, grup_sure_bozuk=True))
        payload = asyncio.run(adapter.master([b"CHUNK"] * 240))
        assert payload is not None
        assert payload.metadata == {}

    def test_eski_seslab_404_none_doner(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(404)

        adapter = _adapter(handler)
        assert asyncio.run(adapter.master([b"CHUNK"] * 240)) is None

    def test_grup_hatasi_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(500)

        adapter = _adapter(handler)
        with pytest.raises(ProviderError):
            asyncio.run(adapter.master([b"CHUNK"] * 240))
