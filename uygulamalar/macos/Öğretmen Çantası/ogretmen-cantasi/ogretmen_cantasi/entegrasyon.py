"""Kardeş uygulamalar için sürümlü, yerel ve idempotent entegrasyon katmanı."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import datetime
from io import BytesIO
from pathlib import PurePosixPath
from typing import Any

from . import ayarlar, depo

PROTOKOL_SURUMU = "v1"
PAKET_SEMA_SURUMU = 1
SAGLAYICILAR = {
    "soru_kesici": ("Soru Kesici", "http://127.0.0.1:8756"),
    "sinav_okur": ("Sınav Okur", "http://127.0.0.1:8001"),
    "biyo_cozucu": ("Biyo Çözücü", "http://127.0.0.1:8020"),
}
AZAMI_PAKET = 100 * 1024 * 1024
AZAMI_DOSYA = 25 * 1024 * 1024
AZAMI_DOSYA_SAYISI = 1000


@dataclass(frozen=True)
class PaketOnizlemesi:
    saglayici: str
    dis_kimlik: str
    icerik_sha256: str
    tur: str
    eklenecek: list[dict[str, Any]]
    atlanacak: list[dict[str, Any]]
    uyarilar: list[str]

    def sozluk(self) -> dict[str, Any]:
        return {
            "saglayici": self.saglayici,
            "dis_kimlik": self.dis_kimlik,
            "icerik_sha256": self.icerik_sha256,
            "tur": self.tur,
            "eklenecek": self.eklenecek,
            "atlanacak": self.atlanacak,
            "uyarilar": self.uyarilar,
        }


def _simdi() -> str:
    return datetime.now().isoformat(timespec="seconds")


def yerel_belirtec() -> str:
    """Kullanıcıya gösterilmeyen, yalnız yerel uygulamalarca paylaşılan anahtar."""
    yol = ayarlar.entegrasyon_belirteci_yolu()
    yol.parent.mkdir(parents=True, exist_ok=True)
    if yol.is_file():
        deger = yol.read_text(encoding="utf-8").strip()
        if len(deger) >= 32:
            return deger
    deger = secrets.token_urlsafe(48)
    gecici = yol.with_suffix(".tmp")
    gecici.write_text(deger + "\n", encoding="utf-8")
    os.chmod(gecici, 0o600)
    gecici.replace(yol)
    return deger


def varsayilan_baglantilari_kur(baglanti: sqlite3.Connection) -> None:
    for saglayici, (ad, adres) in SAGLAYICILAR.items():
        baglanti.execute(
            "INSERT INTO dis_kaynak_baglanti "
            "(saglayici, ad, adres, protokol_surumu) VALUES (?,?,?,?) "
            "ON CONFLICT (saglayici) DO NOTHING",
            (saglayici, ad, adres, PROTOKOL_SURUMU),
        )


def baglantilar(baglanti: sqlite3.Connection) -> list[sqlite3.Row]:
    varsayilan_baglantilari_kur(baglanti)
    return baglanti.execute(
        "SELECT * FROM dis_kaynak_baglanti ORDER BY ad"
    ).fetchall()


def baglanti_guncelle(
    baglanti: sqlite3.Connection, saglayici: str, *, adres: str, etkin: bool
) -> None:
    if saglayici not in SAGLAYICILAR:
        raise ValueError("Bilinmeyen entegrasyon sağlayıcısı.")
    if not (
        adres.startswith("http://127.0.0.1:")
        or adres.startswith("http://localhost:")
        or adres.startswith("http://[::1]:")
    ):
        raise ValueError("Entegrasyon adresi yalnız yerel makineyi gösterebilir.")
    varsayilan_baglantilari_kur(baglanti)
    baglanti.execute(
        "UPDATE dis_kaynak_baglanti SET adres = ?, etkin = ? WHERE saglayici = ?",
        (adres.rstrip("/"), int(etkin), saglayici),
    )


def saglik_kontrolu(
    baglanti: sqlite3.Connection, saglayici: str, *, zaman_asimi: float = 2.0
) -> dict[str, Any]:
    kayit = baglanti.execute(
        "SELECT * FROM dis_kaynak_baglanti WHERE saglayici = ?", (saglayici,)
    ).fetchone()
    if kayit is None:
        varsayilan_baglantilari_kur(baglanti)
        kayit = baglanti.execute(
            "SELECT * FROM dis_kaynak_baglanti WHERE saglayici = ?", (saglayici,)
        ).fetchone()
    if not kayit or not kayit["etkin"]:
        return {"durum": "kapali", "hata": ""}
    url = f"{kayit['adres']}/api/v1/health"
    istek = urllib.request.Request(  # noqa: S310 - adres yukarıda loopback ile sınırlandı
        url, headers={"Authorization": f"Bearer {yerel_belirtec()}"}
    )
    durum = "hata"
    hata = ""
    veri: dict[str, Any] = {}
    try:
        with urllib.request.urlopen(istek, timeout=zaman_asimi) as yanit:  # noqa: S310
            veri = json.loads(yanit.read(1024 * 1024))
        if veri.get("protocol_version") != PROTOKOL_SURUMU:
            hata = f"Uyumsuz protokol: {veri.get('protocol_version') or 'yok'}"
        else:
            durum = "hazir"
    except (OSError, ValueError, urllib.error.URLError) as exc:
        hata = str(exc)
    baglanti.execute(
        "UPDATE dis_kaynak_baglanti SET son_durum = ?, son_hata = ?, son_kontrol = ? "
        "WHERE saglayici = ?",
        (durum, hata[:500], _simdi(), saglayici),
    )
    return {"durum": durum, "hata": hata, "veri": veri}


def _saglayici_adresi(baglanti: sqlite3.Connection, saglayici: str) -> str:
    varsayilan_baglantilari_kur(baglanti)
    kayit = baglanti.execute(
        "SELECT adres, etkin FROM dis_kaynak_baglanti WHERE saglayici = ?",
        (saglayici,),
    ).fetchone()
    if not kayit or not kayit["etkin"]:
        raise ConnectionError("Entegrasyon kapalı.")
    adres = str(kayit["adres"]).rstrip("/")
    if not (
        adres.startswith("http://127.0.0.1:")
        or adres.startswith("http://localhost:")
        or adres.startswith("http://[::1]:")
    ):
        raise ConnectionError("Entegrasyon adresi yerel değil.")
    return adres


def soru_kesiciden_paket_al(
    baglanti: sqlite3.Connection, soru_idleri: list[int]
) -> bytes:
    if not soru_idleri or len(soru_idleri) > 500:
        raise ValueError("1 ile 500 arasında soru kimliği gerekli.")
    adres = _saglayici_adresi(baglanti, "soru_kesici")
    kimlikler = ",".join(str(int(i)) for i in soru_idleri)
    url = f"{adres}/api/v1/questions/export?ids={kimlikler}"
    istek = urllib.request.Request(  # noqa: S310 - adres loopback ile sınırlandı
        url, headers={"Authorization": f"Bearer {yerel_belirtec()}"}
    )
    try:
        with urllib.request.urlopen(istek, timeout=30) as yanit:  # noqa: S310
            icerik = yanit.read(AZAMI_PAKET + 1)
    except urllib.error.URLError as exc:
        raise ConnectionError(f"Soru Kesici'ye bağlanılamadı: {exc}") from exc
    if len(icerik) > AZAMI_PAKET:
        raise ValueError("Soru Kesici paketi boyut sınırını aşıyor.")
    return icerik


def sinav_okura_gonder(
    baglanti: sqlite3.Connection, sinav_id: int
) -> dict[str, Any]:
    icerik = sinav_paketi_uret(baglanti, sinav_id)
    adres = _saglayici_adresi(baglanti, "sinav_okur")
    sinir = "----ogretmen-cantasi-" + secrets.token_hex(12)
    govde = (
        f"--{sinir}\r\n"
        'Content-Disposition: form-data; name="package"; filename="sinav.zip"\r\n'
        "Content-Type: application/zip\r\n\r\n"
    ).encode() + icerik + f"\r\n--{sinir}--\r\n".encode()
    istek = urllib.request.Request(  # noqa: S310 - adres loopback ile sınırlandı
        f"{adres}/api/v1/exams/import",
        data=govde,
        headers={
            "Authorization": f"Bearer {yerel_belirtec()}",
            "Content-Type": f"multipart/form-data; boundary={sinir}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(istek, timeout=30) as yanit:  # noqa: S310
            sonuc = json.loads(yanit.read(1024 * 1024))
    except (urllib.error.URLError, ValueError) as exc:
        raise ConnectionError(f"Sınav Okur'a bağlanılamadı: {exc}") from exc
    simdi = _simdi()
    baglanti.execute(
        "INSERT INTO aktarim_islemi "
        "(saglayici, yon, dis_kimlik, icerik_sha256, tur, durum, ozet_json, "
        "olusturma, guncelleme) VALUES (?,?,?,?,?,?,?,?,?) "
        "ON CONFLICT (saglayici, dis_kimlik, icerik_sha256) DO UPDATE SET "
        "durum = excluded.durum, ozet_json = excluded.ozet_json, "
        "guncelleme = excluded.guncelleme",
        (
            "sinav_okur",
            "disa",
            f"exam:{sinav_id}",
            hashlib.sha256(icerik).hexdigest(),
            f"sinav:{sinav_id}",
            "tamamlandi",
            json.dumps(sonuc, ensure_ascii=False),
            simdi,
            simdi,
        ),
    )
    return sonuc


def sinav_okurdan_sonuc_al(
    baglanti: sqlite3.Connection, sinav_id: int
) -> bytes:
    kayit = baglanti.execute(
        "SELECT ozet_json FROM aktarim_islemi WHERE saglayici = 'sinav_okur' "
        "AND yon = 'disa' AND dis_kimlik = ? AND durum = 'tamamlandi' "
        "ORDER BY id DESC LIMIT 1",
        (f"exam:{sinav_id}",),
    ).fetchone()
    if not kayit:
        raise LookupError("Sınav önce Sınav Okur'a gönderilmeli.")
    try:
        ic_kimlik = json.loads(kayit["ozet_json"])["exam_id"]
    except (json.JSONDecodeError, KeyError) as exc:
        raise LookupError("Sınav Okur eşlemesi bozuk.") from exc
    adres = _saglayici_adresi(baglanti, "sinav_okur")
    istek = urllib.request.Request(  # noqa: S310 - adres loopback ile sınırlandı
        f"{adres}/api/v1/exams/{ic_kimlik}/results",
        headers={"Authorization": f"Bearer {yerel_belirtec()}"},
    )
    try:
        with urllib.request.urlopen(istek, timeout=30) as yanit:  # noqa: S310
            icerik = yanit.read(AZAMI_PAKET + 1)
    except urllib.error.URLError as exc:
        raise ConnectionError(f"Sınav Okur sonucu alınamadı: {exc}") from exc
    if len(icerik) > AZAMI_PAKET:
        raise ValueError("Sınav sonucu paketi boyut sınırını aşıyor.")
    return icerik


def _guvenli_zip(icerik: bytes) -> tuple[dict[str, Any], zipfile.ZipFile]:
    if len(icerik) > AZAMI_PAKET:
        raise ValueError("Aktarım paketi 100 MiB sınırını aşıyor.")
    try:
        paket = zipfile.ZipFile(BytesIO(icerik))
    except zipfile.BadZipFile as exc:
        raise ValueError("Aktarım paketi geçerli bir ZIP dosyası değil.") from exc
    bilgiler = paket.infolist()
    if len(bilgiler) > AZAMI_DOSYA_SAYISI:
        paket.close()
        raise ValueError("Aktarım paketinde çok fazla dosya var.")
    toplam = 0
    for bilgi in bilgiler:
        parcalar = PurePosixPath(bilgi.filename).parts
        if bilgi.filename.startswith("/") or ".." in parcalar:
            paket.close()
            raise ValueError("Aktarım paketi güvensiz bir dosya yolu içeriyor.")
        if bilgi.file_size > AZAMI_DOSYA:
            paket.close()
            raise ValueError("Aktarım paketindeki bir dosya 25 MiB sınırını aşıyor.")
        toplam += bilgi.file_size
        if toplam > AZAMI_PAKET:
            paket.close()
            raise ValueError("Aktarım paketinin açılmış boyutu 100 MiB sınırını aşıyor.")
        if bilgi.compress_size and bilgi.file_size / bilgi.compress_size > 100:
            paket.close()
            raise ValueError("Aktarım paketinde aşırı sıkıştırılmış dosya var.")
    try:
        manifest = json.loads(paket.read("manifest.json"))
    except (KeyError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        paket.close()
        raise ValueError("Geçerli manifest.json bulunamadı.") from exc
    return manifest, paket


def soru_paketi_onizle(
    baglanti: sqlite3.Connection, icerik: bytes
) -> PaketOnizlemesi:
    manifest, paket = _guvenli_zip(icerik)
    try:
        if manifest.get("schema_version") != PAKET_SEMA_SURUMU:
            raise ValueError("Soru paketi şema sürümü desteklenmiyor.")
        if manifest.get("source_app") != "soru-kesici":
            raise ValueError("Bu paket Soru Kesici tarafından üretilmemiş.")
        dis_kimlik = str(manifest.get("export_id") or "").strip()
        if not dis_kimlik:
            raise ValueError("Paket dış kimliği eksik.")
        sorular = manifest.get("questions")
        if not isinstance(sorular, list) or not sorular:
            raise ValueError("Pakette soru bulunamadı.")
        ozet = hashlib.sha256(icerik).hexdigest()
        eklenecek: list[dict[str, Any]] = []
        atlanacak: list[dict[str, Any]] = []
        uyarilar: list[str] = []
        for ham in sorular:
            if not isinstance(ham, dict):
                uyarilar.append("Sözlük olmayan soru satırı atlandı.")
                continue
            dis_soru = str(ham.get("external_id") or "").strip()
            metin = str(ham.get("text") or "").strip()
            if not dis_soru or not metin:
                uyarilar.append("Kimliği veya metni boş soru atlandı.")
                continue
            var = baglanti.execute(
                "SELECT 1 FROM soru WHERE kaynak = ?", (f"soru_kesici:{dis_soru}",)
            ).fetchone()
            hedef = atlanacak if var else eklenecek
            hedef.append(
                {
                    "external_id": dis_soru,
                    "text": metin,
                    "grade": int(ham.get("grade") or 9),
                    "outcome_code": str(ham.get("outcome_code") or ""),
                    "difficulty": str(ham.get("difficulty") or "orta"),
                    "rubric": str(ham.get("rubric") or ""),
                    "image": str(ham.get("image") or ""),
                    "source_document": str(ham.get("source_document") or ""),
                    "source_page": ham.get("source_page"),
                }
            )
        return PaketOnizlemesi(
            "soru_kesici", dis_kimlik, ozet, "sorular", eklenecek, atlanacak, uyarilar
        )
    finally:
        paket.close()


def soru_paketi_uygula(
    baglanti: sqlite3.Connection, icerik: bytes, onizleme: PaketOnizlemesi
) -> int:
    """Önizlenen soru paketini atomik uygular; görselleri içerik özetiyle kopyalar."""
    gercek = soru_paketi_onizle(baglanti, icerik)
    if (
        gercek.dis_kimlik != onizleme.dis_kimlik
        or gercek.icerik_sha256 != onizleme.icerik_sha256
    ):
        raise ValueError("Paket önizlemeden sonra değişti.")
    onceki = baglanti.execute(
        "SELECT durum FROM aktarim_islemi WHERE saglayici = ? AND dis_kimlik = ? "
        "AND icerik_sha256 = ?",
        ("soru_kesici", gercek.dis_kimlik, gercek.icerik_sha256),
    ).fetchone()
    if onceki and onceki["durum"] == "tamamlandi":
        return 0
    _manifest, paket = _guvenli_zip(icerik)
    eklenen = 0
    try:
        with depo.islem(baglanti, immediate=True):
            for soru in gercek.eklenecek:
                gorsel_yolu = ""
                gorsel = soru["image"]
                if gorsel:
                    try:
                        baytlar = paket.read(gorsel)
                    except KeyError as exc:
                        raise ValueError(f"Paket görseli bulunamadı: {gorsel}") from exc
                    uzanti = PurePosixPath(gorsel).suffix.lower()
                    if uzanti not in {".png", ".jpg", ".jpeg", ".webp"}:
                        raise ValueError("Desteklenmeyen soru görseli biçimi.")
                    ad = hashlib.sha256(baytlar).hexdigest() + uzanti
                    hedef = ayarlar.materyal_dizini() / "sorular" / ad
                    hedef.parent.mkdir(parents=True, exist_ok=True)
                    if not hedef.exists():
                        hedef.write_bytes(baytlar)
                    gorsel_yolu = str(hedef)
                baglanti.execute(
                    "INSERT INTO soru "
                    "(mufredat_surumu, kazanim_kodu, sinif, metin, gorsel_yolu, rubrik, "
                    "zorluk, kaynak, olusturma) VALUES (?,?,?,?,?,?,?,?,?)",
                    (
                        "maarif_2024",
                        soru["outcome_code"],
                        soru["grade"],
                        soru["text"],
                        gorsel_yolu,
                        soru["rubric"],
                        soru["difficulty"],
                        f"soru_kesici:{soru['external_id']}",
                        _simdi(),
                    ),
                )
                eklenen += 1
            simdi = _simdi()
            baglanti.execute(
                "INSERT INTO aktarim_islemi "
                "(saglayici, yon, dis_kimlik, icerik_sha256, tur, durum, ozet_json, "
                "olusturma, guncelleme) VALUES (?,?,?,?,?,?,?,?,?) "
                "ON CONFLICT (saglayici, dis_kimlik, icerik_sha256) DO UPDATE SET "
                "durum = excluded.durum, ozet_json = excluded.ozet_json, "
                "guncelleme = excluded.guncelleme, hata = ''",
                (
                    "soru_kesici",
                    "ice",
                    gercek.dis_kimlik,
                    gercek.icerik_sha256,
                    "sorular",
                    "tamamlandi",
                    json.dumps(
                        {"eklenen": eklenen, "atlanan": len(gercek.atlanacak)},
                        ensure_ascii=False,
                    ),
                    simdi,
                    simdi,
                ),
            )
    finally:
        paket.close()
    return eklenen


def aktarimlari_oku(baglanti: sqlite3.Connection, sinir: int = 20) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT * FROM aktarim_islemi ORDER BY guncelleme DESC LIMIT ?", (sinir,)
    ).fetchall()


def paket_manifesti(
    *, source_app: str, export_id: str, tur: str, ek: dict[str, Any]
) -> dict[str, Any]:
    return {
        "schema_version": PAKET_SEMA_SURUMU,
        "protocol_version": PROTOKOL_SURUMU,
        "source_app": source_app,
        "export_id": export_id,
        "type": tur,
        "created_at": _simdi(),
        **ek,
    }


def sinav_paketi_uret(baglanti: sqlite3.Connection, sinav_id: int) -> bytes:
    """Sınav Okur'a gönderilecek değişmez sınav/öğrenci paketini üretir."""
    sinav = baglanti.execute(
        "SELECT s.*, b.ad AS sube_adi, b.sinif FROM sinav s "
        "JOIN sube b ON b.id = s.sube_id WHERE s.id = ?",
        (sinav_id,),
    ).fetchone()
    if not sinav:
        raise LookupError("Sınav bulunamadı.")
    sorular = [
        {
            "external_id": f"question:{s['soru_id']}",
            "order": s["sira"],
            "text": s["metin"],
            "max_score": s["puan"],
            "rubric": s["rubrik"],
            "outcome_code": s["kazanim_kodu"],
        }
        for s in baglanti.execute(
            "SELECT * FROM sinav_sorusu WHERE sinav_id = ? ORDER BY sira", (sinav_id,)
        )
    ]
    ogrenciler = [
        {
            "external_id": f"student:{o['id']}",
            "school_number": o["numara"],
            "name": o["ad_soyad"],
        }
        for o in baglanti.execute(
            "SELECT * FROM ogrenci WHERE sube_id = ? AND aktif = 1 ORDER BY ad_soyad",
            (sinav["sube_id"],),
        )
    ]
    manifest = paket_manifesti(
        source_app="ogretmen-cantasi",
        export_id=f"exam:{sinav_id}",
        tur="exam",
        ek={
            "exam": {
                "external_id": f"exam:{sinav_id}",
                "name": sinav["ad"],
                "date": sinav["tarih"],
                "class_name": sinav["sube_adi"],
                "grade": sinav["sinif"],
                "duration_minutes": sinav["sure_dk"],
            },
            "questions": sorular,
            "students": ogrenciler,
        },
    )
    tampon = BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr(
            "manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2)
        )
    return tampon.getvalue()


