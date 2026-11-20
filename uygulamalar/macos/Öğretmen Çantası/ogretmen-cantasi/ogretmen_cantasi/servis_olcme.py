"""Soru havuzu, sınav, deneme ve materyal işlemleri.

`servis` modülünden ayrı tutuldu: ölçme tarafı kendi içinde bütün ve orada
büyümeye devam edecek (Sınav Okur ve Soru Kesici bağlantıları buraya gelecek).
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime

from . import depo
from . import mufredat as mf
from . import sinav as sn

KAYNAK_ELLE = "elle"
KAYNAK_SORU_KESICI = "soru_kesici"
KAYNAK_SORU_COZUCU = "soru_cozucu"


# --- soru havuzu ---------------------------------------------------------


def soru_ekle(
    baglanti: sqlite3.Connection,
    *,
    mufredat_surumu: str,
    kazanim_kodu: str,
    sinif: int,
    metin: str,
    rubrik: str = "",
    gorsel_yolu: str = "",
    zorluk: str = "orta",
    kaynak: str = KAYNAK_ELLE,
) -> int:
    imlec = baglanti.execute(
        "INSERT INTO soru (mufredat_surumu, kazanim_kodu, sinif, metin, gorsel_yolu, rubrik, "
        "zorluk, kaynak, olusturma) VALUES (?,?,?,?,?,?,?,?,?)",
        (
            mufredat_surumu,
            kazanim_kodu,
            sinif,
            metin.strip(),
            gorsel_yolu,
            rubrik.strip(),
            zorluk,
            kaynak,
            datetime.now().isoformat(timespec="seconds"),
        ),
    )
    return imlec.lastrowid or 0


def soru_arsivle(baglanti: sqlite3.Connection, soru_id: int) -> None:
    imlec = baglanti.execute("UPDATE soru SET aktif = 0 WHERE id = ?", (soru_id,))
    if imlec.rowcount != 1:
        raise LookupError(f"Soru bulunamadı: {soru_id}")


def soru_geri_al(baglanti: sqlite3.Connection, soru_id: int) -> None:
    imlec = baglanti.execute("UPDATE soru SET aktif = 1 WHERE id = ?", (soru_id,))
    if imlec.rowcount != 1:
        raise LookupError(f"Soru bulunamadı: {soru_id}")


def sorulari_oku(
    baglanti: sqlite3.Connection,
    *,
    sinif: int | None = None,
    kazanim_kodu: str = "",
    arama: str = "",
    aktif: bool = True,
) -> list[sqlite3.Row]:
    kosullar: list[str] = ["aktif = ?"]
    degerler: list[object] = [1 if aktif else 0]
    if sinif is not None:
        kosullar.append("sinif = ?")
        degerler.append(sinif)
    if kazanim_kodu:
        kosullar.append("kazanim_kodu LIKE ?")
        degerler.append(f"{kazanim_kodu}%")
    if arama:
        kosullar.append("metin LIKE ?")
        degerler.append(f"%{arama}%")
    nerede = f"WHERE {' AND '.join(kosullar)}" if kosullar else ""
    return baglanti.execute(
        f"SELECT * FROM soru {nerede} ORDER BY kazanim_kodu, id", degerler
    ).fetchall()


def havuzu_kur(satirlar: list[sqlite3.Row]) -> list[sn.Soru]:
    return [
        sn.Soru(
            id=s["id"],
            kazanim_kodu=s["kazanim_kodu"],
            metin=s["metin"],
            puan=s["puan"],
            rubrik=s["rubrik"],
            gorsel_yolu=s["gorsel_yolu"],
            zorluk=s["zorluk"],
        )
        for s in satirlar
    ]


def kazanim_soru_sayilari(baglanti: sqlite3.Connection, sinif: int) -> dict[str, int]:
    satirlar = baglanti.execute(
        "SELECT kazanim_kodu, COUNT(*) AS adet FROM soru "
        "WHERE sinif = ? AND aktif = 1 GROUP BY kazanim_kodu",
        (sinif,),
    ).fetchall()
    return {s["kazanim_kodu"]: s["adet"] for s in satirlar}


# --- sınav ---------------------------------------------------------------


def sinav_uret_ve_kaydet(
    baglanti: sqlite3.Connection,
    *,
    sube_id: int,
    sube_adi: str,
    sinif: int,
    mufredat_surumu: str,
    ad: str,
    dagilim: dict[str, float],
    soru_sayisi: int,
    sure_dk: int = 40,
    gruplar: tuple[str, ...] = sn.VARSAYILAN_GRUPLAR,
    tarih: str = "",
    tohum: int = 0,
) -> tuple[int, sn.Sinav, list[str]]:
    havuz = havuzu_kur(sorulari_oku(baglanti, sinif=sinif))
    program = mf.yukle(mufredat_surumu)
    adlar = {
        f"BİY.{sinif}.{t.no}": f"{t.no}. TEMA: {t.ad}" for t in program.duzey(sinif).temalar
    }
    sinav, uyarilar = sn.sinav_uret(
        ad=ad,
        sube_adi=sube_adi,
        sinif=sinif,
        havuz=havuz,
        dagilim=dagilim,
        soru_sayisi=soru_sayisi,
        sure_dk=sure_dk,
        gruplar=gruplar,
        adlar=adlar,
        tohum=tohum,
    )

    with depo.islem(baglanti, immediate=True):
        imlec = baglanti.execute(
            "INSERT INTO sinav (sube_id, ad, tarih, sure_dk, gruplar, belirtke, olusturma) "
            "VALUES (?,?,?,?,?,?,?)",
            (
                sube_id,
                ad,
                tarih,
                sure_dk,
                ",".join(gruplar),
                json.dumps(dagilim, ensure_ascii=False),
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        sinav_id = imlec.lastrowid or 0
        for sira, soru in enumerate(sinav.sorular, start=1):
            baglanti.execute(
                "INSERT INTO sinav_sorusu "
                "(sinav_id, soru_id, sira, puan, kazanim_kodu, metin, rubrik, "
                "gorsel_yolu, zorluk) VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    sinav_id,
                    soru.id,
                    sira,
                    soru.puan,
                    soru.kazanim_kodu,
                    soru.metin,
                    soru.rubrik,
                    soru.gorsel_yolu,
                    soru.zorluk,
                ),
            )
    return sinav_id, sinav, uyarilar


def sinavlari_oku(baglanti: sqlite3.Connection, sube_id: int) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT s.*, (SELECT COUNT(*) FROM sinav_sorusu q WHERE q.sinav_id = s.id) AS soru_sayisi "
        "FROM sinav s WHERE s.sube_id = ? ORDER BY s.id DESC",
        (sube_id,),
    ).fetchall()


def sinav_kaydi(baglanti: sqlite3.Connection, sinav_id: int) -> sqlite3.Row | None:
    """Sınavın ham kaydı; web katmanı varlık ve şube bilgisini buradan alır."""
    return baglanti.execute("SELECT * FROM sinav WHERE id = ?", (sinav_id,)).fetchone()


def sinavi_yukle(baglanti: sqlite3.Connection, sinav_id: int) -> sn.Sinav:
    kayit = baglanti.execute("SELECT * FROM sinav WHERE id = ?", (sinav_id,)).fetchone()
    if not kayit:
        raise LookupError(f"Sınav bulunamadı: {sinav_id}")
    sube = baglanti.execute("SELECT * FROM sube WHERE id = ?", (kayit["sube_id"],)).fetchone()
    satirlar = baglanti.execute(
        "SELECT q.* FROM sinav_sorusu q WHERE q.sinav_id = ? ORDER BY q.sira",
        (sinav_id,),
    ).fetchall()
    sorular = [
        sn.Soru(
            # Dış arayüzdeki kimlik geriye uyumlu olarak havuz sorusudur;
            # puan kaydı içeride bu satırın kararlı `sinav_sorusu.id` değerine
            # çevrilir.
            id=s["soru_id"],
            kazanim_kodu=s["kazanim_kodu"],
            metin=s["metin"],
            puan=s["puan"],
            rubrik=s["rubrik"],
            gorsel_yolu=s["gorsel_yolu"],
            zorluk=s["zorluk"],
        )
        for s in satirlar
    ]
    dagilim = json.loads(kayit["belirtke"] or "{}")
    gruplar = tuple(g for g in (kayit["gruplar"] or "A").split(",") if g)
    program = mf.yukle(sube["mufredat_surumu"])
    adlar = {
        f"BİY.{sube['sinif']}.{t.no}": f"{t.no}. TEMA: {t.ad}"
        for t in program.duzey(sube["sinif"]).temalar
    }
    return sn.Sinav(
        ad=kayit["ad"],
        sube_adi=sube["ad"],
        sinif=sube["sinif"],
        sure_dk=kayit["sure_dk"],
        sorular=sorular,
        belirtke=sn.belirtke_kur(sorular, dagilim, adlar),
        # Sıra veritabanında saklandığı için gruplar aynı tohumla yeniden
        # üretilir; yazdırılan kâğıtla anahtarın sırası böyle bir tutar.
        gruplar=sn.gruplari_uret(sorular, gruplar, tohum=sinav_id),
    )


def sinav_sil(
    baglanti: sqlite3.Connection, sinav_id: int, *, sube_id: int | None = None
) -> None:
    sorgu = "DELETE FROM sinav WHERE id = ?"
    parametreler: tuple[int, ...] = (sinav_id,)
    if sube_id is not None:
        sorgu += " AND sube_id = ?"
        parametreler += (sube_id,)
    imlec = baglanti.execute(sorgu, parametreler)
    if imlec.rowcount != 1:
        raise LookupError("Sınav bu şubede bulunamadı.")


def soru_puani_yaz(
    baglanti: sqlite3.Connection, sinav_id: int, puanlar: list[tuple[int, int, float]]
) -> None:
    """(soru_id, ogrenci_id, puan) üçlülerini atomik olarak yazar."""
    sinav = baglanti.execute("SELECT sube_id FROM sinav WHERE id = ?", (sinav_id,)).fetchone()
    if not sinav:
        raise LookupError(f"Sınav bulunamadı: {sinav_id}")
    with depo.islem(baglanti, immediate=True):
        for soru_id, ogrenci_id, puan in puanlar:
            soru = baglanti.execute(
                "SELECT id, puan FROM sinav_sorusu WHERE soru_id = ? AND sinav_id = ?",
                (soru_id, sinav_id),
            ).fetchone()
            ogrenci = baglanti.execute(
                "SELECT 1 FROM ogrenci WHERE id = ? AND sube_id = ? AND aktif = 1",
                (ogrenci_id, sinav["sube_id"]),
            ).fetchone()
            if not soru or not ogrenci:
                raise ValueError("Soru veya öğrenci bu sınava ait değil.")
            if not 0 <= puan <= float(soru["puan"]):
                raise ValueError("Puan sorunun puan aralığı dışında.")
            baglanti.execute(
                "INSERT INTO soru_puani (sinav_sorusu_id, ogrenci_id, puan) VALUES (?,?,?) "
                "ON CONFLICT (sinav_sorusu_id, ogrenci_id) DO UPDATE SET puan = excluded.puan",
                (soru["id"], ogrenci_id, puan),
            )


def sinav_puanlari(baglanti: sqlite3.Connection, sinav_id: int) -> dict[tuple[int, int], float]:
    return {
        (s["ogrenci_id"], s["soru_id"]): s["puan"]
        for s in baglanti.execute(
            "SELECT q.soru_id, p.ogrenci_id, p.puan FROM soru_puani p "
            "JOIN sinav_sorusu q ON q.id = p.sinav_sorusu_id WHERE q.sinav_id = ?",
            (sinav_id,),
        )
    }


def sinav_kazanim_analizi(baglanti: sqlite3.Connection, sinav_id: int) -> dict:
    """Sınavın kazanım bazlı sınıf ve öğrenci analizini üretir."""
    sorular = {
        s["id"]: s
        for s in baglanti.execute(
            "SELECT id, puan, kazanim_kodu FROM sinav_sorusu WHERE sinav_id = ?",
            (sinav_id,),
        )
    }
    kayitlar = baglanti.execute(
        "SELECT p.ogrenci_id, p.sinav_sorusu_id, p.puan, o.ad_soyad, o.numara "
        "FROM soru_puani p JOIN sinav_sorusu q ON q.id = p.sinav_sorusu_id "
        "JOIN ogrenci o ON o.id = p.ogrenci_id WHERE q.sinav_id = ?",
        (sinav_id,),
    ).fetchall()

    sinif_kayitlari = [
        (
            k["ogrenci_id"],
            sorular[k["sinav_sorusu_id"]]["kazanim_kodu"],
            k["puan"],
            sorular[k["sinav_sorusu_id"]]["puan"],
        )
        for k in kayitlar
        if k["sinav_sorusu_id"] in sorular
    ]
    ogrenci_bazli: dict[int, dict] = {}
    for k in kayitlar:
        if k["sinav_sorusu_id"] not in sorular:
            continue
        kayit = ogrenci_bazli.setdefault(
            k["ogrenci_id"],
            {"ad_soyad": k["ad_soyad"], "numara": k["numara"], "puanlar": [], "kazanimlar": {}},
        )
        soru = sorular[k["sinav_sorusu_id"]]
        kayit["puanlar"].append((soru["kazanim_kodu"], k["puan"], soru["puan"]))

    for kayit in ogrenci_bazli.values():
        analiz = sn.ogrenci_kazanim_analizi(kayit["puanlar"])
        kayit["kazanimlar"] = {a.kazanim_kodu: a.yuzde for a in analiz}
        kayit["toplam"] = round(sum(p for _, p, _ in kayit["puanlar"]), 2)

    sinif = sn.sinif_kazanim_analizi(sinif_kayitlari)
    return {
        "sinif": sinif,
        "ogrenciler": ogrenci_bazli,
        "zayif": sn.zayif_kazanimlar(sinif),
        "kazanimlar": sorted({s["kazanim_kodu"] for s in sorular.values()}),
    }


def ogrenci_kazanim_profili(baglanti: sqlite3.Connection, ogrenci_id: int) -> dict:
    """Öğrencinin girdiği tüm sınavlardaki kazanım başarı geçmişi.

    `gecmis`: kazanım kodu → sınav sırasına dizilmiş {sinav, tarih, yuzde}
    kayıtları. `son`: her kazanımın en son sınavdaki durumu — sayfada ve veli
    raporunda gösterilen özet budur.
    """
    satirlar = baglanti.execute(
        "SELECT v.id AS sinav_id, v.ad AS sinav_adi, v.tarih, v.olusturma, "
        "q.kazanim_kodu, p.puan, q.puan AS tam_puan FROM soru_puani p "
        "JOIN sinav_sorusu q ON q.id = p.sinav_sorusu_id "
        "JOIN sinav v ON v.id = q.sinav_id WHERE p.ogrenci_id = ? "
        "ORDER BY CASE WHEN v.tarih = '' THEN v.olusturma ELSE v.tarih END, v.id",
        (ogrenci_id,),
    ).fetchall()

    sinavlar: dict[int, dict] = {}
    for s in satirlar:
        kayit = sinavlar.setdefault(
            s["sinav_id"], {"ad": s["sinav_adi"], "tarih": s["tarih"], "puanlar": []}
        )
        kayit["puanlar"].append((s["kazanim_kodu"], s["puan"], s["tam_puan"]))

    gecmis: dict[str, list[dict]] = {}
    for kayit in sinavlar.values():
        for analiz in sn.ogrenci_kazanim_analizi(kayit["puanlar"]):
            gecmis.setdefault(analiz.kazanim_kodu, []).append(
                {
                    "sinav": kayit["ad"],
                    "tarih": kayit["tarih"],
                    "yuzde": analiz.yuzde,
                    "durum": analiz.durum,
                }
            )
    son = {kod: kayitlar[-1] for kod, kayitlar in gecmis.items()}
    return {"gecmis": gecmis, "son": son}


def ogrenci_deneme_netleri(baglanti: sqlite3.Connection, ogrenci_id: int) -> list[dict]:
    return [
        dict(satir)
        for satir in baglanti.execute(
            "SELECT d.ad, d.tarih, s.dogru, s.yanlis, s.bos, s.net FROM deneme_sonucu s "
            "JOIN deneme d ON d.id = s.deneme_id WHERE s.ogrenci_id = ? "
            "ORDER BY d.tarih, d.id",
            (ogrenci_id,),
        ).fetchall()
    ]


# --- deneme --------------------------------------------------------------


def deneme_kaydet(
    baglanti: sqlite3.Connection,
    *,
    ad: str,
    tarih: str,
    yayin: str,
    sonuclar: list[tuple[int, int, int, int, float]],
    sube_id: int | None = None,
) -> int:
    """(ogrenci_id, doğru, yanlış, boş, net) kayıtlarıyla bir deneme yazar."""
    with depo.islem(baglanti, immediate=True):
        if sube_id is not None:
            kimlikler = {s[0] for s in sonuclar}
            if kimlikler:
                yer_tutucular = ",".join("?" for _ in kimlikler)
                bulunan = baglanti.execute(
                    f"SELECT COUNT(*) AS adet FROM ogrenci WHERE sube_id = ? AND aktif = 1 "
                    f"AND id IN ({yer_tutucular})",
                    (sube_id, *kimlikler),
                ).fetchone()["adet"]
                if int(bulunan) != len(kimlikler):
                    raise ValueError("Deneme sonuçlarında başka şubeye ait öğrenci var.")
        imlec = baglanti.execute(
            "INSERT INTO deneme (ad, tarih, yayin) VALUES (?,?,?)", (ad, tarih, yayin)
        )
        deneme_id = imlec.lastrowid or 0
        for ogrenci_id, dogru, yanlis, bos, net in sonuclar:
            baglanti.execute(
                "INSERT INTO deneme_sonucu (deneme_id, ogrenci_id, dogru, yanlis, bos, net) "
                "VALUES (?,?,?,?,?,?) ON CONFLICT (deneme_id, ogrenci_id) DO UPDATE SET "
                "dogru = excluded.dogru, yanlis = excluded.yanlis, bos = excluded.bos, "
                "net = excluded.net",
                (deneme_id, ogrenci_id, dogru, yanlis, bos, net),
            )
        return deneme_id


def denemeleri_oku(baglanti: sqlite3.Connection, sube_id: int | None = None) -> list[sqlite3.Row]:
    if sube_id is None:
        return baglanti.execute("SELECT * FROM deneme ORDER BY tarih DESC, id DESC").fetchall()
    return baglanti.execute(
        "SELECT DISTINCT d.* FROM deneme d JOIN deneme_sonucu s ON s.deneme_id = d.id "
        "JOIN ogrenci o ON o.id = s.ogrenci_id WHERE o.sube_id = ? ORDER BY d.tarih DESC, d.id DESC",
        (sube_id,),
    ).fetchall()


def deneme_gelisimi(baglanti: sqlite3.Connection, sube_id: int) -> dict:
    """Şubenin deneme netlerini öğrenci ve deneme kırılımıyla verir."""
    satirlar = baglanti.execute(
        "SELECT d.id AS deneme_id, d.ad AS deneme_adi, d.tarih, o.id AS ogrenci_id, "
        "o.ad_soyad, s.net FROM deneme_sonucu s "
        "JOIN deneme d ON d.id = s.deneme_id JOIN ogrenci o ON o.id = s.ogrenci_id "
        "WHERE o.sube_id = ? ORDER BY d.tarih, d.id, o.ad_soyad",
        (sube_id,),
    ).fetchall()

    denemeler: list[dict] = []
    ogrenciler: dict[int, dict] = {}
    for satir in satirlar:
        if not denemeler or denemeler[-1]["id"] != satir["deneme_id"]:
            denemeler.append({"id": satir["deneme_id"], "ad": satir["deneme_adi"], "tarih": satir["tarih"], "netler": []})
        denemeler[-1]["netler"].append(satir["net"])
        kayit = ogrenciler.setdefault(
            satir["ogrenci_id"], {"ad_soyad": satir["ad_soyad"], "netler": {}}
        )
        kayit["netler"][satir["deneme_id"]] = satir["net"]

    for deneme in denemeler:
        netler = deneme.pop("netler")
        deneme["ortalama"] = round(sum(netler) / len(netler), 2) if netler else None
    return {"denemeler": denemeler, "ogrenciler": ogrenciler}


# --- materyal ------------------------------------------------------------


def materyal_ekle(
    baglanti: sqlite3.Connection,
    *,
    baslik: str,
    kazanim_kodu: str = "",
    sinif: int | None = None,
    tur: str = "baglanti",
    yol: str = "",
    url: str = "",
    etiketler: str = "",
    mufredat_surumu: str = "",
) -> int:
    imlec = baglanti.execute(
        "INSERT INTO materyal (mufredat_surumu, kazanim_kodu, sinif, baslik, tur, yol, url, "
        "etiketler, olusturma) VALUES (?,?,?,?,?,?,?,?,?)",
        (
            mufredat_surumu,
            kazanim_kodu,
            sinif,
            baslik.strip(),
            tur,
            yol,
            url.strip(),
            etiketler.strip(),
            datetime.now().isoformat(timespec="seconds"),
        ),
    )
    return imlec.lastrowid or 0


def materyalleri_oku(
    baglanti: sqlite3.Connection, *, kazanim_kodu: str = "", sinif: int | None = None
) -> list[sqlite3.Row]:
    kosullar: list[str] = []
    degerler: list[object] = []
    if kazanim_kodu:
        kosullar.append("kazanim_kodu LIKE ?")
        degerler.append(f"{kazanim_kodu}%")
    if sinif is not None:
        kosullar.append("sinif = ?")
        degerler.append(sinif)
    nerede = f"WHERE {' AND '.join(kosullar)}" if kosullar else ""
    return baglanti.execute(
        f"SELECT * FROM materyal {nerede} ORDER BY kazanim_kodu, baslik", degerler
    ).fetchall()


def materyal_sil(baglanti: sqlite3.Connection, materyal_id: int) -> None:
    baglanti.execute("DELETE FROM materyal WHERE id = ?", (materyal_id,))


def soru_puani_sil(
    baglanti: sqlite3.Connection, sinav_id: int, hedefler: list[tuple[int, int]]
) -> None:
    """(soru_id, ogrenci_id) çiftlerinin puanını siler.

    Puanlama ekranında bir hücrenin boşaltılması silme isteğidir; eskiden boş
    değerler atlandığı için yanlış girilmiş bir soru puanı geri alınamıyordu.
    """
    with depo.islem(baglanti, immediate=True):
        for soru_id, ogrenci_id in hedefler:
            baglanti.execute(
                "DELETE FROM soru_puani WHERE ogrenci_id = ? AND sinav_sorusu_id = ("
                "SELECT id FROM sinav_sorusu WHERE sinav_id = ? AND soru_id = ?)",
                (ogrenci_id, sinav_id, soru_id),
            )
