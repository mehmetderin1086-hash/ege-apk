"""Ders kitabı pasajları üzerinde erişim indeksi ve getirme.

`indeks.OrnekIndeksi`den ayrı bir sınıf, çünkü iki koleksiyon farklı şeyler
için aranıyor: örnek indeksi "bu soruya BENZER soru" arar, pasaj indeksi
"bu sorunun konusunu AÇIKLAYAN metin" arar. Sorgu genişletme, tür/konu
uyumu ve kalite kapısı gibi örneklere özgü kademeler burada yok; buna
karşılık pasajda başlık ayrı ağırlıkla indeksleniyor.

Yeniden kullanılan parçalar (`BM25`, `kosinus`, `rrf_birlestir`) bilinçli
olarak paylaşılıyor: iki erişim yolunun sıralama davranışı ayrışırsa
birinde düzeltilen bir hata ötekinde yaşamayı sürdürür.
"""

from __future__ import annotations

import numpy as np

from ..gomme import Gomlemci, kosinus
from ..modeller import Pasaj
from .indeks import ANLAMSAL_TABAN, BM25, rrf_birlestir

# Pasaj kanıtı isteme girmeden önce geçmesi gereken asgari birleşik skor oranı.
# Örnek getirmedeki eşikten daha SEÇİCİ: alakasız bir ders kitabı paragrafı,
# alakasız bir örnek çözümden daha zararlı — model onu olgu diye aktarır.
ESIK_ORANI = 0.55

# MUTLAK alaka tabanı. Göreli oran tek başına yetmez: en iyi sonucun oranı
# tanımı gereği 1,0 olduğundan, indekste konuyla ilgili HİÇBİR pasaj yokken
# bile birinci sıradaki metin eşiği geçer. BM25'te "bir", "hücre" gibi tek bir
# ortak sözcük sıfırdan büyük skor üretmeye yetiyor; sonuç, ilgisiz bir olgunun
# `[DERS KİTABI]` etiketiyle ve "kendi bildiğinle çelişirse kitabı esas al"
# talimatıyla modele dayatılması olurdu — sessizce yanlış cevap üreten yol.
#
# Taban, sorgu ile pasaj arasındaki ANLAMSAL benzerliğe uygulanıyor (gömlemci
# varken); yalnız BM25 varken terim örtüşmesi oranı kullanılıyor.
ASGARI_ANLAMSAL_BENZERLIK = 0.45
ASGARI_TERIM_ORTUSMESI = 0.12


