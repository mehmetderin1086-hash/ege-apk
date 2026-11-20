"""chunk_tr cümle bölme ve paketleme testleri."""
from app.core.text.chunk_tr import chunk_text, split_sentences


# --- Cümle bölme -------------------------------------------------------------

def test_basit_bolme():
    s = split_sentences("Bugün hava güzel. Yarın yağmur bekleniyor.")
    assert s == ["Bugün hava güzel.", "Yarın yağmur bekleniyor."]


def test_unvan_kisaltmasi_bolunmez():
    s = split_sentences("Dr. Ahmet geldi. Hastayı muayene etti.")
    assert s == ["Dr. Ahmet geldi.", "Hastayı muayene etti."]


def test_tek_harf_bas_harfi_bolunmez():
    s = split_sentences("Yazar A. Hamdi Tanpınar çok sevilir.")
    assert len(s) == 1


def test_sira_sayisi_bolunmez():
    s = split_sentences("O 2. Dünya Savaşı sırasında doğdu.")
    assert len(s) == 1


def test_unlem_soru():
    s = split_sentences("Ne güzel! Sen de gelir misin? Elbette.")
    assert s == ["Ne güzel!", "Sen de gelir misin?", "Elbette."]


def test_ondalik_bolunmez():
    s = split_sentences("Oran 3.14 çıktı. Şaşırdık.")
    assert s == ["Oran 3.14 çıktı.", "Şaşırdık."]


def test_tirnakli_cumle():
    s = split_sentences('"Geliyorum." Dedi ve kapıyı kapattı.')
    assert len(s) == 2


def test_noktasiz_kuyruk():
    s = split_sentences("Tamamlanmış cümle. sonra devam eden bir parça")
    # küçük harfle başlayan kuyruk yeni cümle sayılmaz (aday bile değil)
    assert len(s) == 1 or s[-1].startswith("sonra") is False


def test_coklu_bas_harf_bolunmez():
    # "A.H." gibi çoklu baş harfler cümle sonu sayılmaz
    s = split_sentences("Yazar A.H. Tanpınar çok sevilir.")
    assert len(s) == 1


def test_parantezli_kisaltma_bolunmez():
    s = split_sentences("Sayın (Dr.) Ahmet geldi. Hastayı gördü.")
    assert len(s) == 2
    assert s[0].endswith("geldi.")


# --- Paketleme ----------------------------------------------------------------

def test_kisa_metin_tek_parca():
    chunks = chunk_text("Merhaba dünya. Nasılsın?")
    assert len(chunks) == 1
    assert chunks[0].text == "Merhaba dünya. Nasılsın?"


def test_hedef_uzunluk_asilmaz():
    text = " ".join(f"Bu {i} numaralı deneme cümlesidir." for i in range(30))
    chunks = chunk_text(text, target=250, hard=300)
    assert all(c.chars <= 300 for c in chunks)
    assert len(chunks) > 1


def test_asiri_uzun_cumle_bolunur():
    # Tek cümle, 300 karakterden uzun, virgüllerle bölünebilir
    text = ", ".join(f"madde {i} hakkında uzun bir açıklama" for i in range(20)) + "."
    chunks = chunk_text(text, target=250, hard=300)
    assert all(c.chars <= 300 for c in chunks)


def test_paragraf_isareti():
    text = "İlk paragraf burada.\n\nİkinci paragraf burada."
    chunks = chunk_text(text)
    assert len(chunks) == 2
    assert chunks[0].paragraph_break is True
    assert chunks[1].paragraph_break is False  # son parça


def test_indeksler_sirali():
    text = "Bir. İki. Üç.\n\nDört. Beş."
    chunks = chunk_text(text, target=10, hard=300)
    assert [c.i for c in chunks] == list(range(len(chunks)))


def test_bos_metin():
    assert chunk_text("") == []
    assert chunk_text("   \n\n  ") == []
