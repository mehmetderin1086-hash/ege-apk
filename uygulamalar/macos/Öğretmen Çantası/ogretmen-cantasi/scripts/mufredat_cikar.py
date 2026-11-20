"""2024 Maarif Modeli Biyoloji Öğretim Programı PDF'ini yapılandırılmış JSON'a çevirir.

Tek seferlik bir iştir: çıktı `veri/mufredat_2024.json` olarak depoya işlenir ve
program çalışırken PDF'e ihtiyaç duymaz. Belge yeniden yayımlanırsa bu betik
tekrar koşulur.

    .venv/bin/python scripts/mufredat_cikar.py --pdf veri/kaynak/biyoloji_2024.pdf

Ayrıştırma, PDF'in tema bloklarının sabit bir bölüm sırası taşımasına dayanır.
Bölüm sınırları satır başındaki işaretlerle bulunur; iki işaret arasındaki her şey
o bölümün gövdesidir. İşaret bulunamazsa alan boş kalır ve `notlar` listesine
düşer — sessizce yutulmaz, çünkü eksik müfredat verisi tüm planları bozar.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

PROJE = Path(__file__).resolve().parents[1]

# Tema bloklarının başladığı ilk sayfa. Belgenin 12-13. sayfalarında programın
# yapısını ANLATAN şematik bir örnek var ve o da "1. TEMA: YAŞAM" başlığı
# taşıyor; sayfa süzgeci olmadan sahte bir dokuzuncu tema olarak ayrıştırılır.
ILK_TEMA_SAYFASI = 14

# Sayfa üstbilgisi ve bölüm başlıkları gövdeye karışıyor. Çıplak sayfa numarası
# burada değil, sayfa indeksiyle karşılaştırılarak atılır: sınıf düzeyi
# tablolarında ders saatleri de tek başına bir satırda duruyor ve "her çıplak
# sayı gürültüdür" kuralı onları da silerdi.
GURULTU = (
    re.compile(r"^BİYOLOJİ DERSİ ÖĞRETİM PROGRAMI$"),
    re.compile(r"^\d{1,2}\. SINIF$"),
    re.compile(r"^2\. BİYOLOJİ DERSİ ÖĞRETİM PROGRAMI SINIF DÜZEYLERİNE AİT TEMALAR$"),
    re.compile(r"^İÇİNDEKİLER$"),
)

TEMA_BASLIGI = re.compile(r"^(\d)\. TEMA:\s*(.+?)\s*$")
# Belgede kazanım kodu bir yerde "BİY. 9.2.1" diye dizilmiş (noktadan sonra
# boşluk). Boşluğa izin verilmezse o kazanımın uygulama bloğu sessizce kaybolur.
KOD_GOVDE = r"BİY\.\s?\d{1,2}\.\d+\.\d+"
CIKTI_KODU = re.compile(rf"^({KOD_GOVDE})\.?\s*(.*)$")
BILESEN = re.compile(r"^([a-zçğıöşü])\)\s*(.*)$")
SINIF_TABLOSU = re.compile(r"^(\d{1,2})\. SINIF BİYOLOJİ DERSİ \((\d+) SAAT\)$")

# Bölüm işaretleri belgede bu sırayla geçer. (alan_adı, işaret, gövdeden
# atılacak önek) — önekler, iki satıra bölünmüş başlıkların ikinci yarısıdır
# ("ALAN" / "BECERİLERİ FBAB1. …").
BOLUMLER: tuple[tuple[str, re.Pattern[str], str | None], ...] = (
    ("ders_saati", re.compile(r"^DERS SAATİ"), None),
    ("alan_becerileri", re.compile(r"^ALAN\s*$"), "BECERİLERİ"),
    ("kavramsal_beceriler", re.compile(r"^KAVRAMSAL\s*$"), "BECERİLER"),
    ("egilimler", re.compile(r"^EĞİLİMLER"), None),
    ("_programlar_arasi", re.compile(r"^PROGRAMLAR ARASI"), None),
    ("sosyal_duygusal_beceriler", re.compile(r"^Sosyal-Duygusal"), "Öğrenme Becerileri"),
    ("degerler", re.compile(r"^Değerler\b"), None),
    ("okuryazarlik_becerileri", re.compile(r"^Okuryazarlık Becerileri"), None),
    ("disiplinler_arasi", re.compile(r"^DİSİPLİNLER ARASI"), "İLİŞKİLER"),
    ("beceriler_arasi", re.compile(r"^BECERİLER ARASI"), "İLİŞKİLER"),
    ("ogrenme_ciktilari", re.compile(r"^ÖĞRENME ÇIKTILARI"), "VE SÜREÇ BİLEŞENLERİ"),
    ("icerik_cercevesi", re.compile(r"^İÇERİK ÇERÇEVESİ"), None),
    ("anahtar_kavramlar", re.compile(r"^Anahtar Kavramlar"), None),
    ("ogrenme_kanitlari", re.compile(r"^ÖĞRENME\s*$"), "KANITLARI (Ölçme ve Değerlendirme)"),
    ("_yasantilar", re.compile(r"^ÖĞRENME-ÖĞRETME"), None),
    ("temel_kabuller", re.compile(r"^Temel Kabuller"), None),
    ("on_degerlendirme", re.compile(r"^Ön Değerlendirme Süreci"), None),
    ("kopru_kurma", re.compile(r"^Köprü Kurma"), None),
    ("ogretme_uygulamalari", re.compile(r"^Öğrenme-Öğretme\s*$"), "Uygulamaları"),
    ("_farklilastirma", re.compile(r"^FARKLILAŞTIRMA"), None),
    ("zenginlestirme", re.compile(r"^Zenginleştirme"), None),
    ("destekleme", re.compile(r"^Destekleme"), None),
    ("_son", re.compile(r"^ÖĞRETMEN\s*$"), None),
)

# Tema bloğunun içine düşen ama temaya ait olmayan dipnotlar.
DIPNOT_ONEKLERI = (
    "Farklılaştırma kapsamında",
    "Zenginleştirme bölümünde",
    "Destekleme bölümünde",
)


@dataclass
class Satir:
    metin: str
    sayfa: int


@dataclass
class Cikarim:
    veri: dict
    notlar: list[str] = field(default_factory=list)


def pdf_satirlari(pdf: Path) -> list[Satir]:
    """PDF'i satır listesine çevirir; sayfa üstbilgisi ve numaralarını atar."""
    try:
        import pymupdf
    except ImportError:  # pragma: no cover - ortam sorunu
        raise SystemExit("pymupdf kurulu değil: uv sync") from None

    satirlar: list[Satir] = []
    with pymupdf.open(pdf) as belge:
        for indeks, sayfa in enumerate(belge, start=1):
            ilk_satir = True
            for ham in sayfa.get_text("text").splitlines():
                metin = ham.replace("\t", " ").strip()
                metin = re.sub(r"\s{2,}", " ", metin)
                if not metin or any(k.match(metin) for k in GURULTU):
                    continue
                # Sayfa numarası sayfanın ilk satırında basılıyor. "Her yerde
                # sayfa numarasına eşit sayıyı at" kuralı, tema tablosunda
                # tesadüfen aynı değeri taşıyan GERÇEK hücreleri de siliyordu
                # (10. sayfadaki "10" hem sayfa numarası hem iki temanın çıktı
                # sayısı).
                if ilk_satir and metin == str(indeks):
                    ilk_satir = False
                    continue
                ilk_satir = False
                satirlar.append(Satir(metin, indeks))
    return satirlar


