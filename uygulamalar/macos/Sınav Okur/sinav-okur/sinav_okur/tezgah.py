"""Altın örnek regresyon tezgâhı: yerel, tekrarlanabilir doğruluk ölçümü.

Onaylanmış kâğıtlardan altın örnek üretir, seçilen tanıyıcıyla yeniden okur ve
CER / tam eşleşme / puan MAE raporlar. Sonuç anlık görüntüsü ``olcumler/``
altına yazılır; önceki koşuyla fark ve gerileme uyarısı üretilir. Hiçbir
eşik veya motor ağırlığı DEĞİŞTİRİLMEZ — bu modül yalnız ölçer.

Altın set küçükken rapor "duman testi"dir, istatistik değildir; rapor bunu
açıkça söyler ve yazar_grubu kırılımı tek gruba dayanıyorsa uyarır.
"""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Callable

from .analiz import altin_test_metrikleri
from .depo import Depo
from .metin import eslesme_bicimi

VARSAYILAN_KAPSAM_ESIKLERI = (0.5, 0.6, 0.7, 0.8, 0.9, 0.95)
# Önceki koşuya göre bu kadar kötüleşme "gerileme" sayılır (mutlak fark).
GERILEME_CER_PAYI = 0.02
GERILEME_ESLESME_PAYI = 0.02
GERILEME_PUAN_MAE_PAYI = 0.25
GERILEME_YANLIS_KABUL_PAYI = 0.01
# Bu sayının altında gerileme "hata" değil "uyarı" sayılır.
ISTATISTIK_ASGARI_ORNEK = 30


def karakter_hata_orani(beklenen: str, tahmin: str) -> float:
    """CER: Levenshtein mesafesi / referans uzunluğu (eşleşme biçiminde)."""
    from rapidfuzz.distance import Levenshtein

    ref = eslesme_bicimi(beklenen or "")
    hyp = eslesme_bicimi(tahmin or "")
    if not ref:
        return 0.0 if not hyp else 1.0
    return Levenshtein.distance(ref, hyp) / len(ref)


GECERLI_KAYNAKLAR = ("onay", "duzeltme", "hepsi")


def altin_ornekleri_uret(
    depo: Depo,
    sinav_kimlik: str | None = None,
    *,
    kaynak: str = "hepsi",
) -> dict:
    """İnsan-doğrulanmış kutuları altın sete alır.

    İki kol vardır ve ikisi de gerçek insan etiketidir:

    * ``onay`` — öğretmenin onayladığı kâğıtların tüm kutuları.
    * ``duzeltme`` — kâğıt onaylanmamış olsa bile öğretmenin METNİ
      düzelttiği kutular. Onay şartı, düzeltilmiş kutuların etiket değerini
      gereksiz yere rehin tutuyordu.

    Aynı kırpıntı ikinci kez eklenmez; tezgâh tekrar tekrar çalıştırılabilir.
    """
    if kaynak not in GECERLI_KAYNAKLAR:
        raise ValueError(
            f"Bilinmeyen kaynak '{kaynak}'. Seçenekler: "
            + ", ".join(GECERLI_KAYNAKLAR)
        )
    eklenen = guncellenen = atlanan = 0
    kaynak_sayimi = {"onay": 0, "duzeltme": 0}
    gorulen: set[tuple] = set()

    def _ekle(kayit: dict, etiket: str) -> None:
        nonlocal eklenen, guncellenen, atlanan
        anahtar = (kayit["sinav_kimlik"], kayit["soru_no"], kayit["kirp_yolu"])
        if anahtar in gorulen:
            return
        if (
            not kayit["kirp_yolu"]
            or kayit["metin"] is None
            or kayit["puan"] is None
        ):
            atlanan += 1
            return
        gorulen.add(anahtar)
        durum = depo.altin_ornek_ekle(
            sinav_kimlik=kayit["sinav_kimlik"],
            soru_no=kayit["soru_no"],
            kirp_yolu=kayit["kirp_yolu"],
            beklenen_metin=kayit["metin"],
            beklenen_puan=float(kayit["puan"]),
            yazar_grubu=kayit["yazar_grubu"] or "",
            kaynak=etiket,
        )
        kaynak_sayimi[etiket] += 1
        if durum == "eklendi":
            eklenen += 1
        elif durum == "guncellendi":
            guncellenen += 1

    if kaynak in ("onay", "hepsi"):
        for kagit in depo.kagitlar(sinav_kimlik):
            if not kagit["onaylandi"]:
                continue
            for kutu in depo.kutular(kagit["id"]):
                _ekle(
                    {
                        "sinav_kimlik": kagit["sinav_kimlik"],
                        "soru_no": kutu["soru_no"],
                        "kirp_yolu": kutu["kirp_yolu"],
                        "metin": (
                            kutu["duzeltilmis_metin"]
                            if kutu["duzeltilmis_metin"] is not None
                            else kutu["taninan_metin"]
                        ),
                        "puan": (
                            kutu["son_puan"]
                            if kutu["son_puan"] is not None
                            else kutu["otomatik_puan"]
                        ),
                        "yazar_grubu": kagit["yazar_grubu"],
                    },
                    "onay",
                )

    if kaynak in ("duzeltme", "hepsi"):
        for kutu in depo.duzeltilmis_kutular(sinav_kimlik):
            _ekle(
                {
                    "sinav_kimlik": kutu["sinav_kimlik"],
                    "soru_no": kutu["soru_no"],
                    "kirp_yolu": kutu["kirp_yolu"],
                    "metin": kutu["duzeltilmis_metin"],
                    "puan": (
                        kutu["son_puan"]
                        if kutu["son_puan"] is not None
                        else kutu["otomatik_puan"]
                    ),
                    "yazar_grubu": kutu["yazar_grubu"],
                },
                "duzeltme",
            )

    return {
        "eklenen": eklenen,
        "guncellenen": guncellenen,
        "atlanan": atlanan,
        "kaynak_sayimi": kaynak_sayimi,
        "toplam": len(depo.altin_ornekler()),
    }


