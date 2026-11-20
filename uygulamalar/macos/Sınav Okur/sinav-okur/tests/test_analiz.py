"""sinav_analizi'nin genişletilmiş alanları: dağılım, ayırt edicilik, sınıf."""
from sinav_okur.analiz import sinav_analizi
from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _kagit(sinav, oran, sinif="9", sube="A"):
    kutular = [
        KutuSonucu(
            soru_no=s.no,
            tanima=TanimaSonucu(metin="x", guven=0.9),
            puan=PuanSonucu(puan=round(s.puan * oran, 2), max_puan=s.puan, guven=0.9),
        )
        for s in sinav.sorular
    ]
    return KagitSonucu(sinav_kimlik=sinav.kimlik, islenen_sayfalar=[1], kutular=kutular), sinif, sube


def test_dagilim_ve_ortalama(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)
    for oran in (1.0, 0.5, 0.1):
        sonuc, sinif, sube = _kagit(ornek_sinav, oran)
        depo.kagit_kaydet(sonuc, ogrenci_ad="A", sinif=sinif, sube=sube)
    analiz = sinav_analizi(depo, ornek_sinav)
    assert len(analiz["dagilim"]) == 10
    assert sum(analiz["dagilim"]) == 3
    # %100 → son dilim, %50 → 5. dilim, %10 → 1. dilim
    assert analiz["dagilim"][9] == 1
    assert analiz["dagilim"][5] == 1
    assert analiz["dagilim"][1] == 1


def test_ayirt_edicilik_yetersiz_orneklemde_none(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)
    for _ in range(3):
        sonuc, sinif, sube = _kagit(ornek_sinav, 0.8)
        depo.kagit_kaydet(sonuc, ogrenci_ad="A")
    analiz = sinav_analizi(depo, ornek_sinav)
    assert analiz["ayirt_edicilik_hazir"] is False
    assert all(s["ayirt_edicilik"] is None for s in analiz["sorular"])


def test_ayirt_edicilik_yeterli_orneklemde_hesaplanir(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)
    # 10 kâğıt: yarısı yüksek yarısı düşük → ilk soru ayırt edici
    for i in range(10):
        oran = 0.9 if i < 5 else 0.2
        sonuc, sinif, sube = _kagit(ornek_sinav, oran)
        depo.kagit_kaydet(sonuc, ogrenci_ad=f"Ö{i}")
    analiz = sinav_analizi(depo, ornek_sinav)
    assert analiz["ayirt_edicilik_hazir"] is True
    assert analiz["sorular"][0]["ayirt_edicilik"] is not None


def test_sinif_karsilastirma(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)
    for sube, oran in (("A", 0.9), ("A", 0.8), ("B", 0.4), ("B", 0.5)):
        sonuc, sinif, _s = _kagit(ornek_sinav, oran, sube=sube)
        depo.kagit_kaydet(sonuc, ogrenci_ad="A", sinif="9", sube=sube)
    analiz = sinav_analizi(depo, ornek_sinav)
    etiketler = {g["sinif"] for g in analiz["sinif_karsilastirma"]}
    assert etiketler == {"9/A", "9/B"}


def test_zayif_konular_rag_callback(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)
    # RAG callback verildiğinde kaynak eşlenir; kaçırılan kavram yoksa liste boş olabilir
    cagrildi = {}

    def sahte_pasaj(kavram):
        cagrildi[kavram] = True
        return {"kaynak": "Biyoloji 9", "ozet": "hücre"}

    analiz = sinav_analizi(depo, ornek_sinav, referans_pasaj_bul=sahte_pasaj)
    assert "zayif_konular" in analiz


class _SahteSatir(dict):
    """sqlite3.Row yerine geçen, indeksle erişilen sahte satır."""

    def __getitem__(self, anahtar):
        return self.get(anahtar)


def _cevap(kutu_id, metin, puan=10.0, incele=0, kagit_id=1):
    return _SahteSatir(
        id=kutu_id, kagit_id=kagit_id, taninan_metin=metin,
        duzeltilmis_metin=None, son_puan=puan, max_puan=10.0, incele=incele,
    )


def test_benzer_cevap_kumeleri_ayni_metni_birlestirir():
    from sinav_okur.analiz import benzer_cevap_kumeleri

    satirlar = [
        _cevap(1, "mitokondri hücrenin enerji merkezidir"),
        _cevap(2, "mitokondri hücrenin enerji merkezidir"),
        _cevap(3, "kloroplast fotosentez yapar"),
    ]
    kumeler = benzer_cevap_kumeleri(satirlar)
    assert len(kumeler) == 2
    assert kumeler[0]["adet"] == 2
    assert kumeler[0]["ortak_puan"] == 10.0


def test_benzer_cevap_kumeleri_kisa_metni_kumelemez():
    from sinav_okur.analiz import benzer_cevap_kumeleri

    satirlar = [_cevap(1, "evet"), _cevap(2, "evet")]
    kumeler = benzer_cevap_kumeleri(satirlar)
    assert len(kumeler) == 2  # kısa metinler tek tek kalır


