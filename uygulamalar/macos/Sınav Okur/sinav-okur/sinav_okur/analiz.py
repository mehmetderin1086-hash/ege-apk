"""Sınav analitiği, tutarlılık denetimi ve öğretmen kalibrasyonu."""

from __future__ import annotations

import json
import math
import statistics
from collections import Counter, defaultdict

from rapidfuzz import fuzz

from .depo import Depo
from .modeller import Sinav


# Benzer cevap eşiği; hem tutarsızlık tespiti hem toplu puanlama tezgâhı
# aynı eşiği kullanır ki öğretmenin gördüğü küme ile uyarı örtüşsün.
BENZERLIK_ESIGI = 86
ASGARI_KIYAS_UZUNLUGU = 8


def kutu_metni(satir) -> str:
    """Kutunun geçerli metni: öğretmen düzeltmesi varsa o, yoksa OCR çıktısı."""
    return str(satir["duzeltilmis_metin"] or satir["taninan_metin"] or "").strip()


def tutarsiz_ciftler(
    satirlar: list, soru_puani: float, *, esik: int = BENZERLIK_ESIGI
) -> list[dict]:
    """Benzer yazılmış ama belirgin farklı puan almış cevap çiftleri."""
    ciftler: list[dict] = []
    for i, a in enumerate(satirlar):
        a_metin = kutu_metni(a)
        if len(a_metin) < ASGARI_KIYAS_UZUNLUGU:
            continue
        for b in satirlar[i + 1:]:
            b_metin = kutu_metni(b)
            benzerlik = fuzz.token_set_ratio(a_metin, b_metin)
            fark = abs(float(a["son_puan"] or 0) - float(b["son_puan"] or 0))
            if benzerlik >= esik and fark >= max(2.0, soru_puani * 0.20):
                ciftler.append(
                    {
                        "kutu_a": a["id"],
                        "kutu_b": b["id"],
                        "kagit_a": a["kagit_id"],
                        "kagit_b": b["kagit_id"],
                        "benzerlik": round(benzerlik, 1),
                        "puan_farki": round(fark, 1),
                    }
                )
    return ciftler


def benzer_cevap_kumeleri(
    satirlar: list,
    *,
    esik: int = BENZERLIK_ESIGI,
    asgari_uzunluk: int = ASGARI_KIYAS_UZUNLUGU,
) -> list[dict]:
    """Aynı sorunun cevaplarını yazım benzerliğine göre kümeler.

    Kısa cevaplar (``asgari_uzunluk`` altı) kümelenmez — "evet"/"hayır"
    gibi metinler farklı soruları aynı torbaya atardı. Boş cevaplar
    kendi kümelerinde kalır. Kümeler üye sayısına göre azalan sıralanır.
    """
    kumeler: list[dict] = []
    for satir in satirlar:
        metin = kutu_metni(satir)
        yerlesti = False
        if metin and len(metin) >= asgari_uzunluk:
            for kume in kumeler:
                if not kume["temsilci"]:
                    continue
                if fuzz.token_set_ratio(metin, kume["temsilci"]) >= esik:
                    kume["uyeler"].append(satir)
                    yerlesti = True
                    break
        if not yerlesti:
            kumeler.append({"temsilci": metin, "uyeler": [satir]})
    for kume in kumeler:
        puanlar = [float(u["son_puan"] or 0) for u in kume["uyeler"]]
        kume["adet"] = len(kume["uyeler"])
        kume["puanlar"] = puanlar
        kume["ortak_puan"] = (
            puanlar[0] if len(set(puanlar)) == 1 and puanlar else None
        )
        kume["bekleyen"] = sum(1 for u in kume["uyeler"] if u["incele"])
    kumeler.sort(key=lambda k: (-k["adet"], k["temsilci"]))
    return kumeler


