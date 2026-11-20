"""Biyoloji Stüdyosu Merkezi — yerel servisleri tek sayfadan görür ve başlatır.

Stüdyo tek bir program gibi görünse de altında bağımsız süreçler çalışır:
Soru Kesici (ayrı Python 3.9 ortamı) ve BioProf (ayrı uv projesi). Bu modül
onların kimliğini imza yoklamasıyla doğrular, kapalı olanları kullanıcı
isteğiyle başlatır.

İki tasarım kuralı:

* **Port dolu olmak "çalışıyor" demek değildir.** Her yoklama ``/healthz``
  yanıtındaki uygulama imzasına bakar; imza tutmazsa durum "çakışma"dır.
* **Başlatma tek bir yerden serileşir.** Aynı servisi iki sekme, launcher ve
  eski bir ``.app`` aynı anda başlatmaya kalkabilir; dosya kilidi + kilit
  altında ikinci yoklama bunu tekilleştirir.
"""

from __future__ import annotations

import fcntl
import ipaddress
import os
import socket
import subprocess
import sys
from contextlib import closing, suppress
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .durum import Uygulama

YOKLAMA_ZAMAN_ASIMI = 0.6
LOG_DIZINI = (
    Path(os.environ["LOCALAPPDATA"]) / "Cumhuriyet" / "biyocozucu" / "data" / "logs"
    if os.name == "nt" and os.environ.get("LOCALAPPDATA")
    else Path.home() / "Library" / "Logs" / "BiyoCozucu"
)
BIOPROF_VARSAYILAN_KOK = (
    Path.home() / "Library" / "Application Support" / "BioProf" / "runtime"
)
UV_ADAYLARI = (
    Path.home() / ".local" / "bin" / "uv",
    Path("/opt/homebrew/bin/uv"),
    Path("/usr/local/bin/uv"),
)
SORU_KESICI_PORTU = 8756


def _soru_kesici_python(kok):
    """Soru Kesici yorumlayıcısı: SORU_KESICI_PY env > platform venv yolu."""
    import os as _os
    ozel = _os.environ.get("SORU_KESICI_PY")
    if ozel:
        return Path(ozel)
    if _os.name == "nt":
        return kok / "runtime" / "python.exe"
    return kok / ".venv" / "bin" / "python"
BIOPROF_PORTLARI = (8766, *range(8765, 8776))
SESLAB_PORTU = 8010
CLI_PROXY_PORTU = 8317

# Başlatılan çocuk süreçler: uzun ömürlü sunucular oldukları için normalde
# beklemeyiz, ama hemen ölen bir çocuk biz ``poll()`` çağırana kadar zombi
# kalır. Her Merkez isteğinde biriktirilmiş olanları topluyoruz.
_COCUKLAR: list[subprocess.Popen[bytes]] = []


def _cocuklari_topla() -> None:
    for surec in list(_COCUKLAR):
        if surec.poll() is not None:
            _COCUKLAR.remove(surec)


@dataclass
class ServisDurumu:
    anahtar: str
    ad: str
    aciklama: str
    simge: str
    durum: str = "kapali"  # calisiyor | kapali | cakisma | kurulu-degil
    url: str = ""
    ayrinti: str = ""
    baslatilabilir: bool = False
    ic_baglanti: bool = False
    surum: str = ""


@dataclass
class IcSayfa:
    yol: str
    ad: str
    aciklama: str
    simge: str


IC_SAYFALAR = (
    IcSayfa("/kes-ve-coz", "Kes ve çöz", "Kitaptan çözüme tek akış", "K"),
    IcSayfa("/coz", "Soru çöz", "Tek soruyu hemen çöz", "Ç"),
    IcSayfa("/cozumler", "Sonuçlar", "Çözümleri onayla ve düzelt", "S"),
    IcSayfa("/kuyruk", "Onay kuyruğu", "Çıkarılan soruları gözden geçir", "O"),
    IcSayfa("/pano", "Pano", "Hafıza ve kalite özeti", "P"),
)


