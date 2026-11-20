#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik sınav kalıcılığı — SQLite (soru_bankasi.py deseni).

Konum: ~/Library/Application Support/soru-kesici/optik/
    optik.db                (şema PRAGMA user_version ile sürümlü)
    media/<sinav_id>/       (yükleme kopyaları + warp önizlemeleri)

Kağıt kaydı taranan SAYFA başınadır; çok sayfalı formlarda aynı öğrencinin
sayfaları puanlama sırasında ogrenci_no üzerinden birleştirilir
(optik_analiz.puanla).
"""
import datetime
import json
import os
import shutil
import sqlite3

import optik_sema as osm
import veri_yollari

VARSAYILAN_DIZIN = os.path.join(veri_yollari.veri_koku(), "optik")

_SEMA = """
CREATE TABLE IF NOT EXISTS sinavlar (
    id            TEXT PRIMARY KEY,
    ad            TEXT NOT NULL,
    olusturma     TEXT NOT NULL,
    sablon_json   TEXT NOT NULL,
    ayarlar_json  TEXT NOT NULL DEFAULT '{}',
    kazanim_json  TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS anahtarlar (
    sinav_id      TEXT NOT NULL,
    kitapcik      TEXT NOT NULL,
    cevaplar_json TEXT NOT NULL,
    PRIMARY KEY (sinav_id, kitapcik)
);
CREATE TABLE IF NOT EXISTS kagitlar (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    sinav_id        TEXT NOT NULL,
    kaynak          TEXT,
    kaynak_sayfa    INTEGER,
    sayfa_no        INTEGER,
    qr              TEXT,
    durum           TEXT NOT NULL DEFAULT 'okundu',
    ogrenci_no      TEXT,
    ad_soyad        TEXT,
    tc_kimlik       TEXT,
    kitapcik        TEXT,
    okuma_json      TEXT NOT NULL DEFAULT '{}',
    duzeltme_json   TEXT NOT NULL DEFAULT '{}',
    warp_png        TEXT,
    olusturma       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS kagit_sinav ON kagitlar(sinav_id, durum);
"""


def optik_dizin(yol=None):
    dizin = yol or VARSAYILAN_DIZIN
    os.makedirs(dizin, exist_ok=True)
    return dizin


def db_yolu(yol=None):
    return os.path.join(optik_dizin(yol), "optik.db")


def media_dizin(sinav_id, yol=None):
    dizin = os.path.join(optik_dizin(yol), "media", sinav_id)
    os.makedirs(dizin, exist_ok=True)
    return dizin


def baglan(yol=None):
    conn = sqlite3.connect(db_yolu(yol))
    conn.row_factory = sqlite3.Row
    conn.executescript(_SEMA)
    if conn.execute("PRAGMA user_version").fetchone()[0] < 1:
        conn.execute("PRAGMA user_version = 1")
    conn.commit()
    return conn


def _simdi():
    return datetime.datetime.now().isoformat(timespec="seconds")


# ---------------------------------------------------------------------- sınavlar

def sinav_ekle(conn, sablon, ayarlar=None):
    conn.execute(
        "INSERT OR REPLACE INTO sinavlar "
        "(id, ad, olusturma, sablon_json, ayarlar_json) "
        "VALUES (?,?,?,?,?)",
        (sablon.sinav_id, sablon.ad, sablon.olusturma or _simdi(),
         json.dumps(osm.sablon_dict(sablon), ensure_ascii=False),
         json.dumps(ayarlar or {}, ensure_ascii=False)))
    conn.commit()
    return sablon.sinav_id


def sinav_listesi(conn):
    satirlar = conn.execute(
        "SELECT s.id, s.ad, s.olusturma, s.ayarlar_json, "
        "  (SELECT COUNT(*) FROM kagitlar k WHERE k.sinav_id = s.id) "
        "    AS kagit_sayisi, "
        "  (SELECT COUNT(*) FROM kagitlar k WHERE k.sinav_id = s.id "
        "     AND k.durum = 'incelenecek') AS inceleme_sayisi, "
        "  (SELECT COUNT(*) FROM anahtarlar a WHERE a.sinav_id = s.id) "
        "    AS anahtar_sayisi "
        "FROM sinavlar s ORDER BY s.olusturma DESC").fetchall()
    return [dict(s, ayarlar=json.loads(s["ayarlar_json"]))
            for s in ({**dict(r)} for r in satirlar)]


def sinav_al(conn, sinav_id):
    r = conn.execute("SELECT * FROM sinavlar WHERE id = ?",
                     (sinav_id,)).fetchone()
    if r is None:
        return None
    return {"id": r["id"], "ad": r["ad"], "olusturma": r["olusturma"],
            "sablon": osm.sablon_kur(json.loads(r["sablon_json"])),
            "ayarlar": json.loads(r["ayarlar_json"]),
            "kazanimlar": json.loads(r["kazanim_json"])}


def sinav_sil(conn, sinav_id, yol=None):
    conn.execute("DELETE FROM kagitlar WHERE sinav_id = ?", (sinav_id,))
    conn.execute("DELETE FROM anahtarlar WHERE sinav_id = ?", (sinav_id,))
    conn.execute("DELETE FROM sinavlar WHERE id = ?", (sinav_id,))
    conn.commit()
    dizin = os.path.join(optik_dizin(yol), "media", sinav_id)
    shutil.rmtree(dizin, ignore_errors=True)


def kazanim_koy(conn, sinav_id, kazanimlar):
    """kazanimlar: {ders: {soru_no(str): "kazanım metni"}}"""
    conn.execute("UPDATE sinavlar SET kazanim_json = ? WHERE id = ?",
                 (json.dumps(kazanimlar, ensure_ascii=False), sinav_id))
    conn.commit()


# --------------------------------------------------------------------- anahtarlar

def anahtar_koy(conn, sinav_id, kitapcik, cevaplar):
    """cevaplar: {ders: {soru_no(str): "A"|"AB"(çoklu doğru)|""}}"""
    conn.execute(
        "INSERT OR REPLACE INTO anahtarlar (sinav_id, kitapcik, "
        "cevaplar_json) VALUES (?,?,?)",
        (sinav_id, kitapcik, json.dumps(cevaplar, ensure_ascii=False)))
    conn.commit()


def anahtarlar(conn, sinav_id):
    satirlar = conn.execute(
        "SELECT kitapcik, cevaplar_json FROM anahtarlar "
        "WHERE sinav_id = ? ORDER BY kitapcik", (sinav_id,)).fetchall()
    return {r["kitapcik"]: json.loads(r["cevaplar_json"])
            for r in satirlar}


# ----------------------------------------------------------------------- kağıtlar

def kagit_ekle(conn, sinav_id, kagit, yol=None):
    """parti_oku çıktısındaki tek kağıt kaydını saklar; medya kopyalanır."""
    media = media_dizin(sinav_id, yol)
    warp_hedef = None
    if kagit.get("warp_png") and os.path.isfile(kagit["warp_png"]):
        warp_hedef = os.path.join(
            media, f"warp-{_simdi().replace(':', '')}-"
                   f"{os.path.basename(kagit['warp_png'])}")
        shutil.copyfile(kagit["warp_png"], warp_hedef)
    okuma = {k: kagit.get(k) for k in
             ("cevaplar", "sorunlar", "kayit", "olcumler", "hata")}
    imlec = conn.execute(
        "INSERT INTO kagitlar (sinav_id, kaynak, kaynak_sayfa, sayfa_no, "
        "qr, durum, ogrenci_no, ad_soyad, tc_kimlik, kitapcik, "
        "okuma_json, warp_png, olusturma) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (sinav_id, kagit.get("kaynak"), kagit.get("kaynak_sayfa"),
         kagit.get("sayfa_no"), kagit.get("qr"),
         kagit.get("durum", "okundu"), kagit.get("ogrenci_no"),
         kagit.get("ad_soyad"), kagit.get("tc_kimlik"),
         kagit.get("kitapcik"),
         json.dumps(okuma, ensure_ascii=False), warp_hedef, _simdi()))
    conn.commit()
    return imlec.lastrowid


def _kagit_dict(r):
    okuma = json.loads(r["okuma_json"])
    duzeltme = json.loads(r["duzeltme_json"])
    cevaplar = okuma.get("cevaplar") or {}
    # düzeltmeler okumanın üstüne bindirilir
    for ders, sorular in (duzeltme.get("cevaplar") or {}).items():
        hedef = cevaplar.setdefault(ders, {})
        for no, sembol in sorular.items():
            hedef[no] = {"hukum": "tek" if sembol else "bos",
                         "sembol": sembol or None, "guven": 1.0,
                         "adaylar": [sembol] if sembol else [],
                         "iptal": [], "duzeltildi": True}
    return {"id": r["id"], "sinav_id": r["sinav_id"],
            "kaynak": r["kaynak"], "kaynak_sayfa": r["kaynak_sayfa"],
            "sayfa_no": r["sayfa_no"], "qr": r["qr"], "durum": r["durum"],
            "ogrenci_no": duzeltme.get("ogrenci_no") or r["ogrenci_no"],
            "ad_soyad": duzeltme.get("ad_soyad") or r["ad_soyad"],
            "tc_kimlik": r["tc_kimlik"],
            "kitapcik": duzeltme.get("kitapcik") or r["kitapcik"],
            "cevaplar": cevaplar, "sorunlar": okuma.get("sorunlar") or [],
            "kayit": okuma.get("kayit"), "hata": okuma.get("hata"),
            "warp_png": r["warp_png"], "olusturma": r["olusturma"],
            "duzeltme": duzeltme}


def kagitlar(conn, sinav_id, durum=None):
    sorgu = "SELECT * FROM kagitlar WHERE sinav_id = ?"
    parametre = [sinav_id]
    if durum:
        sorgu += " AND durum = ?"
        parametre.append(durum)
    sorgu += " ORDER BY id"
    return [_kagit_dict(r) for r in conn.execute(sorgu, parametre)]


def kagit_al(conn, kagit_id):
    r = conn.execute("SELECT * FROM kagitlar WHERE id = ?",
                     (kagit_id,)).fetchone()
    return _kagit_dict(r) if r else None


def kagit_olcumleri(conn, kagit_id):
    r = conn.execute("SELECT okuma_json FROM kagitlar WHERE id = ?",
                     (kagit_id,)).fetchone()
    if not r:
        return []
    return (json.loads(r["okuma_json"]).get("olcumler")) or []


def kagit_duzelt(conn, kagit_id, duzeltme):
    """İnceleme ekranı düzeltmesi: {"cevaplar": {ders: {no: "B"|""}},
    "ogrenci_no": ..., "kitapcik": ..., "ad_soyad": ...} — birikimli."""
    r = conn.execute("SELECT duzeltme_json FROM kagitlar WHERE id = ?",
                     (kagit_id,)).fetchone()
    if r is None:
        raise ValueError(f"kağıt yok: {kagit_id}")
    mevcut = json.loads(r["duzeltme_json"])
    for anahtar in ("ogrenci_no", "kitapcik", "ad_soyad"):
        if anahtar in duzeltme:
            mevcut[anahtar] = duzeltme[anahtar]
    if duzeltme.get("cevaplar"):
        hedef = mevcut.setdefault("cevaplar", {})
        for ders, sorular in duzeltme["cevaplar"].items():
            hedef.setdefault(ders, {}).update(sorular)
    conn.execute(
        "UPDATE kagitlar SET duzeltme_json = ?, durum = 'okundu' "
        "WHERE id = ?",
        (json.dumps(mevcut, ensure_ascii=False), kagit_id))
    conn.commit()


def kagit_sil(conn, kagit_id):
    r = conn.execute("SELECT warp_png FROM kagitlar WHERE id = ?",
                     (kagit_id,)).fetchone()
    if r and r["warp_png"]:
        try:
            os.unlink(r["warp_png"])
        except OSError:
            pass
    conn.execute("DELETE FROM kagitlar WHERE id = ?", (kagit_id,))
    conn.commit()