def tireleri_birlestir(satirlar: list[Satir]) -> list[Satir]:
    """Satır sonundaki hece tiresini kaldırıp kelimeyi birleştirir.

    PDF metni sütuna sığdırmak için kelimeleri böler ("uygunlu-" / "ğunu").
    Sonraki satır küçük harfle başlıyorsa birleştirme güvenlidir: bölüm
    işaretlerinin hepsi büyük harfle başlar.
    """
    isaretler = tuple(isaret for _, isaret, _ in BOLUMLER)

    def birlestirilebilir(onceki: str, sonraki: str) -> bool:
        if not onceki.endswith("-") or not sonraki:
            return False
        if sonraki[0].islower():
            return True
        # Büyük harfle devam eden bölünme de var: "CO-" / "VID-19". Yalnız
        # tirenin ÖNÜNDEKİ harf de büyükse birleştirilir ve satır bilinen bir
        # bölüm işareti değilse — yoksa "…-" ile biten bir satırın ardından
        # gelen "DERS SAATİ" başlığı gövdeye yapışırdı.
        govde = onceki[:-1]
        if not govde or not govde[-1].isupper():
            return False
        return not any(isaret.match(sonraki) for isaret in isaretler)

    birlesik: list[Satir] = []
    for satir in satirlar:
        if birlesik and birlestirilebilir(birlesik[-1].metin, satir.metin):
            birlesik[-1] = Satir(birlesik[-1].metin[:-1] + satir.metin, birlesik[-1].sayfa)
            continue
        birlesik.append(satir)
    return birlesik


