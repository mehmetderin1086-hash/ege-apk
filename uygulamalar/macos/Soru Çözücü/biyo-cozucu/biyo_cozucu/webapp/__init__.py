"""FastAPI + Jinja2 arayüzü.

Rotalar konuya göre ayrı modüllerde; uygulama fabrikası bunları tek bir
`Uygulama` durumu üzerinde birleştirir.
"""

from __future__ import annotations

import ipaddress
import os
from pathlib import Path

from fastapi import Request

from .. import __version__
from ..cozucu import VARSAYILAN_KOK, Ayarlar
from ..motor.temel import MotorHatasi
from .durum import Uygulama

SABLON_DIZINI = Path(__file__).parent / "sablonlar"
STATIK_DIZINI = Path(__file__).parent / "statik"

# Kütüphane çağıranları tek denemede bırakır; doğrudan kullanıcıya açılan web
# yolu ise ölçülmüş daha güvenli ayarı kullanır. CLI ile aynı değerlerdir.
WEB_VARSAYILAN_DENEME = 3
WEB_VARSAYILAN_INCELEME_ESIGI = 0.70


def sablonlar_kur():
    from fastapi.templating import Jinja2Templates

    sablon = Jinja2Templates(directory=str(SABLON_DIZINI))
    sablon.env.filters["kisa"] = lambda m, n=120: (
        m if len(str(m)) <= n else str(m)[: n - 1] + "…"
    )
    return sablon


