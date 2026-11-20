"""Ölçülmüş puanlama hataları için regresyon çitleri.

Bu dosyadaki her test, yazıldığı anda KIRMIZI yanan gerçek bir hatayı
sabitler. Hepsi öğretmenin gördüğü puanı doğrudan etkiliyordu; kapsam veya
lint bunları yakalayamaz, yalnız senaryoyu çalıştırmak yakalar.
"""

from __future__ import annotations

import pytest

from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Soru,
    SoruTipi,
)
from sinav_okur.puanlama import puanla
from sinav_okur.puanlama.ayarlar import PuanlamaAyar


def _acik_uclu(rubrik: list[RubrikKalemi], puan: float = 10.0) -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.ACIK_UCLU,
        metin="Mitokondrinin görevi nedir?",
        puan=puan,
        anahtar=CevapAnahtari(rubrik=rubrik),
    )


# --- (A) Olumsuzluk bulaşması ------------------------------------------------


def test_ek_olumsuz_cumle_dogru_kalemi_sifirlamaz():
    """Doğru cevabın yanına doğru bir olumsuz cümle eklemek puanı silmemeli.

    Ölçüldü: tek cümlelik hâli 10.0 alırken, olumsuz yan cümle eklenince
    tüm olumlu rubrik kalemleri "çelişki" sayılıp 0.0'a düşüyordu.
    Biyolojide olumsuz yan cümle çok yaygın ("...bulunmaz", "...gerçekleşmez").
    """
    soru = _acik_uclu([RubrikKalemi("Mitokondri ATP üretir", 10.0)])

    tek_cumle = puanla("Mitokondri ATP üretir.", soru)
    iki_cumle = puanla(
        "Mitokondri ATP üretir. Kloroplast ise hayvan hücresinde bulunmaz.",
        soru,
    )

    assert tek_cumle.puan == pytest.approx(10.0)
    assert iki_cumle.puan == pytest.approx(10.0)


def test_kalemin_kendi_cumlesindeki_olumsuzluk_hala_celiski():
    """Gerçek yön terslikleri yakalanmaya devam etmeli (dar hâl korunur)."""
    soru = _acik_uclu([RubrikKalemi("Mitokondri ATP üretir", 10.0)])

    sonuc = puanla("Mitokondri ATP üretmez.", soru)

    assert sonuc.puan == pytest.approx(0.0)


# --- (B) Sayısalda "herhangi bir sayı" eşleşmesi -----------------------------


def _sayisal(dogru: list[str], puan: float = 10.0, **anahtar) -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.SAYISAL,
        metin="Kaç mol gerekir?",
        puan=puan,
        anahtar=CevapAnahtari(dogru_cevaplar=dogru, **anahtar),
    )


def test_ara_islemdeki_dogru_sayi_tam_puan_vermez():
    """Yanlış nihai sonuç, ara işlemde doğru sayıyı andı diye tam puan almamalı.

    Ölçüldü: "Önce 0.5 ile çarptım, sonuç 12 mol buldum" → 10.0 puan ve
    incele=False. Sınıf mevcudunca tekrar eden, öğretmenin hiç görmediği
    sistematik bir yanlış puan.
    """
    soru = _sayisal(["0,5 mol"])

    sonuc = puanla("Önce 0.5 ile çarptım, sonuç 12 mol buldum", soru)

    assert sonuc.puan < 10.0
    assert sonuc.incele is True


def test_dogru_nihai_sonuc_tam_puan_alir():
    """Düzeltme, doğru cevabı cezalandırmamalı (regresyon çiti)."""
    soru = _sayisal(["0,5 mol"])

    sonuc = puanla("0,5 mol", soru)

    assert sonuc.puan == pytest.approx(10.0)


def test_ara_islem_yaninda_dogru_sonuc_tam_puan_alir():
    """Çözüm adımlarını yazan öğrenci cezalandırılmamalı."""
    soru = _sayisal(["0,5 mol"])

    sonuc = puanla("2 ile böldüm, sonuç 0,5 mol", soru)

    assert sonuc.puan == pytest.approx(10.0)


def test_kabul_edilen_alternatif_de_hedef_sayilir():
    """Ölçüldü: yalnız ilk beklenen sayı hedef alınıyor, alternatifler atılıyordu."""
    soru = _sayisal(["0,5 mol"], kabul_edilen_alternatifler=["1/2 mol"])

    sonuc = puanla("1/2 mol", soru)

    assert sonuc.puan == pytest.approx(10.0)


# --- (D) Esneklik profili ----------------------------------------------------


def _bosluk(dogru: list[str], esneklik: str) -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.BOSLUK_DOLDURMA,
        metin="Hücre bölünmesi türü?",
        puan=10.0,
        anahtar=CevapAnahtari(dogru_cevaplar=dogru),
        esneklik=esneklik,
    )