def sinif_ozetleri(satirlar: list[Satir]) -> dict[int, dict]:
    """Sayfa 10-11'deki tema/süre tablolarından sınıf düzeyi bilgilerini alır."""
    metinler = [s.metin for s in satirlar]
    ozetler: dict[int, dict] = {}
    for i, metin in enumerate(metinler):
        eslesme = SINIF_TABLOSU.match(metin)
        if not eslesme:
            continue
        sinif = int(eslesme.group(1))
        kayit: dict = {"haftalik_ders_saati": int(eslesme.group(2))}
        pencere = metinler[i : i + 40]
        for j, satir in enumerate(pencere):
            if satir.startswith("OKUL TEMELLİ PLANLAMA") and j + 1 < len(pencere):
                kayit["okul_temelli_planlama_saati"] = int(pencere[j + 1])
            if satir == "TOPLAM" and j + 3 < len(pencere):
                kayit["toplam_ogrenme_ciktisi"] = int(pencere[j + 1])
                kayit["toplam_ders_saati"] = int(pencere[j + 2])
                break
        ozetler[sinif] = kayit
    return ozetler


def tema_bloklari(satirlar: list[Satir]) -> list[tuple[int, str, list[str]]]:
    """(tema_no, tema_adı, gövde satırları) üçlülerini döndürür."""
    baslangiclar: list[tuple[int, int, str]] = []
    for i, satir in enumerate(satirlar):
        if satir.sayfa < ILK_TEMA_SAYFASI:
            continue
        eslesme = TEMA_BASLIGI.match(satir.metin)
        if eslesme:
            baslangiclar.append((i, int(eslesme.group(1)), eslesme.group(2)))

    bloklar: list[tuple[int, str, list[str]]] = []
    for sira, (indeks, no, ad) in enumerate(baslangiclar):
        son = baslangiclar[sira + 1][0] if sira + 1 < len(baslangiclar) else len(satirlar)
        bloklar.append((no, ad, [s.metin for s in satirlar[indeks + 1 : son]]))
    return bloklar


def bolumlere_ayir(govde: list[str]) -> tuple[dict[str, str], list[str]]:
    """Gövdeyi bilinen bölüm işaretlerine göre parçalar.

    İşaretler belgede sabit sırada geçtiği için arama her zaman bir öncekinin
    bulunduğu yerden devam eder; böylece gövde metninde tesadüfen geçen bir
    kelime bölüm sınırı sanılmaz.
    """
    konumlar: list[tuple[str, int, str | None]] = []
    imlec = 0
    eksikler: list[str] = []
    for alan, isaret, onek in BOLUMLER:
        bulundu = next((i for i in range(imlec, len(govde)) if isaret.match(govde[i])), None)
        if bulundu is None:
            if not alan.startswith("_"):
                eksikler.append(alan)
            continue
        konumlar.append((alan, bulundu, onek))
        imlec = bulundu + 1

    parcalar: dict[str, str] = {}
    for sira, (alan, indeks, onek) in enumerate(konumlar):
        son = konumlar[sira + 1][1] if sira + 1 < len(konumlar) else len(govde)
        # İlk satırın kendisi işareti taşır; işaret metni gövdeden çıkarılır.
        gövde_satirlari = list(govde[indeks:son])
        gövde_satirlari[0] = BOLUMLER[[b[0] for b in BOLUMLER].index(alan)][1].sub(
            "", gövde_satirlari[0], count=1
        )
        metin = " ".join(p.strip() for p in gövde_satirlari if p.strip())
        if onek and metin.startswith(onek):
            metin = metin[len(onek) :]
        parcalar[alan] = metin.strip()

    baslangic = konumlar[0][1] if konumlar else len(govde)
    parcalar["_aciklama"] = " ".join(p.strip() for p in govde[:baslangic] if p.strip())
    return parcalar, eksikler


