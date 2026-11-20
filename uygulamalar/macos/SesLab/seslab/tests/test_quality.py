"""STT geri beslemeli onarım mantığı testleri (model gerektirmez)."""
import numpy as np
import pytest

from app.core import synth
from app.core.quality import (
    find_leading_cut,
    find_trailing_cut,
    has_material_omission,
    has_material_replacement,
    has_mid_insertion,
    has_tail_fusion,
    similarity,
)
from app.core.text.chunk_tr import chunk_text, tts_sanitize


def w(word: str, start: float, end: float) -> dict:
    return {"word": word, "start": start, "end": end}


SOURCE = "Türkiye'nin en kalabalık şehri İstanbul, iki kıtayı birbirine bağlar."


def test_kuyruk_halusinasyonu_kesilir():
    # Whisper sonda fazladan "dağ" duydu → son gerçek kelimenin bitiminde kes
    words = [
        w("Türkiye'nin", 0.0, 0.6), w("en", 0.7, 0.8), w("kalabalık", 0.9, 1.4),
        w("şehri", 1.5, 1.9), w("İstanbul,", 2.0, 2.6), w("iki", 2.7, 2.9),
        w("kıtayı", 3.0, 3.4), w("birbirine", 3.5, 4.0), w("bağlar", 4.1, 4.5),
        w("dağ.", 4.6, 5.1),
    ]
    cut = find_trailing_cut(SOURCE, words)
    assert cut is not None
    assert 4.5 < cut < 4.8  # "bağlar" bitişi + pay; "dağ" atılır


CLEAN_WORDS = [
    w("Türkiye'nin", 0.0, 0.6), w("en", 0.7, 0.8), w("kalabalık", 0.9, 1.4),
    w("şehri", 1.5, 1.9), w("İstanbul,", 2.0, 2.6), w("iki", 2.7, 2.9),
    w("kıtayı", 3.0, 3.4), w("birbirine", 3.5, 4.0), w("bağlar.", 4.1, 4.5),
]


def test_temiz_uretimde_kesim_yok():
    # Kısa doğal düşüş (son kelime 4.5'te bitiyor, ses 4.7'de) → dokunma
    assert find_trailing_cut(SOURCE, CLEAN_WORDS, audio_dur_s=4.7) is None


def test_uzun_ses_kuyrugu_kesilir():
    # Kelime fazlası yok ama son kelimeden sonra 1 sn'lik mırıltı var → kes
    cut = find_trailing_cut(SOURCE, CLEAN_WORDS, audio_dur_s=5.5)
    assert cut is not None
    assert 4.6 < cut < 4.9  # bağlar bitişi (4.5) + END_PAD


def test_cekirdek_bozuksa_kesim_yapilmaz():
    # Kaynağın çoğu eşleşmiyorsa kuyruk kesimi çözüm değil (retry işi)
    words = [w("alakasız", 0.0, 0.5), w("kelimeler", 0.6, 1.2), w("var", 1.3, 1.6)]
    assert find_trailing_cut(SOURCE, words) is None


def test_bos_girdiler():
    assert find_trailing_cut(SOURCE, []) is None
    assert find_trailing_cut("", [w("bir", 0, 1)]) is None


def test_benzerlik_normalize_uzerinden():
    # Whisper rakamlaştırsa bile benzerlik yüksek kalmalı (normalize_tr köprüsü)
    src = "Yarın saat on dört otuzda toplantımız var."
    hyp = "Yarın saat 14:30'da toplantımız var."
    assert similarity(src, hyp) > 0.95


def test_benzerlik_dusuk_farkli_metin():
    assert similarity("Bugün hava güzel.", "Yağmur yağıyor bütün gün.") < 0.6


# --- Ara ekleme dedektörü -------------------------------------------------------

def test_ara_ekleme_yakalanir():
    src = "İki kıtayı birbirine bağlayan güzel bir şehir burası."
    hyp = "İki kıtayı birbirine falan bağlayan güzel bir şehir burası."
    assert has_mid_insertion(src, hyp) is True


def test_whisper_kelime_bolmesi_yanlis_pozitif_degil():
    # "başarıyla" → "başarı ile": replace'tir, saf ekleme değil
    src = "Projeyi başarıyla tamamladık."
    hyp = "Projeyi başarı ile tamamladık."
    assert has_mid_insertion(src, hyp) is False


def test_kuyruk_eklemesi_ara_ekleme_sayilmaz():
    # Sondaki fazlalık kuyruk kesicinin işi
    src = "İki kıtayı birbirine bağlar."
    hyp = "İki kıtayı birbirine bağlar dağ."
    assert has_mid_insertion(src, hyp) is False


def test_ayni_metin_ekleme_yok():
    src = "Bugün hava çok güzel."
    assert has_mid_insertion(src, src) is False


# --- Kelime atlama / belirgin telaffuz sapması -------------------------------------

def test_son_cumle_atlamasi_yakalanir():
    src = "Sonunda kendinize bambaşka gözlerle bakacaksınız. Söz veriyorum."
    hyp = "Sonunda kendinize bambaşka gözlerle bakacaksınız."
    assert has_material_omission(src, hyp) is True


def test_tek_kisa_whisper_atlamasi_yanlis_pozitif_degil():
    assert has_material_omission("Bugün de hava güzel.", "Bugün hava güzel.") is False


def test_belirgin_telaffuz_sapmasi_yakalanir():
    assert has_material_replacement(
        "İşte tam şu an nefes alıyorsunuz.",
        "Üçte tam şu an nefes alıyorsunuz.",
    ) is True


