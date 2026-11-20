"""FastAPI tabanlı gözden geçirme arayüzü — uygulama fabrikası.

`uygulama_kur` tek bir `WebBaglam` kurar ve her biri kendi sorumluluğunu
taşıyan router modüllerini (`api_v1`, `referans`, `gelisim`, `yukle`,
`kagit`, `sinav`, `genel`) `app.include_router(...)` ile bağlar. Rota
gövdeleri artık burada değil, ilgili modüldedir; bu dosya yalnız kurulumu
yapar.
"""

from __future__ import annotations

import ipaddress
import os
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import (
    anahtar_yukle,
    api_v1,
    gelisim,
    genel,
    kagit,
    kapi,
    referans,
    sinav,
    yukle,
)
from .baglam import WebBaglam
from .. import __version__
from ..depo import Depo

_SABLON_DIZINI = Path(__file__).parent / "templates"


def uygulama_kur(
    db_yolu: str = "sinav_okur.db",
    kirp_dizini: str = "kirpintlar",
    veri_dizini: str | None = None,
    taniyici_fabrikasi=None,
    serbest_cozumleyici=None,
    yerel_uretici=None,
    yerel_uret=None,
) -> FastAPI:
    app = FastAPI(title="sinav-okur")
    depo = Depo(db_yolu)
    sablonlar = Jinja2Templates(directory=str(_SABLON_DIZINI))

    @app.exception_handler(StarletteHTTPException)
    async def hata_isleyici(request, exc):
        # API istemcileri ve programatik çağrılar (testler dahil) JSON almaya
        # devam eder; yalnız tarayıcıdan gelen HTML istekleri şablona düşer.
        html_ister = "text/html" in request.headers.get("accept", "")
        if request.url.path.startswith("/api/") or not html_ister:
            return JSONResponse(
                {"detail": exc.detail},
                status_code=exc.status_code,
                headers=getattr(exc, "headers", None),
            )
        return sablonlar.TemplateResponse(
            request,
            "hata.html",
            {"durum": exc.status_code, "mesaj": exc.detail},
            status_code=exc.status_code,
            headers=getattr(exc, "headers", None),
        )
    kirp_kok = Path(kirp_dizini)
    kirp_kok.mkdir(parents=True, exist_ok=True)
    db_kok = Path(db_yolu).resolve().parent
    veri_kok = Path(veri_dizini).resolve() if veri_dizini else db_kok / "sinav_okur_veri"
    sinav_dizini = veri_kok / "sinavlar"
    yukleme_dizini = veri_kok / "yuklemeler"
    serbest_taslak_dizini = veri_kok / "serbest_taslaklar"
    referans_kok = veri_kok / "referans"
    referans_kaynak_dizini = referans_kok / "kaynaklar"
    referans_indeks_dizini = referans_kok / "yerel_indeks"
    toplu_sonuc_dizini = veri_kok / "toplu_sonuclar"
    sinav_dizini.mkdir(parents=True, exist_ok=True)
    yukleme_dizini.mkdir(parents=True, exist_ok=True)
    serbest_taslak_dizini.mkdir(parents=True, exist_ok=True)
    referans_kaynak_dizini.mkdir(parents=True, exist_ok=True)
    toplu_sonuc_dizini.mkdir(parents=True, exist_ok=True)
    proje_kok = Path(__file__).resolve().parents[2]

    def _trocr_model_yolu() -> Path:
        # htr/trocr.py:yerel_model_yolu ile aynı öncelik: özel env, yoksa proje kökü.
        ozel = os.environ.get("SINAV_OKUR_TROCR_MODEL")
        return Path(ozel) if ozel else proje_kok / "modeller/trocr-tr"

    def _karakter_model_yolu() -> Path:
        ozel = os.environ.get("SINAV_OKUR_KARAKTER_MODEL")
        return (
            Path(ozel)
            if ozel
            else proje_kok / "modeller/karakter_cnn/turkce_karakter_cnn.keras"
        )

    # Apple Vision aracı yalnız macOS'ta derlenip çalışır; başka platformda
    # hiç var olmayacak bir yola işaret ederek "hazır" denetimini xcrun'a
    # bakmadan sessizce False'a düşürür.
    _vision_araci_yolu = (
        Path("/usr/bin/xcrun")
        if sys.platform == "darwin"
        else proje_kok / "_apple_vision_yalniz_macosta"
    )
    model_yollari = {
        "coklu": _vision_araci_yolu,
        "vision": _vision_araci_yolu,
        "trocr": _trocr_model_yolu(),
        "keras-karakter": _karakter_model_yolu(),
        "keras-ctc": proje_kok / "modeller/gercek_satir_ctc/turkce_gercek_satir_ctc.keras",
        # HF repo kimliği; diskte bir dosyaya karşılık gelmediği için
        # varlık kontrolü yapılmaz (mlx-vlm kendi önbelleğinden yükler).
        "mlx": Path("mlx-community/Qwen3-VL-4B-Instruct-4bit"),
    }
    taniyici_onbellegi: dict[str, object] = {}
    app.mount("/kirpinti", StaticFiles(directory=str(kirp_kok)), name="kirpinti")
    app.mount(
        "/statik",
        StaticFiles(directory=str(Path(__file__).parent / "statik")),
        name="statik",
    )

    entegrasyon_dizini = veri_kok / "entegrasyonlar"
    entegrasyon_dizini.mkdir(parents=True, exist_ok=True)

    baglam = WebBaglam(
        depo=depo,
        sablonlar=sablonlar,
        kirp_kok=kirp_kok,
        veri_kok=veri_kok,
        sinav_dizini=sinav_dizini,
        yukleme_dizini=yukleme_dizini,
        serbest_taslak_dizini=serbest_taslak_dizini,
        referans_kok=referans_kok,
        referans_kaynak_dizini=referans_kaynak_dizini,
        referans_indeks_dizini=referans_indeks_dizini,
        toplu_sonuc_dizini=toplu_sonuc_dizini,
        entegrasyon_dizini=entegrasyon_dizini,
        proje_kok=proje_kok,
        model_yollari=model_yollari,
        taniyici_onbellegi=taniyici_onbellegi,
        taniyici_fabrikasi=taniyici_fabrikasi,
        serbest_cozumleyici=serbest_cozumleyici,
        yerel_uretici=yerel_uretici,
        yerel_uret=yerel_uret,
    )

    # Testler ve teşhis araçları uygulamanın gerçek bağlamına erişebilsin
    # (sorgu sayacı, önbellek denetimi). Rotalar bunu kullanmaz.
    app.state.baglam = baglam

    app.include_router(api_v1.rota_kur(baglam))
    app.include_router(referans.rota_kur(baglam))
    app.include_router(gelisim.rota_kur(baglam))
    app.include_router(yukle.rota_kur(baglam))
    app.include_router(kagit.rota_kur(baglam))
    app.include_router(sinav.rota_kur(baglam))
    app.include_router(anahtar_yukle.rota_kur(baglam))
    app.include_router(kapi.rota_kur(baglam))
    app.include_router(genel.rota_kur(baglam))

    @app.get("/healthz", include_in_schema=False)
    def _saglik(request: Request):
        """Başlatıcının süreç doğrulaması için token'sız, yalnız-loopback sağlık ucu.

        biyo-cozucu'daki aynı desenin sinav-okur karşılığı: sır taşımadığından
        token yerine istemcinin loopback olduğu denetlenir.
        """
        istemci = request.client
        try:
            adres = ipaddress.ip_address(istemci.host if istemci else "")
        except ValueError as exc:
            raise HTTPException(403, "Bu uç yalnız loopback içindir.") from exc
        eslenmis = getattr(adres, "ipv4_mapped", None)
        if not adres.is_loopback and not (eslenmis and eslenmis.is_loopback):
            raise HTTPException(403, "Bu uç yalnız loopback içindir.")
        return {"app": "sinav-okur", "status": "ready", "version": __version__}

    return app
