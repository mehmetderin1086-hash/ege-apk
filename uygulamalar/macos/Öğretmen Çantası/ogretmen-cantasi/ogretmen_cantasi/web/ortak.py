"""Rota modüllerinin paylaştığı yardımcı fonksiyonlar ve sabitler."""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import re
import sqlite3
import tempfile
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from datetime import date
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from urllib.parse import quote

from fastapi import FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import Response
from fastapi.templating import Jinja2Templates

from .. import ayarlar as ayar_modulu
from .. import depo, servis
from .. import mufredat as mf

KOK = Path(__file__).resolve().parent
sablonlar = Jinja2Templates(directory=str(KOK / "sablonlar"))
TABLO_YUKLEME_SINIRI = 20 * 1024 * 1024
SES_YUKLEME_SINIRI = 25 * 1024 * 1024

XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


def _saatleri_coz(metin: str, varsayilan: list[int] | None = None) -> list[int]:
    """Virgüllü "3,4" saat listesini çözer; sayı olmayan parçaları atar."""
    saatler = [int(s) for s in metin.split(",") if s.strip().isdigit()]
    return saatler or (varsayilan or [])


def _ortak(istek: Request, **ek) -> dict:
    baglanti = istek.state.db
    yil = servis.aktif_yil(baglanti)
    return {
        "imza": ayar_modulu.IMZA,
        "uygulama_adi": ayar_modulu.UYGULAMA_ADI,
        "yil": yil,
        "yillar": servis.ogretim_yillari_oku(baglanti),
        "subeler": servis.subeleri_oku(baglanti, yil.id) if yil else [],
        "ayarlar": servis.ayarlari_oku(baglanti),
        "bugun": date.today(),
        "csrf_token": istek.app.state.csrf_token,
        **ek,
    }


def _tarih_coz(deger: str | None) -> date:
    if not deger:
        return date.today()
    try:
        return date.fromisoformat(deger)
    except ValueError:
        return date.today()


BOS = object()  # "alan boş bırakıldı" — geçersiz değerden ayırt edilir


def _form_revizyonu(veri: Mapping) -> int | None:
    if "_revizyon" not in veri:
        return None
    try:
        return int(str(veri.get("_revizyon", "0")) or 0)
    except ValueError:
        return -1


def _revizyon_ilerlet(
    baglanti: sqlite3.Connection, anahtar: str, beklenen: int | None
) -> int:
    # Eski CLI/test istemcileri revizyon alanı göndermeyebilir. Bu durumda da
    # sürümü artırırız; tarayıcı formları her zaman beklenen sürümü gönderir.
    if beklenen is None:
        beklenen = depo.revizyon_oku(baglanti, anahtar)
    return depo.revizyon_dogrula_ve_artir(baglanti, anahtar, beklenen)


