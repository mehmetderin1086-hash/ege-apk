from sinav_okur.metin import aksansiz, cumleler, eslesme_bicimi, kucult, nfc


def test_turkce_kucultme():
    assert kucult("İSTANBUL") == "istanbul"
    assert kucult("IRMAK") == "ırmak"
    assert kucult("Hücre") == "hücre"


def test_eslesme_bicimi_noktalama_bosluk():
    assert eslesme_bicimi("  Mitokondri, (organel)! ") == "mitokondri organel"


def test_aksansiz_katlama():
    assert aksansiz("hücre") == "hucre"
    assert aksansiz("ĞİŞÇÖÜ") == "giscou"


def test_nfc_birlestirme():
    ayrik = "ü"  # u + combining diaeresis
    assert nfc(ayrik) == "ü"
    assert len(nfc(ayrik)) == 1


def test_cumle_bolme():
    assert cumleler("Bir. İki! Üç?\nDört") == ["Bir", "İki", "Üç", "Dört"]
