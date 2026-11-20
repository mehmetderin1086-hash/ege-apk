#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — CI-benzeri kalite regresyon koşumu.

kalite/koleksiyon.json'daki her belge için dogrula.metrikler çalıştırır ve
kalite/once_*.json anlık görüntüsüyle karşılaştırır: anomali sayısı ARTMIŞSA
regresyon (kırmızı). Ayrıca soru modeli açık/kapalı ikili koşum tablosu
üretebilir (--ikili). Golden koordinat dosyası olan belgeler için (kalite/
altin/<ad>.json) IoU-tabanlı F1 de raporlanır.

Kullanım:
    .venv/bin/python kalite_kosusu.py                 # tüm koleksiyon
    .venv/bin/python kalite_kosusu.py --sadece 9pdf aydin
    .venv/bin/python kalite_kosusu.py --ikili         # model açık/kapalı
    .venv/bin/python kalite_kosusu.py --guncelle      # once_*.json tazele

Çıkış kodu: regresyon varsa 1, yoksa 0 (CI kapısı için).
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile

import dogrula

KOK = os.path.dirname(os.path.abspath(__file__))
KOLEKSIYON = os.path.join(KOK, "kalite", "koleksiyon.json")
ALTIN_DIZIN = os.path.join(KOK, "kalite", "altin")
KAPI_ESIKLERI = os.path.join(KOK, "kalite", "kapi_esikleri.json")
# Ölçülen kutuların bu orandan fazlası teslim edilmiyorsa kapı kırmızı yanar.
# Bir miktar fark meşru (cevap anahtarı sayfaları), ama beşte birden fazlası
# ölçümün ürünü temsil etmediği anlamına gelir.
TESLIM_AYRISMA_ESIGI = 0.20


# Korpus katmanları. Hepsini her değişiklikte koşmak pratik değil (44 belge
# ~20 dk); ama "bütün kitaplar" hedefi de vazgeçilmez. Çözüm üç katman:
#   A — kapı: her ailede temsilci, her motor değişikliğinde koşulur
#   B — tam korpus: faz sonunda koşulur, A'yı da kapsar
#   C — yayın: kutu-altınlı TYT dilimleri, YALNIZ yayın kararında
KAPSAM_KATMANLARI = {
    "A": {"A"},
    "B": {"A", "B"},
    "C": {"A", "B", "C"},
}


def _koleksiyon_oku(yol=KOLEKSIYON, *, varsayilan=True, kapsam=None):
    with open(yol, encoding="utf-8") as f:
        ogeler = json.load(f)
    if kapsam:
        izin = KAPSAM_KATMANLARI[kapsam]
        return [o for o in ogeler if o.get("kapsam", "A") in izin]
    if varsayilan:
        ogeler = [o for o in ogeler if o.get("varsayilan", True)]
    return ogeler


def _secili_koleksiyon(secili=None, kapsam=None, yol=KOLEKSIYON):
    """Koşum ve A/B kimlik kapısı için aynı belge seçimini üretir."""
    koleksiyon = _koleksiyon_oku(
        yol=yol, varsayilan=not bool(secili), kapsam=kapsam)
    if secili:
        secili_adlar = set(secili)
        koleksiyon = [o for o in koleksiyon if o["ad"] in secili_adlar]
    return koleksiyon


def _tam_yol(yol):
    """Koleksiyon yolunu diskteki gerçek dosyaya çevirir.

    Korpusun bir bölümü repoya göreli (`kalite/…`), bir bölümü ise ev
    dizinine göreli (`Desktop/…`) yazılmış. Yalnız repo kökünü denemek,
    proje ~/Documents'tan ~/Developer'a taşındığında 29 belgeyi birden
    bulunamaz yapıp kapıyı sessizce çalıştırılamaz hâle getirdi: koşum
    "belge yok" deyip geçtiği için kapı yeşil de kırmızı da değildi.
    Bu yüzden iki kök de denenir. `SORU_KESICI_KORPUS` verilirse önce o.
    """
    if os.path.isabs(yol):
        return yol
    kokler = []
    ortam = os.environ.get("SORU_KESICI_KORPUS", "").strip()
    if ortam:
        kokler.append(os.path.expanduser(ortam))
    kokler.extend((KOK, os.path.expanduser("~")))
    for kok in kokler:
        aday = os.path.join(kok, yol)
        if os.path.exists(aday):
            return aday
    # Hiçbiri yoksa repo köklü yolu döndür: hata mesajı beklenen yeri gösterir.
    return os.path.join(KOK, yol)


def _girdi_yolu(oge):
    return _tam_yol(oge["yol"])


def _altin_yolu(oge):
    ayar = oge.get("altin")
    return (
        _tam_yol(ayar)
        if ayar
        else os.path.join(ALTIN_DIZIN, f"{oge['ad']}.json")
    )


def _dosya_kimligi(yol, *, zorunlu):
    """Dosyayı akış halinde SHA-256'lar; hash sırasında değişimi de reddeder."""
    if not os.path.exists(yol):
        if zorunlu:
            raise FileNotFoundError(f"A/B korpus dosyası bulunamadı: {yol}")
        if os.path.lexists(yol):
            raise RuntimeError(f"A/B korpusunda kırık bağlantı var: {yol}")
        return None
    if not os.path.isfile(yol):
        raise RuntimeError(f"A/B korpus girdisi dosya değil: {yol}")
    once = os.stat(yol)
    ozet = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1024 * 1024), b""):
            ozet.update(parca)
    sonra = os.stat(yol)
    once_imza = (
        once.st_dev, once.st_ino, once.st_size, once.st_mtime_ns)
    sonra_imza = (
        sonra.st_dev, sonra.st_ino, sonra.st_size, sonra.st_mtime_ns)
    if once_imza != sonra_imza:
        raise RuntimeError(f"A/B korpus dosyası hash sırasında değişti: {yol}")
    return {"sha256": ozet.hexdigest(), "boyut": sonra.st_size}