class PasajIndeksi:
    """Pasajlar üzerinde hibrit (BM25 + gömme) erişim indeksi."""

    def __init__(
        self,
        pasajlar: list[Pasaj],
        gomme: np.ndarray | None = None,
        gomme_modeli: str = "",
    ):
        self.pasajlar = list(pasajlar)
        self.gomme = gomme
        self.gomme_modeli = gomme_modeli
        self._bm25 = BM25([p.indeks_metni() for p in self.pasajlar])

    def __len__(self) -> int:
        return len(self.pasajlar)

    @property
    def anlamsal_hazir(self) -> bool:
        return self.gomme is not None and len(self.gomme) == len(self.pasajlar)

    @classmethod
    def kur(
        cls, pasajlar: list[Pasaj], gomlemci: Gomlemci | None = None
    ) -> PasajIndeksi:
        gomme = None
        model_adi = ""
        if gomlemci is not None and pasajlar:
            gomme = np.asarray(
                gomlemci.gom([p.indeks_metni() for p in pasajlar]), dtype=np.float32
            )
            gomme /= np.clip(np.linalg.norm(gomme, axis=1, keepdims=True), 1e-9, None)
            model_adi = getattr(gomlemci, "model_adi", "")
        return cls(pasajlar, gomme, model_adi)

    def ara(
        self, sorgu: str, gomlemci: Gomlemci | None = None, k: int = 5
    ) -> list[tuple[int, float]]:
        if not self.pasajlar:
            return []
        aday_sayisi = min(len(self.pasajlar), max(k * 4, 20))

        bm25_puanlari = self._bm25.puanla(sorgu)
        siralamalar = [
            [
                int(i)
                for i in np.argsort(-bm25_puanlari)[:aday_sayisi]
                if bm25_puanlari[i] > 0
            ]
        ]
        agirliklar = [1.0]

        if gomlemci is not None and self.anlamsal_hazir:
            q = np.asarray(gomlemci.gom([sorgu], sorgu=True), dtype=np.float32)
            if q.shape[-1] == self.gomme.shape[-1]:  # type: ignore[union-attr]
                benzerlik = kosinus(q, self.gomme)[0]  # type: ignore[arg-type]
                anlamsal_sira = [
                    int(i)
                    for i in np.argsort(-benzerlik)[:aday_sayisi]
                    if float(benzerlik[i]) >= ANLAMSAL_TABAN
                ]
                if anlamsal_sira:
                    siralamalar.append(anlamsal_sira)
                    # Kavram metninde anlamsal katman BM25'ten daha belirleyici:
                    # soru "ATP nerede üretilir" derken kitap "oksidatif
                    # fosforilasyon" yazıyor ve ortak terim çıkmıyor.
                    agirliklar.append(1.4)

        birlesik = rrf_birlestir(siralamalar, agirliklar=agirliklar)
        sirali = sorted(birlesik.items(), key=lambda x: (-x[1], x[0]))
        return [(indeks, float(skor)) for indeks, skor in sirali[:k]]

    def alakali_mi(
        self, sira: int, sorgu: str, gomlemci: Gomlemci | None = None
    ) -> bool:
        """Pasaj gerçekten sorguyla ilgili mi (mutlak taban denetimi).

        RRF sıralaması göreli: liste boşsa bile birinci sıra "en iyi"dir.
        Bu denetim, ilgisiz bir metnin ders kitabı otoritesiyle isteme
        girmesini engelliyor.
        """
        if not (0 <= sira < len(self.pasajlar)):
            return False
        if gomlemci is not None and self.anlamsal_hazir:
            q = np.asarray(gomlemci.gom([sorgu], sorgu=True), dtype=np.float32)
            if q.shape[-1] == self.gomme.shape[-1]:  # type: ignore[union-attr]
                benzerlik = float(kosinus(q, self.gomme)[0][sira])  # type: ignore[arg-type]
                return benzerlik >= ASGARI_ANLAMSAL_BENZERLIK
        # Gömlemci yoksa terim örtüşmesine düşülür: sorgudaki anlamlı
        # sözcüklerin kaçı pasajda geçiyor?
        from .indeks import terimler

        sorgu_terimleri = set(terimler(sorgu))
        if not sorgu_terimleri:
            return False
        pasaj_terimleri = set(terimler(self.pasajlar[sira].indeks_metni()))
        ortusme = len(sorgu_terimleri & pasaj_terimleri) / len(sorgu_terimleri)
        return ortusme >= ASGARI_TERIM_ORTUSMESI


def benzer_pasajlar(
    indeks: PasajIndeksi | None,
    soru: str,
    *,
    gomlemci: Gomlemci | None = None,
    k: int = 2,
    azami_karakter: int = 900,
) -> list[Pasaj]:
    """Soruyla ilgili ders kitabı pasajları; ilgisiz sonuç dönmez.

    `k` küçük tutuluyor (varsayılan 2): pasajlar örnek çözümlerden uzun ve
    bağlamı şişirmek modeli token sınırında kestiriyor — kapsamayı düşüren
    ana mekanizma tam olarak buydu.
    """
    # `k <= 0` "kaynak metni hiç kullanma" demek ve A/B ölçümünün kontrol
    # kolu bu. Denetim döngü İÇİNDE yapılırsa ilk pasaj listeye girdikten
    # sonra kırılır ve kapatma kolu sessizce çalışmaz.
    if indeks is None or not len(indeks) or k <= 0:
        return []
    sonuclar = indeks.ara(soru, gomlemci, k=max(k * 2, 4))
    if not sonuclar:
        return []
    en_iyi = max(sonuclar[0][1], 1e-9)

    secilenler: list[Pasaj] = []
    for sira, skor in sonuclar:
        if skor / en_iyi < ESIK_ORANI:
            continue
        if not indeks.alakali_mi(sira, soru, gomlemci):
            continue
        pasaj = indeks.pasajlar[sira]
        metin = pasaj.metin.strip()
        if len(metin) > azami_karakter:
            # Cümle sınırında kırp: yarım cümlelik bir "olgu" modele eksik
            # bilgiyi tam bilgi gibi gösterir.
            kesim = metin.rfind(".", 0, azami_karakter)
            metin = metin[: kesim + 1] if kesim > azami_karakter // 2 else (
                metin[:azami_karakter] + "…"
            )
        secilenler.append(
            Pasaj(
                metin=metin,
                kaynak=pasaj.kaynak,
                baslik=pasaj.baslik,
                sayfa=pasaj.sayfa,
                konu=pasaj.konu,
                id=pasaj.id,
            )
        )
        if len(secilenler) >= k:
            break
    return secilenler