@dataclass
class DisServis:
    anahtar: str
    ad: str
    aciklama: str
    simge: str
    portlar: tuple[int, ...]
    imza: str  # "soru-kesici" | "bioprof" | "seslab" | "cliproxy"
    baslatilabilir: bool = False
    saglik_yolu: str = "/healthz"
    ek: dict[str, Any] = field(default_factory=dict)


DIS_SERVISLER = (
    DisServis(
        "soru-kesici",
        "Soru Kesici",
        "PDF ve testlerden soru keser",
        "✂",
        (SORU_KESICI_PORTU,),
        "soru-kesici",
        baslatilabilir=True,
    ),
    DisServis(
        "bioprof",
        "BioProf",
        "Kanıta dayalı biyoloji/tıp asistanı",
        "🧬",
        BIOPROF_PORTLARI,
        "bioprof",
        baslatilabilir=True,
    ),
    DisServis(
        "seslab",
        "SesLab",
        "Seslendirme ve transkripsiyon (BioProf yardımcısı)",
        "🎙",
        (SESLAB_PORTU,),
        "seslab",
        saglik_yolu="/api/system/status",
    ),
    DisServis(
        "cliproxy",
        "CLI Proxy",
        "Uzak sağlayıcı köprüsü (BioProf yardımcısı)",
        "🔌",
        (CLI_PROXY_PORTU,),
        "cliproxy",
    ),
)


def _imza_uyar_mi(imza: str, veri: Any) -> tuple[bool, str]:
    """Yanıt gövdesinin beklenen uygulamaya ait olup olmadığını söyler."""
    if not isinstance(veri, dict):
        return False, ""
    if imza == "soru-kesici":
        return veri.get("app") == "soru-kesici", str(veri.get("version") or "")
    if imza == "bioprof":
        uyar = veri.get("status") in {"ok", "degraded"} and "version" in veri
        return bool(uyar), str(veri.get("version") or "")
    if imza == "seslab":
        # SesLab durum ucu sürüm/servis alanları taşır; en azından sözlük
        # dönmesi ve HTTP 200 olması yeterli ayırt edicidir (port zaten ona ayrılmış).
        return True, str(veri.get("version") or "")
    if imza == "cliproxy":
        return True, str(veri.get("version") or "")
    return False, ""


def _port_dolu_mu(port: int) -> bool:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as soket:
        soket.settimeout(0.2)
        return soket.connect_ex(("127.0.0.1", port)) == 0


async def _servisi_yokla(servis: DisServis) -> ServisDurumu:
    import httpx

    sonuc = ServisDurumu(
        anahtar=servis.anahtar,
        ad=servis.ad,
        aciklama=servis.aciklama,
        simge=servis.simge,
        baslatilabilir=servis.baslatilabilir,
    )
    dolu_ama_yabanci: list[int] = []
    async with httpx.AsyncClient(timeout=YOKLAMA_ZAMAN_ASIMI) as istemci:
        for port in dict.fromkeys(servis.portlar):
            taban = f"http://127.0.0.1:{port}"
            try:
                yanit = await istemci.get(taban + servis.saglik_yolu)
            except httpx.HTTPError:
                continue
            if yanit.status_code != 200:
                dolu_ama_yabanci.append(port)
                continue
            try:
                veri = yanit.json()
            except ValueError:
                dolu_ama_yabanci.append(port)
                continue
            uyar, surum = _imza_uyar_mi(servis.imza, veri)
            if uyar:
                sonuc.durum = "calisiyor"
                sonuc.url = taban
                sonuc.surum = surum
                return sonuc
            dolu_ama_yabanci.append(port)
    if dolu_ama_yabanci:
        sonuc.durum = "cakisma"
        portlar = ", ".join(str(p) for p in dolu_ama_yabanci)
        sonuc.ayrinti = f"Port {portlar} dolu ama yanıt {servis.ad} imzası taşımıyor."
        return sonuc
    if servis.anahtar == "soru-kesici" and _soru_kesici_koku() is None:
        sonuc.durum = "kurulu-degil"
        sonuc.baslatilabilir = False
        sonuc.ayrinti = "Soru Kesici klasörü bulunamadı."
    elif servis.anahtar == "bioprof" and _bioprof_koku() is None:
        sonuc.durum = "kurulu-degil"
        sonuc.baslatilabilir = False
        sonuc.ayrinti = "BioProf çalışma klasörü bulunamadı."
    return sonuc


