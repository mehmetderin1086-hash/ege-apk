"""SQLite veri katmanı.

ORM kullanılmıyor: şema tek dosyada duruyor, sorgular açık yazılıyor ve
program tek kullanıcılı. Sürüm geçişleri `sema_surumu` tablosuyla izlenir;
her geçiş yalnız bir kez uygulanır.
"""

from __future__ import annotations

import sqlite3
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

from . import ayarlar

# Her öğe bir şema sürümüdür. Yeni alan gerektiğinde LİSTENİN SONUNA yeni bir
# öğe eklenir; var olan öğeler değiştirilmez — kurulu veritabanları yalnız
# kendilerinden sonraki öğeleri uygular.
GECISLER: tuple[tuple[str, ...], ...] = (
    (
        """
        CREATE TABLE ogretim_yili (
            id INTEGER PRIMARY KEY,
            ad TEXT NOT NULL UNIQUE,
            donem1_baslangic TEXT NOT NULL,
            donem1_bitis TEXT NOT NULL,
            donem2_baslangic TEXT NOT NULL,
            donem2_bitis TEXT NOT NULL,
            aktif INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE takvim_gunu (
            id INTEGER PRIMARY KEY,
            ogretim_yili_id INTEGER NOT NULL REFERENCES ogretim_yili(id) ON DELETE CASCADE,
            tarih TEXT NOT NULL,
            tur TEXT NOT NULL,
            aciklama TEXT NOT NULL DEFAULT '',
            UNIQUE (ogretim_yili_id, tarih, aciklama)
        )
        """,
        """
        CREATE TABLE sube (
            id INTEGER PRIMARY KEY,
            ogretim_yili_id INTEGER NOT NULL REFERENCES ogretim_yili(id) ON DELETE CASCADE,
            ad TEXT NOT NULL,
            sinif INTEGER NOT NULL,
            mufredat_surumu TEXT NOT NULL,
            haftalik_ders_saati INTEGER NOT NULL,
            UNIQUE (ogretim_yili_id, ad)
        )
        """,
        """
        CREATE TABLE ogrenci (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            numara TEXT NOT NULL DEFAULT '',
            ad_soyad TEXT NOT NULL,
            aktif INTEGER NOT NULL DEFAULT 1,
            aciklama TEXT NOT NULL DEFAULT ''
        )
        """,
        """
        CREATE TABLE ders_programi (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            gun INTEGER NOT NULL,
            ders_saati INTEGER NOT NULL,
            UNIQUE (sube_id, gun, ders_saati)
        )
        """,
        """
        CREATE TABLE yillik_plan (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            baslik TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE yillik_plan_satiri (
            id INTEGER PRIMARY KEY,
            plan_id INTEGER NOT NULL REFERENCES yillik_plan(id) ON DELETE CASCADE,
            sira INTEGER NOT NULL,
            hafta_no INTEGER NOT NULL,
            ay TEXT NOT NULL,
            baslangic TEXT NOT NULL,
            bitis TEXT NOT NULL,
            ders_saati INTEGER NOT NULL,
            tur TEXT NOT NULL,
            tema_no INTEGER,
            tema_adi TEXT NOT NULL DEFAULT '',
            kazanim_kodlari TEXT NOT NULL DEFAULT '',
            surec_bilesenleri TEXT NOT NULL DEFAULT '',
            icerik TEXT NOT NULL DEFAULT '',
            yontem_teknik TEXT NOT NULL DEFAULT '',
            arac_gerec TEXT NOT NULL DEFAULT '',
            olcme_degerlendirme TEXT NOT NULL DEFAULT '',
            aciklama TEXT NOT NULL DEFAULT ''
        )
        """,
        """
        CREATE TABLE gunluk_plan (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            tarih TEXT NOT NULL,
            ders_saatleri TEXT NOT NULL DEFAULT '',
            kazanim_kodlari TEXT NOT NULL DEFAULT '',
            bolumler TEXT NOT NULL DEFAULT '{}',
            notlar TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL,
            UNIQUE (sube_id, tarih)
        )
        """,
        """
        CREATE TABLE yoklama (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            tarih TEXT NOT NULL,
            ders_saati INTEGER NOT NULL,
            durum TEXT NOT NULL,
            UNIQUE (ogrenci_id, tarih, ders_saati)
        )
        """,
        """
        CREATE TABLE degerlendirme (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            donem INTEGER NOT NULL,
            tur TEXT NOT NULL,
            ad TEXT NOT NULL,
            tarih TEXT NOT NULL DEFAULT '',
            resmi INTEGER NOT NULL DEFAULT 1,
            tam_puan REAL NOT NULL DEFAULT 100
        )
        """,
        """
        CREATE TABLE not_kaydi (
            id INTEGER PRIMARY KEY,
            degerlendirme_id INTEGER NOT NULL REFERENCES degerlendirme(id) ON DELETE CASCADE,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            puan REAL,
            aciklama TEXT NOT NULL DEFAULT '',
            UNIQUE (degerlendirme_id, ogrenci_id)
        )
        """,
        """
        CREATE TABLE soru (
            id INTEGER PRIMARY KEY,
            mufredat_surumu TEXT NOT NULL,
            kazanim_kodu TEXT NOT NULL,
            sinif INTEGER NOT NULL,
            metin TEXT NOT NULL,
            gorsel_yolu TEXT NOT NULL DEFAULT '',
            rubrik TEXT NOT NULL DEFAULT '',
            puan REAL NOT NULL DEFAULT 10,
            zorluk TEXT NOT NULL DEFAULT 'orta',
            kaynak TEXT NOT NULL DEFAULT 'elle',
            olusturma TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE sinav (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            degerlendirme_id INTEGER REFERENCES degerlendirme(id) ON DELETE SET NULL,
            ad TEXT NOT NULL,
            tarih TEXT NOT NULL DEFAULT '',
            sure_dk INTEGER NOT NULL DEFAULT 40,
            gruplar TEXT NOT NULL DEFAULT 'A',
            belirtke TEXT NOT NULL DEFAULT '{}',
            olusturma TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE sinav_sorusu (
            id INTEGER PRIMARY KEY,
            sinav_id INTEGER NOT NULL REFERENCES sinav(id) ON DELETE CASCADE,
            soru_id INTEGER NOT NULL REFERENCES soru(id) ON DELETE CASCADE,
            sira INTEGER NOT NULL,
            puan REAL NOT NULL DEFAULT 10,
            UNIQUE (sinav_id, soru_id)
        )
        """,
        """
        CREATE TABLE soru_puani (
            id INTEGER PRIMARY KEY,
            sinav_id INTEGER NOT NULL REFERENCES sinav(id) ON DELETE CASCADE,
            soru_id INTEGER NOT NULL REFERENCES soru(id) ON DELETE CASCADE,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            puan REAL NOT NULL,
            UNIQUE (sinav_id, soru_id, ogrenci_id)
        )
        """,
        """
        CREATE TABLE deneme (
            id INTEGER PRIMARY KEY,
            ad TEXT NOT NULL,
            tarih TEXT NOT NULL DEFAULT '',
            yayin TEXT NOT NULL DEFAULT '',
            soru_sayisi INTEGER NOT NULL DEFAULT 13
        )
        """,
        """
        CREATE TABLE deneme_sonucu (
            id INTEGER PRIMARY KEY,
            deneme_id INTEGER NOT NULL REFERENCES deneme(id) ON DELETE CASCADE,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            dogru INTEGER NOT NULL DEFAULT 0,
            yanlis INTEGER NOT NULL DEFAULT 0,
            bos INTEGER NOT NULL DEFAULT 0,
            net REAL NOT NULL DEFAULT 0,
            UNIQUE (deneme_id, ogrenci_id)
        )
        """,
        """
        CREATE TABLE deneme_konu (
            id INTEGER PRIMARY KEY,
            sonuc_id INTEGER NOT NULL REFERENCES deneme_sonucu(id) ON DELETE CASCADE,
            konu TEXT NOT NULL,
            kazanim_kodu TEXT NOT NULL DEFAULT '',
            dogru INTEGER NOT NULL DEFAULT 0,
            yanlis INTEGER NOT NULL DEFAULT 0,
            bos INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE materyal (
            id INTEGER PRIMARY KEY,
            mufredat_surumu TEXT NOT NULL DEFAULT '',
            kazanim_kodu TEXT NOT NULL DEFAULT '',
            sinif INTEGER,
            baslik TEXT NOT NULL,
            tur TEXT NOT NULL DEFAULT 'dosya',
            yol TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            etiketler TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE ayar (
            anahtar TEXT PRIMARY KEY,
            deger TEXT NOT NULL
        )
        """,
        "CREATE INDEX ix_yoklama_sube_tarih ON yoklama (sube_id, tarih)",
        "CREATE INDEX ix_not_ogrenci ON not_kaydi (ogrenci_id)",
        "CREATE INDEX ix_soru_kazanim ON soru (kazanim_kodu)",
        "CREATE INDEX ix_soru_puani_ogrenci ON soru_puani (ogrenci_id)",
        "CREATE INDEX ix_plan_satiri ON yillik_plan_satiri (plan_id, sira)",
    ),
    (
        # MEB'in ünitelendirilmiş plan biçiminde ayrı sütun olarak beklenen iki
        # alan. Türetilebilir oldukları hâlde saklanıyorlar: plan bir kez
        # üretilip teslim edildikten sonra takvim değişse bile idareye verilen
        # belgeyle ekrandaki plan ayrışmasın.
        "ALTER TABLE yillik_plan_satiri ADD COLUMN disiplinler_arasi TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE yillik_plan_satiri ADD COLUMN belirli_gunler TEXT NOT NULL DEFAULT ''",
    ),
    (
        # Satırın hangi döneme ait olduğu üretimde biliniyordu ama saklanmıyor,
        # geri okumada 1'e sabitleniyordu; 38 haftanın 20'sinde yanlış çıkıyordu.
        "ALTER TABLE yillik_plan_satiri ADD COLUMN donem INTEGER NOT NULL DEFAULT 1",
    ),
    (
        # Soru havuzunu geçmiş sınavlardan ayır: sınav sorusu kendi değişmez
        # anlık görüntüsünü taşır, havuzdaki kayıt ise arşivlenebilir.
        "ALTER TABLE soru ADD COLUMN aktif INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE sinav_sorusu ADD COLUMN kazanim_kodu TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE sinav_sorusu ADD COLUMN metin TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE sinav_sorusu ADD COLUMN rubrik TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE sinav_sorusu ADD COLUMN gorsel_yolu TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE sinav_sorusu ADD COLUMN zorluk TEXT NOT NULL DEFAULT 'orta'",
        """
        UPDATE sinav_sorusu
        SET kazanim_kodu = COALESCE((SELECT kazanim_kodu FROM soru WHERE id = soru_id), ''),
            metin = COALESCE((SELECT metin FROM soru WHERE id = soru_id), ''),
            rubrik = COALESCE((SELECT rubrik FROM soru WHERE id = soru_id), ''),
            gorsel_yolu = COALESCE((SELECT gorsel_yolu FROM soru WHERE id = soru_id), ''),
            zorluk = COALESCE((SELECT zorluk FROM soru WHERE id = soru_id), 'orta')
        """,
        """
        CREATE TABLE soru_puani_yeni (
            id INTEGER PRIMARY KEY,
            sinav_sorusu_id INTEGER NOT NULL REFERENCES sinav_sorusu(id) ON DELETE CASCADE,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            puan REAL NOT NULL,
            UNIQUE (sinav_sorusu_id, ogrenci_id)
        )
        """,
        """
        INSERT INTO soru_puani_yeni (id, sinav_sorusu_id, ogrenci_id, puan)
        SELECT p.id, q.id, p.ogrenci_id, p.puan
        FROM soru_puani p
        JOIN sinav_sorusu q ON q.sinav_id = p.sinav_id AND q.soru_id = p.soru_id
        """,
        "DROP TABLE soru_puani",
        "ALTER TABLE soru_puani_yeni RENAME TO soru_puani",
        "CREATE INDEX ix_soru_puani_ogrenci_v2 ON soru_puani (ogrenci_id)",
        "CREATE INDEX ix_soru_aktif_kazanim ON soru (aktif, kazanim_kodu)",
        """
        CREATE TABLE kayit_revizyonu (
            anahtar TEXT PRIMARY KEY,
            surum INTEGER NOT NULL DEFAULT 0
        )
        """,
        # Var olan olası çakışmaları değiştirmeden, bundan sonraki dolu okul
        # numarası tekrarlarını engelle.
        """
        CREATE TRIGGER ogrenci_numara_tekil_ekle
        BEFORE INSERT ON ogrenci
        WHEN trim(NEW.numara) <> '' AND EXISTS (
            SELECT 1 FROM ogrenci
            WHERE sube_id = NEW.sube_id AND trim(numara) = trim(NEW.numara)
              AND aktif = 1
        )
        BEGIN
            SELECT RAISE(ABORT, 'Bu okul numarası şubede zaten kullanılıyor');
        END
        """,
        """
        CREATE TRIGGER ogrenci_numara_tekil_guncelle
        BEFORE UPDATE OF sube_id, numara, aktif ON ogrenci
        WHEN NEW.aktif = 1 AND trim(NEW.numara) <> '' AND EXISTS (
            SELECT 1 FROM ogrenci
            WHERE sube_id = NEW.sube_id AND trim(numara) = trim(NEW.numara)
              AND aktif = 1 AND id <> NEW.id
        )
        BEGIN
            SELECT RAISE(ABORT, 'Bu okul numarası şubede zaten kullanılıyor');
        END
        """,
    ),
    (
        # Ders defteri: her ders bloğu için "ne işlendi" kaydı. Yıllık plan
        # niyeti, bu tablo gerçekleşeni tutar; ikisinin farkı kayma raporunu
        # üretir. Teklik şube+tarih+saat bloğu üzerinedir: aynı bloğun kaydı
        # üstüne yazılır ama aynı günün 1-2 ve 5-6 gibi ayrık blokları
        # birbirini ezmez (şube+tarih tekilken ikinci blok ilkini siliyordu).
        """
        CREATE TABLE ders_kaydi (
            id INTEGER PRIMARY KEY,
            sube_id INTEGER NOT NULL REFERENCES sube(id) ON DELETE CASCADE,
            tarih TEXT NOT NULL,
            ders_saatleri TEXT NOT NULL DEFAULT '',
            kazanim_kodlari TEXT NOT NULL DEFAULT '',
            durum TEXT NOT NULL DEFAULT 'islendi',
            aciklama TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL,
            UNIQUE (sube_id, tarih, ders_saatleri)
        )
        """,
    ),
    (
        # 0.3: dış uygulama aktarımları, kaynaklı öneriler ve plan revizyonları.
        # Yeni tablolar eklemelidir; kurulu veriyi yeniden yazmaz.
        """
        CREATE TABLE dis_kaynak_baglanti (
            id INTEGER PRIMARY KEY,
            saglayici TEXT NOT NULL UNIQUE,
            ad TEXT NOT NULL,
            adres TEXT NOT NULL,
            protokol_surumu TEXT NOT NULL DEFAULT 'v1',
            etkin INTEGER NOT NULL DEFAULT 1,
            son_durum TEXT NOT NULL DEFAULT 'bilinmiyor',
            son_hata TEXT NOT NULL DEFAULT '',
            son_kontrol TEXT NOT NULL DEFAULT ''
        )
        """,
        """
        CREATE TABLE aktarim_islemi (
            id INTEGER PRIMARY KEY,
            saglayici TEXT NOT NULL,
            yon TEXT NOT NULL,
            dis_kimlik TEXT NOT NULL,
            icerik_sha256 TEXT NOT NULL,
            tur TEXT NOT NULL,
            durum TEXT NOT NULL DEFAULT 'onizleme',
            ozet_json TEXT NOT NULL DEFAULT '{}',
            hata TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL,
            guncelleme TEXT NOT NULL,
            UNIQUE (saglayici, dis_kimlik, icerik_sha256)
        )
        """,
        """
        CREATE TABLE kanit_kaynagi (
            id INTEGER PRIMARY KEY,
            tur TEXT NOT NULL,
            dis_kimlik TEXT NOT NULL DEFAULT '',
            baslik TEXT NOT NULL,
            kaynak TEXT NOT NULL DEFAULT '',
            bolum TEXT NOT NULL DEFAULT '',
            icerik_sha256 TEXT NOT NULL DEFAULT '',
            kunye_json TEXT NOT NULL DEFAULT '{}',
            olusturma TEXT NOT NULL,
            UNIQUE (tur, dis_kimlik, icerik_sha256)
        )
        """,
        """
        CREATE TABLE yardimci_onerisi (
            id INTEGER PRIMARY KEY,
            tur TEXT NOT NULL,
            sube_id INTEGER REFERENCES sube(id) ON DELETE CASCADE,
            ogrenci_id INTEGER REFERENCES ogrenci(id) ON DELETE CASCADE,
            kazanim_kodu TEXT NOT NULL DEFAULT '',
            girdi_ozeti TEXT NOT NULL DEFAULT '',
            oneri TEXT NOT NULL,
            kaynaklar_json TEXT NOT NULL DEFAULT '[]',
            model_kimligi TEXT NOT NULL DEFAULT '',
            durum TEXT NOT NULL DEFAULT 'taslak',
            ogretmen_duzeltmesi TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL,
            karar_tarihi TEXT NOT NULL DEFAULT ''
        )
        """,
        """
        CREATE TABLE ogrenci_destek_plani (
            id INTEGER PRIMARY KEY,
            ogrenci_id INTEGER NOT NULL REFERENCES ogrenci(id) ON DELETE CASCADE,
            kazanim_kodu TEXT NOT NULL,
            gerekce TEXT NOT NULL,
            onerilen_calisma TEXT NOT NULL DEFAULT '',
            durum TEXT NOT NULL DEFAULT 'taslak',
            takip_tarihi TEXT NOT NULL DEFAULT '',
            olusturma TEXT NOT NULL,
            guncelleme TEXT NOT NULL,
            UNIQUE (ogrenci_id, kazanim_kodu, durum)
        )
        """,
        """
        CREATE TABLE mufredat_kaynagi (
            id INTEGER PRIMARY KEY,
            surum TEXT NOT NULL,
            ad TEXT NOT NULL,
            resmi_url TEXT NOT NULL DEFAULT '',
            yayin_tarihi TEXT NOT NULL DEFAULT '',
            erisim_tarihi TEXT NOT NULL DEFAULT '',
            icerik_sha256 TEXT NOT NULL,
            siniflar TEXT NOT NULL DEFAULT '',
            gecerlilik_json TEXT NOT NULL DEFAULT '{}',
            etkin INTEGER NOT NULL DEFAULT 1,
            UNIQUE (surum, icerik_sha256)
        )
        """,
        "ALTER TABLE yillik_plan ADD COLUMN revizyon INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE yillik_plan ADD COLUMN durum TEXT NOT NULL DEFAULT 'taslak'",
        "ALTER TABLE yillik_plan ADD COLUMN kaynak_plan_id INTEGER REFERENCES yillik_plan(id)",
        "ALTER TABLE yillik_plan ADD COLUMN karar_tarihi TEXT NOT NULL DEFAULT ''",
        "CREATE INDEX ix_aktarim_durum ON aktarim_islemi (durum, guncelleme)",
        "CREATE INDEX ix_oneri_durum ON yardimci_onerisi (durum, tur)",
        "CREATE INDEX ix_destek_ogrenci ON ogrenci_destek_plani (ogrenci_id, durum)",
        "CREATE INDEX ix_plan_sube_revizyon ON yillik_plan (sube_id, revizyon DESC)",
    ),
)


