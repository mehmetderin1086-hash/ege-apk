#!/usr/bin/env python3
"""Cihaz kabul turu karşılaştırıcısı (P3.10-kabul). Yalnız standart kitaplık; Python 3.9 uyumlu.

Kullanım:
    /usr/bin/python3 -I araclar/kabul_karsilastir.py ONCEKI_TUR YENI_TUR
ONCEKI_TUR boş dize ya da "-" ise (ya da dizin yoksa) yalnız başarısızlıklar denetlenir.

Her tur dizininde `asistan-*.json` sınama raporları vardır (araclar/cihaz-kabul.sh telefondan çeker).
Kurallar:
  - Süre alanları (anahtar `Sn`, `Ms` ile ya da `sureSaniye` ile biter): gerileme = yeni > eski * 1.20
    VE yeni - eski > mutlak eşik (0.2 sn / 200 ms). Negatif değer (ör. -1 = ölçülmedi) karşılaştırılmaz.
  - Boolean alanlar: true -> false gerileme.
  - İç içe `hata` alanı: boş -> dolu gerileme.
  - Başarısızlık: `tamamlandi` false (alan varsa), `asama` varken "tamamlandi" değilse, üst düzey `hata` dolu,
    `zamanAsimi` true ya da betiğin işareti `kabulZamanAsimi` true. İç içe yapraklarda (ör. `turlar[].bitti` false,
    `turlar[].hata` dolu) bunlar da başarısızlıktır: üst düzey `tamamlandi` true olsa bile tur sessizce geçmez.
  - `kosu`, `surum`, `kosuBitti`, `zaman` karşılaştırılmaz. Önceki turda olmayan alan ya da dosya gerileme
    sayılmaz, 'yeni' diye raporlanır.
Çıkış kodu: 0 geçti, 1 gerileme ya da başarısız sınama, 2 altyapı (yeni tur yok, rapor yok, bozuk JSON).
"""

import json
import sys
from pathlib import Path

ORAN = 1.20
MUTLAK_SN = 0.2
MUTLAK_MS = 200.0
DISLANAN = {"kosu", "surum", "kosuBitti", "zaman"}
# Dizi öğelerini sıradan bağımsız eşlemek için kimlik alanları (ilk bulunan dize kullanılır).
KIMLIK_ALANLARI = ("ad", "aile", "yon")

GECTI, GERILEME, ALTYAPI = 0, 1, 2


def _yaprak_mi(d):
    return d is None or isinstance(d, (bool, int, float, str))


def duzlestir(nesne, onek=""):
    """JSON nesnesini {yol: yaprak değer} sözlüğüne çevirir.

    Sözlükte yol `a.b`, dizide `turlar[ad=<ad>]` (kimlik alanı varsa) ya da `turlar[3]` biçimindedir.
    Aynı kimlik iki kez geçerse ikincisi `#2` ekiyle ayrılır.
    """
    sonuc = {}
    if isinstance(nesne, dict):
        for anahtar in sorted(nesne):
            yol = anahtar if not onek else onek + "." + anahtar
            deger = nesne[anahtar]
            if _yaprak_mi(deger):
                sonuc[yol] = deger
            else:
                sonuc.update(duzlestir(deger, yol))
    elif isinstance(nesne, list):
        gorulen = {}
        for i, oge in enumerate(nesne):
            etiket = str(i)
            if isinstance(oge, dict):
                for alan in KIMLIK_ALANLARI:
                    if isinstance(oge.get(alan), str) and oge.get(alan):
                        etiket = alan + "=" + oge[alan]
                        break
            gorulen[etiket] = gorulen.get(etiket, 0) + 1
            if gorulen[etiket] > 1:
                etiket += "#" + str(gorulen[etiket])
            yol = onek + "[" + etiket + "]"
            if _yaprak_mi(oge):
                sonuc[yol] = oge
            else:
                sonuc.update(duzlestir(oge, yol))
    elif onek:
        sonuc[onek] = nesne
    return sonuc


def son_anahtar(yol):
    """`turlar[ad=x].ilkSn` -> `ilkSn`; `sonuclar[2]` -> `sonuclar`."""
    parca = yol.rsplit(".", 1)[-1]
    return parca.split("[", 1)[0]


def ust_anahtar(yol):
    return yol.split(".", 1)[0].split("[", 1)[0]