def _varsayilan_gorsel_yukleyici(yol: str):
    import cv2

    return cv2.imread(yol)


def _puan_alanlarini_doldur(satir: dict, sinav, ornek, tanima) -> None:
    """Puan tahmini + hata bütçesi ayrımı + kapı simülasyonu.

    Hata bütçesi ikiye bölünür:

    * ``rubrik_hatasi`` — BEKLENEN metin (öğretmenin yazdığı doğru metin)
      anahtarla puanlandığında öğretmenin verdiği puandan sapma. Bu tamamen
      anahtar/rubrik hatasıdır, OCR'ın payı yoktur.
    * ``ocr_puan_hatasi`` — tanınan metnin puanı ile beklenen metnin puanı
      arasındaki fark. Bu tamamen okuma hatasının puana yansımasıdır.

    Ayrım olmadan "puan MAE" tek bir sayıdır ve iyileştirme yanlış katmana
    yapılır.
    """
    from .guvenlik_kapisi import otomatik_karari_degerlendir
    from .yeniden_puanlama import metni_puanla

    soru_no = ornek["soru_no"]
    beklenen_puan = ornek["beklenen_puan"]
    try:
        tahmin = metni_puanla(sinav, soru_no, tanima.metin)
        satir["tahmin_puan"] = float(tahmin.puan)
    except (KeyError, ValueError):
        return
    try:
        beklenen_sonuc = metni_puanla(sinav, soru_no, ornek["beklenen_metin"])
        satir["beklenen_metin_puani"] = float(beklenen_sonuc.puan)
        if beklenen_puan is not None:
            satir["rubrik_hatasi"] = abs(
                float(beklenen_sonuc.puan) - float(beklenen_puan)
            )
        satir["ocr_puan_hatasi"] = abs(
            float(tahmin.puan) - float(beklenen_sonuc.puan)
        )
    except (KeyError, ValueError):
        pass

    # Kapı simülasyonu: bu okuma ÜRÜNDE otomatik kabul edilir miydi ve
    # kabul edilseydi doğru mu olurdu? `analiz.altin_test_metrikleri`
    # bu iki alanı arıyordu ama tezgâh hiç üretmiyordu (ölü kod).
    try:
        soru = sinav.soru(soru_no)
        kapili = otomatik_karari_degerlendir(
            tanima, tahmin, soru, sayfa_kritik=False, hizalama_guveni=1.0
        )
        satir["otomatik_kabul"] = bool(kapili.otomatik_kabul)
        satir["kapi_nedenleri"] = list(kapili.kabul_nedenleri)
    except (KeyError, ValueError, TypeError):
        satir["otomatik_kabul"] = False
        satir["kapi_nedenleri"] = []
    satir["dogru"] = bool(satir["tam_eslesme"])
    if beklenen_puan is not None and satir["tahmin_puan"] is not None:
        satir["puan_dogru"] = (
            abs(satir["tahmin_puan"] - float(beklenen_puan)) < 0.01
        )


