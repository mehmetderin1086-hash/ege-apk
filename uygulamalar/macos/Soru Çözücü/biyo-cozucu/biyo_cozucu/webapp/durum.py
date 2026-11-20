"""Web uygulamasının paylaşılan durumu.

Model ve gömlemci süreç boyunca tek örnek olarak yaşar; her istekte yeniden
yüklemek 16 GB'lik bir makinede kabul edilemez. Yükleme tembel yapılır: motor
ilk gerçek çözüm isteğine kadar belleğe alınmaz, böylece arayüz anında açılır.
"""

from __future__ import annotations

import importlib.util
import threading
from dataclasses import dataclass, field
from pathlib import Path

from ..cozucu import Ayarlar, Cozucu
from ..depo import Depo
from ..gomme import Gomlemci
from ..hafiza.indeks import OrnekIndeksi
from ..modeller import Ornek
from ..motor.temel import Motor, MotorHatasi


@dataclass
class Uygulama:
    kok: Path
    motor_turu: str = "mlx"
    gommesiz: bool = False
    ayarlar: Ayarlar = field(default_factory=Ayarlar)
    _kilit: threading.Lock = field(default_factory=threading.Lock, repr=False)
    _depo: Depo | None = field(default=None, repr=False)
    _indeks: OrnekIndeksi | None = field(default=None, repr=False)
    _pasaj_indeksi: object | None = field(default=None, repr=False)
    _pasaj_sayisi: int = field(default=-1, repr=False)
    _gomlemci: Gomlemci | None = field(default=None, repr=False)
    _gomlemci_denendi: bool = field(default=False, repr=False)
    _motor: Motor | None = field(default=None, repr=False)
    _motor_hatasi: str = field(default="", repr=False)

    # --- bileşenler ---

    @property
    def depo(self) -> Depo:
        with self._kilit:
            if self._depo is None:
                self._depo = Depo(self.kok / "biyo.db")
            return self._depo

    @property
    def gomlemci(self) -> Gomlemci | None:
        if self.gommesiz:
            return None
        with self._kilit:
            if not self._gomlemci_denendi:
                # Modül üzerinden çağrılır, ad import anında bağlanmaz:
                # aksi halde `gomme.gomlemci_yukle` yerine konan sahte
                # gömlemci hiç devreye girmez ve testler farkında olmadan
                # 2 GB'lık gerçek modeli yükler (test başına ~11 sn).
                from .. import gomme as gomme_modulu

                self._gomlemci = gomme_modulu.gomlemci_yukle()
                self._gomlemci_denendi = True
            return self._gomlemci

    @property
    def indeks(self) -> OrnekIndeksi:
        with self._kilit:
            if self._indeks is None:
                dizin = self.kok / "indeks"
                if OrnekIndeksi.hazir_mi(dizin):
                    self._indeks = OrnekIndeksi.yukle(dizin)
                else:
                    self._indeks = OrnekIndeksi.kur([], None)
            return self._indeks

    def indeksi_yenile(self) -> OrnekIndeksi:
        indeks = OrnekIndeksi.kur(self.depo.ornekler(), self.gomlemci)
        indeks.kaydet(self.kok / "indeks")
        with self._kilit:
            self._indeks = indeks
        return indeks

    def ornegi_indeksle(self, ornek: Ornek) -> None:
        """Tek örneği artımlı olarak indekse işler.

        Tam yeniden kurulum koleksiyondaki her örneği yeniden gömdürüyor;
        tek örnek eklendiğinde bunu yapmak, hafıza büyüdükçe her kaydı
        dakikalara çıkarır. Artımlı yol uygulanamazsa (gömme modeli değişmiş,
        indeks yok) tam kuruluma düşülür — tutarsız bir indeks, yavaş bir
        indeksten kötüdür.

        Kilit TÜM değişiklik boyunca tutulur. FastAPI'nin senkron rotaları bir
        iş parçacığı havuzunda gerçekten paralel koşuyor ve gömme çağrısı
        yavaş; kilit yalnız `_indeks` okunurken tutulduğunda iki eşzamanlı
        ekleme, gömme satırlarını örneklerle kaydırıyordu (`gomme[3]` 4
        numaralı örneğin vektörünü tutuyordu). Uzunluklar tuttuğu için
        `anlamsal_hazir` True kalıyor ve hiçbir denetim uyarmıyor: anlamsal
        arama sessizce yanlış örneği kanıt gösteriyordu.
        """
        # Gömlemci ve örnek sayısı kilit DIŞINDA çözülür: ikisinin de özelliği
        # aynı kilidi alıyor ve `_kilit` yeniden girişli değil
        # (threading.Lock). Ayrıca modelin tembel yüklenmesi yavaş; indeks
        # kilidini tutmamalı.
        gomlemci = self.gomlemci
        beklenen_sayi = self.depo.ornek_sayisi()
        with self._kilit:
            indeks = self._indeks
            if indeks is not None:
                # İki ayrı soru, iki ayrı denetim:
                # 1) "Ekleme mi güncelleme mi" — örneğin İNDEKSTE OLUP
                #    OLMADIĞINA bakılır. Örnek sayısını karşılaştırmak yakın
                #    ama yanlış bir vekildi: indeks depodan bir örnek geride
                #    kaldığında güncellemeyi ekleme sanıp aynı örneği ikinci
                #    kez yazıyordu.
                if indeks.icerir(ornek.id):
                    basarili = indeks.degistir(ornek, gomlemci)
                else:
                    basarili = indeks.ekle(ornek, gomlemci)
                # 2) "İndeks depoyla tutarlı mı" — işlem başarılı olsa da
                #    sayılar tutmuyorsa indeks başka bir nedenle bayattır
                #    (ör. `ornek-ekle --indekssiz`), tam kurulumla onarılır.
                if basarili and len(indeks) == beklenen_sayi:
                    indeks.kaydet(self.kok / "indeks")
                    return
        self.indeksi_yenile()

    def ornegi_indeksten_sil(self, ornek_id: int | None) -> None:
        beklenen_sayi = self.depo.ornek_sayisi()
        with self._kilit:
            indeks = self._indeks
            if indeks is not None:
                if not indeks.icerir(ornek_id) and len(indeks) == beklenen_sayi:
                    # Zaten indekste değil ve indeks tutarlı: yapacak iş yok.
                    # Tam kuruluma düşmek, silme düğmesine iki kez tıklamayı
                    # her seferinde tüm koleksiyonu yeniden gömdüren bir
                    # işleme çevirirdi.
                    return
                if indeks.sil(ornek_id) and len(indeks) == beklenen_sayi:
                    indeks.kaydet(self.kok / "indeks")
                    return
        self.indeksi_yenile()

    @property
    def pasaj_indeksi(self) -> object | None:
        """Ders kitabı hafızasını güncel tutan, sayıca doğrulanan indeks.

        Kitap aktarımı web sunucusu ayaktayken de yapılabildiğinden, yalnız
        ilk istekle kurulan bir indeks yeni pasajları sessizce görmezdi.
        Pasaj sayısı değiştiğinde indeksi yeniden kuruyoruz; aksi durumda
        aynı nesne tekrar kullanılır ve her çözümde binlerce pasaj taranmaz.
        """
        toplam = self.depo.pasaj_say()
        with self._kilit:
            if toplam == self._pasaj_sayisi:
                return self._pasaj_indeksi

        from ..hafiza.pasaj import PasajIndeksi

        yeni = (
            PasajIndeksi.kur(self.depo.pasajlar(), self.gomlemci)
            if toplam
            else None
        )
        with self._kilit:
            self._pasaj_indeksi = yeni
            self._pasaj_sayisi = toplam
            return self._pasaj_indeksi

    @property
    def motor(self) -> Motor | None:
        if self.motor_turu == "yok":
            return None
        with self._kilit:
            if self._motor is None and not self._motor_hatasi:
                from ..motor import motor_yukle

                try:
                    self._motor = motor_yukle(self.motor_turu)
                except MotorHatasi as exc:
                    self._motor_hatasi = str(exc)
            return self._motor

    @property
    def motor_hatasi(self) -> str:
        return self._motor_hatasi

    def cozucu(self, **ayar_degisiklikleri) -> Cozucu:
        """İstek başına bağımsız ayar kopyasıyla çözücü kurar."""
        from dataclasses import replace

        ayarlar = (
            replace(self.ayarlar, **ayar_degisiklikleri)
            if ayar_degisiklikleri
            else replace(self.ayarlar)
        )
        from ..gorsel import GorselDeposu

        return Cozucu(
            depo=self.depo,
            indeks=self.indeks,
            motor=self.motor,
            gomlemci=self.gomlemci,
            ayarlar=ayarlar,
            gorsel_deposu=GorselDeposu(self.kok),
            pasaj_indeksi=self.pasaj_indeksi,
        )

    def durum(self) -> dict[str, object]:
        ozet = dict(self.depo.ozet())
        ozet["indeks"] = len(self.indeks)
        ozet["anlamsal"] = self.indeks.anlamsal_hazir
        ozet["gomme_modeli"] = self.indeks.gomme_modeli or "—"
        ozet["motor_turu"] = self.motor_turu
        ozet["motor_hatasi"] = self._motor_hatasi
        ozet["motor_yuklu"] = self._motor is not None
        # Arayüz resim/PDF yüklemeyi öne çıkarıyor. Yalnız seçili motor adına
        # bakmak yeterli değil: ``karma`` seçilmiş olsa da mlx-vlm paketi eksik
        # olabilir ve kullanıcı bunu ancak uzun bir ilk denemeden sonra görür.
        # ``find_spec`` paketi yüklemez; sayfa açılışını ve belleği etkilemez.
        gorsel_motor_secili = self.motor_turu in {"karma", "vlm", "sahte"}
        ozet["gorsel_hazir"] = gorsel_motor_secili and (
            self.motor_turu == "sahte" or importlib.util.find_spec("mlx_vlm") is not None
        )
        ozet["indeks_bayat"] = len(self.indeks) != int(ozet["ornek"])
        return ozet
