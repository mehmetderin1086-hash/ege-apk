"""Soru Kesici arşivi okuma testleri.

Künye şeması gerçek arşivlerden alındı (algoritma sürümü 3.4): her kayıtta
`dosya`, `metin`, `govde`, `siklar`, `konu`, `guven`/`kalibre_guven`,
`kaynak`, `sayfa` var; `cevap` ve çözüm alanları İNCELENEN ÜÇ ARŞİVİN
HİÇBİRİNDE dolu değil — bu yüzden arşiv referans örnek değil, çözülecek soru
kaynağıdır.
"""

from __future__ import annotations

import io
import json
import zipfile

import pytest

from biyo_cozucu.alim import AlimHatasi
from biyo_cozucu.alim.soru_kesici import arsivi_ac, ozet, sorulari_oku


def _png() -> bytes:
    pytest.importorskip("PIL")
    from PIL import Image

    tampon = io.BytesIO()
    Image.new("RGB", (12, 8), (200, 30, 30)).save(tampon, format="PNG")
    return tampon.getvalue()


def _kayit(no: int, **degisiklik) -> dict:
    kayit = {
        "dosya": f"soru_{no:02d}.png",
        "sayfa": no,
        "kaynak": "10.sınıf.pdf",
        "cevap": None,
        "metin": f"Soru-{no}) Fotosentezde klorofil hangi olayı başlatır?",
        "govde": f"Soru-{no}) 20 PUAN",
        "siklar": {"A": "Işık soğurulur", "B": "Su parçalanır"},
        "konu": "Fotosentez ve Solunum",
        "guven": 0.9,
        "kalibre_guven": 0.87,
    }
    kayit.update(degisiklik)
    return kayit


def _arsiv_yaz(yol, kayitlar, *, gorseller=True, ust_klasor="") -> None:
    with zipfile.ZipFile(yol, "w") as z:
        onek = f"{ust_klasor}/" if ust_klasor else ""
        z.writestr(f"{onek}sorular.json", json.dumps(kayitlar, ensure_ascii=False))
        if gorseller:
            for kayit in kayitlar:
                if kayit.get("dosya"):
                    z.writestr(f"{onek}{kayit['dosya']}", _png())


def test_zip_arsivinden_sorular_okunur(tmp_path):
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1), _kayit(2)])

    with arsivi_ac(yol) as (_kok, sorular):
        assert len(sorular) == 2
        ilk = sorular[0]
        assert "klorofil" in ilk.soru
        assert ilk.secenekler == {"A": "Işık soğurulur", "B": "Su parçalanır"}
        assert ilk.konu == "Fotosentez ve Solunum"
        assert ilk.gorsel_yolu is not None and ilk.gorsel_yolu.is_file()
        assert ilk.kaynak_adi() == "10.sınıf.pdf · s. 1"


def test_acilmis_klasor_de_okunur(tmp_path):
    """Kullanıcı arşivi elle açmış olabilir; ikisi de aynı yoldan geçmeli."""
    dizin = tmp_path / "acilmis"
    dizin.mkdir()
    (dizin / "sorular.json").write_text(
        json.dumps([_kayit(1)], ensure_ascii=False), encoding="utf-8"
    )
    (dizin / "soru_01.png").write_bytes(_png())

    with arsivi_ac(dizin) as (_kok, sorular):
        assert len(sorular) == 1
        assert sorular[0].gorsel_yolu is not None


def test_tek_ust_klasorlu_arsiv_de_bulunur(tmp_path):
    """Bazı arşivler tüm içeriği tek bir klasörün altında getiriyor."""
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1)], ust_klasor="10.sinif")

    with arsivi_ac(yol) as (_kok, sorular):
        assert len(sorular) == 1
        assert sorular[0].gorsel_yolu is not None


def test_kalibre_guven_ham_guvene_tercih_edilir(tmp_path):
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1, guven=0.9, kalibre_guven=0.42)])
    with arsivi_ac(yol) as (_kok, sorular):
        assert sorular[0].guven == pytest.approx(0.42)


def test_metinsiz_kayit_atlanir(tmp_path):
    """Kırpma başarısız olduğunda metin boş kalabiliyor; çözülecek bir şey yok."""
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1, metin=""), _kayit(2)])
    with arsivi_ac(yol) as (_kok, sorular):
        assert len(sorular) == 1


def test_gorseli_olmayan_kayit_yine_de_okunur(tmp_path):
    """Görüntü eksikse soru metinle çözülebilmeli, tümden düşmemeli."""
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1)], gorseller=False)
    with arsivi_ac(yol) as (_kok, sorular):
        assert len(sorular) == 1
        assert sorular[0].gorsel_yolu is None


def test_bos_sik_degerleri_elenir(tmp_path):
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1, siklar={"A": "dolu", "B": "  ", "c": "küçük harf"})])
    with arsivi_ac(yol) as (_kok, sorular):
        assert sorular[0].secenekler == {"A": "dolu", "C": "küçük harf"}


def test_kunyesiz_arsiv_anlamli_hata_verir(tmp_path):
    yol = tmp_path / "bos.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("okuma.txt", "içerik")
    with pytest.raises(AlimHatasi, match=r"sorular\.json"):
        sorulari_oku(yol)


def test_zip_olmayan_dosya_reddedilir(tmp_path):
    yol = tmp_path / "kitap.pdf"
    yol.write_bytes(b"%PDF-1.4")
    with pytest.raises(AlimHatasi, match="zip"):
        sorulari_oku(yol)


def test_bozuk_kunye_anlamli_hata_verir(tmp_path):
    yol = tmp_path / "arsiv.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("sorular.json", "{bu json degil")
    with pytest.raises(AlimHatasi, match="okunamadı"):
        sorulari_oku(yol)


def test_kunye_liste_degilse_reddedilir(tmp_path):
    yol = tmp_path / "arsiv.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("sorular.json", json.dumps({"soru": 1}))
    with pytest.raises(AlimHatasi, match="liste değil"):
        sorulari_oku(yol)


def test_zip_slip_engellenir(tmp_path):
    """Arşiv üyesi hedef dizinin dışına yazamamalı (`model-kur`'daki koruma)."""
    yol = tmp_path / "kotu.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("sorular.json", json.dumps([_kayit(1)]))
        z.writestr("../kacak.txt", "buraya yazılmamalı")
    with pytest.raises(AlimHatasi, match="güvensiz yol"):
        sorulari_oku(yol)


def test_ozet_konu_ve_gorsel_sayilarini_verir(tmp_path):
    yol = tmp_path / "arsiv.zip"
    _arsiv_yaz(yol, [_kayit(1), _kayit(2, konu="Ekoloji", siklar={})])
    with arsivi_ac(yol) as (_kok, sorular):
        kunye = ozet(sorular)
    assert kunye["soru"] == 2
    assert kunye["gorselli"] == 2
    assert kunye["sikli"] == 1
    assert kunye["kaynaklar"] == ["10.sınıf.pdf"]
    assert kunye["konu_dagilimi"]["Ekoloji"] == 1