def tezgah_calistir(
    depo: Depo,
    taniyici,
    *,
    sinav_kimlik: str | None = None,
    gorsel_yukleyici: Callable | None = None,
    taniyici_adi: str = "",
    zincir: str = "uretim",
) -> dict:
    """Altın seti seçilen tanıyıcıyla yeniden okuyup metrikleri hesaplar.

    ``zincir`` tezgâhın ÜRÜNÜN hangi yolunu ölçtüğünü belirler:

    * ``ham`` — çıplak ``kutu_taniy`` (eski davranış; bağlam/sözlük yok).
    * ``uretim`` — üretimdeki tam zincir: bağlamlı okuma + terim sözlüğü
      düzeltmesi + aday yeniden sıralama.
    * ``ikisi`` — ikisini birden ölçer, katman kazançlarını raporlar.

    Varsayılan ``uretim``: tezgâh üründen başka bir şeyi ölçerse iyileştirme
    kararları yanlış yere gider.
    """
    from .tanima_zinciri import kutuyu_oku

    if zincir not in ("ham", "uretim", "ikisi"):
        raise ValueError("zincir 'ham', 'uretim' veya 'ikisi' olmalı")
    yukle = gorsel_yukleyici or _varsayilan_gorsel_yukleyici
    ornekler = depo.altin_ornekler(sinav_kimlik)
    satirlar: list[dict] = []
    atlanan: list[str] = []
    sinav_onbellek: dict[str, object] = {}
    for ornek in ornekler:
        yol = ornek["kirp_yolu"]
        if not yol or not Path(yol).is_file():
            atlanan.append(f"kırpıntı yok: {yol}")
            continue
        kirp = yukle(yol)
        if kirp is None:
            atlanan.append(f"görsel okunamadı: {yol}")
            continue

        kimlik = ornek["sinav_kimlik"]
        if kimlik not in sinav_onbellek:
            try:
                sinav_onbellek[kimlik] = depo.sinav_yukle(kimlik)
            except KeyError:
                sinav_onbellek[kimlik] = None
        sinav = sinav_onbellek[kimlik]
        soru = None
        if sinav is not None:
            try:
                soru = sinav.soru(ornek["soru_no"])
            except KeyError:
                soru = None

        ham_tanima = None
        if zincir in ("ham", "ikisi") or soru is None:
            ham_tanima = taniyici.kutu_taniy(kirp)
        if zincir == "ham" or soru is None:
            tanima = ham_tanima
            zincir_sonucu = None
        else:
            zincir_sonucu = kutuyu_oku(taniyici, kirp, soru)
            tanima = zincir_sonucu.tanima
            ham_tanima = ham_tanima or zincir_sonucu.ham_tanima

        beklenen = ornek["beklenen_metin"]
        satir = {
            "sinav_kimlik": kimlik,
            "soru_no": ornek["soru_no"],
            "yazar_grubu": ornek["yazar_grubu"] or "",
            "kaynak": (
                ornek["kaynak"] if "kaynak" in ornek.keys() else "onay"
            ),
            "beklenen_metin": beklenen,
            "tahmin_metin": tanima.metin,
            "guven": float(tanima.guven),
            "cer": karakter_hata_orani(beklenen, tanima.metin),
            "tam_eslesme": eslesme_bicimi(beklenen or "")
            == eslesme_bicimi(tanima.metin or ""),
            "beklenen_puan": ornek["beklenen_puan"],
            "tahmin_puan": None,
            "sozluk_degisim_sayisi": (
                len(zincir_sonucu.sozluk_degisimleri) if zincir_sonucu else 0
            ),
            "siralama_uygulandi": bool(
                zincir_sonucu and zincir_sonucu.siralama_karari
            ),
            "basili_karisimi": (
                zincir_sonucu.basili_karisimi if zincir_sonucu else 0.0
            ),
            "basili_ayiklandi": bool(
                zincir_sonucu and zincir_sonucu.basili_ayiklandi
            ),
        }
        if ham_tanima is not None and zincir != "ham":
            satir["tahmin_metin_ham"] = ham_tanima.metin
            satir["cer_ham"] = karakter_hata_orani(beklenen, ham_tanima.metin)
            satir["tam_eslesme_ham"] = eslesme_bicimi(beklenen or "") == (
                eslesme_bicimi(ham_tanima.metin or "")
            )
        if zincir_sonucu is not None and zincir_sonucu.ipuclari:
            from .tanima_zinciri import baglam_sizmasi

            # Bağlamın cevabı fısıldayıp fısıldamadığı: bağlamlı motoru
            # açmadan önce bakılacak kapı.
            satir["baglam_sizmasi"] = baglam_sizmasi(
                tanima.metin, beklenen, zincir_sonucu.ipuclari
            )
            if ham_tanima is not None:
                satir["baglam_sizmasi_ham"] = baglam_sizmasi(
                    ham_tanima.metin, beklenen, zincir_sonucu.ipuclari
                )
        if sinav is not None:
            _puan_alanlarini_doldur(satir, sinav, ornek, tanima)
        satirlar.append(satir)

    yazar_gruplari = {s["yazar_grubu"] for s in satirlar if s["yazar_grubu"]}
    uyarilar: list[str] = []
    if len(satirlar) < 30:
        uyarilar.append(
            f"Altın set küçük ({len(satirlar)} örnek): rapor duman testidir, "
            "istatistik değildir."
        )
    if len(yazar_gruplari) <= 1:
        uyarilar.append(
            "Tek yazar grubu: sonuç yazar-ayrık değildir, genellemez."
        )
    if any("otomatik_kabul" in s for s in satirlar):
        uyarilar.append(
            "Kapı simülasyonu iyimser üst sınırdır: sayfa kalitesi ve "
            "hizalama vetoları hesaba katılmaz (altın sette sayfa bağlamı yok)."
        )
    uyarilar.extend(_veri_sagligi_uyarilari(satirlar))
    metrikler = {
        "ornek": len(satirlar),
        "ort_cer": (
            round(sum(s["cer"] for s in satirlar) / len(satirlar), 4)
            if satirlar
            else None
        ),
        "tam_eslesme_orani": (
            round(sum(s["tam_eslesme"] for s in satirlar) / len(satirlar), 4)
            if satirlar
            else None
        ),
        "puan": altin_test_metrikleri(satirlar),
        "katman_kazanci": _katman_kazanci(satirlar),
        "kaynak_dagilimi": _kaynak_dagilimi(satirlar),
    }
    return {
        "taniyici": taniyici_adi or type(taniyici).__name__,
        "zincir": zincir,
        "sinav": sinav_kimlik,
        "zaman": datetime.now().isoformat(timespec="seconds"),
        "metrikler": metrikler,
        "uyarilar": uyarilar,
        "atlanan": atlanan,
        "yazar_grubu_sayisi": len(yazar_gruplari),
        "satirlar": satirlar,
    }