def _onizleme_imzala(uygulama: FastAPI, veri: dict) -> str:
    ham = json.dumps(veri, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    kodlu = base64.urlsafe_b64encode(ham).decode()
    imza = hmac.new(
        uygulama.state.csrf_token.encode(), kodlu.encode(), hashlib.sha256
    ).hexdigest()
    return f"{kodlu}.{imza}"


def _onizleme_ac(uygulama: FastAPI, paket: str) -> dict:
    try:
        kodlu, gelen_imza = paket.rsplit(".", 1)
        beklenen = hmac.new(
            uygulama.state.csrf_token.encode(), kodlu.encode(), hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(gelen_imza, beklenen):
            raise ValueError
        return json.loads(base64.urlsafe_b64decode(kodlu.encode()))
    except (binascii.Error, ValueError, json.JSONDecodeError, UnicodeDecodeError) as hata:
        raise HTTPException(
            status_code=400, detail="İçe aktarma önizlemesinin imzası geçersiz."
        ) from hata


def _sayi(deger: str | None) -> float | None:
    """Sayıya çevirir; boş ya da geçersizse None. Yalnız okuma amaçlı."""
    cozum = _sayi_ayir(deger)
    return None if cozum is BOS or cozum is None else cozum


def _sayi_ayir(deger: str | None) -> float | object | None:
    """Üç durumu ayırır: geçerli sayı, BOŞ (silme isteği), geçersiz (None).

    Bu ayrım kritik: not hücresine "85x" yazıldığında eskiden değer None'a
    düşüyor, None da "bu notu sil" diye yorumlanıyordu — kayıtlı 85 puan
    sessizce siliniyor, ekranda "Notlar kaydedildi" yazıyordu.
    """
    if deger is None or not str(deger).strip():
        return BOS
    try:
        return float(str(deger).replace(",", "."))
    except ValueError:
        return None


def _dosya_yaniti(icerik: bytes, ad: str, tur: str) -> Response:
    # Dosya adı yüzde kodlanır: başlıklar latin-1 ile kodlandığı için "İ" gibi
    # bir karakter ham hâlde konursa TÜM indirme 500 veriyordu.
    kodlu = quote(ad, safe="")
    return Response(
        content=icerik,
        media_type=tur,
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{kodlu}"},
    )


def _uygulama_surumu() -> str:
    try:
        return version("ogretmen-cantasi")
    except PackageNotFoundError:
        return "gelistirme"


async def _sinirli_oku(dosya: UploadFile, sinir: int) -> bytes:
    parcalar: list[bytes] = []
    toplam = 0
    while True:
        parca = await dosya.read(min(1024 * 1024, sinir + 1 - toplam))
        if not parca:
            break
        toplam += len(parca)
        if toplam > sinir:
            raise HTTPException(
                status_code=413,
                detail=f"Dosya izin verilen {sinir // (1024 * 1024)} MiB sınırını aşıyor.",
            )
        parcalar.append(parca)
    return b"".join(parcalar)


@contextmanager
def _yuklenen_dosya(dosya: UploadFile, icerik: bytes) -> Iterator[Path]:
    """Yüklenen içeriği geçici bir dosyaya yazar ve sonunda siler.

    Dosyanın KENDİ adı yola girmez. `Path(...) / dosya.filename` kalıbı `..`
    parçalarını sadeleştirmediği için "../veri.db" adlı bir yükleme
    veritabanının üstüne yazıp ardından silebiliyordu; istek de "başarılı"
    dönüyordu. Yalnız uzantı korunur, çünkü biçim tanıma ona bakıyor.
    """
    uzanti = Path(dosya.filename or "").suffix.lower()
    if len(uzanti) > 8 or not re.fullmatch(r"\.[a-z0-9]*", uzanti or ".x"):
        uzanti = ""
    tutucu = tempfile.NamedTemporaryFile(  # noqa: SIM115 - kapanışı finally'de
        prefix="ogretmen-yukleme-", suffix=uzanti, delete=False
    )
    try:
        tutucu.write(icerik)
        tutucu.close()
        yield Path(tutucu.name)
    finally:
        Path(tutucu.name).unlink(missing_ok=True)


def _tema_sozlugu(tema: mf.Tema) -> dict:
    return {
        "no": tema.no,
        "ad": tema.ad,
        "aciklama": tema.aciklama,
        "ders_saati": tema.ders_saati,
        "alan_becerileri": list(tema.alan_becerileri),
        "kavramsal_beceriler": list(tema.kavramsal_beceriler),
        "egilimler": list(tema.egilimler),
        "sosyal_duygusal_beceriler": list(tema.sosyal_duygusal_beceriler),
        "degerler": list(tema.degerler),
        "okuryazarlik_becerileri": list(tema.okuryazarlik_becerileri),
        "disiplinler_arasi": list(tema.disiplinler_arasi),
        "beceriler_arasi": list(tema.beceriler_arasi),
        "icerik_cercevesi": tema.icerik_cercevesi,
        "anahtar_kavramlar": list(tema.anahtar_kavramlar),
        "ogrenme_kanitlari": tema.ogrenme_kanitlari,
        "ogrenme_ciktilari": [
            {
                "kod": c.kod,
                "ifade": c.ifade,
                "surec_bilesenleri": [{"harf": b.harf, "ifade": b.ifade} for b in c.surec_bilesenleri],
            }
            for c in tema.ogrenme_ciktilari
        ],
    }