def baglan(yol: Path | str | None = None) -> sqlite3.Connection:
    hedef = Path(yol) if yol else ayarlar.veritabani_yolu()
    if str(hedef) != ":memory:":
        hedef.parent.mkdir(parents=True, exist_ok=True)
    # check_same_thread=False: FastAPI, senkron uçları iş parçacığı havuzunda
    # koşturuyor; bağlantı ara katmanda (olay döngüsü iş parçacığında) açılıp
    # uçta başka bir iş parçacığında kullanılıyor. Her istek KENDİ bağlantısını
    # açtığı için aynı bağlantı iki iş parçacığında AYNI ANDA kullanılmıyor —
    # bayrağın kapattığı koruma zaten gerekmiyor.
    baglanti = sqlite3.connect(hedef, isolation_level=None, check_same_thread=False)
    baglanti.row_factory = sqlite3.Row
    baglanti.execute("PRAGMA foreign_keys = ON")
    baglanti.execute("PRAGMA journal_mode = WAL")
    if str(hedef) != ":memory:" and hedef.is_file():
        tablo_var = baglanti.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sema_surumu'"
        ).fetchone()
        if tablo_var:
            mevcut = baglanti.execute(
                "SELECT COALESCE(MAX(surum), 0) AS s FROM sema_surumu"
            ).fetchone()["s"]
            if int(mevcut) < len(GECISLER):
                yedekle(hedef, etiket="gecis-oncesi")
    sema_kur(baglanti)
    return baglanti


