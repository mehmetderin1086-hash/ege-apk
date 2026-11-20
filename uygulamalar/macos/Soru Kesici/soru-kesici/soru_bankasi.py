#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Bankası — kesilen soruların kalıcı yerel kütüphanesi (SQLite).

Kesim motoru (soru_kes.py) durumsuzdur; bu modül tek büyüyen yerel bir bankaya
kalıcılık sağlar: her soru bir satır + diskte PNG + gömülü küçük-resim. Aynı soru
farklı DPI'da / numara-beyazlatma sonrası yeniden kesilse bile içerik-hash ile
tekilleşir. CLI/web/GUI üçü de bu API'yi tüketebilir.

Depolama: ~/Library/Application Support/soru-kesici/banka/
    banka.db                       (SQLite; şema PRAGMA user_version ile sürümlü)
    media/<hash[:2]>/<hash>.png     (tam boy kırpma; hash-türevli yol → idempotent)

Yalnız stdlib + numpy/Pillow (zaten kurulu) + soru_kes._tr_normalize.
"""

import hashlib
import io
import json
import os
import sqlite3
import threading
import time

import numpy as np
from PIL import Image

from soru_kes import _tr_normalize as _norm
import veri_yollari

SEMA_SURUM = 5
KUCUK_EN = 360                      # küçük-resim (thumbnail) genişliği (px)

_KILIT = threading.Lock()          # yazımları serileştirir (ThreadingHTTPServer)
_SEMA_KILIT = threading.Lock()     # ilk bağlantıdaki göç/yedek yarışını önler
_FTS_VAR = None                    # baglan ilk çağrıda tespit eder (None=bilinmiyor)


# --------------------------------------------------------------- yollar

def banka_dizin():
    d = os.path.join(veri_yollari.veri_koku(), "banka")
    os.makedirs(d, exist_ok=True)
    return d


def db_yolu(yol=None):
    return yol or os.path.join(banka_dizin(), "banka.db")


def _media_dizin(dbyol):
    d = os.path.join(os.path.dirname(dbyol), "media")
    os.makedirs(d, exist_ok=True)
    return d


# --------------------------------------------------------------- şema

_SEMA_V1 = """
CREATE TABLE IF NOT EXISTS sorular (
  id           INTEGER PRIMARY KEY,
  icerik_hash  TEXT NOT NULL UNIQUE,
  gorsel_yol   TEXT NOT NULL,
  gorsel_hash  TEXT,
  kucuk_blob   BLOB,
  kaynak       TEXT,
  test_no      INTEGER,
  test_sira    INTEGER,
  soru_no      INTEGER,
  sayfa        INTEGER,
  cevap        TEXT,
  konu         TEXT,
  metin        TEXT,
  govde        TEXT,
  siklar_json  TEXT,
  kaynak_kutu  TEXT,
  numara_px    TEXT,
  eklenme      TEXT NOT NULL,
  eklenme_ts   REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_soru_konu   ON sorular(konu);
CREATE INDEX IF NOT EXISTS ix_soru_kaynak ON sorular(kaynak);
CREATE INDEX IF NOT EXISTS ix_soru_cevap  ON sorular(cevap);
CREATE INDEX IF NOT EXISTS ix_soru_test   ON sorular(test_no);
CREATE INDEX IF NOT EXISTS ix_soru_ts     ON sorular(eklenme_ts);

CREATE TABLE IF NOT EXISTS etiketler (
  soru_id  INTEGER NOT NULL REFERENCES sorular(id) ON DELETE CASCADE,
  anahtar  TEXT NOT NULL,
  deger    TEXT,
  PRIMARY KEY (soru_id, anahtar)
);
CREATE INDEX IF NOT EXISTS ix_etiket_ad ON etiketler(anahtar, deger);
"""

def _sutun_var(conn, tablo, sutun):
    return any(r[1] == sutun for r in conn.execute(
        f"PRAGMA table_info({tablo})"))


def _goc_v1(conn):
    conn.executescript(_SEMA_V1)      # tümü IF NOT EXISTS → idempotent


def _goc_v2(conn):
    # v2: AI ile belirlenen kısa BAŞLIK sütunu — IDEMPOTENT (kısmi göç güvenli):
    # ALTER iki kez çalışmasın diye sütun varlığı kontrol edilir. Böylece göç ile
    # user_version bump'ı arasında süreç çökse bile yeniden açılış hatasız olur.
    if not _sutun_var(conn, "sorular", "baslik"):
        conn.execute("ALTER TABLE sorular ADD COLUMN baslik TEXT")
    conn.execute("CREATE INDEX IF NOT EXISTS ix_soru_baslik ON sorular(baslik)")


def _goc_v3(conn):
    # v3: AI ile belirlenen ZORLUK (kolay/orta/zor) — idempotent (bkz. v2).
    if not _sutun_var(conn, "sorular", "zorluk"):
        conn.execute("ALTER TABLE sorular ADD COLUMN zorluk TEXT")
    conn.execute("CREATE INDEX IF NOT EXISTS ix_soru_zorluk ON sorular(zorluk)")


def _goc_v4(conn):
    """V2 kesim motorunun izlenebilirlik ve kalite alanları.

    Tüm alanlar bilinçli olarak nullable'dır: daha önce bankaya eklenmiş sorular
    aynen korunur ve eski kayıtlar yeni motorla üretilmiş gibi gösterilmez.
    Sütun başına kontrol, yarıda kalan bir göçün güvenle tekrarlanmasını sağlar.
    """
    alanlar = {
        "kaynak_hash": "TEXT",
        "algoritma_surumu": "TEXT",
        "soru_turu": "TEXT",
        "sayfa_rolu": "TEXT",
        "guven": "REAL",
        "inceleme_durumu": "TEXT",
    }
    for ad, tur in alanlar.items():
        if not _sutun_var(conn, "sorular", ad):
            conn.execute(f"ALTER TABLE sorular ADD COLUMN {ad} {tur}")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS ix_soru_kaynak_hash "
        "ON sorular(kaynak_hash)")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS ix_soru_inceleme "
        "ON sorular(inceleme_durumu)")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS ix_soru_kaynak_surumu "
        "ON sorular(kaynak, algoritma_surumu)")
    _yeniden_isleme_tablolari(conn)


def _yeniden_isleme_tablolari(conn):
    """Eski bankayı değiştirmeyen V2 karşılaştırma sahnesi."""
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS yeniden_isleme_oturumlari (
      id INTEGER PRIMARY KEY,
      kaynak TEXT NOT NULL,
      kaynak_hash TEXT,
      algoritma_surumu TEXT NOT NULL,
      durum TEXT NOT NULL DEFAULT 'onay_bekliyor',
      eski_sayi INTEGER NOT NULL,
      yeni_sayi INTEGER NOT NULL,
      ozet_json TEXT NOT NULL,
      olusturma_ts REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS ix_yeniden_kaynak
      ON yeniden_isleme_oturumlari(kaynak, olusturma_ts);
    CREATE TABLE IF NOT EXISTS yeniden_isleme_adaylari (
      oturum_id INTEGER NOT NULL
        REFERENCES yeniden_isleme_oturumlari(id) ON DELETE CASCADE,
      sira INTEGER NOT NULL,
      sayfa INTEGER,
      soru_no INTEGER,
      kutu_json TEXT,
      soru_turu TEXT,
      sayfa_rolu TEXT,
      guven REAL,
      inceleme_durumu TEXT,
      PRIMARY KEY (oturum_id, sira)
    );
    """)