def sure_esigi(anahtar):
    """Süre alanıysa mutlak eşiği döndürür, değilse None."""
    if anahtar.endswith("Ms"):
        return MUTLAK_MS
    if anahtar.endswith("Sn") or anahtar.endswith("sureSaniye"):
        return MUTLAK_SN
    return None


def _sayi_mi(d):
    return isinstance(d, (int, float)) and not isinstance(d, bool)


def sure_gerilemesi(eski, yeni, esik):
    if not (_sayi_mi(eski) and _sayi_mi(yeni)) or eski < 0 or yeni < 0:
        return False
    return yeni > eski * ORAN and (yeni - eski) > esik


def basarisizliklar(json_nesne):
    """Raporun başarısızlık nedenleri (boş liste = başarılı ya da ölçüt yok)."""
    nedenler = []
    if isinstance(json_nesne, list):
        for oge in json_nesne:
            if isinstance(oge, dict) and _dolu_hata(oge.get("hata")):
                nedenler.append("öğe hatası: " + _kisalt(oge.get("hata")))
        return nedenler
    if not isinstance(json_nesne, dict):
        return ["rapor nesne değil"]
    if json_nesne.get("kabulZamanAsimi") is True:
        nedenler.append("zaman aşımı (rapor bitmedi)")
    if "tamamlandi" in json_nesne and json_nesne.get("tamamlandi") is not True:
        nedenler.append("tamamlanmadı")
    if "asama" in json_nesne and json_nesne.get("asama") != "tamamlandi":
        nedenler.append("aşama: " + str(json_nesne.get("asama")))
    if _dolu_hata(json_nesne.get("hata")):
        nedenler.append("hata: " + _kisalt(json_nesne.get("hata")))
    if json_nesne.get("zamanAsimi") is True:
        nedenler.append("sınama zaman aşımı")
    nedenler.extend(_ic_ice_basarisizliklar(json_nesne))
    return nedenler


def _ic_ice_basarisizliklar(json_nesne):
    """Düzleştirilmiş iç yollarda `bitti` false ya da `hata` dolu olan yapraklar (üst düzey alanlar hariç)."""
    nedenler = []
    duz = duzlestir(json_nesne)
    for yol in sorted(duz):
        if "." not in yol and "[" not in yol:
            continue
        if ust_anahtar(yol) in DISLANAN:
            continue
        anahtar, deger = son_anahtar(yol), duz[yol]
        if anahtar == "bitti" and deger is False:
            nedenler.append("bitmedi: " + yol)
        elif anahtar == "hata" and _dolu_hata(deger):
            nedenler.append("iç hata: " + yol + " = " + _kisalt(deger, 40))
    return nedenler


def _dolu_hata(d):
    if d is None or d is False:
        return False
    if isinstance(d, str):
        return bool(d.strip())
    if isinstance(d, (dict, list)):
        return len(d) > 0
    return True


def _kisalt(d, n=80):
    metin = d if isinstance(d, str) else json.dumps(d, ensure_ascii=False)
    metin = " ".join(metin.split())
    return metin if len(metin) <= n else metin[: n - 1] + "…"


def _bicim(d):
    if d is None:
        return "-"
    if isinstance(d, bool):
        return "true" if d else "false"
    if isinstance(d, float):
        return "%.2f" % d
    return _kisalt(d, 24)


def _yuzde(eski, yeni):
    if not (_sayi_mi(eski) and _sayi_mi(yeni)) or eski <= 0:
        return "-"
    return "%+.0f%%" % ((yeni - eski) / eski * 100)


