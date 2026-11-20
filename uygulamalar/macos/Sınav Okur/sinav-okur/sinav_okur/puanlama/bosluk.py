"""Boşluk doldurma puanlama: cevap anahtarındaki yazımlarla toleranslı eşleme.

HTR çıktısı gürültülü olabileceğinden iki katmanlı karşılaştırma yapılır:
kanonik biçim (küçük harf, noktalamasız) ve aksansız biçim (ş→s, ğ→g...).
Aksansız eşleşme küçük bir cezayla değerlendirilir ki "hucre" ile "hücre"
eşleşsin ama tam yazım her zaman öne geçsin.
"""

from __future__ import annotations

import re

from rapidfuzz import fuzz

from ..metin import aksansiz, eslesme_bicimi
from ..modeller import PuanSonucu, Soru, SoruTipi
from .ayarlar import PuanlamaAyar

_AKSANSIZ_CEZA = 4.0  # aksansız eşleşme puanından düşülür
# İki gerçek terime bu marjdan yakın bir yazım, düzeltilebilir bir hata değil
# çözülmemiş bir belirsizliktir (terim_sozlugu.ASGARI_MARJ ile aynı gerekçe).
KARAR_MARJI = 6.0


def en_iyi_eslesme(cevap: str, kabuller: list[str]) -> tuple[float, str]:
    """Cevabın kabul listesindeki en iyi benzerlik skoru (0-100) ve eşleşen yazım."""
    c_norm, c_aksansiz = eslesme_bicimi(cevap), aksansiz(cevap)
    en_iyi, eslesen = 0.0, ""
    for kabul in kabuller:
        skor = fuzz.ratio(c_norm, eslesme_bicimi(kabul))
        aksansiz_skor = fuzz.ratio(c_aksansiz, aksansiz(kabul)) - _AKSANSIZ_CEZA
        adaylar = max(skor, aksansiz_skor)
        if adaylar > en_iyi:
            en_iyi, eslesen = adaylar, kabul
    return en_iyi, eslesen


_PARCA_AYRACI = re.compile(r"[;\n,]+")
# Soru metnindeki boşluk işaretleri: "___", "....", "(.....)" gibi.
_BOSLUK_ISARETI = re.compile(r"_{2,}|\.{3,}")


def bosluk_sayisi(soru_metni: str) -> int:
    """Soru metnindeki boşluk işareti sayısı (0 = işaret bulunamadı)."""
    return len(_BOSLUK_ISARETI.findall(soru_metni or ""))


def cevabi_parcala(metin: str) -> list[str]:
    """Çok boşluklu cevabı parçalara ayırır (noktalı virgül, virgül, satır)."""
    return [p.strip() for p in _PARCA_AYRACI.split(metin) if p.strip()]


def cok_bosluk_puanla(
    cevap_metni: str, soru: Soru, ayar: PuanlamaAyar
) -> PuanSonucu:
    """Her boşluğu ayrı eşleştirip kısmi puan verir.

    Anahtardaki her doğru cevap bir boşluğa karşılık gelir. Bir öğrenci
    parçası yalnız bir boşluğu doldurabilir; en iyi skorlu eşleşmeden
    başlanarak açgözlü yerleştirilir. Kısmi sonuç her zaman incelemeye düşer.
    """
    beklenenler = list(soru.anahtar.dogru_cevaplar)
    parcalar = cevabi_parcala(cevap_metni)
    adaylar: list[tuple[float, int, int, str]] = []
    for pi, parca in enumerate(parcalar):
        for bi, beklenen in enumerate(beklenenler):
            skor, _eslesen = en_iyi_eslesme(parca, [beklenen])
            adaylar.append((skor, bi, pi, parca))
    adaylar.sort(key=lambda x: -x[0])
    dolan: dict[int, tuple[str, float]] = {}
    kullanilan_parca: set[int] = set()
    for skor, bi, pi, parca in adaylar:
        if skor < ayar.bosluk_kismi_esik:
            break
        if bi in dolan or pi in kullanilan_parca:
            continue
        dolan[bi] = (parca, skor)
        kullanilan_parca.add(pi)
    # Kısmi eşik (80) tam eşikten (88) daha gevşektir; sınırda kalan bir
    # yazımın kutuyu otomatik kesinleştirmesine izin verilmez.
    sinirda = any(skor < ayar.bosluk_tam_esik for _p, skor in dolan.values())
    dogru = len(dolan)
    toplam = len(beklenenler)
    puan = round(soru.puan * dogru / toplam * 2) / 2
    eksikler = [b for i, b in enumerate(beklenenler) if i not in dolan]
    aciklama = f"{dogru}/{toplam} boşluk doğru; {puan:g}/{soru.puan:g} puan."
    detaylar = [aciklama]
    if eksikler:
        detaylar.append("Eksik/yanlış boşluklar: " + ", ".join(eksikler[:5]))
    tam = dogru == toplam and not sinirda
    if sinirda:
        detaylar.append(
            "Bazı boşluklar sınırda eşleşti; yazımları görüntüyle doğrulayın."
        )
    guven = 0.9 if tam else 0.55
    return PuanSonucu(
        puan,
        soru.puan,
        guven,
        detaylar,
        # Kısmi sonuç öğretmen gözü ister: hangi boşluğun hangi parçaya
        # denk geldiği yazım sırasına göre değişebilir.
        incele=not tam,
        risk=0.1 if tam else 0.45,
        kararlar=[
            {
                "tur": "cok_bosluk",
                "beklenen": beklenenler,
                "dolan": {beklenenler[i]: d[0] for i, d in dolan.items()},
                "puan": puan,
            }
        ],
        aciklama=aciklama,
        puanlama_guveni=guven,
    )