def kod_listesi(metin: str) -> list[str]:
    """"FBAB1. Bilimsel Gözlem, FBAB2. Sınıflandırma" → iki öğe."""
    if not metin:
        return []
    # Virgül ayırıcı, ama "KB2.6. Bilgi Toplama" içindeki nokta ayırıcı değil.
    return [p.strip(" .;") for p in metin.split(",") if p.strip(" .;")]


def ciktilari_ayristir(metin: str) -> list[dict]:
    """Öğrenme çıktısı ve süreç bileşenlerini ayırır."""
    if not metin:
        return []
    # Tek satıra indirgenmiş metni kod ve bileşen sınırlarından yeniden böl.
    metin = re.sub(r"\s+", " ", metin)
    parcalar = re.split(rf"(?={KOD_GOVDE}\.?\s)", metin)
    ciktilar: list[dict] = []
    for parca in parcalar:
        eslesme = CIKTI_KODU.match(parca.strip())
        if not eslesme:
            continue
        kod, kalan = eslesme.group(1).replace(" ", ""), eslesme.group(2).strip()
        bilesenler: list[dict] = []
        bolumler = re.split(r"(?<![\wçğıöşüÇĞİÖŞÜ])([a-zçğıöşü])\)\s", " " + kalan)
        ifade = bolumler[0].strip()
        for harf, govde in zip(bolumler[1::2], bolumler[2::2], strict=False):
            bilesenler.append({"harf": harf, "ifade": govde.strip()})
        ciktilar.append({"kod": kod, "ifade": ifade, "surec_bilesenleri": bilesenler})
    return ciktilar


def uygulamalari_ayristir(metin: str) -> dict[str, str]:
    """Öğrenme-öğretme uygulamalarını kazanım koduna göre gruplar."""
    if not metin:
        return {}
    metin = re.sub(r"\s+", " ", metin)
    parcalar = re.split(rf"(?={KOD_GOVDE}\s)", metin)
    uygulamalar: dict[str, str] = {}
    for parca in parcalar:
        eslesme = CIKTI_KODU.match(parca.strip())
        if eslesme:
            uygulamalar[eslesme.group(1).replace(" ", "")] = eslesme.group(2).strip()
    return uygulamalar


def dipnotlari_ayir(metin: str) -> str:
    """Tema gövdesine karışan genel dipnotları metnin sonundan keser."""
    for onek in DIPNOT_ONEKLERI:
        yer = metin.find(onek)
        if yer > 0:
            metin = metin[:yer]
    return metin.strip()