def uygulama_kur(
    kok: str | Path | None = None,
    *,
    motor_turu: str = "mlx",
    gommesiz: bool = False,
    ayarlar: Ayarlar | None = None,
):
    from fastapi import Body, FastAPI, HTTPException
    from fastapi.responses import JSONResponse, RedirectResponse
    from fastapi.staticfiles import StaticFiles

    from . import alim as alim_rotalari
    from . import cozum as cozum_rotalari
    from . import degerlendirme as degerlendirme_rotalari
    from . import egitim as egitim_rotalari
    from . import kes_ve_coz as kes_ve_coz_rotalari
    from . import merkez as merkez_rotalari
    from . import ornekler as ornek_rotalari
    from . import pano as pano_rotalari

    web_ayarlari = ayarlar or Ayarlar(
        deneme_sayisi=WEB_VARSAYILAN_DENEME,
        inceleme_esigi=WEB_VARSAYILAN_INCELEME_ESIGI,
    )
    durum = Uygulama(
        kok=Path(kok or VARSAYILAN_KOK),
        motor_turu=motor_turu,
        gommesiz=gommesiz,
        ayarlar=web_ayarlari,
    )
    sablon = sablonlar_kur()

    uygulama = FastAPI(title="biyo-cozucu", docs_url=None, redoc_url=None)
    uygulama.state.durum = durum
    uygulama.state.sablon = sablon

    def _loopback_dogrula(request: Request) -> None:
        """`/healthz` ve token'sız `/api/v1/uret` için ortak loopback denetimi.

        Sunucu yanlışlıkla dış bir adrese bağlansa bile bu uçlar uzak
        istemcilere yanıt vermez — sır taşımadıklarından token yerine bu
        adres denetimiyle korunurlar.
        """
        istemci = request.client
        try:
            adres = ipaddress.ip_address(istemci.host if istemci else "")
        except ValueError as exc:
            raise HTTPException(403, "Bu uç yalnız loopback içindir.") from exc
        eslenmis = getattr(adres, "ipv4_mapped", None)
        if not adres.is_loopback and not (eslenmis and eslenmis.is_loopback):
            raise HTTPException(403, "Bu uç yalnız loopback içindir.")

    @uygulama.get("/healthz", include_in_schema=False)
    def _saglik(request: Request):
        """Başlatıcının süreç/build doğrulaması için loopback sağlık ucu.

        Öğretmen Çantası API'sinin token korumalı sağlık ucundan ayrıdır:
        burada sır yoktur ve masaüstü başlatıcısı henüz tarayıcı açılmadan
        yalnız yerel sunucunun kimliğini doğrular.
        """
        _loopback_dogrula(request)
        return {
            "app": "biyo-cozucu",
            "build": os.environ.get("BIYO_BUILD_ID", __version__),
            "pid": os.getpid(),
            "status": "ready",
        }

    def _api_yetkili(request: Request) -> None:
        yol = Path(
            os.environ.get("OGRETMEN_API_TOKEN_YOLU")
            or Path.home()
            / (
                "Library/Application Support/OgretmenCantasi/"
                "entegrasyonlar/yerel-api.token"
            )
        )
        try:
            beklenen = yol.read_text(encoding="utf-8").strip()
        except OSError:
            beklenen = ""
        if (
            not beklenen
            or request.headers.get("authorization", "") != f"Bearer {beklenen}"
        ):
            raise HTTPException(401, "Yerel API yetkisi geçersiz.")

    @uygulama.get("/api/v1/health")
    def _api_saglik(request: Request):
        _api_yetkili(request)
        return {
            "app": "biyo-cozucu",
            "app_version": "gelistirme",
            "protocol_version": "v1",
            "status": "ready",
        }

    @uygulama.get("/api/v1/capabilities")
    def _api_yetenekler(request: Request):
        _api_yetkili(request)
        return {
            "protocol_version": "v1",
            "capabilities": ["sourced-suggestions"],
        }

    @uygulama.post("/api/v1/suggestions")
    async def _api_oneri(request: Request):
        _api_yetkili(request)
        try:
            veri = await request.json()
        except ValueError as exc:
            raise HTTPException(400, "Geçerli JSON gerekli.") from exc
        istem = str(veri.get("prompt") or "").strip()
        if not istem:
            raise HTTPException(400, "prompt zorunlu.")
        cozum = durum.cozucu().coz(istem)
        kaynaklar = [
            {
                "title": kanit.kaynak_adi(),
                "section": kanit.konu,
                "passage": kanit.cozum[:800],
                "score": kanit.skor,
                "example_id": kanit.ornek_id,
            }
            for kanit in cozum.kanitlar
        ]
        if not kaynaklar or not cozum.metin().strip():
            return {
                "status": "insufficient_evidence",
                "suggestion": "",
                "sources": kaynaklar,
                "model": cozum.model,
            }
        return {
            "status": "draft",
            "suggestion": cozum.metin(),
            "sources": kaynaklar,
            "model": cozum.model or cozum.uretim_yontemi,
            "requires_teacher_approval": True,
            "review": bool(cozum.incele),
            "warnings": cozum.uyarilar,
        }

    def _uret_mesaji_gecerli_mi(mesaj: object) -> bool:
        return (
            isinstance(mesaj, dict)
            and isinstance(mesaj.get("role"), str)
            and bool(mesaj.get("role"))
            and isinstance(mesaj.get("content"), str)
        )

    @uygulama.post("/api/v1/uret")
    def _api_uret(request: Request, govde: dict = Body(...)):
        """Motorun `uret` metodunu olduğu gibi açan ince proxy.

        `/coz/api` soruyu çözücünün kendi RAG hattından geçirir,
        `/api/v1/suggestions` Öğretmen Çantası Bearer token'ına bağlıdır —
        bu uç ikisi de değil: mesajları hiçbir dönüşüm yapmadan doğrudan
        motora iletir (sinav-okur gibi dış süreçlerin ham üretime ihtiyacı
        için). `/healthz` ile aynı loopback-only koruma; sır taşımadığından
        token yok. Senkron tanım `/coz/api` ile aynı desende: FastAPI bunu
        iş parçacığı havuzunda koşturur, uzun üretim olay döngüsünü
        bloklamaz.
        """
        _loopback_dogrula(request)

        mesajlar = govde.get("mesajlar")
        if (
            not isinstance(mesajlar, list)
            or not mesajlar
            or not all(_uret_mesaji_gecerli_mi(m) for m in mesajlar)
        ):
            raise HTTPException(
                422,
                "mesajlar; her biri 'role' ve 'content' taşıyan dolu bir liste olmalı.",
            )
        sicaklik = govde.get("sicaklik", 0.2)
        azami_token = govde.get("azami_token", 1536)
        if not isinstance(sicaklik, (int, float)) or isinstance(sicaklik, bool):
            raise HTTPException(422, "sicaklik sayısal olmalı.")
        if not isinstance(azami_token, int) or isinstance(azami_token, bool):
            raise HTTPException(422, "azami_token tam sayı olmalı.")

        motor = durum.motor
        if motor is None:
            return JSONResponse(
                {"hata": durum.motor_hatasi or "Motor kullanılamıyor."},
                status_code=502,
            )
        try:
            metin = motor.uret(
                mesajlar, sicaklik=float(sicaklik), azami_token=azami_token
            )
        except MotorHatasi as exc:
            return JSONResponse({"hata": str(exc)}, status_code=502)
        return {"metin": metin, "model": getattr(motor, "ad", None)}

    STATIK_DIZINI.mkdir(parents=True, exist_ok=True)
    uygulama.mount(
        "/statik", StaticFiles(directory=str(STATIK_DIZINI)), name="statik"
    )

    @uygulama.get("/", include_in_schema=False)
    def _kok_yonlendir():
        # Stüdyo çatısı altında açılış sayfası Merkez'dir: kesici, çözücü ve
        # BioProf'a tek yerden geçilir.
        return RedirectResponse("/merkez", status_code=303)

    # Kes ve Çöz kalıcı bir SQLite kuyruğu ve tek işçili yürütücü taşır.
    # Router'ı ayrıca yakalayıp uygulama yaşam döngüsüne bağlamak; yeniden
    # başlatmada yarım işi güvenle bırakmak ve DB/subprocess kaynaklarını
    # kapanışta serbest bırakmak için gerekli.
    kes_ve_coz_router = kes_ve_coz_rotalari.yonlendirici(durum, sablon)
    kes_ve_coz_servisi = kes_ve_coz_router.kes_ve_coz_servisi
    uygulama.state.kes_ve_coz_servisi = kes_ve_coz_servisi
    uygulama.include_router(kes_ve_coz_router)
    uygulama.router.add_event_handler("shutdown", kes_ve_coz_servisi.kapat)

    # YouTube alımı da aynı gerekçeyle ayrı yakalanıyor: kendi SQLite iş
    # kaydını ve tek işçili yürütücüsünü taşıyor.
    from . import youtube as youtube_rotalari

    youtube_router = youtube_rotalari.yonlendirici(durum, sablon)
    youtube_servisi = youtube_router.youtube_servisi
    uygulama.state.youtube_servisi = youtube_servisi
    uygulama.include_router(youtube_router)
    uygulama.router.add_event_handler("shutdown", youtube_servisi.kapat)

    for modul in (
        merkez_rotalari,
        cozum_rotalari,
        ornek_rotalari,
        alim_rotalari,
        egitim_rotalari,
        pano_rotalari,
        degerlendirme_rotalari,
    ):
        uygulama.include_router(modul.yonlendirici(durum, sablon))

    return uygulama


__all__ = ["Uygulama", "uygulama_kur"]
