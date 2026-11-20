"""YouTube alım ve onay kuyruğu rotaları.

İndirme + döküm + çıkarım 45 dakikalık bir video için dakikalar sürer; senkron
bir rotada bu bağlantı zaman aşımı demek ve sekme kapanınca döküm çöpe gider.
Bu yüzden iş, `kes_ve_coz.KesVeCozServisi`'nin kurduğu desenle arka planda
yürür: kalıcı SQLite iş kaydı, tek işçili yürütücü, yeniden başlatmada
kurtarma. Kod paylaşılmıyor (o modül soru merkezli ve 2.000 satır), desen
paylaşılıyor.

Tek işçi bir ayar değil zorunluluk: whisper-server süreç boyunca tek örnek
yaşıyor (574 MB model) ve MLX motoru üretimi zaten seri hâle getiriyor.

Kuyruk gözden geçirme ve onay senkron rotalarda: ikisi de milisaniyelik iş.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

from ..alim import kuyruk as kuyruk_birimi
from ..alim.cikarim import AlimHatasi
from .durum import Uygulama
from .yardimcilar import hata_yaniti

ASAMALAR = ("kunye", "indirme", "dokum", "cikarim", "kuyruk", "bitti", "hata", "durduruldu")
# Yeniden başlatmada bu durumdaki videolar `bekliyor`a döner; transkript
# önbelleği sayesinde tamamlanmış döküm ikinci kez yapılmaz.
YARIM_DURUMLAR = ("indiriliyor", "dokuluyor", "cikariliyor")


class YoutubeDeposu:
    """İş kuyruğunun kalıcı kaydı (`<kök>/youtube/isler.db`)."""

    def __init__(self, yol: Path):
        self.yol = Path(yol)
        self.yol.parent.mkdir(parents=True, exist_ok=True)
        self._kilit = threading.RLock()
        self._db = sqlite3.connect(str(self.yol), check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA journal_mode = WAL")
        self._sema()

    def _sema(self) -> None:
        with self._kilit:
            self._db.executescript(
                """
                CREATE TABLE IF NOT EXISTS is_kaydi (
                    id TEXT PRIMARY KEY,
                    durum TEXT NOT NULL,
                    asama TEXT NOT NULL DEFAULT 'kunye',
                    mesaj TEXT NOT NULL DEFAULT '',
                    url TEXT NOT NULL,
                    toplam_video INTEGER NOT NULL DEFAULT 0,
                    biten_video INTEGER NOT NULL DEFAULT 0,
                    aday_sayisi INTEGER NOT NULL DEFAULT 0,
                    hata_sayisi INTEGER NOT NULL DEFAULT 0,
                    durdur_istendi INTEGER NOT NULL DEFAULT 0,
                    secenekler TEXT NOT NULL DEFAULT '{}',
                    hata TEXT NOT NULL DEFAULT '',
                    olusturma TEXT NOT NULL,
                    guncelleme TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS is_videosu (
                    is_id TEXT NOT NULL,
                    sira INTEGER NOT NULL,
                    video_id TEXT NOT NULL,
                    baslik TEXT NOT NULL DEFAULT '',
                    kanal TEXT NOT NULL DEFAULT '',
                    sure_sn REAL NOT NULL DEFAULT 0,
                    durum TEXT NOT NULL DEFAULT 'bekliyor',
                    aday_sayisi INTEGER NOT NULL DEFAULT 0,
                    kuyruk_dosyasi TEXT NOT NULL DEFAULT '',
                    hata TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (is_id, sira)
                );
                """
            )
            self._db.commit()

    def kapat(self) -> None:
        with self._kilit:
            self._db.close()

    def _yaz(self, sql: str, veri: tuple = ()) -> None:
        with self._kilit:
            self._db.execute(sql, veri)
            self._db.commit()

    def is_ekle(self, url: str, secenekler: dict) -> str:
        is_id = uuid.uuid4().hex
        simdi = datetime.now().isoformat(timespec="seconds")
        self._yaz(
            "INSERT INTO is_kaydi (id, durum, asama, url, secenekler, olusturma, guncelleme)"
            " VALUES (?, 'bekliyor', 'kunye', ?, ?, ?, ?)",
            (is_id, url, json.dumps(secenekler, ensure_ascii=False), simdi, simdi),
        )
        return is_id

    def guncelle(self, is_id: str, **alanlar) -> None:
        if not alanlar:
            return
        alanlar["guncelleme"] = datetime.now().isoformat(timespec="seconds")
        atama = ", ".join(f"{ad} = ?" for ad in alanlar)
        self._yaz(
            f"UPDATE is_kaydi SET {atama} WHERE id = ?",
            (*alanlar.values(), is_id),
        )

    def videolari_yaz(self, is_id: str, videolar: list) -> None:
        with self._kilit:
            self._db.execute("DELETE FROM is_videosu WHERE is_id = ?", (is_id,))
            self._db.executemany(
                "INSERT INTO is_videosu (is_id, sira, video_id, baslik, kanal, sure_sn)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (is_id, sira, v.video_id, v.baslik, v.kanal, v.sure_sn)
                    for sira, v in enumerate(videolar, start=1)
                ],
            )
            self._db.commit()

    def video_guncelle(self, is_id: str, sira: int, **alanlar) -> None:
        if not alanlar:
            return
        atama = ", ".join(f"{ad} = ?" for ad in alanlar)
        self._yaz(
            f"UPDATE is_videosu SET {atama} WHERE is_id = ? AND sira = ?",
            (*alanlar.values(), is_id, sira),
        )

    def kayit(self, is_id: str) -> dict[str, Any] | None:
        with self._kilit:
            satir = self._db.execute(
                "SELECT * FROM is_kaydi WHERE id = ?", (is_id,)
            ).fetchone()
            if satir is None:
                return None
            videolar = self._db.execute(
                "SELECT * FROM is_videosu WHERE is_id = ? ORDER BY sira", (is_id,)
            ).fetchall()
        veri = dict(satir)
        veri["videolar"] = [dict(v) for v in videolar]
        return veri

    def isler(self, limit: int = 20) -> list[dict[str, Any]]:
        with self._kilit:
            satirlar = self._db.execute(
                "SELECT * FROM is_kaydi ORDER BY olusturma DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(s) for s in satirlar]

    def kurtarilacak_isler(self) -> list[str]:
        """Süreç yarıda kapandıysa yeniden kuyruğa girecek işler."""
        with self._kilit:
            satirlar = self._db.execute(
                "SELECT id FROM is_kaydi WHERE durum IN ('bekliyor', 'calisiyor')"
            ).fetchall()
            # Yer tutucular sayıdan üretiliyor: `repr(tuple)` bugün doğru SQL
            # veriyor ama sabit tek üyeye inerse `IN ('x',)` sözdizimi hatası
            # olurdu.
            yer_tutucu = ", ".join("?" * len(YARIM_DURUMLAR))
            self._db.execute(
                f"UPDATE is_videosu SET durum = 'bekliyor' WHERE durum IN ({yer_tutucu})",
                YARIM_DURUMLAR,
            )
            self._db.commit()
        return [s["id"] for s in satirlar]


class YoutubeServisi:
    """İndirme → döküm → çıkarım → kuyruk işini arka planda yürütür."""

    def __init__(
        self,
        kok: str | Path,
        motor_saglayici: Callable[[], Any] | None = None,
        *,
        baslangicta_kurtar: bool = True,
    ):
        self.kok = Path(kok)
        self.depo = YoutubeDeposu(self.kok / "youtube" / "isler.db")
        # Motor FABRİKA olarak alınır, örnek olarak değil: `Uygulama.motor`
        # tembel yükleniyor ve kurulum anında zorlamak arayüzün açılışını
        # modelin yükleme süresi kadar geciktirirdi.
        self._motor_saglayici = motor_saglayici
        self._havuz = ThreadPoolExecutor(max_workers=1, thread_name_prefix="biyo-youtube")
        self._kilit = threading.RLock()
        self._kapandi = False
        self._calisan: set[str] = set()
        if baslangicta_kurtar:
            for is_id in self.depo.kurtarilacak_isler():
                self.baslat(is_id)

    def kapat(self, *, bekleme_sn: float = 20.0) -> None:
        """Yürütücüyü durdurur, sonra veritabanını kapatır.

        Sıra önemli: `cancel_futures` KOŞMAKTA olan işi iptal etmiyor, yalnız
        kuyruktakileri atıyor. Beklemeden bağlantıyı kapatmak, çalışan işçinin
        altından veritabanını çekip `ProgrammingError`a düşürüyor ve iş satırı
        sonsuza dek "calisiyor" kalıyordu (her açılışta yeniden kuyruğa
        giriyor). Durdurma bayrağı işçinin bir sonraki video sınırında
        çıkmasını sağlar; süre dolarsa yine de kapatılır — kapanış asılamaz.
        """
        with self._kilit:
            self._kapandi = True
        self._havuz.shutdown(wait=False, cancel_futures=True)
        son = time.monotonic() + bekleme_sn
        while self._calisan and time.monotonic() < son:
            time.sleep(0.05)
        self.depo.kapat()

    def is_ekle(self, url: str, secenekler: dict | None = None) -> str:
        from ..alim.youtube import _url_dogrula

        # CLI ile AYNI kapı: form alanından gelen adres de doğrulanır.
        adres = _url_dogrula(url)
        return self.depo.is_ekle(adres, secenekler or {})

    def baslat(self, is_id: str) -> None:
        with self._kilit:
            if self._kapandi:
                return
        self._havuz.submit(self._yurut, is_id)

    def durdur(self, is_id: str) -> None:
        """Durdurma video SINIRINDA etkilidir; yarım döküm işe yaramaz."""
        self.depo.guncelle(is_id, durdur_istendi=1, mesaj="Durdurma istendi…")

    def durum(self, is_id: str) -> dict[str, Any] | None:
        return self.depo.kayit(is_id)

    def _zaten_islenmis(self, video) -> bool:
        """Video hafızaya alınmış ya da kuyrukta bekliyor mu?"""
        from ..depo import Depo

        if kuyruk_birimi.kuyrukta_mi(self.kok, video.video_id):
            return True
        veritabani = self.kok / "biyo.db"
        if not veritabani.is_file():
            return False
        return Depo(veritabani).kaynak_alindi_mi(video.imza)

    def _durduruldu_mu(self, is_id: str) -> bool:
        with self._kilit:
            if self._kapandi:
                return True
        kayit = self.depo.kayit(is_id)
        return bool(kayit and kayit["durdur_istendi"])

    def _yurut(self, is_id: str) -> None:
        """İşi yürütür; HER hata iş kaydına yazılır.

        Üst düzey yakalama şart: yalnız `AlimHatasi` yakalandığında disk
        dolması, bozuk seçenek JSON'u ya da beklenmedik bir motor istisnası
        future'ın içinde sessizce ölüyor, satır "calisiyor" kalıyor ve her
        açılışta kurtarma onu yeniden kuyruğa sokuyordu — kullanıcıya hiç
        hata göstermeyen sonsuz yeniden deneme döngüsü.
        """
        with self._kilit:
            self._calisan.add(is_id)
        try:
            self._isi_yurut(is_id)
        except Exception as exc:  # noqa: BLE001 - son durak; hata kaydedilmeli
            # Kapanış sırasında veritabanı kapanmış olabilir; kurtarma bir
            # sonraki açılışta işi yeniden ele alır.
            with suppress(sqlite3.Error, sqlite3.ProgrammingError):
                self.depo.guncelle(
                    is_id, durum="hata", asama="hata", hata=f"Beklenmedik hata: {exc}"
                )
        finally:
            with self._kilit:
                self._calisan.discard(is_id)

    def _isi_yurut(self, is_id: str) -> None:
        from ..alim.konusma import PENCERE_KARAKTERI, sorulari_cikar
        from ..alim.youtube import kunye_getir, videoyu_dok

        kayit = self.depo.kayit(is_id)
        if kayit is None or kayit["durum"] in {"bitti", "durduruldu"}:
            return
        secenekler = json.loads(kayit["secenekler"] or "{}")
        self.depo.guncelle(is_id, durum="calisiyor", asama="kunye", mesaj="Künye çekiliyor…")

        try:
            videolar = kunye_getir(kayit["url"], limit=int(secenekler.get("limit") or 0))
        except AlimHatasi as exc:
            self.depo.guncelle(is_id, durum="hata", asama="hata", hata=str(exc))
            return
        self.depo.videolari_yaz(is_id, videolar)
        self.depo.guncelle(is_id, toplam_video=len(videolar))

        motor = None
        if not secenekler.get("kural") and self._motor_saglayici is not None:
            try:
                motor = self._motor_saglayici()
            except Exception as exc:  # noqa: BLE001 - motor yoksa kural yoluna düşülür
                self.depo.guncelle(is_id, mesaj=f"Motor yüklenemedi ({exc}); kural yolu.")

        toplam_aday = hata_sayisi = atlanan_video = 0
        for sira, video in enumerate(videolar, start=1):
            if self._durduruldu_mu(is_id):
                self.depo.guncelle(
                    is_id, durum="durduruldu", asama="durduruldu",
                    mesaj=f"{sira - 1}/{len(videolar)} videodan sonra durduruldu.",
                )
                return
            ad = video.baslik or video.video_id
            if not secenekler.get("yeniden") and self._zaten_islenmis(video):
                # CLI'daki `youtube-al` ile aynı koruma: aynı adresi iki kez
                # göndermek aynı adaylardan ikinci bir kuyruk dosyası
                # üretmemeli.
                atlanan_video += 1
                self.depo.video_guncelle(is_id, sira, durum="atlandi")
                self.depo.guncelle(is_id, biten_video=sira)
                continue
            try:
                self.depo.video_guncelle(is_id, sira, durum="dokuluyor")
                self.depo.guncelle(
                    is_id, asama="dokum", mesaj=f"{sira}/{len(videolar)} · {ad}: yazıya dökülüyor…"
                )
                kaynak = videoyu_dok(
                    video, kok=self.kok, yeniden=bool(secenekler.get("yeniden"))
                )
                self.depo.video_guncelle(is_id, sira, durum="cikariliyor")
                self.depo.guncelle(
                    is_id, asama="cikarim", mesaj=f"{sira}/{len(videolar)} · {ad}: sorular çıkarılıyor…"
                )
                adaylar, yontem = sorulari_cikar(
                    kaynak, motor, boyut=int(secenekler.get("pencere") or PENCERE_KARAKTERI)
                )
            except Exception as exc:  # noqa: BLE001 - tek video işi düşürmemeli
                # `AlimHatasi` dışındaki hatalar da (disk dolu, bozuk medya,
                # motorun beklenmedik istisnası) yalnız O videoyu düşürmeli;
                # playlist'in kalanı işlenmeye devam eder.
                hata_sayisi += 1
                self.depo.video_guncelle(is_id, sira, durum="hata", hata=str(exc))
                self.depo.guncelle(is_id, hata_sayisi=hata_sayisi, biten_video=sira)
                continue

            asgari = float(secenekler.get("asgari_guven") or 0.0)
            uygun = [a for a in adaylar if a.guven >= asgari]
            dosya_adi = ""
            if uygun:
                from ..cli import _kuyruk_kaydi

                kayitlar = [_kuyruk_kaydi(video, aday, yontem) for aday in uygun]
                yol = kuyruk_birimi.kuyruk_dizini(self.kok) / kuyruk_birimi.dosya_adi(
                    video.video_id
                )
                kuyruk_birimi.yaz(yol, kayitlar)
                dosya_adi = yol.name
                toplam_aday += len(kayitlar)
            self.depo.video_guncelle(
                is_id, sira, durum="bitti", aday_sayisi=len(uygun), kuyruk_dosyasi=dosya_adi
            )
            self.depo.guncelle(is_id, biten_video=sira, aday_sayisi=toplam_aday)

        if toplam_aday:
            mesaj = f"{toplam_aday} aday kuyruğa yazıldı."
        elif atlanan_video:
            mesaj = f"{atlanan_video} video zaten alınmış ya da kuyrukta; atlandı."
        else:
            mesaj = "Aday çıkmadı."
        self.depo.guncelle(is_id, durum="bitti", asama="bitti", mesaj=mesaj)


def yonlendirici(durum: Uygulama, sablon, *, servis: YoutubeServisi | None = None) -> APIRouter:
    yonlendirici = APIRouter()
    youtube_servisi = servis or YoutubeServisi(durum.kok, lambda: durum.motor)
    yonlendirici.youtube_servisi = youtube_servisi

    def _kuyruk_dosyasi(ad: str) -> Path | None:
        return kuyruk_birimi.bul(durum.kok, ad)

    @yonlendirici.get("/youtube", response_class=HTMLResponse)
    def youtube_formu(request: Request, is_id: str = ""):
        return sablon.TemplateResponse(
            request,
            "youtube.html",
            {
                "durum": durum.durum(),
                "etkin": "youtube",
                "isler": youtube_servisi.depo.isler(),
                "is_id": is_id,
                "kuyruk_ozeti": kuyruk_birimi.ozet(durum.kok),
            },
        )

    @yonlendirici.post("/youtube/is")
    def youtube_is_ekle(
        request: Request,
        url: str = Form(...),
        limit: int = Form(0),
        asgari_guven: float = Form(0.0),
        kural: str = Form(""),
        yeniden: str = Form(""),
    ):
        try:
            is_id = youtube_servisi.is_ekle(
                url,
                {
                    "limit": max(0, limit),
                    "asgari_guven": asgari_guven,
                    "kural": bool(kural),
                    "yeniden": bool(yeniden),
                },
            )
        except AlimHatasi as exc:
            return hata_yaniti(
                sablon, durum, request, str(exc),
                baslik="Adres kabul edilmedi", geri="/youtube",
            )
        youtube_servisi.baslat(is_id)
        return RedirectResponse(f"/youtube?is_id={is_id}", status_code=303)

    @yonlendirici.get("/youtube/api/is/{is_id}")
    def youtube_is_durumu(is_id: str):
        kayit = youtube_servisi.durum(is_id)
        if kayit is None:
            return JSONResponse({"hata": "İş bulunamadı."}, status_code=404)
        return JSONResponse(kayit)

    @yonlendirici.post("/youtube/api/is/{is_id}/durdur")
    def youtube_is_durdur(is_id: str):
        if youtube_servisi.durum(is_id) is None:
            return JSONResponse({"hata": "İş bulunamadı."}, status_code=404)
        youtube_servisi.durdur(is_id)
        return JSONResponse({"durum": "durdurma_istendi"})

    @yonlendirici.get("/kuyruk", response_class=HTMLResponse)
    def kuyruk_listesi(request: Request):
        dosyalar = []
        for yol in kuyruk_birimi.dosyalar(durum.kok):
            kayitlar, bozuk = kuyruk_birimi.oku(yol)
            dosyalar.append(
                {
                    "ad": yol.name,
                    "toplam": len(kayitlar),
                    "bekleyen": sum(1 for k in kayitlar if k.durum == "bekliyor"),
                    "onayli": sum(1 for k in kayitlar if k.durum == "onay"),
                    "bozuk": bozuk,
                    "baslik": kayitlar[0].video_basligi if kayitlar else "",
                }
            )
        return sablon.TemplateResponse(
            request,
            "kuyruk.html",
            {
                "durum": durum.durum(),
                "etkin": "kuyruk",
                "dosyalar": dosyalar,
                "ozet": kuyruk_birimi.ozet(durum.kok),
            },
        )

    @yonlendirici.get("/kuyruk/{ad}", response_class=HTMLResponse)
    def kuyruk_dosyasi(request: Request, ad: str):
        yol = _kuyruk_dosyasi(ad)
        if yol is None:
            return hata_yaniti(
                sablon, durum, request, f"Kuyruk dosyası bulunamadı: {ad}",
                baslik="Bulunamadı", geri="/kuyruk", kod=404,
            )
        kayitlar, bozuk = kuyruk_birimi.oku(yol)
        return sablon.TemplateResponse(
            request,
            "kuyruk_dosyasi.html",
            {
                "durum": durum.durum(),
                "etkin": "kuyruk",
                "ad": yol.name,
                "kayitlar": list(enumerate(kayitlar, start=1)),
                "bozuk": bozuk,
            },
        )

    @yonlendirici.post("/kuyruk/{ad}/satir/{kimlik}")
    def kuyruk_satir_guncelle(
        request: Request,
        ad: str,
        kimlik: str,
        soru: str = Form(""),
        cozum: str = Form(""),
        cevap: str = Form(""),
        konu: str = Form(""),
    ):
        yol = _kuyruk_dosyasi(ad)
        if yol is None:
            return hata_yaniti(
                sablon, durum, request, f"Kuyruk dosyası bulunamadı: {ad}",
                baslik="Bulunamadı", geri="/kuyruk", kod=404,
            )
        try:
            kuyruk_birimi.satiri_guncelle(
                yol, kimlik,
                {"soru": soru, "cozum": cozum, "cevap": cevap, "konu": konu},
            )
        except ValueError as exc:
            return hata_yaniti(
                sablon, durum, request, str(exc),
                baslik="Kayıt güncellenemedi", geri=f"/kuyruk/{yol.name}",
            )
        return RedirectResponse(f"/kuyruk/{yol.name}", status_code=303)

    @yonlendirici.post("/kuyruk/{ad}/toplu")
    def kuyruk_toplu_isaretle(
        request: Request,
        ad: str,
        secilenler: list[str] = Form(default=[]),
        eylem: str = Form("onay"),
    ):
        yol = _kuyruk_dosyasi(ad)
        if yol is None:
            return hata_yaniti(
                sablon, durum, request, f"Kuyruk dosyası bulunamadı: {ad}",
                baslik="Bulunamadı", geri="/kuyruk", kod=404,
            )
        if secilenler and eylem in {"onay", "ret", "bekliyor"}:
            try:
                kuyruk_birimi.durumlari_isaretle(yol, list(secilenler), eylem)
            except ValueError as exc:
                # Bayat sekme ya da geri tuşuyla yeniden gönderim: kayıt artık
                # dosyada olmayabilir. Yığın izi yerine anlaşılır sayfa.
                return hata_yaniti(
                    sablon, durum, request, str(exc),
                    baslik="İşaretleme uygulanamadı",
                    oneri="Sayfayı yenileyip yeniden deneyin.",
                    geri=f"/kuyruk/{yol.name}",
                )
        return RedirectResponse(f"/kuyruk/{yol.name}", status_code=303)

    @yonlendirici.post("/kuyruk/{ad}/aktar", response_class=HTMLResponse)
    def kuyruk_aktar(request: Request, ad: str):
        """Onaylı kayıtları hafızaya yazar ve indeksi ARTIMLI günceller."""
        yol = _kuyruk_dosyasi(ad)
        if yol is None:
            return hata_yaniti(
                sablon, durum, request, f"Kuyruk dosyası bulunamadı: {ad}",
                baslik="Bulunamadı", geri="/kuyruk", kod=404,
            )
        kayitlar, _bozuk = kuyruk_birimi.oku(yol)
        # Eşleme KALICI KİMLİKLE: aşağıdaki döngü kayıt başına gömme yapıyor
        # ve dosya bu sırada değişebilir; sıra tabanlı eşleme kayarak hiç
        # yazılmamış bir kaydı "alindi" damgalayıp sessizce kaybederdi.
        sonuclar: dict[str, int] = {}
        imzalar: set[str] = set()
        eklenen = guncellenen = 0
        atlananlar: list[str] = []
        for kayit in kayitlar:
            if kayit.durum != "onay":
                continue
            ornek = kuyruk_birimi.ornege_cevir(kayit)
            if ornek is None:
                atlananlar.append(f"{kayit.soru[:60]}: soru ya da çözüm boş")
                continue
            try:
                onceki = durum.depo.ornek_sayisi()
                kimlik = durum.depo.ornek_ekle(ornek)
            except ValueError as exc:
                # Yinelenen soru: sessizce yutulursa kullanıcı 30 kaydı
                # onaylayıp 5'inin neden hâlâ "onay" durumunda kaldığını ve
                # dosyanın neden arşivlenmediğini hiçbir yerde göremezdi.
                atlananlar.append(f"{kayit.soru[:60]}: {exc}")
                continue
            if durum.depo.ornek_sayisi() > onceki:
                eklenen += 1
            else:
                guncellenen += 1
            sonuclar[kayit.kimlik] = kimlik
            if kayit.kaynak_imzasi:
                imzalar.add(kayit.kaynak_imzasi)
            # Örnek TAZE okunur: `ornek_ekle` yalnız kimlik döndürüyor,
            # nesneyi güncellemiyor; id'siz örnek indekse girerse `icerir`
            # ve `sil` onu bir daha bulamaz.
            yazilan = durum.depo.ornek(kimlik)
            if yazilan is not None:
                durum.ornegi_indeksle(yazilan)

        if sonuclar:
            kuyruk_birimi.alindi_isaretle(yol, sonuclar)
            for imza in imzalar:
                durum.depo.kaynagi_isaretle(imza)
            durum.depo.denetim_yaz(
                "kuyruk_onayla", f"eklenen={eklenen} guncellenen={guncellenen}"
            )
            kalan, _ = kuyruk_birimi.oku(yol)
            if kalan and all(k.durum in {"alindi", "ret"} for k in kalan):
                kuyruk_birimi.arsivle(yol, durum.kok)
                return RedirectResponse("/kuyruk", status_code=303)
        if atlananlar:
            return sablon.TemplateResponse(
                request,
                "kuyruk_aktarim.html",
                {
                    "durum": durum.durum(),
                    "etkin": "kuyruk",
                    "ad": yol.name,
                    "eklenen": eklenen,
                    "guncellenen": guncellenen,
                    "atlananlar": atlananlar,
                },
            )
        return RedirectResponse(f"/kuyruk/{yol.name}", status_code=303)

    @yonlendirici.post("/kuyruk/{ad}/sil")
    def kuyruk_dosyasi_sil(request: Request, ad: str, onaylandi: str = Form("")):
        yol = _kuyruk_dosyasi(ad)
        if yol is None:
            return hata_yaniti(
                sablon, durum, request, f"Kuyruk dosyası bulunamadı: {ad}",
                baslik="Bulunamadı", geri="/kuyruk", kod=404,
            )
        if not onaylandi:
            # CLI'daki `kuyruk-sil` bekleyen kayıt varsa soruyor; arayüzde de
            # tek tıkla bir videonun tüm adayları ve elle yapılmış düzeltmeler
            # gitmemeli.
            return hata_yaniti(
                sablon, durum, request,
                "Silme onaylanmadı.",
                baslik="Kuyruk dosyası silinmedi",
                oneri="Silmek için onay kutusunu işaretleyin.",
                geri=f"/kuyruk/{yol.name}",
            )
        yol.unlink(missing_ok=True)
        return RedirectResponse("/kuyruk", status_code=303)

    return yonlendirici
