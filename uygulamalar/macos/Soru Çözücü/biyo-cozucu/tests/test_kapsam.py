"""Hafıza kapsamı raporunun testleri.

Buradaki asıl soru "sayı doğru mu" değil, **öneri işe yarar mı**: rapor
kullanıcıya sırada hangi soruyu yazacağını söylüyor, yanlış yönlendirirse
hafıza yanlış yöne büyür.
"""

from __future__ import annotations

from biyo_cozucu.kapsam import LORA_ESIGI, RAG_ESIGI, kapsami_cikar
from biyo_cozucu.modeller import COZUM_TURLERI


def test_bos_hafizada_tum_turler_eksik_bildirilir():
    rapor = kapsami_cikar({})
    assert rapor.toplam == 0
    assert rapor.dolu_hucre == 0
    assert set(rapor.bos_turler) == set(COZUM_TURLERI)
    assert rapor.esige_kalan(RAG_ESIGI) == RAG_ESIGI
    assert rapor.esige_kalan(LORA_ESIGI) == LORA_ESIGI
    assert rapor.oneriler == [], "hiç örnek yokken konu önerisi anlamsız"


def test_hic_ornegi_olmayan_tur_icin_konu_onerilmez():
    """Regresyon: boş türe konu eşlemek "destek ve hareket × kalıtım hesabı"
    gibi biyolojik olarak anlamsız çiftler üretiyordu.

    Boş tür zaten `bos_turler`de ve daha güçlü biçimde bildiriliyor.
    """
    rapor = kapsami_cikar({("kalıtım", "kalitim_hesabi"): 3})
    onerilen_turler = {o.cozum_turu for o in rapor.oneriler}
    assert not (onerilen_turler & set(rapor.bos_turler))
    assert "kalitim_hesabi" in onerilen_turler, "var olan türdeki konu boşluğu gerçek"


def test_oneriler_ayni_konuyu_tekrarlamaz():
    """Her tür için ayrı ayrı "en boş konu" seçilseydi liste baştan sona aynı
    konuyu önerir, kullanıcıya tek konudan yedi soru yazdırırdı."""
    matris = {
        ("kalıtım", "kalitim_hesabi"): 2,
        ("fotosentez", "grafik_yorumlama"): 1,
        ("enzimler", "mekanizma_aciklama"): 1,
        ("hücre", "ezber_bilgi"): 1,
    }
    rapor = kapsami_cikar(matris)
    konular = [o.konu for o in rapor.oneriler]
    assert len(konular) == len(set(konular))


def test_dolu_hucre_yalniz_taninan_konulari_sayar():
    """Kural tabanlı etiketleyicinin tanımadığı konu adları matrise girebilir
    (elle yazılmış etiketler); hücre oranını şişirmemeli."""
    rapor = kapsami_cikar(
        {("kalıtım", "kalitim_hesabi"): 1, ("uydurma konu", "kalitim_hesabi"): 5}
    )
    assert rapor.dolu_hucre == 1
    assert rapor.toplam == 6, "toplam yine de tüm örnekleri saymalı"


def test_tur_dagilimi_matristen_toplanir():
    rapor = kapsami_cikar(
        {("kalıtım", "kalitim_hesabi"): 2, ("hücre", "kalitim_hesabi"): 3}
    )
    assert rapor.tur_dagilimi["kalitim_hesabi"] == 5
    assert rapor.konu_dagilimi["kalıtım"] == 2
    assert "kalitim_hesabi" not in rapor.bos_turler


def test_esik_asildiginda_kalan_sifir():
    rapor = kapsami_cikar({("kalıtım", "kalitim_hesabi"): LORA_ESIGI + 10})
    assert rapor.esige_kalan(RAG_ESIGI) == 0
    assert rapor.esige_kalan(LORA_ESIGI) == 0


def test_metin_raporu_eksikleri_yazar():
    rapor = kapsami_cikar({("kalıtım", "kalitim_hesabi"): 1})
    metin = rapor.metin()
    assert "RAG eşiğine" in metin
    assert "Hiç örneği olmayan çözüm türü" in metin
    assert "grafik_yorumlama" in metin


def test_oneri_sayisi_sinirlanir():
    matris = {(konu, "kalitim_hesabi"): 1 for konu in ("kalıtım", "hücre")}
    rapor = kapsami_cikar(matris, oneri_sayisi=1)
    assert len(rapor.oneriler) <= 1


def test_yeni_kanonik_konular_matriste_sayilir():
    """Palme paketinin ilk iki ünitesi bu konulara düşüyor; eksen onları görmeli."""
    rapor = kapsami_cikar(
        {
            ("canlıların temel bileşenleri", "ezber_bilgi"): 114,
            ("canlıların ortak özellikleri", "grafik_yorumlama"): 50,
        }
    )
    assert rapor.toplam == 164
    assert rapor.dolu_hucre == 2
    assert "canlıların temel bileşenleri" not in rapor.bos_konular
    assert "canlıların ortak özellikleri" not in rapor.bos_konular