def test_benzer_cevap_kumeleri_esik_altini_ayirir():
    from sinav_okur.analiz import benzer_cevap_kumeleri

    satirlar = [
        _cevap(1, "mitokondri hücrenin enerji merkezidir"),
        _cevap(2, "ribozom protein sentezi yapan organeldir"),
    ]
    assert len(benzer_cevap_kumeleri(satirlar)) == 2


def test_benzer_cevap_kumeleri_farkli_puanda_ortak_puan_yok():
    from sinav_okur.analiz import benzer_cevap_kumeleri

    satirlar = [
        _cevap(1, "mitokondri hücrenin enerji merkezidir", puan=10.0),
        _cevap(2, "mitokondri hücrenin enerji merkezidir", puan=4.0),
    ]
    kume = benzer_cevap_kumeleri(satirlar)[0]
    assert kume["adet"] == 2
    assert kume["ortak_puan"] is None


# --- Kazanım analizi ------------------------------------------------------


def _kazanimli_sinav(kazanimlar_1, kazanimlar_2):
    from sinav_okur.modeller import CevapAnahtari, Sinav, Soru, SoruTipi

    return Sinav(
        kimlik="KAZ-1",
        baslik="Kazanım",
        sorular=[
            Soru(
                no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="Soru 1", puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
                kazanımlar=list(kazanimlar_1),
            ),
            Soru(
                no=2, tip=SoruTipi.BOSLUK_DOLDURMA, metin="Soru 2", puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["kloroplast"]),
                kazanımlar=list(kazanimlar_2),
            ),
        ],
    )


def _kazanim_kagidi(depo, sinav, puanlar, ad="Öğrenci"):
    from sinav_okur.modeller import PuanSonucu, TanimaSonucu
    from sinav_okur.sonuclar import KagitSonucu, KutuSonucu

    return depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=soru.no,
                    tanima=TanimaSonucu(metin="cevap", guven=0.9),
                    puan=PuanSonucu(
                        puan=puanlar[i], max_puan=soru.puan, guven=0.9
                    ),
                )
                for i, soru in enumerate(sinav.sorular)
            ],
        ),
        ogrenci_ad=ad,
    )


def test_kazanimsiz_sinavda_bos_sonuc(depo):
    from sinav_okur.analiz import kazanim_analizi

    sinav = _kazanimli_sinav([], [])
    depo.sinav_kaydet(sinav)
    _kazanim_kagidi(depo, sinav, [10, 10])
    sonuc = kazanim_analizi(depo, sinav)
    assert sonuc == {"kazanimlar": [], "ogrenciler": []}


def test_ayni_kazanimi_paylasan_sorular_birlesir(depo):
    from sinav_okur.analiz import kazanim_analizi

    sinav = _kazanimli_sinav(["Organeller"], ["Organeller"])
    depo.sinav_kaydet(sinav)
    _kazanim_kagidi(depo, sinav, [10, 0])
    sonuc = kazanim_analizi(depo, sinav)
    assert len(sonuc["kazanimlar"]) == 1
    kayit = sonuc["kazanimlar"][0]
    assert kayit["soru_nolari"] == [1, 2]
    assert kayit["basari_yuzdesi"] == 50.0


def test_ogrenci_zayif_kazanimi_listelenir(depo):
    from sinav_okur.analiz import kazanim_analizi

    sinav = _kazanimli_sinav(["Enerji"], ["Fotosentez"])
    depo.sinav_kaydet(sinav)
    _kazanim_kagidi(depo, sinav, [10, 0], ad="Ali")
    sonuc = kazanim_analizi(depo, sinav)
    ogrenci = sonuc["ogrenciler"][0]
    assert ogrenci["ogrenci"] == "Ali"
    assert ogrenci["zayif"] == ["Fotosentez"]


def test_kazanim_ozetleri_zayiftan_siralanir(depo):
    from sinav_okur.analiz import kazanim_analizi

    sinav = _kazanimli_sinav(["Enerji"], ["Fotosentez"])
    depo.sinav_kaydet(sinav)
    _kazanim_kagidi(depo, sinav, [10, 0])
    adlar = [k["ad"] for k in kazanim_analizi(depo, sinav)["kazanimlar"]]
    assert adlar == ["Fotosentez", "Enerji"]


def test_soru_analizinde_kazanimlar_ascii_anahtarla_gelir(depo):
    from sinav_okur.analiz import sinav_analizi

    sinav = _kazanimli_sinav(["Enerji"], [])
    depo.sinav_kaydet(sinav)
    _kazanim_kagidi(depo, sinav, [10, 10])
    analiz = sinav_analizi(depo, sinav)
    assert analiz["sorular"][0]["kazanimlar"] == ["Enerji"]
