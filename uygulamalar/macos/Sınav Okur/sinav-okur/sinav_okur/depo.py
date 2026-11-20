"""SQLite depo: sınavlar, öğrenci kâğıtları, kutu sonuçları ve insan düzeltmeleri.

Düzeltilmiş transkripsiyonlar ``kutu.duzeltilmis_metin`` alanında saklanır;
``egitim_verisi_disa_aktar`` bunları kırpıntı yollarıyla eşleyip yeniden
eğitim (flywheel) için JSONL üretir.
"""

from __future__ import annotations

import json
import hashlib
import sqlite3
from contextlib import contextmanager
from pathlib import Path

from .modeller import Sinav
from .sonuclar import KagitSonucu

SEMA = """
CREATE TABLE IF NOT EXISTS sinav (
    kimlik TEXT PRIMARY KEY,
    baslik TEXT NOT NULL,
    ders TEXT,
    tanim_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS kagit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_kimlik TEXT NOT NULL REFERENCES sinav(kimlik),
    ogrenci_ad TEXT,
    ogrenci_soyad TEXT,
    ogrenci_no TEXT,
    sinif TEXT,
    sube TEXT,
    kimlik_guveni REAL DEFAULT 0,
    kimlik_json TEXT,
    kaynak_dosya TEXT,
    yazar_grubu TEXT,
    egitim_izni INTEGER DEFAULT 0,
    islem_uyarilari TEXT,
    kalite_json TEXT,
    sayfa_eslesme_json TEXT,
    inceleme_onceligi REAL DEFAULT 0,
    saklama_son_tarihi TEXT,
    olusturuldu TEXT DEFAULT (datetime('now')),
    onaylandi INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sinav_dosya (
    sinav_kimlik TEXT PRIMARY KEY REFERENCES sinav(kimlik) ON DELETE CASCADE,
    yaml_yolu TEXT,
    sablon_yolu TEXT,
    form_pdf_yolu TEXT
);
CREATE TABLE IF NOT EXISTS kutu (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kagit_id INTEGER NOT NULL REFERENCES kagit(id) ON DELETE CASCADE,
    soru_no INTEGER NOT NULL,
    taninan_metin TEXT,
    tanima_guveni REAL,
    duzeltilmis_metin TEXT,
    otomatik_puan REAL,
    son_puan REAL,
    max_puan REAL,
    incele INTEGER DEFAULT 0,
    detaylar TEXT,
    kirp_yolu TEXT,
    puanlama_guveni REAL DEFAULT 0,
    risk REAL DEFAULT 0,
    alternatifler_json TEXT,
    kararlar_json TEXT,
    aciklama TEXT,
    motor_sonuclari_json TEXT,
    girdi_kalitesi_json TEXT,
    model_surumu_json TEXT,
    kabul_nedenleri_json TEXT,
    uzlasma_guveni REAL DEFAULT 0,
    bagimsiz_motor_sayisi INTEGER DEFAULT 0,
    karar_marji REAL DEFAULT 0,
    otomatik_kabul INTEGER DEFAULT 0,
    degistirildi TEXT
);
CREATE TABLE IF NOT EXISTS ogrenci_listesi (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_kimlik TEXT NOT NULL REFERENCES sinav(kimlik) ON DELETE CASCADE,
    ogrenci_no TEXT NOT NULL,
    ad TEXT,
    soyad TEXT,
    sinif TEXT,
    sube TEXT,
    UNIQUE(sinav_kimlik, ogrenci_no)
);
CREATE TABLE IF NOT EXISTS denetim_kaydi (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    varlik_turu TEXT NOT NULL,
    varlik_id TEXT NOT NULL,
    islem TEXT NOT NULL,
    onceki_json TEXT,
    yeni_json TEXT,
    neden TEXT,
    aktor TEXT DEFAULT 'ogretmen',
    olusturuldu TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS duzeltme_ogrenimi (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kutu_id INTEGER NOT NULL REFERENCES kutu(id) ON DELETE CASCADE,
    ocr_metni TEXT,
    duzeltilmis_metin TEXT,
    otomatik_puan REAL,
    ogretmen_puani REAL,
    neden TEXT,
    olusturuldu TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS anahtar_surum (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_kimlik TEXT NOT NULL REFERENCES sinav(kimlik) ON DELETE CASCADE,
    surum INTEGER NOT NULL,
    tanim_json TEXT NOT NULL,
    onay_durumu TEXT DEFAULT 'taslak',
    olusturuldu TEXT DEFAULT (datetime('now')),
    UNIQUE(sinav_kimlik, surum)
);
CREATE TABLE IF NOT EXISTS altin_ornek (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_kimlik TEXT NOT NULL,
    soru_no INTEGER NOT NULL,
    kirp_yolu TEXT,
    beklenen_metin TEXT,
    beklenen_puan REAL,
    yazar_grubu TEXT,
    olusturuldu TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS puanlama_calistirmasi (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kutu_id INTEGER NOT NULL REFERENCES kutu(id) ON DELETE CASCADE,
    girdi_parmakizi TEXT NOT NULL,
    model_surumu_json TEXT,
    sonuc_json TEXT NOT NULL,
    olusturuldu TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS itiraz (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kagit_id INTEGER NOT NULL REFERENCES kagit(id) ON DELETE CASCADE,
    kutu_id INTEGER REFERENCES kutu(id) ON DELETE CASCADE,
    soru_no INTEGER,
    gerekce TEXT NOT NULL,
    durum TEXT DEFAULT 'acik',
    onceki_puan REAL,
    yeni_puan REAL,
    karar_notu TEXT,
    olusturuldu TEXT DEFAULT (datetime('now')),
    kapandi TEXT
);
CREATE TABLE IF NOT EXISTS ogrenci (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ogrenci_no TEXT,
    ad TEXT,
    soyad TEXT,
    sinif TEXT,
    sube TEXT,
    olusturuldu TEXT DEFAULT (datetime('now')),
    UNIQUE(ogrenci_no, ad, soyad)
);
CREATE TABLE IF NOT EXISTS ogrenilmis_kabul (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_kimlik TEXT NOT NULL,
    soru_no INTEGER NOT NULL,
    yazim TEXT NOT NULL,
    destek INTEGER DEFAULT 1,
    onay_durumu TEXT DEFAULT 'oneri',
    olusturuldu TEXT DEFAULT (datetime('now')),
    UNIQUE(sinav_kimlik, soru_no, yazim)
);

-- SQLite yabancı anahtarları kendiliğinden indekslemez; bunlar olmadan
-- kâğıt/kutu sorguları tam tablo taraması yapıyordu. DİKKAT: bu blok ALTER
-- migration'larından ÖNCE çalışır, bu yüzden yalnız ilk şema sürümünde var
-- olan sütunlara indeks yazılabilir (sonradan eklenen bir sütuna indeks,
-- eski bir veritabanını açılışta "no such column" ile kırar).
CREATE INDEX IF NOT EXISTS idx_kutu_kagit ON kutu(kagit_id, soru_no);
CREATE INDEX IF NOT EXISTS idx_kagit_sinav ON kagit(sinav_kimlik);
CREATE INDEX IF NOT EXISTS idx_itiraz_kagit ON itiraz(kagit_id);
CREATE INDEX IF NOT EXISTS idx_duzeltme_kutu ON duzeltme_ogrenimi(kutu_id);
CREATE INDEX IF NOT EXISTS idx_denetim_varlik
    ON denetim_kaydi(varlik_turu, varlik_id);
CREATE INDEX IF NOT EXISTS idx_puanlama_kutu ON puanlama_calistirmasi(kutu_id);
CREATE INDEX IF NOT EXISTS idx_altin_sinav
    ON altin_ornek(sinav_kimlik, soru_no);
"""