# CER 1.0 = "hiçbir şey okunamadı" demektir; bunun belirgin üstü, tanınan
# metnin beklenenden KAT KAT uzun olduğunu, yani kırpıntının cevaptan
# fazlasını (çoğunlukla basılı soru metnini) içerdiğini gösterir.
SISME_CER_ESIGI = 2.0


def _veri_sagligi_uyarilari(satirlar: list[dict]) -> list[str]:
    """Ölçümün kendisi doğru olsa da VERİSİ bozuksa öğretmene söyle.

    Ölçüldü: kırpıntısı basılı soru metnini de kapsayan örneklerde OCR
    öğrencinin cevabı yerine soruyu okuyor ve CER 8-12 çıkıyor. Böyle bir
    altın set "model kötü" gibi görünen ama aslında etiket-görüntü
    uyumsuzluğu olan bir tablo üretir.
    """
    if not satirlar:
        return []
    sisen = [s for s in satirlar if float(s.get("cer") or 0) > SISME_CER_ESIGI]
    if not sisen:
        return []
    return [
        f"{len(sisen)}/{len(satirlar)} örnekte CER {SISME_CER_ESIGI}'nin "
        "üstünde: kırpıntı büyük olasılıkla öğrenci cevabından fazlasını "
        "(basılı soru metnini) içeriyor. Bu örnekler model kalitesini değil "
        "kesme hatasını ölçer — kırpıntıları düzeltmeden sonuçlara güvenmeyin."
    ]


def _ortalama(degerler: list[float]) -> float | None:
    return round(sum(degerler) / len(degerler), 4) if degerler else None


