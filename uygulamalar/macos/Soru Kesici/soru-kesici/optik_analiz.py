#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik sınav puanlama ve analiz — yalnız stdlib (+fitz karne için).

Puanlama: net = D − Y/4 (YKS), D − Y/3 (LGS) veya cezasız; ders bazında.
Kitapçık türü başına ayrı cevap anahtarı; çoklu doğru ("AB") desteklenir;
boş anahtar ("") soruyu değerlendirme dışı bırakır (iptal edilen soru).
Çoklu kodlanan cevap YANLIŞ sayılır (Türk optik geleneği), "belirsiz"
hüküm boş sayılır ve sonuçta işaretlenir (inceleme ekranı çözmelidir).

Madde analizi (Remark/ExamSoft standardı): p (güçlük), ayırt edicilik
(üst-alt %27), madde-toplam nokta-çiftserili korelasyon, çeldirici
dağılımı (<%5 işlevsiz çeldirici uyarısı), KR-20, dağılım istatistikleri.
"""
import csv
import math
import os

import optik_sema as osm

VARSAYILAN_BOLEN = {"yanlis_boler": 0}


# ------------------------------------------------------------------- puanlama

def _ogrenci_anahtari(kagit, sira):
    if kagit.get("ogrenci_no"):
        return "no:" + kagit["ogrenci_no"]
    if kagit.get("ad_soyad"):
        return "ad:" + kagit["ad_soyad"]
    return f"kagit:{kagit.get('id', sira)}"


def ogrencileri_grupla(kagitlar):
    """Sayfa kayıtlarını öğrenci başına birleştirir (çok sayfalı formlar).

    Dönüş: [{"ogrenci_no","ad_soyad","kitapcik","kagit_idler",
             "cevaplar","sorunlar"}]"""
    gruplar = {}
    for sira, k in enumerate(kagitlar):
        if k.get("durum") == "hatali":
            continue
        anahtar = _ogrenci_anahtari(k, sira)
        g = gruplar.setdefault(anahtar, {
            "ogrenci_no": k.get("ogrenci_no"),
            "ad_soyad": k.get("ad_soyad"),
            "kitapcik": None, "kagit_idler": [], "cevaplar": {},
            "sorunlar": []})
        g["kagit_idler"].append(k.get("id"))
        g["ad_soyad"] = g["ad_soyad"] or k.get("ad_soyad")
        if k.get("kitapcik"):
            if g["kitapcik"] and g["kitapcik"] != k["kitapcik"]:
                g["sorunlar"].append("sayfalar arasında kitapçık çelişkisi")
            g["kitapcik"] = g["kitapcik"] or k["kitapcik"]
        for ders, sorular in (k.get("cevaplar") or {}).items():
            hedef = g["cevaplar"].setdefault(ders, {})
            for no, cevap in sorular.items():
                if no in hedef and hedef[no].get("sembol") != \
                        cevap.get("sembol"):
                    g["sorunlar"].append(f"{ders} {no}: sayfa çakışması")
                hedef[no] = cevap
        if k.get("durum") == "incelenecek":
            g["sorunlar"].append("incelenmemiş kağıt içeriyor")
    return list(gruplar.values())


def _anahtar_sec(anahtarlar, kitapcik):
    if not anahtarlar:
        return None
    if kitapcik and kitapcik in anahtarlar:
        return anahtarlar[kitapcik]
    if len(anahtarlar) == 1:
        return next(iter(anahtarlar.values()))
    return None


def puanla(kagitlar, anahtarlar, kural=None, sablon=None):
    """Kağıt kayıtları + anahtarlar → öğrenci sonuçları.

    kural: {"yanlis_boler": 0|3|4}. Dönüş: [OgrenciSonuc]; sonuçlar
    toplam nete göre sıralı (sira alanı doldurulur).
    """
    kural = dict(VARSAYILAN_BOLEN, **(kural or {}))
    bolen = int(kural.get("yanlis_boler") or 0)
    sonuclar = []
    for g in ogrencileri_grupla(kagitlar):
        anahtar = _anahtar_sec(anahtarlar, g["kitapcik"])
        sonuc = {"ogrenci_no": g["ogrenci_no"], "ad_soyad": g["ad_soyad"],
                 "kitapcik": g["kitapcik"], "kagit_idler": g["kagit_idler"],
                 "dersler": {}, "sorunlar": list(g["sorunlar"])}
        if anahtar is None:
            sonuc["sorunlar"].append(
                "cevap anahtarı yok" if not anahtarlar
                else f"kitapçık {g['kitapcik'] or '?'} anahtarı yok")
        t_dogru = t_yanlis = t_bos = t_soru = 0
        t_net = 0.0
        for ders, sorular in sorted(g["cevaplar"].items()):
            d_anahtar = (anahtar or {}).get(ders) or {}
            dsonuc = {"dogru": 0, "yanlis": 0, "bos": 0, "iptal_soru": 0,
                      "net": 0.0, "soru": 0, "sorular": {}}
            for no, cevap in sorted(sorular.items(), key=lambda t:
                                    int(t[0])):
                dogru_cevap = d_anahtar.get(no)
                verilen = cevap.get("sembol")
                hukum = cevap.get("hukum")
                if anahtar is not None and not dogru_cevap:
                    karar = "iptal"          # anahtarsız/iptal soru: dışı
                    dsonuc["iptal_soru"] += 1
                elif anahtar is None:
                    karar = "anahtarsiz"
                elif hukum == "coklu":
                    karar = "yanlis"
                elif hukum in ("bos", "belirsiz") or not verilen:
                    karar = "bos"
                elif verilen in dogru_cevap:
                    karar = "dogru"
                else:
                    karar = "yanlis"
                dsonuc["sorular"][no] = {
                    "verilen": verilen, "hukum": hukum,
                    "dogru_cevap": dogru_cevap, "sonuc": karar}
                if karar in ("dogru", "yanlis", "bos"):
                    dsonuc["soru"] += 1
                    dsonuc[karar] += 1
            if bolen:
                dsonuc["net"] = round(
                    dsonuc["dogru"] - dsonuc["yanlis"] / bolen, 3)
            else:
                dsonuc["net"] = float(dsonuc["dogru"])
            sonuc["dersler"][ders] = dsonuc
            t_dogru += dsonuc["dogru"]
            t_yanlis += dsonuc["yanlis"]
            t_bos += dsonuc["bos"]
            t_soru += dsonuc["soru"]
            t_net += dsonuc["net"]
        sonuc["toplam"] = {
            "dogru": t_dogru, "yanlis": t_yanlis, "bos": t_bos,
            "soru": t_soru, "net": round(t_net, 3),
            "yuzde": round(100.0 * t_dogru / t_soru, 1) if t_soru else 0.0}
        sonuclar.append(sonuc)
    sonuclar.sort(key=lambda s: -s["toplam"]["net"])
    for i, s in enumerate(sonuclar):
        s["sira"] = i + 1
    return sonuclar


# --------------------------------------------------------------- madde analizi

def _ortalama(dizi):
    return sum(dizi) / len(dizi) if dizi else 0.0


def _std_pop(dizi):
    if len(dizi) < 2:
        return 0.0
    ort = _ortalama(dizi)
    return math.sqrt(sum((x - ort) ** 2 for x in dizi) / len(dizi))


def madde_analizi(sonuclar, anahtarlar, sablon=None):
    """Soru başına p, ayırt edicilik, nokta-çiftserili + çeldirici tablosu.

    Yalnız anahtarı olan öğrenciler dahil edilir. Dönüş:
    {"sorular": [...], "test": {kr20, alfa (=kr20), ortalama, ss, ...}}"""
    katilan = [s for s in sonuclar
               if not any("anahtarı yok" in p or p == "cevap anahtarı yok"
                          for p in s["sorunlar"])]
    if not katilan:
        return {"sorular": [], "test": {"katilimci": 0}}
    toplamlar = [s["toplam"]["dogru"] for s in katilan]
    n = len(katilan)
    ss = _std_pop(toplamlar)
    dilim = max(1, int(round(n * 0.27)))
    siralanmis = sorted(katilan, key=lambda s: -s["toplam"]["dogru"])
    ust, alt = siralanmis[:dilim], siralanmis[-dilim:]

    soru_listesi = []
    pq_toplam = 0.0
    for ders in sorted({d for s in katilan for d in s["dersler"]}):
        nolar = sorted({no for s in katilan
                        for no in s["dersler"].get(ders, {})
                        .get("sorular", {})}, key=int)
        for no in nolar:
            def _soru(s):
                return s["dersler"].get(ders, {}).get("sorular", {}) \
                    .get(no)
            kayitlar = [(_soru(s), s["toplam"]["dogru"])
                        for s in katilan if _soru(s)]
            gecerli = [(q, t) for q, t in kayitlar
                       if q["sonuc"] in ("dogru", "yanlis", "bos")]
            if not gecerli:
                continue
            dogru = [1 if q["sonuc"] == "dogru" else 0
                     for q, _ in gecerli]
            p = _ortalama(dogru)
            q_oran = 1.0 - p
            pq_toplam += p * q_oran
            # ayırt edicilik: üst-alt %27 doğruluk farkı
            def _oran(grup):
                dizi = [1 if (_soru(s) or {}).get("sonuc") == "dogru"
                        else 0 for s in grup if _soru(s)]
                return _ortalama(dizi) if dizi else 0.0
            ayirt = round(_oran(ust) - _oran(alt), 3)
            # nokta-çiftserili
            rpb = 0.0
            if 0 < p < 1 and ss > 0:
                m1 = _ortalama([t for (q, t), d in zip(gecerli, dogru)
                                if d])
                m0 = _ortalama([t for (q, t), d in zip(gecerli, dogru)
                                if not d])
                rpb = round((m1 - m0) / ss * math.sqrt(p * q_oran), 3)
            # çeldirici dağılımı
            dagilim = {}
            for q, _ in gecerli:
                etiket = q["verilen"] or ("çoklu" if q["hukum"] == "coklu"
                                          else "boş")
                if q["hukum"] == "coklu":
                    etiket = "çoklu"
                elif not q["verilen"]:
                    etiket = "boş"
                dagilim[etiket] = dagilim.get(etiket, 0) + 1
            dogru_cevap = gecerli[0][0]["dogru_cevap"]
            uyarilar = []
            if ayirt < 0.1:
                uyarilar.append("düşük ayırt edicilik")
            if rpb < 0:
                uyarilar.append("negatif korelasyon — anahtar hatalı olabilir")
            for sembol, adet in dagilim.items():
                if sembol not in ("boş", "çoklu") and dogru_cevap \
                        and sembol not in dogru_cevap \
                        and adet / len(gecerli) < 0.05 and len(gecerli) >= 20:
                    uyarilar.append(f"işlevsiz çeldirici: {sembol}")
            soru_listesi.append({
                "ders": ders, "soru": no, "dogru_cevap": dogru_cevap,
                "katilimci": len(gecerli), "p": round(p, 3),
                "ayirt_edicilik": ayirt, "nokta_ciftserili": rpb,
                "dagilim": dagilim, "uyarilar": uyarilar})

    k = len(soru_listesi)
    varyans = ss ** 2
    kr20 = None
    if k >= 2 and varyans > 0:
        kr20 = round(k / (k - 1) * (1 - pq_toplam / varyans), 3)
    netler = [s["toplam"]["net"] for s in katilan]
    test = {"katilimci": n, "soru": k, "kr20": kr20,
            "ortalama_dogru": round(_ortalama(toplamlar), 2),
            "ortalama_net": round(_ortalama(netler), 2),
            "ss": round(ss, 2),
            "en_yuksek_net": max(netler) if netler else 0,
            "en_dusuk_net": min(netler) if netler else 0}
    return {"sorular": soru_listesi, "test": test}


# -------------------------------------------------------------- kazanım analizi

def kazanim_csv_oku(yol):
    """CSV (ders,soru,kazanim başlıklı; , veya ; ayraçlı) →
    {ders: {soru_no(str): kazanım}}"""
    with open(yol, encoding="utf-8-sig") as f:
        ham = f.read()
    ayrac = ";" if ham.count(";") > ham.count(",") else ","
    sonuc = {}
    okuyucu = csv.reader(ham.splitlines(), delimiter=ayrac)
    satirlar = list(okuyucu)
    if satirlar and satirlar[0] and \
            satirlar[0][0].strip().lower() in ("ders", "bölüm", "bolum"):
        satirlar = satirlar[1:]
    for satir in satirlar:
        if len(satir) < 3 or not satir[2].strip():
            continue
        ders = satir[0].strip()
        try:
            no = str(int(satir[1].strip()))
        except ValueError:
            continue
        sonuc.setdefault(ders, {})[no] = satir[2].strip()
    return sonuc


def kazanim_analizi(sonuclar, kazanimlar, kitapcik_sira=None):
    """Öğrenci ve sınıf düzeyinde kazanım başarısı.

    kitapcik_sira: {harf: [kanonik_no, ...]} — sınav optik_koprusu ile
    üretildiyse B/C/D kitapçığındaki soru numarası kanonik (A) numaraya
    çevrilerek kazanım bulunur (kazanım eşlemesi kanonik numaradadır).
    Dönüş: {"kazanimlar": [{kazanim, ders, sorular, dogru, yanlis, bos,
    yuzde}], "ogrenciler": {ogrenci_anahtar: [{kazanim, dogru, ...}]}}"""
    havuz = {}
    ogrenci_havuz = {}
    for s in sonuclar:
        anahtar = s.get("ogrenci_no") or s.get("ad_soyad") or "?"
        ceviri = (kitapcik_sira or {}).get(s.get("kitapcik") or "")
        for ders, dsonuc in s["dersler"].items():
            ders_kazanim = kazanimlar.get(ders) or {}
            for no, q in dsonuc["sorular"].items():
                kanonik = no
                if ceviri:
                    try:
                        idx = int(no) - 1
                        if 0 <= idx < len(ceviri):
                            kanonik = str(ceviri[idx])
                    except (ValueError, TypeError):
                        pass
                kazanim = ders_kazanim.get(kanonik)
                if not kazanim or q["sonuc"] not in ("dogru", "yanlis",
                                                     "bos"):
                    continue
                for hedef, kimlik in ((havuz, None),
                                      (ogrenci_havuz, anahtar)):
                    kk = (kazanim, ders) if kimlik is None else \
                        (kimlik, kazanim, ders)
                    kayit = hedef.setdefault(kk, {
                        "kazanim": kazanim, "ders": ders, "sorular": set(),
                        "dogru": 0, "yanlis": 0, "bos": 0})
                    kayit["sorular"].add(kanonik)
                    kayit[q["sonuc"]] += 1

    def _bicimle(kayit):
        toplam = kayit["dogru"] + kayit["yanlis"] + kayit["bos"]
        return {**kayit, "sorular": sorted(kayit["sorular"], key=int),
                "yuzde": round(100.0 * kayit["dogru"] / toplam, 1)
                if toplam else 0.0}

    ogrenciler = {}
    for (kimlik, _, _), kayit in ogrenci_havuz.items():
        ogrenciler.setdefault(kimlik, []).append(_bicimle(kayit))
    return {"kazanimlar": sorted((_bicimle(k) for k in havuz.values()),
                                 key=lambda k: k["yuzde"]),
            "ogrenciler": ogrenciler}


# ------------------------------------------------------------------ dışa aktarım

def disa_csv(sonuclar, yol):
    """Excel-TR dostu (UTF-8-sig, ;) sonuç tablosu."""
    dersler = sorted({d for s in sonuclar for d in s["dersler"]})
    with open(yol, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        baslik = ["Sıra", "Öğrenci No", "Adı Soyadı", "Kitapçık"]
        for ders in dersler:
            ad = ders or "Genel"
            baslik += [f"{ad} D", f"{ad} Y", f"{ad} B", f"{ad} Net"]
        baslik += ["Toplam D", "Toplam Y", "Toplam B", "Toplam Net",
                   "Yüzde", "Sorunlar"]
        w.writerow(baslik)
        for s in sonuclar:
            satir = [s.get("sira"), s.get("ogrenci_no") or "",
                     s.get("ad_soyad") or "", s.get("kitapcik") or ""]
            for ders in dersler:
                d = s["dersler"].get(ders)
                satir += ([d["dogru"], d["yanlis"], d["bos"],
                           _sayi(d["net"])] if d else ["", "", "", ""])
            t = s["toplam"]
            satir += [t["dogru"], t["yanlis"], t["bos"], _sayi(t["net"]),
                      _sayi(t["yuzde"]), " | ".join(s["sorunlar"])]
            w.writerow(satir)
    return yol


def _sayi(v):
    """Excel-TR ondalık virgül."""
    return str(v).replace(".", ",")


def disa_txt(sonuclar, yol, sablon=None):
    """Klasik sabit genişlikli optik TXT (k12 tarzı analiz araçları okur).

    Düzen: öğrenci no (10, sola) + ad soyad (25) + kitapçık (1) +
    ders sırasına göre cevap harfleri (boş=boşluk)."""
    dersler = sorted({d for s in sonuclar for d in s["dersler"]})
    with open(yol, "w", encoding="utf-8") as f:
        for s in sonuclar:
            parcalar = [
                (s.get("ogrenci_no") or "").ljust(10)[:10],
                (s.get("ad_soyad") or "").ljust(25)[:25],
                (s.get("kitapcik") or " ")[:1]]
            for ders in dersler:
                d = s["dersler"].get(ders)
                if not d:
                    continue
                nolar = sorted(d["sorular"], key=int)
                parcalar.append("".join(
                    (d["sorular"][no]["verilen"] or " ")[:1]
                    for no in nolar))
            f.write("".join(parcalar) + "\n")
    return yol


def disa_eokul(sonuclar, yol, tam_puan=100.0):
    """e-Okul'a yapıştırmaya uygun: no;puan (yüzde üzerinden)."""
    with open(yol, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["Öğrenci No", "Puan"])
        for s in sonuclar:
            t = s["toplam"]
            puan = round(tam_puan * t["dogru"] / t["soru"], 1) \
                if t["soru"] else 0.0
            w.writerow([s.get("ogrenci_no") or "", _sayi(puan)])
    return yol