def _rakip_terim(
    cevap: str,
    eslesen: str,
    skor: float,
    bilinen_terimler: set[str] | None,
    marj: float = KARAR_MARJI,
) -> str | None:
    """Cevabın eşit yakın olduğu BAŞKA bir alan terimi var mı?

    ``terim_sozlugu``'nün yazım düzeltmesindeki marj kuralının puanlamadaki
    karşılığı: iki gerçek terime aynı yakınlıktaki bir yazım, düzeltilebilir
    bir hata değil, çözülmemiş bir belirsizliktir.
    """
    if not bilinen_terimler:
        return None
    hedef = eslesme_bicimi(cevap)
    eslesen_bicim = eslesme_bicimi(eslesen)
    en_iyi_rakip, en_iyi_skor = None, 0.0
    for terim in bilinen_terimler:
        bicim = eslesme_bicimi(terim)
        if not bicim or bicim == eslesen_bicim:
            continue
        aday = fuzz.ratio(hedef, bicim)
        if aday > en_iyi_skor:
            en_iyi_rakip, en_iyi_skor = terim, aday
    if en_iyi_rakip is not None and en_iyi_skor >= skor - marj:
        return en_iyi_rakip
    return None


def bosluk_puanla(
    cevap_metni: str,
    soru: Soru,
    ayar: PuanlamaAyar | None = None,
    ogrenilmis_kabuller: list[str] | None = None,
    bilinen_terimler: set[str] | None = None,
) -> PuanSonucu:
    # Öğretmenin katı/dengeli/esnek tercihi boşluk eşiklerine de uygulanır
    # (rubrik yolu bunu zaten yapıyordu; arayüz ayarı geneldi ama boşlukta
    # hiçbir şey değişmiyordu).
    ayar = (ayar or PuanlamaAyar()).profil(
        soru.esneklik or soru.anahtar.esneklik
    )
    if not cevap_metni.strip():
        return PuanSonucu(0.0, soru.puan, 1.0, ["Cevap boş"], incele=False)

    # Anahtardaki birden çok doğru cevap "aynı boşluğun kabul edilen
    # yazımları" mı yoksa "ayrı boşluklar" mı? Bu ayrımı anahtar tek başına
    # taşımıyor; en güvenilir kanıt SORU METNİNDEKİ boşluk işaretleridir.
    # İşaret sayısı anahtarla örtüşüyorsa çok boşluk kesindir — öğrenci tek
    # parça yazmış olsa bile eksik boşluk puan kaybettirir.
    if soru.tip == SoruTipi.BOSLUK_DOLDURMA and len(soru.anahtar.dogru_cevaplar) > 1:
        isaret = bosluk_sayisi(soru.metin)
        # Cevabın TAMAMI anahtardaki bir yazıma oturuyorsa bu tek boşluktur.
        # Bu kapı olmadan ondalık virgüllü ("0,5 mol") ya da açıklamalı
        # ("mitokondri, yani enerji merkezi") doğru cevaplar parçalanıp
        # yarım puan alıyordu.
        tam_skor, _e = en_iyi_eslesme(cevap_metni, soru.anahtar.dogru_cevaplar)
        if isaret == len(soru.anahtar.dogru_cevaplar):
            return cok_bosluk_puanla(cevap_metni, soru, ayar)
        # İşaret yoksa (eski sınavlar, serbest yazılmış sorular) cevabın
        # çok parçalı olması ikincil kanıttır.
        if (
            isaret == 0
            and tam_skor < ayar.bosluk_tam_esik
            and len(cevabi_parcala(cevap_metni)) > 1
        ):
            return cok_bosluk_puanla(cevap_metni, soru, ayar)

    kabuller = list(soru.anahtar.dogru_cevaplar)
    ogrenilmis = [y for y in (ogrenilmis_kabuller or []) if y]
    skor, eslesen = en_iyi_eslesme(cevap_metni, kabuller)
    if skor < ayar.bosluk_tam_esik and ogrenilmis:
        # Öğretmenin geçmişte tam puan verdiği yazım: puan verilir ama
        # otomatik kabul edilmez, öğretmen onayına düşer.
        o_skor, o_eslesen = en_iyi_eslesme(cevap_metni, ogrenilmis)
        if o_skor >= ayar.bosluk_tam_esik:
            return PuanSonucu(
                soru.puan,
                soru.puan,
                0.55,
                [
                    f"'{cevap_metni.strip()}' ≈ öğrenilmiş kabul yazımı "
                    f"'{o_eslesen}' (skor {o_skor:.0f}); anahtarda yok, "
                    "öğretmen onayı bekliyor."
                ],
                incele=True,
                risk=0.45,
                kararlar=[
                    {
                        "tur": "ogrenilmis_kabul",
                        "yazim": o_eslesen,
                        "skor": round(o_skor, 1),
                    }
                ],
                puanlama_guveni=0.55,
            )

    if skor >= ayar.bosluk_tam_esik:
        guven = min(1.0, 0.7 + 0.3 * (skor - ayar.bosluk_tam_esik) / (100 - ayar.bosluk_tam_esik + 1e-9))
        return PuanSonucu(
            soru.puan, soru.puan, guven,
            [f"'{cevap_metni.strip()}' ≈ '{eslesen}' (skor {skor:.0f})"],
        )
    if skor >= ayar.bosluk_supheli_esik:
        rakip = _rakip_terim(cevap_metni, eslesen, skor, bilinen_terimler)
        if rakip is not None:
            # Cevap iki gerçek terime eşit yakın (ölçüldü: "miyoz" hem
            # "mitoz"a hem "mayoz"a 80 skorla eşleşiyor). Hangisini kastettiği
            # belirsizken tam puan vermek yazım hatasını değil, yanlış cevabı
            # ödüllendirme riski taşır.
            return PuanSonucu(
                0.0, soru.puan, 0.4,
                [
                    f"Kararsız eşleşme: '{cevap_metni.strip()}' hem "
                    f"'{eslesen}' hem '{rakip}' terimine yakın "
                    f"(skor {skor:.0f}) — öğretmen karar versin."
                ],
                incele=True,
                risk=0.6,
                kararlar=[
                    {
                        "tur": "bosluk",
                        "karar": "kararsiz_terim",
                        "eslesen": eslesen,
                        "rakip": rakip,
                        "skor": round(skor, 1),
                    }
                ],
                puanlama_guveni=0.4,
            )
        return PuanSonucu(
            soru.puan, soru.puan, 0.5,
            [f"Sınırda eşleşme: '{cevap_metni.strip()}' ~ '{eslesen}' (skor {skor:.0f}) — geçici tam puan"],
            incele=True,
            kararlar=[
                {
                    "tur": "bosluk",
                    "karar": "sinirda_esleme",
                    "eslesen": eslesen,
                    "skor": round(skor, 1),
                }
            ],
        )
    if skor >= ayar.bosluk_ret_esik:
        return PuanSonucu(
            0.0, soru.puan, 0.5,
            [f"Zayıf eşleşme: '{cevap_metni.strip()}' vs '{eslesen}' (skor {skor:.0f}) — 0 verildi"],
            incele=True,
        )
    # Güven, ret eşiğinden uzaklaştıkça 0.5'ten 1.0'a çıkar (eşiğin hemen
    # altında ~0.5 → süreksizlik yok: sınırdaki cevaplar da incele bandına yakın).
    guven = min(1.0, 0.5 + 0.5 * (ayar.bosluk_ret_esik - skor) / ayar.bosluk_ret_esik)
    return PuanSonucu(
        0.0, soru.puan, guven, [f"Eşleşme yok (en iyi skor {skor:.0f})"],
        incele=guven < ayar.incele_guven_esigi,
    )