def _katman_kazanci(satirlar: list[dict]) -> dict:
    """Üretim zincirinin ham okumaya göre kazandırdığı CER farkı."""
    karsilastirilabilir = [s for s in satirlar if "cer_ham" in s]
    if not karsilastirilabilir:
        return {}
    ham = _ortalama([s["cer_ham"] for s in karsilastirilabilir])
    uretim = _ortalama([s["cer"] for s in karsilastirilabilir])
    return {
        "ornek": len(karsilastirilabilir),
        "ort_cer_ham": ham,
        "ort_cer_uretim": uretim,
        "cer_kazanci": (
            round(ham - uretim, 4) if ham is not None and uretim is not None
            else None
        ),
        "sozluk_dokunan": sum(
            1 for s in karsilastirilabilir if s.get("sozluk_degisim_sayisi")
        ),
        "siralama_dokunan": sum(
            1 for s in karsilastirilabilir if s.get("siralama_uygulandi")
        ),
        "ort_baglam_sizmasi": _ortalama(
            [
                s["baglam_sizmasi"]
                for s in karsilastirilabilir
                if s.get("baglam_sizmasi") is not None
            ]
        ),
        "ort_baglam_sizmasi_ham": _ortalama(
            [
                s["baglam_sizmasi_ham"]
                for s in karsilastirilabilir
                if s.get("baglam_sizmasi_ham") is not None
            ]
        ),
    }


def _kaynak_dagilimi(satirlar: list[dict]) -> dict:
    """Etiketlerin nereden geldiği (onay / düzeltme / elle)."""
    dagilim: dict[str, int] = {}
    for satir in satirlar:
        etiket = str(satir.get("kaynak") or "onay")
        dagilim[etiket] = dagilim.get(etiket, 0) + 1
    return dagilim


def kapsam_supurmesi(
    satirlar: list[dict],
    esikler: tuple[float, ...] = VARSAYILAN_KAPSAM_ESIKLERI,
) -> list[dict]:
    """Güven eşiği → kapsam ve o kapsamdaki doğruluk (yalnız rapor)."""
    sonuc = []
    for esik in esikler:
        kapsanan = [s for s in satirlar if s["guven"] >= esik]
        sonuc.append(
            {
                "esik": esik,
                "kapsam": round(len(kapsanan) / len(satirlar), 4) if satirlar else 0.0,
                "ornek": len(kapsanan),
                "ort_cer": (
                    round(sum(s["cer"] for s in kapsanan) / len(kapsanan), 4)
                    if kapsanan
                    else None
                ),
                "tam_eslesme_orani": (
                    round(sum(s["tam_eslesme"] for s in kapsanan) / len(kapsanan), 4)
                    if kapsanan
                    else None
                ),
            }
        )
    return sonuc


