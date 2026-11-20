from __future__ import annotations

import json

import numpy as np

from biyo_cozucu.hafiza.etiketleme import (
    bloklari_ayristir,
    kural_ile_etiketle,
    model_ile_etiketle,
)
from biyo_cozucu.hafiza.getirme import benzer_ornekler
from biyo_cozucu.hafiza.indeks import BM25, OrnekIndeksi, rrf_birlestir, terimler
from biyo_cozucu.metin import imza
from biyo_cozucu.modeller import Ornek
from biyo_cozucu.motor.temel import SahteMotor

# --- BM25 ---


def test_terimler_durak_sozcukleri_atar():
    cikti = terimler("Aşağıdakilerden hangisi mitokondride gerçekleşir?")
    assert "mitokondride" in cikti
    assert "hangisi" not in cikti and "aşağıdakilerden" not in cikti


def test_bm25_ilgili_belgeyi_one_alir():
    bm25 = BM25([
        "Mitokondri oksijenli solunumun merkezidir",
        "Kloroplast fotosentez yapar",
        "Ribozom protein sentezler",
    ])
    puanlar = bm25.puanla("mitokondri solunum")
    assert int(np.argmax(puanlar)) == 0


def test_bm25_turkce_cekim_ekini_yakalar():
    bm25 = BM25(["Mitokondride oksijenli solunum gerçekleşir", "Kloroplast fotosentez yapar"])
    puanlar = bm25.puanla("mitokondri")
    assert puanlar[0] > puanlar[1]


def test_bm25_bos_sorguda_sifir_doner():
    bm25 = BM25(["bir belge"])
    assert bm25.puanla("ve ile de").sum() == 0.0


def test_rrf_iki_siralamayi_birlestirir():
    # 1 numaralı belge iki listede de üstlerde; birinci sırada olmalı.
    skorlar = rrf_birlestir([[3, 1, 2], [1, 2, 3]])
    assert max(skorlar, key=skorlar.get) == 1


def test_rrf_agirlik_dikkate_alir():
    hafif = rrf_birlestir([[1], [2]], agirliklar=[1.0, 1.0])
    assert hafif[1] == hafif[2]
    agirlikli = rrf_birlestir([[1], [2]], agirliklar=[1.0, 3.0])
    assert agirlikli[2] > agirlikli[1]


# --- indeks ---


def test_indeks_gommesiz_kurulabilir(ornekler):
    indeks = OrnekIndeksi.kur(ornekler, None)
    assert len(indeks) == 5
    assert not indeks.anlamsal_hazir
    sonuc = indeks.ara("mayoz kromozom sayısı", None, k=2)
    assert sonuc, "sözcüksel katman tek başına sonuç üretmeli"