# ------------------------------------------------------------------------ karne

def karne_pdf(sonuclar, yol, sinav_ad="", kurum="", kazanim=None):
    """Öğrenci başına tek sayfalık karne PDF'i (fitz)."""
    import fitz
    import yazi_tipi
    A4 = fitz.paper_rect("a4")
    KENAR = 42
    ff = yazi_tipi.ttf_yolu()
    ad = "tur" if ff else "helv"

    def yaz(page, rect, metin, boyut=10, hiza=0, renk=(0, 0, 0)):
        try:
            page.insert_textbox(rect, metin, fontname=ad, fontfile=ff,
                                fontsize=boyut, align=hiza, color=renk)
        except Exception:  # noqa: BLE001
            page.insert_textbox(rect, metin, fontname="helv",
                                fontsize=boyut, align=hiza, color=renk)

    doc = fitz.open()
    for s in sonuclar:
        page = doc.new_page(width=A4.width, height=A4.height)
        y = KENAR
        if kurum:
            yaz(page, fitz.Rect(KENAR, y, A4.width - KENAR, y + 16),
                kurum, 10, 1, (0.3, 0.3, 0.3))
            y += 18
        yaz(page, fitz.Rect(KENAR, y, A4.width - KENAR, y + 24),
            f"{sinav_ad} — Sonuç Karnesi" if sinav_ad else "Sonuç Karnesi",
            15, 1)
        y += 34
        kimlik = " · ".join(p for p in (
            s.get("ad_soyad"), f"No: {s['ogrenci_no']}"
            if s.get("ogrenci_no") else None,
            f"Kitapçık {s['kitapcik']}" if s.get("kitapcik") else None,
            f"Sıra: {s.get('sira', '?')} / {len(sonuclar)}") if p)
        yaz(page, fitz.Rect(KENAR, y, A4.width - KENAR, y + 18),
            kimlik, 11)
        y += 26
        # ders tablosu
        sutunlar = ["Ders", "Soru", "Doğru", "Yanlış", "Boş", "Net"]
        gen = [(A4.width - 2 * KENAR) * o
               for o in (0.4, 0.12, 0.12, 0.12, 0.12, 0.12)]
        satirlar = [[ders or "Genel", d["soru"], d["dogru"], d["yanlis"],
                     d["bos"], d["net"]]
                    for ders, d in sorted(s["dersler"].items())]
        t = s["toplam"]
        satirlar.append(["TOPLAM", t["soru"], t["dogru"], t["yanlis"],
                         t["bos"], t["net"]])
        for si, satir in enumerate([sutunlar] + satirlar):
            x = KENAR
            kalin = si == 0 or si == len(satirlar)
            for deger, g in zip(satir, gen):
                yaz(page, fitz.Rect(x + 2, y, x + g - 2, y + 14),
                    str(deger), 9.5 if not kalin else 10,
                    0 if g == gen[0] else 1,
                    (0, 0, 0) if kalin else (0.15, 0.15, 0.15))
                x += g
            y += 16
            if si == 0:
                page.draw_line(fitz.Point(KENAR, y - 2),
                               fitz.Point(A4.width - KENAR, y - 2),
                               width=0.5)
        y += 10
        # kazanım tablosu
        ogr_kazanim = (kazanim or {}).get(
            s.get("ogrenci_no") or s.get("ad_soyad") or "?")
        if ogr_kazanim:
            yaz(page, fitz.Rect(KENAR, y, A4.width - KENAR, y + 16),
                "Kazanım Analizi", 12)
            y += 20
            for k in sorted(ogr_kazanim, key=lambda k: k["yuzde"]):
                toplam = k["dogru"] + k["yanlis"] + k["bos"]
                metin = (f"{k['kazanim']}  ({k['ders']}) — "
                         f"{k['dogru']}/{toplam} doğru  (%{k['yuzde']})")
                renk = (0.7, 0.1, 0.1) if k["yuzde"] < 50 else \
                    (0.1, 0.4, 0.1) if k["yuzde"] >= 80 else (0, 0, 0)
                yaz(page, fitz.Rect(KENAR, y, A4.width - KENAR, y + 13),
                    metin, 9, 0, renk)
                y += 14
                if y > A4.height - KENAR - 20:
                    break
    doc.save(yol, deflate=True)
    doc.close()
    return yol