def perf_ozeti(serbest_taslak_dizini: str | Path) -> dict:
    """Kayıtlı taslakların sayfa-OCR raporlarından motor süre kırılımı.

    ``sure_ms`` her koşuda zaten toplanıyordu ama hiçbir yerde
    raporlanmıyordu. Süreler gerçek motor koşularına aittir; ``yapay``/test
    motorları taslak üretmediği için buraya karışmaz.
    """
    motorlar: dict[str, dict] = {}
    sayfa_toplamlari: list[int] = []
    taslak_sayisi = 0
    for taslak in sorted(Path(serbest_taslak_dizini).glob("*/taslak.json")):
        try:
            veri = json.loads(taslak.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        raporlar = veri.get("ocr_raporu") or []
        if not raporlar:
            continue
        taslak_sayisi += 1
        sayfa_sureleri: dict[int, int] = {}
        for rapor in raporlar:
            motor = str(rapor.get("motor", "?"))
            m = motorlar.setdefault(
                motor, {"istek": 0, "toplam_ms": 0, "hata": 0}
            )
            sure = int(rapor.get("sure_ms") or 0)
            m["istek"] += 1
            m["toplam_ms"] += sure
            if rapor.get("hata"):
                m["hata"] += 1
            sayfa = int(rapor.get("sayfa") or 1)
            sayfa_sureleri[sayfa] = sayfa_sureleri.get(sayfa, 0) + sure
        sayfa_toplamlari.extend(sayfa_sureleri.values())
    kirilim = [
        {
            "motor": motor,
            "istek": m["istek"],
            "hata": m["hata"],
            "toplam_ms": m["toplam_ms"],
            "ort_ms": round(m["toplam_ms"] / m["istek"]) if m["istek"] else 0,
        }
        for motor, m in motorlar.items()
    ]
    kirilim.sort(key=lambda x: -x["toplam_ms"])
    return {
        "taslak_sayisi": taslak_sayisi,
        "sayfa_sayisi": len(sayfa_toplamlari),
        "ort_sayfa_ms": (
            round(sum(sayfa_toplamlari) / len(sayfa_toplamlari))
            if sayfa_toplamlari
            else 0
        ),
        "motorlar": kirilim,
    }


def _son_anlik_goruntu(olcum_dizini: Path) -> dict | None:
    dosyalar = sorted(olcum_dizini.glob("tezgah-*.json"))
    if not dosyalar:
        return None
    try:
        return json.loads(dosyalar[-1].read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def gerileme_karsilastir(onceki: dict | None, yeni: dict) -> dict:
    """Önceki anlık görüntüyle fark; kötüleşme payı aşılırsa gerileme uyarısı.

    Yalnız aynı tanıyıcı VE aynı sınav kapsamındaki koşular karşılaştırılır —
    --sinav X koşusu tam koşuyla kıyaslanıp yapay gerileme üretmesin.
    """
    if (
        not onceki
        or onceki.get("taniyici") != yeni.get("taniyici")
        or onceki.get("sinav") != yeni.get("sinav")
    ):
        return {"onceki": None, "gerilemeler": []}
    o, y = onceki["metrikler"], yeni["metrikler"]
    gerilemeler = []
    if (
        o.get("ort_cer") is not None
        and y.get("ort_cer") is not None
        and y["ort_cer"] - o["ort_cer"] > GERILEME_CER_PAYI
    ):
        gerilemeler.append(
            f"CER {o['ort_cer']:.4f} → {y['ort_cer']:.4f} (kötüleşme)"
        )
    if (
        o.get("tam_eslesme_orani") is not None
        and y.get("tam_eslesme_orani") is not None
        and o["tam_eslesme_orani"] - y["tam_eslesme_orani"] > GERILEME_ESLESME_PAYI
    ):
        gerilemeler.append(
            f"Tam eşleşme {o['tam_eslesme_orani']:.4f} → "
            f"{y['tam_eslesme_orani']:.4f} (kötüleşme)"
        )
    # Puan MAE ve yanlış otomatik kabul: öğrencinin notunu doğrudan etkileyen
    # iki metrik. Kapı yalnız CER'e bakarsa, metni aynı okuyup puanı bozan bir
    # değişiklik sessizce geçer.
    o_puan, y_puan = o.get("puan") or {}, y.get("puan") or {}
    if (
        o_puan.get("puan_mae") is not None
        and y_puan.get("puan_mae") is not None
        and y_puan["puan_mae"] - o_puan["puan_mae"] > GERILEME_PUAN_MAE_PAYI
    ):
        gerilemeler.append(
            f"Puan MAE {o_puan['puan_mae']:.3f} → "
            f"{y_puan['puan_mae']:.3f} (kötüleşme)"
        )
    o_yanlis = o_puan.get("yanlis_otomatik_kabul_orani")
    y_yanlis = y_puan.get("yanlis_otomatik_kabul_orani")
    if (
        o_yanlis is not None
        and y_yanlis is not None
        and y_yanlis - o_yanlis > GERILEME_YANLIS_KABUL_PAYI
    ):
        gerilemeler.append(
            f"Yanlış otomatik kabul oranı {o_yanlis:.4f} → {y_yanlis:.4f} "
            "(kötüleşme)"
        )

    # Küçük altın sette tek örnek metrikleri savurur; gerileme burada karar
    # değil uyarıdır. Sürekli kırmızı yanan bir kapı kısa sürede susturulur.
    if gerilemeler and int(y.get("ornek") or 0) < ISTATISTIK_ASGARI_ORNEK:
        gerilemeler = [
            f"{g} — altın set {y.get('ornek')} örnek, istatistik değil; "
            "uyarı sayılır"
            for g in gerilemeler
        ]
    return {
        "onceki": {"zaman": onceki.get("zaman"), "metrikler": o},
        "gerilemeler": gerilemeler,
        "sert": bool(gerilemeler)
        and int(y.get("ornek") or 0) >= ISTATISTIK_ASGARI_ORNEK,
    }


def anlik_goruntu_yaz(olcum_dizini: str | Path, sonuc: dict) -> Path:
    dizin = Path(olcum_dizini)
    dizin.mkdir(parents=True, exist_ok=True)
    onceki = _son_anlik_goruntu(dizin)
    sonuc["karsilastirma"] = gerileme_karsilastir(onceki, sonuc)
    ad = "tezgah-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".json"
    yol = dizin / ad
    yol.write_text(
        json.dumps(sonuc, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return yol