def _soru_kesici_koku() -> Path | None:
    from .kes_ve_coz import KesVeCozHatasi
    from .kes_ve_coz import _soru_kesici_koku as cozumle

    try:
        return cozumle()
    except KesVeCozHatasi:
        return None


def _bioprof_koku() -> Path | None:
    ortam = os.environ.get("BIOPROF_KOK", "").strip()
    adaylar = [Path(ortam).expanduser()] if ortam else []
    isaret = (
        Path.home()
        / "Desktop"
        / "BioProf.app"
        / "Contents"
        / "Resources"
        / "runtime-path"
    )
    with suppress(OSError):
        yazili = isaret.read_text(encoding="utf-8").strip()
        if yazili:
            adaylar.append(Path(yazili).expanduser())
    adaylar.append(BIOPROF_VARSAYILAN_KOK)
    for aday in adaylar:
        if (aday / "pyproject.toml").is_file():
            return aday
    return None


def _uv_yolu() -> Path | None:
    for aday in UV_ADAYLARI:
        if aday.is_file() and os.access(aday, os.X_OK):
            return aday
    return None


def _bos_port_bul(portlar: tuple[int, ...]) -> int | None:
    for port in dict.fromkeys(portlar):
        if not _port_dolu_mu(port):
            return port
    return None


def _baslatma_komutu(anahtar: str) -> tuple[list[str], Path]:
    """Servis için kabuk kullanmayan sabit komut ve çalışma dizini üretir."""
    if anahtar == "soru-kesici":
        kok = _soru_kesici_koku()
        if kok is None:
            raise HTTPException(404, "Soru Kesici klasörü bulunamadı.")
        python = _soru_kesici_python(kok)
        if not python.is_file():
            raise HTTPException(
                409, f"Soru Kesici Python ortamı yok: {python}"
            )
        return [str(python), str(kok / "soru_kes_web.py")], kok
    if anahtar == "bioprof":
        kok = _bioprof_koku()
        if kok is None:
            raise HTTPException(404, "BioProf çalışma klasörü bulunamadı.")
        uv = _uv_yolu()
        if uv is None:
            raise HTTPException(409, "uv bulunamadı; BioProf başlatılamıyor.")
        port = _bos_port_bul(BIOPROF_PORTLARI)
        if port is None:
            raise HTTPException(409, "8765-8775 aralığında boş port yok.")
        return (
            [
                str(uv),
                "run",
                "--project",
                str(kok),
                "--no-sync",
                "python",
                "-m",
                "bioprof.cli",
                "serve",
                "--port",
                str(port),
            ],
            kok,
        )
    raise HTTPException(404, "Bilinmeyen servis.")


def _servis_tanimi(anahtar: str) -> DisServis:
    for servis in DIS_SERVISLER:
        if servis.anahtar == anahtar:
            return servis
    raise HTTPException(404, "Bilinmeyen servis.")


