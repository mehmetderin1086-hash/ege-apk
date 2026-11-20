"""Ders kitabı PDF'ini pasajlara çevirip hafızaya alır.

`alim.cikarim._pdf_cikar` bir dosyayı tek seferde metne çeviriyor ve bu
akış için yetmiyor: Campbell 1101 sayfa ve metin katmanı yok, yani her
sayfa OCR'dan geçmek zorunda. Tek çağrıda yapmanın iki sorunu var —
tüm metin bellekte birikiyor ve koşu ortasında düşerse saatlerin emeği
gidiyor. Burada sayfa sayfa ilerleniyor ve HER SAYFA kendi pasajlarıyla
anında depoya yazılıyor; ikinci koşu kaldığı yerden devam eder çünkü
`Depo.pasaj_ekle` aynı metni ikinci kez almaz.

Bölütleme paragraf tabanlı: ders kitabında anlam birimi paragraftır ve
sabit uzunlukta kesmek cümleyi ortadan bölüp olguyu bozar.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

from ..depo import Depo
from ..modeller import Pasaj

# Bir pasajın hedef uzunluğu. Alt sınırın altındaki paragraf kendinden
# sonrakiyle birleştirilir (tek başına "Şekil 12.3" satırı kanıt değildir),
# üst sınırı aşan paragraf cümle sınırından bölünür.
ASGARI_KARAKTER = 200
AZAMI_KARAKTER = 1200

# Bu uzunluğun altındaki sayfa çıktısı boş sayılır: kapak, boş sayfa ya da
# yalnız sayfa numarası taşıyan sayfalar pasaj üretmemeli.
ASGARI_SAYFA_KARAKTERI = 120

# Sayfa üstü/altı gürültüsü: yalnız sayfa numarası ya da "BÖLÜM 12" / "ÜNİTE 3"
# gibi tek başına duran başlık satırları. Kitapta bunlar her sayfada tekrar
# ediyor ve pasaja karışırsa erişim onları konu sanıp yanlış eşleşme üretiyor.
# IGNORECASE şart: aynı satır kitapta hem "BÖLÜM 8" hem "Bölüm 8" biçiminde.
_GURULTU = re.compile(
    r"^\s*(\d{1,4}|b[öo]l[üu]m\s+\d+|[üu]n[iı̇]te\s+\d+|\W{1,4})\s*$",
    re.IGNORECASE,
)
# OCR'ın satır sonuna koyduğu tireyi birleştir: "fotosen-\ntez" → "fotosentez".
_TIRELI_BOLME = re.compile(r"(\w)-\s*\n\s*(\w)")

# İçindekiler satırı: "1.10. İskelet Kaslarının Mekanizması....... 98".
# Ders kitaplarının ilk sayfaları bunlarla dolu ve pasaj olarak alındıklarında
# saf gürültü oluyorlar: konu adlarını içerdikleri için erişimde ÜST SIRAYA
# çıkıyorlar (sorgu terimleriyle birebir eşleşiyorlar) ama tek bir olgu
# taşımıyorlar — yani en zararlı kanıt türü.
_ICINDEKILER_SATIRI = re.compile(r"\.{4,}\s*\d{1,4}\s*$|\.{6,}")
# Bir pasajın bu orandan fazlası içindekiler satırıysa pasaj tümden atılır.
_ICINDEKILER_ORANI = 0.4


@dataclass
class KitapOzeti:
    kaynak: str
    sayfa: int = 0
    okunan_sayfa: int = 0
    ocr_sayfasi: int = 0
    pasaj: int = 0
    atlanan: int = 0          # zaten kayıtlı (yinelenen) pasaj
    bos_sayfa: int = 0        # gerçekten boş sayfa (kapak, ara sayfa)
    # OCR çalıştı ama metin dönmedi. `bos_sayfa`dan AYRI sayılıyor: ilk
    # koşuda OCR arka ucu (llama-server) çöktükten sonra 650 sayfa boyunca
    # boş sonuç döndü, hepsi "boş sayfa" sayıldı ve koşu hatasız görünerek
    # sonuna kadar gitti. Sessiz kayıp tam olarak buydu.
    ocr_bos: int = 0
    hata: int = 0
    # Üst üste boş dönen OCR sayısı; arka uç çöktüyse bu hızla büyür.
    ardisik_ocr_bos: int = 0


# Bu kadar sayfa üst üste OCR'dan boş dönerse arka uç çökmüş sayılır ve
# tanıyıcı yeniden kurulur. 6 sayfa: gerçek kitapta bu kadar ardışık tam boş
# sayfa (bölüm araları dahil) pratikte görülmüyor.
ARDISIK_BOS_SINIRI = 6


def _temizle(metin: str) -> str:
    """Gürültü satırlarını atar ama PARAGRAF SINIRLARINI korur.

    Boş satırlar burada silinemez: `paragraflara_bol` bölmeyi `\\n\\n`
    üzerinden yapıyor ve boş satır kalmazsa tüm sayfa tek gövde olur —
    o zaman paragraf mantığı sessizce devre dışı kalır ve metin karakter
    sınırından kör kesilir. Gürültü satırı silinirken yerine boş satır
    bırakılıyor, böylece başlığın iki yanındaki paragraflar birleşmez.
    """
    metin = _TIRELI_BOLME.sub(r"\1\2", metin or "")
    temiz: list[str] = []
    for ham in metin.splitlines():
        satir = ham.strip()
        temiz.append("" if satir and _GURULTU.match(satir) else satir)
    return "\n".join(temiz)


def paragraflara_bol(metin: str) -> list[str]:
    """Sayfa metnini pasaj adaylarına böler.

    Kısa paragraflar birleştirilir, uzun olanlar cümle sınırından bölünür.
    Karakter sayısıyla körlemesine kesmek, bir olgunun yarısını kanıt diye
    sunmak demektir.
    """
    ham = [p.strip() for p in re.split(r"\n\s*\n", _temizle(metin)) if p.strip()]
    if not ham:
        return []

    birlesik: list[str] = []
    tampon = ""
    for paragraf in ham:
        tampon = f"{tampon}\n{paragraf}".strip() if tampon else paragraf
        if len(tampon) >= ASGARI_KARAKTER:
            birlesik.append(tampon)
            tampon = ""
    if tampon:
        # Son artık tek başına çok kısaysa öncekine iliştirilir.
        if birlesik and len(tampon) < ASGARI_KARAKTER:
            birlesik[-1] = f"{birlesik[-1]}\n{tampon}"
        else:
            birlesik.append(tampon)

    sonuc: list[str] = []
    for parca in birlesik:
        for dilim in _uzunu_bol(parca):
            # Çok kısa artık parçayı ATMA, öncekine iliştir: sessizce düşen
            # metin hiçbir sayaca yazılmıyor ve "kitap alındı" raporu eksik
            # içeriği tam göstermiş olurdu. Kaybın görünmezi en kötüsüdür.
            if sonuc and len(dilim) < ASGARI_KARAKTER // 2:
                sonuc[-1] = f"{sonuc[-1]} {dilim}".strip()
            else:
                sonuc.append(dilim)
    return [p for p in sonuc if p.strip() and not _icindekiler_mi(p)]


def _icindekiler_mi(metin: str) -> bool:
    """Pasaj bir içindekiler/dizin bloğu mu?

    Tek tek satır atmak yerine pasaj bütününe bakılıyor: gerçek metinde de
    tek bir nokta dizisi geçebilir, ama bir paragrafın yarısı sayfa
    numarasına çıkan başlıksa o paragraf bilgi taşımıyordur.
    """
    satirlar = [s for s in metin.splitlines() if s.strip()]
    if not satirlar:
        return True
    isabet = sum(1 for s in satirlar if _ICINDEKILER_SATIRI.search(s))
    return isabet / len(satirlar) >= _ICINDEKILER_ORANI


def _uzunu_bol(metin: str) -> list[str]:
    if len(metin) <= AZAMI_KARAKTER:
        return [metin]
    cumleler = re.split(r"(?<=[.!?])\s+", metin)
    parcalar: list[str] = []
    tampon = ""
    for cumle in cumleler:
        if tampon and len(tampon) + len(cumle) + 1 > AZAMI_KARAKTER:
            parcalar.append(tampon)
            tampon = cumle
        else:
            tampon = f"{tampon} {cumle}".strip()
    if tampon:
        parcalar.append(tampon)
    return parcalar


def _ocr_tanicisini_sifirla() -> None:
    """OCR arka ucunu yeniden kurar (bkz. `alim.ocr.taniyicilari_sifirla`)."""
    from ..alim.ocr import taniyicilari_sifirla

    taniyicilari_sifirla()


def _metin_katmani(sayfa) -> str:
    try:
        return sayfa.get_textpage().get_text_range() or ""
    except Exception:  # noqa: BLE001 - bozuk sayfa tüm kitabı düşürmesin
        return ""


def _grubu_oku(
    belge, numaralar: list[int], *, ocr: str, ocr_motoru: str
) -> list[tuple[int, str, bool]]:
    """Bir sayfa grubunu okur; (sayfa_no, metin, ocr_kullanildi) döndürür.

    OCR gereken sayfalar TEK çağrıda toplu okunuyor: tek tek okumaya göre
    sayfa başına yaklaşık %38 daha hızlı ve 1101 sayfalık bir kitapta bu
    saatler demek. Metin katmanı olan sayfalar hiç OCR'a gitmez.
    """
    from ..alim.cikarim import OCR_ESIGI_KARAKTER

    sonuc: list[tuple[int, str, bool]] = []
    ocr_bekleyen: list[int] = []
    for no in numaralar:
        metin = _metin_katmani(belge[no - 1])
        gerekli = ocr != "kapali" and (
            ocr == "zorla" or len(metin.strip()) < OCR_ESIGI_KARAKTER
        )
        if gerekli:
            ocr_bekleyen.append(no)
            sonuc.append((no, "", True))
        else:
            sonuc.append((no, metin, False))

    if ocr_bekleyen:
        from ..alim.ocr import sayfalari_oku

        okunanlar = sayfalari_oku(
            [belge[no - 1] for no in ocr_bekleyen], motor=ocr_motoru
        )
        metinler = dict(zip(ocr_bekleyen, (o.metin for o in okunanlar), strict=False))
        sonuc = [
            (no, metinler.get(no, metin) if ocrli else metin, ocrli)
            for no, metin, ocrli in sonuc
        ]
    return sonuc


def kitabi_al(
    pdf: str | Path,
    depo: Depo,
    *,
    kaynak: str,
    baslangic: int = 1,
    bitis: int | None = None,
    ocr: str = "oto",
    ocr_motoru: str = "",
    toplu: int = 4,
    ilerleme=None,
) -> Iterator[KitapOzeti]:
    """PDF'i sayfa sayfa pasajlara çevirip depoya yazar; her sayfada özet verir.

    Üreteç olması bilinçli: 1101 sayfalık bir koşuda çağıran her sayfadan
    sonra ilerlemeyi yazdırabilsin ve gerekirse döngüyü kırabilsin.
    """
    try:
        import pypdfium2
    except ImportError as exc:  # pragma: no cover - ortam bağımlı
        raise RuntimeError("PDF okumak için: uv sync --extra alim") from exc

    yol = Path(pdf).expanduser()
    if not yol.is_file():
        raise FileNotFoundError(f"PDF bulunamadı: {yol}")

    belge = pypdfium2.PdfDocument(str(yol))
    ozet = KitapOzeti(kaynak=kaynak, sayfa=len(belge))
    ocr_arka_ucu_sifirlandi = False
    son = min(bitis or len(belge), len(belge))
    tum_sayfalar = list(range(max(1, baslangic), son + 1))
    try:
        for bas in range(0, len(tum_sayfalar), max(1, toplu)):
            grup = tum_sayfalar[bas : bas + max(1, toplu)]
            try:
                okunanlar = _grubu_oku(
                    belge, grup, ocr=ocr, ocr_motoru=ocr_motoru
                )
            except Exception:  # noqa: BLE001 - tek grup koşuyu düşürmesin
                # Grup düştüğünde sayfaları kaybetmiş sayma: hata olarak
                # kaydet ki rapordaki "okunan" sayısı gerçeği göstersin.
                ozet.okunan_sayfa += len(grup)
                ozet.hata += len(grup)
                if ilerleme:
                    ilerleme(grup[-1], son, ozet)
                yield ozet
                continue

            for no, metin, ocr_kullanildi in okunanlar:
                ozet.okunan_sayfa += 1
                ozet.ocr_sayfasi += int(ocr_kullanildi)
                if len(metin.strip()) < ASGARI_SAYFA_KARAKTERI:
                    if ocr_kullanildi:
                        # OCR çalıştı ama metin yok: ya sayfa gerçekten boş
                        # ya da arka uç düştü. İkisini ayırmak için ardışık
                        # sayaç tutuluyor — tek tek bakınca ayırt edilemez.
                        ozet.ocr_bos += 1
                        ozet.ardisik_ocr_bos += 1
                    else:
                        ozet.bos_sayfa += 1
                    continue
                ozet.ardisik_ocr_bos = 0
                # Her sayfa okunur okunmaz yazılıyor: koşu saatler sürüyor
                # ve ortada düştüğünde okunmuş sayfalar hafızada kalmalı.
                for govde in paragraflara_bol(metin):
                    eklendi = depo.pasaj_ekle(
                        Pasaj(metin=govde, kaynak=kaynak, sayfa=no)
                    )
                    if eklendi is None:
                        ozet.atlanan += 1
                    else:
                        ozet.pasaj += 1
            if ozet.ardisik_ocr_bos >= ARDISIK_BOS_SINIRI:
                # Arka uç (llama-server) çökmüş olabilir. Sessizce devam
                # etmek 650 sayfayı boşa okutup koşuyu "hatasız" bitirir;
                # bu yüzden tanıyıcı bir kez yeniden kuruluyor ve sayaç
                # sıfırlanıyor. İkinci kez dolarsa koşu durur.
                if ocr_arka_ucu_sifirlandi:
                    raise RuntimeError(
                        f"OCR arka ucu {ozet.ardisik_ocr_bos} sayfadır boş "
                        "dönüyor ve yeniden kurulum işe yaramadı; koşu "
                        f"durduruldu (son sayfa {grup[-1]}). Okunanlar kayıtlı."
                    )
                _ocr_tanicisini_sifirla()
                ocr_arka_ucu_sifirlandi = True
                ozet.ardisik_ocr_bos = 0

            if ilerleme:
                ilerleme(grup[-1], son, ozet)
            yield ozet
    finally:
        belge.close()