def dosya_karsilastir(ad, eski, yeni):
    """Tek raporun satırları: (sınama, alan, önceki, yeni, değişim, durum). `eski` None olabilir."""
    satirlar = []
    for neden in basarisizliklar(yeni):
        satirlar.append((ad, "-", "-", "-", "-", "başarısız: " + neden))
    if eski is None:
        return satirlar
    duz_eski, duz_yeni = duzlestir(eski), duzlestir(yeni)
    for yol in sorted(duz_yeni):
        if ust_anahtar(yol) in DISLANAN:
            continue
        y = duz_yeni[yol]
        anahtar = son_anahtar(yol)
        esik = sure_esigi(anahtar)
        ilgili = esik is not None or isinstance(y, bool) or anahtar == "hata"
        if not ilgili:
            continue
        if yol not in duz_eski:
            if esik is not None or y is False:
                satirlar.append((ad, yol, "-", _bicim(y), "-", "yeni"))
            continue
        e = duz_eski[yol]
        if esik is not None:
            if not (_sayi_mi(e) and _sayi_mi(y)):
                continue
            if sure_gerilemesi(e, y, esik):
                durum = "GERİLEME"
            elif sure_gerilemesi(y, e, esik):
                durum = "iyileşme"
            else:
                durum = "tamam"
            satirlar.append((ad, yol, _bicim(e), _bicim(y), _yuzde(e, y), durum))
        elif isinstance(y, bool):
            if e is True and y is False:
                satirlar.append((ad, yol, "true", "false", "-", "GERİLEME"))
            elif e is False and y is True:
                satirlar.append((ad, yol, "false", "true", "-", "iyileşme"))
        elif anahtar == "hata" and yol != "hata":
            if not _dolu_hata(e) and _dolu_hata(y):
                satirlar.append((ad, yol, "-", _bicim(y), "-", "GERİLEME"))
    return satirlar


def _rapor_oku(yol):
    with open(str(yol), "r", encoding="utf-8") as f:
        return json.load(f)


def raporlar(dizin):
    return sorted(p for p in Path(dizin).glob("asistan-*.json") if p.is_file())


def tablo_bas(satirlar, cikis):
    basliklar = ("Sınama", "Alan", "Önceki", "Yeni", "Değişim", "Durum")
    tum = [basliklar] + [tuple(str(h) for h in s) for s in satirlar]
    genislik = [max(len(s[i]) for s in tum) for i in range(len(basliklar))]
    for j, s in enumerate(tum):
        print("  ".join(h.ljust(genislik[i]) for i, h in enumerate(s)).rstrip(), file=cikis)
        if j == 0:
            print("  ".join("-" * g for g in genislik), file=cikis)


def calistir(onceki, yeni, cikis=sys.stdout):
    yeni_dizin = Path(yeni) if yeni else None
    if yeni_dizin is None or not yeni_dizin.is_dir():
        print("Altyapı: yeni tur dizini yok: %s" % yeni, file=cikis)
        return ALTYAPI
    onceki_dizin = Path(onceki) if onceki and onceki != "-" else None
    if onceki_dizin is not None and not onceki_dizin.is_dir():
        onceki_dizin = None
    yeni_raporlar = raporlar(yeni_dizin)
    if not yeni_raporlar:
        print("Altyapı: yeni turda sınama raporu yok (%s)." % yeni_dizin, file=cikis)
        return ALTYAPI

    altyapi, satirlar = [], []
    for yol in yeni_raporlar:
        ad = yol.name[len("asistan-"):-len(".json")]
        try:
            yeni_json = _rapor_oku(yol)
        except (ValueError, OSError) as hata:
            altyapi.append("%s okunamadı: %s" % (yol.name, _kisalt(str(hata))))
            continue
        eski_json = None
        if onceki_dizin is not None:
            eski_yol = onceki_dizin / yol.name
            if eski_yol.is_file():
                try:
                    eski_json = _rapor_oku(eski_yol)
                except (ValueError, OSError):
                    print("Uyarı: önceki turdaki %s okunamadı; karşılaştırılmadı." % yol.name, file=cikis)
            else:
                satirlar.append((ad, "-", "-", "-", "-", "yeni sınama"))
        satirlar.extend(dosya_karsilastir(ad, eski_json, yeni_json))

    print("Kabul karşılaştırması: önceki %s → yeni %s" % (onceki_dizin.name if onceki_dizin else "yok", yeni_dizin.name), file=cikis)
    if satirlar:
        tablo_bas(satirlar, cikis)
    for a in altyapi:
        print("Altyapı: " + a, file=cikis)
    gerileme = sum(1 for s in satirlar if s[5] == "GERİLEME")
    basarisiz = sum(1 for s in satirlar if s[5].startswith("başarısız"))
    print("Özet: %d rapor · %d gerileme · %d başarısız · %d altyapı" % (len(yeni_raporlar), gerileme, basarisiz, len(altyapi)), file=cikis)
    if altyapi:
        return ALTYAPI
    if gerileme or basarisiz:
        return GERILEME
    return GECTI


def main(argv):
    if len(argv) != 3:
        print("Kullanım: kabul_karsilastir.py ONCEKI_TUR YENI_TUR", file=sys.stderr)
        return ALTYAPI
    return calistir(argv[1], argv[2])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