def sema_kur(baglanti: sqlite3.Connection) -> None:
    baglanti.execute("CREATE TABLE IF NOT EXISTS sema_surumu (surum INTEGER NOT NULL)")
    satir = baglanti.execute("SELECT MAX(surum) AS s FROM sema_surumu").fetchone()
    mevcut = satir["s"] if satir and satir["s"] is not None else 0
    for numara, gecis in enumerate(GECISLER, start=1):
        if numara <= mevcut:
            continue
        # Geçiş tek işlemde uygulanır: ortada bir ifade patlarsa yarım şema
        # kalıyor, sürüm numarası yazılmıyor ve veritabanı bir daha
        # açılamıyordu ("table already exists").
        baglanti.execute("BEGIN")
        try:
            for ifade in gecis:
                baglanti.execute(ifade)
            baglanti.execute("INSERT INTO sema_surumu (surum) VALUES (?)", (numara,))
        except Exception:
            baglanti.execute("ROLLBACK")
            raise
        baglanti.execute("COMMIT")


@contextmanager
def islem(
    baglanti: sqlite3.Connection, *, immediate: bool = False
) -> Iterator[sqlite3.Connection]:
    """Toplu yazmaları tek işlemde toplar; hata olursa hiçbiri kalıcı olmaz."""
    if baglanti.in_transaction:
        # Servisler kendi başlarına da atomik kalırken, web katmanı revizyon
        # kontrolüyle daha geniş bir işlem açabilir.
        ad = f"ic_{id(baglanti):x}"
        baglanti.execute(f"SAVEPOINT {ad}")
        try:
            yield baglanti
        except Exception:
            baglanti.execute(f"ROLLBACK TO SAVEPOINT {ad}")
            baglanti.execute(f"RELEASE SAVEPOINT {ad}")
            raise
        baglanti.execute(f"RELEASE SAVEPOINT {ad}")
        return
    baglanti.execute("BEGIN IMMEDIATE" if immediate else "BEGIN")
    try:
        yield baglanti
    except Exception:
        baglanti.execute("ROLLBACK")
        raise
    baglanti.execute("COMMIT")