def _loopback_dogrula(request: Request) -> None:
    """Yalnız yerel makineden ve kendi sayfamızdan gelen isteklere izin verir.

    Loopback kontrolü uzak istemciyi keser; Origin kontrolü ise tarayıcıdaki
    yabancı bir sayfanın (CSRF) bizim adımıza süreç başlatmasını engeller.
    """
    istemci = request.client
    try:
        adres = ipaddress.ip_address(istemci.host if istemci else "")
    except ValueError as exc:
        raise HTTPException(403, "Yalnız yerel isteklere açıktır.") from exc
    eslenmis = getattr(adres, "ipv4_mapped", None)
    if not adres.is_loopback and not (eslenmis and eslenmis.is_loopback):
        raise HTTPException(403, "Yalnız yerel isteklere açıktır.")
    kaynak = request.headers.get("origin", "").strip()
    if kaynak:
        makine = urlparse(kaynak).hostname or ""
        if makine not in {"127.0.0.1", "localhost", "::1"}:
            raise HTTPException(403, "Yabancı kaynaktan istek reddedildi.")


def _kilit_yolu(anahtar: str) -> Path:
    LOG_DIZINI.mkdir(parents=True, exist_ok=True)
    return LOG_DIZINI / f"baslat-{anahtar}.lock"


def _servisi_baslat(anahtar: str) -> str:
    """Servisi tekilleştirilmiş biçimde başlatır; kullanıcıya mesaj döner."""
    servis = _servis_tanimi(anahtar)
    if not servis.baslatilabilir:
        raise HTTPException(400, f"{servis.ad} buradan başlatılamıyor.")
    _cocuklari_topla()
    kilit = _kilit_yolu(anahtar)
    with kilit.open("a+") as tutamac:
        try:
            fcntl.flock(tutamac, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return f"{servis.ad} zaten başlatılıyor."
        try:
            # Kilit altında ikinci yoklama: kilidi bekleyen başka bir yol
            # servisi bu arada ayağa kaldırmış olabilir.
            if _senkron_calisiyor_mu(servis):
                return f"{servis.ad} zaten çalışıyor."
            komut, calisma_dizini = _baslatma_komutu(anahtar)
            log_yolu = LOG_DIZINI / f"{anahtar}.log"
            with log_yolu.open("ab") as log:
                surec = subprocess.Popen(  # noqa: S603 - kabuk yok, sabit komut
                    komut,
                    cwd=str(calisma_dizini),
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            _COCUKLAR.append(surec)
            return f"{servis.ad} başlatıldı; hazır olması birkaç saniye sürebilir."
        finally:
            fcntl.flock(tutamac, fcntl.LOCK_UN)


def _senkron_calisiyor_mu(servis: DisServis) -> bool:
    """Kilit altında kullanılan, olay döngüsüne bağlı olmayan hızlı yoklama."""
    import json
    import urllib.request

    for port in dict.fromkeys(servis.portlar):
        adres = f"http://127.0.0.1:{port}{servis.saglik_yolu}"
        try:
            with urllib.request.urlopen(
                adres, timeout=YOKLAMA_ZAMAN_ASIMI
            ) as yanit:
                veri = json.loads(yanit.read().decode("utf-8", "replace"))
        except (OSError, ValueError):
            continue
        if _imza_uyar_mi(servis.imza, veri)[0]:
            return True
    return False


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.get("/merkez", response_class=HTMLResponse)
    async def merkez(request: Request, mesaj: str = ""):
        import asyncio

        _cocuklari_topla()
        servisler = list(
            await asyncio.gather(*(_servisi_yokla(s) for s in DIS_SERVISLER))
        )
        return sablon.TemplateResponse(
            request,
            "merkez.html",
            {
                "durum": durum.durum(),
                "etkin": "merkez",
                "servisler": servisler,
                "ic_sayfalar": IC_SAYFALAR,
                "mesaj": mesaj,
                "python": f"{sys.version_info.major}.{sys.version_info.minor}",
            },
        )

    @yonlendirici.post("/merkez/baslat/{anahtar}")
    def servisi_baslat(anahtar: str, request: Request):
        _loopback_dogrula(request)
        mesaj = _servisi_baslat(anahtar)
        return RedirectResponse(
            "/merkez?mesaj=" + quote(mesaj), status_code=303
        )

    return yonlendirici
