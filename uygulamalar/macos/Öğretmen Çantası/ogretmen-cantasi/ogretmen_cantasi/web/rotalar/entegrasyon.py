"""Kardeş uygulama bağlantıları ve sürümlü paket aktarımları."""

from __future__ import annotations

import hashlib
import sqlite3
from datetime import date
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import ayarlar, entegrasyon, servis
from ..ortak import (
    _dosya_yaniti,
    _onizleme_ac,
    _onizleme_imzala,
    _ortak,
    _sinirli_oku,
    sablonlar,
)
from .bugun import ders_kaydi_sozluk, gunun_ozeti_json


def _paketi_sakla(icerik: bytes) -> Path:
    ozet = hashlib.sha256(icerik).hexdigest()
    hedef = ayarlar.entegrasyon_dizini() / "bekleyen" / f"{ozet}.zip"
    hedef.parent.mkdir(parents=True, exist_ok=True)
    if not hedef.exists():
        hedef.write_bytes(icerik)
    return hedef


def _baglam(istek: Request, **ek):
    baglanti = istek.state.db
    ek.setdefault("onizleme", None)
    ek.setdefault("onizleme_paketi", "")
    return _ortak(
        istek,
        sayfa="entegrasyon",
        baglantilar=entegrasyon.baglantilar(baglanti),
        aktarimlar=entegrasyon.aktarimlari_oku(baglanti),
        **ek,
    )


def api_tarihi(deger: str | None) -> date:
    """API tarihi: boşsa bugün; geçersizse ValueError (sessizce bugüne düşülmez)."""
    if not deger:
        return date.today()
    try:
        return date.fromisoformat(deger)
    except ValueError as exc:
        raise ValueError("tarih YYYY-AA-GG biçiminde olmalı.") from exc


def yoklama_ozeti(
    baglanti: sqlite3.Connection, sube_id: int, gun: date, saat: int | None = None
) -> dict:
    """Bir şubenin o günkü (saat verilmezse günün ilk dersindeki) yoklaması ve devamsızlık özeti.

    Salt okunur; `servis.Bulunamadi` şube yoksa fırlar.
    """
    sube = servis.sube_al(baglanti, sube_id)
    if saat is None:
        yil = servis.aktif_yil(baglanti)
        bloklar = servis.gunun_bloklari(baglanti, yil.id, gun) if yil else []
        saat = next((b["saatler"][0] for b in bloklar if b["sube_id"] == sube_id), None)
    durumlar = servis.gunun_yoklamasi(baglanti, sube_id, gun, saat) if saat else {}
    ogrenciler = {o["id"]: o for o in servis.ogrencileri_oku(baglanti, sube_id)}
    sayilar: dict[str, int] = {}
    for durum in durumlar.values():
        sayilar[durum] = sayilar.get(durum, 0) + 1
    gelmeyenler = [
        {
            "numara": ogrenciler[oid]["numara"],
            "ad_soyad": ogrenciler[oid]["ad_soyad"],
            "durum": durum,
        }
        for oid, durum in durumlar.items()
        if durum != "var" and oid in ogrenciler
    ]
    devamsizlik = [
        {
            "numara": k["numara"],
            "ad_soyad": k["ad_soyad"],
            "yok_gun": k["yok_gun"],
            "uyari": k["uyari"],
        }
        for k in servis.devamsizlik_tablosu(baglanti, sube_id)
        if k["yok_gun"] or k["uyari"]
    ]
    return {
        "sube_id": sube.id,
        "sube_adi": sube.ad,
        "tarih": gun.isoformat(),
        "ders_saati": saat,
        "alindi": bool(durumlar),
        "ogrenci_sayisi": len(ogrenciler),
        "sayilar": sayilar,
        "gelmeyenler": gelmeyenler,
        "devamsizlik": devamsizlik,
    }