class Depo:
    def __init__(self, yol: str | Path = "sinav_okur.db"):
        self.yol = str(yol)
        # sorgulari_say() bunu bir listeye çevirir; None iken iz sürme kapalı
        # ve maliyeti sıfırdır.
        self._sorgu_kaydi: list[str] | None = None
        con = self._baglan()
        try:
            con.executescript(SEMA)
            # Eski veritabanlarını veri kaybetmeden güncelle.
            mevcut = {r[1] for r in con.execute("PRAGMA table_info(kagit)")}
            if "yazar_grubu" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN yazar_grubu TEXT")
            if "egitim_izni" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN egitim_izni INTEGER DEFAULT 0")
            if "islem_uyarilari" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN islem_uyarilari TEXT")
            if "ogrenci_soyad" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN ogrenci_soyad TEXT")
            if "sinif" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN sinif TEXT")
            if "sube" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN sube TEXT")
            if "kimlik_guveni" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN kimlik_guveni REAL DEFAULT 0")
            if "kimlik_json" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN kimlik_json TEXT")
            for ad, tanim in {
                "kalite_json": "TEXT",
                "sayfa_eslesme_json": "TEXT",
                "inceleme_onceligi": "REAL DEFAULT 0",
                "saklama_son_tarihi": "TEXT",
            }.items():
                if ad not in mevcut:
                    con.execute(f"ALTER TABLE kagit ADD COLUMN {ad} {tanim}")
            if "ogrenci_kimlik" not in mevcut:
                con.execute("ALTER TABLE kagit ADD COLUMN ogrenci_kimlik INTEGER")
            altin_mevcut = {
                r[1] for r in con.execute("PRAGMA table_info(altin_ornek)")
            }
            if "kaynak" not in altin_mevcut:
                con.execute(
                    "ALTER TABLE altin_ornek ADD COLUMN kaynak TEXT DEFAULT 'onay'"
                )
            kutu_mevcut = {r[1] for r in con.execute("PRAGMA table_info(kutu)")}
            for ad, tanim in {
                "puanlama_guveni": "REAL DEFAULT 0",
                "risk": "REAL DEFAULT 0",
                "alternatifler_json": "TEXT",
                "kararlar_json": "TEXT",
                "aciklama": "TEXT",
                "motor_sonuclari_json": "TEXT",
                "girdi_kalitesi_json": "TEXT",
                "model_surumu_json": "TEXT",
                "kabul_nedenleri_json": "TEXT",
                "uzlasma_guveni": "REAL DEFAULT 0",
                "bagimsiz_motor_sayisi": "INTEGER DEFAULT 0",
                "karar_marji": "REAL DEFAULT 0",
                "otomatik_kabul": "INTEGER DEFAULT 0",
                "degistirildi": "TEXT",
                "sozluk_duzeltmeleri_json": "TEXT",
            }.items():
                if ad not in kutu_mevcut:
                    con.execute(f"ALTER TABLE kutu ADD COLUMN {ad} {tanim}")
            con.commit()
        finally:
            con.close()

    def _baglan(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.yol)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys = ON")
        if self._sorgu_kaydi is not None:
            kayit = self._sorgu_kaydi
            con.set_trace_callback(lambda ifade: kayit.append(ifade))
        return con

    @contextmanager
    def sorgulari_say(self):
        """Blok içindeki SQL ifadelerini toplar (N+1 testleri için).

        Sayaç örneğin kendi niteliğidir; modül düzeyi global tutulmaz
        (test yalıtımı). ``with depo.sorgulari_say() as sorgular: ...``
        """
        onceki = self._sorgu_kaydi
        kayit: list[str] = []
        self._sorgu_kaydi = kayit
        try:
            yield kayit
        finally:
            self._sorgu_kaydi = onceki

    @contextmanager
    def _islem(self):
        con = self._baglan()
        try:
            yield con
            con.commit()
        finally:
            con.close()

    # --- Sınav ---

    def sinav_kaydet(self, sinav: Sinav) -> None:
        from dataclasses import asdict

        tanim = asdict(sinav)
        for s in tanim["sorular"]:
            s["tip"] = s["tip"].value if hasattr(s["tip"], "value") else s["tip"]
        with self._islem() as con:
            onceki = con.execute(
                "SELECT tanim_json FROM sinav WHERE kimlik=?", (sinav.kimlik,)
            ).fetchone()
            yeni_json = json.dumps(tanim, ensure_ascii=False)
            con.execute(
                "INSERT INTO sinav(kimlik, baslik, ders, tanim_json) VALUES (?,?,?,?) "
                "ON CONFLICT(kimlik) DO UPDATE SET "
                "baslik=excluded.baslik, ders=excluded.ders, "
                "tanim_json=excluded.tanim_json",
                (sinav.kimlik, sinav.baslik, sinav.ders, yeni_json),
            )
            if onceki is not None and onceki["tanim_json"] != yeni_json:
                con.execute(
                    "INSERT INTO denetim_kaydi"
                    "(varlik_turu,varlik_id,islem,onceki_json,yeni_json,neden) "
                    "VALUES ('sinav',?,'anahtar_surum',?,?,"
                    "'Cevap anahtarı veya puanlama ayarı güncellendi')",
                    (
                        sinav.kimlik,
                        onceki["tanim_json"],
                        yeni_json,
                    ),
                )
            satir = con.execute(
                "SELECT COALESCE(MAX(surum),0)+1 s FROM anahtar_surum "
                "WHERE sinav_kimlik=?",
                (sinav.kimlik,),
            ).fetchone()
            surum = int(satir["s"])
            con.execute(
                "INSERT OR IGNORE INTO anahtar_surum"
                "(sinav_kimlik,surum,tanim_json,onay_durumu) VALUES (?,?,?,?)",
                (
                    sinav.kimlik,
                    surum,
                    yeni_json,
                    (
                        "onayli"
                        if all(
                            s.anahtar.onay_durumu == "onayli"
                            for s in sinav.sorular
                        )
                        else "taslak"
                    ),
                ),
            )

    def sinav_yukle(self, kimlik: str) -> Sinav:
        with self._islem() as con:
            satir = con.execute(
                "SELECT tanim_json FROM sinav WHERE kimlik=?", (kimlik,)
            ).fetchone()
        if satir is None:
            raise KeyError(f"Sınav bulunamadı: {kimlik}")
        return Sinav(**json.loads(satir["tanim_json"]))

    def sinavlar(self) -> list[sqlite3.Row]:
        with self._islem() as con:
            return con.execute(
                "SELECT kimlik, baslik, ders FROM sinav ORDER BY kimlik"
            ).fetchall()

    def sinav_dosya_kaydet(
        self,
        sinav_kimlik: str,
        *,
        yaml_yolu: str | Path | None = None,
        sablon_yolu: str | Path | None = None,
        form_pdf_yolu: str | Path | None = None,
    ) -> None:
        """Sınava ait yeniden kullanılabilir form/şablon yollarını sakla."""
        with self._islem() as con:
            con.execute(
                "INSERT INTO sinav_dosya(sinav_kimlik,yaml_yolu,sablon_yolu,form_pdf_yolu) "
                "VALUES (?,?,?,?) ON CONFLICT(sinav_kimlik) DO UPDATE SET "
                "yaml_yolu=COALESCE(excluded.yaml_yolu,sinav_dosya.yaml_yolu), "
                "sablon_yolu=COALESCE(excluded.sablon_yolu,sinav_dosya.sablon_yolu), "
                "form_pdf_yolu=COALESCE(excluded.form_pdf_yolu,sinav_dosya.form_pdf_yolu)",
                (
                    sinav_kimlik,
                    str(yaml_yolu) if yaml_yolu else None,
                    str(sablon_yolu) if sablon_yolu else None,
                    str(form_pdf_yolu) if form_pdf_yolu else None,
                ),
            )

    def sinav_dosyasi(self, sinav_kimlik: str) -> sqlite3.Row | None:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM sinav_dosya WHERE sinav_kimlik=?",
                (sinav_kimlik,),
            ).fetchone()

    # --- Kâğıt + kutular ---

    def kagit_kaydet(
        self, sonuc: KagitSonucu, ogrenci_ad: str = "", ogrenci_no: str = "",
        ogrenci_soyad: str = "", sinif: str = "", sube: str = "",
        kimlik_guveni: float = 0.0, kimlik_bilgileri: dict | None = None,
        kaynak_dosya: str = "", yazar_grubu: str = "", egitim_izni: bool = False,
        islem_uyarilari: list[str] | None = None,
        saklama_gunu: int = 365,
    ) -> int:
        kalite = list(getattr(sonuc, "kalite_raporu", []) or [])
        eslesmeler = list(getattr(sonuc, "sayfa_eslesmeleri", []) or [])
        kritik_sayfa = sum(1 for r in kalite if r.get("kritik"))
        bekleyen = sum(1 for k in sonuc.kutular if k.puan.incele)
        oncelik = min(1.0, 0.25 * kritik_sayfa + 0.12 * bekleyen)
        with self._islem() as con:
            cur = con.execute(
                "INSERT INTO kagit(sinav_kimlik, ogrenci_ad, ogrenci_soyad, "
                "ogrenci_no, sinif, sube, kimlik_guveni, kimlik_json, kaynak_dosya, "
                "yazar_grubu, egitim_izni, islem_uyarilari, kalite_json, "
                "sayfa_eslesme_json, inceleme_onceligi, saklama_son_tarihi) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,"
                "datetime('now', ?))",
                (sonuc.sinav_kimlik, ogrenci_ad, ogrenci_soyad, ogrenci_no,
                 sinif, sube, float(kimlik_guveni),
                 json.dumps(kimlik_bilgileri or {}, ensure_ascii=False), kaynak_dosya,
                 yazar_grubu.strip(), int(egitim_izni),
                 json.dumps(islem_uyarilari or [], ensure_ascii=False),
                 json.dumps(kalite, ensure_ascii=False),
                 json.dumps(eslesmeler, ensure_ascii=False),
                 oncelik,
                 f"+{max(1, int(saklama_gunu))} days"),
            )
            kagit_id = cur.lastrowid
            for k in sonuc.kutular:
                cur_kutu = con.execute(
                    "INSERT INTO kutu(kagit_id, soru_no, taninan_metin, tanima_guveni, "
                    "otomatik_puan, son_puan, max_puan, incele, detaylar, kirp_yolu, "
                    "puanlama_guveni, risk, alternatifler_json, kararlar_json, aciklama, "
                    "motor_sonuclari_json, girdi_kalitesi_json, model_surumu_json, "
                    "kabul_nedenleri_json, uzlasma_guveni, bagimsiz_motor_sayisi, "
                    "karar_marji, otomatik_kabul, sozluk_duzeltmeleri_json) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (kagit_id, k.soru_no, k.tanima.metin, k.tanima.guven,
                     k.puan.puan, k.puan.puan, k.puan.max_puan,
                     int(k.puan.incele), json.dumps(k.puan.detaylar, ensure_ascii=False),
                     k.kirp_yolu, float(k.puan.puanlama_guveni or k.puan.guven),
                     float(k.puan.risk),
                     json.dumps(k.tanima.alternatifler, ensure_ascii=False),
                     json.dumps(k.puan.kararlar, ensure_ascii=False),
                     k.puan.aciklama,
                     json.dumps(k.tanima.motor_sonuclari, ensure_ascii=False),
                     json.dumps(getattr(k, "kalite", {}) or {}, ensure_ascii=False),
                     json.dumps(k.tanima.model_surumu, ensure_ascii=False),
                     json.dumps(k.puan.kabul_nedenleri, ensure_ascii=False),
                     float(k.tanima.uzlasma_guveni),
                     int(k.tanima.bagimsiz_motor_sayisi),
                     float(k.tanima.karar_marji),
                     int(k.puan.otomatik_kabul),
                     json.dumps(
                         getattr(k, "sozluk_duzeltmeleri", []) or [],
                         ensure_ascii=False,
                     )),
                )
                girdi_parmakizi = hashlib.sha256(
                    (
                        f"{sonuc.sinav_kimlik}:{k.soru_no}:"
                        f"{k.tanima.metin}:{k.puan.max_puan}"
                    ).encode("utf-8")
                ).hexdigest()
                con.execute(
                    "INSERT INTO puanlama_calistirmasi"
                    "(kutu_id,girdi_parmakizi,model_surumu_json,sonuc_json) "
                    "VALUES (?,?,?,?)",
                    (
                        int(cur_kutu.lastrowid),
                        girdi_parmakizi,
                        json.dumps(k.tanima.model_surumu, ensure_ascii=False),
                        json.dumps(
                            {
                                "puan": k.puan.puan,
                                "max_puan": k.puan.max_puan,
                                "incele": k.puan.incele,
                                "otomatik_kabul": k.puan.otomatik_kabul,
                                "kabul_nedenleri": k.puan.kabul_nedenleri,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            self._guvenlik_kapisi_ozeti_yaz(con, kagit_id, sonuc.kutular)
        return kagit_id

    @staticmethod
    def _guvenlik_kapisi_ozeti_yaz(con, kagit_id: int, kutular) -> None:
        """Kâğıt başına kapı kararlarını denetim_kaydı'na özet olarak yazar."""
        kapi_kararlari = [
            karar
            for kutu in kutular
            for karar in kutu.puan.kararlar
            if isinstance(karar, dict) and karar.get("tur") == "guvenlik_kapisi"
        ]
        if not kapi_kararlari:
            return
        neden_sayimlari: dict[str, int] = {}
        for karar in kapi_kararlari:
            if not karar.get("otomatik_kabul"):
                for neden in karar.get("nedenler", []):
                    neden_sayimlari[neden] = neden_sayimlari.get(neden, 0) + 1
        modlar = {k.get("mod", "") for k in kapi_kararlari}
        ozet = {
            "mod": next(iter(modlar)) if len(modlar) == 1 else sorted(modlar),
            "kutu": len(kapi_kararlari),
            "otomatik_kabul_edilebilir": sum(
                1 for k in kapi_kararlari if k.get("otomatik_kabul")
            ),
            "neden_sayimlari": neden_sayimlari,
        }
        con.execute(
            "INSERT INTO denetim_kaydi"
            "(varlik_turu,varlik_id,islem,yeni_json,neden,aktor) "
            "VALUES ('kagit',?,?,?,?, 'sistem')",
            (
                str(kagit_id),
                "guvenlik_kapisi",
                json.dumps(ozet, ensure_ascii=False),
                "Seçici kabul kapısı kararları",
            ),
        )

    def kagit_kimlik_guncelle(
        self,
        kagit_id: int,
        *,
        ogrenci_ad: str,
        ogrenci_soyad: str = "",
        ogrenci_no: str = "",
        sinif: str = "",
        sube: str = "",
    ) -> None:
        """Öğretmenin doğruladığı kimlik alanlarını sakla."""
        with self._islem() as con:
            con.execute(
                "UPDATE kagit SET ogrenci_ad=?, ogrenci_soyad=?, ogrenci_no=?, "
                "sinif=?, sube=?, kimlik_guveni=1 WHERE id=?",
                (
                    ogrenci_ad.strip(),
                    ogrenci_soyad.strip(),
                    ogrenci_no.strip(),
                    sinif.strip(),
                    sube.strip(),
                    kagit_id,
                ),
            )

    def kagit_kalitesini_guncelle(
        self,
        kagit_id: int,
        kalite_raporu: list[dict],
    ) -> None:
        """Eski bir kaydın kaynak görüntülerini kalite kapısından yeniden geçir."""
        kritik = sum(1 for rapor in kalite_raporu if rapor.get("kritik"))
        en_yuksek_risk = max(
            (
                min(
                    1.0,
                    (0.55 if rapor.get("kritik") else 0.0)
                    + float(rapor.get("parlama_orani", 0.0))
                    + min(0.25, float(rapor.get("golge_sapmasi", 0.0))),
                )
                for rapor in kalite_raporu
            ),
            default=0.0,
        )
        with self._islem() as con:
            con.execute(
                "UPDATE kagit SET kalite_json=?, inceleme_onceligi="
                "MAX(COALESCE(inceleme_onceligi,0),?) WHERE id=?",
                (
                    json.dumps(kalite_raporu, ensure_ascii=False),
                    min(1.0, 0.25 * kritik + en_yuksek_risk),
                    kagit_id,
                ),
            )
            if kritik:
                con.execute(
                    "UPDATE kutu SET incele=1, otomatik_kabul=0, "
                    "kabul_nedenleri_json=? WHERE kagit_id=?",
                    (
                        json.dumps(
                            [
                                "Yenilenen sayfa kalite kapısı kritik girdi "
                                "anomalisi buldu."
                            ],
                            ensure_ascii=False,
                        ),
                        kagit_id,
                    ),
                )
            con.execute(
                "INSERT INTO denetim_kaydi"
                "(varlik_turu,varlik_id,islem,neden) VALUES "
                "('kagit',?,'kalite_yenileme',"
                "'Kaynak görüntüler kalite kapısından yeniden geçirildi')",
                (str(kagit_id),),
            )

    def kagit(self, kagit_id: int) -> sqlite3.Row:
        with self._islem() as con:
            return con.execute("SELECT * FROM kagit WHERE id=?", (kagit_id,)).fetchone()

    def kagitlar(self, sinav_kimlik: str | None = None) -> list[sqlite3.Row]:
        with self._islem() as con:
            if sinav_kimlik:
                return con.execute(
                    "SELECT * FROM kagit WHERE sinav_kimlik=? ORDER BY id DESC",
                    (sinav_kimlik,),
                ).fetchall()
            return con.execute("SELECT * FROM kagit ORDER BY id DESC").fetchall()

    def kutular(self, kagit_id: int) -> list[sqlite3.Row]:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM kutu WHERE kagit_id=? ORDER BY soru_no", (kagit_id,)
            ).fetchall()

    def kutu(self, kutu_id: int) -> sqlite3.Row | None:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM kutu WHERE id=?", (kutu_id,)
            ).fetchone()

    def guvenlik_kapisi_ozeti(self, sinav_kimlik: str | None = None) -> dict:
        """Gölge/aktif kapı kararlarını kutu düzeyinde tarayıp özetler.

        ``golge_yanlis_kabul``: kapının otomatik kabul edilebilir gördüğü ama
        öğretmenin sonradan metnini veya puanını değiştirdiği kutu sayısı —
        aktivasyon için kritik gösterge (docs/ml_dl_guvenilirlik.md).
        """
        from .metin import eslesme_bicimi

        sorgu = (
            "SELECT k.taninan_metin, k.duzeltilmis_metin, k.otomatik_puan, "
            "k.son_puan, k.kararlar_json FROM kutu k JOIN kagit g ON k.kagit_id=g.id"
        )
        parametreler: tuple = ()
        if sinav_kimlik:
            sorgu += " WHERE g.sinav_kimlik=?"
            parametreler = (sinav_kimlik,)
        with self._islem() as con:
            satirlar = con.execute(sorgu, parametreler).fetchall()

        kapili = kabul_edilebilir = golge_yanlis_kabul = 0
        neden_sayimlari: dict[str, int] = {}
        for satir in satirlar:
            try:
                kararlar = json.loads(satir["kararlar_json"] or "[]")
            except (TypeError, ValueError):
                continue
            kapi = next(
                (
                    k for k in kararlar
                    if isinstance(k, dict) and k.get("tur") == "guvenlik_kapisi"
                ),
                None,
            )
            if kapi is None:
                continue
            kapili += 1
            if kapi.get("otomatik_kabul"):
                kabul_edilebilir += 1
                metin_degisti = (
                    satir["duzeltilmis_metin"] is not None
                    and eslesme_bicimi(satir["duzeltilmis_metin"])
                    != eslesme_bicimi(satir["taninan_metin"] or "")
                )
                puan_degisti = (
                    satir["son_puan"] is not None
                    and satir["otomatik_puan"] is not None
                    and abs(
                        float(satir["son_puan"]) - float(satir["otomatik_puan"])
                    ) > 1e-9
                )
                if metin_degisti or puan_degisti:
                    golge_yanlis_kabul += 1
            else:
                for neden in kapi.get("nedenler", []):
                    neden_sayimlari[neden] = neden_sayimlari.get(neden, 0) + 1
        return {
            "kutu": len(satirlar),
            "kapili_kutu": kapili,
            "kabul_edilebilir": kabul_edilebilir,
            "kabul_orani": (kabul_edilebilir / kapili) if kapili else 0.0,
            "golge_yanlis_kabul": golge_yanlis_kabul,
            "neden_sayimlari": neden_sayimlari,
        }

    def kapi_kayitlari(self, sinav_kimlik: str | None = None) -> list[dict]:
        """Kutu başına ham kapı kararlarını eşik simülasyonu için döker.

        ``ogretmen_degistirdi``: öğretmen sonradan metni veya puanı değiştirdi —
        simülasyonda "bu eşikle kabul edilseydi yanlış kabul olurdu" sinyali.
        """
        from .metin import eslesme_bicimi

        sorgu = (
            "SELECT k.taninan_metin, k.duzeltilmis_metin, k.otomatik_puan, "
            "k.son_puan, k.kararlar_json FROM kutu k JOIN kagit g ON k.kagit_id=g.id"
        )
        parametreler: tuple = ()
        if sinav_kimlik:
            sorgu += " WHERE g.sinav_kimlik=?"
            parametreler = (sinav_kimlik,)
        with self._islem() as con:
            satirlar = con.execute(sorgu, parametreler).fetchall()

        kayitlar: list[dict] = []
        for satir in satirlar:
            try:
                kararlar = json.loads(satir["kararlar_json"] or "[]")
            except (TypeError, ValueError):
                continue
            kapi = next(
                (
                    k for k in kararlar
                    if isinstance(k, dict) and k.get("tur") == "guvenlik_kapisi"
                ),
                None,
            )
            if kapi is None:
                continue
            metin_degisti = (
                satir["duzeltilmis_metin"] is not None
                and eslesme_bicimi(satir["duzeltilmis_metin"])
                != eslesme_bicimi(satir["taninan_metin"] or "")
            )
            puan_degisti = (
                satir["son_puan"] is not None
                and satir["otomatik_puan"] is not None
                and abs(
                    float(satir["son_puan"]) - float(satir["otomatik_puan"])
                ) > 1e-9
            )
            kayitlar.append(
                {
                    "otomatik_kabul": bool(kapi.get("otomatik_kabul")),
                    "nedenler": list(kapi.get("nedenler", [])),
                    "kalibre_guven": float(kapi.get("kalibre_guven", 0.0)),
                    "uzlasma_guveni": float(kapi.get("uzlasma_guveni", 0.0)),
                    "bagimsiz_motor": int(kapi.get("bagimsiz_motor", 0)),
                    "karar_marji": float(kapi.get("karar_marji", 0.0)),
                    "puanlama_guveni": float(kapi.get("puanlama_guveni", 0.0)),
                    "mod": str(kapi.get("mod", "")),
                    "ogretmen_degistirdi": metin_degisti or puan_degisti,
                }
            )
        return kayitlar

    def kutu_guncelle(
        self, kutu_id: int, son_puan: float | None = None,
        duzeltilmis_metin: str | None = None, incele: bool | None = None,
        neden: str = "Öğretmen elle düzeltti", aktor: str = "ogretmen",
    ) -> None:
        alanlar, degerler = [], []
        if son_puan is not None:
            alanlar.append("son_puan=?"); degerler.append(son_puan)
        if duzeltilmis_metin is not None:
            alanlar.append("duzeltilmis_metin=?"); degerler.append(duzeltilmis_metin)
        if incele is not None:
            alanlar.append("incele=?"); degerler.append(int(incele))
        if not alanlar:
            return
        alanlar.append("degistirildi=datetime('now')")
        degerler.append(kutu_id)
        with self._islem() as con:
            onceki = con.execute(
                "SELECT * FROM kutu WHERE id=?", (kutu_id,)
            ).fetchone()
            con.execute(f"UPDATE kutu SET {', '.join(alanlar)} WHERE id=?", degerler)
            yeni = con.execute(
                "SELECT * FROM kutu WHERE id=?", (kutu_id,)
            ).fetchone()
            if onceki is not None and yeni is not None:
                con.execute(
                    "INSERT INTO denetim_kaydi"
                    "(varlik_turu,varlik_id,islem,onceki_json,yeni_json,neden,aktor) "
                    "VALUES ('kutu',?,?,?,?,?,?)",
                    (
                        str(kutu_id),
                        "elle_duzeltme",
                        json.dumps(dict(onceki), ensure_ascii=False),
                        json.dumps(dict(yeni), ensure_ascii=False),
                        neden,
                        aktor,
                    ),
                )
                if (
                    duzeltilmis_metin is not None
                    or (
                        son_puan is not None
                        and float(son_puan) != float(onceki["son_puan"] or 0)
                    )
                ):
                    con.execute(
                        "INSERT INTO duzeltme_ogrenimi"
                        "(kutu_id,ocr_metni,duzeltilmis_metin,otomatik_puan,"
                        "ogretmen_puani,neden) VALUES (?,?,?,?,?,?)",
                        (
                            kutu_id,
                            onceki["taninan_metin"],
                            duzeltilmis_metin,
                            onceki["otomatik_puan"],
                            son_puan,
                            neden,
                        ),
                    )

    def kutu_otomatik_puan_guncelle(
        self,
        kutu_id: int,
        *,
        metin: str,
        puan: float,
        guven: float,
        incele: bool,
        detaylar: list[str],
        kararlar: list[dict] | None = None,
        aciklama: str = "",
        risk: float | None = None,
        otomatik_kabul: bool = False,
        kabul_nedenleri: list[str] | None = None,
    ) -> None:
        """Düzeltilmiş metni cevap anahtarına göre yeniden puanlayıp birlikte sakla."""
        with self._islem() as con:
            con.execute(
                "UPDATE kutu SET duzeltilmis_metin=?, otomatik_puan=?, "
                "son_puan=?, incele=?, detaylar=?, puanlama_guveni=?, risk=?, "
                "kararlar_json=?, aciklama=?, otomatik_kabul=?, "
                "kabul_nedenleri_json=?, degistirildi=datetime('now') WHERE id=?",
                (
                    metin,
                    float(puan),
                    float(puan),
                    int(incele),
                    json.dumps(
                        [*detaylar, f"Otomatik puanlama güveni: %{guven * 100:.0f}"],
                        ensure_ascii=False,
                    ),
                    float(guven),
                    float((1.0 - guven) if risk is None else risk),
                    json.dumps(kararlar or [], ensure_ascii=False),
                    aciklama,
                    int(otomatik_kabul),
                    json.dumps(kabul_nedenleri or [], ensure_ascii=False),
                    kutu_id,
                ),
            )

    def kagit_onayla(self, kagit_id: int) -> None:
        with self._islem() as con:
            con.execute("UPDATE kagit SET onaylandi=1 WHERE id=?", (kagit_id,))
            con.execute(
                "UPDATE kutu SET incele=0 WHERE kagit_id=?", (kagit_id,)
            )
            con.execute(
                "INSERT INTO denetim_kaydi"
                "(varlik_turu,varlik_id,islem,neden) VALUES ('kagit',?,'onay','Öğretmen onayı')",
                (str(kagit_id),),
            )

    def kagit_onayini_kaldir(self, kagit_id: int) -> None:
        with self._islem() as con:
            con.execute("UPDATE kagit SET onaylandi=0 WHERE id=?", (kagit_id,))

    def cozulmemis_kutular(self, kagit_id: int) -> list[sqlite3.Row]:
        """OCR metni olmayan ve öğretmence henüz doğrulanmayan kutuları getir."""
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM kutu WHERE kagit_id=? "
                "AND incele=1 "
                "AND (taninan_metin IS NULL OR TRIM(taninan_metin)='') "
                "AND duzeltilmis_metin IS NULL "
                "ORDER BY soru_no",
                (kagit_id,),
            ).fetchall()

    def kagit_toplam(self, kagit_id: int) -> tuple[float, float]:
        with self._islem() as con:
            satir = con.execute(
                "SELECT COALESCE(SUM(son_puan),0) t, COALESCE(SUM(max_puan),0) m "
                "FROM kutu WHERE kagit_id=?", (kagit_id,)
            ).fetchone()
        return satir["t"], satir["m"]

    # --- Öğrenci listesi, denetim ve ölçüm ---

    def ogrenci_listesi_kaydet(self, sinav_kimlik: str, kayitlar: list[dict]) -> int:
        adet = 0
        with self._islem() as con:
            for kayit in kayitlar:
                no = str(kayit.get("ogrenci_no", kayit.get("numara", ""))).strip()
                if not no:
                    continue
                con.execute(
                    "INSERT INTO ogrenci_listesi"
                    "(sinav_kimlik,ogrenci_no,ad,soyad,sinif,sube) VALUES (?,?,?,?,?,?) "
                    "ON CONFLICT(sinav_kimlik,ogrenci_no) DO UPDATE SET "
                    "ad=excluded.ad,soyad=excluded.soyad,sinif=excluded.sinif,"
                    "sube=excluded.sube",
                    (
                        sinav_kimlik,
                        no,
                        str(kayit.get("ad", "")).strip(),
                        str(kayit.get("soyad", "")).strip(),
                        str(kayit.get("sinif", "")).strip(),
                        str(kayit.get("sube", "")).strip(),
                    ),
                )
                adet += 1
        return adet

    def ogrenci_listesi(self, sinav_kimlik: str) -> list[sqlite3.Row]:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM ogrenci_listesi WHERE sinav_kimlik=? "
                "ORDER BY sinif,sube,ogrenci_no",
                (sinav_kimlik,),
            ).fetchall()

    def denetim_kayitlari(
        self, varlik_turu: str | None = None, varlik_id: str | None = None
    ) -> list[sqlite3.Row]:
        sorgu = "SELECT * FROM denetim_kaydi WHERE 1=1"
        degerler: list[str] = []
        if varlik_turu:
            sorgu += " AND varlik_turu=?"
            degerler.append(varlik_turu)
        if varlik_id:
            sorgu += " AND varlik_id=?"
            degerler.append(str(varlik_id))
        sorgu += " ORDER BY id DESC"
        with self._islem() as con:
            return con.execute(sorgu, degerler).fetchall()

    def sinav_cevaplari(self, sinav_kimlik: str) -> list[sqlite3.Row]:
        with self._islem() as con:
            return con.execute(
                "SELECT k.*, g.ogrenci_ad, g.ogrenci_soyad, g.ogrenci_no, "
                "g.onaylandi FROM kutu k JOIN kagit g ON g.id=k.kagit_id "
                "WHERE g.sinav_kimlik=? ORDER BY k.soru_no,g.id",
                (sinav_kimlik,),
            ).fetchall()

    def duzeltme_ornekleri(self, sinav_kimlik: str | None = None) -> list[sqlite3.Row]:
        sorgu = (
            "SELECT d.*, g.sinav_kimlik, k.soru_no FROM duzeltme_ogrenimi d "
            "JOIN kutu k ON k.id=d.kutu_id JOIN kagit g ON g.id=k.kagit_id"
        )
        degerler: tuple = ()
        if sinav_kimlik:
            sorgu += " WHERE g.sinav_kimlik=?"
            degerler = (sinav_kimlik,)
        sorgu += " ORDER BY d.id DESC"
        with self._islem() as con:
            return con.execute(sorgu, degerler).fetchall()

    def kalibrasyon_ornekleri(
        self, sinav_kimlik: str | None = None
    ) -> list[dict]:
        """OCR güven kalibrasyonu için (ham_kanit, taninan, ogretmen) üçlüleri.

        Ham güven kaynağı ``alternatifler_json[0]["guven"]`` — CokluTaniyici
        kazanan kümesinin Platt ÖNCESİ kanıt skoru (kalibre tanima_guveni
        kolonu KULLANILMAZ; yeniden eğitimde anlamı kayar). Yalnız çoklu-hat
        kutuları (alternatifler + motor_sonuclari dolu) alınır.

        Kaynaklar:
          1) Öğretmen düzeltmesi (duzeltilmis_metin dolu) → etiket karşılaştırma
          2) Onaylı, dokunulmamış kutular (onaylandi=1, duzeltilmis_metin NULL)
             → dogru=True (öğretmen görüp değiştirmeden geçmiş)
        """
        sorgu = (
            "SELECT k.taninan_metin, k.duzeltilmis_metin, k.alternatifler_json, "
            "k.motor_sonuclari_json, k.bagimsiz_motor_sayisi, "
            "k.girdi_kalitesi_json, k.sozluk_duzeltmeleri_json, "
            "k.kararlar_json, g.onaylandi FROM kutu k "
            "JOIN kagit g ON g.id=k.kagit_id "
            "WHERE k.alternatifler_json IS NOT NULL "
            "AND k.motor_sonuclari_json IS NOT NULL "
            "AND (k.duzeltilmis_metin IS NOT NULL OR g.onaylandi=1)"
        )
        parametreler: tuple = ()
        if sinav_kimlik:
            sorgu += " AND g.sinav_kimlik=?"
            parametreler = (sinav_kimlik,)
        with self._islem() as con:
            satirlar = con.execute(sorgu, parametreler).fetchall()

        ornekler: list[dict] = []
        for satir in satirlar:
            try:
                alternatifler = json.loads(satir["alternatifler_json"] or "[]")
                motorlar = json.loads(satir["motor_sonuclari_json"] or "[]")
            except (TypeError, ValueError):
                continue
            if not alternatifler or not motorlar:
                continue
            ham = alternatifler[0].get("guven")
            if ham is None:
                continue
            # Sözlük düzeltmesi ya da aday yeniden sıralama metni değiştirmişse
            # etiket artık `alternatifler[0]`'ın doğruluğunu ölçmez; öznitelik
            # ile etiket farklı adaylara ait olur ve eğri gürültüyle eğitilir.
            if satir["sozluk_duzeltmeleri_json"] not in (None, "", "[]"):
                continue
            try:
                kararlar = json.loads(satir["kararlar_json"] or "[]")
            except (TypeError, ValueError):
                kararlar = []
            if any(
                k.get("tur") == "aday_yeniden_siralama" for k in kararlar
            ):
                continue
            taninan = satir["taninan_metin"] or ""
            duzeltilmis = satir["duzeltilmis_metin"]
            if duzeltilmis is not None:
                ogretmen = duzeltilmis
                kaynak = "duzeltme"
            else:
                ogretmen = taninan
                kaynak = "onay"
            try:
                kalite = json.loads(satir["girdi_kalitesi_json"] or "{}")
            except (TypeError, ValueError):
                kalite = {}
            # Dilim sütunları sonradan eklendi; eski satırlarda DEFAULT 0 /
            # NULL var. Bunları "motor1/kalite_dusuk" saymak o dilimin eğrisini
            # yapay olarak iyimser yapardı — dilim bilinmiyor olarak işaretlenir
            # ve dilim eğitiminin dışında bırakılır.
            dilim_bilinir = bool(satir["bagimsiz_motor_sayisi"]) and bool(
                satir["girdi_kalitesi_json"]
            )
            ornekler.append(
                {
                    "ham_guven": float(ham),
                    "taninan": taninan,
                    "ogretmen": ogretmen,
                    "kaynak": kaynak,
                    "bagimsiz_motor_sayisi": int(
                        satir["bagimsiz_motor_sayisi"] or 0
                    ),
                    "girdi_kalitesi": float(kalite.get("kalite", 0.0) or 0.0),
                    "dilim_bilinir": dilim_bilinir,
                }
            )
        return ornekler

    def itiraz_ac(
        self, kagit_id: int, kutu_id: int | None, gerekce: str
    ) -> int:
        """Öğrenci itirazını kaydeder; puanı DEĞİŞTİRMEZ."""
        if not (gerekce or "").strip():
            raise ValueError("İtiraz gerekçesi boş olamaz.")
        with self._islem() as con:
            # Kutu, itirazın açıldığı kâğıda AİT olmalı; aksi halde bir
            # kâğıt üzerinden başka bir öğrencinin puanı değiştirilebilir.
            kutu = (
                con.execute(
                    "SELECT soru_no, son_puan FROM kutu WHERE id=? AND kagit_id=?",
                    (int(kutu_id), int(kagit_id)),
                ).fetchone()
                if kutu_id
                else None
            )
            if kutu_id and kutu is None:
                raise ValueError("Kutu bu kâğıda ait değil.")
            cur = con.execute(
                "INSERT INTO itiraz(kagit_id, kutu_id, soru_no, gerekce, "
                "onceki_puan) VALUES (?,?,?,?,?)",
                (
                    int(kagit_id),
                    int(kutu_id) if kutu_id else None,
                    kutu["soru_no"] if kutu else None,
                    gerekce.strip(),
                    kutu["son_puan"] if kutu else None,
                ),
            )
            itiraz_id = int(cur.lastrowid)
            con.execute(
                "INSERT INTO denetim_kaydi"
                "(varlik_turu, varlik_id, islem, onceki_json, yeni_json, neden, aktor) "
                "VALUES ('kutu',?,'itiraz',?,?,?,'ogretmen')",
                (
                    int(kutu_id) if kutu_id else int(kagit_id),
                    json.dumps({}, ensure_ascii=False),
                    json.dumps({"itiraz_id": itiraz_id}, ensure_ascii=False),
                    f"İtiraz açıldı: {gerekce.strip()[:180]}",
                ),
            )
            return itiraz_id

    def itiraz_karara_bagla(
        self,
        itiraz_id: int,
        kabul: bool,
        yeni_puan: float | None = None,
        karar_notu: str = "",
    ) -> None:
        """İtirazı kapatır. Kabulde puan ``kutu_guncelle`` ile değişir.

        Puan değişimi kutu_guncelle üzerinden gittiği için düzeltme öğrenimi
        ve denetim kaydı otomatik beslenir — kalibrasyon itirazlardan da öğrenir.
        """
        with self._islem() as con:
            itiraz = con.execute(
                "SELECT * FROM itiraz WHERE id=?", (int(itiraz_id),)
            ).fetchone()
        if itiraz is None:
            raise KeyError(f"İtiraz bulunamadı: {itiraz_id}")
        if itiraz["durum"] != "acik":
            # Kapanmış itiraz yeniden karara bağlanamaz; aksi halde her
            # çağrıda yeni puan yazılır ve denetim izi yanıltıcı olur.
            raise ValueError("Bu itiraz zaten karara bağlanmış.")
        if kabul and yeni_puan is not None and itiraz["kutu_id"]:
            kutu = self.kutu(int(itiraz["kutu_id"]))
            azami = float(kutu["max_puan"]) if kutu else 0.0
            if not 0.0 <= float(yeni_puan) <= azami:
                raise ValueError(
                    f"İtiraz puanı 0 ile {azami:g} arasında olmalı."
                )
            self.kutu_guncelle(
                kutu_id=int(itiraz["kutu_id"]),
                son_puan=float(yeni_puan),
                incele=False,
                neden=f"İtiraz kabul edildi: {(karar_notu or '').strip()[:180]}",
            )
        with self._islem() as con:
            con.execute(
                "UPDATE itiraz SET durum=?, yeni_puan=?, karar_notu=?, "
                "kapandi=datetime('now') WHERE id=?",
                (
                    "kabul" if kabul else "ret",
                    float(yeni_puan) if (kabul and yeni_puan is not None) else None,
                    (karar_notu or "").strip(),
                    int(itiraz_id),
                ),
            )

    def itirazlar(
        self, sinav_kimlik: str | None = None, durum: str | None = None
    ) -> list[sqlite3.Row]:
        sorgu = (
            "SELECT i.*, g.sinav_kimlik, g.ogrenci_ad, g.ogrenci_soyad "
            "FROM itiraz i JOIN kagit g ON g.id=i.kagit_id"
        )
        kosullar: list[str] = []
        degerler: list = []
        if sinav_kimlik:
            kosullar.append("g.sinav_kimlik=?")
            degerler.append(sinav_kimlik)
        if durum:
            kosullar.append("i.durum=?")
            degerler.append(durum)
        if kosullar:
            sorgu += " WHERE " + " AND ".join(kosullar)
        sorgu += " ORDER BY i.durum='acik' DESC, i.id DESC"
        with self._islem() as con:
            return con.execute(sorgu, tuple(degerler)).fetchall()

    def ogrenci_bul_veya_ekle(
        self, ad: str, soyad: str, ogrenci_no: str = "",
        sinif: str = "", sube: str = "",
    ) -> int:
        """Öğrenciyi (numara, ad, soyad) üçlüsüyle bulur; yoksa oluşturur."""
        with self._islem() as con:
            satir = con.execute(
                "SELECT id FROM ogrenci WHERE COALESCE(ogrenci_no,'')=? "
                "AND COALESCE(ad,'')=? AND COALESCE(soyad,'')=?",
                (ogrenci_no or "", ad or "", soyad or ""),
            ).fetchone()
            if satir:
                # Sınıf/şube en güncel kâğıttan tazelenir.
                con.execute(
                    "UPDATE ogrenci SET sinif=COALESCE(NULLIF(?,''),sinif), "
                    "sube=COALESCE(NULLIF(?,''),sube) WHERE id=?",
                    (sinif or "", sube or "", satir["id"]),
                )
                return int(satir["id"])
            cur = con.execute(
                "INSERT INTO ogrenci(ogrenci_no, ad, soyad, sinif, sube) "
                "VALUES (?,?,?,?,?)",
                (ogrenci_no or "", ad or "", soyad or "", sinif or "", sube or ""),
            )
            return int(cur.lastrowid)

    def kagidi_ogrenciye_bagla(self, kagit_id: int, ogrenci_kimlik: int) -> None:
        with self._islem() as con:
            con.execute(
                "UPDATE kagit SET ogrenci_kimlik=? WHERE id=?",
                (int(ogrenci_kimlik), int(kagit_id)),
            )

    def ogrencileri_esle(self, sinav_kimlik: str | None = None) -> dict:
        """Kâğıtları kalıcı öğrenci kayıtlarına bağlar.

        Otomatik ÇALIŞMAZ; öğretmen /gelisim sayfasından tetikler. Kimlik
        alanı hiç olmayan kâğıtlar (isimsiz) bağlanmaz — yanlış birleştirme
        riski insan kararına bırakılır.
        """
        sorgu = "SELECT * FROM kagit"
        degerler: tuple = ()
        if sinav_kimlik:
            sorgu += " WHERE sinav_kimlik=?"
            degerler = (sinav_kimlik,)
        with self._islem() as con:
            kagitlar = con.execute(sorgu, degerler).fetchall()
        baglanan = atlanan = 0
        for kagit in kagitlar:
            ad = (kagit["ogrenci_ad"] or "").strip()
            soyad = (kagit["ogrenci_soyad"] or "").strip()
            no = (kagit["ogrenci_no"] or "").strip()
            if not (no or ad):
                atlanan += 1  # kimliksiz kâğıt; öğretmen elle girmeli
                continue
            kimlik = self.ogrenci_bul_veya_ekle(
                ad, soyad, no, kagit["sinif"] or "", kagit["sube"] or ""
            )
            self.kagidi_ogrenciye_bagla(kagit["id"], kimlik)
            baglanan += 1
        return {"baglanan": baglanan, "atlanan": atlanan}

    def ogrenciler(self, sinif: str | None = None) -> list[sqlite3.Row]:
        sorgu = "SELECT * FROM ogrenci"
        degerler: tuple = ()
        if sinif:
            sorgu += " WHERE sinif=?"
            degerler = (sinif,)
        sorgu += " ORDER BY ad, soyad"
        with self._islem() as con:
            return con.execute(sorgu, degerler).fetchall()

    def ogrenci(self, ogrenci_kimlik: int) -> sqlite3.Row | None:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM ogrenci WHERE id=?", (int(ogrenci_kimlik),)
            ).fetchone()

    def ogrenci_kagitlari(self, ogrenci_kimlik: int) -> list[sqlite3.Row]:
        """Öğrencinin tüm sınavlardaki kâğıtları, kronolojik."""
        with self._islem() as con:
            return con.execute(
                "SELECT k.*, s.baslik AS sinav_baslik, s.ders AS sinav_ders "
                "FROM kagit k LEFT JOIN sinav s ON s.kimlik=k.sinav_kimlik "
                "WHERE k.ogrenci_kimlik=? ORDER BY k.olusturuldu, k.id",
                (int(ogrenci_kimlik),),
            ).fetchall()

    def ogrenilmis_kabul_kaydet(
        self,
        sinav_kimlik: str,
        soru_no: int,
        yazim: str,
        destek: int,
        onay_durumu: str = "oneri",
    ) -> None:
        """Öneriyi ekler/günceller; öğretmen onayı ayrı bir çağrıyla verilir."""
        with self._islem() as con:
            con.execute(
                "INSERT INTO ogrenilmis_kabul"
                "(sinav_kimlik, soru_no, yazim, destek, onay_durumu) "
                "VALUES (?,?,?,?,?) "
                "ON CONFLICT(sinav_kimlik, soru_no, yazim) DO UPDATE SET "
                "destek=excluded.destek",
                (sinav_kimlik, int(soru_no), yazim, int(destek), onay_durumu),
            )

    def ogrenilmis_kabul_onayla(self, kabul_id: int, onayli: bool = True) -> None:
        with self._islem() as con:
            con.execute(
                "UPDATE ogrenilmis_kabul SET onay_durumu=? WHERE id=?",
                ("onayli" if onayli else "reddedildi", int(kabul_id)),
            )

    def ogrenilmis_kabuller(
        self,
        sinav_kimlik: str,
        soru_no: int | None = None,
        onay_durumu: str | None = None,
    ) -> list[sqlite3.Row]:
        sorgu = "SELECT * FROM ogrenilmis_kabul WHERE sinav_kimlik=?"
        degerler: list = [sinav_kimlik]
        if soru_no is not None:
            sorgu += " AND soru_no=?"
            degerler.append(int(soru_no))
        if onay_durumu is not None:
            sorgu += " AND onay_durumu=?"
            degerler.append(onay_durumu)
        sorgu += " ORDER BY destek DESC, yazim"
        with self._islem() as con:
            return con.execute(sorgu, tuple(degerler)).fetchall()

    def suresi_dolan_kagitlar(self) -> list[sqlite3.Row]:
        with self._islem() as con:
            return con.execute(
                "SELECT * FROM kagit WHERE saklama_son_tarihi IS NOT NULL "
                "AND saklama_son_tarihi <= datetime('now') ORDER BY id"
            ).fetchall()

    def suresi_dolanlari_anonimlestir(self) -> int:
        """Süresi dolan doğrudan kimlikleri sil, akademik puan/denetimi koru."""
        with self._islem() as con:
            satirlar = con.execute(
                "SELECT * FROM kagit WHERE saklama_son_tarihi IS NOT NULL "
                "AND saklama_son_tarihi <= datetime('now')"
            ).fetchall()
            for satir in satirlar:
                con.execute(
                    "INSERT INTO denetim_kaydi"
                    "(varlik_turu,varlik_id,islem,neden) "
                    "VALUES ('kagit',?,'anonimlestirme','Saklama süresi doldu')",
                    (str(satir["id"]),),
                )
                con.execute(
                    # ogrenci_kimlik de silinmeli: aksi halde tek JOIN ile
                    # `ogrenci` tablosundan ad/soyad/numara geri gelir ve
                    # anonimleştirme fiilen etkisiz kalır.
                    "UPDATE kagit SET ogrenci_ad=NULL,ogrenci_soyad=NULL,"
                    "ogrenci_no=NULL,sinif=NULL,sube=NULL,kimlik_json='{}',"
                    "kaynak_dosya=NULL,yazar_grubu=NULL,egitim_izni=0,"
                    "ogrenci_kimlik=NULL "
                    "WHERE id=?",
                    (satir["id"],),
                )
            # Hiçbir kâğıdı kalmayan öğrenci kayıtları kişisel veri taşımaya
            # devam etmemeli.
            con.execute(
                "DELETE FROM ogrenci WHERE id NOT IN "
                "(SELECT ogrenci_kimlik FROM kagit WHERE ogrenci_kimlik IS NOT NULL)"
            )
        return len(satirlar)

    # --- Flywheel: eğitim verisi ---

    def altin_ornek_ekle(
        self,
        *,
        sinav_kimlik: str,
        soru_no: int,
        kirp_yolu: str | None,
        beklenen_metin: str | None,
        beklenen_puan: float | None,
        yazar_grubu: str = "",
        kaynak: str = "onay",
    ) -> str:
        """Altın örneği ekler veya günceller: 'eklendi' / 'guncellendi' / 'ayni'.

        Öğretmen sonradan metni/puanı düzeltip kâğıdı yeniden onaylarsa aynı
        kırpıntının etiketi eski kalmasın diye ekleme yerine upsert yapılır.
        ``kaynak`` etiketin nereden geldiğini taşır (onay / duzeltme / elle);
        ölçüm raporu bunu ayırmalı, çünkü güvenilirlikleri aynı değil.
        """
        with self._islem() as con:
            mevcut = con.execute(
                "SELECT id, beklenen_metin, beklenen_puan FROM altin_ornek "
                "WHERE sinav_kimlik=? AND soru_no=? AND kirp_yolu IS ?",
                (sinav_kimlik, soru_no, kirp_yolu),
            ).fetchone()
            if mevcut:
                if (
                    mevcut["beklenen_metin"] == beklenen_metin
                    and mevcut["beklenen_puan"] == beklenen_puan
                ):
                    return "ayni"
                con.execute(
                    "UPDATE altin_ornek SET beklenen_metin=?, beklenen_puan=?, "
                    "yazar_grubu=?, kaynak=? WHERE id=?",
                    (
                        beklenen_metin, beklenen_puan, yazar_grubu,
                        kaynak, mevcut["id"],
                    ),
                )
                return "guncellendi"
            con.execute(
                "INSERT INTO altin_ornek"
                "(sinav_kimlik, soru_no, kirp_yolu, beklenen_metin, "
                "beklenen_puan, yazar_grubu, kaynak) VALUES (?,?,?,?,?,?,?)",
                (
                    sinav_kimlik, soru_no, kirp_yolu, beklenen_metin,
                    beklenen_puan, yazar_grubu, kaynak,
                ),
            )
        return "eklendi"

    def sinav_kagit_ozetleri(self, sinav_kimlik: str) -> list[sqlite3.Row]:
        """Kâğıt başına toplam/azami puan ve bekleyen sayısı, TEK sorguda.

        Sınav sayfası bunları kâğıt başına iki ayrı sorguyla topluyordu
        (30 kâğıt = 60 sorgu, her biri kutu tablosunu baştan tarayarak).
        Sıra ``kagitlar()`` ile aynı tutulur; ekrandaki kâğıt sırası değişmez.
        """
        with self._islem() as con:
            return con.execute(
                "SELECT g.*, "
                "COALESCE(SUM(k.son_puan), 0) toplam_puan, "
                "COALESCE(SUM(k.max_puan), 0) azami_puan, "
                "COALESCE(SUM(k.incele), 0) bekleyen "
                "FROM kagit g LEFT JOIN kutu k ON k.kagit_id = g.id "
                "WHERE g.sinav_kimlik=? "
                # g.id birincil anahtar olduğu için diğer g.* sütunları
                # SQLite'ta belirlenimli gelir (bare column kuralı).
                "GROUP BY g.id ORDER BY g.id DESC",
                (sinav_kimlik,),
            ).fetchall()

    def duzeltilmis_kutular(
        self, sinav_kimlik: str | None = None
    ) -> list[sqlite3.Row]:
        """Öğretmenin metnini düzelttiği, kırpıntısı duran kutular.

        Kâğıdın onaylanmış olması ŞART DEĞİL: gerçek etiket öğretmenin
        yazdığı metindir; onay, tüm-kâğıt iş akışının ayrı bir adımıdır.
        İkisini bağlamak düzeltilmiş kutuların etiket değerini rehin tutuyordu.
        """
        sorgu = (
            "SELECT k.*, g.sinav_kimlik, g.yazar_grubu, g.onaylandi "
            "FROM kutu k JOIN kagit g ON k.kagit_id=g.id "
            "WHERE k.duzeltilmis_metin IS NOT NULL "
            "AND TRIM(k.duzeltilmis_metin) != '' "
            "AND k.kirp_yolu IS NOT NULL"
        )
        params: tuple = ()
        if sinav_kimlik:
            sorgu += " AND g.sinav_kimlik=?"
            params = (sinav_kimlik,)
        with self._islem() as con:
            return con.execute(sorgu + " ORDER BY k.id", params).fetchall()

    def altin_ornekler(self, sinav_kimlik: str | None = None) -> list[sqlite3.Row]:
        sorgu = "SELECT * FROM altin_ornek"
        params: tuple = ()
        if sinav_kimlik:
            sorgu += " WHERE sinav_kimlik=?"
            params = (sinav_kimlik,)
        with self._islem() as con:
            return con.execute(sorgu + " ORDER BY id", params).fetchall()

    def egitim_verisi_disa_aktar(self, yol: str | Path, sinav_kimlik: str | None = None) -> int:
        """İzinli, anonim-yazarlı ve insan-düzeltilmiş örnekleri JSONL yazar."""
        sorgu = (
            "SELECT k.kirp_yolu, k.duzeltilmis_metin metin, g.yazar_grubu, "
            "g.sinav_kimlik, k.soru_no "
            "FROM kutu k JOIN kagit g ON k.kagit_id=g.id "
            "WHERE k.kirp_yolu IS NOT NULL AND k.duzeltilmis_metin IS NOT NULL "
            "AND TRIM(k.duzeltilmis_metin) != '' "
            "AND g.egitim_izni=1 AND g.yazar_grubu IS NOT NULL "
            "AND TRIM(g.yazar_grubu) != ''"
        )
        params: tuple = ()
        if sinav_kimlik:
            sorgu += " AND g.sinav_kimlik=?"
            params = (sinav_kimlik,)
        with self._islem() as con:
            satirlar = con.execute(sorgu, params).fetchall()
        n, yazarlar = 0, set()
        yol = Path(yol)
        # Kırpıntısı diskte olmayan düzeltmeler sessizce kaybolmasın: sayısı ve
        # yolları manifeste yazılır, çağıran raporlayabilir.
        atlanan: list[str] = []
        with yol.open("w", encoding="utf-8") as f:
            for s in satirlar:
                if s["kirp_yolu"] and Path(s["kirp_yolu"]).exists():
                    f.write(json.dumps(
                        {
                            "image": s["kirp_yolu"],
                            "text": s["metin"],
                            "writer_id": s["yazar_grubu"],
                            "exam_id": s["sinav_kimlik"],
                            "question_id": s["soru_no"],
                            "source": "teacher-reviewed-real-exam",
                        },
                        ensure_ascii=False,
                    ) + "\n")
                    yazarlar.add(s["yazar_grubu"])
                    n += 1
                else:
                    atlanan.append(str(s["kirp_yolu"] or f"soru {s['soru_no']}"))
        yol.with_suffix(yol.suffix + ".manifest.json").write_text(
            json.dumps(
                {
                    "real_handwriting": True,
                    "human_transcribed": True,
                    "consent_required": True,
                    "contains_direct_identifiers": False,
                    "samples": n,
                    "writers": len(yazarlar),
                    "split_requirement": "writer_id-disjoint",
                    "skipped_missing_crops": atlanan,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        return n
