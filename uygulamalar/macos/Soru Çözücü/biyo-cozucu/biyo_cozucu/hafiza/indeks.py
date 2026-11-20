"""Referans örnek indeksi: sözcüksel (BM25) + anlamsal (gömme) hibrit erişim.

Vektör veritabanı bilinçli olarak kullanılmıyor. Koleksiyon birkaç bin örnek
mertebesinde kaldığı sürece numpy ile tam tarama hem daha hızlı hem de sıfır
ek bağımlılık; erişim kalitesini belirleyen şey veritabanı değil, sorgu ve
birleştirme stratejisi.
"""

from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path

import numpy as np

from ..gomme import Gomlemci, kosinus
from ..metin import esitle
from ..modeller import Ornek

_KELIME = re.compile(r"[0-9a-zA-ZçğıöşüÇĞİÖŞÜ]{2,}")

# Bu kosinüs değerinin altındaki adaylar anlamsal sıralamaya hiç girmez.
# Çok dilli erişim modellerinde ilgisiz çiftler tipik olarak 0.2-0.5 bandında
# kaldığından taban buna göre seçildi; daha yüksek bir taban gerçek eş anlamlı
# eşleşmeleri de eler.
ANLAMSAL_TABAN = 0.55

# Biyoloji sorularında sık geçen, ayırt edici olmayan sözcükler.
_DURAK = {
    "acaba", "ait", "ama", "ancak", "aşağıdaki", "aşağıdakilerden", "bazı",
    "belirt", "bile", "bir", "biri", "birinde", "bu", "buna", "bunlardan",
    "bunu", "çok", "da", "daha", "de", "değildir", "değil", "diye", "en",
    "gibi", "göre", "hangi", "hangisi", "hangisidir", "hem", "her", "için",
    "ile", "ilgili", "ise", "kadar", "ki", "mı", "mi", "mu", "mü", "nasıl",
    "ne", "neden", "nedir", "olan", "olarak", "olduğunu", "olur", "sonuç",
    "şekilde", "söylenebilir", "ve", "veya", "verilen", "ya", "yani",
    "yukarıdaki", "yukarıdakilerden",
}


def terimler(metin: str) -> list[str]:
    """Metni BM25 terimlerine ayırır (Türkçe katlama + durak sözcük eleme)."""
    return [t for t in (esitle(k) for k in _KELIME.findall(metin)) if t not in _DURAK]


# Kök eşleşmesi için gereken asgari uzunluk. Ters indeksin önek kovası da bu
# değerle anahtarlanıyor — ikisi ayrışırsa kova bazı adayları kaçırır.
_KOK_ASGARI = 5


def _kok_eslesir(sol: str, sag: str) -> bool:
    """Türkçe çekim eklerinde tam sözcük kaçırmalarını azaltır ("mitozda" ≈ "mitoz")."""
    return sol == sag or (
        min(len(sol), len(sag)) >= _KOK_ASGARI
        and (sol.startswith(sag) or sag.startswith(sol))
    )