def _json_sha256(deger):
    ham = json.dumps(
        deger,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(ham).hexdigest()


def _korpus_kimlikleri(secili=None, kapsam=None, koleksiyon_yolu=KOLEKSIYON):
    """A/B'de kullanılan kaynak ve bütün kalite kanıtlarını içerikle bağlar.

    Dosya adı eşitliği yeterli değildir: aynı PDF iki kol arasında yerinde
    değiştirilebilir. Bu manifest kaynak baytlarını, belge ayarını ve sonucu
    etkileyen altın/sayım/snapshot/eşik dosyalarını SHA-256 ile sabitler.
    """
    koleksiyon = _secili_koleksiyon(
        secili, kapsam=kapsam, yol=koleksiyon_yolu)
    adlar = [o.get("ad") for o in koleksiyon]
    if any(not isinstance(ad, str) or not ad for ad in adlar):
        raise RuntimeError("A/B koleksiyonunda geçersiz belge kimliği var")
    if len(adlar) != len(set(adlar)):
        raise RuntimeError("A/B koleksiyonunda yinelenen belge kimliği var")

    esik = _dosya_kimligi(KAPI_ESIKLERI, zorunlu=False)
    esik_sha = esik["sha256"] if esik else None
    kimlikler = []
    for oge in koleksiyon:
        ad = oge["ad"]
        kaynak = _dosya_kimligi(_girdi_yolu(oge), zorunlu=True)
        altin = _dosya_kimligi(_altin_yolu(oge), zorunlu=False)
        sayim = _dosya_kimligi(
            os.path.join(KOK, "kalite", "altin_sayim", f"{ad}.json"),
            zorunlu=False,
        )
        anlik = (
            _dosya_kimligi(_tam_yol(oge["anlik"]), zorunlu=False)
            if oge.get("anlik")
            else None
        )
        kimlikler.append({
            "ad": ad,
            "kaynak_sha256": kaynak["sha256"],
            "kaynak_boyut": kaynak["boyut"],
            "meta_sha256": _json_sha256(oge),
            "altin_sha256": altin["sha256"] if altin else None,
            "sayim_altin_sha256": sayim["sha256"] if sayim else None,
            "anlik_sha256": anlik["sha256"] if anlik else None,
            "kapi_esikleri_sha256": esik_sha,
        })
    return sorted(kimlikler, key=lambda k: k["ad"])


def _anlik_oku(yol):
    if not yol:
        return None
    tam = yol if os.path.isabs(yol) else os.path.join(KOK, yol)
    if not os.path.exists(tam):
        return None
    with open(tam, encoding="utf-8") as f:
        return json.load(f)


def _incele_sayisi(veriler):
    """'incele' durumundaki (otomatik kovaya girmeyen, devam parçası olmayan)
    aday sayısı. dogrula.belge_isle'ın meta listesinden okunur; dogrula.py'ye
    dokunmadan yalnız bilgi amaçlı bir sayaçtır."""
    return sum(
        1
        for _s, _bantlar, _kutular, meta in veriler
        for aday in meta
        if not getattr(aday, "devam_aday", False)
        and getattr(aday, "inceleme_durumu", None) == "incele"
    )


def _kayma_degerlendir(m, onceki):
    """İki koşum arasındaki KUTU/ADAY kaymasını değerlendirir.

    Anomali sayısı bir proxy'dir ve recall kaybını göremez: gerçek bir vakada
    bir belgenin kutu sayısı 27→18 düşerken anomali iki koşumda da 0 kaldı ve
    kapı yeşil verdi. Buradaki kurallar o sınıfı kapatır.

    Yanlış alarm üretmemek için önce GEÇERLİLİK kapısı çalışır: kaynak dosya,
    sayfa örneklemi, format veya ML durumu değiştiyse iki koşum kıyaslanabilir
    değildir ve hiçbir kayma kuralı uygulanmaz. Snapshot'ta bir alan yoksa
    (eski dosyalar) o kural sessizce atlanır.

    Dönüş: [{"kod", "seviye": kirmizi|sari|bilgi, "detay"}]
    """
    if not onceki:
        return []
    for alan in ("kaynak_sha256", "format", "duzen_model"):
        eski, yeni = onceki.get(alan), m.get(alan)
        if eski is not None and yeni is not None and eski != yeni:
            return [{"kod": "anlik-gecersiz", "seviye": "bilgi",
                     "detay": f"{alan}: {eski} → {yeni}"}]
    if onceki.get("sayfa") is not None and onceki["sayfa"] != m.get("sayfa"):
        return [{"kod": "anlik-gecersiz", "seviye": "bilgi",
                 "detay": f"sayfa: {onceki['sayfa']} → {m.get('sayfa')}"}]

    bulgular = []
    eski_kutu, yeni_kutu = onceki.get("toplam_kutu"), m.get("toplam_kutu")
    eski_aday, yeni_aday = onceki.get("ham_aday"), m.get("ham_aday")
    eski_red, yeni_red = onceki.get("reddedilen_kutu"), m.get("reddedilen_kutu")

    if (eski_aday is not None and yeni_aday is not None
            and yeni_aday < eski_aday * 0.95 and eski_aday - yeni_aday >= 3):
        bulgular.append({"kod": "aday-dusus", "seviye": "kirmizi",
                         "detay": f"ham aday {eski_aday} → {yeni_aday}"})
    if (eski_kutu is not None and yeni_kutu is not None
            and yeni_kutu < eski_kutu * 0.95 and eski_kutu - yeni_kutu >= 3):
        bulgular.append({"kod": "kutu-dusus", "seviye": "kirmizi",
                         "detay": f"kutu {eski_kutu} → {yeni_kutu}"})
    elif (eski_kutu is not None and yeni_kutu is not None
            and yeni_kutu > eski_kutu * 1.15 and yeni_kutu - eski_kutu >= 5):
        bulgular.append({"kod": "kutu-artis", "seviye": "sari",
                         "detay": f"kutu {eski_kutu} → {yeni_kutu}"})

    eski_sayfa = onceki.get("sayfa_soru") or []
    yeni_sayfa = m.get("sayfa_soru") or []
    if len(eski_sayfa) == len(yeni_sayfa) and eski_sayfa:
        sifirlanan = [i + 1 for i, (a, b) in enumerate(zip(eski_sayfa,
                                                           yeni_sayfa))
                      if a > 0 and b == 0]
        if sifirlanan:
            bulgular.append({"kod": "sayfa-sifirlandi", "seviye": "kirmizi",
                             "detay": f"örnek sıra {sifirlanan[:8]}"})
        kayan = sum(1 for a, b in zip(eski_sayfa, yeni_sayfa)
                    if abs(a - b) >= 2)
        if kayan / len(eski_sayfa) > 0.20:
            bulgular.append({"kod": "sayfa-kayma", "seviye": "sari",
                             "detay": f"{kayan}/{len(eski_sayfa)} sayfa ±2+"})

    eski_tur = onceki.get("anomali_turleri")
    yeni_tur = m.get("anomali_turleri")
    if isinstance(eski_tur, dict) and isinstance(yeni_tur, dict):
        artan = {t: (eski_tur.get(t, 0), n) for t, n in yeni_tur.items()
                 if n > eski_tur.get(t, 0)}
        if artan:
            bulgular.append({"kod": "anomali-tur-artis", "seviye": "kirmizi",
                             "detay": ", ".join(f"{t} {a}→{b}"
                                                for t, (a, b) in artan.items())})

    if (not any(b["kod"] == "kutu-dusus" for b in bulgular)
            and None not in (eski_kutu, yeni_kutu, eski_aday, yeni_aday,
                             eski_red, yeni_red)
            and yeni_kutu < eski_kutu and yeni_aday >= eski_aday * 0.98
            and yeni_red > eski_red):
        bulgular.append({"kod": "filtre-kaymasi", "seviye": "sari",
                         "detay": f"reddedilen {eski_red} → {yeni_red}"})

    # Sayım-altını gerilemesi: eşik dosyasından BAĞIMSIZ, iki koşum arası
    # doğrudan karşılaştırma. Kutu sayısı sabit kalırken bile hangi sayfada
    # kaç soru bulunduğu bozulabilir; bunu yalnız bu sinyal görür.
    eski_sayim = onceki.get("sayim")
    yeni_sayim = m.get("sayim")
    if isinstance(eski_sayim, dict) and isinstance(yeni_sayim, dict):
        for olcut in ("count_recall", "count_precision",
                      "count_recall_auto", "page_exact_rate"):
            a, b = eski_sayim.get(olcut), yeni_sayim.get(olcut)
            if a is None or b is None:
                continue
            if b < a - 1e-9:
                bulgular.append({
                    "kod": f"sayim-dusus-{olcut}", "seviye": "kirmizi",
                    "detay": f"{a:.4f} → {b:.4f}"})
    return bulgular


def _esikleri_oku(yol=None):
    yol = yol or KAPI_ESIKLERI
    if not os.path.exists(yol):
        return {"varsayilan": {}, "belgeler": {}}
    with open(yol, encoding="utf-8") as f:
        return json.load(f)


def _altin_kapisi(ad, satir, esikler):
    """Altın verili belgede kalite tabanının altına düşüşü kırmızı bulguya
    çevirir.

    Bu kapı olmadan bir kalite düşüşü YALNIZ elle fark edilebiliyordu: gerçek
    vakada bir motor değişikliği 10 belgelik korpusta anomali artışı üretmeden
    altın veride F1'i 0,975'ten 0,966'ya indirdi (41 yanlış-pozitif) ve koşum
    yeşil verdi."""
    hedef = (esikler.get("belgeler") or {}).get(ad)
    if not hedef:
        return []
    bulgular = []
    olculen = {
        "f1_min": satir.get("f1"),
        "precision_min": satir.get("precision"),
        "recall_min": satir.get("recall"),
        "f1_siki_min": satir.get("f1_siki"),
        # Sayım-altını (koordinatsız) tabanları. Kutu-altını yalnız tek bir
        # ÖSYM PDF'inde var; korpusun geri kalanında recall/precision'ı
        # gören TEK kapı budur.
        "count_recall_min": satir.get("count_recall"),
        "count_precision_min": satir.get("count_precision"),
        "count_recall_auto_min": satir.get("count_recall_auto"),
        "page_exact_min": satir.get("page_exact_rate"),
    }
    for anahtar, deger in olculen.items():
        taban = hedef.get(anahtar)
        if taban is None or deger is None:
            continue
        olcut = anahtar[:-4].rstrip("_")
        onek = "sayim" if olcut.startswith("count_") else "altin"
        if deger < taban:
            bulgular.append({
                "kod": f"{onek}-{olcut}",
                "seviye": "kirmizi",
                "detay": f"{deger:.4f} < taban {taban:.4f}"})
    # Ratchet önerisi: ölçüm tabanın belirgin üstündeyse tabanı yükselt.
    # Otomatik YAZILMAZ — insan onayıyla kapi_esikleri.json'a işlenir.
    tolerans = (esikler.get("varsayilan") or {}).get("gerileme_toleransi", 0.005)
    for anahtar in ("f1_min", "count_recall_min", "count_recall_auto_min"):
        deger, taban = olculen.get(anahtar), hedef.get(anahtar)
        if (deger is not None and taban is not None
                and deger - tolerans > taban + 1e-9):
            bulgular.append({
                "kod": "altin-taban-yukseltilebilir", "seviye": "bilgi",
                "detay": (f"{anahtar} {taban:.4f} → "
                          f"{deger - tolerans:.4f} önerilir")})
    return bulgular


def _sayim_kosusu(ad, veriler, ornek_no):
    """Varsa sayım-altınını AYNI koşumun verileriyle değerlendirir.

    İkinci bir motor koşumu gerekmez: `veriler`/`ornek_no` zaten elde.
    Sayım-altını korpusun büyük kısmında recall'ü gören tek ölçüdür; bu
    bağlantı olmadan cozumler1'in 1,00 → 0,475 çöküşü gibi bir olay ancak
    elle `altin_sayim.py --olc` koşulursa görülüyordu."""
    yol = os.path.join(KOK, "kalite", "altin_sayim", f"{ad}.json")
    if not os.path.exists(yol):
        return None
    try:
        import altin_sayim
        return altin_sayim.sayim_degerlendir(
            altin_sayim.sayim_yukle(yol), veriler, ornek_no)
    except Exception as e:  # noqa: BLE001
        return {"hata": str(e)}


def _teslim_ayrismasi(veriler, fmt, kalite="legacy"):
    """Ölçülen küme ile TESLİM edilen küme arasındaki farkı hesaplar.

    `dogrula.belge_isle` her sayfa için doğrudan `sorulari_tespit_meta`
    çağırır; ürün yolu (`sorulari_tespit_toplu`) ise önce sayfa rolü
    vetosunu ve cevap-anahtarı atlamasını uygular. Yani kapı, teslim
    edilmeyen sayfaların kutularını da sayabiliyordu: cozumler1'de kapı
    count_recall 0,845 derken gerçek teslim 0,451'di ve bu fark hiçbir
    yerde görünmüyordu.

    Burada aynı ön filtre kapı tarafında da koşturulur; dönen sözlük
    farkı görünür kılar. Ölçüm metriklerinin anlamı DEĞİŞTİRİLMEZ
    (anlık görüntülerle karşılaştırılabilir kalsınlar diye); fark ayrı
    bir alan ve ayrı bir kapı sinyali olarak raporlanır.
    """
    import soru_kes as sk

    sayfalar = [v[0] for v in veriler]
    try:
        dislanacak, soru_sayfalari = sk._belge_sayfa_rolleri(
            sayfalar, kalite, fmt=fmt)
    except Exception as exc:  # noqa: BLE001 — ayrışma ölçümü koşumu düşürmesin
        return {"hata": f"{type(exc).__name__}: {exc}"}

    veto = set()
    for i, sayfa in enumerate(sayfalar):
        if i in dislanacak or (
                soru_sayfalari is not None and i not in soru_sayfalari):
            veto.add(i)
            continue
        try:
            if sk._cevap_sayfasi_mi(sayfa.satirlar()):
                veto.add(i)
        except Exception:  # noqa: BLE001 — OCR hatası normal akışa düşer
            pass

    olculen = sum(len(v[2]) for v in veriler)
    teslim = sum(len(v[2]) for i, v in enumerate(veriler) if i not in veto)
    return {
        "olculen_kutu": olculen,
        "teslim_kutu": teslim,
        "veto_sayfa": sorted(veto),
        "kayip_kutu": olculen - teslim,
    }


def _belge_kosusu(oge, altin=True):
    """Tek belgeyi işler; (metrikler, kalite|None, sayim|None) döner."""
    yol = _girdi_yolu(oge)
    dpi = oge.get("dpi", 300)
    max_sayfa = oge.get("max_sayfa", 40)
    bas = oge.get("bas")
    son = oge.get("son")
    import soru_kes as sk
    # Tek belge_isle çağrısı: hem metrikler hem (golden varsa) tahmin raporu
    # aynı işlemeden türetilir — belgeyi iki kez açıp OCR etmeyi önler ve
    # meta listesine (incele-kuyruğu sayacı için) erişim verir.
    fmt, veriler, ornek_no, acik = dogrula.belge_isle(
        yol, dpi=dpi, max_sayfa=max_sayfa, bas=bas, son=son)
    kalite = None
    sayim = None
    try:
        m = dogrula._metrikleri_hesapla(fmt, veriler, ornek_no, yol)
        # YENİ bilgi kolonu: snapshot karşılaştırmasına girmez, yalnız
        # görüntülenir (kosu() içindeki regresyon mantığı anomali_sayisi'na
        # bakar, incele_kuyrugu'na değil).
        m["incele_kuyrugu"] = _incele_sayisi(veriler)
        m["teslim"] = _teslim_ayrismasi(veriler, fmt)
        sayim = _sayim_kosusu(oge["ad"], veriler, ornek_no)
        if sayim and "hata" not in sayim:
            # Snapshot'a da gömülür: böylece kayma kapısı ve --guncelle
            # bloklaması sayım gerilemesini eşiklerden bağımsız görebilir.
            m["sayim"] = {k: sayim[k] for k in (
                "count_recall", "count_precision", "count_recall_auto",
                "count_precision_auto", "page_exact_rate", "gold_total",
                "pred_total", "zero_pages")}
        altin_yol = _altin_yolu(oge)
        if altin and os.path.exists(altin_yol):
            try:
                altin_veri = dogrula.altin_veriyi_yukle(altin_yol)
                tahmin_semasi = (
                    dogrula.TAHMIN_SEMA_SURUMU_V2
                    if altin_veri.get("schema_version")
                    == dogrula.ALTIN_SEMA_SURUMU_V2
                    else dogrula.TAHMIN_SEMA_SURUMU_V1
                )
                tahmin = dogrula._tahmin_raporu_verilerden(
                    yol, fmt, veriler, ornek_no, dpi=dpi,
                    max_sayfa=max_sayfa,
                    schema_version=tahmin_semasi,
                    quality_mode=oge.get("kalite", "balanced"))
                kalite = dogrula.kalite_degerlendir(
                    altin_veri, tahmin)
            except Exception as e:  # noqa: BLE001
                kalite = {"hata": str(e)}
    finally:
        sk.belge_kapat(acik)
    return m, kalite, sayim


class KorpusEksik(FileNotFoundError):
    """Kapı korpusundaki bir veya daha çok belge okunamıyor."""


# macOS, iCloud tarafından buluta taşınmış bir dosyayı yerinde ve doğru
# boyutta gösterir ama içeriği yoktur. Bayrak stat'ta görünür; içeriğe
# dokunmak (open/read, hatta `head`) süreci ASKIDA BIRAKIR, bu yüzden
# okunabilirlik testi kesinlikle stat ile yapılmalı.
_SF_DATALESS = 0x40000000


def _belge_erisilebilir_mi(yol):
    """(erişilebilir_mi, gerekçe). İçeriğe hiç dokunmaz."""
    try:
        st = os.stat(yol)
    except OSError:
        return False, "dosya yok"
    if st.st_flags & _SF_DATALESS or (st.st_size > 0 and st.st_blocks == 0):
        return False, "iCloud'a tahliye edilmiş (yerel kopya yok)"
    return True, ""


def _korpusu_dogrula(koleksiyon):
    """Koşumdan ÖNCE bütün belgelerin GERÇEKTEN okunabilir olduğunu doğrular.

    Yalnız `os.path.exists` bakmak yetmiyor: iCloud'a tahliye edilmiş bir
    PDF var görünür, doğru boyutu bildirir ve `fitz.open` ancak dakikalar
    sonra, koşumun ortasında `FileDataError` ile patlar. Korpusun tamamı
    böyle kaybolduğunda kapı ne yeşil ne kırmızıdır — sadece çöker.

    Kısmi koşum da kabul edilmez: bir belge eksik kalırsa çıkan sayılar
    önceki anlık görüntülerle karşılaştırılabilir olmaktan çıkar.
    """
    sorunlu = []
    for oge in koleksiyon:
        yol = _girdi_yolu(oge)
        tamam, gerekce = _belge_erisilebilir_mi(yol)
        if not tamam:
            sorunlu.append((oge["ad"], yol, gerekce))
    if not sorunlu:
        return
    dokum = "\n".join(f"  {ad}: {gerekce} — {yol}" for ad, yol, gerekce in sorunlu)
    tahliye = sum(1 for _a, _y, g in sorunlu if "iCloud" in g)
    ipucu = (
        "Korpus başka bir klasördeyse SORU_KESICI_KORPUS ile kökü belirtin."
    )
    if tahliye:
        ipucu = (
            f"{tahliye} belge iCloud'a tahliye edilmiş. İndirme denemesi "
            "(brctl download, cp, head) bu dosyalarda ASKIDA KALIR; korpusu "
            "iCloud dışı bir diskten geri getirmek gerekir."
        )
    raise KorpusEksik(
        f"Korpusun {len(sorunlu)}/{len(koleksiyon)} belgesi okunamıyor:\n"
        f"{dokum}\n{ipucu}"
    )


def kosu(secili=None, altin=True, kapsam=None):
    """Koleksiyonu koşar; her belge için önce/sonra karşılaştırma satırı
    döndürür. Dönüş: (satirlar, bulgular_var_mi)."""
    koleksiyon = _secili_koleksiyon(secili, kapsam=kapsam)
    _korpusu_dogrula(koleksiyon)
    satirlar = []
    regresyon = False
    esikler = _esikleri_oku()
    for oge in koleksiyon:
        m, kalite, sayim = _belge_kosusu(oge, altin=altin)
        onceki = _anlik_oku(oge.get("anlik"))
        onceki_anomali = (onceki.get("anomali_sayisi")
                          if onceki else None)
        simdi_anomali = m.get("anomali_sayisi", 0)
        durum = "ok"
        bulgular = _kayma_degerlendir(m, onceki)
        if onceki_anomali is not None and simdi_anomali > onceki_anomali:
            bulgular.insert(0, {
                "kod": "anomali-artis", "seviye": "kirmizi",
                "detay": f"{onceki_anomali} → {simdi_anomali}"})
        if any(b["seviye"] == "kirmizi" for b in bulgular):
            durum = "REGRESYON"
            regresyon = True
        elif any(b["seviye"] == "sari" for b in bulgular):
            durum = "dikkat"
        elif onceki_anomali is not None and simdi_anomali < onceki_anomali:
            durum = "iyilesme"
        satir = {"ad": oge["ad"],
                 "aile": oge.get("aile", "bilinmiyor"),
                 "katman": oge.get("katman", "bilinmiyor"),
                 "anomali": simdi_anomali,
                 "onceki_anomali": onceki_anomali,
                 "toplam_kutu": m.get("toplam_kutu"),
                 "onceki_kutu": onceki.get("toplam_kutu") if onceki else None,
                 "ham_aday": m.get("ham_aday"),
                 "incele_kuyrugu": m.get("incele_kuyrugu", 0),
                 "durum": durum,
                 "bulgular": bulgular,
                 "anomaliler": m.get("anomaliler", [])}
        if kalite and "f1" in kalite:
            satir["f1"] = round(kalite["f1"], 4)
            satir["precision"] = round(kalite.get("precision", 0), 4)
            satir["recall"] = round(kalite.get("recall", 0), 4)
        elif kalite and isinstance(kalite.get("final_cuts"), dict):
            # Golden-v2 nihai kesim metriklerini aynı özet sütununa taşı.
            nihai = kalite["final_cuts"]
            satir["f1"] = round(nihai.get("f1", 0), 4)
            satir["precision"] = round(nihai.get("precision", 0), 4)
            satir["recall"] = round(nihai.get("recall", 0), 4)
            satir["mean_iou"] = round(
                nihai.get("mean_matched_iou", 0), 4)
            siki = kalite.get("final_cuts_strict_iou")
            if isinstance(siki, dict):
                # Kesim sınırı kalitesi: IoU@0.5 doygunken asıl sinyal budur.
                satir["f1_siki"] = round(siki.get("f1", 0), 4)
        elif kalite and "hata" in kalite:
            # Altın değerlendirmesinin patlaması SESSİZ geçmez: bu yol, altın
            # kapısının tamamen devre dışı kalabileceği tek deliktir.
            satir["kalite_hatasi"] = kalite["hata"]
            satir["bulgular"].append({"kod": "altin-degerlendirme-hatasi",
                                      "seviye": "kirmizi",
                                      "detay": str(kalite["hata"])[:120]})
            satir["durum"] = "REGRESYON"
            regresyon = True
        if sayim and "hata" not in sayim:
            for alan in ("count_recall", "count_precision",
                         "count_recall_auto", "count_precision_auto",
                         "page_exact_rate"):
                satir[alan] = round(sayim[alan], 4)
            satir["sayim_sapmalari"] = sayim.get("worst_pages", [])
            satir["zero_pages"] = sayim.get("zero_pages", [])
            satir["pages_overlap_ratio"] = sayim.get("pages_overlap_ratio")
            if (sayim.get("pages_overlap_ratio") or 1.0) < 0.8:
                # Koşumun örneklemi altınınkinden kaymış: ölçüm birkaç sayfaya
                # düşmüş ve sayılar yanıltıcı derecede iyi görünebilir.
                # Sessiz geçerse "kusursuz" bir belge aslında ölçülmemiş olur.
                satir["bulgular"].append({
                    "kod": "sayim-ortusme-dusuk", "seviye": "kirmizi",
                    "detay": (f"{sayim['pages']}/{sayim['gold_pages']} altın "
                              f"sayfası ölçüldü — max_sayfa/bas/son ayarı "
                              f"altınla uyumsuz")})
                satir["durum"] = "REGRESYON"
                regresyon = True
            if sayim.get("zero_pages"):
                # Altında soru olan bir sayfada motorun HİÇ kutu üretmemesi
                # her zaman kırmızıdır: eşikten bağımsız, yapısal bir kayıp.
                satir["bulgular"].append({
                    "kod": "sayim-sifir-sayfa", "seviye": "kirmizi",
                    "detay": f"altında soru var, motor 0: {sayim['zero_pages']}"})
                satir["durum"] = "REGRESYON"
                regresyon = True
        elif sayim and "hata" in sayim:
            # Sessiz geçmez: sayım kapısının devre dışı kalabileceği tek delik.
            satir["bulgular"].append({
                "kod": "sayim-degerlendirme-hatasi", "seviye": "kirmizi",
                "detay": str(sayim["hata"])[:120]})
            satir["durum"] = "REGRESYON"
            regresyon = True

        # Ölçülen küme ile teslim edilen küme ayrışması: kapının bu sınıfı
        # göremediği dönemde cozumler1'de count_recall 0,845 raporlanırken
        # gerçek teslim 0,451'di. Artık ayrışma sayıyla raporlanıyor;
        # eşiği aşarsa kırmızı, altındaysa bilgi satırı olarak görünüyor.
        teslim = m.get("teslim") or {}
        if "hata" in teslim:
            satir["bulgular"].append({
                "kod": "teslim-olcumu-hatasi", "seviye": "sari",
                "detay": str(teslim["hata"])[:120]})
        elif teslim:
            satir["teslim_kutu"] = teslim["teslim_kutu"]
            satir["veto_sayfa"] = len(teslim["veto_sayfa"])
            kayip = teslim["kayip_kutu"]
            olculen = teslim["olculen_kutu"] or 1
            if kayip:
                oran = kayip / olculen
                seviye = "kirmizi" if oran > TESLIM_AYRISMA_ESIGI else "bilgi"
                satir["bulgular"].append({
                    "kod": "teslim-ayrismasi", "seviye": seviye,
                    "detay": (f"{kayip}/{teslim['olculen_kutu']} kutu "
                              f"({oran:.0%}) vetolu sayfalarda: ölçüm bunları "
                              f"sayıyor, teslim etmiyor — "
                              f"sayfalar {teslim['veto_sayfa'][:8]}")})
                if seviye == "kirmizi":
                    satir["durum"] = "REGRESYON"
                    regresyon = True
        altin_bulgular = _altin_kapisi(oge["ad"], satir, esikler)
        if altin_bulgular:
            satir["bulgular"].extend(altin_bulgular)
            if any(b["seviye"] == "kirmizi" for b in altin_bulgular):
                satir["durum"] = "REGRESYON"
                regresyon = True
        satirlar.append(satir)
    return satirlar, regresyon


def _aile_ozeti(satirlar):
    """Aile bazlı toplam — aynı kuralın ailelere ZIT etkisi ancak böyle görünür.

    Projenin dokümante edilmiş dersi: zincir çapası daraltması ygslys/aydin'da
    recall kazandırırken cozumler1'de count_recall'ü 1,00 → 0,475 yıktı. Belge
    bazlı tablo bunu gösterir ama 44 belgede gözden kaçar; aile satırı
    "bu değişiklik hangi kitap türüne yaradı, hangisine zarar verdi" sorusunu
    tek bakışta yanıtlar."""
    aileler = {}
    for s in satirlar:
        a = aileler.setdefault(s.get("aile", "bilinmiyor"), {
            "belge": 0, "regresyon": 0, "anomali": 0, "kutu": 0,
            "incele": 0, "sayR": [], "sayP": [], "oR": [], "f1": []})
        a["belge"] += 1
        a["regresyon"] += int(s["durum"] == "REGRESYON")
        a["anomali"] += s.get("anomali") or 0
        a["kutu"] += s.get("toplam_kutu") or 0
        a["incele"] += s.get("incele_kuyrugu") or 0
        for anahtar, kova in (("count_recall", "sayR"),
                              ("count_precision", "sayP"),
                              ("count_recall_auto", "oR"), ("f1", "f1")):
            if anahtar in s:
                a[kova].append(s[anahtar])
    for a in aileler.values():
        for kova in ("sayR", "sayP", "oR", "f1"):
            a[kova] = round(sum(a[kova]) / len(a[kova]), 4) if a[kova] else None
    return aileler


def _rapor_yaz(yol, satirlar, kapsam):
    veri = {"schema_version": "soru-kesici.kosum-raporu/v1",
            "kapsam": kapsam, "belge_sayisi": len(satirlar),
            "belgeler": satirlar, "aileler": _aile_ozeti(satirlar)}
    tam = yol if os.path.isabs(yol) else os.path.join(KOK, yol)
    os.makedirs(os.path.dirname(tam) or ".", exist_ok=True)
    with open(tam, "w", encoding="utf-8") as f:
        json.dump(veri, f, ensure_ascii=False, indent=1)
    return tam


def _kiyas_bas(yol, satirlar):
    """Önceki koşum raporuyla belge bazlı delta tablosu basar."""
    tam = yol if os.path.isabs(yol) else os.path.join(KOK, yol)
    if not os.path.exists(tam):
        print(f"kıyas atlandı: {yol} yok")
        return
    with open(tam, encoding="utf-8") as f:
        onceki = json.load(f)
    eski = {b["ad"]: b for b in onceki.get("belgeler", [])}
    olcutler = ("count_recall", "count_recall_auto", "count_precision",
                "f1", "f1_siki", "toplam_kutu")
    print(f"\n=== KIYAS: {yol} ===")
    basildi = False
    for s in satirlar:
        e = eski.get(s["ad"])
        if not e:
            print(f"  {s['ad']:14s} YENİ")
            basildi = True
            continue
        farklar = []
        for o in olcutler:
            a, b = e.get(o), s.get(o)
            if a is None or b is None or a == b:
                continue
            ok = "▲" if b > a else "▼"
            biçim = "d" if isinstance(b, int) else ".4f"
            farklar.append(f"{o} {a:{biçim}}→{b:{biçim}} {ok}")
        if farklar:
            print(f"  {s['ad']:14s} " + " | ".join(farklar))
            basildi = True
    if not basildi:
        print("  fark yok")


def _guncelle(secili=None, zorla=False):
    """once_*.json anlık görüntülerini mevcut çıktıyla tazeler.

    KAÇIŞ DELİĞİ KORUMASI: kırmızı bir kayma bulgusu varken snapshot tazelemek
    regresyonu kalıcı olarak gizler. Böyle bir belge `--zorla` verilmedikçe
    atlanır."""
    koleksiyon = _koleksiyon_oku(varsayilan=not bool(secili))
    if secili:
        koleksiyon = [o for o in koleksiyon if o["ad"] in set(secili)]
    for oge in koleksiyon:
        # _belge_kosusu (dogrula.metrikler değil): snapshot'a sayım
        # metrikleri de gömülsün ki bir sonraki koşum sayım gerilemesini
        # görebilsin. altin=False — pahalı kutu-altını değerlendirmesi
        # snapshot tazelemek için gereksiz.
        m, _kalite, _sayim = _belge_kosusu(oge, altin=False)
        if not oge.get("anlik"):
            print(f"  atlandı: {oge['ad']} için anlık yolu yok")
            continue
        bulgular = _kayma_degerlendir(m, _anlik_oku(oge.get("anlik")))
        kirmizi = [b for b in bulgular if b["seviye"] == "kirmizi"]
        if kirmizi and not zorla:
            kodlar = ", ".join(f"{b['kod']} ({b['detay']})" for b in kirmizi)
            print(f"  ATLANDI (kırmızı bulgu): {oge['ad']} — {kodlar}")
            print("           gerekçelendirip --zorla ile tazeleyin")
            continue
        hedef = os.path.join(KOK, oge["anlik"])
        with open(hedef, "w", encoding="utf-8") as f:
            json.dump(m, f, ensure_ascii=False, indent=1)
        print(f"  güncellendi: {oge['anlik']} (anomali={m['anomali_sayisi']})")


def _sha256_gecerli(deger):
    return (
        isinstance(deger, str)
        and len(deger) == 64
        and all(c in "0123456789abcdef" for c in deger)
    )


def _korpus_kimlikleri_gecerli(kimlikler):
    """Alt süreçten gelen korpus kanıtının kapalı şemasını doğrular."""
    if not isinstance(kimlikler, list):
        return False
    zorunlu = {
        "ad",
        "kaynak_sha256",
        "kaynak_boyut",
        "meta_sha256",
        "altin_sha256",
        "sayim_altin_sha256",
        "anlik_sha256",
        "kapi_esikleri_sha256",
    }
    adlar = []
    for kimlik in kimlikler:
        if not isinstance(kimlik, dict) or set(kimlik) != zorunlu:
            return False
        ad = kimlik.get("ad")
        if not isinstance(ad, str) or not ad:
            return False
        if not _sha256_gecerli(kimlik.get("kaynak_sha256")):
            return False
        boyut = kimlik.get("kaynak_boyut")
        if type(boyut) is not int or boyut < 0:
            return False
        if not _sha256_gecerli(kimlik.get("meta_sha256")):
            return False
        for alan in (
                "altin_sha256",
                "sayim_altin_sha256",
                "anlik_sha256",
                "kapi_esikleri_sha256"):
            deger = kimlik.get(alan)
            if deger is not None and not _sha256_gecerli(deger):
                return False
        adlar.append(ad)
    return len(adlar) == len(set(adlar)) and adlar == sorted(adlar)


def _sari_bulgu_var(satirlar):
    return any(
        satir.get("durum") == "dikkat"
        or any(
            isinstance(bulgu, dict) and bulgu.get("seviye") == "sari"
            for bulgu in satir.get("bulgular", ())
        )
        for satir in satirlar
        if isinstance(satir, dict)
    )


def _ikili_kol_calistir(
        durum, secili, cikti_yolu, kapsam=None, sert=False):
    """Tek A/B kolunu taze süreç ve boş soru-modeli cache'iyle çalıştırır."""
    import duzen_model

    acik = durum == "acik"
    if durum not in ("acik", "kapali"):
        raise ValueError(f"geçersiz A/B kolu: {durum}")
    etkin_sert = bool(sert or kapsam == "C")
    korpus_baslangic = _korpus_kimlikleri(secili, kapsam=kapsam)
    # Süreç zaten doğru env ile başlatıldı. Yine de modül içi zorlamayı açık
    # tutmak, ayar dosyasının sonucu değiştirmesini engeller. Genel DocLayout
    # AKTIF_ZORLA'ya dokunulmaz.
    duzen_model.SORU_MODEL_AKTIF_ZORLA = acik
    duzen_model._SORU_BOZUK = False
    duzen_model._SORU_PROBE_SONUC = None
    duzen_model._SORU_MANIFEST_CACHE = None
    duzen_model._SORU_SAYAC = 0
    duzen_model._SORU_GOZLENEN_KIMLIKLER.clear()
    duzen_model._soru_oldur()

    with tempfile.TemporaryDirectory(prefix=f"soru-ab-{durum}-") as cache:
        duzen_model.SORU_MODEL_CACHE_DIZIN = cache
        model_bilgisi = None
        beklenen_model_sha = None
        if acik:
            # Etkin symlink'i koşu başında bir kez çöz. Bu özel yollar,
            # soru_model_yollarini_esitle tarafından korunur ve A/B kolunun
            # ortasında yeni bir yayın yapılsa bile ölçüm tek sürümde kalır.
            donmus_model, donmus_manifest = (
                duzen_model.soru_model_yollarini_dondur())
            duzen_model.SORU_MODEL_YOLU = donmus_model
            duzen_model.SORU_MODEL_MANIFEST_YOLU = donmus_manifest
            duzen_model._SORU_MANIFEST_CACHE = None
            model_bilgisi = duzen_model.soru_modeli_dogrula(derin=True)
            if not model_bilgisi.get("ok"):
                raise RuntimeError(
                    "açık kol soru modeli derin probe başarısız: "
                    + str(model_bilgisi.get("mesaj"))
                )
            beklenen_model_sha = model_bilgisi.get("weights_sha256")
            if not beklenen_model_sha:
                raise RuntimeError("açık kol pinlenmiş model SHA-256 üretmedi")
        satirlar, motor_regresyonu = kosu(
            secili, altin=True, kapsam=kapsam)
        korpus_bitis = _korpus_kimlikleri(secili, kapsam=kapsam)
        if korpus_bitis != korpus_baslangic:
            raise RuntimeError(
                f"{durum} A/B kolunda korpus koşu sırasında değişti")
        satir_adlari = [
            satir.get("ad") for satir in satirlar
            if isinstance(satir, dict)
        ]
        korpus_adlari = [k["ad"] for k in korpus_baslangic]
        if (len(satir_adlari) != len(satirlar)
                or len(satir_adlari) != len(set(satir_adlari))
                or sorted(satir_adlari) != korpus_adlari):
            raise RuntimeError(
                f"{durum} A/B kolu sabitlenen korpusun tamamını ölçmedi")
        sari_bulgu = _sari_bulgu_var(satirlar)
        regresyon = bool(
            motor_regresyonu or (etkin_sert and sari_bulgu))
        istek_sayisi = int(duzen_model._SORU_SAYAC)
        isci_canli = bool(
            duzen_model._SORU_ISCI is not None
            and duzen_model._SORU_ISCI[0].poll() is None
        )
        isci_kimligi = duzen_model._SORU_ISCI_KIMLIK
        gozlenen_kimlikler = sorted(
            duzen_model._SORU_GOZLENEN_KIMLIKLER)
        if acik and (
                istek_sayisi <= 0
                or duzen_model._SORU_BOZUK
                or not isci_canli
                or isci_kimligi != beklenen_model_sha
                or gozlenen_kimlikler != [beklenen_model_sha]):
            raise RuntimeError(
                "açık kol soru modelini gerçekten kullanmadı "
                f"(istek={istek_sayisi}, bozuk={duzen_model._SORU_BOZUK}, "
                f"işçi_canlı={isci_canli}, işçi_sha={isci_kimligi}, "
                f"beklenen_sha={beklenen_model_sha}, "
                f"gözlenen_sha={gozlenen_kimlikler})"
            )
        if not acik and (
                istek_sayisi
                or isci_canli
                or isci_kimligi is not None
                or gozlenen_kimlikler):
            raise RuntimeError(
                "kapalı kol beklenmedik soru-modeli kullanımı yaptı: "
                f"istek={istek_sayisi}, işçi_canlı={isci_canli}, "
                f"işçi_sha={isci_kimligi}, gözlenen_sha={gozlenen_kimlikler}"
            )
        sonuc = {
            "durum": durum,
            "kapsam": kapsam,
            "sert": etkin_sert,
            "sari_bulgu": sari_bulgu,
            "regresyon": regresyon,
            "model": model_bilgisi,
            "soru_model_istek_sayisi": istek_sayisi,
            "soru_model_isci_canli": isci_canli,
            "soru_model_isci_sha256": isci_kimligi,
            "soru_model_gozlenen_sha256": gozlenen_kimlikler,
            "korpus_kimlikleri": korpus_baslangic,
            "satirlar": satirlar,
        }
        with open(cikti_yolu, "w", encoding="utf-8") as f:
            json.dump(sonuc, f, ensure_ascii=False, indent=1)
        duzen_model.kapat()
    return sonuc


def _ikili_kapi(tablo, meta, tolerans=1e-9):
    """Açık kolun kapalı kola göre kalite gerilemesini fail-closed ölçer."""
    bulgular = []
    meta = meta if isinstance(meta, dict) else {}
    kol_meta = {}
    for durum in ("kapali", "acik"):
        ham = meta.get(durum)
        if not isinstance(ham, dict):
            bulgular.append({
                "kod": f"{durum}-kol-meta-kaniti-gecersiz",
                "detay": f"{durum} kol metadata kaydı yok veya nesne değil",
            })
            ham = {}
        kol_meta[durum] = ham
        kol_regresyonu = ham.get("regresyon")
        if type(kol_regresyonu) is not bool:
            bulgular.append({
                "kod": f"{durum}-kol-regresyon-kaniti-gecersiz",
                "detay": (
                    f"{durum} kol regresyon alanı bulunmalı ve bool olmalı"),
            })
        elif kol_regresyonu:
            bulgular.append({
                "kod": f"{durum}-kol-mutlak-regresyon",
                "detay": (
                    f"{durum} kol kendi kalite kapısında REGRESYON bildirdi"),
            })
        kol_sert = ham.get("sert")
        if type(kol_sert) is not bool:
            bulgular.append({
                "kod": f"{durum}-kol-sert-kaniti-gecersiz",
                "detay": f"{durum} kol sert alanı bulunmalı ve bool olmalı",
            })
        sari_bulgu = ham.get("sari_bulgu")
        if type(sari_bulgu) is not bool:
            bulgular.append({
                "kod": f"{durum}-kol-sari-kaniti-gecersiz",
                "detay": (
                    f"{durum} kol sarı-bulgu alanı bulunmalı ve bool olmalı"),
            })
        elif kol_sert is True and sari_bulgu and kol_regresyonu is not True:
            bulgular.append({
                "kod": f"{durum}-kol-sert-regresyon-kaniti-tutarsiz",
                "detay": "sert kolda sarı bulgu regresyon sayılmadı",
            })

    kapali_meta = kol_meta["kapali"]
    acik_meta = kol_meta["acik"]
    if kapali_meta.get("kapsam") != acik_meta.get("kapsam"):
        bulgular.append({
            "kod": "kol-kapsami-uyusmaz",
            "detay": "kapalı ve açık kol aynı kapsamla çalışmadı",
        })
    kapsam = acik_meta.get("kapsam")
    if kapsam not in (None, *KAPSAM_KATMANLARI):
        bulgular.append({
            "kod": "kol-kapsami-gecersiz",
            "detay": f"geçersiz A/B kapsam kanıtı: {kapsam!r}",
        })
    if (kapali_meta.get("sert") is not acik_meta.get("sert")
            or (kapsam == "C" and (
                kapali_meta.get("sert") is not True
                or acik_meta.get("sert") is not True))):
        bulgular.append({
            "kod": "kol-sert-semantigi-uyusmaz",
            "detay": (
                "iki kol aynı sert semantiğiyle çalışmadı veya C sert değil"),
        })

    model = acik_meta.get("model")
    beklenen_sha = (
        model.get("weights_sha256") if isinstance(model, dict) else None)
    istek_sayisi = acik_meta.get("soru_model_istek_sayisi")
    if not (
            isinstance(model, dict)
            and model.get("ok") is True
            and type(istek_sayisi) is int
            and istek_sayisi > 0
            and acik_meta.get("soru_model_isci_canli") is True
            and _sha256_gecerli(beklenen_sha)
            and acik_meta.get("soru_model_isci_sha256") == beklenen_sha
            and acik_meta.get("soru_model_gozlenen_sha256")
                == [beklenen_sha]):
        bulgular.append({
            "kod": "acik-kol-model-kaniti-yok",
            "detay": (
                "derin probe + gerçek istek + canlı işçi + tek pinlenmiş SHA "
                "birlikte kanıtlanmadı"),
        })
    kapali_istek = kapali_meta.get("soru_model_istek_sayisi")
    if not (
            kapali_meta.get("model") is None
            and type(kapali_istek) is int
            and kapali_istek == 0
            and kapali_meta.get("soru_model_isci_canli") is False
            and kapali_meta.get("soru_model_isci_sha256") is None
            and kapali_meta.get("soru_model_gozlenen_sha256") == []):
        bulgular.append({
            "kod": "kapali-kol-model-kaniti-yok",
            "detay": (
                "kapalı kolda soru modelinin hiç kullanılmadığı kanıtlanmadı"),
        })

    korpus_kimlikleri = {}
    for durum in ("kapali", "acik"):
        kimlikler = kol_meta[durum].get("korpus_kimlikleri")
        if not _korpus_kimlikleri_gecerli(kimlikler):
            bulgular.append({
                "kod": f"{durum}-kol-korpus-kaniti-gecersiz",
                "detay": f"{durum} kol içerik-SHA korpus kanıtı geçersiz",
            })
            continue
        korpus_kimlikleri[durum] = kimlikler
        tablo_kolu = tablo.get(durum)
        sonuc_adlari = (
            set(tablo_kolu) if isinstance(tablo_kolu, dict) else set())
        kimlik_adlari = {k["ad"] for k in kimlikler}
        if sonuc_adlari != kimlik_adlari:
            bulgular.append({
                "kod": f"{durum}-kol-sonuc-korpus-uyusmaz",
                "detay": (
                    f"{durum} kol sonuçları sabitlenen korpusla eşleşmiyor"),
            })
    if (
            set(korpus_kimlikleri) == {"kapali", "acik"}
            and korpus_kimlikleri["kapali"] != korpus_kimlikleri["acik"]):
        bulgular.append({
            "kod": "korpus-kimligi-uyusmaz",
            "detay": (
                "aynı mantıksal belge adlarında kaynak/altın/metadata SHA "
                "kimlikleri farklı"),
        })

    yuksek_iyi = (
        "f1",
        "f1_siki",
        "precision",
        "recall",
        "count_recall",
        "count_precision",
        "count_recall_auto",
        "count_precision_auto",
        "page_exact_rate",
    )
    kapali_tablo = (
        tablo.get("kapali") if isinstance(tablo.get("kapali"), dict) else {})
    acik_tablo = (
        tablo.get("acik") if isinstance(tablo.get("acik"), dict) else {})
    ortak_belgeler = sorted(set(kapali_tablo) & set(acik_tablo))
    if set(kapali_tablo) != set(acik_tablo):
        bulgular.append({
            "kod": "belge-kumesi-uyusmaz",
            "detay": (
                "kapalı ve açık A/B kolları aynı belge korpusunu kullanmadı"),
        })
    if not ortak_belgeler:
        bulgular.append({
            "kod": "ortak-belge-yok",
            "detay": "iki A/B kolunda ortak belge bulunamadı",
        })
    karsilastirilan = 0
    for ad in ortak_belgeler:
        kapali = kapali_tablo[ad]
        acik = acik_tablo[ad]
        if (kapali.get("durum") != "REGRESYON"
                and acik.get("durum") == "REGRESYON"):
            bulgular.append({
                "kod": "acik-kol-regresyon",
                "detay": ad,
            })
        eski_anomali, yeni_anomali = kapali.get("anomali"), acik.get("anomali")
        if (eski_anomali is not None and yeni_anomali is not None
                and yeni_anomali > eski_anomali):
            bulgular.append({
                "kod": "anomali-artisi",
                "detay": f"{ad}: {eski_anomali} → {yeni_anomali}",
            })
            karsilastirilan += 1
        for olcut in yuksek_iyi:
            eski, yeni = kapali.get(olcut), acik.get(olcut)
            if eski is None or yeni is None:
                continue
            karsilastirilan += 1
            if yeni < eski - tolerans:
                bulgular.append({
                    "kod": f"{olcut}-gerilemesi",
                    "detay": f"{ad}: {eski:.6f} → {yeni:.6f}",
                })
    if karsilastirilan == 0:
        bulgular.append({
            "kod": "kalite-olcumu-yok",
            "detay": "A/B kollarında karşılaştırılabilir altın/sayım metriği yok",
        })
    return bulgular


def _ikili_kosu(secili=None, kapsam=None, sert=False):
    """Soru modeli açık/kapalı kollarını ayrı, temiz alt süreçlerde koşar."""
    etkin_sert = bool(sert or kapsam == "C")
    beklenen_korpus = _korpus_kimlikleri(secili, kapsam=kapsam)
    tablo = {"kapali": {}, "acik": {}}
    meta = {}
    with tempfile.TemporaryDirectory(prefix="soru-ikili-") as gecici:
        for durum, deger in (("kapali", "0"), ("acik", "1")):
            cikti = os.path.join(gecici, durum + ".json")
            komut = [
                sys.executable,
                os.path.abspath(__file__),
                "--ikili-kol",
                durum,
                "--ikili-cikti",
                cikti,
            ]
            if secili:
                komut.extend(["--sadece", *secili])
            if kapsam:
                komut.extend(["--kapsam", kapsam])
            if etkin_sert:
                komut.append("--sert")
            ortam = dict(os.environ)
            ortam["SORU_KESICI_SORU_MODELI"] = deger
            sonuc = subprocess.run(
                komut,
                capture_output=True,
                text=True,
                timeout=3600,
                env=ortam,
                check=False,
            )
            if sonuc.returncode != 0 or not os.path.isfile(cikti):
                detay = (sonuc.stderr or sonuc.stdout or "").strip()[-2000:]
                raise RuntimeError(
                    f"{durum} A/B alt süreci başarısız "
                    f"(kod={sonuc.returncode}): {detay}"
                )
            with open(cikti, encoding="utf-8") as f:
                kol = json.load(f)
            anlik_korpus = _korpus_kimlikleri(secili, kapsam=kapsam)
            if anlik_korpus != beklenen_korpus:
                raise RuntimeError(
                    f"{durum} A/B kolunda korpus süreçler arasında değişti")
            if kol.get("korpus_kimlikleri") != beklenen_korpus:
                raise RuntimeError(
                    f"{durum} A/B kolunun korpus SHA kanıtı beklenenle uyuşmuyor")
            if kol.get("durum") != durum:
                raise RuntimeError(
                    f"{durum} A/B kolu yanlış kol kimliği bildirdi")
            if kol.get("kapsam") != kapsam:
                raise RuntimeError(
                    f"{durum} A/B kolu yanlış kapsam bildirdi")
            if (type(kol.get("sert")) is not bool
                    or kol["sert"] is not etkin_sert):
                raise RuntimeError(
                    f"{durum} A/B kolu yanlış sert semantiği bildirdi")
            meta[durum] = {
                "regresyon": kol.get("regresyon"),
                "sert": kol.get("sert"),
                "sari_bulgu": kol.get("sari_bulgu"),
                "model": kol.get("model"),
                "soru_model_istek_sayisi":
                    kol.get("soru_model_istek_sayisi"),
                "soru_model_isci_canli": kol.get("soru_model_isci_canli"),
                "soru_model_isci_sha256":
                    kol.get("soru_model_isci_sha256"),
                "soru_model_gozlenen_sha256":
                    kol.get("soru_model_gozlenen_sha256"),
                "korpus_kimlikleri": kol.get("korpus_kimlikleri"),
                "kapsam": kol.get("kapsam"),
            }
            satirlar = kol.get("satirlar")
            if not isinstance(satirlar, list):
                raise RuntimeError(f"{durum} A/B kolu sonuç listesi üretmedi")
            satir_adlari = [
                s.get("ad") for s in satirlar if isinstance(s, dict)]
            if (len(satir_adlari) != len(satirlar)
                    or any(
                        not isinstance(ad, str) or not ad
                        for ad in satir_adlari)
                    or len(satir_adlari) != len(set(satir_adlari))):
                raise RuntimeError(
                    f"{durum} A/B kolu geçersiz/yinelenen belge sonucu üretti")
            tablo[durum] = {
                s["ad"]: {k: s[k] for k in (
                    "durum",
                    "anomali",
                    "toplam_kutu",
                    "f1",
                    "f1_siki",
                    "precision",
                    "recall",
                    "count_recall",
                    "count_precision",
                    "count_recall_auto",
                    "count_precision_auto",
                    "page_exact_rate",
                ) if k in s}
                for s in satirlar
            }
    bulgular = _ikili_kapi(tablo, meta)
    tablo["_meta"] = {
        "ok": not bulgular,
        "regresyon": bool(bulgular),
        "bulgular": bulgular,
        "kollar": meta,
    }
    return tablo


def main(argv=None):
    p = argparse.ArgumentParser(description="Kalite regresyon koşumu")
    p.add_argument("--sadece", nargs="+", metavar="AD",
                   help="yalnız bu belge kimliklerini koş")
    p.add_argument("--guncelle", action="store_true",
                   help="once_*.json anlık görüntülerini tazele")
    p.add_argument("--ikili", action="store_true",
                   help="soru modeli açık/kapalı karşılaştırması")
    p.add_argument("--ikili-kol", choices=("acik", "kapali"),
                   help=argparse.SUPPRESS)
    p.add_argument("--ikili-cikti", help=argparse.SUPPRESS)
    p.add_argument("--altinsiz", action="store_true",
                   help="golden F1 değerlendirmesini atla")
    p.add_argument("--sert", action="store_true",
                   help="sarı (dikkat) bulguları da başarısızlık say")
    p.add_argument("--zorla", action="store_true",
                   help="--guncelle: kırmızı bulguya rağmen snapshot tazele")
    p.add_argument("--kapsam", choices=sorted(KAPSAM_KATMANLARI),
                   help="A=kapı katmanı, B=tam korpus, C=yayın (holdout dahil)")
    p.add_argument("--rapor", metavar="YOL",
                   help="koşum sonucunu JSON olarak yaz")
    p.add_argument("--kiyas", metavar="YOL",
                   help="önceki --rapor çıktısıyla delta tablosu bas")
    args = p.parse_args(argv)
    if args.kapsam == "C" and not args.sert:
        # Yayın katmanı holdout'u içerir; orada sarı bulgu tolere edilemez.
        args.sert = True

    if args.guncelle:
        _guncelle(args.sadece, zorla=args.zorla)
        return 0
    if args.ikili_kol:
        if not args.ikili_cikti:
            p.error("--ikili-kol için --ikili-cikti gerekli")
        _ikili_kol_calistir(
            args.ikili_kol,
            args.sadece,
            os.path.abspath(args.ikili_cikti),
            kapsam=args.kapsam,
            sert=args.sert,
        )
        return 0
    if args.ikili:
        tablo = _ikili_kosu(
            args.sadece, kapsam=args.kapsam, sert=args.sert)
        print(json.dumps(tablo, ensure_ascii=False, indent=1))
        return 1 if tablo["_meta"]["regresyon"] else 0

    satirlar, regresyon = kosu(args.sadece, altin=not args.altinsiz,
                               kapsam=args.kapsam)
    print(f"{'BELGE':14s} {'ANOMALİ':>10s} {'KUTU':>10s} {'ADAY':>6s} "
          f"{'İNCELE':>7s} {'sayR':>6s} {'sayP':>6s} {'oR':>6s} "
          f"{'F1':>7s} {'F1@.75':>7s}  DURUM")
    sari_var = False
    for s in satirlar:
        onc = s["onceki_anomali"]
        anomali = (f"{s['anomali']}" if onc is None
                   else f"{s['anomali']}({onc:+d})".replace("(+", "(=")
                   if s['anomali'] == onc else f"{s['anomali']}(was {onc})")
        kutu = str(s["toplam_kutu"])
        if s.get("onceki_kutu") not in (None, s["toplam_kutu"]):
            kutu = f"{s['toplam_kutu']}(was {s['onceki_kutu']})"
        f1 = f"{s['f1']:.3f}" if "f1" in s else "—"
        f1s = f"{s['f1_siki']:.3f}" if "f1_siki" in s else "—"
        say_r = f"{s['count_recall']:.3f}" if "count_recall" in s else "—"
        say_p = (f"{s['count_precision']:.3f}"
                 if "count_precision" in s else "—")
        oto_r = (f"{s['count_recall_auto']:.3f}"
                 if "count_recall_auto" in s else "—")
        isaret = {"REGRESYON": "🔴", "iyilesme": "🟢",
                  "dikkat": "🟡", "ok": "  "}[s["durum"]]
        print(f"{s['ad']:14s} {anomali:>10s} "
              f"{kutu:>10s} {str(s.get('ham_aday') or '—'):>6s} "
              f"{str(s['incele_kuyrugu']):>7s} "
              f"{say_r:>6s} {say_p:>6s} {oto_r:>6s} "
              f"{f1:>7s} {f1s:>7s}  {isaret} {s['durum']}")
        for b in s.get("bulgular", ()):
            if b["seviye"] == "sari":
                sari_var = True
            im = {"kirmizi": "🔴", "sari": "🟡", "bilgi": "ℹ️"}[b["seviye"]]
            print(f"{'':14s}   {im} {b['kod']}: {b['detay']}")
    if len(satirlar) > 3:
        print(f"\n{'AİLE':16s} {'BELGE':>5s} {'🔴':>3s} {'KUTU':>7s} "
              f"{'İNCELE':>7s} {'sayR':>6s} {'sayP':>6s} {'oR':>6s} {'F1':>7s}")
        for aile, a in sorted(_aile_ozeti(satirlar).items()):
            def _f(v):
                return f"{v:.3f}" if isinstance(v, float) else "—"
            print(f"{aile:16s} {a['belge']:>5d} {a['regresyon']:>3d} "
                  f"{a['kutu']:>7d} {a['incele']:>7d} "
                  f"{_f(a['sayR']):>6s} {_f(a['sayP']):>6s} "
                  f"{_f(a['oR']):>6s} {_f(a['f1']):>7s}")

    if args.kiyas:
        _kiyas_bas(args.kiyas, satirlar)
    if args.rapor:
        print(f"\nrapor yazıldı: {_rapor_yaz(args.rapor, satirlar, args.kapsam)}")

    print(f"\nSonuç: {'❌ REGRESYON VAR' if regresyon else '✅ regresyon yok'}")
    if regresyon:
        return 1
    return 1 if (args.sert and sari_var) else 0


if __name__ == "__main__":
    sys.exit(main())