def test_yakin_bicim_ve_kelime_bolmesi_kabul_edilir():
    assert has_material_replacement("Bedeni neyden yapılmıştır?", "Bedeni neden yapılmıştır?") is False
    assert has_material_replacement("Projeyi başarıyla bitirdi.", "Projeyi başarı ile bitirdi.") is False


# --- Baş artefaktı kesici ---------------------------------------------------------

def test_bas_artefakti_kesilir():
    # "Anne." başta fazlalık → ilk gerçek kelimenin öncesinden başlat
    src = "Konser başladı."
    words = [w("Anne.", 0.0, 0.35), w("Konser", 0.6, 1.0), w("başladı.", 1.1, 1.6)]
    cut = find_leading_cut(src, words)
    assert cut is not None
    assert 0.5 <= cut <= 0.6  # "Konser" başlangıcı - pay


def test_temiz_baslangicta_kesim_yok():
    src = "Konser başladı."
    words = [w("Konser", 0.05, 0.5), w("başladı.", 0.6, 1.1)]
    assert find_leading_cut(src, words) is None


# --- Kuyruk kaynaşması dedektörü -----------------------------------------------------

def test_kuyruk_kaynasmasi_yakalanir():
    # Bataryada görülen gerçek vakalar — hepsi yakalanmalı
    assert has_tail_fusion("Sanatçı sahneye çıktı.", "Sanatçı sahneye çıktıda.") is True
    assert has_tail_fusion("Dikkatli ol.", "Dikkatli olduğunu.") is True
    assert has_tail_fusion("Tehlikeli olabilir, dikkatli ol.",
                           "Tehlikeli olabilir, dikkatli olsun.") is True


def test_kuyruk_kaynasmasi_normal_metin():
    src = "Bugün hava çok güzel."
    assert has_tail_fusion(src, src) is False
    assert has_tail_fusion(src, "Bugün hava çok güzeldi.") is True  # güzel→güzeldi


# --- TTS-güvenli noktalama ---------------------------------------------------------

def test_uc_nokta_sadelesir():
    assert tts_sanitize("Bekledi... Sonra gitti…") == "Bekledi. Sonra gitti."


def test_tire_ve_noktali_virgul():
    assert tts_sanitize("Geldi; baktı — ve gitti.") == "Geldi, baktı, ve gitti."


def test_coklu_unlem():
    assert tts_sanitize("Harika!!! Gerçekten mi??") == "Harika! Gerçekten mi!"


# --- Cümle-başına parçalama (XTTS modu) ----------------------------------------------

def test_pack_false_cumle_basina():
    text = "Birinci cümle burada. İkinci cümle burada. Üçüncü cümle burada."
    packed = chunk_text(text, pack=True)
    per_sentence = chunk_text(text, pack=False)
    assert len(packed) == 1          # 63 karakter → tek pakete sığar
    assert len(per_sentence) == 3    # cümle başına bir parça
    assert per_sentence[0].text == "Birinci cümle burada."


def test_pack_false_paragraf_isareti_korunur():
    text = "Bir. İki.\n\nÜç."
    chunks = chunk_text(text, pack=False)
    assert [c.paragraph_break for c in chunks] == [False, True, False]


def test_paket_basina_cumle_siniri():
    text = "Bir. İki. Üç. Dört. Beş."
    chunks = chunk_text(text, target=200, hard=226, pack=True, max_pieces=3)
    assert [c.text for c in chunks] == ["Bir. İki. Üç.", "Dört. Beş."]


def test_basarisiz_paket_cumle_guvenlik_agina_duser(monkeypatch):
    source = "Birinci cümle burada. İkinci cümle burada."
    generated: list[str] = []

    def fake_generate(text, *_args):
        generated.append(text)
        return np.ones(2400, dtype=np.float32) * 0.1, 24000

    def fake_verify(audio, sr, text, language):
        if text == source:
            return audio, {
                "similarity": 0.96,
                "action": "retry",
                "reason": "kelime-atlama",
                "transcript": "Birinci cümle burada.",
            }
        return audio, {"similarity": 1.0, "action": "ok", "transcript": text}

    monkeypatch.setattr(synth, "_generate_once", fake_generate)
    monkeypatch.setattr("app.core.quality.verify_and_repair", fake_verify)
    args = (source, "tr", None, 0.5, 0.5, 0.8, 0.85, "xtts", None)
    out, sr = synth.finalize_chunk_sync(
        np.zeros(2400, dtype=np.float32), 24000, source, "tr", args
    )
    assert generated == ["Birinci cümle burada.", "İkinci cümle burada."]
    assert sr == 24000
    assert len(out) > 4800  # iki cümle + tasarlanmış ara durak


def test_dogrulanamayan_tek_cumle_sessizce_kabul_edilmez(monkeypatch):
    source = "Bu tek cümle doğrulanamadı."

    monkeypatch.setattr(
        synth,
        "_generate_once",
        lambda *_args: (np.zeros(1200, dtype=np.float32), 24000),
    )
    monkeypatch.setattr(
        "app.core.quality.verify_and_repair",
        lambda audio, sr, text, language: (
            audio,
            {"similarity": 0.7, "action": "retry", "transcript": "yanlış"},
        ),
    )
    args = (source, "tr", None, 0.5, 0.5, 0.8, 0.85, "xtts", None)
    with pytest.raises(RuntimeError, match="metne sadık"):
        synth.finalize_chunk_sync(
            np.zeros(1200, dtype=np.float32), 24000, source, "tr", args
        )