def sinav_sonucu_onizle(
    baglanti: sqlite3.Connection, icerik: bytes, sinav_id: int
) -> PaketOnizlemesi:
    manifest, paket = _guvenli_zip(icerik)
    try:
        if manifest.get("schema_version") != PAKET_SEMA_SURUMU:
            raise ValueError("Sonuç paketi şema sürümü desteklenmiyor.")
        if manifest.get("source_app") != "sinav-okur":
            raise ValueError("Bu paket Sınav Okur tarafından üretilmemiş.")
        if manifest.get("type") != "exam_results":
            raise ValueError("Paket sınav sonucu içermiyor.")
        if str(manifest.get("exam_external_id")) != f"exam:{sinav_id}":
            raise ValueError("Sonuç paketi bu sınava ait değil.")
        dis_kimlik = str(manifest.get("export_id") or "").strip()
        if not dis_kimlik:
            raise ValueError("Sonuç paketi dış kimliği eksik.")
        sinav = baglanti.execute(
            "SELECT sube_id FROM sinav WHERE id = ?", (sinav_id,)
        ).fetchone()
        if not sinav:
            raise LookupError("Sınav bulunamadı.")
        ogrenciler = {
            f"student:{o['id']}": o
            for o in baglanti.execute(
                "SELECT * FROM ogrenci WHERE sube_id = ? AND aktif = 1",
                (sinav["sube_id"],),
            )
        }
        sorular = {
            f"question:{s['soru_id']}": s
            for s in baglanti.execute(
                "SELECT * FROM sinav_sorusu WHERE sinav_id = ?", (sinav_id,)
            )
        }
        eklenecek: list[dict[str, Any]] = []
        atlanacak: list[dict[str, Any]] = []
        uyarilar: list[str] = []
        for sonuc in manifest.get("results") or []:
            if not isinstance(sonuc, dict):
                uyarilar.append("Geçersiz sonuç satırı atlandı.")
                continue
            if not sonuc.get("approved"):
                atlanacak.append({"reason": "Öğretmen onayı yok", **sonuc})
                continue
            ogrenci = ogrenciler.get(str(sonuc.get("student_external_id")))
            soru = sorular.get(str(sonuc.get("question_external_id")))
            try:
                puan = float(sonuc.get("final_score"))
            except (TypeError, ValueError):
                uyarilar.append("Sayısal olmayan puan atlandı.")
                continue
            if not ogrenci or not soru:
                uyarilar.append("Sınavla eşleşmeyen öğrenci veya soru atlandı.")
                continue
            if not 0 <= puan <= float(soru["puan"]):
                uyarilar.append("Soru puan sınırını aşan sonuç atlandı.")
                continue
            eklenecek.append(
                {
                    "student_id": ogrenci["id"],
                    "student_name": ogrenci["ad_soyad"],
                    "question_id": soru["soru_id"],
                    "question_order": soru["sira"],
                    "score": puan,
                    "confidence": sonuc.get("confidence"),
                    "decision_source": str(sonuc.get("decision_source") or ""),
                }
            )
        return PaketOnizlemesi(
            "sinav_okur",
            dis_kimlik,
            hashlib.sha256(icerik).hexdigest(),
            f"sinav_sonucu:{sinav_id}",
            eklenecek,
            atlanacak,
            uyarilar,
        )
    finally:
        paket.close()