def test_indeks_gomme_ile_anlamsal_katman_acilir(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    assert indeks.anlamsal_hazir
    assert indeks.gomme.shape == (5, sahte_gomlemci.boyut)
    assert indeks.gomme_modeli == "sahte-gomlemci"


def test_indeks_kaydet_yukle_gidis_donusu(ornekler, sahte_gomlemci, tmp_path):
    OrnekIndeksi.kur(ornekler, sahte_gomlemci).kaydet(tmp_path / "ix")
    yuklenen = OrnekIndeksi.yukle(tmp_path / "ix")
    assert len(yuklenen) == 5
    assert yuklenen.anlamsal_hazir
    assert yuklenen.ornekler[1].cozum_turu == "kalitim_hesabi"


def test_bayat_gomme_dosyasi_anlamsal_katmani_devre_disi_birakir(
    ornekler, sahte_gomlemci, tmp_path
):
    """Örnek sayısı ile gömme satırı uyuşmuyorsa yanlış örneğe atıf yapılmamalı."""
    dizin = tmp_path / "ix"
    OrnekIndeksi.kur(ornekler, sahte_gomlemci).kaydet(dizin)
    np.save(dizin / "gomme.npy", np.zeros((2, sahte_gomlemci.boyut), dtype=np.float32))
    yuklenen = OrnekIndeksi.yukle(dizin)
    assert len(yuklenen) == 5
    assert not yuklenen.anlamsal_hazir


def test_bos_indeks_sonuc_dondurmez():
    assert OrnekIndeksi.kur([], None).ara("herhangi", None) == []


# --- artımlı güncelleme ---
#
# Bu bölümün tek amacı şunu kanıtlamak: artımlı yol, tam yeniden kurulumla
# AYNI indeksi üretir. Aksi halde hızlı ama sessizce yanlış bir erişim
# katmanı elde edilir — yavaş olandan kötüsü.


def _bm25_esdeger(sol: BM25, sag: BM25, sorgular: list[str]) -> None:
    assert len(sol) == len(sag)
    assert sol.idf == sag.idf, "idf sözlükleri birebir aynı olmalı"
    for sorgu in sorgular:
        np.testing.assert_allclose(sol.puanla(sorgu), sag.puanla(sorgu), rtol=1e-6)


def test_bm25_ekle_bastan_kurmakla_ayni_sonucu_verir():
    belgeler = ["mitoz bölünme kromozom", "fotosentez kloroplast ışık", "enzim substrat"]
    artimli = BM25(belgeler[:2])
    artimli.ekle(belgeler[2])
    _bm25_esdeger(artimli, BM25(belgeler), ["kromozom", "enzim", "fotosentez ışık"])


def test_bm25_sil_bastan_kurmakla_ayni_sonucu_verir():
    belgeler = ["mitoz bölünme kromozom", "fotosentez kloroplast ışık", "enzim substrat"]
    artimli = BM25(belgeler)
    artimli.sil(1)
    _bm25_esdeger(artimli, BM25([belgeler[0], belgeler[2]]), ["kromozom", "kloroplast"])


def test_bm25_degistir_bastan_kurmakla_ayni_sonucu_verir():
    belgeler = ["mitoz bölünme kromozom", "fotosentez kloroplast ışık"]
    artimli = BM25(belgeler)
    artimli.degistir(1, "solunum glikoliz mitokondri")
    _bm25_esdeger(
        artimli,
        BM25([belgeler[0], "solunum glikoliz mitokondri"]),
        ["kromozom", "glikoliz", "kloroplast"],
    )


def test_bm25_silinen_terim_idf_sozlugunde_kalmaz():
    """`Counter.subtract` sıfır girdileri saklıyor; kalırlarsa o terimler
    hiçbir belgede geçmedikleri hâlde en yüksek idf'i alırdı."""
    artimli = BM25(["fotosentez kloroplast", "mitoz kromozom"])
    artimli.sil(0)
    assert "fotosentez" not in artimli.idf
    assert "kloroplast" not in artimli.idf


def test_indekse_ekleme_tam_kurulumla_ayni_gommeyi_uretir(ornekler, sahte_gomlemci):
    artimli = OrnekIndeksi.kur(ornekler[:4], sahte_gomlemci)
    assert artimli.ekle(ornekler[4], sahte_gomlemci)

    tam = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    assert len(artimli) == len(tam) == 5
    assert artimli.anlamsal_hazir
    np.testing.assert_allclose(artimli.gomme, tam.gomme, rtol=1e-6)
    assert artimli.ara("mayoz kromozom sayısı", sahte_gomlemci) == tam.ara(
        "mayoz kromozom sayısı", sahte_gomlemci
    )


def test_indeksten_silme_tam_kurulumla_ayni_sonucu_verir(ornekler, sahte_gomlemci):
    artimli = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    assert artimli.sil(ornekler[2].id)

    kalanlar = [o for o in ornekler if o.id != ornekler[2].id]
    tam = OrnekIndeksi.kur(kalanlar, sahte_gomlemci)
    assert len(artimli) == 4
    assert artimli.anlamsal_hazir, "gömme satırı da silinmeli, yoksa indeks bayatlar"
    np.testing.assert_allclose(artimli.gomme, tam.gomme, rtol=1e-6)


def test_indekste_degistirme_gommeyi_de_tazeler(ornekler, sahte_gomlemci):
    artimli = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    guncel = Ornek(
        id=ornekler[0].id,
        soru="Solunumda glikoliz nerede gerçekleşir?",
        cozum="Sitoplazmada.",
        konu="solunum",
    )
    assert artimli.degistir(guncel, sahte_gomlemci)

    tam = OrnekIndeksi.kur([guncel, *ornekler[1:]], sahte_gomlemci)
    np.testing.assert_allclose(artimli.gomme, tam.gomme, rtol=1e-6)
    assert artimli.ornekler[0].soru == guncel.soru


def test_gomme_modeli_degistiyse_artimli_yol_reddedilir(ornekler, sahte_gomlemci):
    """Farklı modelin vektörü eskilerle kıyaslanamaz; kosinüs yine bir sayı
    üretir ama anlamı yoktur. Sessizce karıştırmaktansa tam kuruluma düşülür.
    """
    indeks = OrnekIndeksi.kur(ornekler[:4], sahte_gomlemci)

    class _BaskaModel:
        model_adi = "baska-gomlemci"
        boyut = sahte_gomlemci.boyut

        def gom(self, metinler, *, sorgu=False):
            return sahte_gomlemci.gom(metinler, sorgu=sorgu)

    assert indeks.ekle(ornekler[4], _BaskaModel()) is False
    assert len(indeks) == 4, "reddedilen ekleme indeksi değiştirmemeli"


def test_bilinmeyen_id_silinemez(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    assert indeks.sil(9999) is False
    assert indeks.sil(None) is False
    assert len(indeks) == 5


def test_gommesiz_indekse_artimli_ekleme_calisir(ornekler):
    indeks = OrnekIndeksi.kur(ornekler[:2], None)
    assert indeks.ekle(ornekler[2], None)
    assert len(indeks) == 3
    assert not indeks.anlamsal_hazir
    assert indeks.ara("mitoz", None), "BM25 katmanı çalışmaya devam etmeli"


def test_artimli_eklemeden_sonra_kalicilik_bozulmaz(ornekler, sahte_gomlemci, tmp_path):
    indeks = OrnekIndeksi.kur(ornekler[:3], sahte_gomlemci)
    indeks.ekle(ornekler[3], sahte_gomlemci)
    indeks.kaydet(tmp_path / "ix")

    yuklenen = OrnekIndeksi.yukle(tmp_path / "ix")
    assert len(yuklenen) == 4
    assert yuklenen.anlamsal_hazir, "satır sayısı örnek sayısıyla uyuşmalı"


# --- getirme ---


def test_getirme_konuya_uygun_ornegi_bulur(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, "Bb genotipli bireylerin çaprazlanmasında olasılık nedir?",
        gomlemci=sahte_gomlemci, k=2,
    )
    assert kanitlar
    assert kanitlar[0].ornek_id == 2


def test_cozum_turu_uyumu_esit_yakinlikta_one_gecirir(sahte_gomlemci):
    """Aynı konudan iki örnek: hedefle aynı muhakeme yapısında olan seçilmeli."""
    ayni_konu = [
        Ornek(id=1, soru="Mitoz bölünme evreleri nasıl sıralanır?",
              cozum="Profaz metafaz anafaz telofaz.", konu="hücre bölünmesi",
              cozum_turu="mekanizma_aciklama"),
        Ornek(id=2, soru="Mitoz bölünme kaç hücre oluşturur hesaplayınız?",
              cozum="Bir hücre iki hücre verir.", konu="hücre bölünmesi",
              cozum_turu="hesaplama"),
    ]
    indeks = OrnekIndeksi.kur(ayni_konu, sahte_gomlemci)
    sorgu = "Mitoz bölünme sonucunda kaç hücre oluşur?"

    hesaplama = benzer_ornekler(indeks, sorgu, gomlemci=sahte_gomlemci, k=1,
                                cozum_turu="hesaplama")
    mekanizma = benzer_ornekler(indeks, sorgu, gomlemci=sahte_gomlemci, k=1,
                                cozum_turu="mekanizma_aciklama")
    assert hesaplama[0].ornek_id == 2
    assert mekanizma[0].ornek_id == 1


def test_tur_kademesi_en_benzer_ornegi_tumuyle_dusurmez(sahte_gomlemci):
    """Tür etiketi yanlış tahmin edildiğinde en alakalı örnek listede kalmalı."""
    ayni_konu = [
        Ornek(id=1, soru="Mitoz bölünme evreleri nasıl sıralanır?",
              cozum="Profaz metafaz anafaz telofaz.", konu="hücre bölünmesi",
              cozum_turu="mekanizma_aciklama"),
        Ornek(id=2, soru="Mitoz bölünme kaç hücre oluşturur hesaplayınız?",
              cozum="Bir hücre iki hücre verir.", konu="hücre bölünmesi",
              cozum_turu="hesaplama"),
    ]
    indeks = OrnekIndeksi.kur(ayni_konu, sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, "Mitoz bölünme sonucunda kaç hücre oluşur?",
        gomlemci=sahte_gomlemci, k=2, cozum_turu="mekanizma_aciklama",
    )
    assert [k.ornek_id for k in kanitlar] == [1, 2], (
        "tür uyumu başa geçmeli ama en benzer örnek (2) elenmemeli"
    )


def test_getirme_kendini_ornek_gostermez(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, ornekler[1].soru, gomlemci=sahte_gomlemci, k=3
    )
    assert all(k.ornek_id != 2 for k in kanitlar)


def test_haric_imzalar_kor_degerlendirmede_sizintiyi_keser(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    haric = {imza(ornekler[1].soru), imza(ornekler[3].soru)}
    kanitlar = benzer_ornekler(
        indeks, "kromozom sayısı ve çaprazlama", gomlemci=sahte_gomlemci, k=5,
        haric_imzalar=haric,
    )
    assert {k.ornek_id for k in kanitlar}.isdisjoint({2, 4})


def test_getirme_kanit_metnini_kirpar(sahte_gomlemci):
    """Uzun referans çözüm istemi şişirmesin diye kanıt metni kırpılır."""
    uzun = Ornek(
        id=1,
        soru="Enzimlerin aktivasyon enerjisine etkisi nedir?",
        cozum="Enzim aktivasyon enerjisini düşürür. " * 200,
        konu="enzimler",
    )
    indeks = OrnekIndeksi.kur([uzun], sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, "Enzimler tepkime hızını nasıl artırır?",
        gomlemci=sahte_gomlemci, k=1, azami_cozum_karakteri=120,
    )
    assert kanitlar and len(kanitlar[0].cozum) <= 120


def test_alakasiz_soruda_esik_bos_dondurebilir(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, "zzzz qqqq wwww", gomlemci=sahte_gomlemci, k=3
    )
    assert isinstance(kanitlar, list)  # çökmemeli


# --- etiketleme ---


def test_kural_ile_etiketleme_konu_ve_tur_bulur():
    konu, tur = kural_ile_etiketle(
        "Aa x Aa çaprazlamasında çekinik fenotip olasılığı kaçtır?", ""
    )
    assert konu == "kalıtım"
    assert tur == "kalitim_hesabi"


def test_kural_ile_etiketleme_grafik_sorusunu_ayirir():
    _konu, tur = kural_ile_etiketle(
        "Yukarıdaki grafikte fotosentez hızının değişimi verilmiştir. Grafiğe göre?"
    )
    assert tur == "grafik_yorumlama"


def test_konu_etiketinde_soru_cozumden_agir_basar():
    """Çözümde geçen yan kavram, sorunun asıl konusunu bastırmamalı."""
    konu, _tur = kural_ile_etiketle("Kloroplast ne yapar?", "Fotosentez yapar.")
    assert konu == "hücre"
    konu, _tur = kural_ile_etiketle(
        "Fotosentez hızını ışık şiddeti nasıl etkiler?",
        "Kloroplast içindeki tepkimeler ışıkla hızlanır.",
    )
    assert konu == "fotosentez"


def test_kural_ile_etiketleme_ipucu_yoksa_varsayilana_duser():
    konu, tur = kural_ile_etiketle("Bir şey hakkında bir şey.")
    assert konu == ""
    assert tur == "mekanizma_aciklama"


def test_model_ile_etiketleme_yaniti_ayristirir():
    motor = SahteMotor(
        json.dumps(
            {"konu": "fotosentez", "cozum_turu": "grafik_yorumlama",
             "etiketler": ["klorofil", "ışık şiddeti", "", "  ", "stoma", "fazladan"]},
            ensure_ascii=False,
        )
    )
    konu, tur, etiketler = model_ile_etiketle(motor, "Grafikte fotosentez hızı...")
    assert konu == "fotosentez"
    assert tur == "grafik_yorumlama"
    assert etiketler == ["klorofil", "ışık şiddeti", "stoma", "fazladan"], (
        "boşlar elenmeli, en fazla 4 etiket kalmalı"
    )


def test_model_ile_etiketleme_bozuk_yanitta_kurala_duser():
    """Model erişilemez ya da JSON bozuksa etiketleme çalışmaya devam etmeli."""
    motor = SahteMotor("bu JSON değil")
    konu, tur, etiketler = model_ile_etiketle(
        motor, "Mitoz bölünmede kromozom sayısı neden korunur?"
    )
    assert konu == "hücre bölünmesi", "kural tabanlı katman devreye girmeli"
    assert tur in {"mekanizma_aciklama", "hesaplama"}
    assert etiketler == []


def test_model_ile_etiketleme_gecersiz_turu_varsayilana_cevirir():
    motor = SahteMotor(json.dumps({"konu": "enzimler", "cozum_turu": "uydurma_tur"}))
    _konu, tur, _etiketler = model_ile_etiketle(motor, "Enzim nedir?")
    assert tur == "mekanizma_aciklama"


def test_bloklari_ayristir_soru_cozum_cevap_ayirir():
    metin = (
        "SORU: Aşağıdakilerden hangisi mitokondride gerçekleşir?\n"
        "A) Fotosentez\n"
        "B) Krebs döngüsü\n"
        "ÇÖZÜM:\n"
        "Mitokondri oksijenli solunumun merkezidir.\n"
        "CEVAP: B\n"
        "\n"
        "SORU: Enzimler ne işe yarar?\n"
        "ÇÖZÜM: Aktivasyon enerjisini düşürür.\n"
    )
    kayitlar = bloklari_ayristir(metin)
    assert len(kayitlar) == 2
    assert kayitlar[0]["cevap"] == "B"
    assert kayitlar[0]["secenekler"] == {"A": "Fotosentez", "B": "Krebs döngüsü"}
    assert "CEVAP" not in kayitlar[0]["cozum"]
    assert kayitlar[1]["cevap"] == ""
    assert kayitlar[1]["cevap_turu"] == "acik_uclu"


def test_bloklari_ayristir_bicimsiz_metinde_bos_doner():
    assert bloklari_ayristir("rastgele bir metin") == []


def test_yeni_konu_ipuclari_mevcut_etiketlemeyi_bozmaz():
    """TYT'nin ilk iki ünitesi eklenirken komşu konulardan puan çalınmamalı.

    İpuçları bilinçli dar seçildi: "protein", "enzim" ve "solunum" listede yok,
    çünkü sırasıyla "nükleik asitler", "enzimler" ve "solunum" konularının
    ipuçlarıyla çakışıp o konuların örneklerini kendine çekerlerdi. Ekleme
    öncesi/sonrası ölçümde 14 örnek sorudan yalnız ikisinin etiketi değişti ve
    ikisi de daha önce KONUSUZ kalan sorulardı.
    """
    korunan = {
        "Ribozomda protein sentezi nasıl olur?": "hücre",
        "Enzimlerin çalışmasını sıcaklık nasıl etkiler?": "enzimler",
        "Glikoliz sonunda kaç ATP üretilir?": "solunum",
        "DNA replikasyonu hangi evrede olur?": "nükleik asitler",
        "Ksilem suyu nasıl taşır?": "bitki biyolojisi",
        "Aşı sonrası antikor üretimi nasıl gerçekleşir?": "bağışıklık",
    }
    for soru, beklenen in korunan.items():
        konu, _tur = kural_ile_etiketle(soru)
        assert konu == beklenen, f"{soru!r} → {konu!r}"

    yeni_yakalanan = {
        "Vitaminlerin görevi nedir?": "canlıların temel bileşenleri",
        "Nişasta ve glikojen hangi grupta yer alır?": "canlıların temel bileşenleri",
        "Canlıların ortak özellikleri arasında homeostazi var mıdır?":
            "canlıların ortak özellikleri",
    }
    for soru, beklenen in yeni_yakalanan.items():
        konu, _tur = kural_ile_etiketle(soru)
        assert konu == beklenen, f"{soru!r} → {konu!r}"