def temayi_kur(no: int, ad: str, govde: list[str]) -> tuple[dict, list[str]]:
    parcalar, eksikler = bolumlere_ayir(govde)
    saat_metni = parcalar.get("ders_saati", "")
    saat = re.search(r"\d+", saat_metni)
    tema = {
        "no": no,
        "ad": ad,
        "aciklama": parcalar.get("_aciklama", ""),
        "ders_saati": int(saat.group()) if saat else 0,
        "alan_becerileri": kod_listesi(parcalar.get("alan_becerileri", "")),
        "kavramsal_beceriler": kod_listesi(parcalar.get("kavramsal_beceriler", "")),
        "egilimler": kod_listesi(parcalar.get("egilimler", "")),
        "sosyal_duygusal_beceriler": kod_listesi(parcalar.get("sosyal_duygusal_beceriler", "")),
        "degerler": kod_listesi(parcalar.get("degerler", "")),
        "okuryazarlik_becerileri": kod_listesi(parcalar.get("okuryazarlik_becerileri", "")),
        "disiplinler_arasi": kod_listesi(parcalar.get("disiplinler_arasi", "")),
        "beceriler_arasi": kod_listesi(parcalar.get("beceriler_arasi", "")),
        "ogrenme_ciktilari": ciktilari_ayristir(parcalar.get("ogrenme_ciktilari", "")),
        "icerik_cercevesi": parcalar.get("icerik_cercevesi", ""),
        "anahtar_kavramlar": kod_listesi(parcalar.get("anahtar_kavramlar", "")),
        "ogrenme_kanitlari": parcalar.get("ogrenme_kanitlari", ""),
        "temel_kabuller": parcalar.get("temel_kabuller", ""),
        "on_degerlendirme": parcalar.get("on_degerlendirme", ""),
        "kopru_kurma": parcalar.get("kopru_kurma", ""),
        "ogretme_uygulamalari": uygulamalari_ayristir(parcalar.get("ogretme_uygulamalari", "")),
        "zenginlestirme": dipnotlari_ayir(parcalar.get("zenginlestirme", "")),
        "destekleme": dipnotlari_ayir(parcalar.get("destekleme", "")),
    }
    return tema, eksikler


def cikar(pdf: Path) -> Cikarim:
    satirlar = tireleri_birlestir(pdf_satirlari(pdf))
    ozetler = sinif_ozetleri(satirlar)
    notlar: list[str] = []

    siniflar: dict[int, dict] = {}
    for no, ad, govde in tema_bloklari(satirlar):
        tema, eksikler = temayi_kur(no, ad, govde)
        if not tema["ogrenme_ciktilari"]:
            notlar.append(f"{ad}: öğrenme çıktısı bulunamadı, tema atlandı")
            continue
        sinif = int(tema["ogrenme_ciktilari"][0]["kod"].split(".")[1])
        for alan in eksikler:
            notlar.append(f"{sinif}. sınıf {ad}: '{alan}' bölümü bulunamadı")
        siniflar.setdefault(sinif, {"sinif": sinif, "temalar": []})
        siniflar[sinif]["temalar"].append(tema)

    for sinif, kayit in siniflar.items():
        kayit.update(ozetler.get(sinif, {}))
        kayit["temalar"].sort(key=lambda t: t["no"])

    veri = {
        "surum": "maarif_2024",
        "ad": "Türkiye Yüzyılı Maarif Modeli Biyoloji Dersi Öğretim Programı (2024)",
        "ders": "Biyoloji",
        "kazanim_onek": "BİY",
        "siniflar": [siniflar[s] for s in sorted(siniflar)],
    }
    return Cikarim(veri, notlar)