def sema_surumu(baglanti: sqlite3.Connection) -> int:
    """Veritabanının GERÇEKTE uygulanmış şema sürümü.

    `len(GECISLER)` kodun beklediği sürümdür; ikisi ancak göç tamamlandıysa
    eşittir. Dışa aktarım künyesi gibi "bu dosyada ne var" soruları buradan
    okunmalı.
    """
    return int(
        baglanti.execute("SELECT COALESCE(MAX(surum), 0) AS s FROM sema_surumu").fetchone()["s"]
    )


def revizyon_oku(baglanti: sqlite3.Connection, anahtar: str) -> int:
    satir = baglanti.execute(
        "SELECT surum FROM kayit_revizyonu WHERE anahtar = ?", (anahtar,)
    ).fetchone()
    return int(satir["surum"]) if satir else 0


def revizyon_dogrula_ve_artir(
    baglanti: sqlite3.Connection, anahtar: str, beklenen: int
) -> int:
    """İyimser eşzamanlılık kapısı; çağıran bunu IMMEDIATE işlemde kullanır."""
    mevcut = revizyon_oku(baglanti, anahtar)
    if mevcut != beklenen:
        raise ValueError(
            f"Kayıt başka bir sekmede değiştirildi (beklenen {beklenen}, güncel {mevcut})."
        )
    yeni = mevcut + 1
    baglanti.execute(
        "INSERT INTO kayit_revizyonu (anahtar, surum) VALUES (?, ?) "
        "ON CONFLICT (anahtar) DO UPDATE SET surum = excluded.surum",
        (anahtar, yeni),
    )
    return yeni