def sinav_sonucu_uygula(
    baglanti: sqlite3.Connection,
    icerik: bytes,
    sinav_id: int,
    onizleme: PaketOnizlemesi,
) -> int:
    from . import servis_olcme as so

    gercek = sinav_sonucu_onizle(baglanti, icerik, sinav_id)
    if (
        gercek.dis_kimlik != onizleme.dis_kimlik
        or gercek.icerik_sha256 != onizleme.icerik_sha256
    ):
        raise ValueError("Sonuç paketi önizlemeden sonra değişti.")
    onceki = baglanti.execute(
        "SELECT durum FROM aktarim_islemi WHERE saglayici = ? AND dis_kimlik = ? "
        "AND icerik_sha256 = ?",
        ("sinav_okur", gercek.dis_kimlik, gercek.icerik_sha256),
    ).fetchone()
    if onceki and onceki["durum"] == "tamamlandi":
        return 0
    puanlar = [
        (s["question_id"], s["student_id"], s["score"]) for s in gercek.eklenecek
    ]
    with depo.islem(baglanti, immediate=True):
        so.soru_puani_yaz(baglanti, sinav_id, puanlar)
        simdi = _simdi()
        baglanti.execute(
            "INSERT INTO aktarim_islemi "
            "(saglayici, yon, dis_kimlik, icerik_sha256, tur, durum, ozet_json, "
            "olusturma, guncelleme) VALUES (?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT (saglayici, dis_kimlik, icerik_sha256) DO UPDATE SET "
            "durum = excluded.durum, ozet_json = excluded.ozet_json, "
            "guncelleme = excluded.guncelleme, hata = ''",
            (
                "sinav_okur",
                "ice",
                gercek.dis_kimlik,
                gercek.icerik_sha256,
                f"sinav_sonucu:{sinav_id}",
                "tamamlandi",
                json.dumps(
                    {"yazilan": len(puanlar), "atlanan": len(gercek.atlanacak)},
                    ensure_ascii=False,
                ),
                simdi,
                simdi,
            ),
        )
    return len(puanlar)