def dogrula(veri: dict) -> list[str]:
    """Çıkarımı belgedeki sayılarla karşılaştırır; her uyuşmazlığı döndürür."""
    hatalar: list[str] = []
    if len(veri["siniflar"]) != 4:
        hatalar.append(f"4 sınıf düzeyi beklenir, {len(veri['siniflar'])} bulundu")

    for kayit in veri["siniflar"]:
        sinif = kayit["sinif"]
        temalar = kayit["temalar"]
        if len(temalar) != 2:
            hatalar.append(f"{sinif}. sınıf: 2 tema beklenir, {len(temalar)} bulundu")

        tema_saati = sum(t["ders_saati"] for t in temalar)
        okul_temelli = kayit.get("okul_temelli_planlama_saati", 0)
        toplam = kayit.get("toplam_ders_saati", 0)
        if tema_saati + okul_temelli != toplam:
            hatalar.append(
                f"{sinif}. sınıf: tema saatleri ({tema_saati}) + okul temelli "
                f"({okul_temelli}) = {tema_saati + okul_temelli}, tabloda {toplam}"
            )

        cikti_sayisi = sum(len(t["ogrenme_ciktilari"]) for t in temalar)
        if cikti_sayisi != kayit.get("toplam_ogrenme_ciktisi"):
            hatalar.append(
                f"{sinif}. sınıf: {cikti_sayisi} öğrenme çıktısı çıkarıldı, "
                f"tabloda {kayit.get('toplam_ogrenme_ciktisi')}"
            )

        for tema in temalar:
            for cikti in tema["ogrenme_ciktilari"]:
                if not cikti["ifade"]:
                    hatalar.append(f"{cikti['kod']}: çıktı ifadesi boş")
                if not cikti["surec_bilesenleri"]:
                    hatalar.append(f"{cikti['kod']}: süreç bileşeni yok")
            for alan in ("icerik_cercevesi", "ogrenme_kanitlari", "on_degerlendirme"):
                if not tema[alan]:
                    hatalar.append(f"{sinif}. sınıf {tema['ad']}: '{alan}' boş")
            if not tema["anahtar_kavramlar"]:
                hatalar.append(f"{sinif}. sınıf {tema['ad']}: anahtar kavram yok")
    return hatalar


def main() -> int:
    ayristirici = argparse.ArgumentParser(description=__doc__)
    ayristirici.add_argument("--pdf", type=Path, default=PROJE / "veri/kaynak/biyoloji_2024.pdf")
    ayristirici.add_argument("--cikti", type=Path, default=PROJE / "veri/mufredat_maarif_2024.json")
    ayristirici.add_argument(
        "--zorla",
        action="store_true",
        help="doğrulama geçmese de yaz (var olan JSON'un üstüne yazar)",
    )
    ayristirici.add_argument(
        "--surum",
        default="maarif_2024",
        help="çıkarılacak program sürümü (şimdilik yalnız maarif_2024)",
    )
    args = ayristirici.parse_args()

    if args.surum != "maarif_2024":
        # 2018 programı ünite/kazanım düzeninde; bu betiğin tema ve süreç
        # bileşeni varsayımlarıyla ayrıştırılamaz. Sessizce yanlış JSON
        # üretmektense açık hata veriyoruz.
        raise SystemExit(
            f"'{args.surum}' için ayrıştırıcı yok: bu betik Maarif Modeli'nin "
            "tema düzenine göre yazıldı. 2018 belgesi için ayrı ayrıştırıcı gerekir."
        )

    if not args.pdf.is_file():
        raise SystemExit(f"PDF bulunamadı: {args.pdf}")

    sonuc = cikar(args.pdf)
    # Bulunamayan bölüm işaretleri de HATA sayılır: bir bölüm kaybolduğunda
    # metni komşu alana emiliyor, sayısal doğrulamalar bunu yakalamıyor ve
    # eksik veri "başarılı" görünüyordu.
    hatalar = dogrula(sonuc.veri) + sonuc.notlar

    toplam_cikti = sum(
        len(t["ogrenme_ciktilari"]) for s in sonuc.veri["siniflar"] for t in s["temalar"]
    )
    for hata in hatalar:
        print(f"  HATA: {hata}", file=sys.stderr)

    if hatalar and not args.zorla:
        print(
            "Doğrulama geçmedi; var olan JSON KORUNDU. Yine de yazmak için --zorla verin.",
            file=sys.stderr,
        )
        return 1

    args.cikti.parent.mkdir(parents=True, exist_ok=True)
    args.cikti.write_text(
        json.dumps(sonuc.veri, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Yazıldı: {args.cikti}")
    print(f"Sınıf düzeyi: {len(sonuc.veri['siniflar'])}, öğrenme çıktısı: {toplam_cikti}")
    return 1 if hatalar else 0


if __name__ == "__main__":
    # Türkçe karakterlerin NFC olarak yazılması, JSON'da aynı kelimenin iki
    # farklı bayt dizisiyle görünmesini önler.
    unicodedata.normalize("NFC", "")
    raise SystemExit(main())