def test_esneklik_profili_bosluk_puanlamasina_ulasir():
    """Ölçüldü: BOSLUK'ta katı/dengeli/esnek üçü de 10.0 veriyordu.

    Arayüz genel bir "Puanlama esnekliği" ayarı sunuyor; profil yalnız rubriği
    etkilediği için öğretmen değiştirdiğini sandığı şeyi değiştiremiyordu.
    """
    ayar = PuanlamaAyar()
    sinirda = "mitozz"  # tam eşiğin hemen altında, ret eşiğinin üstünde

    kati = puanla(sinirda, _bosluk(["mitoz"], "kati"), ayar=ayar)
    esnek = puanla(sinirda, _bosluk(["mitoz"], "esnek"), ayar=ayar)

    assert (kati.puan, kati.incele) != (esnek.puan, esnek.incele)


def test_esneklik_varsayilani_dengeli_davranisi_korur():
    soru = _bosluk(["mitoz"], "dengeli")

    assert puanla("mitoz", soru).puan == pytest.approx(10.0)


# --- (E) İnceleme kuyruğunun sinyali ----------------------------------------


def test_tam_dogru_acik_uclu_kuyruga_dusmez():
    """Ölçüldü: gömlemci kapalıyken HER açık uçlu cevap kuyruğa düşüyordu.

    Tavan 0.6, inceleme eşiği 0.65 → tam doğru cevap bile bekleyenler
    listesine giriyor, kuyruk sinyal taşımıyordu.
    """
    soru = _acik_uclu(
        [
            RubrikKalemi("Mitokondri ATP üretir", 5.0),
            RubrikKalemi("Oksijenli solunum merkezidir", 5.0),
        ]
    )

    sonuc = puanla(
        "Mitokondri ATP üretir ve oksijenli solunum merkezidir.", soru
    )

    assert sonuc.puan == pytest.approx(10.0)
    assert sonuc.incele is False


def test_kucuk_paya_sahip_tek_kararsiz_kalem_kuyruga_atmaz():
    """min(guvenler) yerine puan ağırlıklı birleşim: 1 puanlık kararsız kalem
    9 puanlık kesin kalemleri kuyruğa sürüklememeli."""
    soru = _acik_uclu(
        [
            RubrikKalemi("Mitokondri ATP üretir", 9.0),
            RubrikKalemi("Krista adı verilen kıvrımları vardır", 1.0),
        ]
    )

    sonuc = puanla("Mitokondri ATP üretir.", soru)

    assert sonuc.incele is False


def test_buyuk_paya_sahip_kararsiz_karar_kuyruga_duser():
    """Asıl sinyal: risk altındaki puan payı. Cevabın çoğu kısmi puandaysa
    öğretmen görmeli."""
    soru = _acik_uclu(
        [
            RubrikKalemi("Mitokondri oksijenli solunumla ATP üretir", 9.0),
            RubrikKalemi("Çift zarlıdır", 1.0),
        ]
    )

    sonuc = puanla("Mitokondri solunum yapar, çift zarlıdır.", soru)

    assert sonuc.incele is True


# --- (C1) Rakip terim kapısı ------------------------------------------------


def test_iki_gercek_terime_esit_yakin_cevap_tam_puan_almaz():
    """Ölçüldü: "miyoz" hem "mitoz"a hem "mayoz"a 80 skorla eşleşiyor.

    Şüpheli bandın (70-88) tam ortasında, marj sıfır. Eskiden "geçici tam
    puan" veriliyordu; toplu onay bunu tek tıkla mühürleyebiliyordu.
    """
    soru = _bosluk(["mitoz"], "dengeli")
    terimler = {"mitoz", "mayoz", "hücre"}

    sonuc = puanla("miyoz", soru, bilinen_terimler=terimler)

    assert sonuc.puan == pytest.approx(0.0)
    assert sonuc.incele is True
    assert any(k.get("karar") == "kararsiz_terim" for k in sonuc.kararlar)


def test_rakipsiz_yazim_hatasi_gecici_puani_korur():
    """Şüpheli bandda ama rakipsiz yazım eski davranışını sürdürmeli.

    "mitokon" anahtara 82 skorla yakın (70-88 şüpheli bandı), diğer alan
    terimlerine uzak → belirsizlik yok, geçici tam puan + incele korunur.
    """
    soru = _bosluk(["mitokondri"], "dengeli")
    terimler = {"mitokondri", "ribozom", "kloroplast"}

    sonuc = puanla("mitokon", soru, bilinen_terimler=terimler)

    assert sonuc.puan == pytest.approx(10.0)
    assert sonuc.incele is True


def test_terim_listesi_yoksa_davranis_degismez():
    """bilinen_terimler verilmeyen çağrılar (eski kod yolları) etkilenmemeli."""
    soru = _bosluk(["mitoz"], "dengeli")

    assert puanla("miyoz", soru).puan == pytest.approx(10.0)