def ders_defteri_ozeti(baglanti: sqlite3.Connection, sube_id: int, gun: date) -> dict:
    """Şubenin o günkü ders defteri kayıtları (salt okunur)."""
    sube = servis.sube_al(baglanti, sube_id)
    kayitlar = servis.gunun_ders_kayitlari(baglanti, sube_id, gun)
    return {
        "sube_id": sube.id,
        "sube_adi": sube.ad,
        "tarih": gun.isoformat(),
        "kayitlar": [ders_kaydi_sozluk(k) for k in kayitlar],
    }


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/entegrasyonlar", response_class=HTMLResponse)
    def entegrasyonlar(istek: Request, mesaj: str = ""):
        return sablonlar.TemplateResponse(
            istek, "entegrasyonlar.html", _baglam(istek, mesaj=mesaj)
        )

    @uygulama.post("/entegrasyonlar/{saglayici}/ayar")
    def baglanti_ayarla(
        istek: Request,
        saglayici: str,
        adres: Annotated[str, Form()],
        etkin: Annotated[str, Form()] = "",
    ):
        try:
            entegrasyon.baglanti_guncelle(
                istek.state.db, saglayici, adres=adres, etkin=bool(etkin)
            )
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        return RedirectResponse("/entegrasyonlar?mesaj=Bağlantı+ayarlandı", status_code=303)

    @uygulama.post("/entegrasyonlar/{saglayici}/kontrol")
    def baglanti_kontrol(istek: Request, saglayici: str):
        sonuc = entegrasyon.saglik_kontrolu(istek.state.db, saglayici)
        mesaj = "Bağlantı hazır" if sonuc["durum"] == "hazir" else f"Bağlantı kurulamadı: {sonuc['hata']}"
        return RedirectResponse(f"/entegrasyonlar?mesaj={mesaj}", status_code=303)

    @uygulama.post("/entegrasyonlar/soru-paketi/onizle", response_class=HTMLResponse)
    async def soru_paketi_onizle(
        istek: Request, dosya: Annotated[UploadFile, File()]
    ):
        icerik = await _sinirli_oku(dosya, entegrasyon.AZAMI_PAKET)
        try:
            onizleme = entegrasyon.soru_paketi_onizle(istek.state.db, icerik)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        yol = _paketi_sakla(icerik)
        paket = _onizleme_imzala(
            uygulama,
            {
                "tur": "sorular",
                "yol": str(yol),
                "sha256": onizleme.icerik_sha256,
                "dis_kimlik": onizleme.dis_kimlik,
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "entegrasyonlar.html",
            _baglam(
                istek,
                onizleme=onizleme.sozluk(),
                onizleme_paketi=paket,
                mesaj="Paket yalnız önizlendi; henüz veri yazılmadı.",
            ),
        )

    @uygulama.post("/entegrasyonlar/soru-kesici/al", response_class=HTMLResponse)
    def soru_kesiciden_al(
        istek: Request, soru_idleri: Annotated[str, Form()]
    ):
        try:
            idler = [
                int(p.strip())
                for p in soru_idleri.replace(";", ",").split(",")
                if p.strip()
            ]
            icerik = entegrasyon.soru_kesiciden_paket_al(
                istek.state.db, idler
            )
            onizleme = entegrasyon.soru_paketi_onizle(
                istek.state.db, icerik
            )
        except (ValueError, ConnectionError) as exc:
            raise HTTPException(502, str(exc)) from exc
        yol = _paketi_sakla(icerik)
        paket = _onizleme_imzala(
            uygulama,
            {
                "tur": "sorular",
                "yol": str(yol),
                "sha256": onizleme.icerik_sha256,
                "dis_kimlik": onizleme.dis_kimlik,
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "entegrasyonlar.html",
            _baglam(
                istek,
                onizleme=onizleme.sozluk(),
                onizleme_paketi=paket,
                mesaj="Sorular Soru Kesici'den alındı ve yalnız önizlendi.",
            ),
        )

    @uygulama.post("/entegrasyonlar/soru-paketi/uygula")
    def soru_paketi_uygula(
        istek: Request, paket: Annotated[str, Form()]
    ):
        veri = _onizleme_ac(uygulama, paket)
        yol = Path(veri.get("yol") or "")
        if (
            veri.get("tur") != "sorular"
            or not yol.is_file()
            or yol.parent != ayarlar.entegrasyon_dizini() / "bekleyen"
        ):
            raise HTTPException(400, "Bekleyen aktarım paketi bulunamadı.")
        icerik = yol.read_bytes()
        onizleme = entegrasyon.soru_paketi_onizle(istek.state.db, icerik)
        if onizleme.icerik_sha256 != veri.get("sha256"):
            raise HTTPException(400, "Bekleyen paket değişmiş.")
        eklenen = entegrasyon.soru_paketi_uygula(
            istek.state.db, icerik, onizleme
        )
        yol.unlink(missing_ok=True)
        return RedirectResponse(
            f"/entegrasyonlar?mesaj={eklenen}+soru+aktarıldı", status_code=303
        )

    @uygulama.get("/entegrasyonlar/sinav/{sinav_id}/paket")
    def sinav_paketi(istek: Request, sinav_id: int):
        icerik = entegrasyon.sinav_paketi_uret(istek.state.db, sinav_id)
        return _dosya_yaniti(
            icerik, f"ogretmen-cantasi-sinav-{sinav_id}.zip", "application/zip"
        )

    @uygulama.post("/entegrasyonlar/sinav/{sinav_id}/gonder")
    def sinav_gonder(istek: Request, sinav_id: int):
        try:
            sonuc = entegrasyon.sinav_okura_gonder(
                istek.state.db, sinav_id
            )
        except (ValueError, LookupError, ConnectionError) as exc:
            raise HTTPException(502, str(exc)) from exc
        return RedirectResponse(
            f"/sinav/{sinav_id}?mesaj=Sınav+Sınav+Okur'a+gönderildi:+{sonuc.get('exam_id', '')}",
            status_code=303,
        )

    @uygulama.post(
        "/entegrasyonlar/sinav/{sinav_id}/sonuc-al", response_class=HTMLResponse
    )
    def sinav_sonucu_al(istek: Request, sinav_id: int):
        try:
            icerik = entegrasyon.sinav_okurdan_sonuc_al(
                istek.state.db, sinav_id
            )
            onizleme = entegrasyon.sinav_sonucu_onizle(
                istek.state.db, icerik, sinav_id
            )
        except (ValueError, LookupError, ConnectionError) as exc:
            raise HTTPException(502, str(exc)) from exc
        yol = _paketi_sakla(icerik)
        paket = _onizleme_imzala(
            uygulama,
            {
                "tur": "sinav_sonucu",
                "sinav_id": sinav_id,
                "yol": str(yol),
                "sha256": onizleme.icerik_sha256,
                "dis_kimlik": onizleme.dis_kimlik,
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "entegrasyonlar.html",
            _baglam(
                istek,
                onizleme=onizleme.sozluk(),
                onizleme_paketi=paket,
                mesaj="Onaylı sonuçlar Sınav Okur'dan alındı ve yalnız önizlendi.",
            ),
        )

    @uygulama.post(
        "/entegrasyonlar/sinav/{sinav_id}/sonuc-onizle", response_class=HTMLResponse
    )
    async def sinav_sonucu_onizle(
        istek: Request,
        sinav_id: int,
        dosya: Annotated[UploadFile, File()],
    ):
        icerik = await _sinirli_oku(dosya, entegrasyon.AZAMI_PAKET)
        try:
            onizleme = entegrasyon.sinav_sonucu_onizle(
                istek.state.db, icerik, sinav_id
            )
        except (ValueError, LookupError) as exc:
            raise HTTPException(400, str(exc)) from exc
        yol = _paketi_sakla(icerik)
        paket = _onizleme_imzala(
            uygulama,
            {
                "tur": "sinav_sonucu",
                "sinav_id": sinav_id,
                "yol": str(yol),
                "sha256": onizleme.icerik_sha256,
                "dis_kimlik": onizleme.dis_kimlik,
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "entegrasyonlar.html",
            _baglam(
                istek,
                onizleme=onizleme.sozluk(),
                onizleme_paketi=paket,
                mesaj="Sınav sonucu yalnız önizlendi.",
            ),
        )

    @uygulama.post("/entegrasyonlar/sinav-sonucu/uygula")
    def sinav_sonucu_uygula(
        istek: Request, paket: Annotated[str, Form()]
    ):
        veri = _onizleme_ac(uygulama, paket)
        yol = Path(veri.get("yol") or "")
        if (
            veri.get("tur") != "sinav_sonucu"
            or not yol.is_file()
            or yol.parent != ayarlar.entegrasyon_dizini() / "bekleyen"
        ):
            raise HTTPException(400, "Bekleyen sonuç paketi bulunamadı.")
        sinav_id = int(veri["sinav_id"])
        icerik = yol.read_bytes()
        onizleme = entegrasyon.sinav_sonucu_onizle(
            istek.state.db, icerik, sinav_id
        )
        yazilan = entegrasyon.sinav_sonucu_uygula(
            istek.state.db, icerik, sinav_id, onizleme
        )
        yol.unlink(missing_ok=True)
        return RedirectResponse(
            f"/sinav/{sinav_id}?mesaj={yazilan}+soru+puanı+aktarıldı",
            status_code=303,
        )

    @uygulama.get("/api/v1/health")
    def api_saglik():
        return {
            "app": "ogretmen-cantasi",
            "app_version": "0.3.0",
            "protocol_version": entegrasyon.PROTOKOL_SURUMU,
            "status": "ready",
        }

    @uygulama.get("/api/v1/capabilities")
    def api_yetenekler():
        return {
            "protocol_version": entegrasyon.PROTOKOL_SURUMU,
            "capabilities": [
                "question-package-import",
                "exam-package-export",
                "exam-results-import",
                "daily-json",
                "mcp",
            ],
        }

    # Salt okunur günlük JSON uçları: /api/v1/ altında olduğu için middleware'in
    # Bearer / X-Api-Token denetimi kendiliğinden geçerlidir.
    @uygulama.get("/api/v1/bugun")
    def api_bugun(istek: Request, tarih: str | None = None):
        try:
            gun = api_tarihi(tarih)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        return gunun_ozeti_json(istek.state.db, gun)

    @uygulama.get("/api/v1/yoklama/{sube_id}")
    def api_yoklama(
        istek: Request, sube_id: int, tarih: str | None = None, saat: int | None = None
    ):
        try:
            gun = api_tarihi(tarih)
            return yoklama_ozeti(istek.state.db, sube_id, gun, saat)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except servis.Bulunamadi as exc:
            raise HTTPException(404, "Şube bulunamadı.") from exc

    @uygulama.get("/api/v1/ders-defteri")
    def api_ders_defteri(istek: Request, sube_id: int, tarih: str | None = None):
        try:
            gun = api_tarihi(tarih)
            return ders_defteri_ozeti(istek.state.db, sube_id, gun)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except servis.Bulunamadi as exc:
            raise HTTPException(404, "Şube bulunamadı.") from exc
