"""Excel (.xlsx) çıktıları: not çizelgesi, devamsızlık, yıllık plan, kazanım analizi.

e-Okul'a elle giriş yaparken ve yedek alırken kullanılır; bu yüzden sütun
düzeni ekrandaki tabloyla aynı tutuldu.
"""

from __future__ import annotations

import io

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from ..plan.yillik import TUR_TATIL, PlanSatiri

BASLIK_DOLGU = PatternFill("solid", fgColor="E8EEF7")
BASLIK_YAZI = Font(bold=True)
SARMA = Alignment(wrap_text=True, vertical="top")


def _excel_degeri(deger):
    """Kullanıcı metninin Excel tarafından formül olarak çalıştırılmasını önler."""
    if isinstance(deger, str) and deger and deger[0] in "=+-@\t\r":
        return "'" + deger
    return deger


def _satir_ekle(sayfa, degerler: list) -> None:
    sayfa.append([_excel_degeri(d) for d in degerler])


def _basliklari_yaz(sayfa, basliklar: list[str], genislikler: list[float]) -> None:
    _satir_ekle(sayfa, basliklar)
    for sutun, genislik in enumerate(genislikler, start=1):
        sayfa.column_dimensions[get_column_letter(sutun)].width = genislik
        hucre = sayfa.cell(row=1, column=sutun)
        hucre.fill = BASLIK_DOLGU
        hucre.font = BASLIK_YAZI
        hucre.alignment = SARMA
    sayfa.freeze_panes = "A2"


def _kitabi_bayta_cevir(kitap: Workbook) -> bytes:
    tampon = io.BytesIO()
    kitap.save(tampon)
    return tampon.getvalue()


def not_cizelgesi_xlsx(
    ogrenciler: list[dict],
    degerlendirmeler: list[dict],
    *,
    sube_adi: str,
) -> bytes:
    """Öğrenci × değerlendirme çizelgesi; dönem ortalaması sütunlarıyla."""
    kitap = Workbook()
    sayfa = kitap.active
    sayfa.title = f"{sube_adi} notlar"[:31]

    basliklar = ["No", "Adı Soyadı"]
    basliklar += [f"{d['ad']} ({d['donem']}. dönem)" for d in degerlendirmeler]
    basliklar += ["1. Dönem", "2. Dönem", "Yıl Sonu", "Durum"]
    genislikler = [7, 26] + [14] * len(degerlendirmeler) + [11, 11, 11, 10]
    _basliklari_yaz(sayfa, basliklar, genislikler)

    for ogrenci in ogrenciler:
        satir = [ogrenci.get("numara", ""), ogrenci["ad_soyad"]]
        satir += [ogrenci["puanlar"].get(d["id"]) for d in degerlendirmeler]
        satir += [
            ogrenci.get("donem1"),
            ogrenci.get("donem2"),
            ogrenci.get("yil_sonu"),
            ogrenci.get("durum", ""),
        ]
        _satir_ekle(sayfa, satir)

    return _kitabi_bayta_cevir(kitap)


def devamsizlik_xlsx(kayitlar: list[dict], *, sube_adi: str) -> bytes:
    kitap = Workbook()
    sayfa = kitap.active
    sayfa.title = f"{sube_adi} devamsızlık"[:31]
    _basliklari_yaz(
        sayfa,
        ["No", "Adı Soyadı", "Toplam ders", "Gelmedi (saat)", "İzinli", "Geç", "Devam %", "Uyarı"],
        [7, 26, 12, 14, 10, 8, 10, 30],
    )
    for kayit in kayitlar:
        _satir_ekle(
            sayfa,
            [
                kayit.get("numara", ""),
                kayit["ad_soyad"],
                kayit["toplam_ders"],
                kayit["yok_saat"],
                kayit["izinli_saat"],
                kayit["gec_saat"],
                kayit.get("devam_orani"),
                kayit.get("uyari", ""),
            ]
        )
    return _kitabi_bayta_cevir(kitap)


def yillik_plan_xlsx(
    satirlar: list[PlanSatiri], *, sube_adi: str, ogretim_yili: str
) -> bytes:
    kitap = Workbook()
    sayfa = kitap.active
    sayfa.title = f"{sube_adi} yıllık plan"[:31]
    _basliklari_yaz(
        sayfa,
        [
            "Ay",
            "Hafta",
            "Tarih",
            "Saat",
            "Tema",
            "Kazanım kodları",
            "Kazanımlar",
            "Yöntem-teknik",
            "Araç-gereç",
            "Ölçme",
            "Diğer derslerle ilişkilendirme",
            "Belirli gün ve haftalar",
            "Açıklama",
        ],
        [10, 7, 18, 6, 16, 20, 52, 26, 22, 26, 26, 24, 24],
    )
    for satir in satirlar:
        _satir_ekle(
            sayfa,
            [
                satir.ay,
                satir.hafta_no,
                f"{satir.baslangic} – {satir.bitis}",
                satir.ders_saati,
                satir.tema_adi,
                ", ".join(satir.kazanim_kodlari),
                "\n".join(satir.kazanim_ifadeleri)
                if satir.tur != TUR_TATIL
                else satir.aciklama,
                ", ".join(satir.yontem_teknik),
                ", ".join(satir.arac_gerec),
                ", ".join(satir.olcme_degerlendirme),
                ", ".join(satir.disiplinler_arasi),
                ", ".join(satir.belirli_gunler),
                satir.aciklama,
            ]
        )
    for satir_nesnesi in sayfa.iter_rows(min_row=2):
        for hucre in satir_nesnesi:
            hucre.alignment = SARMA

    ozet = kitap.create_sheet("Özet")
    _basliklari_yaz(ozet, ["Öğretim yılı", "Şube", "Hafta", "Ders saati", "Kazanım"], [16, 10, 9, 12, 10])
    _satir_ekle(
        ozet,
        [
            ogretim_yili,
            sube_adi,
            len(satirlar),
            sum(s.ders_saati for s in satirlar),
            len({k for s in satirlar for k in s.kazanim_kodlari}),
        ]
    )
    return _kitabi_bayta_cevir(kitap)


def kazanim_analizi_xlsx(
    ogrenciler: list[dict], kazanimlar: list[str], *, sube_adi: str
) -> bytes:
    """Öğrenci × kazanım ısı tablosu (yüzde)."""
    kitap = Workbook()
    sayfa = kitap.active
    sayfa.title = "Kazanım analizi"
    _basliklari_yaz(
        sayfa,
        ["No", "Adı Soyadı", *kazanimlar, "Ortalama"],
        [7, 26] + [12] * len(kazanimlar) + [11],
    )
    for ogrenci in ogrenciler:
        yuzdeler = [ogrenci["kazanimlar"].get(k) for k in kazanimlar]
        gecerli = [y for y in yuzdeler if y is not None]
        _satir_ekle(
            sayfa,
            [
                ogrenci.get("numara", ""),
                ogrenci["ad_soyad"],
                *yuzdeler,
                round(sum(gecerli) / len(gecerli), 1) if gecerli else None,
            ]
        )
    return _kitabi_bayta_cevir(kitap)
