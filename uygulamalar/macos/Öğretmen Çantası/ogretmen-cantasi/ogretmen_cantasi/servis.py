"""Veritabanı üzerindeki alan işlemleri.

Web katmanı SQL yazmaz; her işlem burada bir fonksiyondur. Böylece aynı işlem
hem arayüzden hem komut satırından çağrılabiliyor ve testler sunucuya ihtiyaç
duymadan yazılabiliyor.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from datetime import date, datetime

from . import depo
from . import mufredat as mf
from . import notlar as nt
from . import takvim as tk
from . import yoklama as yk
from .plan import gunluk as gp
from .plan import yillik as yp

AYAR_OKUL = "okul_adi"
AYAR_OGRETMEN = "ogretmen_adi"
AYAR_DERS_DAKIKASI = "ders_dakikasi"
AYAR_YAZILI_SAYISI = "donem_basina_yazili"
AYAR_PERFORMANS_SAYISI = "donem_basina_performans"
AYAR_GECME_PUANI = "gecme_puani"
# Varsayılan 10, MEB Ortaöğretim Kurumları Yönetmeliği md. 36'daki özürsüz
# devamsızlık sınırıdır. Okul türüne/yönetmelik değişikliğine göre ayarlanabilir
# olsun diye sabit değil ayar: program yönetmelik yorumu yapmaz.
AYAR_DEVAMSIZLIK_SINIRI = "devamsizlik_gun_siniri"

VARSAYILAN_AYARLAR = {
    AYAR_OKUL: "",
    AYAR_OGRETMEN: "",
    AYAR_DERS_DAKIKASI: "40",
    AYAR_YAZILI_SAYISI: "2",
    AYAR_PERFORMANS_SAYISI: "1",
    AYAR_GECME_PUANI: "50",
    AYAR_DEVAMSIZLIK_SINIRI: "10",
}


class Bulunamadi(LookupError):
    """İstenen kayıt yok."""


@dataclass(frozen=True)
class Sube:
    id: int
    ad: str
    sinif: int
    mufredat_surumu: str
    haftalik_ders_saati: int


@dataclass(frozen=True)
class OgretimYili:
    id: int
    ad: str
    donem1: tk.Donem
    donem2: tk.Donem

    @property
    def donemler(self) -> tuple[tk.Donem, tk.Donem]:
        return (self.donem1, self.donem2)

    def donem_no(self, gun: date) -> int:
        return 1 if self.donem1.icinde(gun) else 2


# --- ayarlar -------------------------------------------------------------


def ayarlari_oku(baglanti: sqlite3.Connection) -> dict[str, str]:
    # Anahtar başına ayrı SELECT yerine tek okuma: bu fonksiyon her sayfa
    # isteğinde (bazen şube başına) çağrılıyor.
    kayitli = {
        s["anahtar"]: s["deger"]
        for s in baglanti.execute("SELECT anahtar, deger FROM ayar")
    }
    return {a: kayitli.get(a, v) for a, v in VARSAYILAN_AYARLAR.items()}


SAYISAL_AYARLAR = {
    AYAR_DERS_DAKIKASI: (20, 60),
    AYAR_YAZILI_SAYISI: (1, 5),
    AYAR_PERFORMANS_SAYISI: (0, 5),
    AYAR_GECME_PUANI: (0, 100),
    AYAR_DEVAMSIZLIK_SINIRI: (1, 60),
}


def ayarlari_yaz(baglanti: sqlite3.Connection, degerler: dict[str, str]) -> list[str]:
    """Ayarları yazar; kabul edilmeyen değerleri uyarı olarak döndürür.

    Sayısal alanlar doğrulanmadan yazıldığında ("iki" gibi bir değer) not
    defteri sayfası açılmaz hâle geliyordu; kullanıcı da nedenini göremiyordu.
    """
    from .depo import ayar_yaz

    uyarilar: list[str] = []
    for anahtar, deger in degerler.items():
        if anahtar not in VARSAYILAN_AYARLAR:
            continue
        sinirlar = SAYISAL_AYARLAR.get(anahtar)
        if sinirlar is not None:
            try:
                sayi = float(str(deger).replace(",", "."))
            except ValueError:
                uyarilar.append(f"{anahtar}: '{deger}' sayı değil, değiştirilmedi")
                continue
            en_az, en_cok = sinirlar
            if not (en_az <= sayi <= en_cok):
                uyarilar.append(f"{anahtar}: {sayi:g} aralık dışı ({en_az}-{en_cok})")
                continue
            deger = f"{sayi:g}"
        ayar_yaz(baglanti, anahtar, str(deger))
    return uyarilar


def _sayi_ayari(degerler: dict[str, str], anahtar: str, varsayilan: float) -> float:
    """Ayar bozuksa varsayılana düşer — sayfa açılmaz hâle gelmesin."""
    try:
        return float(str(degerler.get(anahtar, "")).replace(",", "."))
    except ValueError:
        return varsayilan


def belge_kunyesi(baglanti: sqlite3.Connection) -> tuple[str, str]:
    """Belgelerin başlık/imza künyesi: (okul, öğretmen); boşsa yer tutucu."""
    ayarlar = ayarlari_oku(baglanti)
    return ayarlar[AYAR_OKUL] or "…", ayarlar[AYAR_OGRETMEN] or "…"


def mufredat_surumu_sec(baglanti: sqlite3.Connection, sinif: int) -> str:
    """Aktif öğretim yılına göre sınıfın tabi olduğu müfredat sürümü.

    Soru havuzu gibi şubeden bağımsız ekranlar da sınav ekranıyla aynı sürümü
    seçmek zorunda; kural tek yerde durur.
    """
    yil = aktif_yil(baglanti)
    return mf.surum_sec(yil.ad, sinif) if yil else mf.VARSAYILAN_SURUM


def not_kurallari(baglanti: sqlite3.Connection) -> nt.Kurallar:
    ayarlar = ayarlari_oku(baglanti)
    return nt.Kurallar(
        donem_basina_yazili=int(_sayi_ayari(ayarlar, AYAR_YAZILI_SAYISI, 2)),
        donem_basina_performans=int(_sayi_ayari(ayarlar, AYAR_PERFORMANS_SAYISI, 1)),
        gecme_puani=_sayi_ayari(ayarlar, AYAR_GECME_PUANI, 50.0),
    )


# --- öğretim yılı ve takvim ---------------------------------------------


def ogretim_yili_kur(
    baglanti: sqlite3.Connection,
    ad: str,
    donem1: tk.Donem,
    donem2: tk.Donem,
    *,
    resmi_tatilleri_ekle: bool = True,
) -> OgretimYili:
    baglanti.execute("UPDATE ogretim_yili SET aktif = 0")
    imlec = baglanti.execute(
        "INSERT INTO ogretim_yili (ad, donem1_baslangic, donem1_bitis, donem2_baslangic, "
        "donem2_bitis, aktif) VALUES (?, ?, ?, ?, ?, 1) "
        "ON CONFLICT (ad) DO UPDATE SET donem1_baslangic = excluded.donem1_baslangic, "
        "donem1_bitis = excluded.donem1_bitis, donem2_baslangic = excluded.donem2_baslangic, "
        "donem2_bitis = excluded.donem2_bitis, aktif = 1",
        (
            ad,
            donem1.baslangic.isoformat(),
            donem1.bitis.isoformat(),
            donem2.baslangic.isoformat(),
            donem2.bitis.isoformat(),
        ),
    )
    # lastrowid KULLANILMAZ: ON CONFLICT DO UPDATE ile giden bir upsert'te
    # sqlite3 bu değeri güncellenmiş satıra göre ayarlamıyor, bağlantıdaki son
    # gerçek eklemeden kalanı döndürüyor. Kimlik her zaman sorgulanarak alınır.
    del imlec
    yil_id = baglanti.execute("SELECT id FROM ogretim_yili WHERE ad = ?", (ad,)).fetchone()["id"]

    if resmi_tatilleri_ekle:
        tatil_ekle(baglanti, yil_id, tk.sabit_tatiller((donem1, donem2)))
        # Belirli gün ve haftalar da takvime girer ama ders saatini düşürmez;
        # yıllık planın kendi sütununda anılırlar.
        tatil_ekle(baglanti, yil_id, tk.belirli_gunler((donem1, donem2)))
    return OgretimYili(id=yil_id, ad=ad, donem1=donem1, donem2=donem2)


def _yil_satirindan(satir: sqlite3.Row | None) -> OgretimYili | None:
    if not satir:
        return None
    return OgretimYili(
        id=satir["id"],
        ad=satir["ad"],
        donem1=tk.Donem(1, date.fromisoformat(satir["donem1_baslangic"]), date.fromisoformat(satir["donem1_bitis"])),
        donem2=tk.Donem(2, date.fromisoformat(satir["donem2_baslangic"]), date.fromisoformat(satir["donem2_bitis"])),
    )


def aktif_yil(baglanti: sqlite3.Connection) -> OgretimYili | None:
    return _yil_satirindan(
        baglanti.execute(
            "SELECT * FROM ogretim_yili WHERE aktif = 1 ORDER BY id DESC LIMIT 1"
        ).fetchone()
    )


def ogretim_yillari_oku(baglanti: sqlite3.Connection) -> list[OgretimYili]:
    return [
        yil
        for satir in baglanti.execute("SELECT * FROM ogretim_yili ORDER BY ad DESC")
        if (yil := _yil_satirindan(satir)) is not None
    ]


def ogretim_yili_al(baglanti: sqlite3.Connection, yil_id: int) -> OgretimYili:
    yil = _yil_satirindan(
        baglanti.execute("SELECT * FROM ogretim_yili WHERE id = ?", (yil_id,)).fetchone()
    )
    if yil is None:
        raise Bulunamadi(f"Öğretim yılı bulunamadı: {yil_id}")
    return yil


def ogretim_yili_aktiflestir(baglanti: sqlite3.Connection, yil_id: int) -> None:
    with depo.islem(baglanti, immediate=True):
        if not baglanti.execute(
            "SELECT 1 FROM ogretim_yili WHERE id = ?", (yil_id,)
        ).fetchone():
            raise Bulunamadi(f"Öğretim yılı bulunamadı: {yil_id}")
        baglanti.execute("UPDATE ogretim_yili SET aktif = (id = ?)", (yil_id,))


def subenin_yili(baglanti: sqlite3.Connection, sube_id: int) -> OgretimYili:
    satir = baglanti.execute(
        "SELECT y.* FROM ogretim_yili y JOIN sube s ON s.ogretim_yili_id = y.id "
        "WHERE s.id = ?",
        (sube_id,),
    ).fetchone()
    yil = _yil_satirindan(satir)
    if yil is None:
        raise Bulunamadi(f"Şubenin öğretim yılı bulunamadı: {sube_id}")
    return yil


def yili_zorunlu_al(baglanti: sqlite3.Connection) -> OgretimYili:
    yil = aktif_yil(baglanti)
    if yil is None:
        raise Bulunamadi("Önce kurulum ekranından öğretim yılını tanımlayın.")
    return yil


def tatil_ekle(baglanti: sqlite3.Connection, yil_id: int, gunler: list[tk.TatilGunu]) -> int:
    eklenen = 0
    for gun in gunler:
        imlec = baglanti.execute(
            "INSERT OR IGNORE INTO takvim_gunu (ogretim_yili_id, tarih, tur, aciklama) "
            "VALUES (?, ?, ?, ?)",
            (yil_id, gun.tarih.isoformat(), gun.tur, gun.aciklama),
        )
        eklenen += imlec.rowcount or 0
    return eklenen


def tatil_sil(baglanti: sqlite3.Connection, tatil_id: int) -> None:
    baglanti.execute("DELETE FROM takvim_gunu WHERE id = ?", (tatil_id,))


def tatilleri_oku(baglanti: sqlite3.Connection, yil_id: int) -> list[tuple[int, tk.TatilGunu]]:
    satirlar = baglanti.execute(
        "SELECT * FROM takvim_gunu WHERE ogretim_yili_id = ? ORDER BY tarih", (yil_id,)
    ).fetchall()
    return [
        (s["id"], tk.TatilGunu(date.fromisoformat(s["tarih"]), s["tur"], s["aciklama"]))
        for s in satirlar
    ]


# --- şubeler ve öğrenciler ----------------------------------------------


def sube_ekle(
    baglanti: sqlite3.Connection,
    yil_id: int,
    ad: str,
    sinif: int,
    *,
    haftalik_ders_saati: int | None = None,
    ogretim_yili_adi: str = "",
) -> int:
    surum = mf.surum_sec(ogretim_yili_adi, sinif) if ogretim_yili_adi else mf.VARSAYILAN_SURUM
    if haftalik_ders_saati is None:
        try:
            haftalik_ders_saati = mf.yukle(surum).duzey(sinif).haftalik_ders_saati
        except mf.MufredatYok:
            haftalik_ders_saati = 4 if sinif >= 11 else 2
    baglanti.execute(
        "INSERT INTO sube (ogretim_yili_id, ad, sinif, mufredat_surumu, haftalik_ders_saati) "
        "VALUES (?, ?, ?, ?, ?) ON CONFLICT (ogretim_yili_id, ad) DO UPDATE SET "
        # mufredat_surumu de güncellenir: 9. sınıf olarak açılan bir şube 12'ye
        # çevrildiğinde sürüm eski kalıyor ve öğretmene sessizce YANLIŞ programın
        # planı üretiliyordu.
        "sinif = excluded.sinif, haftalik_ders_saati = excluded.haftalik_ders_saati, "
        "mufredat_surumu = excluded.mufredat_surumu",
        (yil_id, ad, sinif, surum, haftalik_ders_saati),
    )
    # lastrowid'e GÜVENİLMEZ: var olan bir şube güncellendiğinde sqlite3 bu
    # değeri o satıra göre ayarlamıyor, bağlantıdaki son gerçek eklemeden
    # kalanı döndürüyor. Ders programı yüklenirken bu, bir şubenin saatlerinin
    # BAŞKA bir şubeye yazılmasına yol açıyordu.
    return baglanti.execute(
        "SELECT id FROM sube WHERE ogretim_yili_id = ? AND ad = ?", (yil_id, ad)
    ).fetchone()["id"]


def subeleri_oku(baglanti: sqlite3.Connection, yil_id: int) -> list[Sube]:
    satirlar = baglanti.execute(
        "SELECT * FROM sube WHERE ogretim_yili_id = ? ORDER BY sinif, ad", (yil_id,)
    ).fetchall()
    return [
        Sube(s["id"], s["ad"], s["sinif"], s["mufredat_surumu"], s["haftalik_ders_saati"])
        for s in satirlar
    ]


def sube_al(baglanti: sqlite3.Connection, sube_id: int) -> Sube:
    satir = baglanti.execute("SELECT * FROM sube WHERE id = ?", (sube_id,)).fetchone()
    if not satir:
        raise Bulunamadi(f"Şube bulunamadı: {sube_id}")
    return Sube(
        satir["id"], satir["ad"], satir["sinif"], satir["mufredat_surumu"], satir["haftalik_ders_saati"]
    )


def sube_sil(baglanti: sqlite3.Connection, sube_id: int) -> None:
    baglanti.execute("DELETE FROM sube WHERE id = ?", (sube_id,))


def ogrenci_ekle(
    baglanti: sqlite3.Connection, sube_id: int, kayitlar: list[tuple[str, str]]
) -> int:
    """Öğrenciyi önce okul numarası, numara yoksa benzersiz adla eşleştirir.

    Aynı numarayla gelen ad düzeltmesi mevcut kimliği günceller; not ve yoklama
    geçmişi bölünmez. Belirsiz eski çakışmalar otomatik birleştirilmez.
    """
    # Dosyanın KENDİ içindeki tekrar: "101 Ayşe" + "101 Ali" iki öğrenci
    # sanılıp tek kayda çöküyordu (ikinci satır ilkinin adını eziyor, sayaç
    # yine 2 diyordu). Böyle dosya reddedilir — hangi satırın doğru olduğuna
    # program karar veremez.
    gorulen_numara: set[str] = set()
    for ham_numara, _ in kayitlar:
        numara = ham_numara.strip()
        if not numara:
            continue
        if numara in gorulen_numara:
            raise ValueError(
                f"Dosyada {numara} numarası birden çok satırda; listeyi düzeltip "
                "yeniden yükleyin."
            )
        gorulen_numara.add(numara)
    with depo.islem(baglanti, immediate=True):
        satirlar = baglanti.execute(
            "SELECT id, numara, ad_soyad, aktif FROM ogrenci WHERE sube_id = ?", (sube_id,)
        ).fetchall()
        indeks = yk.eslesme_indeksi((s["numara"], s["ad_soyad"], s) for s in satirlar)
        numaraya, ada = indeks

        degisen = 0
        for ham_numara, ham_ad in kayitlar:
            numara = ham_numara.strip()
            ad = " ".join(ham_ad.split())
            adaylar = yk.aday_bul(indeks, numara, ad)
            if len(adaylar) > 1:
                raise ValueError(
                    f"{numara or ad} için birden çok mevcut öğrenci var; önce çakışmayı düzeltin."
                )
            if adaylar:
                kayit = adaylar[0]
                if not kayit["aktif"] or kayit["ad_soyad"] != ad:
                    baglanti.execute(
                        "UPDATE ogrenci SET ad_soyad = ?, aktif = 1 WHERE id = ?",
                        (ad, kayit["id"]),
                    )
                    degisen += 1
                continue
            imlec = baglanti.execute(
                "INSERT INTO ogrenci (sube_id, numara, ad_soyad) VALUES (?, ?, ?)",
                (sube_id, numara, ad),
            )
            yeni = {
                "id": imlec.lastrowid,
                "numara": numara,
                "ad_soyad": ad,
                "aktif": 1,
            }
            if numara:
                numaraya.setdefault(numara, []).append(yeni)  # type: ignore[arg-type]
            ada.setdefault(yk.sadelestir(ad), []).append(yeni)  # type: ignore[arg-type]
            degisen += 1
        return degisen


def ogrenci_al(baglanti: sqlite3.Connection, ogrenci_id: int) -> sqlite3.Row:
    satir = baglanti.execute(
        "SELECT o.*, s.ad AS sube_adi, s.sinif, s.ogretim_yili_id, "
        "s.mufredat_surumu FROM ogrenci o "
        "JOIN sube s ON s.id = o.sube_id WHERE o.id = ?",
        (ogrenci_id,),
    ).fetchone()
    if satir is None:
        raise Bulunamadi("Öğrenci bulunamadı")
    return satir


def ogrencileri_oku(
    baglanti: sqlite3.Connection, sube_id: int, *, hepsi: bool = False
) -> list[sqlite3.Row]:
    """Şubenin öğrencilerini okur; `hepsi=True` pasifleri de içerir.

    `hepsi`, içe aktarma önizlemesi içindir: `ogrenci_ekle` pasif kayıtla da
    eşleştirdiği için önizleme yalnız aktiflere bakarsa "Yeni öğrenci" deyip
    aslında eski kaydı geçmişiyle geri getirir — kullanıcı bunu görmeli.
    """
    kosul = "" if hepsi else "AND aktif = 1 "
    return baglanti.execute(
        f"SELECT * FROM ogrenci WHERE sube_id = ? {kosul}"
        "ORDER BY CAST(NULLIF(numara,'') AS INTEGER), ad_soyad",
        (sube_id,),
    ).fetchall()


def ogrenci_sil(
    baglanti: sqlite3.Connection, ogrenci_id: int, *, sube_id: int | None = None
) -> None:
    sorgu = "UPDATE ogrenci SET aktif = 0 WHERE id = ?"
    parametreler: tuple[int, ...] = (ogrenci_id,)
    if sube_id is not None:
        sorgu += " AND sube_id = ?"
        parametreler += (sube_id,)
    imlec = baglanti.execute(sorgu, parametreler)
    if imlec.rowcount != 1:
        raise Bulunamadi("Öğrenci bu şubede bulunamadı.")


# --- ders programı -------------------------------------------------------


AZAMI_DERS_SAATI = 12


def izgara_saat_sayisi(baglanti: sqlite3.Connection, yil_id: int, en_az: int = 8) -> int:
    """Izgaranın kaç ders saati göstermesi gerektiği.

    Kayıtlı programda 9. ya da 10. ders saati varsa (ikili öğretim yapan
    okullar) ızgara onları da göstermeli; göstermezse öğretmen sayfayı açıp
    hiçbir şeyi değiştirmeden kaydettiğinde o saatler siliniyordu.
    """
    satir = baglanti.execute(
        "SELECT MAX(d.ders_saati) AS enb FROM ders_programi d "
        "JOIN sube s ON s.id = d.sube_id WHERE s.ogretim_yili_id = ?",
        (yil_id,),
    ).fetchone()
    return min(AZAMI_DERS_SAATI, max(en_az, satir["enb"] or 0))


def ders_programi_yaz(
    baglanti: sqlite3.Connection,
    hucreler: list[tuple[int, int, int]],
    *,
    temizlenecek_subeler: list[int] | None = None,
    saat_araligi: tuple[int, int] | None = None,
) -> None:
    """(sube_id, gün, ders_saati) üçlülerini yazar; önce ilgili kayıtlar silinir.

    `temizlenecek_subeler`, ızgara kaydedilirken verilir: ızgarada hiç hücresi
    kalmayan bir şubenin programı da temizlenmeli. Silme ve yazma AYNI işlemde
    yapılır — eskiden silme dışarıda kaldığı için, yazılacak hücre üretilmeyen
    bir kaydetmede (ör. tanınmayan bir şube adı yüzünden) bütün ders programı
    siliniyor, kullanıcıya ise "kaydedildi" yazıyordu.

    `saat_araligi` verilirse silme YALNIZ o aralıkta yapılır. Izgara ekranı
    sınırlı sayıda ders saati gösteriyor; göstermediği saatleri silmemeli,
    yoksa ikili öğretimin 9-10. saatleri ızgara kaydedilir kaydedilmez
    kayboluyordu.
    """
    hedefler = set(temizlenecek_subeler) if temizlenecek_subeler is not None else set()
    hedefler |= {s for s, _, _ in hucreler}
    en_az, en_cok = saat_araligi or (1, AZAMI_DERS_SAATI)
    with depo.islem(baglanti):
        for sube_id in hedefler:
            baglanti.execute(
                "DELETE FROM ders_programi WHERE sube_id = ? AND ders_saati BETWEEN ? AND ?",
                (sube_id, en_az, en_cok),
            )
        for sube_id, gun, saat in hucreler:
            baglanti.execute(
                "INSERT OR IGNORE INTO ders_programi (sube_id, gun, ders_saati) VALUES (?, ?, ?)",
                (sube_id, gun, saat),
            )


def ders_programini_oku(baglanti: sqlite3.Connection, yil_id: int) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT d.*, s.ad AS sube_adi, s.sinif FROM ders_programi d "
        "JOIN sube s ON s.id = d.sube_id WHERE s.ogretim_yili_id = ? "
        "ORDER BY d.gun, d.ders_saati",
        (yil_id,),
    ).fetchall()


def sube_ders_gunleri(baglanti: sqlite3.Connection, sube_id: int) -> dict[int, int]:
    satirlar = baglanti.execute(
        "SELECT gun, COUNT(*) AS adet FROM ders_programi WHERE sube_id = ? GROUP BY gun",
        (sube_id,),
    ).fetchall()
    return {s["gun"]: s["adet"] for s in satirlar}


def gunun_dersleri(baglanti: sqlite3.Connection, yil_id: int, gun: date) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT d.*, s.ad AS sube_adi, s.sinif, s.id AS sube_id FROM ders_programi d "
        "JOIN sube s ON s.id = d.sube_id WHERE s.ogretim_yili_id = ? AND d.gun = ? "
        "ORDER BY d.ders_saati",
        (yil_id, gun.isoweekday()),
    ).fetchall()


def gunun_bloklari(baglanti: sqlite3.Connection, yil_id: int, gun: date) -> list[dict]:
    """Günün derslerini ardışık saatleri birleştirerek bloklara toplar.

    "Blok" yoklamanın, ders defterinin ve günlük planın paylaştığı kavramdır;
    aynı şubenin peş peşe saatleri tek ders sayılır.
    """
    bloklar: list[dict] = []
    for ders in gunun_dersleri(baglanti, yil_id, gun):
        if bloklar and bloklar[-1]["sube_id"] == ders["sube_id"] and (
            ders["ders_saati"] - bloklar[-1]["saatler"][-1] == 1
        ):
            bloklar[-1]["saatler"].append(ders["ders_saati"])
            continue
        bloklar.append(
            {
                "sube_id": ders["sube_id"],
                "sube_adi": ders["sube_adi"],
                "sinif": ders["sinif"],
                "saatler": [ders["ders_saati"]],
            }
        )
    return bloklar


# --- yıllık plan ---------------------------------------------------------


def sube_haftalari(
    baglanti: sqlite3.Connection, yil: OgretimYili, sube: Sube
) -> list[tk.Hafta]:
    tatiller = [t for _, t in tatilleri_oku(baglanti, yil.id)]
    ders_gunleri = sube_ders_gunleri(baglanti, sube.id)
    if not ders_gunleri:
        # Ders programı girilmemişse haftalık saati tek güne toplayıp yine de
        # plan üretilir; yoksa öğretmen programı girmeden plan alamazdı.
        ders_gunleri = {2: sube.haftalik_ders_saati}
    return tk.haftalari_uret(yil.donemler, tatiller, ders_gunleri)


def yillik_plan_uret_ve_kaydet(
    baglanti: sqlite3.Connection, yil: OgretimYili, sube: Sube
) -> list[yp.PlanSatiri]:
    if sube.mufredat_surumu not in mf.mevcut_surumler():
        raise Bulunamadi(
            f"{sube.sinif}. sınıfın müfredat dosyası ({sube.mufredat_surumu}) yüklü değil; "
            "plan üretilemiyor."
        )
    program = mf.yukle(sube.mufredat_surumu)
    duzey = program.duzey(sube.sinif)
    satirlar = yp.yillik_plan_uret(duzey, sube_haftalari(baglanti, yil, sube))

    # Tek işlem: eski plan silinip yenisi satır satır yazılıyor; ortada bir
    # hata olursa öğretmen ne eski ne yeni plana sahip oluyordu.
    with depo.islem(baglanti):
        _plani_yaz(baglanti, yil, sube, satirlar)
    return satirlar


def _plani_yaz(
    baglanti: sqlite3.Connection, yil: OgretimYili, sube: Sube, satirlar: list[yp.PlanSatiri]
) -> None:
    onceki = baglanti.execute(
        "SELECT id, revizyon FROM yillik_plan WHERE sube_id = ? "
        "ORDER BY revizyon DESC, id DESC LIMIT 1",
        (sube.id,),
    ).fetchone()
    revizyon = int(onceki["revizyon"]) + 1 if onceki else 1
    imlec = baglanti.execute(
        "INSERT INTO yillik_plan "
        "(sube_id, baslik, olusturma, revizyon, durum, kaynak_plan_id) "
        "VALUES (?, ?, ?, ?, 'taslak', ?)",
        (
            sube.id,
            f"{yil.ad} {sube.ad} yıllık planı",
            datetime.now().isoformat(timespec="seconds"),
            revizyon,
            onceki["id"] if onceki else None,
        ),
    )
    plan_id = imlec.lastrowid
    for satir in satirlar:
        baglanti.execute(
            "INSERT INTO yillik_plan_satiri (plan_id, sira, hafta_no, ay, baslangic, bitis, "
            "ders_saati, tur, tema_no, tema_adi, kazanim_kodlari, surec_bilesenleri, icerik, "
            "yontem_teknik, arac_gerec, olcme_degerlendirme, aciklama, disiplinler_arasi, "
            "belirli_gunler, donem) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                plan_id,
                satir.sira,
                satir.hafta_no,
                satir.ay,
                satir.baslangic,
                satir.bitis,
                satir.ders_saati,
                satir.tur,
                satir.tema_no,
                satir.tema_adi,
                ", ".join(satir.kazanim_kodlari),
                "\n".join(satir.surec_bilesenleri),
                satir.icerik,
                ", ".join(satir.yontem_teknik),
                ", ".join(satir.arac_gerec),
                ", ".join(satir.olcme_degerlendirme),
                satir.aciklama,
                ", ".join(satir.disiplinler_arasi),
                ", ".join(satir.belirli_gunler),
                satir.donem,
            ),
        )


def yillik_plan_oku(baglanti: sqlite3.Connection, sube: Sube) -> list[yp.PlanSatiri]:
    plan = baglanti.execute(
        "SELECT id FROM yillik_plan WHERE sube_id = ? "
        "ORDER BY revizyon DESC, id DESC LIMIT 1",
        (sube.id,),
    ).fetchone()
    if not plan:
        return []
    if sube.mufredat_surumu not in mf.mevcut_surumler():
        # 12. sınıf 2026-2027'de 2018 programına tabi ve o dosya henüz yok.
        # Plan sayfası bunu uyarıyla karşılıyor; indirme ve günlük plan
        # uçlarının 500 vermemesi için burada da sessizce boş dönülür.
        return []
    satirlar = baglanti.execute(
        "SELECT * FROM yillik_plan_satiri WHERE plan_id = ? ORDER BY sira", (plan["id"],)
    ).fetchall()

    program = mf.yukle(sube.mufredat_surumu)
    sonuc: list[yp.PlanSatiri] = []
    for s in satirlar:
        kodlar = [k.strip() for k in s["kazanim_kodlari"].split(",") if k.strip()]
        ifadeler = []
        haritada: dict[str, list[str]] = {}
        for kod in kodlar:
            try:
                cikti = program.cikti(kod)
            except mf.MufredatYok:
                ifadeler.append("")
                continue
            ifadeler.append(cikti.ifade)
            haritada[kod] = [f"{b.harf}) {b.ifade}" for b in cikti.surec_bilesenleri]
        sonuc.append(
            yp.PlanSatiri(
                sira=s["sira"],
                hafta_no=s["hafta_no"],
                donem=s["donem"],
                ay=s["ay"],
                baslangic=s["baslangic"],
                bitis=s["bitis"],
                ders_saati=s["ders_saati"],
                tur=s["tur"],
                tema_no=s["tema_no"],
                tema_adi=s["tema_adi"],
                kazanim_kodlari=kodlar,
                kazanim_ifadeleri=ifadeler,
                surec_bilesenleri=[b for b in s["surec_bilesenleri"].split("\n") if b],
                icerik=s["icerik"],
                yontem_teknik=[y.strip() for y in s["yontem_teknik"].split(",") if y.strip()],
                arac_gerec=[a.strip() for a in s["arac_gerec"].split(",") if a.strip()],
                olcme_degerlendirme=[
                    o.strip() for o in s["olcme_degerlendirme"].split(",") if o.strip()
                ],
                aciklama=s["aciklama"],
                bilesen_haritasi=haritada,
                disiplinler_arasi=[d.strip() for d in s["disiplinler_arasi"].split(",") if d.strip()],
                belirli_gunler=[g.strip() for g in s["belirli_gunler"].split(",") if g.strip()],
            )
        )
    yp._devamlari_isaretle(sonuc)  # noqa: SLF001 - aynı paketin iç yardımcısı
    return sonuc


PLAN_DURUMLARI = ("taslak", "onaylandi", "teslim_edildi", "revize_edildi")


def plan_gecmisi(baglanti: sqlite3.Connection, sube_id: int) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT p.*, COUNT(s.id) AS satir_sayisi FROM yillik_plan p "
        "LEFT JOIN yillik_plan_satiri s ON s.plan_id = p.id "
        "WHERE p.sube_id = ? GROUP BY p.id ORDER BY p.revizyon DESC, p.id DESC",
        (sube_id,),
    ).fetchall()


def plan_durum_guncelle(
    baglanti: sqlite3.Connection, sube_id: int, plan_id: int, durum: str
) -> None:
    if durum not in PLAN_DURUMLARI:
        raise ValueError("Bilinmeyen plan durumu.")
    with depo.islem(baglanti, immediate=True):
        hedef = baglanti.execute(
            "SELECT id FROM yillik_plan WHERE id = ? AND sube_id = ?",
            (plan_id, sube_id),
        ).fetchone()
        if not hedef:
            raise Bulunamadi("Plan bu şubede bulunamadı.")
        if durum in {"onaylandi", "teslim_edildi"}:
            baglanti.execute(
                "UPDATE yillik_plan SET durum = 'revize_edildi' "
                "WHERE sube_id = ? AND id <> ? AND durum IN ('onaylandi', 'teslim_edildi')",
                (sube_id, plan_id),
            )
        baglanti.execute(
            "UPDATE yillik_plan SET durum = ?, karar_tarihi = ? WHERE id = ?",
            (durum, datetime.now().isoformat(timespec="seconds"), plan_id),
        )


def haftanin_kazanimlari(
    satirlar: list[yp.PlanSatiri], gun: date
) -> yp.PlanSatiri | None:
    for satir in satirlar:
        if satir.baslangic <= gun.isoformat() <= satir.bitis:
            return satir
    return None


# --- ders defteri --------------------------------------------------------

DERS_DURUMLARI = ("islendi", "ertelendi")


def kod_listesi(metin: str) -> list[str]:
    return [k.strip() for k in metin.split(",") if k.strip()]


def ders_kaydi_yaz(
    baglanti: sqlite3.Connection,
    sube_id: int,
    tarih: date,
    *,
    ders_saatleri: list[int],
    kazanim_kodlari: list[str],
    durum: str = "islendi",
    aciklama: str = "",
) -> None:
    if durum not in DERS_DURUMLARI:
        raise ValueError(f"Bilinmeyen ders kaydı durumu: {durum}")
    saat_metni = ",".join(str(s) for s in ders_saatleri)
    with depo.islem(baglanti, immediate=True):
        mevcut = baglanti.execute(
            "SELECT kazanim_kodlari FROM ders_kaydi "
            "WHERE sube_id = ? AND tarih = ? AND ders_saatleri = ?",
            (sube_id, tarih.isoformat(), saat_metni),
        ).fetchone()
        kodlar = ", ".join(kazanim_kodlari)
        if not kodlar and mevcut:
            # Boş kod listesi büyük olasılıkla yarım form gönderimi; var olan
            # kayıttaki kodları sessizce silmek yerine koru.
            kodlar = mevcut["kazanim_kodlari"]
        baglanti.execute(
            "INSERT INTO ders_kaydi "
            "(sube_id, tarih, ders_saatleri, kazanim_kodlari, durum, aciklama, olusturma) "
            "VALUES (?,?,?,?,?,?,?) "
            "ON CONFLICT (sube_id, tarih, ders_saatleri) DO UPDATE SET "
            "kazanim_kodlari = excluded.kazanim_kodlari, "
            "durum = excluded.durum, aciklama = excluded.aciklama",
            (
                sube_id,
                tarih.isoformat(),
                saat_metni,
                kodlar,
                durum,
                aciklama,
                datetime.now().isoformat(timespec="seconds"),
            ),
        )


def ders_kaydi_sil(baglanti: sqlite3.Connection, sube_id: int, tarih: date) -> None:
    with depo.islem(baglanti):
        baglanti.execute(
            "DELETE FROM ders_kaydi WHERE sube_id = ? AND tarih = ?",
            (sube_id, tarih.isoformat()),
        )


def gunun_ders_kayitlari(
    baglanti: sqlite3.Connection, sube_id: int, gun: date
) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT * FROM ders_kaydi WHERE sube_id = ? AND tarih = ? ORDER BY ders_saatleri",
        (sube_id, gun.isoformat()),
    ).fetchall()


def gunun_ders_kaydi(
    baglanti: sqlite3.Connection,
    sube_id: int,
    gun: date,
    ders_saatleri: list[int] | None = None,
) -> sqlite3.Row | None:
    """Blok belirtilirse o bloğun, belirtilmezse günün ilk kaydını verir."""
    if ders_saatleri is None:
        kayitlar = gunun_ders_kayitlari(baglanti, sube_id, gun)
        return kayitlar[0] if kayitlar else None
    return baglanti.execute(
        "SELECT * FROM ders_kaydi WHERE sube_id = ? AND tarih = ? AND ders_saatleri = ?",
        (sube_id, gun.isoformat(), ",".join(str(s) for s in ders_saatleri)),
    ).fetchone()


def ders_kayitlari(baglanti: sqlite3.Connection, sube_id: int) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT * FROM ders_kaydi WHERE sube_id = ? ORDER BY tarih", (sube_id,)
    ).fetchall()


def gerceklesme_raporu(
    satirlar: list[yp.PlanSatiri],
    kayitlar: list[sqlite3.Row],
    bugun: date,
) -> dict:
    """Yıllık plan (niyet) ile ders defterini (gerçekleşen) karşılaştırır.

    Kazanım eşleştirmesi tam kod eşitliğiyle yapılır: BİY.9.1.1 işlendi diye
    BİY.9.1.10 işlenmiş sayılmaz (startswith burada sessiz yanlış sayar).

    Sayım kazanım odaklıdır, hafta odaklı değil: iki haftaya yayılan kazanım
    bir kez işlendiğinde devam haftası da tamam sayılır — telafi başka haftada
    yapılabildiği için haftaya kilitlemek sahte "geride" üretir. Gelecek
    tarihli kayıtlar ise sayılmaz: 10 Ekim'e yazılmış kayıt 25 Eylül'de
    geçmiş haftayı tamamlanmış gösteremez.
    """
    islenen: set[str] = set()
    for kayit in kayitlar:
        if kayit["durum"] == "islendi" and kayit["tarih"] <= bugun.isoformat():
            islenen.update(kod_listesi(kayit["kazanim_kodlari"]))

    haftalar: list[dict] = []
    islenmemis: list[str] = []
    geride = 0
    bugun_iso = bugun.isoformat()
    for satir in satirlar:
        if satir.tur != yp.TUR_TEMA or not satir.kazanim_kodlari:
            continue
        planlanan = list(dict.fromkeys(satir.kazanim_kodlari))
        tamam = [k for k in planlanan if k in islenen]
        gecmis = satir.bitis < bugun_iso
        durum = "tam" if len(tamam) == len(planlanan) else ("kismi" if tamam else "yok")
        if gecmis and durum != "tam":
            geride += 1
            islenmemis.extend(k for k in planlanan if k not in islenen)
        haftalar.append(
            {
                "hafta_no": satir.hafta_no,
                "baslangic": satir.baslangic,
                "bitis": satir.bitis,
                "tema_adi": satir.tema_adi,
                "planlanan": planlanan,
                "islenen": tamam,
                "durum": durum,
                "gecmis": gecmis,
            }
        )

    gecmis_haftalar = [h for h in haftalar if h["gecmis"]]
    return {
        "haftalar": haftalar,
        # Aynı kazanım iki haftaya yayılmışsa listede bir kez görünsün.
        "islenmemis": list(dict.fromkeys(islenmemis)),
        "geride_hafta": geride,
        "gecmis_hafta": len(gecmis_haftalar),
        "islenen_sayisi": len(islenen),
    }


def sube_gerceklesmesi(baglanti: sqlite3.Connection, sube: Sube) -> dict | None:
    """Şubenin plan gerçekleşme raporu; plan yoksa None."""
    satirlar = yillik_plan_oku(baglanti, sube)
    if not satirlar:
        return None
    return gerceklesme_raporu(satirlar, ders_kayitlari(baglanti, sube.id), date.today())


# --- günlük plan ---------------------------------------------------------


def gunluk_plan_uret(
    baglanti: sqlite3.Connection,
    yil: OgretimYili,
    sube: Sube,
    gun: date,
    ders_saatleri: list[int],
) -> gp.GunlukPlan | None:
    satirlar = yillik_plan_oku(baglanti, sube)
    if not satirlar:
        satirlar = yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    hedef = haftanin_kazanimlari(satirlar, gun)
    if hedef is None or not hedef.kazanim_kodlari:
        return None
    if sube.mufredat_surumu not in mf.mevcut_surumler():
        return None

    program = mf.yukle(sube.mufredat_surumu)
    duzey = program.duzey(sube.sinif)
    tema = next((t for t in duzey.temalar if t.no == hedef.tema_no), duzey.temalar[0])
    kazanimlar = [program.cikti(k) for k in hedef.kazanim_kodlari]
    dakika = int(ayarlari_oku(baglanti).get(AYAR_DERS_DAKIKASI, "40") or 40)
    return gp.gunluk_plan_uret(
        tarih=gun,
        sube_adi=sube.ad,
        sinif=sube.sinif,
        tema=tema,
        kazanimlar=kazanimlar,
        ders_saatleri=ders_saatleri,
        ders_dakikasi=dakika,
    )


def gunluk_plan_kaydet(baglanti: sqlite3.Connection, sube_id: int, plan: gp.GunlukPlan) -> None:
    baglanti.execute(
        "INSERT INTO gunluk_plan (sube_id, tarih, ders_saatleri, kazanim_kodlari, bolumler, "
        "notlar, olusturma) VALUES (?,?,?,?,?,?,?) "
        "ON CONFLICT (sube_id, tarih) DO UPDATE SET ders_saatleri = excluded.ders_saatleri, "
        "kazanim_kodlari = excluded.kazanim_kodlari, bolumler = excluded.bolumler, "
        "notlar = excluded.notlar",
        (
            sube_id,
            plan.tarih.isoformat(),
            ",".join(str(s) for s in plan.ders_saatleri),
            ", ".join(plan.kazanim_kodlari),
            json.dumps(plan.sozluge(), ensure_ascii=False),
            plan.notlar,
            datetime.now().isoformat(timespec="seconds"),
        ),
    )


# --- yoklama -------------------------------------------------------------


def yoklama_kaydet(
    baglanti: sqlite3.Connection,
    sube_id: int,
    gun: date,
    ders_saati: int,
    durumlar: dict[int, str],
) -> None:
    with depo.islem(baglanti, immediate=True):
        for ogrenci_id, durum in durumlar.items():
            if durum not in yk.DURUM_ADLARI:
                raise ValueError(f"Geçersiz yoklama durumu: {durum}")
            ogrenci = baglanti.execute(
                "SELECT 1 FROM ogrenci WHERE id = ? AND sube_id = ? AND aktif = 1",
                (ogrenci_id, sube_id),
            ).fetchone()
            if not ogrenci:
                raise ValueError("Yoklama öğrencisi bu şubeye ait değil.")
            baglanti.execute(
                "INSERT INTO yoklama (sube_id, ogrenci_id, tarih, ders_saati, durum) "
                "VALUES (?,?,?,?,?) ON CONFLICT (ogrenci_id, tarih, ders_saati) "
                "DO UPDATE SET sube_id = excluded.sube_id, durum = excluded.durum",
                (sube_id, ogrenci_id, gun.isoformat(), ders_saati, durum),
            )


def gunun_yoklamasi(
    baglanti: sqlite3.Connection, sube_id: int, gun: date, ders_saati: int
) -> dict[int, str]:
    satirlar = baglanti.execute(
        "SELECT ogrenci_id, durum FROM yoklama WHERE sube_id = ? AND tarih = ? AND ders_saati = ?",
        (sube_id, gun.isoformat(), ders_saati),
    ).fetchall()
    return {s["ogrenci_id"]: s["durum"] for s in satirlar}


def devamsizlik_tablosu(baglanti: sqlite3.Connection, sube_id: int) -> list[dict]:
    ogrenciler = ogrencileri_oku(baglanti, sube_id)
    ayarlar = ayarlari_oku(baglanti)
    sinir = int(_sayi_ayari(ayarlar, AYAR_DEVAMSIZLIK_SINIRI, 10))
    gunler = sube_ders_gunleri(baglanti, sube_id)
    # Öğrenci başına ayrı SELECT (N+1) yerine şubenin tüm yoklaması tek
    # sorguda okunur (ix_yoklama_sube_tarih indeksini kullanır).
    ogrenci_kayitlari: dict[int, list[tuple[str, int, str]]] = {}
    for k in baglanti.execute(
        "SELECT ogrenci_id, tarih, ders_saati, durum FROM yoklama WHERE sube_id = ?",
        (sube_id,),
    ):
        ogrenci_kayitlari.setdefault(k["ogrenci_id"], []).append(
            (k["tarih"], k["ders_saati"], k["durum"])
        )
    sonuc: list[dict] = []
    for ogrenci in ogrenciler:
        ozet = yk.devamsizlik_ozeti(ogrenci_kayitlari.get(ogrenci["id"], []), gunler=gunler)
        sonuc.append(
            {
                "id": ogrenci["id"],
                "numara": ogrenci["numara"],
                "ad_soyad": ogrenci["ad_soyad"],
                **ozet,
                "uyari": nt.devamsizlik_uyarisi(ozet["yok_gun"], sinir=sinir),
                "sinir": sinir,
            }
        )
    return sonuc


# --- sınav takvimi -------------------------------------------------------


def sinav_takvimi(baglanti: sqlite3.Connection, yil: OgretimYili) -> dict:
    """Tarihi girilmiş resmî değerlendirmeleri ve sınavları tek takvimde toplar.

    Uyarılar yalnız takvim gerçeklerinden üretilir: tatil gününe denk gelme ve
    aynı şubeye aynı gün ikinci resmî değerlendirme. "Haftada şu kadar sınav
    olur" gibi yönetmelik yorumları burada üretilmez — o karar öğretmenindir.
    """
    # Belirli gün/haftalar (ör. Öğretmenler Günü) takvim_gunu'nda durur ama
    # ders yapılan günlerdir; sınav uyarısına dahil edilmezler.
    tatiller = {
        t.tarih: t
        for _, t in tatilleri_oku(baglanti, yil.id)
        if t.tur not in tk.DERS_YAPILAN_TURLER
    }
    girisler: list[dict] = []
    for satir in baglanti.execute(
        "SELECT d.id, d.ad, d.tarih, d.tur, s.ad AS sube_adi, s.id AS sube_id "
        "FROM degerlendirme d JOIN sube s ON s.id = d.sube_id "
        "WHERE s.ogretim_yili_id = ? AND d.resmi = 1 AND d.tarih <> '' "
        "ORDER BY d.tarih",
        (yil.id,),
    ):
        girisler.append(
            {
                "tarih": satir["tarih"],
                "sube_adi": satir["sube_adi"],
                "sube_id": satir["sube_id"],
                "ad": satir["ad"],
                "tur": satir["tur"],
                "kaynak": "degerlendirme",
            }
        )
    # Üretilmiş sınav kâğıtları: değerlendirmeye bağlı olmayanlar da görünsün.
    # Aynı şubede aynı gün aynı adla tanımlı bir değerlendirme varsa bu
    # büyük olasılıkla AYNI yazılıdır (sınav üretimi değerlendirmeye kendini
    # bağlamıyor); ikinci satır ve sahte çakışma uyarısı üretmemek için atlanır.
    gorunenler = {
        (g["tarih"], g["sube_id"], g["ad"].casefold().strip()) for g in girisler
    }
    for satir in baglanti.execute(
        "SELECT v.id, v.ad, v.tarih, s.ad AS sube_adi, s.id AS sube_id "
        "FROM sinav v JOIN sube s ON s.id = v.sube_id "
        "WHERE s.ogretim_yili_id = ? AND v.tarih <> '' AND v.degerlendirme_id IS NULL "
        "ORDER BY v.tarih",
        (yil.id,),
    ):
        if (satir["tarih"], satir["sube_id"], satir["ad"].casefold().strip()) in gorunenler:
            continue
        girisler.append(
            {
                "tarih": satir["tarih"],
                "sube_adi": satir["sube_adi"],
                "sube_id": satir["sube_id"],
                "ad": satir["ad"],
                "tur": "yazili",
                "kaynak": "sinav",
            }
        )
    girisler.sort(key=lambda g: (g["tarih"], g["sube_adi"]))

    uyarilar: list[str] = []
    gorulen: dict[tuple[str, int], list[str]] = {}
    for giris in girisler:
        # Tarih serbest metin olarak saklanıyor; bozuk tek bir kayıt takvim
        # sayfasını kalıcı 500'e düşürmemeli.
        try:
            tatil = tatiller.get(date.fromisoformat(giris["tarih"]))
        except ValueError:
            tatil = None
            uyarilar.append(
                f"{giris['sube_adi']} — {giris['ad']}: tarih biçimi tanınmadı "
                f"({giris['tarih']})"
            )
        giris["tatil"] = tatil.aciklama if tatil else ""
        if tatil:
            uyarilar.append(
                f"{giris['tarih']} {giris['sube_adi']} — {giris['ad']}: "
                f"takvimde tatil ({tatil.aciklama})"
            )
        anahtar = (giris["tarih"], giris["sube_id"])
        gorulen.setdefault(anahtar, []).append(giris["ad"])
    for (tarih, _), adlar in gorulen.items():
        if len(adlar) > 1:
            uyarilar.append(
                f"{tarih}: aynı şubeye aynı gün {len(adlar)} değerlendirme "
                f"({', '.join(adlar)})"
            )

    return {"girisler": girisler, "uyarilar": uyarilar}


# --- değerlendirme ve notlar --------------------------------------------


def degerlendirme_ekle(
    baglanti: sqlite3.Connection,
    sube_id: int,
    donem: int,
    tur: str,
    ad: str,
    *,
    tarih: str = "",
    tam_puan: float = 100.0,
) -> int:
    imlec = baglanti.execute(
        "INSERT INTO degerlendirme (sube_id, donem, tur, ad, tarih, resmi, tam_puan) "
        "VALUES (?,?,?,?,?,?,?)",
        (sube_id, donem, tur, ad, tarih, 0 if tur == nt.TUR_IC_TAKIP else 1, tam_puan),
    )
    return imlec.lastrowid or 0


def degerlendirmeleri_oku(baglanti: sqlite3.Connection, sube_id: int) -> list[sqlite3.Row]:
    return baglanti.execute(
        "SELECT * FROM degerlendirme WHERE sube_id = ? ORDER BY donem, id", (sube_id,)
    ).fetchall()


def degerlendirme_sil(
    baglanti: sqlite3.Connection,
    degerlendirme_id: int,
    *,
    sube_id: int | None = None,
) -> None:
    sorgu = "DELETE FROM degerlendirme WHERE id = ?"
    parametreler: tuple[int, ...] = (degerlendirme_id,)
    if sube_id is not None:
        sorgu += " AND sube_id = ?"
        parametreler += (sube_id,)
    imlec = baglanti.execute(sorgu, parametreler)
    if imlec.rowcount != 1:
        raise Bulunamadi("Değerlendirme bu şubede bulunamadı.")


def not_yaz(
    baglanti: sqlite3.Connection, degerlendirme_id: int, puanlar: dict[int, float | None]
) -> None:
    degerlendirme = baglanti.execute(
        "SELECT sube_id, tam_puan FROM degerlendirme WHERE id = ?", (degerlendirme_id,)
    ).fetchone()
    if not degerlendirme:
        raise Bulunamadi("Değerlendirme bulunamadı.")
    with depo.islem(baglanti, immediate=True):
        for ogrenci_id, puan in puanlar.items():
            ogrenci = baglanti.execute(
                "SELECT 1 FROM ogrenci WHERE id = ? AND sube_id = ? AND aktif = 1",
                (ogrenci_id, degerlendirme["sube_id"]),
            ).fetchone()
            if not ogrenci:
                raise ValueError("Not öğrencisi bu değerlendirme şubesine ait değil.")
            if puan is None:
                baglanti.execute(
                    "DELETE FROM not_kaydi WHERE degerlendirme_id = ? AND ogrenci_id = ?",
                    (degerlendirme_id, ogrenci_id),
                )
                continue
            if not 0 <= puan <= float(degerlendirme["tam_puan"]):
                raise ValueError("Not, değerlendirmenin puan aralığı dışında.")
            baglanti.execute(
                "INSERT INTO not_kaydi (degerlendirme_id, ogrenci_id, puan) VALUES (?,?,?) "
                "ON CONFLICT (degerlendirme_id, ogrenci_id) DO UPDATE SET puan = excluded.puan",
                (degerlendirme_id, ogrenci_id, puan),
            )


def karneler(baglanti: sqlite3.Connection, sube_id: int) -> list[nt.OgrenciKarnesi]:
    kurallar = not_kurallari(baglanti)
    degerlendirmeler = {d["id"]: d for d in degerlendirmeleri_oku(baglanti, sube_id)}
    # Öğrenci başına ayrı SELECT (N+1) yerine şubenin tüm notları tek sorguda
    # okunup bellekte gruplanır; öğrenci sayısıyla sorgu sayısı büyümez.
    ogrenci_notlari: dict[int, list[sqlite3.Row]] = {}
    for kayit in baglanti.execute(
        "SELECT n.ogrenci_id, n.degerlendirme_id, n.puan FROM not_kaydi n "
        "JOIN ogrenci o ON o.id = n.ogrenci_id WHERE o.sube_id = ?",
        (sube_id,),
    ):
        ogrenci_notlari.setdefault(kayit["ogrenci_id"], []).append(kayit)
    sonuc: list[nt.OgrenciKarnesi] = []
    for ogrenci in ogrencileri_oku(baglanti, sube_id):
        puanlar = [
            nt.Puan(
                tur=degerlendirmeler[k["degerlendirme_id"]]["tur"],
                ad=degerlendirmeler[k["degerlendirme_id"]]["ad"],
                deger=k["puan"],
                donem=degerlendirmeler[k["degerlendirme_id"]]["donem"],
                resmi=bool(degerlendirmeler[k["degerlendirme_id"]]["resmi"]),
            )
            for k in ogrenci_notlari.get(ogrenci["id"], [])
            if k["degerlendirme_id"] in degerlendirmeler
        ]
        sonuc.append(nt.karne_kur(ogrenci["id"], ogrenci["ad_soyad"], puanlar, kurallar))
    return sonuc


def not_tablosu(baglanti: sqlite3.Connection, sube_id: int) -> tuple[list[dict], list[dict]]:
    degerlendirmeler = [dict(d) for d in degerlendirmeleri_oku(baglanti, sube_id)]
    karne_haritasi = {k.ogrenci_id: k for k in karneler(baglanti, sube_id)}
    satirlar: list[dict] = []
    for ogrenci in ogrencileri_oku(baglanti, sube_id):
        puanlar = {
            k["degerlendirme_id"]: k["puan"]
            for k in baglanti.execute(
                "SELECT degerlendirme_id, puan FROM not_kaydi WHERE ogrenci_id = ?",
                (ogrenci["id"],),
            )
        }
        karne = karne_haritasi.get(ogrenci["id"])
        satirlar.append(
            {
                "id": ogrenci["id"],
                "numara": ogrenci["numara"],
                "ad_soyad": ogrenci["ad_soyad"],
                "puanlar": puanlar,
                "donem1": karne.donemler[1].ortalama if karne else None,
                "donem2": karne.donemler[2].ortalama if karne else None,
                "yil_sonu": karne.yil_sonu if karne else None,
                "durum": "" if not karne or karne.gecti is None else ("Geçti" if karne.gecti else "Kaldı"),
                "ic_takip": karne.ic_takip_ortalamasi if karne else None,
            }
        )
    return satirlar, degerlendirmeler
