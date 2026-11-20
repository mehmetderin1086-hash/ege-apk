"""SQLite deposu: referans örnekler, üretilen çözümler, önbellek, eğitim sürümleri.

ORM yok — şema burada tek yerde tanımlı, göç (`_gocleri_uygula`) sürüm tablosuyla
yürür. Tüm yazmalar `_islem()` bağlam yöneticisinden geçer.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from .metin import esitle as metin_esitle
from .metin import imza as metin_imzasi
from .modeller import Cozum, Ornek, Pasaj

SEMA_SURUMU = 5


def _simdi() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


class Depo:
    """Tek dosyalık SQLite deposu."""

    def __init__(self, yol: str | Path):
        self.yol = Path(yol)
        self.yol.parent.mkdir(parents=True, exist_ok=True)
        self._baglanti = sqlite3.connect(str(self.yol), check_same_thread=False)
        self._baglanti.row_factory = sqlite3.Row
        # Tek bağlantı birden çok thread'den (FastAPI senkron rotaları bir thread
        # havuzunda koşar) kullanıldığında transaction sınırları bağlantı
        # genelindedir: bir isteğin commit'i başka bir isteğin yarım işlemini de
        # kapsayabilir. Bu kilit tüm erişimi seri hale getirerek bunu engeller.
        self._kilit = threading.RLock()
        self._baglanti.execute("PRAGMA foreign_keys = ON")
        self._baglanti.execute("PRAGMA journal_mode = WAL")
        self._baglanti.execute("PRAGMA busy_timeout = 5000")
        # Türkçe katlamayı SQL'e taşır: SQLite'ın LIKE'ı "İ/ı" ayrımını bilmez,
        # Python'da süzmek ise tüm satırları nesneye çevirmeyi gerektirirdi.
        self._baglanti.create_function(
            "esitle", 1, lambda m: metin_esitle(m or ""), deterministic=True
        )
        self._semayi_kur()

    # --- altyapı ---

    @contextmanager
    def _islem(self) -> Iterator[sqlite3.Connection]:
        with self._kilit:
            try:
                with self._baglanti:
                    yield self._baglanti
            except sqlite3.IntegrityError as exc:
                raise ValueError(str(exc)) from exc

    def _sorgu(self, sql: str, parametreler: tuple | list = ()) -> list[sqlite3.Row]:
        """Okuma sorgusu — yazmalarla aynı kilidi paylaşır."""
        with self._kilit:
            return list(self._baglanti.execute(sql, parametreler))

    def _tek(self, sql: str, parametreler: tuple | list = ()) -> sqlite3.Row | None:
        with self._kilit:
            return self._baglanti.execute(sql, parametreler).fetchone()

    def kapat(self) -> None:
        with self._kilit:
            self._baglanti.close()

    def _semayi_kur(self) -> None:
        with self._islem() as b:
            b.executescript(
                """
                CREATE TABLE IF NOT EXISTS sema_bilgi (
                    anahtar TEXT PRIMARY KEY,
                    deger   TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS ornek (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    soru        TEXT NOT NULL,
                    soru_imza   TEXT NOT NULL UNIQUE,
                    secenekler  TEXT NOT NULL DEFAULT '{}',
                    cozum       TEXT NOT NULL,
                    cevap       TEXT NOT NULL DEFAULT '',
                    cevap_turu  TEXT NOT NULL DEFAULT 'acik_uclu',
                    konu        TEXT NOT NULL DEFAULT '',
                    cozum_turu  TEXT NOT NULL DEFAULT '',
                    etiketler   TEXT NOT NULL DEFAULT '[]',
                    kaynak      TEXT NOT NULL DEFAULT '',
                    etiket_kaynagi TEXT NOT NULL DEFAULT 'elle',
                    -- Soru görselinin imzası; dosyanın kendisi
                    -- <kök>/gorseller/<imza>.png içinde (bkz. gorsel.py).
                    gorsel      TEXT NOT NULL DEFAULT '',
                    -- Kanıt havuzundan dışlama bayrağı. `aktif=0` ile
                    -- KARIŞTIRILMAMALI: `aktif=0` örneği tümden emekliye
                    -- ayırır, `kanit_disi=1` ise örneği hafızada ve arayüzde
                    -- tutar, yalnız RAG kanıtı olmaktan men eder.
                    kanit_disi  INTEGER NOT NULL DEFAULT 0,
                    -- 0-1 arası kanıt kalite skoru; -1 = hiç puanlanmadı.
                    kalite      REAL NOT NULL DEFAULT -1,
                    -- MEB Maarif Modeli öğrenme çıktısı kodu (ör. BİY.9.1.1).
                    kazanim     TEXT NOT NULL DEFAULT '',
                    aktif       INTEGER NOT NULL DEFAULT 1,
                    olusturma   TEXT NOT NULL,
                    guncelleme  TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_ornek_konu ON ornek(konu);
                CREATE INDEX IF NOT EXISTS ix_ornek_cozum_turu ON ornek(cozum_turu);
                -- `ix_ornek_kazanim` bilinçli olarak burada DEĞİL: bu betik eski
                -- bir veritabanında da koşuyor ve orada `kazanim` sütunu henüz
                -- yok (CREATE TABLE IF NOT EXISTS sütun eklemez). İndeks, sütunu
                -- ekleyen göçün hemen ardında oluşturuluyor.

                CREATE TABLE IF NOT EXISTS cozum (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    soru            TEXT NOT NULL,
                    soru_imza       TEXT NOT NULL,
                    cozum_json      TEXT NOT NULL,
                    cevap           TEXT NOT NULL DEFAULT '',
                    guven           REAL NOT NULL DEFAULT 0,
                    incele          INTEGER NOT NULL DEFAULT 0,
                    uretim_yontemi  TEXT NOT NULL DEFAULT 'model',
                    model           TEXT NOT NULL DEFAULT '',
                    onay_durumu     TEXT NOT NULL DEFAULT 'bekliyor',
                    duzeltme        TEXT NOT NULL DEFAULT '',
                    olusturma       TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_cozum_imza ON cozum(soru_imza);
                CREATE INDEX IF NOT EXISTS ix_cozum_onay ON cozum(onay_durumu);

                CREATE TABLE IF NOT EXISTS cozum_onbellek (
                    soru_imza     TEXT PRIMARY KEY,
                    soru          TEXT NOT NULL,
                    baglam_imza   TEXT NOT NULL DEFAULT '',
                    gomme         BLOB,
                    cozum_json    TEXT NOT NULL,
                    isabet        INTEGER NOT NULL DEFAULT 0,
                    olusturma     TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS egitim_surumu (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    etiket        TEXT NOT NULL,
                    yol           TEXT NOT NULL,
                    ornek_sayisi  INTEGER NOT NULL DEFAULT 0,
                    dogrulama_sayisi INTEGER NOT NULL DEFAULT 0,
                    notlar        TEXT NOT NULL DEFAULT '',
                    olusturma     TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS denetim_kaydi (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    zaman     TEXT NOT NULL,
                    eylem     TEXT NOT NULL,
                    ayrinti   TEXT NOT NULL DEFAULT ''
                );

                -- Kör değerlendirme koşularının geçmişi. Ayrı tablo şart:
                -- ölçümün değeri tek bir sayıda değil, SÜRÜMLER ARASI FARKTA
                -- (taban model vs ince ayarlı). Karşılaştırma yapılabilmesi
                -- için koşuların saklanması gerekiyor.
                CREATE TABLE IF NOT EXISTS kosu (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    etiket        TEXT NOT NULL DEFAULT '',
                    model         TEXT NOT NULL DEFAULT '',
                    ornek_sayisi  INTEGER NOT NULL DEFAULT 0,
                    dogru         INTEGER NOT NULL DEFAULT 0,
                    dogruluk      REAL NOT NULL DEFAULT 0,
                    ortusme       REAL NOT NULL DEFAULT 0,
                    guven         REAL NOT NULL DEFAULT 0,
                    inceleme_orani REAL NOT NULL DEFAULT 0,
                    tur_bazli     TEXT NOT NULL DEFAULT '{}',
                    -- Hangi dondurulmuş dilim üzerinde koşuldu ve o dilimin
                    -- imzası. İmza olmadan iki koşunun aynı soruları gördüğü
                    -- doğrulanamaz ve fark raporu anlamsızlaşır.
                    dilim         TEXT NOT NULL DEFAULT '',
                    dilim_imzasi  TEXT NOT NULL DEFAULT '',
                    -- `olcumler/` altındaki ayrıntılı kaydın yolu.
                    dosya         TEXT NOT NULL DEFAULT '',
                    olusturma     TEXT NOT NULL
                );

                -- Görsellerin VLM tarafından üretilmiş yapılandırılmış betimi.
                -- Anahtarda MODEL ADI var: VLM değiştiğinde eski betim dönerse
                -- sürüm karşılaştırması sessizce anlamını yitirir (aynı gerekçe
                -- `cozucu.onbellek_kimligi` içinde de geçerli).
                CREATE TABLE IF NOT EXISTS sekil_betimi (
                    imza       TEXT NOT NULL,
                    model      TEXT NOT NULL,
                    betim_json TEXT NOT NULL,
                    olusturma  TEXT NOT NULL,
                    PRIMARY KEY (imza, model)
                );

                -- Ders kitabı pasajları. `ornek` tablosundan AYRI: pasaj bir
                -- soru-çözüm çifti değil, dayanılacak bir bilgi kaynağı.
                -- `metin_imza` yinelenen sayfaları (aynı bölüm iki kez
                -- taranmış olabilir) sessizce elemek için.
                CREATE TABLE IF NOT EXISTS pasaj (
                    id         INTEGER PRIMARY KEY AUTOINCREMENT,
                    metin      TEXT NOT NULL,
                    metin_imza TEXT NOT NULL UNIQUE,
                    kaynak     TEXT NOT NULL DEFAULT '',
                    baslik     TEXT NOT NULL DEFAULT '',
                    sayfa      INTEGER,
                    konu       TEXT NOT NULL DEFAULT '',
                    aktif      INTEGER NOT NULL DEFAULT 1,
                    olusturma  TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_pasaj_kaynak ON pasaj(kaynak);
                CREATE INDEX IF NOT EXISTS ix_pasaj_konu ON pasaj(konu);
                """
            )
            self._gocleri_uygula(b)
            b.execute(
                "INSERT OR REPLACE INTO sema_bilgi(anahtar, deger) VALUES('surum', ?)",
                (str(SEMA_SURUMU),),
            )

    @staticmethod
    def _gocleri_uygula(b: sqlite3.Connection) -> None:
        """`CREATE TABLE IF NOT EXISTS` eski dosyalara sütun eklemez; eksikleri burada tamamlarız."""
        mevcut = {
            satir["name"] for satir in b.execute("PRAGMA table_info(cozum_onbellek)")
        }
        if mevcut and "baglam_imza" not in mevcut:
            b.execute(
                "ALTER TABLE cozum_onbellek ADD COLUMN baglam_imza TEXT NOT NULL DEFAULT ''"
            )
            # v1 satırları zaten erişilemez: anahtar biçimi değişti (cevap türü
            # etiketi eklendi) ve şık eşlemeleri bilinmiyor. Tutmak yalnız
            # `ozet()` önbellek sayacını şişirirdi; önbellek türetilmiş veridir,
            # silmek kayıp değil.
            b.execute("DELETE FROM cozum_onbellek")

        # v3 → v4: soru görseli. Var olan örnekler görselsiz kalır (boş dizge),
        # bu doğru davranış — eski sorular zaten metin sorusuydu.
        ornek_sutunlari = {satir["name"] for satir in b.execute("PRAGMA table_info(ornek)")}
        if ornek_sutunlari and "gorsel" not in ornek_sutunlari:
            b.execute("ALTER TABLE ornek ADD COLUMN gorsel TEXT NOT NULL DEFAULT ''")

        # v4 → v5: kanıt kalite bayrakları ve kazanım kodu. Varsayılanlar
        # bilinçli olarak "etkisiz": `kanit_disi=0` hiçbir örneği dışlamaz,
        # `kalite=-1` "hiç puanlanmadı" demektir ve kalite kapısı bunu süzmez.
        # Yani göç tek başına davranışı DEĞİŞTİRMEZ.
        for sutun, tanim in (
            ("kanit_disi", "INTEGER NOT NULL DEFAULT 0"),
            ("kalite", "REAL NOT NULL DEFAULT -1"),
            ("kazanim", "TEXT NOT NULL DEFAULT ''"),
        ):
            if ornek_sutunlari and sutun not in ornek_sutunlari:
                b.execute(f"ALTER TABLE ornek ADD COLUMN {sutun} {tanim}")
        if ornek_sutunlari:
            b.execute("CREATE INDEX IF NOT EXISTS ix_ornek_kazanim ON ornek(kazanim)")

        # v4 → v5: koşuya dilim kimliği. Eski koşular dilimsiz kalır; fark
        # raporu bunları "karşılaştırılamaz" sayar, sessizce eşleştirmez.
        kosu_sutunlari = {satir["name"] for satir in b.execute("PRAGMA table_info(kosu)")}
        for sutun in ("dilim", "dilim_imzasi", "dosya"):
            if kosu_sutunlari and sutun not in kosu_sutunlari:
                b.execute(f"ALTER TABLE kosu ADD COLUMN {sutun} TEXT NOT NULL DEFAULT ''")

    def denetim_yaz(self, eylem: str, ayrinti: str = "") -> None:
        with self._islem() as b:
            b.execute(
                "INSERT INTO denetim_kaydi(zaman, eylem, ayrinti) VALUES(?,?,?)",
                (_simdi(), eylem, ayrinti),
            )

    # --- alınmış kaynaklar ---
    #
    # Ayrı tablo açılmadı: bu, tam olarak denetim kaydının işi — "şu içerik şu
    # tarihte alındı". Kaynak imzası dosya adına değil İÇERİĞE bağlı olduğundan
    # yeniden adlandırılan ya da başka klasöre kopyalanan aynı kitap tekrar
    # işlenmez.
    _ALIM_EYLEMI = "alim_kaynak"

    def kaynak_alindi_mi(self, imza: str) -> bool:
        if not imza:
            return False
        return bool(
            self._sorgu(
                "SELECT 1 FROM denetim_kaydi WHERE eylem=? AND ayrinti=? LIMIT 1",
                (self._ALIM_EYLEMI, imza),
            )
        )

    def kaynagi_isaretle(self, imza: str) -> None:
        if imza:
            self.denetim_yaz(self._ALIM_EYLEMI, imza)

    # --- değerlendirme koşuları ---

    def kosu_kaydet(
        self,
        ozet,
        *,
        etiket: str = "",
        model: str = "",
        dilim: str = "",
        dilim_imzasi: str = "",
        dosya: str = "",
    ) -> int:
        """Bir `KosuOzeti`'ni geçmişe yazar ve kimliğini döndürür.

        Dilim alanları varsayılanlı: `webapp` tarafındaki mevcut çağrı
        değişmeden çalışsın diye. Dilimsiz koşular fark raporunda
        karşılaştırılamaz sayılır.
        """
        import json as _json

        with self._islem() as b:
            imlec = b.execute(
                "INSERT INTO kosu(etiket, model, ornek_sayisi, dogru, dogruluk,"
                " ortusme, guven, inceleme_orani, tur_bazli, dilim, dilim_imzasi,"
                " dosya, olusturma)"
                " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    etiket, model, ozet.toplam, ozet.dogru, ozet.dogruluk,
                    ozet.ortalama_ortusme, ozet.ortalama_guven, ozet.inceleme_orani,
                    _json.dumps(ozet.tur_bazli, ensure_ascii=False),
                    dilim, dilim_imzasi, dosya, _simdi(),
                ),
            )
            return int(imlec.lastrowid or 0)

    # --- şekil betimleri (VLM çıktısı önbelleği) ---

    def betim_oku(self, imza: str, model: str) -> dict | None:
        """Görselin bu modelce üretilmiş betimi; yoksa None."""
        import json as _json

        satir = self._tek(
            "SELECT betim_json FROM sekil_betimi WHERE imza = ? AND model = ?",
            (imza, model),
        )
        if not satir:
            return None
        try:
            return dict(_json.loads(satir["betim_json"]))
        except (ValueError, TypeError):
            return None

    def betim_yaz(self, imza: str, model: str, betim: dict) -> None:
        import json as _json

        with self._islem() as b:
            b.execute(
                "INSERT OR REPLACE INTO sekil_betimi(imza, model, betim_json, olusturma)"
                " VALUES(?,?,?,?)",
                (imza, model, _json.dumps(betim, ensure_ascii=False), _simdi()),
            )

    def betimli_imzalar(self, model: str) -> set[str]:
        """Bu model için betimi zaten üretilmiş görsel imzaları."""
        satirlar = self._sorgu(
            "SELECT imza FROM sekil_betimi WHERE model = ?", (model,)
        )
        return {s["imza"] for s in satirlar}

    def kosular(self, limit: int = 20) -> list[dict]:
        import json as _json

        satirlar = self._sorgu(
            "SELECT * FROM kosu ORDER BY id DESC LIMIT ?", (int(limit),)
        )
        kayitlar = []
        for satir in satirlar:
            kayit = dict(satir)
            kayit["tur_bazli"] = _json.loads(kayit.get("tur_bazli") or "{}")
            kayitlar.append(kayit)
        return kayitlar

    def kosu(self, kosu_id: int) -> dict | None:
        for kayit in self.kosular(limit=1000):
            if kayit["id"] == kosu_id:
                return kayit
        return None

    # --- örnekler ---

    def ornek_ekle(self, ornek: Ornek, *, uzerine_yaz: bool = False) -> int:
        """Örneği ekler; aynı soru zaten varsa `uzerine_yaz` ile günceller.

        Dönen değer örnek kimliğidir. Yinelenen soru `uzerine_yaz=False` iken
        `ValueError` yükseltir — sessizce yoksaymak hafızayı bozar.
        """
        simdi = _simdi()
        anahtar = metin_imzasi(ornek.soru)
        mevcut = self._tek("SELECT id FROM ornek WHERE soru_imza = ?", (anahtar,))
        if mevcut and not uzerine_yaz:
            raise ValueError(f"Bu soru zaten kayıtlı (örnek #{mevcut['id']}).")
        veri = (
            ornek.soru,
            anahtar,
            json.dumps(ornek.secenekler, ensure_ascii=False),
            ornek.cozum,
            ornek.cevap,
            ornek.cevap_turu,
            ornek.konu,
            ornek.cozum_turu,
            json.dumps(ornek.etiketler, ensure_ascii=False),
            ornek.kaynak,
            ornek.etiket_kaynagi,
            ornek.gorsel,
            int(bool(ornek.kanit_disi)),
            float(ornek.kalite),
            ornek.kazanim,
            simdi,
        )
        with self._islem() as b:
            if mevcut:
                b.execute(
                    """UPDATE ornek SET soru=?, soru_imza=?, secenekler=?, cozum=?,
                       cevap=?, cevap_turu=?, konu=?, cozum_turu=?, etiketler=?,
                       kaynak=?, etiket_kaynagi=?, gorsel=?, kanit_disi=?, kalite=?,
                       kazanim=?, guncelleme=?, aktif=1
                       WHERE id=?""",
                    (*veri, mevcut["id"]),
                )
                return int(mevcut["id"])
            imlec = b.execute(
                """INSERT INTO ornek(soru, soru_imza, secenekler, cozum, cevap,
                   cevap_turu, konu, cozum_turu, etiketler, kaynak, etiket_kaynagi,
                   gorsel, kanit_disi, kalite, kazanim, guncelleme, olusturma)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (*veri, simdi),
            )
            return int(imlec.lastrowid)

    def _ornek_kur(self, satir: sqlite3.Row) -> Ornek:
        return Ornek(
            id=int(satir["id"]),
            soru=satir["soru"],
            secenekler=json.loads(satir["secenekler"] or "{}"),
            cozum=satir["cozum"],
            cevap=satir["cevap"],
            cevap_turu=satir["cevap_turu"],
            konu=satir["konu"],
            cozum_turu=satir["cozum_turu"],
            etiketler=json.loads(satir["etiketler"] or "[]"),
            kaynak=satir["kaynak"],
            etiket_kaynagi=satir["etiket_kaynagi"],
            # `.keys()` şart: sqlite3.Row'da `in` sütun adını DEĞİL değeri
            # arar. Eski bir satır (göç öncesi okunmuş) sütunu taşımayabilir.
            gorsel=(satir["gorsel"] if "gorsel" in satir.keys() else "") or "",  # noqa: SIM118
            kanit_disi=bool(satir["kanit_disi"] if "kanit_disi" in satir.keys() else 0),  # noqa: SIM118
            kalite=float(satir["kalite"] if "kalite" in satir.keys() else -1.0),  # noqa: SIM118
            kazanim=(satir["kazanim"] if "kazanim" in satir.keys() else "") or "",  # noqa: SIM118
            olusturma=satir["olusturma"],
        )

    @staticmethod
    def _arama_deseni(ara: str) -> str:
        """LIKE deseni — kullanıcının yazdığı `%` ve `_` joker olmamalı.

        Kaçışsız bırakıldığında "50%" araması her kaydı, "m_toz" ise "mitoz"u
        getiriyordu; sonuç listesi de sayfalama toplamı da yanlış çıkıyordu.
        """
        katlanmis = metin_esitle(ara.strip())
        for karakter in ("\\", "%", "_"):
            katlanmis = katlanmis.replace(karakter, "\\" + karakter)
        return f"%{katlanmis}%"

    @staticmethod
    def _ornek_suzgeci(
        yalniz_aktif: bool, ara: str, konu: str, cozum_turu: str
    ) -> tuple[str, list]:
        kosullar: list[str] = []
        parametreler: list = []
        if yalniz_aktif:
            kosullar.append("aktif = 1")
        if ara.strip():
            kosullar.append(
                "(esitle(soru) LIKE ? ESCAPE '\\' OR esitle(konu) LIKE ? ESCAPE '\\')"
            )
            desen = Depo._arama_deseni(ara)
            parametreler += [desen, desen]
        if konu.strip():
            kosullar.append("esitle(konu) = ?")
            parametreler.append(metin_esitle(konu.strip()))
        if cozum_turu.strip():
            kosullar.append("cozum_turu = ?")
            parametreler.append(cozum_turu.strip())
        nerede = (" WHERE " + " AND ".join(kosullar)) if kosullar else ""
        return nerede, parametreler

    def ornekler(
        self,
        *,
        yalniz_aktif: bool = True,
        limit: int | None = None,
        offset: int = 0,
        ara: str = "",
        konu: str = "",
        cozum_turu: str = "",
    ) -> list[Ornek]:
        """Süzme SQL'de yapılır; Python'da süzmek her satırı gereksizce nesneye çevirirdi."""
        nerede, parametreler = self._ornek_suzgeci(yalniz_aktif, ara, konu, cozum_turu)
        sorgu = f"SELECT * FROM ornek{nerede} ORDER BY id"
        if limit:
            sorgu += " LIMIT ? OFFSET ?"
            parametreler += [int(limit), max(0, int(offset))]
        return [self._ornek_kur(s) for s in self._sorgu(sorgu, parametreler)]

    def ornek_say(
        self,
        *,
        yalniz_aktif: bool = True,
        ara: str = "",
        konu: str = "",
        cozum_turu: str = "",
    ) -> int:
        """Sayfalamanın toplamı — `ornekler()` ile birebir aynı süzgeci kullanır."""
        nerede, parametreler = self._ornek_suzgeci(yalniz_aktif, ara, konu, cozum_turu)
        return int(self._tek(f"SELECT COUNT(*) FROM ornek{nerede}", parametreler)[0])

    def ornek(self, ornek_id: int) -> Ornek | None:
        satir = self._tek("SELECT * FROM ornek WHERE id = ?", (int(ornek_id),))
        return self._ornek_kur(satir) if satir else None

    # --- ders kitabı pasajları ---

    @staticmethod
    def _pasaj_kur(satir) -> Pasaj:
        return Pasaj(
            metin=satir["metin"],
            kaynak=satir["kaynak"],
            baslik=satir["baslik"],
            sayfa=satir["sayfa"],
            konu=satir["konu"],
            id=satir["id"],
            olusturma=satir["olusturma"],
        )

    def pasaj_ekle(self, pasaj: Pasaj) -> int | None:
        """Pasajı ekler; birebir aynısı zaten varsa `None` döner.

        Yinelenen pasaj hata değil BEKLENEN durum: aynı kitap yeniden
        alındığında ya da bölümler örtüştüğünde aynı metin tekrar gelir.
        Hata yükseltmek toplu alımı ortasında durdururdu.
        """
        metin = (pasaj.metin or "").strip()
        if not metin:
            return None
        anahtar = metin_imzasi(metin)
        if self._tek("SELECT id FROM pasaj WHERE metin_imza = ?", (anahtar,)):
            return None
        simdi = _simdi()
        with self._islem() as b:
            imlec = b.execute(
                "INSERT INTO pasaj(metin, metin_imza, kaynak, baslik, sayfa, konu, "
                "olusturma) VALUES(?,?,?,?,?,?,?)",
                (
                    metin,
                    anahtar,
                    pasaj.kaynak,
                    pasaj.baslik,
                    int(pasaj.sayfa) if pasaj.sayfa else None,
                    pasaj.konu,
                    simdi,
                ),
            )
        return int(imlec.lastrowid or 0)

    def pasajlar(
        self, *, kaynak: str = "", yalniz_aktif: bool = True, limit: int | None = None
    ) -> list[Pasaj]:
        kosullar, parametreler = [], []
        if yalniz_aktif:
            kosullar.append("aktif = 1")
        if kaynak:
            kosullar.append("kaynak = ?")
            parametreler.append(kaynak)
        nerede = f" WHERE {' AND '.join(kosullar)}" if kosullar else ""
        sorgu = f"SELECT * FROM pasaj{nerede} ORDER BY id"
        if limit:
            sorgu += " LIMIT ?"
            parametreler.append(int(limit))
        return [self._pasaj_kur(s) for s in self._sorgu(sorgu, parametreler)]

    def pasaj_say(self, *, kaynak: str = "") -> int:
        if kaynak:
            return int(
                self._tek(
                    "SELECT COUNT(*) FROM pasaj WHERE aktif = 1 AND kaynak = ?",
                    (kaynak,),
                )[0]
            )
        return int(self._tek("SELECT COUNT(*) FROM pasaj WHERE aktif = 1")[0])

    def pasaj_kaynaklari(self) -> dict[str, int]:
        """Kaynak adı → pasaj sayısı."""
        return {
            s["kaynak"] or "(adsız)": int(s["adet"])
            for s in self._sorgu(
                "SELECT kaynak, COUNT(*) AS adet FROM pasaj WHERE aktif = 1 "
                "GROUP BY kaynak ORDER BY adet DESC",
                [],
            )
        }

    def ornek_sorusuyla(self, soru: str) -> Ornek | None:
        """Aktif, kanıt dışı olmayan birebir soru kaydını döndür."""
        satir = self._tek(
            """SELECT * FROM ornek
               WHERE soru_imza = ? AND aktif = 1 AND kanit_disi = 0
               LIMIT 1""",
            (metin_imzasi(soru),),
        )
        return self._ornek_kur(satir) if satir else None

    def ornek_guncelle(self, ornek: Ornek) -> None:
        if ornek.id is None:
            raise ValueError("Güncellenecek örneğin kimliği yok.")
        with self._islem() as b:
            b.execute(
                """UPDATE ornek SET soru=?, soru_imza=?, secenekler=?, cozum=?, cevap=?,
                   cevap_turu=?, konu=?, cozum_turu=?, etiketler=?, kaynak=?,
                   etiket_kaynagi=?, gorsel=?, kanit_disi=?, kalite=?, kazanim=?,
                   guncelleme=? WHERE id=?""",
                (
                    ornek.soru,
                    metin_imzasi(ornek.soru),
                    json.dumps(ornek.secenekler, ensure_ascii=False),
                    ornek.cozum,
                    ornek.cevap,
                    ornek.cevap_turu,
                    ornek.konu,
                    ornek.cozum_turu,
                    json.dumps(ornek.etiketler, ensure_ascii=False),
                    ornek.kaynak,
                    ornek.etiket_kaynagi,
                    ornek.gorsel,
                    int(bool(ornek.kanit_disi)),
                    float(ornek.kalite),
                    ornek.kazanim,
                    _simdi(),
                    int(ornek.id),
                ),
            )

    def ornek_sil(self, ornek_id: int) -> None:
        """Örneği pasife alır (silmez) — geçmiş çözümlerin atıfları kırılmasın."""
        with self._islem() as b:
            b.execute("UPDATE ornek SET aktif = 0, guncelleme = ? WHERE id = ?",
                      (_simdi(), int(ornek_id)))

    def ornek_sayisi(self, *, yalniz_aktif: bool = True) -> int:
        sorgu = "SELECT COUNT(*) FROM ornek" + (" WHERE aktif = 1" if yalniz_aktif else "")
        return int(self._tek(sorgu)[0])

    # --- çözümler ---

    def cozum_kaydet(self, cozum: Cozum, *, kaynak_kimligi: str = "") -> int:
        """Çözümü kaydet; verilirse dış iş kimliğiyle idempotent güncelle.

        Kes ve Çöz iş DB'si ile bu DB aynı transaction'ı paylaşamaz. Süreç iki
        yazma arasında çökerse aynı ``iş:sıra`` yeniden işlendiğinde ikinci
        satır açmak yerine ilk satır güncellenir.
        """
        kaynak_kimligi = kaynak_kimligi.strip()[:300]
        if kaynak_kimligi:
            cozum.dogrulama["kaynak_kimligi"] = kaynak_kimligi
        with self._islem() as b:
            if kaynak_kimligi:
                mevcut = b.execute(
                    """SELECT id FROM cozum
                       WHERE json_extract(cozum_json, '$.dogrulama.kaynak_kimligi') = ?
                       ORDER BY id LIMIT 1""",
                    (kaynak_kimligi,),
                ).fetchone()
                if mevcut is not None:
                    cozum_id = int(mevcut["id"])
                    b.execute(
                        """UPDATE cozum SET soru=?, soru_imza=?, cozum_json=?,
                           cevap=?, guven=?, incele=?, uretim_yontemi=?, model=?
                           WHERE id=?""",
                        (
                            cozum.soru,
                            metin_imzasi(cozum.soru),
                            cozum.json(),
                            cozum.cevap,
                            float(cozum.guven),
                            int(bool(cozum.incele)),
                            cozum.uretim_yontemi,
                            cozum.model,
                            cozum_id,
                        ),
                    )
                    return cozum_id
            imlec = b.execute(
                """INSERT INTO cozum(soru, soru_imza, cozum_json, cevap, guven, incele,
                   uretim_yontemi, model, olusturma)
                   VALUES(?,?,?,?,?,?,?,?,?)""",
                (
                    cozum.soru,
                    metin_imzasi(cozum.soru),
                    cozum.json(),
                    cozum.cevap,
                    float(cozum.guven),
                    int(bool(cozum.incele)),
                    cozum.uretim_yontemi,
                    cozum.model,
                    _simdi(),
                ),
            )
            return int(imlec.lastrowid)

    def cozum(self, cozum_id: int) -> tuple[Cozum, sqlite3.Row] | None:
        satir = self._tek("SELECT * FROM cozum WHERE id = ?", (int(cozum_id),))
        if not satir:
            return None
        nesne = Cozum.sozlukten(json.loads(satir["cozum_json"]))
        nesne.id = int(satir["id"])
        return nesne, satir

    @staticmethod
    def _cozum_suzgeci(
        onay_durumu: str | None, ara: str, yalniz_incele: bool
    ) -> tuple[str, list]:
        kosullar: list[str] = []
        parametreler: list = []
        if onay_durumu:
            kosullar.append("onay_durumu = ?")
            parametreler.append(onay_durumu)
        if ara.strip():
            kosullar.append("esitle(soru) LIKE ? ESCAPE '\\'")
            parametreler.append(Depo._arama_deseni(ara))
        if yalniz_incele:
            kosullar.append("incele = 1")
        nerede = (" WHERE " + " AND ".join(kosullar)) if kosullar else ""
        return nerede, parametreler

    def cozumler(
        self,
        *,
        limit: int = 100,
        offset: int = 0,
        onay_durumu: str | None = None,
        ara: str = "",
        yalniz_incele: bool = False,
    ) -> list[sqlite3.Row]:
        nerede, parametreler = self._cozum_suzgeci(onay_durumu, ara, yalniz_incele)
        sorgu = f"SELECT * FROM cozum{nerede} ORDER BY id DESC LIMIT ? OFFSET ?"
        return self._sorgu(sorgu, [*parametreler, int(limit), max(0, int(offset))])

    def cozum_say(
        self,
        *,
        onay_durumu: str | None = None,
        ara: str = "",
        yalniz_incele: bool = False,
    ) -> int:
        nerede, parametreler = self._cozum_suzgeci(onay_durumu, ara, yalniz_incele)
        return int(self._tek(f"SELECT COUNT(*) FROM cozum{nerede}", parametreler)[0])

    def cozum_onayla(self, cozum_id: int, *, durum: str, duzeltme: str = "") -> None:
        if durum not in {"bekliyor", "onaylandi", "duzeltildi", "reddedildi"}:
            raise ValueError(f"Bilinmeyen onay durumu: {durum}")
        with self._islem() as b:
            b.execute(
                "UPDATE cozum SET onay_durumu = ?, duzeltme = ? WHERE id = ?",
                (durum, duzeltme, int(cozum_id)),
            )

    # --- önbellek ---

    def onbellek_yaz(
        self,
        kimlik: str,
        cozum: Cozum,
        gomme: np.ndarray | None,
        baglam_imza: str = "",
    ) -> None:
        """`kimlik` çözümü tek belirleyen metindir (soru + şıklar + cevap türü).

        Yalnız soru gövdesi anahtar yapılsaydı, aynı soru farklı şıklarla
        sorulduğunda eski şık harfi güvenle geri döndürülürdü. `baglam_imza`
        yalnız şık eşlemesini ve cevap türünü özetler; yakın eşleşmede
        bu imza birebir tutmayan girdiler elenir.
        """
        veri = (
            gomme.astype(np.float32).tobytes() if gomme is not None else None
        )
        with self._islem() as b:
            b.execute(
                """INSERT INTO cozum_onbellek(soru_imza, soru, baglam_imza, gomme,
                                              cozum_json, olusturma)
                   VALUES(?,?,?,?,?,?)
                   ON CONFLICT(soru_imza) DO UPDATE SET
                     baglam_imza = excluded.baglam_imza,
                     cozum_json = excluded.cozum_json,
                     gomme = excluded.gomme,
                     olusturma = excluded.olusturma""",
                (
                    metin_imzasi(kimlik),
                    kimlik,
                    baglam_imza,
                    veri,
                    cozum.json(),
                    _simdi(),
                ),
            )

    def onbellek_tam_eslesme(self, kimlik: str) -> Cozum | None:
        satir = self._tek(
            "SELECT * FROM cozum_onbellek WHERE soru_imza = ?", (metin_imzasi(kimlik),)
        )
        if not satir:
            return None
        self._isabet_artir(satir["soru_imza"])
        return Cozum.sozlukten(json.loads(satir["cozum_json"]))

    def onbellek_girdileri(
        self, baglam_imza: str | None = None
    ) -> list[tuple[str, np.ndarray, str]]:
        """Gömmesi olan önbellek girdileri: (imza, vektör, çözüm json).

        `baglam_imza` verilirse yalnız şık eşlemesi ve cevap türü birebir aynı
        olan girdiler döner — şıkları permüte edilmiş bir soru yakın eşleşmeyle
        eski harfi geri döndüremesin diye.
        """
        sql = (
            "SELECT soru_imza, gomme, cozum_json FROM cozum_onbellek "
            "WHERE gomme IS NOT NULL"
        )
        parametreler: tuple = ()
        if baglam_imza is not None:
            sql += " AND baglam_imza = ?"
            parametreler = (baglam_imza,)
        sonuc = []
        for satir in self._sorgu(sql, parametreler):
            vektor = np.frombuffer(satir["gomme"], dtype=np.float32)
            if vektor.size:
                sonuc.append((satir["soru_imza"], vektor, satir["cozum_json"]))
        return sonuc

    def _isabet_artir(self, anahtar: str) -> None:
        with self._islem() as b:
            b.execute(
                "UPDATE cozum_onbellek SET isabet = isabet + 1 WHERE soru_imza = ?",
                (anahtar,),
            )

    def onbellek_temizle(self) -> int:
        with self._islem() as b:
            imlec = b.execute("DELETE FROM cozum_onbellek")
            return int(imlec.rowcount)

    # --- eğitim sürümleri ---

    def egitim_surumu_ekle(
        self, etiket: str, yol: str, ornek_sayisi: int, dogrulama_sayisi: int, notlar: str = ""
    ) -> int:
        with self._islem() as b:
            imlec = b.execute(
                """INSERT INTO egitim_surumu(etiket, yol, ornek_sayisi, dogrulama_sayisi,
                   notlar, olusturma) VALUES(?,?,?,?,?,?)""",
                (etiket, yol, int(ornek_sayisi), int(dogrulama_sayisi), notlar, _simdi()),
            )
            return int(imlec.lastrowid)

    def egitim_surumleri(self) -> list[sqlite3.Row]:
        return self._sorgu("SELECT * FROM egitim_surumu ORDER BY id DESC")

    # --- özet ---

    def kapsam_matrisi(self) -> dict[tuple[str, str], int]:
        """(konu, çözüm türü) → örnek sayısı.

        Kullanıcının "sırada hangi soruyu eklemeliyim" sorusunun cevabı bu:
        hafızayı rastgele değil, boş hücreleri kapatarak büyütmek gerekiyor.
        """
        return {
            (satir["konu"] or "", satir["cozum_turu"] or ""): int(satir["adet"])
            for satir in self._sorgu(
                "SELECT konu, cozum_turu, COUNT(*) AS adet FROM ornek WHERE aktif=1"
                " GROUP BY konu, cozum_turu"
            )
        }

    def ozet(self) -> dict[str, object]:
        konu_dagilimi = {
            (satir["konu"] or "(belirtilmemiş)"): int(satir["adet"])
            for satir in self._sorgu(
                "SELECT konu, COUNT(*) AS adet FROM ornek WHERE aktif=1 GROUP BY konu"
                " ORDER BY adet DESC"
            )
        }
        tur_dagilimi = {
            (satir["cozum_turu"] or "(belirtilmemiş)"): int(satir["adet"])
            for satir in self._sorgu(
                "SELECT cozum_turu, COUNT(*) AS adet FROM ornek WHERE aktif=1"
                " GROUP BY cozum_turu ORDER BY adet DESC"
            )
        }
        return {
            "ornek": self.ornek_sayisi(),
            "cozum": int(self._tek("SELECT COUNT(*) FROM cozum")[0]),
            "onbellek": int(self._tek("SELECT COUNT(*) FROM cozum_onbellek")[0]),
            "onbellek_isabeti": int(
                self._tek("SELECT COALESCE(SUM(isabet),0) FROM cozum_onbellek")[0]
            ),
            "konu_dagilimi": konu_dagilimi,
            "cozum_turu_dagilimi": tur_dagilimi,
        }


def ornek_kopyala(ornek: Ornek, **degisiklikler: object) -> Ornek:
    """Örneğin değiştirilmiş kopyasını üretir (dataclasses.replace sarmalayıcısı)."""
    return replace(ornek, **degisiklikler)  # type: ignore[arg-type]