def _yuzdelik(degerler: list[float], q: float) -> float | None:
    if not degerler:
        return None
    sirali = sorted(degerler)
    konum = (len(sirali) - 1) * q
    alt = math.floor(konum)
    ust = math.ceil(konum)
    if alt == ust:
        return sirali[alt]
    return sirali[alt] * (ust - konum) + sirali[ust] * (konum - alt)


def sinav_analizi(depo: Depo, sinav: Sinav, referans_pasaj_bul=None) -> dict:
    """Sınav analitiği. ``referans_pasaj_bul`` verilirse (kavram → pasaj metni)
    zayıf konular ders kitabı kaynağıyla eşlenir; RAG hazır değilse atlanır."""
    kagitlar = depo.kagitlar(sinav.kimlik)
    cevaplar = depo.sinav_cevaplari(sinav.kimlik)
    duzeltmeler = depo.duzeltme_ornekleri(sinav.kimlik)
    puan_yuzdeleri = []
    kagit_yuzdesi: dict[int, float] = {}
    for kagit in kagitlar:
        toplam, azami = depo.kagit_toplam(kagit["id"])
        if azami:
            yuzde = 100 * toplam / azami
            puan_yuzdeleri.append(yuzde)
            kagit_yuzdesi[kagit["id"]] = yuzde

    soruya_gore: dict[int, list] = defaultdict(list)
    for cevap in cevaplar:
        soruya_gore[int(cevap["soru_no"])].append(cevap)

    # Ayırt edicilik için üst/alt %27 kâğıt kümeleri (yeterli örneklemde).
    sirali_kagitlar = sorted(
        kagit_yuzdesi, key=lambda kid: kagit_yuzdesi[kid], reverse=True
    )
    ayirt_hazir = len(sirali_kagitlar) >= 10
    if ayirt_hazir:
        dilim = max(1, round(len(sirali_kagitlar) * 0.27))
        ust_grup = set(sirali_kagitlar[:dilim])
        alt_grup = set(sirali_kagitlar[-dilim:])
    else:
        ust_grup = alt_grup = set()

    itiraz_sayaci: Counter = Counter()
    for itiraz in depo.itirazlar(sinav.kimlik):
        if itiraz["soru_no"] is not None:
            itiraz_sayaci[int(itiraz["soru_no"])] += 1

    soru_analizleri = []
    tutarsizliklar = []
    kacirilan = Counter()
    for soru in sinav.sorular:
        satirlar = soruya_gore.get(soru.no, [])
        oranlar = [
            float(s["son_puan"] or 0) / max(1e-9, float(s["max_puan"] or soru.puan))
            for s in satirlar
        ]
        bekleyen = sum(int(s["incele"] or 0) for s in satirlar)
        elle = sum(
            1
            for s in satirlar
            if s["duzeltilmis_metin"] is not None
            or abs(float(s["son_puan"] or 0) - float(s["otomatik_puan"] or 0)) > 1e-6
        )
        for s in satirlar:
            try:
                kararlar = json.loads(s["kararlar_json"] or "[]")
            except (TypeError, json.JSONDecodeError):
                kararlar = []
            for karar in kararlar:
                if karar.get("tur") == "rubrik" and not float(karar.get("puan", 0)):
                    kacirilan[str(karar.get("olcut", ""))] += 1

        # Benzer cevaplara belirgin farklı puan verilmesini yakala.
        for cift in tutarsiz_ciftler(satirlar, soru.puan):
            tutarsizliklar.append({"soru_no": soru.no, **cift})
        ortalama = statistics.mean(oranlar) if oranlar else None
        sorunlu_anahtar = bool(
            len(oranlar) >= 5
            and ortalama is not None
            and ortalama < 0.25
            and elle / len(oranlar) >= 0.35
        )
        # Ayırt edicilik: üst %27 ile alt %27 grubun bu sorudaki başarı farkı.
        ayirt_edicilik = None
        if ayirt_hazir:
            def _grup_orani(grup: set) -> float | None:
                puanlar = [
                    float(s["son_puan"] or 0)
                    / max(1e-9, float(s["max_puan"] or soru.puan))
                    for s in satirlar
                    if s["kagit_id"] in grup
                ]
                return statistics.mean(puanlar) if puanlar else None

            ust_oran, alt_oran = _grup_orani(ust_grup), _grup_orani(alt_grup)
            if ust_oran is not None and alt_oran is not None:
                ayirt_edicilik = round(ust_oran - alt_oran, 3)
        soru_analizleri.append(
            {
                "no": soru.no,
                "metin": soru.metin,
                "cevap": len(satirlar),
                "ortalama_yuzde": round(100 * ortalama, 1) if ortalama is not None else None,
                "guclik": round(ortalama, 3) if ortalama is not None else None,
                "ayirt_edicilik": ayirt_edicilik,
                "bekleyen": bekleyen,
                "elle_duzeltme": elle,
                "anahtar_supheli": sorunlu_anahtar,
                # İtiraz oranı, anahtar_supheli sezgisinden güçlü bir
                # "anahtar bozuk" sinyalidir.
                "itiraz": itiraz_sayaci.get(soru.no, 0),
                # ASCII anahtar: `Soru.kazanımlar` alan adı ASCII dışı, Jinja
                # ve JSON tüketicilerinde sürpriz üretmesin.
                "kazanimlar": list(soru.kazanımlar),
            }
        )

    puan_farklari = [
        float(x["ogretmen_puani"] or 0) - float(x["otomatik_puan"] or 0)
        for x in duzeltmeler
        if x["ogretmen_puani"] is not None
    ]
    inceleme_kuyrugu = sorted(
        [
            {
                "kagit_id": k["id"],
                "ogrenci": (
                    f"{k['ogrenci_ad'] or ''} {k['ogrenci_soyad'] or ''}".strip()
                    or "İsimsiz öğrenci"
                ),
                "oncelik": round(float(k["inceleme_onceligi"] or 0), 3),
                "kimlik_guveni": round(float(k["kimlik_guveni"] or 0), 3),
            }
            for k in kagitlar
            if not k["onaylandi"]
        ],
        key=lambda x: (-x["oncelik"], x["kimlik_guveni"]),
    )
    # Puan dağılımı: 10'luk dilim histogramı.
    dagilim = [0] * 10
    for yuzde in puan_yuzdeleri:
        dilim_no = min(9, int(yuzde // 10))
        dagilim[dilim_no] += 1

    # Sınıf/şube karşılaştırması.
    sinif_gruplari: dict[str, list[float]] = defaultdict(list)
    sinif_bekleyen: dict[str, int] = defaultdict(int)
    for kagit in kagitlar:
        etiket = f"{kagit['sinif'] or '?'}{('/' + kagit['sube']) if kagit['sube'] else ''}"
        if kagit["id"] in kagit_yuzdesi:
            sinif_gruplari[etiket].append(kagit_yuzdesi[kagit["id"]])
        if not kagit["onaylandi"]:
            sinif_bekleyen[etiket] += 1
    sinif_karsilastirma = sorted(
        (
            {
                "sinif": etiket,
                "adet": len(yuzdeler),
                "ortalama": round(statistics.mean(yuzdeler), 1) if yuzdeler else None,
                "bekleyen": sinif_bekleyen.get(etiket, 0),
            }
            for etiket, yuzdeler in sinif_gruplari.items()
        ),
        key=lambda x: (x["ortalama"] is None, -(x["ortalama"] or 0)),
    )

    # Zayıf konular: en çok kaçırılan kavramlar + (varsa) ders kitabı kaynağı.
    zayif_konular = []
    for ad, adet in kacirilan.most_common(5):
        if not ad:
            continue
        kayit = {"kavram": ad, "adet": adet, "kaynak": None}
        if referans_pasaj_bul is not None:
            try:
                kayit["kaynak"] = referans_pasaj_bul(ad)
            except Exception:
                kayit["kaynak"] = None
        zayif_konular.append(kayit)

    return {
        "kagit_sayisi": len(kagitlar),
        "dagilim": dagilim,
        "sinif_karsilastirma": sinif_karsilastirma if len(sinif_karsilastirma) > 1 else [],
        "zayif_konular": zayif_konular,
        "ayirt_edicilik_hazir": ayirt_hazir,
        "ortalama": (
            round(statistics.mean(puan_yuzdeleri), 1)
            if puan_yuzdeleri else None
        ),
        "medyan": (
            round(statistics.median(puan_yuzdeleri), 1)
            if puan_yuzdeleri else None
        ),
        "alt_ceyrek": (
            round(_yuzdelik(puan_yuzdeleri, 0.25), 1)
            if puan_yuzdeleri else None
        ),
        "ust_ceyrek": (
            round(_yuzdelik(puan_yuzdeleri, 0.75), 1)
            if puan_yuzdeleri else None
        ),
        "sorular": soru_analizleri,
        "tutarsizliklar": tutarsizliklar[:50],
        "kacirilan_kavramlar": [
            {"kavram": ad, "adet": adet}
            for ad, adet in kacirilan.most_common(12)
            if ad
        ],
        "ogretmen_duzeltme_sayisi": len(duzeltmeler),
        "ogretmen_esneklik_farki": (
            round(statistics.mean(puan_farklari), 2)
            if puan_farklari else 0.0
        ),
        "inceleme_kuyrugu": inceleme_kuyrugu,
        "psikometri": _psikometri_ekle(depo, sinav, duzeltmeler, soru_analizleri),
    }


def _psikometri_ekle(depo, sinav, duzeltmeler, soru_analizleri) -> dict:
    """Güvenilirlik + madde korelasyonu; soru satırlarına r_pbis işler.

    Negatif madde-toplam korelasyonu güçlü bir "anahtar hatalı olabilir"
    sinyalidir; mevcut ``anahtar_supheli`` bayrağına OR'lanır.
    """
    from .psikometri import sinav_psikometrisi

    try:
        sonuc = sinav_psikometrisi(depo, sinav, [dict(d) for d in duzeltmeler])
    except (KeyError, ValueError, TypeError, statistics.StatisticsError):
        return {}
    korelasyonlar = sonuc.get("madde_korelasyonu") or {}
    for satir in soru_analizleri:
        # Soru analizi satırlarında alan adı "no" (şablon da onu kullanıyor).
        kayit = korelasyonlar.get(satir.get("no"))
        if not kayit:
            continue
        satir["r_pbis"] = kayit.get("deger")
        satir["r_pbis_band"] = kayit.get("band")
        if kayit.get("band") == "anahtar_supheli":
            satir["anahtar_supheli"] = True
    return sonuc


def kazanim_analizi(depo: Depo, sinav: Sinav) -> dict:
    """Kazanım (konu) bazlı sınıf ve öğrenci başarısı.

    ``Soru.kazanımlar`` etiketleri anahtar düzenleyiciden girilir. Etiket
    yoksa boş sonuç döner — çağıranın ayrıca kontrol etmesi gerekmez.
    """
    kazanim_sorulari: dict[str, list] = defaultdict(list)
    for soru in sinav.sorular:
        for kazanim in soru.kazanımlar:
            ad = str(kazanim).strip()
            if ad:
                kazanim_sorulari[ad].append(soru)
    if not kazanim_sorulari:
        return {"kazanimlar": [], "ogrenciler": []}

    soruya_gore: dict[int, list] = defaultdict(list)
    kagida_gore: dict[int, list] = defaultdict(list)
    kagit_adlari: dict[int, str] = {}
    for satir in depo.sinav_cevaplari(sinav.kimlik):
        soruya_gore[int(satir["soru_no"])].append(satir)
        kagida_gore[int(satir["kagit_id"])].append(satir)
        kagit_adlari.setdefault(
            int(satir["kagit_id"]),
            " ".join(
                p
                for p in (
                    satir["ogrenci_ad"] or "",
                    satir["ogrenci_soyad"] or "",
                )
                if p
            )
            or f"Kâğıt #{satir['kagit_id']}",
        )

    def _oran(satirlar: list, varsayilan_puan: float) -> float | None:
        oranlar = [
            float(s["son_puan"] or 0)
            / max(1e-9, float(s["max_puan"] or varsayilan_puan))
            for s in satirlar
        ]
        return statistics.mean(oranlar) if oranlar else None

    kazanim_ozetleri = []
    for ad in sorted(kazanim_sorulari):
        sorular = kazanim_sorulari[ad]
        satirlar = [s for soru in sorular for s in soruya_gore.get(soru.no, [])]
        oran = _oran(satirlar, sorular[0].puan)
        kazanim_ozetleri.append(
            {
                "ad": ad,
                "soru_nolari": [s.no for s in sorular],
                "cevap_sayisi": len(satirlar),
                "basari_yuzdesi": round(100 * oran, 1) if oran is not None else None,
            }
        )
    kazanim_ozetleri.sort(
        key=lambda k: (k["basari_yuzdesi"] is None, k["basari_yuzdesi"] or 0)
    )

    ogrenciler = []
    for kagit_id, satirlar in kagida_gore.items():
        kagit_sorulari = {int(s["soru_no"]): s for s in satirlar}
        kazanim_oranlari = []
        for ad in sorted(kazanim_sorulari):
            ilgili = [
                kagit_sorulari[soru.no]
                for soru in kazanim_sorulari[ad]
                if soru.no in kagit_sorulari
            ]
            if not ilgili:
                continue
            oran = _oran(ilgili, kazanim_sorulari[ad][0].puan)
            if oran is not None:
                kazanim_oranlari.append((ad, oran))
        if not kazanim_oranlari:
            continue
        kazanim_oranlari.sort(key=lambda x: x[1])
        ogrenciler.append(
            {
                "kagit_id": kagit_id,
                "ogrenci": kagit_adlari.get(kagit_id, f"Kâğıt #{kagit_id}"),
                "kazanimlar": [
                    {"ad": ad, "basari_yuzdesi": round(100 * oran, 1)}
                    for ad, oran in kazanim_oranlari
                ],
                # %60 altı kazanımlar "tekrar edilecek" sayılır.
                "zayif": [ad for ad, oran in kazanim_oranlari if oran < 0.60],
            }
        )
    ogrenciler.sort(key=lambda o: o["ogrenci"])
    return {"kazanimlar": kazanim_ozetleri, "ogrenciler": ogrenciler}


def altin_test_metrikleri(tahminler: list[dict]) -> dict:
    """Kimliksiz altın test seti için puan MAE ve kabul edilebilir fark oranı."""
    farklar = [
        abs(float(x["tahmin_puan"]) - float(x["beklenen_puan"]))
        for x in tahminler
        if x.get("tahmin_puan") is not None and x.get("beklenen_puan") is not None
    ]
    if not farklar:
        return {"ornek": 0, "puan_mae": None, "iki_puan_icinde": None}
    sonuc = {
        "ornek": len(farklar),
        "puan_mae": round(statistics.mean(farklar), 3),
        "iki_puan_icinde": round(
            sum(f <= 2 for f in farklar) / len(farklar), 4
        ),
    }
    secici = [x for x in tahminler if "otomatik_kabul" in x and "dogru" in x]
    if secici:
        kabuller = [x for x in secici if bool(x["otomatik_kabul"])]
        yanlis_kabul = sum(not bool(x["dogru"]) for x in kabuller)
        # Puan bazlı yanlış kabul: metin birebir tutmasa da puan doğruysa
        # öğrencinin notu doğrudur; asıl zarar puanın yanlış olmasıdır.
        puanli = [x for x in kabuller if "puan_dogru" in x]
        sonuc.update(
            {
                "otomatik_kapsama": round(len(kabuller) / len(secici), 4),
                "yanlis_otomatik_kabul": yanlis_kabul,
                "yanlis_otomatik_kabul_orani": (
                    round(yanlis_kabul / len(kabuller), 6) if kabuller else 0.0
                ),
                "yanlis_puanli_otomatik_kabul": sum(
                    not bool(x["puan_dogru"]) for x in puanli
                ),
                "yanlis_puanli_otomatik_kabul_orani": (
                    round(
                        sum(not bool(x["puan_dogru"]) for x in puanli)
                        / len(puanli),
                        6,
                    )
                    if puanli
                    else None
                ),
            }
        )

    # Hata bütçesi: puan sapmasının ne kadarı anahtardan, ne kadarı okumadan.
    rubrik_hatalari = [
        float(x["rubrik_hatasi"])
        for x in tahminler
        if x.get("rubrik_hatasi") is not None
    ]
    ocr_hatalari = [
        float(x["ocr_puan_hatasi"])
        for x in tahminler
        if x.get("ocr_puan_hatasi") is not None
    ]
    if rubrik_hatalari:
        sonuc["rubrik_mae"] = round(statistics.mean(rubrik_hatalari), 3)
    if ocr_hatalari:
        sonuc["ocr_puan_mae"] = round(statistics.mean(ocr_hatalari), 3)
    return sonuc


# Kayıtlı veto mesajından yalnız OCR güven vetosunu ayıklamak için; diğer tüm
# kriterler kayıtlı karar neyse o kabul edilir (eşik süpürmesi tek boyutludur).
_OCR_GUVEN_VETO_ONEKI = "Kalibre OCR güveni düşük"
_BOS_KABUL_KANITI = "boş buldu"

VARSAYILAN_SUPURME_ESIKLERI = (0.80, 0.82, 0.84, 0.86, 0.88, 0.90, 0.92, 0.95)


def esik_supurmesi(
    kayitlar: list[dict],
    esikler: tuple[float, ...] = VARSAYILAN_SUPURME_ESIKLERI,
) -> list[dict]:
    """Kayıtlı kapı kararlarından "OCR güven eşiği X olsaydı" simülasyonu.

    YALNIZ rapor üretir; kapı eşiklerini değiştirmez. Simülasyon kayıtlı
    kararı yeniden yorumlar: OCR güven vetosu dışındaki tüm vetolar aynen
    korunur (kategorik vetolu kutu hiçbir eşikte kabul edilmez), boş-kutu
    kabulü güvenden bağımsızdır. ``sim_yanlis_kabul`` o eşikle kabul edilecek
    ama öğretmenin sonradan düzelttiği kutu sayısıdır.
    """
    sonuclar = []
    for esik in esikler:
        kabul = yanlis = 0
        for kayit in kayitlar:
            if kayit["otomatik_kabul"]:
                bos_kabul = any(
                    _BOS_KABUL_KANITI in n for n in kayit["nedenler"]
                )
                sim_kabul = bos_kabul or kayit["kalibre_guven"] >= esik
            else:
                kalan_veto = [
                    n
                    for n in kayit["nedenler"]
                    if not n.startswith(_OCR_GUVEN_VETO_ONEKI)
                ]
                sim_kabul = not kalan_veto and kayit["kalibre_guven"] >= esik
            if sim_kabul:
                kabul += 1
                if kayit["ogretmen_degistirdi"]:
                    yanlis += 1
        sonuclar.append(
            {
                "esik": esik,
                "sim_kabul": kabul,
                "sim_kabul_orani": round(kabul / len(kayitlar), 4) if kayitlar else 0.0,
                "sim_yanlis_kabul": yanlis,
            }
        )
    return sonuclar