class BM25:
    """Klasik BM25 (k1=1.5, b=0.75), kök eşleşmeli geri düşüşle."""

    def __init__(self, belgeler: list[str], k1: float = 1.5, b: float = 0.75):
        self.k1 = k1
        self.b = b
        self._sayimlar = [Counter(terimler(m)) for m in belgeler]
        # Belge frekansı ve toplam uzunluk alan olarak tutuluyor: `ekle`/`sil`
        # bunları artımlı güncelleyip yalnız idf'i yeniden türetiyor. Tüm
        # belgeleri yeniden terimlere ayırmak (pahalı olan kısım) gerekmiyor.
        self._belge_frekansi: Counter[str] = Counter()
        for sayim in self._sayimlar:
            self._belge_frekansi.update(sayim.keys())
        self._toplam_boy = sum(sum(s.values()) for s in self._sayimlar)
        # Ters indeks TEMBEL kuruluyor: `sil` belge sıralarını kaydırdığı için
        # geçiş listelerini artımlı güncellemek kırılgan olurdu. Kurulum tüm
        # jetonlar üzerinde tek geçiş (9.400 örnekte ~1 sn) ve değişiklikler
        # sorgulara kıyasla seyrek; ilk `puanla` çağrısında kuruluyor.
        self._gecis: dict[str, dict[int, int]] = {}
        self._onek_kovalari: dict[str, list[str]] = {}
        self._boylar = np.zeros(0, dtype=np.float32)
        self._gecis_gecerli = False
        self._istatistikleri_tazele()

    def _istatistikleri_tazele(self) -> None:
        # Sözlük ya da belge kümesi değiştiyse ters indeks artık geçerli değil.
        self._gecis_gecerli = False
        belge_sayisi = max(1, len(self._sayimlar))
        self.idf = {
            terim: math.log(1.0 + (belge_sayisi - adet + 0.5) / (adet + 0.5))
            for terim, adet in self._belge_frekansi.items()
        }
        self._ortalama_boy = (self._toplam_boy / belge_sayisi) or 1.0

    def ekle(self, belge: str) -> None:
        """Tek belgeyi indekse katar; diğer belgeler yeniden ayrıştırılmaz."""
        sayim = Counter(terimler(belge))
        self._sayimlar.append(sayim)
        self._belge_frekansi.update(sayim.keys())
        self._toplam_boy += sum(sayim.values())
        self._istatistikleri_tazele()

    def degistir(self, sira: int, belge: str) -> None:
        sayim = Counter(terimler(belge))
        eski = self._sayimlar[sira]
        self._belge_frekansi.subtract(eski.keys())
        self._toplam_boy -= sum(eski.values())
        self._sayimlar[sira] = sayim
        self._belge_frekansi.update(sayim.keys())
        self._toplam_boy += sum(sayim.values())
        self._temizle()
        self._istatistikleri_tazele()

    def sil(self, sira: int) -> None:
        eski = self._sayimlar.pop(sira)
        self._belge_frekansi.subtract(eski.keys())
        self._toplam_boy -= sum(eski.values())
        self._temizle()
        self._istatistikleri_tazele()

    def _temizle(self) -> None:
        """Frekansı sıfıra düşen terimleri atar.

        `Counter.subtract` sıfır (ve negatif) girdileri saklıyor; bırakılırsa
        idf sözlüğü hiçbir belgede geçmeyen terimlerle şişer ve o terimler
        `log(1 + (N + 0.5) / 0.5)` ile en yüksek ağırlığı alırdı.
        """
        for terim, adet in list(self._belge_frekansi.items()):
            if adet <= 0:
                del self._belge_frekansi[terim]

    def __len__(self) -> int:
        return len(self._sayimlar)

    def _gecisleri_kur(self) -> None:
        """Ters indeksi (terim → {belge: frekans}) ve önek kovalarını kurar.

        ÖNEK KOVASI neden yeterli: `_kok_eslesir` iki terimi ancak biri
        diğeriyle başlıyorsa ve ikisi de en az 5 karakterse eşleştiriyor —
        bu da ilk 5 karakterlerinin AYNI olması demek. Yani 5 karakterlik
        önek kovası, kök eşleşmesi için tam (hiçbir adayı kaçırmayan) bir
        süzgeç. Böylece kök arama, belge başına tüm terimleri taramak yerine
        sorgu başına bir kova okumasına iniyor.
        """
        gecis: dict[str, dict[int, int]] = {}
        onekler: dict[str, list[str]] = {}
        for belge, sayim in enumerate(self._sayimlar):
            for terim, adet in sayim.items():
                gecis.setdefault(terim, {})[belge] = adet
        for terim in gecis:
            if len(terim) >= _KOK_ASGARI:
                onekler.setdefault(terim[:_KOK_ASGARI], []).append(terim)
        self._gecis = gecis
        self._onek_kovalari = onekler
        self._boylar = np.array(
            [max(1, sum(s.values())) for s in self._sayimlar], dtype=np.float32
        )
        self._gecis_gecerli = True

    def _kok_adaylari(self, terim: str) -> list[str]:
        """Sorgu terimiyle kök eşleşen sözlük terimleri (tam eşleşme hariç)."""
        if len(terim) < _KOK_ASGARI:
            return []
        return [
            aday
            for aday in self._onek_kovalari.get(terim[:_KOK_ASGARI], ())
            if aday != terim and _kok_eslesir(terim, aday)
        ]

    def puanla(self, sorgu: str) -> np.ndarray:
        """Her belge için BM25 puanı döndürür (uzunluk = belge sayısı).

        Ters indeks üzerinden SEYREK hesaplanıyor: yalnız sorgu terimini (ya
        da kök eşini) gerçekten içeren belgeler dolaşılıyor. Eskiden her sorgu
        tüm belgeleri, her belge için de tüm terimlerini tarıyordu; 3.000
        belgelik indekste 25 sorgu `_kok_eslesir`'i 62 MİLYON kez çağırıyor ve
        sorgu başına 660 ms sürüyordu. Korpus 9.400 örneğe çıkınca bu, her
        soru çözümüne ~0,7 sn ekleyen bir gerileme hâline geldi.
        """
        if not self._gecis_gecerli:
            self._gecisleri_kur()
        sorgu_sayaci = Counter(terimler(sorgu))
        puanlar = np.zeros(len(self._sayimlar), dtype=np.float32)
        if not sorgu_sayaci:
            return puanlar

        ortalama = self._ortalama_boy or 1.0
        for terim, qf in sorgu_sayaci.items():
            agirlik = min(2, qf)
            # (belge → (tf, idf)) — tam eşleşme kök eşleşmesini EZER, çünkü
            # özgün davranışta kök yolu yalnız `tf == 0` iken çalışıyordu.
            katkilar: dict[int, tuple[int, float]] = {}
            tam_idf = self.idf.get(terim, 0.0)
            for belge, tf in self._gecis.get(terim, {}).items():
                katkilar[belge] = (tf, tam_idf)
            for aday in self._kok_adaylari(terim):
                # Kök eşleşmesi tam eşleşme kadar güçlü sayılmaz.
                aday_idf = self.idf.get(aday, 0.0) * 0.85
                for belge, tf in self._gecis.get(aday, {}).items():
                    if belge in katkilar and katkilar[belge][1] == tam_idf:
                        continue  # bu belgede terim zaten tam eşleşti
                    mevcut = katkilar.get(belge)
                    # Özgün seçim ölçütü: frekans × idf en yüksek olan kök eşi.
                    if mevcut is None or tf * aday_idf > mevcut[0] * mevcut[1]:
                        katkilar[belge] = (tf, aday_idf)
            for belge, (tf, idf) in katkilar.items():
                boy = float(self._boylar[belge])
                payda = tf + self.k1 * (1 - self.b + self.b * boy / ortalama)
                puanlar[belge] += idf * (tf * (self.k1 + 1) / payda) * agirlik
        return puanlar


