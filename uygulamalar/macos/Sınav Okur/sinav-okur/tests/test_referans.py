import numpy as np

from sinav_okur.referans import pasajlara_bol
from sinav_okur.referans.kitap import KitapDeposu, KitapPasaji


def test_pasaj_bolme_uzun_paragraf():
    metin = " ".join(f"cümle{i} kelime kelime kelime kelime." for i in range(40))
    pasajlar = pasajlara_bol(metin, max_kelime=30)
    assert len(pasajlar) > 1
    assert all(len(p.split()) <= 60 for p in pasajlar)


def test_pasaj_kisa_birlestir():
    metin = "Kısa.\n\n" + "uzun " * 20
    pasajlar = pasajlara_bol(metin, min_kelime=5)
    # çok kısa ilk parça, ya birleşti ya elendi; boş dönmemeli
    assert pasajlar


class KelimeGomlemci:
    """Basit torbalama gömlemci: sabit sözlükte kelime varlığına göre vektör."""

    SOZLUK = ["mitokondri", "enerji", "kloroplast", "fotosentez", "hücre"]

    def gom(self, metinler):
        vek = []
        for m in metinler:
            ml = m.lower()
            vek.append([1.0 if k in ml else 0.0 for k in self.SOZLUK])
        return np.array(vek, dtype=float)


def test_kitap_deposu_erisim(tmp_path):
    g = KelimeGomlemci()
    kaynak = tmp_path / "ders.txt"
    kaynak.write_text(
        "Mitokondri hücrenin enerji üretim merkezidir ve solunum yapar burada.\n\n"
        "Kloroplast fotosentez yapan yeşil organeldir bitki hücrelerinde bulunur.\n\n"
        "Ribozom protein sentezi yapan yapıdır hücrede çok sayıda bulunur.",
        encoding="utf-8",
    )
    depo = KitapDeposu.kur([kaynak], g)
    assert len(depo.pasajlar) == 3

    sonuc = depo.ilgili("enerji üreten organel nedir", g, k=1)
    assert "mitokondri" in sonuc[0][0].metin.lower()

    # kaydet/yükle gidiş-dönüş
    depo.kaydet(tmp_path / "idx")
    tekrar = KitapDeposu.yukle(tmp_path / "idx")
    assert len(tekrar.pasajlar) == 3
    sonuc2 = tekrar.ilgili("fotosentez nerede olur", g, k=1)
    assert "kloroplast" in sonuc2[0][0].metin.lower()


def test_referansli_puanlama_incele_bayragi():
    """Cevap kitapla örtüşüyor ama rubrik kaçırıyorsa incele işaretlenmeli."""
    from sinav_okur.modeller import CevapAnahtari, RubrikKalemi, Soru, SoruTipi
    from sinav_okur.puanlama.rubrik import rubrik_puanla

    g = KelimeGomlemci()
    soru = Soru(no=1, tip=SoruTipi.ACIK_UCLU, metin="mitokondri görevi", puan=20,
                anahtar=CevapAnahtari(rubrik=[
                    RubrikKalemi("ATP sentezler", 10),
                    RubrikKalemi("oksijenli solunum yapar", 10)]))
    # Öğrenci kitabın diliyle yazmış ama rubrik anahtar kelimeleri yok
    cevap = "mitokondri hücrenin enerji merkezidir"
    pasajlar = ["Mitokondri hücrenin enerji üretim merkezidir enerji sağlar"]
    sonuc = rubrik_puanla(cevap, soru, gomlemci=g, referans_pasajlari=pasajlar)
    assert sonuc.incele  # düşük rubrik puanı + yüksek kitap örtüşmesi → incele
    assert any("Kitap örtüşmesi" in d for d in sonuc.detaylar)
