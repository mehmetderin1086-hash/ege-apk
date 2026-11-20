"""Kaynak gösteren ve öğretmen onayı olmadan resmî kayıt değiştirmeyen yardımcı."""

from __future__ import annotations

import hashlib
import json
import sqlite3
import urllib.error
import urllib.request
from datetime import date, datetime
from typing import Any

from . import depo, entegrasyon, servis
from . import mufredat as mf
from . import servis_olcme as so

ONERI_TURLERI = ("ders", "soru_rubrik", "telafi")
ONERI_DURUMLARI = ("taslak", "onaylandi", "reddedildi")


def _simdi() -> str:
    return datetime.now().isoformat(timespec="seconds")


def mufredat_kaynagini_kaydet(
    baglanti: sqlite3.Connection, surum: str = mf.MAARIF_2024
) -> int | None:
    try:
        program = mf.yukle(surum)
    except mf.MufredatYok:
        return None
    yol = mf.VERI_DIZINI / f"mufredat_{surum}.json"
    ozet = hashlib.sha256(yol.read_bytes()).hexdigest()
    kunye = mf.kaynak_kunyesi(surum)
    baglanti.execute(
        "INSERT INTO mufredat_kaynagi "
        "(surum, ad, resmi_url, yayin_tarihi, erisim_tarihi, icerik_sha256, "
        "siniflar, gecerlilik_json) VALUES (?,?,?,?,?,?,?,?) "
        "ON CONFLICT (surum, icerik_sha256) DO UPDATE SET "
        "ad = excluded.ad, resmi_url = excluded.resmi_url, "
        "erisim_tarihi = excluded.erisim_tarihi, siniflar = excluded.siniflar",
        (
            surum,
            kunye.get("title") or program.ad,
            kunye.get("official_url") or "",
            kunye.get("published_at") or "",
            date.today().isoformat(),
            ozet,
            ",".join(str(s) for s in sorted(program.siniflar)),
            json.dumps(mf.sinif_surumleri(), ensure_ascii=False),
        ),
    )
    satir = baglanti.execute(
        "SELECT id FROM mufredat_kaynagi WHERE surum = ? AND icerik_sha256 = ?",
        (surum, ozet),
    ).fetchone()
    return int(satir["id"]) if satir else None


def _mufredat_kaniti(sube: servis.Sube, kazanim_kodu: str) -> tuple[str, dict[str, Any]]:
    program = mf.yukle(sube.mufredat_surumu)
    cikti = program.cikti(kazanim_kodu)
    tema = next(t for t in program.duzey(sube.sinif).temalar if t.no == cikti.tema_no)
    metin = " ".join(
        parca
        for parca in (
            cikti.ifade,
            tema.uygulama(kazanim_kodu),
            tema.ogrenme_kanitlari,
        )
        if parca
    )
    kunye = mf.kaynak_kunyesi(sube.mufredat_surumu)
    kaynak = {
        "type": "mufredat",
        "title": kunye.get("title") or program.ad,
        "url": kunye.get("official_url") or "",
        "section": kazanim_kodu,
        "excerpt": metin[:1200],
    }
    return metin, kaynak