def _goc_v5(conn):
    """Sınav sihirbazı şablonları (blueprint/ayarlar/tam). Salt yeni tablo →
    mevcut kayıtlara dokunmaz, V4 yedek töreni gerekmez, idempotent."""
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS sinav_sablonlari (
      id INTEGER PRIMARY KEY,
      ad TEXT NOT NULL,
      tur TEXT NOT NULL DEFAULT 'blueprint',
      veri_json TEXT NOT NULL,
      olusturma_ts REAL NOT NULL,
      guncelleme_ts REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS ix_sablon_tur ON sinav_sablonlari(tur);
    """)


_GOCLER = {1: _goc_v1, 2: _goc_v2, 3: _goc_v3, 4: _goc_v4, 5: _goc_v5}


def _v4_yedek_adlari(dbyol):
    """Bu DB'ye ait V4-öncesi yedekleri (eski → yeni) döndürür."""
    dizin = os.path.dirname(dbyol)
    govde, uzanti = os.path.splitext(os.path.basename(dbyol))
    uzanti = uzanti or ".db"
    onek = f"{govde}.v3-oncesi-v4."
    try:
        adlar = os.listdir(dizin)
    except OSError:
        return []
    return [os.path.join(dizin, ad) for ad in sorted(adlar)
            if ad.startswith(onek) and ad.endswith(uzanti)]


def _gecerli_sqlite_yedegi(yol):
    try:
        # Backup hedefi kaynak gibi WAL modunda olabilir. ``immutable=1`` salt
        # okunur doğrulamada -wal/-shm yan dosyası oluşturma gereksinimini önler.
        conn = sqlite3.connect(
            f"file:{yol}?mode=ro&immutable=1", uri=True, timeout=1.0)
        try:
            return (conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
                    and conn.execute("PRAGMA user_version").fetchone()[0] <= 3)
        finally:
            conn.close()
    except (OSError, sqlite3.Error):
        return False


def _v4_oncesi_yedekle(conn, dbyol):
    """V3 durumunu SQLite backup API ile bir kez ve tutarlı biçimde saklar."""
    for onceki in _v4_yedek_adlari(dbyol):
        if _gecerli_sqlite_yedegi(onceki):
            return onceki

    govde, uzanti = os.path.splitext(os.path.basename(dbyol))
    uzanti = uzanti or ".db"
    damga = time.strftime("%Y%m%d-%H%M%S", time.localtime())
    benzersiz = f"{time.time_ns() % 1_000_000_000:09d}-{os.getpid()}"
    ad = f"{govde}.v3-oncesi-v4.{damga}-{benzersiz}{uzanti}"
    yedek_yolu = os.path.join(os.path.dirname(dbyol), ad)
    hedef = sqlite3.connect(yedek_yolu)
    try:
        conn.backup(hedef)
        hedef.commit()
    finally:
        hedef.close()
    if not _gecerli_sqlite_yedegi(yedek_yolu):
        raise sqlite3.DatabaseError("V4 öncesi banka yedeği doğrulanamadı")
    return yedek_yolu


def baglan(yol=None):
    """Dizinleri kurar, PRAGMA'ları uygular, göçü çalıştırır, bağlantı döndürür.
    Her çağrı kendi kısa ömürlü bağlantısını açmalıdır (thread güvenliği)."""
    global _FTS_VAR
    dbyol = db_yolu(yol)
    os.makedirs(os.path.dirname(dbyol), exist_ok=True)
    mevcut_db = os.path.isfile(dbyol) and os.path.getsize(dbyol) > 0
    conn = sqlite3.connect(dbyol, timeout=5.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA foreign_keys=ON")
    sur = conn.execute("PRAGMA user_version").fetchone()[0]
    if sur < SEMA_SURUM:
        with _SEMA_KILIT:
            # Başka bir web iş parçacığı kilidi beklerken göçü bitirmiş olabilir.
            sur = conn.execute("PRAGMA user_version").fetchone()[0]
            # Her göç IDEMPOTENT olduğundan kısmi/tekrar uygulama güvenli; bump
            # ayrı commit edilir (executescript'in örtük commit'i atomikliği
            # bozar).
            for v in range(sur + 1, SEMA_SURUM + 1):
                if v == 4 and mevcut_db:
                    _v4_oncesi_yedekle(conn, dbyol)
                _GOCLER[v](conn)
                conn.execute(f"PRAGMA user_version = {v}")
                conn.commit()
    # FTS5 tam-metin arama tablosu (yoksa LIKE yedeğine düşülür)
    if _FTS_VAR is None:
        try:
            conn.execute(
                "CREATE VIRTUAL TABLE IF NOT EXISTS arama USING fts5(metin)")
            _FTS_VAR = True
        except sqlite3.OperationalError:
            _FTS_VAR = False
    elif _FTS_VAR:
        conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS arama USING fts5(metin)")
    return conn


# --------------------------------------------------------------- hash / dedup

def _ahash(img):
    """256-bit average-hash (aHash) hex. Küçük yeniden-ölçek/sıkıştırmaya
    dayanıklı görüntü imzası (metin OCR'ı olmayan sorular için dedup)."""
    g = img.convert("L").resize((16, 16))
    a = np.asarray(g, dtype=np.float64)
    bits = (a > a.mean()).flatten()
    v = 0
    for b in bits:
        v = (v << 1) | int(b)
    return format(v, "064x")


def icerik_hash(so, ahash):
    """Dedup anahtarı. Metin sinyali yeterliyse (≥12 karakter) tr-normalize
    edilmiş gövde+şık sha256'sı ('t:...'); değilse görüntü aHash ('i:...').
    Böylece aynı soru farklı DPI'da yeniden kesilse de tekilleşir."""
    govde = (so.get("govde") or so.get("metin") or "")
    siklar = so.get("siklar") or {}
    t = _norm(govde) + "\x1f" + "|".join(
        _norm(str(v)) for v in siklar.values())
    yalin = t.replace("\x1f", "").replace("|", "").strip()
    if len(yalin) >= 12:
        return "t:" + hashlib.sha256(t.encode("utf-8")).hexdigest()
    return "i:" + ahash


def _kucuk_png(img):
    """~KUCUK_EN genişliğinde küçük-resim PNG baytları (ızgara için)."""
    if img.width > KUCUK_EN:
        oran = KUCUK_EN / img.width
        img = img.resize((KUCUK_EN, max(1, round(img.height * oran))))
    bio = io.BytesIO()
    img.convert("RGB").save(bio, "PNG")
    return bio.getvalue()


def _png_baytlar(img):
    bio = io.BytesIO()
    img.convert("RGB").save(bio, "PNG")
    return bio.getvalue()


# --------------------------------------------------------------- ekleme

def _arama_metni(so):
    """FTS/LIKE için tr-normalize edilmiş arama havuzu: metin + konu + başlık +
    etiket."""
    etik = so.get("etiketler") or {}
    return _norm(" ".join([
        so.get("metin") or so.get("govde") or "",
        so.get("konu") or "", so.get("baslik") or "",
        " ".join(f"{k} {v}" for k, v in etik.items()),
    ]))


def banka_ekle(sorular, kirpmalar, kaynak=None, *, kaynak_hash=None,
               algoritma_surumu=None, yol=None):
    """(sorular meta, kirpmalar PIL) çiftlerini bankaya ekler. İçerik-hash ile
    tekilleştirir. ``kaynak_hash`` ve ``algoritma_surumu`` belge düzeyi
    varsayılanlardır; soru metasındaki değerler varsa önceliklidir.
    Dönüş: {"eklenen","atlanan","idler"}."""
    if not sorular:
        return {"eklenen": 0, "atlanan": 0, "idler": []}
    dbyol = db_yolu(yol)
    medya = _media_dizin(dbyol)
    eklenen = atlanan = 0
    idler = []
    simdi_ts = time.time()
    simdi = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(simdi_ts))
    with _KILIT:
        conn = baglan(yol)
        try:
            for so, img in zip(sorular, kirpmalar):
                if img is None:
                    continue
                ah = _ahash(img)
                h = icerik_hash(so, ah)
                govdesi = h.split(":", 1)[1]
                rel = os.path.join("media", govdesi[:2], f"{govdesi}.png")
                tam = os.path.join(os.path.dirname(dbyol), rel)
                if not os.path.exists(tam):
                    os.makedirs(os.path.dirname(tam), exist_ok=True)
                    with open(tam, "wb") as f:
                        f.write(_png_baytlar(img))
                cur = conn.execute(
                    """INSERT OR IGNORE INTO sorular
                       (icerik_hash, gorsel_yol, gorsel_hash, kucuk_blob,
                        kaynak, test_no, test_sira, soru_no, sayfa, cevap,
                        konu, baslik, zorluk, metin, govde, siklar_json,
                        kaynak_kutu, numara_px, eklenme, eklenme_ts,
                        kaynak_hash, algoritma_surumu, soru_turu, sayfa_rolu,
                        guven, inceleme_durumu)
                       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (h, rel, ah, _kucuk_png(img),
                     kaynak or so.get("kaynak"), so.get("test_no"),
                     so.get("test_sira"), so.get("soru_no"), so.get("sayfa"),
                     so.get("cevap"), so.get("konu"), so.get("baslik"),
                     so.get("zorluk"), so.get("metin"), so.get("govde"),
                     json.dumps(so.get("siklar") or {}, ensure_ascii=False),
                     json.dumps(so.get("kaynak_kutu")),
                     json.dumps(so.get("numara_px")), simdi, simdi_ts,
                     so.get("kaynak_hash") or kaynak_hash,
                     so.get("algoritma_surumu") or algoritma_surumu,
                     so.get("soru_turu"), so.get("sayfa_rolu"),
                     so.get("guven"), so.get("inceleme_durumu")))
                if cur.rowcount:
                    sid = cur.lastrowid
                    idler.append(sid)
                    eklenen += 1
                    for k, v in (so.get("etiketler") or {}).items():
                        conn.execute(
                            "INSERT OR IGNORE INTO etiketler VALUES (?,?,?)",
                            (sid, k, v))
                    if _FTS_VAR:
                        conn.execute(
                            "INSERT INTO arama(rowid, metin) VALUES (?,?)",
                            (sid, _arama_metni(so)))
                else:
                    atlanan += 1
            conn.commit()
        finally:
            conn.close()
    return {"eklenen": eklenen, "atlanan": atlanan, "idler": idler}


# --------------------------------------------------------------- sorgu

def _fts_sorgu(arama):
    # Jetonlardan alfasayısal-olmayanı at → FTS5 özel karakterleri (" : ( ) - AND
    # NEAR ...) sözdizim hatası fırlatamaz. _norm zaten küçültüp aksan katlar;
    # FTS unicode61 tokenizer da alfasayısal-olmayanda böler → eşleşme tutarlı.
    import re
    kelimeler = [re.sub(r"[^a-z0-9]+", "", k) for k in _norm(arama).split()]
    return " ".join(k + "*" for k in kelimeler if k)


def _satir_dict(row, etiket_map):
    d = dict(row)
    d.pop("kucuk_blob", None)
    d["siklar"] = json.loads(d.pop("siklar_json") or "{}")
    d["kaynak_kutu"] = json.loads(d.get("kaynak_kutu") or "null")
    d["numara_px"] = json.loads(d.get("numara_px") or "null")
    d["etiketler"] = etiket_map.get(d["id"], {})
    d["gorsel_url"] = f"/banka-gorsel?id={d['id']}"
    return d


def _sorgu_kosullari(f):
    """Filtre sözlüğünden (WHERE koşulları, parametreler) üretir.
    banka_sorgula ve banka_blueprint_sec paylaşır. arama FTS'e bağlıdır →
    _FTS_VAR belirlenmiş olmalı (baglan çağrısından SONRA)."""
    kosul, param = [], []
    if f.get("konu"):
        kosul.append("konu = ?"); param.append(f["konu"])
    if f.get("kaynak"):
        kosul.append("kaynak = ?"); param.append(f["kaynak"])
    if f.get("cevap"):
        kosul.append("cevap = ?"); param.append(f["cevap"])
    if f.get("zorluk"):
        kosul.append("zorluk = ?"); param.append(f["zorluk"])
    if f.get("kaynak_hash"):
        kosul.append("kaynak_hash = ?"); param.append(f["kaynak_hash"])
    if f.get("algoritma_surumu"):
        kosul.append("algoritma_surumu = ?"); param.append(f["algoritma_surumu"])
    if f.get("soru_turu"):
        kosul.append("soru_turu = ?"); param.append(f["soru_turu"])
    if f.get("sayfa_rolu"):
        kosul.append("sayfa_rolu = ?"); param.append(f["sayfa_rolu"])
    if f.get("inceleme_durumu"):
        kosul.append("inceleme_durumu = ?"); param.append(f["inceleme_durumu"])
    if f.get("guven_min") is not None:
        kosul.append("guven >= ?"); param.append(float(f["guven_min"]))
    if f.get("guven_max") is not None:
        kosul.append("guven <= ?"); param.append(float(f["guven_max"]))
    if f.get("test") not in (None, ""):
        kosul.append("test_no = ?"); param.append(int(f["test"]))
    if f.get("bos") == "dolu":
        kosul.append("cevap IS NOT NULL AND cevap != ''")
    elif f.get("bos") == "bos":
        kosul.append("(cevap IS NULL OR cevap = '')")
    # Tarih aralığı (YYYY-MM-DD; son gün dahil)
    if f.get("tarih_bas"):
        ts = _tarih_ts(f["tarih_bas"])
        if ts is not None:
            kosul.append("eklenme_ts >= ?"); param.append(ts)
    if f.get("tarih_son"):
        ts = _tarih_ts(f["tarih_son"])
        if ts is not None:
            kosul.append("eklenme_ts < ?"); param.append(ts + 86400)
    if f.get("etiket"):
        etiket = f["etiket"]
        if "=" in etiket:
            a, d = etiket.split("=", 1)
            kosul.append("EXISTS (SELECT 1 FROM etiketler e WHERE "
                         "e.soru_id = sorular.id AND e.anahtar=? AND e.deger=?)")
            param += [a.strip(), d.strip()]
        else:
            kosul.append("EXISTS (SELECT 1 FROM etiketler e WHERE "
                         "e.soru_id = sorular.id AND e.anahtar=?)")
            param.append(etiket.strip())
    if f.get("arama"):
        arama = f["arama"]
        fts = _fts_sorgu(arama) if _FTS_VAR else ""
        if _FTS_VAR and fts:
            kosul.append("id IN (SELECT rowid FROM arama WHERE arama MATCH ?)")
            param.append(fts)
        elif not _FTS_VAR:
            for k in _norm(arama).split():
                temiz = "".join(ch for ch in k if ch.isalnum())
                if temiz:
                    kosul.append("lower(metin) LIKE ?"); param.append(f"%{temiz}%")
    return kosul, param


def _tarih_ts(deger):
    """YYYY-MM-DD → yerel gün başı epoch saniyesi | None."""
    import time
    try:
        return time.mktime(time.strptime(str(deger)[:10], "%Y-%m-%d"))
    except (ValueError, TypeError):
        return None


def banka_sorgula(*, konu=None, test=None, kaynak=None, cevap=None,
                  etiket=None, arama=None, bos=None, zorluk=None, rastgele=None,
                  limit=60, ofset=0, sirala="yeni", kaynak_hash=None,
                  algoritma_surumu=None, soru_turu=None, sayfa_rolu=None,
                  inceleme_durumu=None, guven_min=None, guven_max=None,
                  tarih_bas=None, tarih_son=None, yol=None):
    """Filtreli soru listesi. Dönüş: {"kayitlar":[...], "toplam":int}.
    bos: 'bos' (cevapsız) | 'dolu' (cevaplı). rastgele: N → rastgele N kayıt.
    tarih_bas/tarih_son: YYYY-MM-DD (son gün dahil)."""
    conn = baglan(yol)          # ÖNCE bağlan: _FTS_VAR'ı belirler (arama dalı ona bağlı)
    kosul, param = _sorgu_kosullari(locals())
    where = ("WHERE " + " AND ".join(kosul)) if kosul else ""
    if rastgele:
        duzen = "ORDER BY RANDOM()"; limit = int(rastgele); ofset = 0
    elif sirala == "eski":
        duzen = "ORDER BY eklenme_ts ASC"
    elif sirala == "test":
        duzen = "ORDER BY test_sira, soru_no"
    else:
        duzen = "ORDER BY eklenme_ts DESC"

    try:
        toplam = conn.execute(
            f"SELECT COUNT(*) FROM sorular {where}", param).fetchone()[0]
        rows = conn.execute(
            f"SELECT * FROM sorular {where} {duzen} LIMIT ? OFFSET ?",
            param + [int(limit), int(ofset)]).fetchall()
        idler = [r["id"] for r in rows]
        etiket_map = _etiketleri_al(conn, idler)
        kayitlar = [_satir_dict(r, etiket_map) for r in rows]
    finally:
        conn.close()
    return {"kayitlar": kayitlar, "toplam": toplam,
            "ofset": int(ofset), "limit": int(limit)}


def _etiketleri_al(conn, idler):
    if not idler:
        return {}
    q = ",".join("?" * len(idler))
    m = {}
    for r in conn.execute(
            f"SELECT soru_id, anahtar, deger FROM etiketler "
            f"WHERE soru_id IN ({q})", idler):
        m.setdefault(r["soru_id"], {})[r["anahtar"]] = r["deger"]
    return m


def _kaynak_secim_kosulu(kaynak, kaynak_hash, algoritma_surumu=None):
    """Kaynak görüntüsü API'leri için parametreli, zorunlu daraltma koşulu."""
    kosul, param = [], []
    if kaynak:
        kosul.append("kaynak = ?")
        param.append(kaynak)
    if kaynak_hash:
        kosul.append("kaynak_hash = ?")
        param.append(kaynak_hash)
    if not kosul:
        raise ValueError("kaynak veya kaynak_hash belirtilmelidir")
    if algoritma_surumu is not None:
        if algoritma_surumu == "":
            kosul.append(
                "(algoritma_surumu IS NULL OR algoritma_surumu = '')")
        else:
            kosul.append("algoritma_surumu = ?")
            param.append(algoritma_surumu)
    return " AND ".join(kosul), param


def banka_kaynak_kayitlari(*, kaynak=None, kaynak_hash=None,
                           algoritma_surumu=None, yol=None):
    """Bir kaynağın değiştirilmeyen kayıt görüntüsünü döndürür.

    Yeniden kesim öncesi eski-yeni karşılaştırması için tasarlanmıştır. En az
    ``kaynak`` veya ``kaynak_hash`` zorunludur; böylece yanlışlıkla bütün banka
    belleğe alınmaz. Fonksiyon hiçbir soru, etiket veya media dosyasını yazmaz.
    ``algoritma_surumu=''`` eski/sürümü bilinmeyen kayıtları seçer.
    """
    where, param = _kaynak_secim_kosulu(
        kaynak, kaynak_hash, algoritma_surumu)
    conn = baglan(yol)
    try:
        rows = conn.execute(
            f"SELECT * FROM sorular WHERE {where} ORDER BY id", param
        ).fetchall()
        idler = [r["id"] for r in rows]
        etiket_map = _etiketleri_al(conn, idler)
        kayitlar = [_satir_dict(r, etiket_map) for r in rows]
    finally:
        conn.close()
    return {"kayitlar": kayitlar, "toplam": len(kayitlar)}


def banka_kaynak_ozeti(*, kaynak=None, kaynak_hash=None, yol=None):
    """Kaynağın karşılaştırma özetini salt-okunur olarak üretir."""
    sonuc = banka_kaynak_kayitlari(
        kaynak=kaynak, kaynak_hash=kaynak_hash, yol=yol)
    kayitlar = sonuc["kayitlar"]

    def sayim(alan, eski_etiketi="(bilinmiyor)"):
        degerler = {}
        for kayit in kayitlar:
            deger = kayit.get(alan)
            anahtar = deger if deger not in (None, "") else eski_etiketi
            degerler[anahtar] = degerler.get(anahtar, 0) + 1
        return degerler

    guvenler = [float(k["guven"]) for k in kayitlar
                if k.get("guven") is not None]
    return {
        "toplam": sonuc["toplam"],
        "idler": [k["id"] for k in kayitlar],
        "icerik_hashleri": [k["icerik_hash"] for k in kayitlar],
        "algoritma_surumleri": sayim("algoritma_surumu", "(eski)"),
        "soru_turleri": sayim("soru_turu"),
        "sayfa_rolleri": sayim("sayfa_rolu"),
        "inceleme_durumlari": sayim("inceleme_durumu", "(eski)"),
        "guven": {
            "bilinen": len(guvenler),
            "ortalama": (sum(guvenler) / len(guvenler)) if guvenler else None,
            "minimum": min(guvenler) if guvenler else None,
            "maksimum": max(guvenler) if guvenler else None,
        },
    }


def banka_yeniden_isleme_sahnele(kaynak, adaylar, *, kaynak_hash=None,
                                 algoritma_surumu="2.1", yol=None):
    """Yeni aday metadatasını ayrı tabloda tut; ``sorular`` tablosuna dokunma.

    Bu güvenli aşama yalnız karşılaştırma içindir. Onay verilmeden eski kayıt
    silmez, medya yazmaz ve yeni adayı banka sorusu haline getirmez.
    """
    if not kaynak:
        raise ValueError("kaynak zorunludur")
    adaylar = list(adaylar or [])
    conn = baglan(yol)
    try:
        _yeniden_isleme_tablolari(conn)
        eski = conn.execute(
            "SELECT COUNT(*) FROM sorular WHERE kaynak=?", (kaynak,)
        ).fetchone()[0]

        def sayim(alan, varsayilan="(bilinmiyor)"):
            sonuc = {}
            for aday in adaylar:
                deger = aday.get(alan) or varsayilan
                sonuc[deger] = sonuc.get(deger, 0) + 1
            return sonuc

        ozet = {
            "eski_toplam": int(eski), "yeni_toplam": len(adaylar),
            "fark": len(adaylar) - int(eski),
            "inceleme_durumlari": sayim("inceleme_durumu"),
            "soru_turleri": sayim("soru_turu"),
            "sayfa_rolleri": sayim("sayfa_rolu"),
        }
        cur = conn.execute(
            """INSERT INTO yeniden_isleme_oturumlari
               (kaynak,kaynak_hash,algoritma_surumu,durum,eski_sayi,
                yeni_sayi,ozet_json,olusturma_ts)
               VALUES (?,?,?,?,?,?,?,?)""",
            (kaynak, kaynak_hash, algoritma_surumu, "onay_bekliyor",
             int(eski), len(adaylar), json.dumps(ozet, ensure_ascii=False),
             time.time()))
        oid = int(cur.lastrowid)
        conn.executemany(
            """INSERT INTO yeniden_isleme_adaylari
               (oturum_id,sira,sayfa,soru_no,kutu_json,soru_turu,sayfa_rolu,
                guven,inceleme_durumu) VALUES (?,?,?,?,?,?,?,?,?)""",
            [(oid, i, a.get("sayfa"), a.get("soru_no"),
              json.dumps(a.get("kutu"), ensure_ascii=False),
              a.get("soru_turu"), a.get("sayfa_rolu"), a.get("guven"),
              a.get("inceleme_durumu")) for i, a in enumerate(adaylar)])
        conn.commit()
        return {"id": oid, "kaynak": kaynak, "kaynak_hash": kaynak_hash,
                "algoritma_surumu": algoritma_surumu,
                "durum": "onay_bekliyor", **ozet}
    finally:
        conn.close()


def banka_yeniden_isleme_son(*, kaynak=None, yol=None):
    """Son karşılaştırmayı döndürür; yoksa ``None``."""
    conn = baglan(yol)
    try:
        _yeniden_isleme_tablolari(conn)
        if kaynak:
            satir = conn.execute(
                """SELECT * FROM yeniden_isleme_oturumlari
                   WHERE kaynak=? ORDER BY olusturma_ts DESC, id DESC LIMIT 1""",
                (kaynak,)).fetchone()
        else:
            satir = conn.execute(
                """SELECT * FROM yeniden_isleme_oturumlari
                   ORDER BY olusturma_ts DESC, id DESC LIMIT 1""").fetchone()
        if not satir:
            return None
        ozet = json.loads(satir["ozet_json"] or "{}")
        return {"id": satir["id"], "kaynak": satir["kaynak"],
                "kaynak_hash": satir["kaynak_hash"],
                "algoritma_surumu": satir["algoritma_surumu"],
                "durum": satir["durum"],
                "olusturma_ts": satir["olusturma_ts"], **ozet}
    finally:
        conn.close()


def banka_kayit(soru_id, *, yol=None):
    conn = baglan(yol)
    try:
        r = conn.execute("SELECT * FROM sorular WHERE id=?",
                         (int(soru_id),)).fetchone()
        if not r:
            return None
        return _satir_dict(r, _etiketleri_al(conn, [int(soru_id)]))
    finally:
        conn.close()


def banka_gorsel(soru_id, kucuk=True, *, yol=None):
    """Soru görüntüsü PNG baytları | None. kucuk=True saklı thumbnail blob'u
    (hızlı), aksi hâlde diskteki tam-boy dosya."""
    conn = baglan(yol)
    try:
        r = conn.execute(
            "SELECT gorsel_yol, kucuk_blob FROM sorular WHERE id=?",
            (int(soru_id),)).fetchone()
    finally:
        conn.close()
    if not r:
        return None
    if kucuk and r["kucuk_blob"]:
        return bytes(r["kucuk_blob"])
    tam = os.path.join(banka_dizin() if yol is None
                       else os.path.dirname(db_yolu(yol)), r["gorsel_yol"])
    if os.path.exists(tam):
        with open(tam, "rb") as f:
            return f.read()
    return bytes(r["kucuk_blob"]) if r["kucuk_blob"] else None


def banka_getir(idler, *, yol=None):
    """Verilen id sırasında (kirpmalar:[PIL], meta:[dict]) döndürür — sınav
    üretimi için. meta, sinav_pdf.sinav_pdf_uret'in beklediği biçimde
    (test_sira/soru_no/cevap/numara_px/...)."""
    kirpmalar, meta = [], []
    conn = baglan(yol)
    kok = os.path.dirname(db_yolu(yol))
    try:
        for sid in idler:
            r = conn.execute("SELECT * FROM sorular WHERE id=?",
                             (int(sid),)).fetchone()
            if not r:
                continue
            tam = os.path.join(kok, r["gorsel_yol"])
            if not os.path.exists(tam):
                continue
            kirpmalar.append(Image.open(tam).convert("RGB"))
            meta.append({
                "test_no": r["test_no"], "test_sira": r["test_sira"],
                "soru_no": r["soru_no"], "sayfa": r["sayfa"],
                "kaynak": r["kaynak"], "cevap": r["cevap"], "konu": r["konu"],
                "baslik": r["baslik"], "zorluk": r["zorluk"],
                "kaynak_hash": r["kaynak_hash"],
                "algoritma_surumu": r["algoritma_surumu"],
                "soru_turu": r["soru_turu"],
                "sayfa_rolu": r["sayfa_rolu"], "guven": r["guven"],
                "inceleme_durumu": r["inceleme_durumu"],
                "metin": r["metin"], "govde": r["govde"],
                "siklar": json.loads(r["siklar_json"] or "{}"),
                "kaynak_kutu": json.loads(r["kaynak_kutu"] or "null"),
                "numara_px": json.loads(r["numara_px"] or "null"),
            })
    finally:
        conn.close()
    return kirpmalar, meta


def banka_filtreler(*, yol=None):
    """Filtre açılır listeleri için mevcut distinct değerler."""
    conn = baglan(yol)
    try:
        konular = [r[0] for r in conn.execute(
            "SELECT DISTINCT konu FROM sorular WHERE konu IS NOT NULL "
            "AND konu != '' ORDER BY konu")]
        kaynaklar = [r[0] for r in conn.execute(
            "SELECT DISTINCT kaynak FROM sorular WHERE kaynak IS NOT NULL "
            "AND kaynak != '' ORDER BY kaynak")]
        soru_turleri = [r[0] for r in conn.execute(
            "SELECT DISTINCT soru_turu FROM sorular WHERE soru_turu IS NOT NULL "
            "AND soru_turu != '' ORDER BY soru_turu")]
        sayfa_rolleri = [r[0] for r in conn.execute(
            "SELECT DISTINCT sayfa_rolu FROM sorular WHERE sayfa_rolu IS NOT NULL "
            "AND sayfa_rolu != '' ORDER BY sayfa_rolu")]
        inceleme_durumlari = [r[0] for r in conn.execute(
            "SELECT DISTINCT inceleme_durumu FROM sorular "
            "WHERE inceleme_durumu IS NOT NULL AND inceleme_durumu != '' "
            "ORDER BY inceleme_durumu")]
        algoritma_surumleri = [r[0] for r in conn.execute(
            "SELECT DISTINCT algoritma_surumu FROM sorular "
            "WHERE algoritma_surumu IS NOT NULL AND algoritma_surumu != '' "
            "ORDER BY algoritma_surumu")]
    finally:
        conn.close()
    return {"konular": konular, "kaynaklar": kaynaklar,
            "soru_turleri": soru_turleri, "sayfa_rolleri": sayfa_rolleri,
            "inceleme_durumlari": inceleme_durumlari,
            "algoritma_surumleri": algoritma_surumleri}


def banka_guncelle_konu(guncellemeler, *, yol=None):
    """Toplu konu/başlık/zorluk güncellemesi (AI etiketleme sonrası).
    guncellemeler: [{"id":int, "konu":?, "baslik":?, "zorluk":?}]. FTS arama
    satırını da tazeler. Dönüş: güncellenen satır sayısı."""
    if not guncellemeler:
        return 0
    n = 0
    with _KILIT:
        conn = baglan(yol)
        try:
            for g in guncellemeler:
                sid = int(g["id"])
                cur = conn.execute(
                    "UPDATE sorular SET konu=COALESCE(?,konu), "
                    "baslik=COALESCE(?,baslik), zorluk=COALESCE(?,zorluk) "
                    "WHERE id=?",
                    (g.get("konu") or None, g.get("baslik") or None,
                     g.get("zorluk") or None, sid))
                if cur.rowcount:
                    n += 1
                    if _FTS_VAR:
                        r = conn.execute(
                            "SELECT metin, konu, baslik FROM sorular WHERE id=?",
                            (sid,)).fetchone()
                        havuz = _arama_metni({"metin": r["metin"],
                                              "konu": r["konu"],
                                              "baslik": r["baslik"]})
                        conn.execute("DELETE FROM arama WHERE rowid=?", (sid,))
                        conn.execute(
                            "INSERT INTO arama(rowid, metin) VALUES (?,?)",
                            (sid, havuz))
            conn.commit()
        finally:
            conn.close()
    return n


def banka_sil(soru_id, *, yol=None):
    with _KILIT:
        conn = baglan(yol)
        try:
            r = conn.execute("SELECT gorsel_yol FROM sorular WHERE id=?",
                             (int(soru_id),)).fetchone()
            conn.execute("DELETE FROM sorular WHERE id=?", (int(soru_id),))
            if _FTS_VAR:
                conn.execute("DELETE FROM arama WHERE rowid=?", (int(soru_id),))
            conn.commit()
        finally:
            conn.close()
    # media dosyası hash-paylaşımlı olabilir; başka satır kullanıyorsa silme
    if r:
        _media_temizle_tek(r["gorsel_yol"], yol)
    return bool(r)


def _media_temizle_tek(rel, yol):
    conn = baglan(yol)
    try:
        kalan = conn.execute(
            "SELECT COUNT(*) FROM sorular WHERE gorsel_yol=?", (rel,)
        ).fetchone()[0]
    finally:
        conn.close()
    if kalan == 0:
        tam = os.path.join(os.path.dirname(db_yolu(yol)), rel)
        try:
            os.remove(tam)
        except OSError:
            pass


def banka_istatistik(*, yol=None):
    conn = baglan(yol)
    try:
        toplam = conn.execute("SELECT COUNT(*) FROM sorular").fetchone()[0]
        konu = {r[0] or "(konusuz)": r[1] for r in conn.execute(
            "SELECT konu, COUNT(*) FROM sorular GROUP BY konu")}
        kaynak = {r[0] or "(?)": r[1] for r in conn.execute(
            "SELECT kaynak, COUNT(*) FROM sorular GROUP BY kaynak")}
        cevap = {r[0] or "(boş)": r[1] for r in conn.execute(
            "SELECT cevap, COUNT(*) FROM sorular GROUP BY cevap")}
        zorluk = {r[0] or "(?)": r[1] for r in conn.execute(
            "SELECT zorluk, COUNT(*) FROM sorular GROUP BY zorluk")}
        soru_turu = {r[0] or "(?)": r[1] for r in conn.execute(
            "SELECT soru_turu, COUNT(*) FROM sorular GROUP BY soru_turu")}
        sayfa_rolu = {r[0] or "(?)": r[1] for r in conn.execute(
            "SELECT sayfa_rolu, COUNT(*) FROM sorular GROUP BY sayfa_rolu")}
        inceleme = {r[0] or "(?)": r[1] for r in conn.execute(
            "SELECT inceleme_durumu, COUNT(*) FROM sorular "
            "GROUP BY inceleme_durumu")}
        guven_ortalama = conn.execute(
            "SELECT AVG(guven) FROM sorular WHERE guven IS NOT NULL"
        ).fetchone()[0]
        etiketli = conn.execute(
            "SELECT COUNT(*) FROM sorular WHERE baslik IS NOT NULL "
            "AND baslik != ''").fetchone()[0]
        # Konu × zorluk çaprazı (sihirbaz blueprint matrisi için)
        konu_zorluk = {}
        for r in conn.execute(
                "SELECT konu, zorluk, COUNT(*) FROM sorular "
                "GROUP BY konu, zorluk"):
            k = r[0] or "(konusuz)"
            z = r[1] or "(?)"
            konu_zorluk.setdefault(k, {})[z] = r[2]
    finally:
        conn.close()
    return {"toplam": toplam, "konu": konu, "kaynak": kaynak,
            "cevap": cevap, "zorluk": zorluk, "ai_etiketli": etiketli,
            "soru_turu": soru_turu, "sayfa_rolu": sayfa_rolu,
            "inceleme_durumu": inceleme,
            "konu_zorluk": konu_zorluk,
            "guven_ortalama": guven_ortalama}


# --------------------------------------------------- sınav sihirbazı (V5)

def banka_blueprint_sec(hucreler, *, genel_filtre=None, tohum=None,
                        haric_idler=None, yol=None):
    """Konu×zorluk kotalı örnekleme. hucreler: [{konu,zorluk,etiket,kaynak,
    arama,adet}]. genel_filtre her hücreye VE'lenir (tarih dahil). Örnekleme
    Python random.Random(tohum) ile (SQLite RANDOM tohumlanamaz); hücreler
    arası aynı soru iki kez sayılmaz. Dönüş: {idler, hucreler[rapor],
    eksik_toplam}."""
    import random
    rnd = random.Random(tohum)
    conn = baglan(yol)
    genel = dict(genel_filtre or {})
    haric = set(haric_idler or [])
    kullanilan = set(haric)
    rapor = []
    tum_idler = []
    try:
        for h in hucreler:
            f = dict(genel)
            for k in ("konu", "zorluk", "etiket", "kaynak", "arama"):
                if h.get(k):
                    f[k] = h[k]
            kosul, param = _sorgu_kosullari(f)
            where = ("WHERE " + " AND ".join(kosul)) if kosul else ""
            adaylar = [r[0] for r in conn.execute(
                f"SELECT id FROM sorular {where}", param).fetchall()
                if r[0] not in kullanilan]
            istenen = int(h.get("adet", 0))
            secilen = (adaylar if istenen >= len(adaylar)
                       else rnd.sample(adaylar, istenen))
            kullanilan.update(secilen)
            tum_idler.extend(secilen)
            rapor.append({"konu": h.get("konu"), "zorluk": h.get("zorluk"),
                          "istenen": istenen, "bulunan": len(secilen),
                          "eksik": max(0, istenen - len(secilen)),
                          "secilen_idler": secilen})
    finally:
        conn.close()
    return {"idler": tum_idler, "hucreler": rapor,
            "eksik_toplam": sum(r["eksik"] for r in rapor)}


def banka_toplu_guncelle(idler, *, konu=None, zorluk=None, cevap=None,
                         etiket_ekle=None, etiket_sil=None, yol=None):
    """Seçili sorulara toplu düzenleme (bilinçli açık atama). etiket_ekle:
    {anahtar: deger}, etiket_sil: [anahtar]. FTS tazelenir."""
    if not idler:
        return {"guncellenen": 0}
    with _KILIT:
        conn = baglan(yol)
        try:
            q = ",".join("?" * len(idler))
            for sutun, deger in (("konu", konu), ("zorluk", zorluk),
                                 ("cevap", cevap)):
                if deger is not None:
                    conn.execute(
                        f"UPDATE sorular SET {sutun}=? WHERE id IN ({q})",
                        [deger] + list(idler))
            for anahtar, deg in (etiket_ekle or {}).items():
                for sid in idler:
                    conn.execute(
                        "INSERT OR REPLACE INTO etiketler(soru_id,anahtar,deger)"
                        " VALUES(?,?,?)", (sid, anahtar, deg))
            for anahtar in (etiket_sil or []):
                conn.execute(
                    f"DELETE FROM etiketler WHERE anahtar=? AND soru_id IN ({q})",
                    [anahtar] + list(idler))
            if konu is not None and _FTS_VAR:
                q2 = ",".join("?" * len(idler))
                for r in conn.execute(
                        f"SELECT id, metin, konu, baslik FROM sorular "
                        f"WHERE id IN ({q2})", list(idler)).fetchall():
                    havuz = _arama_metni({"metin": r["metin"],
                                          "konu": r["konu"],
                                          "baslik": r["baslik"]})
                    conn.execute("DELETE FROM arama WHERE rowid=?", (r["id"],))
                    conn.execute(
                        "INSERT INTO arama(rowid, metin) VALUES (?,?)",
                        (r["id"], havuz))
            conn.commit()
        finally:
            conn.close()
    return {"guncellenen": len(idler)}


def banka_mukerrer_rapor(sorular, kirpmalar, *, yol=None):
    """İçe alma ÖNCESİ mükerrer raporu (YAZMAZ). Her aday için icerik_hash +
    ahash ile eşleşme arar. Dönüş: [{indeks, durum, mevcut_id, mevcut_konu}]."""
    conn = baglan(yol)
    rapor = []
    try:
        for i, (so, img) in enumerate(zip(sorular, kirpmalar)):
            ah = _ahash(img) if img is not None else None
            h = icerik_hash(so, ah)
            row = conn.execute(
                "SELECT id, konu FROM sorular WHERE icerik_hash=?",
                (h,)).fetchone()
            if row:
                rapor.append({"indeks": i, "durum": "mukerrer",
                              "mevcut_id": row["id"], "mevcut_konu": row["konu"]})
            else:
                rapor.append({"indeks": i, "durum": "yeni",
                              "mevcut_id": None, "mevcut_konu": None})
    finally:
        conn.close()
    yeni = sum(1 for r in rapor if r["durum"] == "yeni")
    return {"rapor": rapor, "yeni": yeni, "mukerrer": len(rapor) - yeni}


def sablon_kaydet(ad, veri, *, tur="blueprint", sablon_id=None, yol=None):
    """Sınav sihirbazı şablonu kaydeder/günceller. veri: JSON-serileşebilir."""
    import time
    veri_json = json.dumps(veri, ensure_ascii=False)
    with _KILIT:
        conn = baglan(yol)
        try:
            simdi = time.time()
            if sablon_id:
                conn.execute(
                    "UPDATE sinav_sablonlari SET ad=?, tur=?, veri_json=?, "
                    "guncelleme_ts=? WHERE id=?",
                    (ad, tur, veri_json, simdi, sablon_id))
                yeni_id = sablon_id
            else:
                cur = conn.execute(
                    "INSERT INTO sinav_sablonlari(ad,tur,veri_json,"
                    "olusturma_ts,guncelleme_ts) VALUES(?,?,?,?,?)",
                    (ad, tur, veri_json, simdi, simdi))
                yeni_id = cur.lastrowid
            conn.commit()
        finally:
            conn.close()
    return {"id": yeni_id}


def sablon_liste(*, tur=None, yol=None):
    conn = baglan(yol)
    try:
        if tur:
            rows = conn.execute(
                "SELECT id,ad,tur,guncelleme_ts FROM sinav_sablonlari "
                "WHERE tur=? ORDER BY guncelleme_ts DESC", (tur,)).fetchall()
        else:
            rows = conn.execute(
                "SELECT id,ad,tur,guncelleme_ts FROM sinav_sablonlari "
                "ORDER BY guncelleme_ts DESC").fetchall()
        return [{"id": r["id"], "ad": r["ad"], "tur": r["tur"],
                 "guncelleme_ts": r["guncelleme_ts"]} for r in rows]
    finally:
        conn.close()


def sablon_getir(sablon_id, *, yol=None):
    conn = baglan(yol)
    try:
        r = conn.execute("SELECT * FROM sinav_sablonlari WHERE id=?",
                         (sablon_id,)).fetchone()
        if not r:
            return None
        return {"id": r["id"], "ad": r["ad"], "tur": r["tur"],
                "veri": json.loads(r["veri_json"])}
    finally:
        conn.close()


def sablon_sil(sablon_id, *, yol=None):
    with _KILIT:
        conn = baglan(yol)
        try:
            conn.execute("DELETE FROM sinav_sablonlari WHERE id=?",
                         (sablon_id,))
            conn.commit()
        finally:
            conn.close()
    return {"silindi": sablon_id}


def banka_bakim(*, yol=None):
    """Yetim media dosyalarını temizler + integrity_check + VACUUM. TÜMÜ _KILIT
    altında: aksi hâlde eşzamanlı banka_ekle'nin yeni yazdığı medyayı yetim sanıp
    silme (TOCTOU veri kaybı) ve çakışan VACUUM riski doğar."""
    dbyol = db_yolu(yol)
    medya = _media_dizin(dbyol)
    with _KILIT:
        conn = baglan(yol)
        try:
            kullanilan = {r[0] for r in conn.execute(
                "SELECT gorsel_yol FROM sorular")}
            butun = conn.execute("PRAGMA integrity_check").fetchone()[0]
        finally:
            conn.close()
        silinen = 0
        for kok, _, dosyalar in os.walk(medya):
            for d in dosyalar:
                tam = os.path.join(kok, d)
                rel = os.path.relpath(tam, os.path.dirname(dbyol))
                if rel not in kullanilan:
                    try:
                        os.remove(tam); silinen += 1
                    except OSError:
                        pass
        conn = baglan(yol)
        try:
            conn.execute("VACUUM")
        finally:
            conn.close()
    return {"integrity": butun, "yetim_silinen": silinen}