def ayar_oku(baglanti: sqlite3.Connection, anahtar: str, varsayilan: str = "") -> str:
    satir = baglanti.execute("SELECT deger FROM ayar WHERE anahtar = ?", (anahtar,)).fetchone()
    return satir["deger"] if satir else varsayilan


def ayar_yaz(baglanti: sqlite3.Connection, anahtar: str, deger: str) -> None:
    baglanti.execute(
        "INSERT INTO ayar (anahtar, deger) VALUES (?, ?) "
        "ON CONFLICT (anahtar) DO UPDATE SET deger = excluded.deger",
        (anahtar, deger),
    )


def _yedegi_dogrula(baglanti: sqlite3.Connection, ad: str) -> None:
    sonuc = baglanti.execute("PRAGMA quick_check").fetchone()
    if not sonuc or sonuc[0] != "ok":
        raise sqlite3.DatabaseError(f"{ad} SQLite quick_check denetimini geçmedi.")


def yedekle(
    yol: Path | None = None, *, sakla: int = 30, etiket: str = "veri"
) -> Path | None:
    """Veritabanının tarih damgalı bir kopyasını alır, eskileri temizler.

    `sakla` en fazla kaç yedek dosyası tutulacağını söyler; öğrenci notları
    geri alınamaz veri olduğu için yedekler her yazma değil, oturum başına
    alınır (bkz. web.sunucu).
    """
    kaynak = yol or ayarlar.veritabani_yolu()
    if not kaynak.is_file():
        return None
    hedef_dizin = ayarlar.yedek_dizini()
    hedef_dizin.mkdir(parents=True, exist_ok=True)
    damga = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    temiz_etiket = "".join(k for k in etiket.casefold() if k.isalnum() or k == "-") or "veri"
    hedef = hedef_dizin / f"{temiz_etiket}-{damga}.db"

    # Dosya kopyalamak yerine SQLite'ın kendi yedekleme API'si kullanılır:
    # WAL kipinde henüz ana dosyaya işlenmemiş yazmalar `copy2` ile alınan
    # yedeğe girmiyor ve yedek sessizce eksik kalıyor.
    kaynak_baglanti = sqlite3.connect(kaynak)
    hedef_baglanti = sqlite3.connect(hedef)
    try:
        with hedef_baglanti:
            kaynak_baglanti.backup(hedef_baglanti)
        _yedegi_dogrula(hedef_baglanti, "Oluşturulan yedek")
    finally:
        hedef_baglanti.close()
        kaynak_baglanti.close()

    # Budama yaşa göre yapılır, ada göre DEĞİL: "gecis-oncesi-*" alfabetik
    # olarak her "veri-*"den önce geldiği için ada göre sıralama, az önce
    # alınmış geçiş yedeğini en eski sanıp silebiliyordu — geçiş bir şeyi
    # bozduğunda dönülecek yedek sessizce yok oluyordu.
    yedekler = sorted(hedef_dizin.glob("*.db"), key=lambda y: y.stat().st_mtime)
    for eski in yedekler[:-sakla]:
        eski.unlink(missing_ok=True)
    return hedef


def anlik_goruntu_baytlari(yol: Path | None = None) -> bytes:
    """WAL dahil tutarlı, quick_check'ten geçmiş SQLite snapshotı üretir."""
    kaynak = yol or ayarlar.veritabani_yolu()
    if not kaynak.is_file():
        return b""
    with tempfile.NamedTemporaryFile(
        prefix="ogretmen-snapshot-", suffix=".db", delete=False
    ) as gecici:
        gecici_yol = Path(gecici.name)
    kaynak_baglanti = sqlite3.connect(kaynak)
    hedef_baglanti = sqlite3.connect(gecici_yol)
    try:
        kaynak_baglanti.backup(hedef_baglanti)
        _yedegi_dogrula(hedef_baglanti, "Dışa aktarım snapshotı")
        hedef_baglanti.close()  # close() yinelenebilir; finally'deki çağrı zararsız
        return gecici_yol.read_bytes()
    finally:
        kaynak_baglanti.close()
        hedef_baglanti.close()
        gecici_yol.unlink(missing_ok=True)