def _biyo_onerisi(
    baglanti: sqlite3.Connection,
    *,
    amac: str,
    soru: str,
    sinif: int,
    kazanim_kodu: str,
) -> tuple[str, list[dict[str, Any]], str] | None:
    kayit = baglanti.execute(
        "SELECT adres FROM dis_kaynak_baglanti "
        "WHERE saglayici = 'biyo_cozucu' AND etkin = 1"
    ).fetchone()
    if not kayit:
        return None
    govde = json.dumps(
        {
            "purpose": amac,
            "prompt": soru,
            "grade": sinif,
            "outcome_code": kazanim_kodu,
            "allowed_sources": ["mufredat", "yerel_kitap", "materyal"],
        },
        ensure_ascii=False,
    ).encode()
    istek = urllib.request.Request(  # noqa: S310 - adres yalnız loopback olarak kaydedilir
        f"{kayit['adres']}/api/v1/suggestions",
        data=govde,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {entegrasyon.yerel_belirtec()}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(istek, timeout=90) as yanit:  # noqa: S310
            veri = json.loads(yanit.read(4 * 1024 * 1024))
    except (OSError, ValueError, urllib.error.URLError):
        return None
    kaynaklar = veri.get("sources")
    oneri = str(veri.get("suggestion") or "").strip()
    if veri.get("status") == "insufficient_evidence" or not oneri or not kaynaklar:
        return None
    return oneri, list(kaynaklar), str(veri.get("model") or "biyo-cozucu")


def oneri_uret(
    baglanti: sqlite3.Connection,
    *,
    tur: str,
    sube_id: int,
    kazanim_kodu: str,
    ogrenci_id: int | None = None,
    ek_istek: str = "",
) -> int:
    if tur not in ONERI_TURLERI:
        raise ValueError("Bilinmeyen yardımcı türü.")
    sube = servis.sube_al(baglanti, sube_id)
    kanit, kaynak = _mufredat_kaniti(sube, kazanim_kodu)
    girdi = {
        "ders": "Bu kazanım için süre bölümlü, uygulanabilir bir ders etkinliği öner.",
        "soru_rubrik": "Bu kazanımı ölçen açık uçlu soru ve puanlama rubriği öner.",
        "telafi": "Bu kazanımda zorlanan öğrenci için kısa, ölçülebilir telafi çalışması öner.",
    }[tur]
    if ek_istek.strip():
        girdi += " Öğretmen notu: " + ek_istek.strip()
    uzak = _biyo_onerisi(
        baglanti,
        amac=tur,
        soru=f"{girdi}\n\nResmî kanıt:\n{kanit[:5000]}",
        sinif=sube.sinif,
        kazanim_kodu=kazanim_kodu,
    )
    if uzak:
        oneri, kaynaklar, model = uzak
    else:
        # Sağlayıcı yokken de kaynağın kendisinden güvenli bir taslak sunulur;
        # yeni olgu eklemez ve açıkça deterministik olarak işaretlenir.
        if tur == "ders":
            oneri = (
                f"{kazanim_kodu} için önce öğrencilerin ön bilgilerini yoklayan kısa bir soru "
                "sorun; ardından resmî öğretme uygulamasındaki etkinliği sınıf düzeyine göre "
                "uygulayın ve öğrenme kanıtlarında belirtilen yöntemle çıkış bileti alın."
            )
        elif tur == "soru_rubrik":
            oneri = (
                f"Soru: {kazanim_kodu} kapsamında verilen bir biyolojik durumu kanıta dayalı "
                "olarak açıklayınız.\nRubrik: doğru biyolojik ilişki %50, kanıt kullanımı %30, "
                "açıklık ve kavram doğruluğu %20."
            )
        else:
            oneri = (
                f"{kazanim_kodu} için öğrenciden kavramı kendi cümlesiyle açıklamasını, bir "
                "örnek vermesini ve ardından benzer yeni bir durumu çözmesini isteyin; sonucu "
                "üç maddelik kontrol listesiyle yeniden değerlendirin."
            )
        kaynaklar = [kaynak]
        model = "kaynak-sablonu-v1"
    imlec = baglanti.execute(
        "INSERT INTO yardimci_onerisi "
        "(tur, sube_id, ogrenci_id, kazanim_kodu, girdi_ozeti, oneri, "
        "kaynaklar_json, model_kimligi, olusturma) VALUES (?,?,?,?,?,?,?,?,?)",
        (
            tur,
            sube_id,
            ogrenci_id,
            kazanim_kodu,
            girdi[:1000],
            oneri,
            json.dumps(kaynaklar, ensure_ascii=False),
            model,
            _simdi(),
        ),
    )
    return int(imlec.lastrowid or 0)


def oneriler(
    baglanti: sqlite3.Connection, *, durum: str = "", sinir: int = 50
) -> list[dict[str, Any]]:
    sorgu = (
        "SELECT y.*, s.ad AS sube_adi, o.ad_soyad FROM yardimci_onerisi y "
        "LEFT JOIN sube s ON s.id = y.sube_id "
        "LEFT JOIN ogrenci o ON o.id = y.ogrenci_id"
    )
    degerler: list[Any] = []
    if durum:
        sorgu += " WHERE y.durum = ?"
        degerler.append(durum)
    sorgu += " ORDER BY y.id DESC LIMIT ?"
    degerler.append(sinir)
    sonuc = []
    for satir in baglanti.execute(sorgu, degerler):
        kayit = dict(satir)
        try:
            kayit["kaynaklar"] = json.loads(kayit["kaynaklar_json"])
        except json.JSONDecodeError:
            kayit["kaynaklar"] = []
        sonuc.append(kayit)
    return sonuc


def oneri_karari(
    baglanti: sqlite3.Connection,
    oneri_id: int,
    *,
    durum: str,
    duzeltme: str = "",
) -> None:
    if durum not in {"onaylandi", "reddedildi"}:
        raise ValueError("Bilinmeyen öneri kararı.")
    imlec = baglanti.execute(
        "UPDATE yardimci_onerisi SET durum = ?, ogretmen_duzeltmesi = ?, "
        "karar_tarihi = ? WHERE id = ? AND durum = 'taslak'",
        (durum, duzeltme.strip(), _simdi(), oneri_id),
    )
    if imlec.rowcount != 1:
        raise LookupError("Taslak öneri bulunamadı.")


def destek_planlarini_turet(
    baglanti: sqlite3.Connection, sinav_id: int, *, esik: float = 60.0
) -> int:
    """Onaylı puanlardan öğrenci-kazanım destek taslakları çıkarır."""
    analiz = so.sinav_kazanim_analizi(baglanti, sinav_id)
    eklenen = 0
    simdi = _simdi()
    with depo.islem(baglanti, immediate=True):
        for ogrenci_id, ogrenci in analiz["ogrenciler"].items():
            for kod, yuzde in ogrenci["kazanimlar"].items():
                if yuzde is None or float(yuzde) >= esik:
                    continue
                imlec = baglanti.execute(
                    "INSERT INTO ogrenci_destek_plani "
                    "(ogrenci_id, kazanim_kodu, gerekce, durum, olusturma, guncelleme) "
                    "VALUES (?,?,?,?,?,?) ON CONFLICT DO NOTHING",
                    (
                        int(ogrenci_id),
                        kod,
                        f"Öğretmen onaylı sınav sonucunda başarı %{float(yuzde):.0f}; eşik %{esik:g}.",
                        "taslak",
                        simdi,
                        simdi,
                    ),
                )
                eklenen += max(0, imlec.rowcount)
    return eklenen


def destek_planlari(
    baglanti: sqlite3.Connection, *, sube_id: int | None = None
) -> list[sqlite3.Row]:
    sorgu = (
        "SELECT d.*, o.ad_soyad, o.numara, o.sube_id FROM ogrenci_destek_plani d "
        "JOIN ogrenci o ON o.id = d.ogrenci_id"
    )
    degerler: tuple[Any, ...] = ()
    if sube_id is not None:
        sorgu += " WHERE o.sube_id = ?"
        degerler = (sube_id,)
    sorgu += " ORDER BY d.guncelleme DESC"
    return baglanti.execute(sorgu, degerler).fetchall()


def destek_plani_guncelle(
    baglanti: sqlite3.Connection,
    plan_id: int,
    *,
    durum: str,
    calisma: str,
    takip_tarihi: str,
) -> None:
    if durum not in {"taslak", "onaylandi", "tamamlandi", "iptal"}:
        raise ValueError("Bilinmeyen destek planı durumu.")
    baglanti.execute(
        "UPDATE ogrenci_destek_plani SET durum = ?, onerilen_calisma = ?, "
        "takip_tarihi = ?, guncelleme = ? WHERE id = ?",
        (durum, calisma.strip(), takip_tarihi, _simdi(), plan_id),
    )