def rrf_birlestir(
    siralamalar: list[list[int]], *, agirliklar: list[float] | None = None, k: int = 60
) -> dict[int, float]:
    """Reciprocal Rank Fusion — farklı ölçekteki skorları sıralama üzerinden birleştirir.

    Skorları doğrudan toplamak yerine sıralama kullanmak, BM25 ile kosinüs gibi
    kıyaslanamaz ölçekleri normalleştirme varsayımı yapmadan birleştirir.
    """
    agirliklar = agirliklar or [1.0] * len(siralamalar)
    toplam: dict[int, float] = {}
    # strict=True: ağırlık sayısı sıralama sayısıyla eşleşmezse sessizce bir
    # sıralamayı düşürmek yerine hata versin — eksik ağırlık, o erişim
    # katmanının fark edilmeden birleşimden çıkması demek.
    for sira_listesi, agirlik in zip(siralamalar, agirliklar, strict=True):
        for konum, belge in enumerate(sira_listesi):
            toplam[belge] = toplam.get(belge, 0.0) + agirlik / (k + konum + 1)
    return toplam


class OrnekIndeksi:
    """Referans örnekler üzerinde hibrit erişim indeksi."""

    def __init__(
        self,
        ornekler: list[Ornek],
        gomme: np.ndarray | None = None,
        gomme_modeli: str = "",
    ):
        # Kopya şart: `ekle`/`sil` bu listeyi yerinde değiştiriyor. Çağıranın
        # listesini paylaşmak, indeksten bir örnek silindiğinde çağıranın
        # elindeki listeyi de sessizce kısaltıyordu.
        self.ornekler = list(ornekler)
        self.gomme = gomme
        self.gomme_modeli = gomme_modeli
        self._bm25 = BM25([o.indeks_metni() for o in ornekler])

    def __len__(self) -> int:
        return len(self.ornekler)

    @property
    def anlamsal_hazir(self) -> bool:
        return self.gomme is not None and len(self.gomme) == len(self.ornekler)

    # --- kurulum ---

    @classmethod
    def kur(cls, ornekler: list[Ornek], gomlemci: Gomlemci | None = None) -> OrnekIndeksi:
        gomme = None
        model_adi = ""
        if gomlemci is not None and ornekler:
            gomme = np.asarray(
                gomlemci.gom([o.indeks_metni() for o in ornekler]), dtype=np.float32
            )
            gomme /= np.clip(np.linalg.norm(gomme, axis=1, keepdims=True), 1e-9, None)
            model_adi = getattr(gomlemci, "model_adi", "")
        return cls(ornekler, gomme, model_adi)

    # --- artımlı güncelleme ---

    def _gomlemci_uyumlu_mu(self, gomlemci: Gomlemci | None) -> bool:
        """Verilen gömlemci bu indeksteki vektörlerle aynı uzayda mı?

        Model değiştiyse yeni vektör eskilerle kıyaslanamaz; kosinüs yine bir
        sayı üretir ama anlamı yoktur. Bu durumda artımlı yol reddedilir ve
        çağıran tam yeniden kurulum yapar.
        """
        if gomlemci is None:
            return self.gomme is None
        if self.gomme is None:
            # Henüz hiç vektör yok: boş indekse ilk ekleme uyumludur.
            return not self.ornekler
        return getattr(gomlemci, "model_adi", "") == self.gomme_modeli

    def _vektor(self, ornek: Ornek, gomlemci: Gomlemci) -> np.ndarray:
        vektor = np.asarray(gomlemci.gom([ornek.indeks_metni()]), dtype=np.float32)
        return vektor / np.clip(np.linalg.norm(vektor, axis=1, keepdims=True), 1e-9, None)

    def ekle(self, ornek: Ornek, gomlemci: Gomlemci | None = None) -> bool:
        """Tek örneği indekse katar. Uyumsuz gömlemcide False döner.

        Kazanç gömme tarafında: tam yeniden kurulum koleksiyondaki HER örneği
        yeniden gömdürüyor. Birkaç yüz örnekte bu, her ekleme için dakikalara
        çıkan bir maliyet.
        """
        if not self._gomlemci_uyumlu_mu(gomlemci):
            return False
        self.ornekler.append(ornek)
        self._bm25.ekle(ornek.indeks_metni())
        if gomlemci is not None:
            yeni = self._vektor(ornek, gomlemci)
            self.gomme = yeni if self.gomme is None else np.vstack([self.gomme, yeni])
            self.gomme_modeli = getattr(gomlemci, "model_adi", "")
        return True

    def degistir(self, ornek: Ornek, gomlemci: Gomlemci | None = None) -> bool:
        """Aynı id'li örneği yerinde günceller."""
        sira = self._sira_bul(ornek.id)
        if sira is None or not self._gomlemci_uyumlu_mu(gomlemci):
            return False
        self.ornekler[sira] = ornek
        self._bm25.degistir(sira, ornek.indeks_metni())
        if gomlemci is not None and self.gomme is not None:
            self.gomme[sira] = self._vektor(ornek, gomlemci)[0]
        return True

    def sil(self, ornek_id: int | None) -> bool:
        sira = self._sira_bul(ornek_id)
        if sira is None:
            return False
        self.ornekler.pop(sira)
        self._bm25.sil(sira)
        if self.gomme is not None:
            self.gomme = np.delete(self.gomme, sira, axis=0)
        return True

    def icerir(self, ornek_id: int | None) -> bool:
        """Bu id indekste var mı?

        "Ekleme mi güncelleme mi" kararı buna sorulmalı. Örnek SAYISINI
        karşılaştırmak yakın ama yanlış bir vekil: indeks depodan bir örnek
        geride kaldığında iki yol çakışıp güncellemeyi ekleme sanıyor ve
        aynı örnek indekse ikinci kez giriyordu.
        """
        return self._sira_bul(ornek_id) is not None

    def _sira_bul(self, ornek_id: int | None) -> int | None:
        if ornek_id is None:
            return None
        for sira, mevcut in enumerate(self.ornekler):
            if mevcut.id == ornek_id:
                return sira
        return None

    # --- kalıcılık ---

    def kaydet(self, dizin: str | Path) -> None:
        dizin = Path(dizin)
        dizin.mkdir(parents=True, exist_ok=True)
        (dizin / "ornekler.jsonl").write_text(
            "\n".join(json.dumps(o.sozluk(), ensure_ascii=False) for o in self.ornekler),
            encoding="utf-8",
        )
        if self.gomme is not None:
            np.save(dizin / "gomme.npy", self.gomme)
        elif (dizin / "gomme.npy").exists():
            (dizin / "gomme.npy").unlink()
        (dizin / "indeks.json").write_text(
            json.dumps(
                {"gomme_modeli": self.gomme_modeli, "ornek": len(self.ornekler)},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

    @classmethod
    def yukle(cls, dizin: str | Path) -> OrnekIndeksi:
        dizin = Path(dizin)
        satirlar = (dizin / "ornekler.jsonl").read_text(encoding="utf-8").splitlines()
        ornekler = [Ornek(**json.loads(s)) for s in satirlar if s.strip()]
        gomme = None
        gomme_yolu = dizin / "gomme.npy"
        if gomme_yolu.exists():
            yuklenen = np.load(gomme_yolu)
            # Örnek sayısı ile gömme satır sayısı uyuşmuyorsa indeks bayattır;
            # sessizce yanlış örneğe atıf yapmaktansa anlamsal katmanı devre dışı bırak.
            if len(yuklenen) == len(ornekler):
                gomme = yuklenen
        bilgi = {}
        bilgi_yolu = dizin / "indeks.json"
        if bilgi_yolu.exists():
            bilgi = json.loads(bilgi_yolu.read_text(encoding="utf-8"))
        return cls(ornekler, gomme, str(bilgi.get("gomme_modeli", "")))

    @classmethod
    def hazir_mi(cls, dizin: str | Path) -> bool:
        yol = Path(dizin) / "ornekler.jsonl"
        return yol.is_file() and yol.stat().st_size > 0

    # --- erişim ---

    def ara(
        self,
        sorgu: str,
        gomlemci: Gomlemci | None = None,
        k: int = 10,
    ) -> list[tuple[int, float]]:
        """Sorguya en uygun örneklerin (indeks, birleşik skor) listesi."""
        if not self.ornekler:
            return []
        aday_sayisi = min(len(self.ornekler), max(k * 4, 20))

        bm25_puanlari = self._bm25.puanla(sorgu)
        bm25_sirasi = [
            int(i) for i in np.argsort(-bm25_puanlari)[:aday_sayisi] if bm25_puanlari[i] > 0
        ]
        siralamalar = [bm25_sirasi]
        agirliklar = [1.0]

        if gomlemci is not None and self.anlamsal_hazir:
            q = np.asarray(gomlemci.gom([sorgu], sorgu=True), dtype=np.float32)
            if q.shape[-1] == self.gomme.shape[-1]:  # type: ignore[union-attr]
                benzerlik = kosinus(q, self.gomme)[0]  # type: ignore[arg-type]
                # Mutlak kosinüs tabanı ŞART: RRF sıra tabanlı olduğu için,
                # süzülmeden eklenen bir aday listesi hiç ilgisiz belgeleri de
                # (kosinüs ≈ -1) en iyi skorun %97'sine taşır. O zaman eşik hiçbir
                # şeyi elemez ve sistem her soruya "kanıt" bulmuş görünür —
                # kanıtsızlık cezası da hiç uygulanmaz.
                anlamsal_sira = [
                    int(i)
                    for i in np.argsort(-benzerlik)[:aday_sayisi]
                    if float(benzerlik[i]) >= ANLAMSAL_TABAN
                ]
                if anlamsal_sira:
                    siralamalar.append(anlamsal_sira)
                    # Anlamsal katman biraz daha ağır: eş anlamlı terimleri yakalar.
                    agirliklar.append(1.2)

        birlesik = rrf_birlestir(siralamalar, agirliklar=agirliklar)
        sirali = sorted(birlesik.items(), key=lambda x: (-x[1], x[0]))
        return [(indeks, float(skor)) for indeks, skor in sirali[:k]]
