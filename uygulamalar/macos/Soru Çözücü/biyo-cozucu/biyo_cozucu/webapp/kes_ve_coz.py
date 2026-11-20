"""Dayanikli ``Kes ve Coz`` isleri.

Bu modul Soru Kesici ile Biyo Cozucu arasindaki surec siniridir. Kullanici
belgeyi bir kez yukler; belge ayri bir surecte kesilir, surumlu paket guvenle
acilir ve sorular tek tek cozulur. Kesicinin buldugu resmi cevap model istemine
hicbir zaman eklenmez. Yalniz cozum bittikten sonra karsilastirma icin kullanilir.

Is kayitlari ana ``biyo.db`` dosyasindan ayri tutulur. Boylece binlerce soruluk
bir kuyruğun sik durum yazmalari cozum/onay veritabanini sisirmez ve uygulama
yeniden basladiginda yarim isler guvenle surdurulebilir.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import math
import os
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import threading
import time
import uuid
import zipfile
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse

from ..cevap import cevap_eslesiyor
from ..gorsel import AZAMI_BOYUT_MB as AZAMI_GORSEL_MB
from ..gorsel import GorselDeposu
from ..gorsel_zeka import siniflandir as gorseli_siniflandir
from ..modeller import Cozum

PAKET_SURUMU = "kes-ve-coz-question-package-v1"
PAKET_KUNYE_ADLARI = (
    "kes-ve-coz-manifest.json",
    "manifest.json",
    "package.json",
)

AZAMI_YUKLEME_BAYT = 400 * 1024 * 1024
AZAMI_ACILMIS_BAYT = 2 * 1024 * 1024 * 1024
AZAMI_ARSIV_UYESI = 20_000
AZAMI_SORU = 10_000
AZAMI_MANIFEST_BAYT = 64 * 1024 * 1024
AKIS_PARCA_BAYT = 1024 * 1024

DESTEKLENEN_GIRDI_UZANTILARI = {
    ".pdf",
    ".docx",
    ".png",
    ".jpg",
    ".jpeg",
    ".tif",
    ".tiff",
    ".bmp",
    ".webp",
    ".gif",
    # Hazir Soru Kesici arsivi: kesim adimi atlanir, dogrudan cozulur.
    ".zip",
}
HAZIR_ARSIV_UZANTISI = ".zip"
GORSEL_UZANTILARI = {".png", ".jpg", ".jpeg", ".webp"}
GORSEL_MEDYA_TURLERI = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
}

IS_TERMINAL = frozenset({"tamamlandı", "kısmi", "hata", "durduruldu"})
SORU_TERMINAL = frozenset({"tamamlandı", "inceleme", "hata", "atlanmış"})

def _simdi() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def _sinirli_tamsayi(ham: Any, ust: int) -> int:
    try:
        deger = int(ham)
    except (TypeError, ValueError):
        return 0
    return max(0, min(ust, deger))


def _model_gorseli_gerekli_mi(soru: PaketSorusu) -> bool:
    """Kesimi yalnız görsel bilgi gerçekten gerekiyorsa modele gönder.

    Soru Kesici her soru için kullanıcıya gösterilecek bir kırpım üretir;
    bu, her kırpımın VLM gerektirdiği anlamına gelmez. Uzun ve şıkları tam
    çıkarılmış düz metin soruları metin motorunda daha hızlı ve daha kararlı
    çözülür. Kısa/eksik OCR ya da şekil, grafik, tablo ve soyağacı işaretleri
    varsa görsel yol korunur.
    """
    karar = gorseli_siniflandir(
        soru.metin,
        soru.secenekler,
        gorsel_var=soru.gorsel_yolu is not None,
    )
    return karar.gerekli


def _surec_grubuna_sinyal(surec: subprocess.Popen[bytes], sinyal: int) -> None:
    """Kesicinin OCR/LibreOffice cocuklarini da tek islemde sonlandirir."""
    # ``start_new_session=True`` ile baslatilan liderin PID'si ayni zamanda
    # surec grubu kimligidir. Lider cocuklarindan once cikmis olabilir; bu
    # nedenle ``poll()`` sonucuna bakip erken donmek yetim OCR/LibreOffice
    # sureclerini geride birakir.
    grup = surec.pid
    try:
        if grup == os.getpgrp():
            raise OSError("alt surec ayri surec grubunda degil")
        os.killpg(grup, sinyal)
    except ProcessLookupError:
        return
    except OSError:
        if surec.poll() is None:
            with suppress(OSError):
                surec.send_signal(sinyal)


def _surec_grubu_calisiyor(surec: subprocess.Popen[bytes]) -> bool:
    """Lider ciksa bile ayni oturumdaki cocuklarin yasayip yasamadigini soyler."""
    # Lideri burada reap etmek grup kimliginin yalniz bir zombi yuzunden
    # var gorunmesini onler.
    surec.poll()
    try:
        os.killpg(surec.pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _surec_grubunun_bitmesini_bekle(
    surec: subprocess.Popen[bytes], sure: float
) -> bool:
    bitis = time.monotonic() + max(0.0, sure)
    while _surec_grubu_calisiyor(surec):
        if time.monotonic() >= bitis:
            return False
        time.sleep(0.05)
    return True


def _atomik_json_yaz(yol: Path, veri: object) -> None:
    gecici = yol.with_suffix(yol.suffix + ".tmp")
    gecici.write_text(
        json.dumps(veri, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    os.replace(gecici, yol)


def _dosya_sha256(yol: Path) -> str:
    ozet = hashlib.sha256()
    with yol.open("rb") as kaynak:
        for parca in iter(lambda: kaynak.read(AKIS_PARCA_BAYT), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _guvenli_ad(ad: str, sira: int) -> str:
    """Tarayicidan gelen dizin/kontrol karakterlerini dosya adindan dusurur."""
    temiz = Path((ad or "").replace("\\", "/")).name
    temiz = "".join(c for c in temiz if c.isprintable() and c not in "/\\:").strip()
    if not temiz:
        temiz = f"belge-{sira}"
    # APFS 255 bayt sinirina yaklasmamak ve log/arayuz sisirmemek icin.
    kok, uzanti = os.path.splitext(temiz)
    return f"{kok[:120] or 'belge'}{uzanti[:16].lower()}"


class KesVeCozHatasi(RuntimeError):
    """Kullaniciya guvenle gosterilebilen is/paket hatasi."""


class YuklemeCokBuyuk(KesVeCozHatasi):
    """Yukleme akista boyut sinirini astiginda."""


@dataclass(frozen=True)
class PaketSorusu:
    """Soru Kesici paketinin dogrulanmis, cevap sizdirmaz gorunumu."""

    external_id: str
    sira: int
    metin: str
    secenekler: dict[str, str] = field(default_factory=dict)
    gorsel_yolu: Path | None = None
    kaynak_belge: str = ""
    kaynak_sayfa: int | None = None
    kaynak_kutu: list[float] = field(default_factory=list)
    kesici_surumu: str = ""
    guven: float = 0.0
    kalite_durumu: str = "automatic"
    inceleme_gerekli: bool = False
    uyarilar: list[str] = field(default_factory=list)
    referans_cevap: str = ""
    kaynak_parcalar: list[dict[str, Any]] = field(default_factory=list)

    def provenance(self) -> dict[str, Any]:
        return {
            "external_id": self.external_id,
            "source_document": self.kaynak_belge,
            "source_page": self.kaynak_sayfa,
            "source_box": self.kaynak_kutu,
            "source_parts": self.kaynak_parcalar,
            "cutter_version": self.kesici_surumu,
            "confidence": self.guven,
            "quality_status": self.kalite_durumu,
            "review_required": self.inceleme_gerekli,
            "warnings": self.uyarilar,
        }


class KesVeCozDeposu:
    """Is kuyrugu icin ayri, thread-guvenli SQLite deposu."""

    def __init__(self, yol: str | Path):
        self.yol = Path(yol)
        self.yol.parent.mkdir(parents=True, exist_ok=True)
        self._kilit = threading.RLock()
        self._db = sqlite3.connect(str(self.yol), check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA journal_mode = WAL")
        self._db.execute("PRAGMA busy_timeout = 5000")
        self._kur()

    def _kur(self) -> None:
        with self._kilit, self._db:
            self._db.executescript(
                """
                CREATE TABLE IF NOT EXISTS isler (
                    id TEXT PRIMARY KEY,
                    durum TEXT NOT NULL,
                    asama TEXT NOT NULL,
                    ilerleme INTEGER NOT NULL DEFAULT 0,
                    mesaj TEXT NOT NULL DEFAULT '',
                    toplam INTEGER NOT NULL DEFAULT 0,
                    kesilen INTEGER NOT NULL DEFAULT 0,
                    cozulen INTEGER NOT NULL DEFAULT 0,
                    inceleme INTEGER NOT NULL DEFAULT 0,
                    hata_sayisi INTEGER NOT NULL DEFAULT 0,
                    durdur_istendi INTEGER NOT NULL DEFAULT 0,
                    girdiler_json TEXT NOT NULL DEFAULT '[]',
                    girdi_imzasi TEXT NOT NULL DEFAULT '',
                    arsiv_yolu TEXT NOT NULL DEFAULT '',
                    hata TEXT NOT NULL DEFAULT '',
                    olusturma TEXT NOT NULL,
                    guncelleme TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sorular (
                    is_id TEXT NOT NULL REFERENCES isler(id) ON DELETE CASCADE,
                    sira INTEGER NOT NULL,
                    external_id TEXT NOT NULL,
                    durum TEXT NOT NULL DEFAULT 'bekliyor',
                    soru TEXT NOT NULL,
                    secenekler_json TEXT NOT NULL DEFAULT '{}',
                    gorsel_yolu TEXT NOT NULL DEFAULT '',
                    provenance_json TEXT NOT NULL DEFAULT '{}',
                    inceleme_gerekli INTEGER NOT NULL DEFAULT 0,
                    referans_cevap TEXT NOT NULL DEFAULT '',
                    cozum_girdisi_imzasi TEXT NOT NULL DEFAULT '',
                    referans_eslesmesi INTEGER,
                    cozum_json TEXT NOT NULL DEFAULT '',
                    hata TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (is_id, sira)
                );
                CREATE INDEX IF NOT EXISTS ix_kes_ve_coz_is_durum
                    ON isler(durum, guncelleme);
                CREATE INDEX IF NOT EXISTS ix_kes_ve_coz_soru_durum
                    ON sorular(is_id, durum, sira);
                """
            )
            # Surec model uretirken kapanmissa ayni soru yeniden denenebilir.
            # Cozum kaydi yazildiysa durum zaten terminaldir; bu guncelleme
            # yalniz yarim kalmis satiri kuyruga geri koyar.
            self._db.execute(
                "UPDATE sorular SET durum='bekliyor' WHERE durum='çözülüyor'"
            )
            sutunlar = {
                str(s["name"])
                for s in self._db.execute("PRAGMA table_info(sorular)").fetchall()
            }
            if "inceleme_gerekli" not in sutunlar:
                self._db.execute(
                    "ALTER TABLE sorular ADD COLUMN inceleme_gerekli "
                    "INTEGER NOT NULL DEFAULT 0"
                )
            if "cozum_girdisi_imzasi" not in sutunlar:
                self._db.execute(
                    "ALTER TABLE sorular ADD COLUMN cozum_girdisi_imzasi "
                    "TEXT NOT NULL DEFAULT ''"
                )
            # Fingerprint oncesinden kalan terminal cozumlerin girdisi yeniden
            # dogrulanamaz. Cozumu silme; fakat sessizce guvenilir sayma ve eski
            # anahtar eslesmesini kesin bilgi gibi gostermeme.
            self._db.execute(
                """
                UPDATE sorular
                   SET inceleme_gerekli=1, referans_eslesmesi=NULL
                 WHERE cozum_girdisi_imzasi=''
                   AND cozum_json<>''
                   AND durum IN ('tamamlandı','inceleme')
                """
            )
            self._db.execute(
                """
                UPDATE isler
                   SET inceleme=(SELECT COUNT(*) FROM sorular s
                                  WHERE s.is_id=isler.id
                                    AND (s.inceleme_gerekli=1
                                         OR s.durum='inceleme'))
                """
            )

    def kapat(self) -> None:
        with self._kilit:
            self._db.close()

    def is_ekle(
        self,
        is_id: str,
        *,
        girdiler: list[dict[str, Any]],
        girdi_imzasi: str,
        arsiv_yolu: Path,
    ) -> None:
        simdi = _simdi()
        with self._kilit, self._db:
            self._db.execute(
                """
                INSERT INTO isler(
                    id, durum, asama, ilerleme, mesaj, girdiler_json,
                    girdi_imzasi, arsiv_yolu, olusturma, guncelleme
                ) VALUES(?, 'bekliyor', 'yuklendi', 0, ?, ?, ?, ?, ?, ?)
                """,
                (
                    is_id,
                    "Belge alindi; kesim kuyrugunda.",
                    json.dumps(girdiler, ensure_ascii=False),
                    girdi_imzasi,
                    str(arsiv_yolu),
                    simdi,
                    simdi,
                ),
            )

    def is_getir(self, is_id: str) -> dict[str, Any] | None:
        with self._kilit:
            satir = self._db.execute(
                "SELECT * FROM isler WHERE id=?", (is_id,)
            ).fetchone()
        return dict(satir) if satir is not None else None

    def son_isler(self, sinir: int = 20) -> list[dict[str, Any]]:
        with self._kilit:
            satirlar = self._db.execute(
                "SELECT * FROM isler ORDER BY olusturma DESC LIMIT ?",
                (max(1, min(100, sinir)),),
            ).fetchall()
        return [dict(s) for s in satirlar]

    def kurtarilacak_isler(self) -> list[str]:
        yer_tutucular = ",".join("?" for _ in IS_TERMINAL)
        with self._kilit, self._db:
            # Durdurma istegi kalici bir kullanici kararidir. Surec tam bu
            # bayrak yazildiktan sonra kapanirsa isi yeniden baslatmak da,
            # sonsuza dek ``bekliyor`` birakmak da yanlistir: terminale cek.
            self._db.execute(
                f"""
                UPDATE sorular SET durum='atlanmış'
                 WHERE durum IN ('bekliyor','çözülüyor')
                   AND is_id IN (
                       SELECT id FROM isler
                        WHERE durdur_istendi=1
                          AND durum NOT IN ({yer_tutucular})
                   )
                """,
                tuple(sorted(IS_TERMINAL)),
            )
            self._db.execute(
                f"""
                UPDATE isler
                   SET durum='durduruldu', asama='bitti',
                       mesaj='Önceki durdurma isteği tamamlandı.',
                       cozulen=(SELECT COUNT(*) FROM sorular s
                                WHERE s.is_id=isler.id
                                  AND s.durum IN ('tamamlandı','inceleme')),
                       inceleme=(SELECT COUNT(*) FROM sorular s
                                 WHERE s.is_id=isler.id
                                   AND (s.inceleme_gerekli=1
                                        OR s.durum='inceleme')),
                       hata_sayisi=(SELECT COUNT(*) FROM sorular s
                                    WHERE s.is_id=isler.id
                                      AND s.durum='hata'),
                       guncelleme=?
                 WHERE durdur_istendi=1
                   AND durum NOT IN ({yer_tutucular})
                """,
                (_simdi(), *sorted(IS_TERMINAL)),
            )
            self._db.execute(
                f"""
                UPDATE isler
                   SET durum='bekliyor', asama='kurtarma', ilerleme=0,
                       mesaj='Uygulama yeniden basladi; is guvenle surdurulecek.',
                       guncelleme=?
                 WHERE durdur_istendi=0 AND durum NOT IN ({yer_tutucular})
                """,
                (_simdi(), *sorted(IS_TERMINAL)),
            )
            satirlar = self._db.execute(
                "SELECT id FROM isler WHERE durum='bekliyor' "
                "AND durdur_istendi=0 ORDER BY olusturma"
            ).fetchall()
        return [str(s["id"]) for s in satirlar]

    def is_guncelle(self, is_id: str, **alanlar: Any) -> None:
        izinli = {
            "durum",
            "asama",
            "ilerleme",
            "mesaj",
            "toplam",
            "kesilen",
            "cozulen",
            "inceleme",
            "hata_sayisi",
            "durdur_istendi",
            "hata",
        }
        guncel = {k: v for k, v in alanlar.items() if k in izinli}
        if not guncel:
            return
        guncel["guncelleme"] = _simdi()
        sql = ", ".join(f"{ad}=?" for ad in guncel)
        with self._kilit, self._db:
            self._db.execute(
                f"UPDATE isler SET {sql} WHERE id=?", (*guncel.values(), is_id)
            )

    def durdur_iste(self, is_id: str) -> bool:
        with self._kilit, self._db:
            sonuc = self._db.execute(
                """
                UPDATE isler SET durdur_istendi=1, mesaj=?, guncelleme=?
                 WHERE id=? AND durum NOT IN ('tamamlandı','kısmi','hata','durduruldu')
                """,
                ("Is durduruluyor...", _simdi(), is_id),
            )
        return bool(sonuc.rowcount)

    def durdur_istendi_mi(self, is_id: str) -> bool:
        with self._kilit:
            satir = self._db.execute(
                "SELECT durdur_istendi FROM isler WHERE id=?", (is_id,)
            ).fetchone()
        return bool(satir and satir["durdur_istendi"])

    def soru_ekle(self, is_id: str, soru: PaketSorusu) -> None:
        cozum_girdisi_imzasi, eski_cozum_girdisi_imzasi = (
            _cozum_girdisi_imzalari(soru)
        )
        with self._kilit, self._db:
            self._soru_ekle(
                is_id,
                soru,
                cozum_girdisi_imzasi,
                eski_cozum_girdisi_imzasi,
            )

    def sorulari_esitle(self, is_id: str, sorular: Iterable[PaketSorusu]) -> None:
        """Manifesti atomik esitle; artik bulunmayan eski sorulari tasima."""
        hazir = [
            (soru, *_cozum_girdisi_imzalari(soru)) for soru in sorular
        ]
        guncel = {
            soru.sira: soru.external_id for soru, _imza, _eski_imza in hazir
        }
        if len(guncel) != len(hazir) or len(set(guncel.values())) != len(hazir):
            raise KesVeCozHatasi("Manifestte yinelenen soru sirasi veya kimligi var.")

        with self._kilit, self._db:
            mevcut = self._db.execute(
                "SELECT sira, external_id FROM sorular WHERE is_id=?", (is_id,)
            ).fetchall()
            silinecek = [
                (is_id, int(satir["sira"]))
                for satir in mevcut
                if guncel.get(int(satir["sira"])) != str(satir["external_id"])
            ]
            if silinecek:
                self._db.executemany(
                    "DELETE FROM sorular WHERE is_id=? AND sira=?", silinecek
                )
            for soru, imza, eski_imza in hazir:
                self._soru_ekle(is_id, soru, imza, eski_imza)

    def _soru_ekle(
        self,
        is_id: str,
        soru: PaketSorusu,
        cozum_girdisi_imzasi: str,
        eski_cozum_girdisi_imzasi: str,
    ) -> None:
        # Uyari bilgisini icermeyen eski fingerprint'i yalniz ayni eski girdi
        # ve ayni kanonik paket uyarilari birlikte dogrulanabiliyorsa v2'ye
        # yukselt. Bozuk provenance veya uyari farki fail-closed yeniden cozer.
        mevcut = self._db.execute(
            """
            SELECT cozum_girdisi_imzasi, provenance_json
              FROM sorular WHERE is_id=? AND sira=?
            """,
            (is_id, soru.sira),
        ).fetchone()
        if mevcut is not None:
            mevcut_imza = str(mevcut["cozum_girdisi_imzasi"] or "")
            eski_uyarilar: list[str] | None = None
            try:
                eski_provenance = json.loads(mevcut["provenance_json"] or "{}")
                if isinstance(eski_provenance, dict):
                    eski_uyarilar = _kanonik_paket_uyarilari(
                        eski_provenance.get("warnings", [])
                    )
            except (TypeError, json.JSONDecodeError):
                pass
            if (
                mevcut_imza
                and not mevcut_imza.startswith("v2:")
                and mevcut_imza == eski_cozum_girdisi_imzasi
                and eski_uyarilar == _kanonik_paket_uyarilari(soru.uyarilar)
            ):
                self._db.execute(
                    """
                    UPDATE sorular SET cozum_girdisi_imzasi=?
                     WHERE is_id=? AND sira=? AND cozum_girdisi_imzasi=?
                    """,
                    (cozum_girdisi_imzasi, is_id, soru.sira, mevcut_imza),
                )
        self._db.execute(
            """
                INSERT INTO sorular(
                    is_id, sira, external_id, durum, soru, secenekler_json,
                    gorsel_yolu, provenance_json, inceleme_gerekli,
                    referans_cevap, cozum_girdisi_imzasi
                ) VALUES(?, ?, ?, 'bekliyor', ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(is_id, sira) DO UPDATE SET
                    durum=CASE
                        WHEN sorular.cozum_girdisi_imzasi<>''
                         AND sorular.cozum_girdisi_imzasi=
                             excluded.cozum_girdisi_imzasi
                        THEN sorular.durum ELSE 'bekliyor' END,
                    external_id=excluded.external_id,
                    soru=excluded.soru,
                    secenekler_json=excluded.secenekler_json,
                    gorsel_yolu=excluded.gorsel_yolu,
                    provenance_json=excluded.provenance_json,
                    inceleme_gerekli=excluded.inceleme_gerekli,
                    referans_cevap=excluded.referans_cevap,
                    cozum_girdisi_imzasi=excluded.cozum_girdisi_imzasi,
                    referans_eslesmesi=CASE
                        WHEN excluded.referans_cevap<>''
                         AND sorular.cozum_girdisi_imzasi<>''
                         AND sorular.cozum_girdisi_imzasi=
                             excluded.cozum_girdisi_imzasi
                        THEN sorular.referans_eslesmesi ELSE NULL END,
                    cozum_json=CASE
                        WHEN sorular.cozum_girdisi_imzasi<>''
                         AND sorular.cozum_girdisi_imzasi=
                             excluded.cozum_girdisi_imzasi
                        THEN sorular.cozum_json ELSE '' END,
                    hata=CASE
                        WHEN sorular.cozum_girdisi_imzasi<>''
                         AND sorular.cozum_girdisi_imzasi=
                             excluded.cozum_girdisi_imzasi
                        THEN sorular.hata ELSE '' END
            """,
            (
                is_id,
                soru.sira,
                soru.external_id,
                soru.metin,
                json.dumps(soru.secenekler, ensure_ascii=False),
                str(soru.gorsel_yolu or ""),
                json.dumps(soru.provenance(), ensure_ascii=False),
                int(soru.inceleme_gerekli),
                soru.referans_cevap,
                cozum_girdisi_imzasi,
            ),
        )

    def soru_durumu(self, is_id: str, sira: int) -> str:
        with self._kilit:
            satir = self._db.execute(
                "SELECT durum FROM sorular WHERE is_id=? AND sira=?",
                (is_id, sira),
            ).fetchone()
        return str(satir["durum"]) if satir else ""

    def soru_guncelle(self, is_id: str, sira: int, **alanlar: Any) -> None:
        izinli = {
            "durum",
            "referans_eslesmesi",
            "cozum_json",
            "hata",
        }
        guncel = {k: v for k, v in alanlar.items() if k in izinli}
        if not guncel:
            return
        sql = ", ".join(f"{ad}=?" for ad in guncel)
        with self._kilit, self._db:
            self._db.execute(
                f"UPDATE sorular SET {sql} WHERE is_id=? AND sira=?",
                (*guncel.values(), is_id, sira),
            )

    def bekleyenleri_atla(self, is_id: str) -> None:
        with self._kilit, self._db:
            self._db.execute(
                """
                UPDATE sorular SET durum='atlanmış'
                 WHERE is_id=? AND durum IN ('bekliyor','çözülüyor')
                """,
                (is_id,),
            )

    def fatal_sorulari_bitir(self, is_id: str, hata: str) -> None:
        """Is duzeyindeki hata sonrasi hicbir soruyu gecici durumda birakmaz."""
        with self._kilit, self._db:
            self._db.execute(
                """
                UPDATE sorular SET durum='hata', hata=?
                 WHERE is_id=? AND durum='çözülüyor'
                """,
                (hata, is_id),
            )
            self._db.execute(
                """
                UPDATE sorular SET durum='atlanmış'
                 WHERE is_id=? AND durum='bekliyor'
                """,
                (is_id,),
            )

    def sorular(self, is_id: str) -> list[dict[str, Any]]:
        with self._kilit:
            satirlar = self._db.execute(
                "SELECT * FROM sorular WHERE is_id=? ORDER BY sira", (is_id,)
            ).fetchall()
        return [dict(s) for s in satirlar]

    def soru_getir(self, is_id: str, sira: int) -> dict[str, Any] | None:
        with self._kilit:
            satir = self._db.execute(
                "SELECT * FROM sorular WHERE is_id=? AND sira=?", (is_id, sira)
            ).fetchone()
        return dict(satir) if satir is not None else None

    def soru_sayaclari(self, is_id: str) -> dict[str, int]:
        """Kuyruk sayaclarini Python'a binlerce satir tasimadan hesaplar."""
        with self._kilit:
            satir = self._db.execute(
                """
                SELECT COUNT(*) AS toplam,
                       SUM(CASE WHEN durum IN ('tamamlandı','inceleme')
                                THEN 1 ELSE 0 END) AS cozulmus,
                       SUM(CASE WHEN inceleme_gerekli=1 OR durum='inceleme'
                                THEN 1 ELSE 0 END) AS inceleme,
                       SUM(CASE WHEN durum='hata' THEN 1 ELSE 0 END) AS hata,
                       SUM(CASE WHEN durum='atlanmış' THEN 1 ELSE 0 END) AS atlanmis
                  FROM sorular WHERE is_id=?
                """,
                (is_id,),
            ).fetchone()
        return {
            ad: int(satir[ad] or 0)
            for ad in ("toplam", "cozulmus", "inceleme", "hata", "atlanmis")
        }


KomutKurucu = Callable[[list[Path], Path], tuple[list[str], Path]]


def _soru_kesici_koku() -> Path:
    ortam = os.environ.get("SORU_KESICI_KOK", "").strip()
    adaylar = [
        Path(ortam).expanduser() if ortam else None,
        Path.home() / "Developer" / "soru-kesici",
        Path.home() / "Documents" / "soru-kesici",
    ]
    for aday in adaylar:
        if aday is not None and (aday / "soru_kes.py").is_file():
            return aday.resolve()
    raise KesVeCozHatasi(
        "Soru Kesici bulunamadi. SORU_KESICI_KOK ile proje klasorunu belirtin."
    )


def varsayilan_paketleyici_komutu(
    girdiler: list[Path], cikti: Path
) -> tuple[list[str], Path]:
    """Kurulu Soru Kesici'yi kabuksuz ve sabit argumanlarla calistirir."""
    kok = _soru_kesici_koku()
    from biyo_cozucu.webapp.merkez import _soru_kesici_python
    python = _soru_kesici_python(kok)
    if len(girdiler) != 1:
        raise KesVeCozHatasi("Bir Kes ve Coz isinde tek kitap veya test olmali.")
    paketleyici = kok / "kes_ve_coz_paketle.py"
    if paketleyici.is_file():
        if not python.is_file():
            raise KesVeCozHatasi(
                "Soru Kesici Python ortami bulunamadi: .venv/bin/python"
            )
        yorumlayici = str(python)
        # Bas-siz kopru kaliteyi ``balanced`` olarak sabitler ve otomatik ile
        # inceleme sorularini ayni v1 pakette teslim eder.
        komut = [
            yorumlayici,
            str(paketleyici),
            str(girdiler[0]),
            "--output",
            str(cikti),
            "--max-input-mb",
            "400",
            "--max-output-mb",
            "2048",
            "--max-questions",
            str(AZAMI_SORU),
        ]
    else:
        yorumlayici = str(python if python.is_file() else Path(sys.executable))
        # Gecis uyumlulugu: bas-siz kopru henuz kurulmamissa eski CLI ile tek
        # belgeyi kes. Cikti ``sorular.json``dan ic v1 manifestine cevrilir.
        komut = [
            yorumlayici,
            str(kok / "soru_kes.py"),
            str(girdiler[0]),
            "-o",
            str(cikti),
            "--kalite",
            "legacy",
            "--birlestirme",
            "acik",
        ]
    return komut, kok


class KesVeCozServisi:
    """Tek isciyle kesim + cozum kuyrugunu yurutur."""

    def __init__(
        self,
        kok: str | Path,
        cozucu_fabrikasi: Callable[[], Any],
        *,
        komut_kurucu: KomutKurucu = varsayilan_paketleyici_komutu,
        azami_yukleme_bayt: int = AZAMI_YUKLEME_BAYT,
        baslangicta_kurtar: bool = True,
    ):
        self.kok = Path(kok)
        self.is_koku = self.kok / "kes_ve_coz"
        self.is_dizini = self.is_koku / "isler"
        self.is_dizini.mkdir(parents=True, exist_ok=True)
        self.is_koku.chmod(0o700)
        self.is_dizini.chmod(0o700)
        self.depo = KesVeCozDeposu(self.is_koku / "isler.db")
        self._cozucu_fabrikasi = cozucu_fabrikasi
        self._komut_kurucu = komut_kurucu
        self.azami_yukleme_bayt = max(1, int(azami_yukleme_bayt))
        self._havuz = ThreadPoolExecutor(max_workers=1, thread_name_prefix="kes-ve-coz")
        self._kilit = threading.RLock()
        self._calisan: set[str] = set()
        self._surecler: dict[str, subprocess.Popen[bytes]] = {}
        self._bekleme = threading.Event()
        self._kapandi = False
        if baslangicta_kurtar:
            for is_id in self.depo.kurtarilacak_isler():
                self.baslat(is_id)

    def kapat(self) -> None:
        with self._kilit:
            self._kapandi = True
            surecler = list(self._surecler.values())
        self._bekleme.set()
        for surec in surecler:
            _surec_grubuna_sinyal(surec, signal.SIGTERM)
        self._havuz.shutdown(wait=True, cancel_futures=True)
        self.depo.kapat()

    def _is_dizini(self, is_id: str) -> Path:
        if not is_id or any(c not in "0123456789abcdef-" for c in is_id):
            raise KesVeCozHatasi("Gecersiz is kimligi.")
        yol = (self.is_dizini / is_id).resolve()
        if yol.parent != self.is_dizini.resolve():
            raise KesVeCozHatasi("Gecersiz is yolu.")
        return yol

    async def yukle(self, dosyalar: list[UploadFile]) -> str:
        """UploadFile'lari bellekte biriktirmeden is dizinine yazar."""
        gercek = [d for d in dosyalar if (d.filename or "").strip()]
        if not gercek:
            raise KesVeCozHatasi("En az bir kitap veya test dosyasi secin.")
        if len(gercek) > 1:
            raise KesVeCozHatasi(
                "Her is tek bir kitap veya test icindir; dosyalari ayri ayri yukleyin."
            )

        is_id = str(uuid.uuid4())
        is_dizini = self._is_dizini(is_id)
        girdi_dizini = is_dizini / "girdi"
        girdi_dizini.mkdir(parents=True)
        is_dizini.chmod(0o700)
        girdi_dizini.chmod(0o700)
        toplam = 0
        butun_imza = hashlib.sha256()
        girdiler: list[dict[str, Any]] = []
        try:
            for sira, yukleme in enumerate(gercek, 1):
                ad = _guvenli_ad(yukleme.filename or "", sira)
                uzanti = Path(ad).suffix.casefold()
                if uzanti not in DESTEKLENEN_GIRDI_UZANTILARI:
                    destek = ", ".join(sorted(DESTEKLENEN_GIRDI_UZANTILARI))
                    raise KesVeCozHatasi(
                        f"{ad}: desteklenmeyen dosya turu. Desteklenenler: {destek}"
                    )
                hedef = girdi_dizini / f"{sira:03d}-{ad}"
                dosya_imzasi = hashlib.sha256()
                boyut = 0
                with hedef.open("xb") as cikti:
                    while True:
                        parca = await yukleme.read(AKIS_PARCA_BAYT)
                        if not parca:
                            break
                        toplam += len(parca)
                        boyut += len(parca)
                        if toplam > self.azami_yukleme_bayt:
                            sinir_mb = self.azami_yukleme_bayt / (1024 * 1024)
                            raise YuklemeCokBuyuk(
                                f"Yukleme {sinir_mb:g} MB sinirini asiyor; kitabi "
                                "bolumler halinde yukleyin."
                            )
                        dosya_imzasi.update(parca)
                        butun_imza.update(parca)
                        cikti.write(parca)
                    cikti.flush()
                    os.fsync(cikti.fileno())
                hedef.chmod(0o600)
                await yukleme.close()
                if boyut == 0:
                    raise KesVeCozHatasi(f"{ad}: dosya bos.")
                girdiler.append(
                    {
                        "ad": ad,
                        "yol": str(hedef),
                        "boyut": boyut,
                        "sha256": dosya_imzasi.hexdigest(),
                    }
                )
            arsiv = is_dizini / "soru-paketi.zip"
            if Path(girdiler[0]["ad"]).suffix.casefold() == HAZIR_ARSIV_UZANTISI:
                # Hazir arsiv yuklendi: kesim yapilacak bir belge yok. Dosyayi
                # paket konumuna baglayinca yurutucu ``_paketle`` adimini
                # atlayip dogrudan dogrulama+cozme hattina giriyor.
                kaynak = Path(girdiler[0]["yol"])
                _yuklenen_arsivi_dogrula(kaynak)
                try:
                    os.link(kaynak, arsiv)
                except OSError:
                    shutil.copyfile(kaynak, arsiv)
                arsiv.chmod(0o600)
            _atomik_json_yaz(is_dizini / "girdiler.json", girdiler)
            self.depo.is_ekle(
                is_id,
                girdiler=girdiler,
                girdi_imzasi=butun_imza.hexdigest(),
                arsiv_yolu=arsiv,
            )
            return is_id
        except Exception:
            for yukleme in gercek:
                with suppress(Exception):
                    await yukleme.close()
            shutil.rmtree(is_dizini, ignore_errors=True)
            raise

    def baslat(self, is_id: str) -> None:
        with self._kilit:
            if self._kapandi or is_id in self._calisan:
                return
            kayit = self.depo.is_getir(is_id)
            if kayit is None or kayit["durum"] in IS_TERMINAL:
                return
            self._calisan.add(is_id)
            self._havuz.submit(self._calistir, is_id)

    def durdur(self, is_id: str) -> bool:
        if self.depo.is_getir(is_id) is None:
            raise KeyError(is_id)
        degisti = self.depo.durdur_iste(is_id)
        with self._kilit:
            surec = self._surecler.get(is_id)
        if surec is not None and surec.poll() is None:
            _surec_grubuna_sinyal(surec, signal.SIGTERM)
        return degisti

    def _calistir(self, is_id: str) -> None:
        is_kilidi = None
        try:
            # Uvicorn reload'u veya yanlislikla acilan ikinci worker ayni
            # SQLite kuyrugunu gorebilir. Thread kilidi surecler arasinda
            # yeterli degildir; flock coklu calismayi onler ve sahibi
            # coktugunde isletim sistemi tarafindan otomatik birakilir.
            kilit_yolu = self._is_dizini(is_id) / ".islem.lock"
            is_kilidi = kilit_yolu.open("a+b")
            try:
                fcntl.flock(is_kilidi.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            is_kilidi.seek(0)
            is_kilidi.truncate()
            is_kilidi.write(f"{os.getpid()}\n".encode())
            is_kilidi.flush()

            kayit = self.depo.is_getir(is_id)
            if kayit is None:
                return
            if self.depo.durdur_istendi_mi(is_id):
                self._durduruldu(is_id)
                return

            arsiv = Path(str(kayit["arsiv_yolu"]))
            if not arsiv.is_file():
                self._paketle(is_id, kayit, arsiv)
            if self.depo.durdur_istendi_mi(is_id):
                self._durduruldu(is_id)
                return

            self.depo.is_guncelle(
                is_id,
                durum="çalışıyor",
                asama="paket-dogrulama",
                ilerleme=18,
                mesaj="Kesilen sorular dogrulaniyor.",
            )
            paket_dizini = self._is_dizini(is_id) / "paket"
            if paket_dizini.exists():
                shutil.rmtree(paket_dizini)
            paket_dizini.mkdir()
            _guvenli_zip_ac(arsiv, paket_dizini)
            sorular = _paket_sorularini_oku(paket_dizini)
            if not sorular:
                raise KesVeCozHatasi("Soru Kesici pakette cozulebilir soru bulamadi.")

            _atomik_json_yaz(
                self._is_dizini(is_id) / "dogrulanmis-manifest.v1.json",
                _normalize_manifest(sorular),
            )
            self.depo.sorulari_esitle(is_id, sorular)
            kesim_sayaclari = self.depo.soru_sayaclari(is_id)
            self.depo.is_guncelle(
                is_id,
                durum="çalışıyor",
                asama="cozum",
                ilerleme=20,
                toplam=len(sorular),
                kesilen=len(sorular),
                inceleme=kesim_sayaclari["inceleme"],
                mesaj=f"{len(sorular)} soru kesildi; cozum basladi.",
            )
            self._sorulari_coz(is_id, sorular)
        except Exception as exc:  # noqa: BLE001 - is hatasi kayda donusturulur
            if self._kapandi:
                self._duraklat(is_id)
            elif self.depo.durdur_istendi_mi(is_id):
                self._durduruldu(is_id)
            else:
                self._hata_ile_bitir(is_id, exc)
        finally:
            if is_kilidi is not None:
                with suppress(OSError):
                    fcntl.flock(is_kilidi.fileno(), fcntl.LOCK_UN)
                is_kilidi.close()
            with self._kilit:
                self._calisan.discard(is_id)
                self._surecler.pop(is_id, None)

    def _paketle(self, is_id: str, kayit: dict[str, Any], arsiv: Path) -> None:
        try:
            girdiler = json.loads(str(kayit["girdiler_json"]))
            yollar = [Path(str(g["yol"])) for g in girdiler]
        except (TypeError, ValueError, KeyError, json.JSONDecodeError) as exc:
            raise KesVeCozHatasi("Isin girdi kaydi bozuk.") from exc
        if not yollar:
            raise KesVeCozHatasi(
                "Yuklenen belge bulunamadi; is yeniden baslatilamiyor."
            )
        girdi_koku = (self._is_dizini(is_id) / "girdi").resolve()
        for yol, bilgi in zip(yollar, girdiler, strict=True):
            gercek = yol.resolve()
            try:
                gercek.relative_to(girdi_koku)
            except ValueError as exc:
                raise KesVeCozHatasi("Is kaydinda guvensiz girdi yolu var.") from exc
            if not gercek.is_file():
                raise KesVeCozHatasi(
                    "Yuklenen belge bulunamadi; is yeniden baslatilamiyor."
                )
            try:
                beklenen_boyut = int(bilgi["boyut"])
                beklenen_imza = str(bilgi["sha256"])
            except (KeyError, TypeError, ValueError) as exc:
                raise KesVeCozHatasi("Isin girdi butunluk kaydi bozuk.") from exc
            if gercek.stat().st_size != beklenen_boyut or _dosya_sha256(
                gercek
            ) != beklenen_imza:
                raise KesVeCozHatasi(
                    "Yuklenen belge islem oncesinde degismis veya bozulmus."
                )

        self.depo.is_guncelle(
            is_id,
            durum="çalışıyor",
            asama="kesim",
            ilerleme=5,
            mesaj="Sayfalar bulunuyor ve sorular kesiliyor.",
        )
        komut, calisma_dizini = self._komut_kurucu(yollar, arsiv)
        if not komut:
            raise KesVeCozHatasi("Soru Kesici komutu bos.")
        log_yolu = self._is_dizini(is_id) / "soru-kesici.log"
        with log_yolu.open("ab") as log:
            log_konumu = log.tell()
            surec = subprocess.Popen(  # noqa: S603 - kabuk yok, sabit kurucu
                komut,
                cwd=str(calisma_dizini),
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            with self._kilit:
                self._surecler[is_id] = surec
            while surec.poll() is None:
                log_konumu = self._paketleme_ilerlemesini_oku(
                    is_id, log_yolu, log_konumu
                )
                if self._kapandi or self.depo.durdur_istendi_mi(is_id):
                    _surec_grubuna_sinyal(surec, signal.SIGTERM)
                    if not _surec_grubunun_bitmesini_bekle(surec, 5.0):
                        _surec_grubuna_sinyal(surec, signal.SIGKILL)
                    with suppress(subprocess.TimeoutExpired):
                        surec.wait(timeout=1)
                    if self._kapandi:
                        raise KesVeCozHatasi("Uygulama kapanirken is duraklatildi.")
                    raise KesVeCozHatasi("Is kullanici tarafindan durduruldu.")
                # Event kullanmak, uzun ``sleep`` ile iptal gecikmesini onler.
                self._bekleme.wait(0.1)
            self._paketleme_ilerlemesini_oku(is_id, log_yolu, log_konumu)
            kod = int(surec.returncode or 0)
        with self._kilit:
            self._surecler.pop(is_id, None)
        if kod != 0:
            raise KesVeCozHatasi(
                f"Soru Kesici tamamlanamadi (cikis kodu {kod}). Ayrinti is gunlugunde."
            )
        if not arsiv.is_file() or arsiv.stat().st_size == 0:
            raise KesVeCozHatasi("Soru Kesici cikti paketi olusturmadi.")

    def _paketleme_ilerlemesini_oku(
        self, is_id: str, log_yolu: Path, konum: int
    ) -> int:
        """Bas-siz kesicinin JSONL olaylarini guvenli ilerlemeye cevirir."""
        try:
            with log_yolu.open("rb") as kaynak:
                kaynak.seek(konum)
                yeni = kaynak.read()
        except OSError:
            return konum
        son_satir = yeni.rfind(b"\n")
        if son_satir < 0:
            return konum
        tamam = yeni[: son_satir + 1]
        yeni_konum = konum + len(tamam)
        for ham in tamam.splitlines():
            try:
                olay = json.loads(ham.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(olay, dict):
                continue
            tur = str(olay.get("event") or "")
            if tur == "started":
                self.depo.is_guncelle(
                    is_id, ilerleme=6, mesaj="Belge Soru Kesici ile aciliyor."
                )
            elif tur == "document_ready":
                sayfa = _sinirli_tamsayi(olay.get("pages"), AZAMI_SORU)
                self.depo.is_guncelle(
                    is_id,
                    ilerleme=8,
                    mesaj=f"{sayfa} sayfa hazirlandi; soru sinirlari bulunuyor.",
                )
            elif tur == "cut_progress":
                simdiki = _sinirli_tamsayi(olay.get("current"), AZAMI_SORU)
                toplam = max(1, _sinirli_tamsayi(olay.get("total"), AZAMI_SORU))
                oran = min(1.0, simdiki / toplam)
                kova = "inceleme" if olay.get("bucket") == "review" else "otomatik"
                kayit = self.depo.is_getir(is_id) or {}
                ilerleme = max(
                    int(kayit.get("ilerleme") or 0), 8 + round(5 * oran)
                )
                self.depo.is_guncelle(
                    is_id,
                    ilerleme=ilerleme,
                    mesaj=f"{kova.capitalize()} kesimler: {simdiki}/{toplam}.",
                )
            elif tur == "package_progress":
                simdiki = _sinirli_tamsayi(olay.get("current"), AZAMI_SORU)
                toplam = max(1, _sinirli_tamsayi(olay.get("total"), AZAMI_SORU))
                self.depo.is_guncelle(
                    is_id,
                    ilerleme=14 + round(3 * min(1.0, simdiki / toplam)),
                    mesaj=f"Kesilen sorular paketleniyor: {simdiki}/{toplam}.",
                )
            elif tur == "completed":
                self.depo.is_guncelle(
                    is_id, ilerleme=18, mesaj="Soru paketi hazir; dogrulaniyor."
                )
        return yeni_konum

    def _sorulari_coz(self, is_id: str, sorular: list[PaketSorusu]) -> None:
        cozucu = self._cozucu_fabrikasi()
        ayarlar = getattr(cozucu, "ayarlar", None)
        normal_deneme = max(1, int(getattr(ayarlar, "deneme_sayisi", 1) or 1))
        normal_onbellek = bool(getattr(ayarlar, "onbellek_aktif", True))
        normal_sicaklik = float(getattr(ayarlar, "sicaklik", 0.0) or 0.0)
        ham_yeniden_sicaklik = getattr(
            ayarlar, "deneme_sicakligi", normal_sicaklik
        )
        yeniden_sicaklik = float(
            normal_sicaklik
            if ham_yeniden_sicaklik is None
            else ham_yeniden_sicaklik
        )

        def deneme_sayisini_ayarla(deger: int) -> None:
            if ayarlar is not None and hasattr(ayarlar, "deneme_sayisi"):
                ayarlar.deneme_sayisi = max(1, int(deger))

        def gecici_ayarlari_geri_al() -> None:
            deneme_sayisini_ayarla(normal_deneme)
            if ayarlar is not None and hasattr(ayarlar, "onbellek_aktif"):
                ayarlar.onbellek_aktif = normal_onbellek
            if ayarlar is not None and hasattr(ayarlar, "sicaklik"):
                ayarlar.sicaklik = normal_sicaklik

        toplam = len(sorular)
        for soru in sorular:
            if self._kapandi:
                self._duraklat(is_id)
                return
            mevcut = self.depo.soru_durumu(is_id, soru.sira)
            if mevcut in SORU_TERMINAL:
                continue
            if self.depo.durdur_istendi_mi(is_id):
                self._durduruldu(is_id)
                return
            self.depo.soru_guncelle(is_id, soru.sira, durum="çözülüyor", hata="")
            try:
                # Cevap anahtarlı kitaplarda önce hızlı, bağımsız tek geçiş
                # yap. Yalnız uyuşmazlık çıkarsa normal oylamaya yükselt;
                # anahtarın değeri hiçbir model çağrısına girmez.
                deneme_sayisini_ayarla(1 if soru.referans_cevap else normal_deneme)
                gorsel_imzasi = ""
                if (
                    soru.gorsel_yolu is not None
                    and _model_gorseli_gerekli_mi(soru)
                ):
                    gorsel_imzasi = GorselDeposu(self.kok).yaz(
                        soru.gorsel_yolu.read_bytes()
                    )
                # Guvenlik siniri: ``referans_cevap`` ve provenance bu cagriya
                # hicbir sekilde girmez. Model yalniz soru, siklar ve kirpimi gorur.
                cozum: Cozum = cozucu.coz(
                    soru.metin,
                    secenekler=soru.secenekler or None,
                    gorsel=gorsel_imzasi,
                    # Kesim kalitesi ve resmi cevap karsilastirmasi ancak model
                    # dondukten sonra uygulanabilir. Erken kayit, ana Cozumler
                    # ekraninda riskli soruyu yanlislikla guvenli gosterirdi.
                    kaydet=False,
                    # Kesme guveni cozum guvenine tavan olur. Kuyruk zaten dusuk
                    # kaliteli soruyu `inceleme_gerekli` ile isaretliyordu ama
                    # cozumun GUVEN sayisi el degmeden yuksek kaliyordu; ayni
                    # soru CLI'dan gecince sinirlanip buradan gecince
                    # sinirlanmamasi tutarsizdi.
                    kaynak_guveni=soru.guven,
                )
                ilk_cozum = cozum
                ilk_eslesme = None
                if soru.referans_cevap:
                    ilk_eslesme = cevap_eslesiyor(
                        cozum.cevap, soru.referans_cevap, soru=soru.metin
                    )
                cozum.dogrulama = {
                    **cozum.dogrulama,
                    "referans_var": bool(soru.referans_cevap),
                    "ilk_cevap": cozum.cevap,
                    "ilk_eslesme": ilk_eslesme,
                    "hedef_deneme": 1 if soru.referans_cevap else normal_deneme,
                    "tamamlanan_deneme": 1,
                    "yeniden_denendi": False,
                    "son_yontem": cozum.uretim_yontemi,
                }
                yeniden_denenebilir = cozum.uretim_yontemi in {
                    "model",
                    "kurtarma",
                    "onbellek",
                    # Sema bozulup metinden toplanan ve nihai cevap yerine on
                    # cevabin kullanildigi yollar da yeniden denenebilir:
                    # ikisi de modelin URETIM kazasi, deterministik bir arac
                    # sonucu degil.
                    "bicimsiz",
                    "on_cevap",
                }
                if (
                    ilk_eslesme is False
                    and normal_deneme > 1
                    and yeniden_denenebilir
                    and not self._kapandi
                    and not self.depo.durdur_istendi_mi(is_id)
                ):
                    adaylar = [ilk_cozum]
                    deneme_sayisini_ayarla(1)
                    if ayarlar is not None and hasattr(ayarlar, "onbellek_aktif"):
                        ayarlar.onbellek_aktif = False
                    if ayarlar is not None and hasattr(ayarlar, "sicaklik"):
                        ayarlar.sicaklik = yeniden_sicaklik
                    retry_hatalari = 0
                    for _sira in range(1, normal_deneme):
                        if self._kapandi or self.depo.durdur_istendi_mi(is_id):
                            break
                        try:
                            adaylar.append(
                                cozucu.coz(
                                    soru.metin,
                                    secenekler=soru.secenekler or None,
                                    gorsel=gorsel_imzasi,
                                    kaydet=False,
                                    # Tavan burada da verilmeli: oylama
                                    # kazanan kume icinden EN YUKSEK guvenli
                                    # adayi temsilci seciyor ve `cozumleri_oyla`
                                    # `_oz_kontrol`den gecmiyor. Tavansiz bir
                                    # retry adayi secilirse kesme guveni
                                    # sinirlamasi tumden delinir.
                                    kaynak_guveni=soru.guven,
                                )
                            )
                        except Exception:  # noqa: BLE001 - ilk çözüm korunur
                            retry_hatalari += 1
                    if len(adaylar) > 1:
                        oylayici = getattr(cozucu, "cozumleri_oyla", None)
                        cozum = (
                            oylayici(soru.metin, adaylar)
                            if callable(oylayici)
                            else adaylar[0]
                        )
                    else:
                        cozum = ilk_cozum
                    cozum.dogrulama = {
                        **cozum.dogrulama,
                        "referans_var": True,
                        "ilk_cevap": ilk_cozum.cevap,
                        "ilk_eslesme": False,
                        "hedef_deneme": normal_deneme,
                        "tamamlanan_deneme": len(adaylar),
                        "yeniden_denendi": len(adaylar) > 1,
                        "retry_hatasi": retry_hatalari,
                        "son_yontem": cozum.uretim_yontemi,
                    }
                    if len(adaylar) > 1:
                        cozum.uyarilar.append(
                            "İlk bağımsız çözüm cevap anahtarıyla uyuşmadı; anahtar "
                            f"modele verilmeden {len(adaylar)}/{normal_deneme} "
                            "bağımsız çözüm tamamlandı ve oylandı."
                        )
                    else:
                        cozum.uyarilar.append(
                            "Yeniden denemeler tamamlanamadı; ilk bağımsız çözüm "
                            "korundu ve incelemeye ayrıldı."
                        )
                elif ilk_eslesme is False and normal_deneme > 1:
                    neden = (
                        "işlem durdurulduğu için"
                        if self._kapandi or self.depo.durdur_istendi_mi(is_id)
                        else f"{cozum.uretim_yontemi} yöntemi deterministik olduğu için"
                    )
                    cozum.dogrulama["yeniden_deneme_atlandi"] = neden
                    cozum.uyarilar.append(
                        f"Cevap anahtarı uyuşmazlığı sonrası yeniden deneme {neden} atlandı."
                    )
                for uyari in soru.uyarilar:
                    if uyari not in cozum.uyarilar:
                        cozum.uyarilar.append(uyari)
                if soru.inceleme_gerekli:
                    cozum.incele = True
                    uyari = "Kesim kalite kapisi bu soruyu incelemeye ayirdi."
                    if uyari not in cozum.uyarilar:
                        cozum.uyarilar.append(uyari)

                eslesme: int | None = None
                if soru.referans_cevap:
                    eslesme = int(
                        cevap_eslesiyor(
                            cozum.cevap, soru.referans_cevap, soru=soru.metin
                        )
                    )
                    if not eslesme:
                        cozum.incele = True
                        uyari = (
                            "Uretilen cevap kaynak cevap anahtariyla uyusmuyor; "
                            "ogretmen incelemesi gerekli."
                        )
                        if uyari not in cozum.uyarilar:
                            cozum.uyarilar.append(uyari)
                ana_depo = getattr(cozucu, "depo", None)
                if ana_depo is not None and hasattr(ana_depo, "cozum_kaydet"):
                    cozum.id = int(
                        ana_depo.cozum_kaydet(
                            cozum,
                            kaynak_kimligi=f"kes-ve-coz:{is_id}:{soru.sira}",
                        )
                    )
                soru_durumu = "inceleme" if cozum.incele else "tamamlandı"
                self.depo.soru_guncelle(
                    is_id,
                    soru.sira,
                    durum=soru_durumu,
                    referans_eslesmesi=eslesme,
                    cozum_json=json.dumps(cozum.sozluk(), ensure_ascii=False),
                    hata="",
                )
            except Exception as exc:  # noqa: BLE001 - tek soru isi dusurmez
                if self._kapandi:
                    self.depo.soru_guncelle(
                        is_id, soru.sira, durum="bekliyor", hata=""
                    )
                    self._duraklat(is_id)
                    return
                self.depo.soru_guncelle(
                    is_id,
                    soru.sira,
                    durum="hata",
                    hata=f"Cozum uretilemedi: {exc}",
                )
            finally:
                gecici_ayarlari_geri_al()
            self._sayaclari_guncelle(is_id, toplam)
            if self._kapandi:
                self._duraklat(is_id)
                return
            if self.depo.durdur_istendi_mi(is_id):
                self._durduruldu(is_id)
                return

        sayac = self.depo.soru_sayaclari(is_id)
        hata = sayac["hata"]
        cozulmus = sayac["cozulmus"]
        inceleme = sayac["inceleme"]
        if hata:
            durum = "kısmi" if cozulmus else "hata"
            mesaj = f"{cozulmus} soru cozuldu; {hata} soruda hata olustu."
        else:
            durum = "tamamlandı"
            mesaj = f"{cozulmus} sorunun kesim ve cozumu tamamlandi."
        self.depo.is_guncelle(
            is_id,
            durum=durum,
            asama="bitti",
            ilerleme=100,
            mesaj=mesaj,
            toplam=toplam,
            kesilen=toplam,
            cozulen=cozulmus,
            inceleme=inceleme,
            hata_sayisi=hata,
        )

    def _sayaclari_guncelle(self, is_id: str, toplam: int) -> None:
        sayac = self.depo.soru_sayaclari(is_id)
        cozulmus = sayac["cozulmus"]
        inceleme = sayac["inceleme"]
        hata = sayac["hata"]
        biten = cozulmus + hata + sayac["atlanmis"]
        ilerleme = 20 + round(80 * biten / max(1, toplam))
        self.depo.is_guncelle(
            is_id,
            durum="çalışıyor",
            asama="cozum",
            ilerleme=min(99, ilerleme),
            mesaj=f"{cozulmus}/{toplam} soru cozuldu.",
            toplam=toplam,
            kesilen=toplam,
            cozulen=cozulmus,
            inceleme=inceleme,
            hata_sayisi=hata,
        )

    def _durduruldu(self, is_id: str) -> None:
        self.depo.bekleyenleri_atla(is_id)
        sayac = self.depo.soru_sayaclari(is_id)
        self.depo.is_guncelle(
            is_id,
            durum="durduruldu",
            asama="bitti",
            mesaj="Is durduruldu; tamamlanmayan sorular atlanmis olarak isaretlendi.",
            cozulen=sayac["cozulmus"],
            inceleme=sayac["inceleme"],
            hata_sayisi=sayac["hata"],
        )

    def _duraklat(self, is_id: str) -> None:
        """Uygulama kapanirken isi terminal hataya cevirmeden kurtarilabilir tutar."""
        kayit = self.depo.is_getir(is_id)
        if kayit is None or kayit["durum"] in IS_TERMINAL:
            return
        self.depo.is_guncelle(
            is_id,
            durum="bekliyor",
            asama="kurtarma",
            mesaj="Uygulama yeniden basladiginda is kaldigi yerden surdurulecek.",
        )

    def _hata_ile_bitir(self, is_id: str, exc: Exception) -> None:
        mesaj = str(exc).strip() or type(exc).__name__
        self.depo.fatal_sorulari_bitir(is_id, mesaj)
        sayac = self.depo.soru_sayaclari(is_id)
        cozulmus = sayac["cozulmus"]
        hata_sayisi = sayac["hata"]
        durum = "kısmi" if cozulmus else "hata"
        self.depo.is_guncelle(
            is_id,
            durum=durum,
            asama="bitti",
            mesaj=mesaj,
            hata=mesaj,
            cozulen=cozulmus,
            inceleme=sayac["inceleme"],
            hata_sayisi=max(1, hata_sayisi),
        )

    def durum(self, is_id: str, *, sorular_dahil: bool = True) -> dict[str, Any]:
        kayit = self.depo.is_getir(is_id)
        if kayit is None:
            raise KeyError(is_id)
        sonuc = {
            "id": is_id,
            "is_id": is_id,
            "durum": kayit["durum"],
            "status": kayit["durum"],
            "asama": kayit["asama"],
            "ilerleme": int(kayit["ilerleme"]),
            "mesaj": kayit["mesaj"],
            "toplam": int(kayit["toplam"]),
            "kesilen": int(kayit["kesilen"]),
            "cozulen": int(kayit["cozulen"]),
            "inceleme": int(kayit["inceleme"]),
            "hata_sayisi": int(kayit["hata_sayisi"]),
            "olusturma": kayit["olusturma"],
            "guncelleme": kayit["guncelleme"],
        }
        sonuc["sorular"] = self._sorular_json(is_id) if sorular_dahil else []
        return sonuc

    def _sorular_json(self, is_id: str) -> list[dict[str, Any]]:
        sonuclar: list[dict[str, Any]] = []
        for satir in self.depo.sorular(is_id):
            try:
                secenekler = json.loads(satir["secenekler_json"] or "{}")
                provenance = json.loads(satir["provenance_json"] or "{}")
                cozum = json.loads(satir["cozum_json"]) if satir["cozum_json"] else None
            except json.JSONDecodeError:
                secenekler, provenance, cozum = {}, {}, None
            if isinstance(cozum, dict):
                # Ham model yaniti (ve varsa dusunce etiketi) arayuz API'sine
                # ait degildir; denetim icin yerel kayitta kalir.
                cozum.pop("ham_yanit", None)
            cozum_uyarilari = cozum.get("uyarilar", []) if isinstance(cozum, dict) else []
            uyarilar = list(
                dict.fromkeys([*provenance.get("warnings", []), *cozum_uyarilari])
            )
            imzasiz_eski_cozum = bool(
                isinstance(cozum, dict)
                and not str(satir["cozum_girdisi_imzasi"] or "")
            )
            if imzasiz_eski_cozum:
                uyarilar.append(
                    "Bu eski iş kaydında doğrulanmış çözüm girdisi imzası yok; "
                    "sonucu kullanmadan önce yeniden işleyin."
                )
            inceleme = bool(satir["inceleme_gerekli"]) or satir[
                "durum"
            ] == "inceleme" or bool(
                isinstance(cozum, dict) and cozum.get("incele")
            ) or imzasiz_eski_cozum
            sonuclar.append(
                {
                    "id": satir["external_id"],
                    "sira": int(satir["sira"]),
                    "durum": satir["durum"],
                    "status": satir["durum"],
                    "soru": satir["soru"],
                    "secenekler": secenekler,
                    "provenance": provenance,
                    "kaynak": provenance.get("source_document", ""),
                    "sayfa": provenance.get("source_page"),
                    "kesim_guveni": provenance.get("confidence", 0),
                    "review_required": bool(satir["inceleme_gerekli"]),
                    "incele": inceleme,
                    "inceleme_gerekli": inceleme,
                    "uyarilar": uyarilar,
                    "guven": cozum.get("guven") if isinstance(cozum, dict) else None,
                    # Anahtarın kendisini açmadan arayüzün kaç sorunun gerçekten
                    # denetlenebilir olduğunu göstermesine izin ver.
                    "referans_var": bool(str(satir["referans_cevap"] or "").strip()),
                    "referansla_eslesiyor": (
                        None
                        if satir["referans_eslesmesi"] is None
                        else bool(satir["referans_eslesmesi"])
                    ),
                    # Model bitmeden cevap anahtari istemciye verilmez. Model
                    # anahtarla celistiyse ise kullaniciyi yanlis model cevabiyla
                    # bas basa birakma: kaynak belgedeki harfi ayri ve acikca
                    # etiketlenmis bir alan olarak goster. Bu deger model
                    # cagrilarina hicbir zaman girmez; kör basari bayragi da
                    # degistirilmez.
                    "kaynak_anahtar_cevabi": (
                        str(satir["referans_cevap"] or "").strip()
                        if satir["referans_eslesmesi"] == 0
                        else ""
                    ),
                    "cozum": cozum,
                    "hata": satir["hata"],
                    "gorsel_url": (
                        f"/kes-ve-coz/api/is/{is_id}/soru/{satir['sira']}/gorsel"
                        if satir["gorsel_yolu"]
                        else ""
                    ),
                }
            )
        return sonuclar

    def soru_gorseli(self, is_id: str, sira: int) -> Path | None:
        satir = self.depo.soru_getir(is_id, sira)
        if satir is None or not satir["gorsel_yolu"]:
            return None
        yol = Path(str(satir["gorsel_yolu"])).resolve()
        paket = (self._is_dizini(is_id) / "paket").resolve()
        try:
            yol.relative_to(paket)
        except ValueError:
            return None
        return yol if yol.is_file() else None


def _guvenli_zip_ac(arsiv: Path, hedef: Path) -> None:
    """Zip-slip, sembolik bag, uye sayisi ve acilmis boyut korumali acma."""
    hedef = hedef.resolve()
    toplam = 0
    gorulen: set[str] = set()
    try:
        paket = zipfile.ZipFile(arsiv)
    except (OSError, zipfile.BadZipFile) as exc:
        raise KesVeCozHatasi("Soru paketi gecerli bir ZIP degil.") from exc
    with paket:
        uyeler = paket.infolist()
        if len(uyeler) > AZAMI_ARSIV_UYESI:
            raise KesVeCozHatasi("Soru paketinde guvenli sinirdan fazla dosya var.")
        for uye in uyeler:
            ham = uye.filename.replace("\\", "/")
            if "\x00" in ham:
                raise KesVeCozHatasi("Soru paketinde gecersiz dosya adi var.")
            bagil = PurePosixPath(ham)
            if bagil.is_absolute() or any(p in {"", ".", ".."} for p in bagil.parts):
                raise KesVeCozHatasi(f"Soru paketinde guvensiz yol: {uye.filename}")
            kip = (uye.external_attr >> 16) & 0o170000
            if kip == stat.S_IFLNK:
                raise KesVeCozHatasi("Soru paketinde sembolik bag kabul edilmez.")
            anahtar = bagil.as_posix().casefold()
            if anahtar in gorulen:
                raise KesVeCozHatasi("Soru paketinde cakisacak dosya adlari var.")
            gorulen.add(anahtar)
            toplam += int(uye.file_size)
            if toplam > AZAMI_ACILMIS_BAYT:
                raise KesVeCozHatasi("Soru paketi acilinca 2 GB sinirini asiyor.")
            varis = hedef.joinpath(*bagil.parts).resolve()
            try:
                varis.relative_to(hedef)
            except ValueError as exc:
                raise KesVeCozHatasi(
                    f"Soru paketinde guvensiz yol: {uye.filename}"
                ) from exc
            if uye.is_dir():
                varis.mkdir(parents=True, exist_ok=True)
                continue
            varis.parent.mkdir(parents=True, exist_ok=True)
            with paket.open(uye) as kaynak, varis.open("xb") as cikti:
                shutil.copyfileobj(kaynak, cikti, length=AKIS_PARCA_BAYT)


def _yuklenen_arsivi_dogrula(yol: Path) -> None:
    """Kullanicinin yukledigi zip gercekten bir Soru Kesici paketi mi bakar.

    Amac hizli ve kesin geri bildirim: alakasiz bir zip (fotograf klasoru,
    indirilmis bir kaynak paketi) is kuyruguna girip dakikalar sonra anlamsiz
    bir hatayla dusmesin. Yalnizca merkezi dizin okunur, icerik acilmaz.
    """
    try:
        with zipfile.ZipFile(yol) as paket:
            adlar = paket.namelist()
    except (OSError, zipfile.BadZipFile) as exc:
        raise KesVeCozHatasi(
            "Yuklenen dosya gecerli bir zip arsivi degil."
        ) from exc
    if len(adlar) > AZAMI_ARSIV_UYESI:
        raise KesVeCozHatasi(
            f"Arsivde {len(adlar)} dosya var; guvenlik siniri {AZAMI_ARSIV_UYESI}."
        )
    kunye_adlari = {*PAKET_KUNYE_ADLARI, "sorular.json"}
    for ad in adlar:
        if PurePosixPath(ad).name in kunye_adlari:
            return
    raise KesVeCozHatasi(
        "Bu zip bir Soru Kesici paketi degil: icinde kunye dosyasi "
        "(kes-ve-coz-manifest.json veya sorular.json) bulunamadi."
    )


def _json_oku(yol: Path) -> Any:
    try:
        if yol.stat().st_size > AZAMI_MANIFEST_BAYT:
            raise KesVeCozHatasi("Paket kunyesi 64 MB guvenlik sinirini asiyor.")
        return json.loads(yol.read_text(encoding="utf-8"))
    except KesVeCozHatasi:
        raise
    except (OSError, json.JSONDecodeError) as exc:
        raise KesVeCozHatasi(f"Paket kunyesi okunamadi: {yol.name}") from exc


def _manifest_bul(kok: Path) -> Path | None:
    bulunan: list[Path] = []
    for ad in PAKET_KUNYE_ADLARI:
        bulunan.extend(kok.rglob(ad))
    surumlu = []
    for yol in sorted(set(bulunan), key=lambda p: (len(p.parts), str(p))):
        veri = _json_oku(yol)
        if isinstance(veri, dict) and veri.get("schema_version") == PAKET_SURUMU:
            surumlu.append(yol)
    if len(surumlu) > 1:
        raise KesVeCozHatasi("Pakette birden fazla v1 manifest bulundu.")
    return surumlu[0] if surumlu else None


def _paket_sorularini_oku(kok: Path) -> list[PaketSorusu]:
    manifest = _manifest_bul(kok)
    if manifest is not None:
        veri = _json_oku(manifest)
        return _v1_sorularini_dogrula(veri, manifest.parent)
    # Gecis donemi: eski Soru Kesici ``sorular.json`` paketleri de kayipsiz
    # okunur ve hemen ic manifest v1'e normalize edilir.
    return _legacy_sorularini_dogrula(kok)


def _siklari_dogrula(ham: Any) -> dict[str, str]:
    if not isinstance(ham, dict):
        return {}
    sonuc: dict[str, str] = {}
    for harf, metin in ham.items():
        h = str(harf).strip().upper()
        m = str(metin).strip()
        if h and len(h) <= 4 and m:
            sonuc[h] = m[:10_000]
    return sonuc


def _referansi_dogrula(ham: Any, secenekler: dict[str, str]) -> tuple[str, bool]:
    """Anahtarı modele açmadan A-E harfine indirger ve OCR boşluğunu işaretler."""
    referans = str(ham or "").strip()[:1000]
    if not referans:
        return "", False
    harf = referans.upper()
    if len(harf) != 1 or harf not in "ABCDE":
        return "", True
    if secenekler and harf not in secenekler:
        # Grafik, tablo ve soyağacı sorularında OCR yalnız bazı şık harflerini
        # çıkarabilir. Resmî A-E anahtarını kaybetme; fakat kırpımı insan
        # incelemesine ayırarak eksik şık çıkarımını görünür kıl.
        return harf, True
    return harf, False


def _kanonik_paket_uyarilari(ham: Any) -> list[str]:
    if not isinstance(ham, list):
        return []
    return sorted(
        {
            str(uyari).strip()[:1000]
            for uyari in ham
            if str(uyari).strip()
        }
    )


def _cozum_girdisi_imzalari(soru: PaketSorusu) -> tuple[str, str]:
    """V2 kimligiyle uyari-oncesi V1 gecis kimligini tek dosya okumasinda uret."""
    gorsel_imzasi = ""
    if soru.gorsel_yolu is not None:
        try:
            gorsel_imzasi = _dosya_sha256(soru.gorsel_yolu)
        except OSError:
            # Okunamayan bir gorseli sabit yol kimligiyle "ayni" saymak eski
            # terminal cozumu fail-open korurdu. Her denemeyi supheli/yeni girdi
            # say; dogrulanmis paket akisi daha sonra dosya okumasinda guvenle
            # hata verir, dogrudan depo kullanan kurtarma araclari ise yeniden
            # cozum durumuna doner.
            gorsel_imzasi = f"okunamadi:{uuid.uuid4().hex}"
    temel = {
        "external_id": soru.external_id,
        "soru": soru.metin,
        "secenekler": soru.secenekler,
        "gorsel_sha256": gorsel_imzasi,
        "referans_cevap": soru.referans_cevap,
        "inceleme_gerekli": soru.inceleme_gerekli,
        "kalite_durumu": soru.kalite_durumu,
    }
    eski_ham = json.dumps(
        temel,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    yeni_ham = json.dumps(
        {
            **temel,
            "fingerprint_version": 2,
            "paket_uyarilari": _kanonik_paket_uyarilari(soru.uyarilar),
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return (
        f"v2:{hashlib.sha256(yeni_ham).hexdigest()}",
        hashlib.sha256(eski_ham).hexdigest(),
    )


def _cozum_girdisi_imzasi(soru: PaketSorusu) -> str:
    """Eski bir terminal çözümün yalnız aynı kör girdide yeniden kullanım kimliği."""
    return _cozum_girdisi_imzalari(soru)[0]


def _liste(ham: Any) -> list[str]:
    if not isinstance(ham, list):
        return []
    return [str(x).strip()[:1000] for x in ham if str(x).strip()]


def _guven(ham: Any) -> float:
    try:
        deger = float(ham)
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, min(1.0, deger)) if math.isfinite(deger) else 0.0


def _sayfa(ham: Any) -> int | None:
    if isinstance(ham, bool):
        return None
    try:
        deger = int(ham)
    except (TypeError, ValueError):
        return None
    return deger if deger > 0 else None


def _kutu(ham: Any) -> list[float]:
    if not isinstance(ham, (list, tuple)) or len(ham) != 4:
        return []
    try:
        degerler = [float(x) for x in ham]
    except (TypeError, ValueError):
        return []
    return degerler if all(abs(x) < 1_000_000 for x in degerler) else []


def _gorsel_yolu(kok: Path, ham: Any) -> Path | None:
    ad = str(ham or "").strip().replace("\\", "/")
    if not ad:
        return None
    bagil = PurePosixPath(ad)
    if bagil.is_absolute() or any(p in {"", ".", ".."} for p in bagil.parts):
        raise KesVeCozHatasi(f"Manifestte guvensiz gorsel yolu: {ad}")
    yol = kok.joinpath(*bagil.parts).resolve()
    try:
        yol.relative_to(kok.resolve())
    except ValueError as exc:
        raise KesVeCozHatasi(f"Manifestte guvensiz gorsel yolu: {ad}") from exc
    if yol.suffix.casefold() not in GORSEL_UZANTILARI or not yol.is_file():
        raise KesVeCozHatasi(f"Manifestteki soru gorseli bulunamadi: {ad}")
    if yol.stat().st_size > AZAMI_GORSEL_MB * 1024 * 1024:
        raise KesVeCozHatasi(
            f"Manifestteki soru gorseli {AZAMI_GORSEL_MB} MB sinirini asiyor: {ad}"
        )
    return yol


def _legacy_gorsel_yolu(paket_koku: Path, kunye: Path, ham: Any) -> Path | None:
    """Eski ``Incele/sorular.json`` tam ya da yerel dosya yolu yazabiliyor."""
    ad = str(ham or "").strip().replace("\\", "/")
    if not ad:
        return None
    for kok in (kunye.parent, paket_koku):
        try:
            yol = _gorsel_yolu(kok, ad)
        except KesVeCozHatasi:
            continue
        if yol is not None:
            return yol
    raise KesVeCozHatasi(f"Manifestteki soru gorseli bulunamadi: {ad}")


def _v1_sorularini_dogrula(veri: Any, kok: Path) -> list[PaketSorusu]:
    if not isinstance(veri, dict) or veri.get("schema_version") != PAKET_SURUMU:
        raise KesVeCozHatasi("Desteklenmeyen Soru Kesici paket surumu.")
    if str(veri.get("source_app") or "").strip().casefold() != "soru kesici":
        raise KesVeCozHatasi("V1 paket guvenilir Soru Kesici kaynagini belirtmiyor.")
    cevap_politikasi = veri.get("answer_policy")
    modelden_saklanan = (
        cevap_politikasi.get("withheld_from_model")
        if isinstance(cevap_politikasi, dict)
        else None
    )
    if not isinstance(modelden_saklanan, list) or "reference_answer" not in {
        str(alan).strip() for alan in modelden_saklanan
    }:
        raise KesVeCozHatasi(
            "V1 paket cevap anahtarini modelden saklama sozlesmesini belirtmiyor."
        )
    kayitlar = veri.get("questions")
    if not isinstance(kayitlar, list):
        raise KesVeCozHatasi("V1 manifestte questions listesi yok.")
    if len(kayitlar) > AZAMI_SORU:
        raise KesVeCozHatasi("Pakette guvenli sinirdan fazla soru var.")
    kaynak_surumu = str(veri.get("source_version") or "").strip()
    gorulen: set[str] = set()
    sonuclar: list[PaketSorusu] = []
    for sira, kayit in enumerate(kayitlar, 1):
        if not isinstance(kayit, dict):
            raise KesVeCozHatasi(f"Manifestte {sira}. soru bir nesne degil.")
        external_id = str(
            kayit.get("external_id") or f"soru-{sira:05d}"
        ).strip()[:200]
        if (
            not external_id
            or external_id in gorulen
            or any(c in external_id for c in "/\\\r\n\x00")
            or external_id in {".", ".."}
        ):
            raise KesVeCozHatasi("Manifestte bos veya yinelenen soru kimligi var.")
        gorulen.add(external_id)
        metin = str(kayit.get("text") or "").strip()[:50_000]
        secenekler = _siklari_dogrula(kayit.get("choices"))
        referans, referans_gecersiz = _referansi_dogrula(
            kayit.get("reference_answer"), secenekler
        )
        ham_gorsel = str(kayit.get("image") or "").strip().replace("\\", "/")
        if ham_gorsel and ham_gorsel != f"images/{external_id}.png":
            raise KesVeCozHatasi(
                f"Manifestte guvensiz veya soru kimligiyle uyusmayan gorsel: "
                f"{ham_gorsel}"
            )
        gorsel = _gorsel_yolu(kok, ham_gorsel)
        if not metin:
            if gorsel is None:
                raise KesVeCozHatasi(f"{external_id}: soru metni ve gorseli bos.")
            metin = (
                "Gorseldeki biyoloji sorusunu ve varsa siklari okuyup coz. "
                "Sekil, grafik ve tablodaki bilgileri de kullan."
            )
        kalite = str(kayit.get("quality_status") or "automatic").strip().casefold()
        if kalite not in {"automatic", "review"}:
            kalite = "review"
        inceleme = (
            bool(kayit.get("review_required"))
            or kalite == "review"
            or referans_gecersiz
        )
        uyarilar = _liste(kayit.get("warnings"))
        if referans_gecersiz:
            uyarilar.append(
                "Cevap anahtarı harfi çıkarılan şıklarda görünmüyor; görsel ve "
                "kaynak anahtar üzerinden karşılaştırıldı."
                if referans
                else "Cevap anahtarı şıklarla uyumlu değil; otomatik "
                "karşılaştırma yapılmadı."
            )
        parcalar = kayit.get("source_parts")
        sonuclar.append(
            PaketSorusu(
                external_id=external_id,
                sira=sira,
                metin=metin,
                secenekler=secenekler,
                gorsel_yolu=gorsel,
                kaynak_belge=str(kayit.get("source_document") or "").strip()[:1000],
                kaynak_sayfa=_sayfa(kayit.get("source_page")),
                kaynak_kutu=_kutu(kayit.get("source_box")),
                kesici_surumu=str(
                    kayit.get("cutter_version") or kaynak_surumu
                ).strip()[:100],
                guven=_guven(kayit.get("confidence")),
                kalite_durumu=kalite,
                inceleme_gerekli=inceleme,
                uyarilar=uyarilar,
                referans_cevap=referans,
                kaynak_parcalar=(
                    [dict(p) for p in parcalar if isinstance(p, dict)]
                    if isinstance(parcalar, list)
                    else []
                ),
            )
        )
    return sonuclar


def _legacy_sorularini_dogrula(kok: Path) -> list[PaketSorusu]:
    kunyeler = sorted(
        kok.rglob("sorular.json"), key=lambda p: (len(p.relative_to(kok).parts), str(p))
    )
    if not kunyeler:
        raise KesVeCozHatasi(
            "Pakette v1 manifest veya eski sorular.json bulunamadi."
        )
    sonuclar: list[PaketSorusu] = []
    gorulen: set[str] = set()
    for kunye in kunyeler:
        kayitlar = _json_oku(kunye)
        if not isinstance(kayitlar, list):
            continue
        inceleme_klasoru = "ncele" in kunye.parent.name.casefold()
        for kayit in kayitlar:
            if not isinstance(kayit, dict):
                continue
            sira = len(sonuclar) + 1
            kimlik = str(
                kayit.get("_kimlik")
                or kayit.get("external_id")
                or f"legacy-{sira:05d}"
            ).strip()[:200]
            if kimlik in gorulen:
                kimlik = f"{kimlik}-{sira}"
            gorulen.add(kimlik)
            metin = str(kayit.get("metin") or kayit.get("text") or "").strip()
            gorsel = _legacy_gorsel_yolu(
                kok, kunye, kayit.get("dosya") or kayit.get("image")
            )
            if not metin and gorsel is None:
                continue
            if not metin:
                metin = (
                    "Gorseldeki biyoloji sorusunu ve varsa siklari okuyup coz. "
                    "Sekil, grafik ve tablodaki bilgileri de kullan."
                )
            kalite_ham = str(
                kayit.get("inceleme_durumu") or kayit.get("quality_status") or ""
            ).casefold()
            secenekler = _siklari_dogrula(
                kayit.get("siklar") or kayit.get("choices")
            )
            referans, referans_gecersiz = _referansi_dogrula(
                kayit.get("cevap") or kayit.get("reference_answer"), secenekler
            )
            inceleme = inceleme_klasoru or kalite_ham in {
                "incele",
                "review",
                "bekliyor",
            } or referans_gecersiz
            uyarilar = _liste(kayit.get("uyarilar"))
            if referans_gecersiz:
                uyarilar.append(
                    "Cevap anahtarı harfi çıkarılan şıklarda görünmüyor; görsel ve "
                    "kaynak anahtar üzerinden karşılaştırıldı."
                    if referans
                    else "Cevap anahtarı şıklarla uyumlu değil; otomatik "
                    "karşılaştırma yapılmadı."
                )
            sonuclar.append(
                PaketSorusu(
                    external_id=kimlik,
                    sira=sira,
                    metin=metin[:50_000],
                    secenekler=secenekler,
                    gorsel_yolu=gorsel,
                    kaynak_belge=str(kayit.get("kaynak") or "").strip()[:1000],
                    kaynak_sayfa=_sayfa(kayit.get("sayfa")),
                    kaynak_kutu=_kutu(kayit.get("kutu") or kayit.get("source_box")),
                    kesici_surumu=str(kayit.get("surum") or "legacy").strip(),
                    guven=_guven(
                        kayit.get("kalibre_guven", kayit.get("guven", 0))
                    ),
                    kalite_durumu="review" if inceleme else "automatic",
                    inceleme_gerekli=inceleme,
                    uyarilar=uyarilar,
                    referans_cevap=referans,
                )
            )
    if len(sonuclar) > AZAMI_SORU:
        raise KesVeCozHatasi("Pakette guvenli sinirdan fazla soru var.")
    return sonuclar


def _normalize_manifest(sorular: Iterable[PaketSorusu]) -> dict[str, Any]:
    return {
        "schema_version": PAKET_SURUMU,
        "source_app": "Soru Kesici",
        "answer_policy": {"withheld_from_model": ["reference_answer"]},
        "questions": [
            {
                **s.provenance(),
                "text": s.metin,
                "choices": s.secenekler,
                "image": s.gorsel_yolu.name if s.gorsel_yolu else "",
                "reference_answer": s.referans_cevap,
            }
            for s in sorular
        ],
    }


def yonlendirici(
    durum: Any,
    sablon: Any | None = None,
    *,
    servis: KesVeCozServisi | None = None,
) -> APIRouter:
    """Kes-ve-Coz sayfasi ve JSON is API'si.

    Testler ``servis`` enjekte edebilir. Normal uygulama, paylasilan
    ``Uygulama`` durumunun kokunu/cozucu fabrikasini kullanir.
    """
    servis = servis or KesVeCozServisi(durum.kok, durum.cozucu)
    router = APIRouter()

    if sablon is not None:

        @router.get("/kes-ve-coz", response_class=HTMLResponse)
        def kes_ve_coz_sayfasi(request: Request, is_id: str = ""):
            is_id = is_id or request.query_params.get("is", "")
            if is_id and servis.depo.is_getir(is_id) is None:
                is_id = ""
            return sablon.TemplateResponse(
                request,
                "kes_ve_coz.html",
                {
                    "durum": durum.durum(),
                    "etkin": "kes-ve-coz",
                    "isler": servis.depo.son_isler(),
                    "is_id": is_id,
                },
            )

    @router.post("/kes-ve-coz/is", status_code=202)
    async def is_baslat(request: Request, dosyalar: list[UploadFile] = File(...)):
        try:
            is_id = await servis.yukle(dosyalar)
        except YuklemeCokBuyuk as exc:
            return JSONResponse({"hata": str(exc)}, status_code=413)
        except KesVeCozHatasi as exc:
            return JSONResponse({"hata": str(exc)}, status_code=400)
        servis.baslat(is_id)
        sonuc = {
            "id": is_id,
            "is_id": is_id,
            "durum": "bekliyor",
            "status": "bekliyor",
            "api": f"/kes-ve-coz/api/is/{is_id}",
        }
        if "application/json" not in request.headers.get("accept", ""):
            return RedirectResponse(f"/kes-ve-coz?is={is_id}", status_code=303)
        return sonuc

    @router.get("/kes-ve-coz/api/isler")
    def is_listesi():
        return {
            "isler": [servis.durum(str(k["id"]), sorular_dahil=False) for k in servis.depo.son_isler()]
        }

    @router.get("/kes-ve-coz/api/is/{is_id}")
    def is_durumu(is_id: str):
        try:
            return servis.durum(is_id)
        except (KeyError, KesVeCozHatasi) as exc:
            raise HTTPException(404, "Kes ve Coz isi bulunamadi.") from exc

    @router.post("/kes-ve-coz/api/is/{is_id}/durdur")
    def is_durdur(is_id: str):
        try:
            degisti = servis.durdur(is_id)
            return {**servis.durum(is_id), "durdurma_istendi": degisti}
        except KeyError as exc:
            raise HTTPException(404, "Kes ve Coz isi bulunamadi.") from exc

    @router.get(
        "/kes-ve-coz/api/is/{is_id}/soru/{sira}/gorsel",
        response_class=FileResponse,
    )
    def soru_gorseli(is_id: str, sira: int):
        try:
            yol = servis.soru_gorseli(is_id, sira)
        except KesVeCozHatasi as exc:
            raise HTTPException(404, "Soru gorseli bulunamadi.") from exc
        if yol is None:
            raise HTTPException(404, "Soru gorseli bulunamadi.")
        return FileResponse(
            yol,
            media_type=GORSEL_MEDYA_TURLERI.get(
                yol.suffix.casefold(), "image/png"
            ),
            headers={
                "Cache-Control": "private, max-age=3600",
                "X-Content-Type-Options": "nosniff",
            },
        )

    # Entegrasyon/test, router kapanmadan servise erisebilsin.
    router.kes_ve_coz_servisi = servis  # type: ignore[attr-defined]
    return router


__all__ = [
    "AZAMI_YUKLEME_BAYT",
    "PAKET_SURUMU",
    "KesVeCozHatasi",
    "KesVeCozServisi",
    "PaketSorusu",
    "YuklemeCokBuyuk",
    "varsayilan_paketleyici_komutu",
    "yonlendirici",
]
