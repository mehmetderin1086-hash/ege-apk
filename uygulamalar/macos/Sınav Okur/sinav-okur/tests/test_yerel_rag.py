from sinav_okur.referans import YerelRAGDeposu


def test_yerel_kitap_rag_tokensiz_cevap_ve_kaynak_uretir(tmp_path):
    kitap = tmp_path / "biyoloji.txt"
    kitap.write_text(
        "Mitokondri, ökaryot hücrelerde hücresel solunumun gerçekleştiği "
        "organeldir. Besinlerden elde edilen enerjiyi ATP biçiminde kullanılabilir "
        "enerjiye dönüştürür.\n\n"
        "Kloroplast bitki hücrelerinde fotosentez yapar. Işık enerjisi kimyasal "
        "enerjiye dönüştürülür ve glikoz sentezlenir.",
        encoding="utf-8",
    )

    depo = YerelRAGDeposu.kur([kitap])
    depo.kaydet(tmp_path / "indeks")
    tekrar = YerelRAGDeposu.yukle(tmp_path / "indeks")
    sonuc = tekrar.cevap_uret(
        [(1, "Mitokondrinin hücredeki enerji üretim görevi nedir?", 10)]
    )[0]

    assert "ATP" in sonuc.cevap
    assert sonuc.rubrik
    assert sonuc.kaynaklar == ["biyoloji.txt · pasaj 1"]
    assert tekrar.durum() == {"hazir": True, "pasaj": 2, "kitap": 1}


def test_bioprof_yoksa_ayni_yerel_rag_cevabi_kullanilir(tmp_path, monkeypatch):
    from sinav_okur import bioprof

    kitap = tmp_path / "not.txt"
    kitap.write_text(
        "Hücre zarı seçici geçirgendir ve hücre ile çevre arasındaki madde "
        "alışverişini düzenler. Fosfolipit çift tabakadan oluşur.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    monkeypatch.setattr(bioprof, "bioprof_bul", lambda: None)

    sonuc = bioprof.bioprof_ile_cevapla(
        depo, [(2, "Hücre zarının görevi nedir?", 10)]
    )[0]

    assert "madde alışverişini" in sonuc.cevap
    assert sonuc.kaynaklar


def test_bioprof_mevcut_notebook_kitabindan_strict_cevap_alir(monkeypatch):
    from sinav_okur import bioprof

    monkeypatch.setattr(bioprof, "bioprof_bul", lambda: "http://127.0.0.1:8766")
    monkeypatch.setattr(
        bioprof,
        "bioprof_kaynakli_notebook",
        lambda _adres=None: (
            "notebook-1",
            [{"title": "biyoloji-campbell", "status": "ready"}],
        ),
    )

    def sahte_json(url, *, veri=None, anahtar=None, timeout=8.0):
        assert url.endswith("/api/v1/notebooks/notebook-1/ask")
        assert veri["mode"] == "strict"
        assert veri["provider"] == "local_evidence"
        return {
            "answer_markdown": "Mitokondri hücresel solunumla ATP sentezler. [S1]",
            "claims": [{"text": "ATP sentezler.", "supported": True}],
            "citations": [{"source_title": "biyoloji-campbell", "page": 169}],
        }

    monkeypatch.setattr(bioprof, "_json_istek", sahte_json)
    sonuc = bioprof.bioprof_notebook_ile_cevapla(
        [(1, "Mitokondrinin temel görevi nedir?", 10)]
    )[0]

    assert "ATP" in sonuc.cevap
    assert sonuc.rubrik == ["ATP sentezler."]
    assert sonuc.kaynaklar == ["biyoloji-campbell · sayfa 169"]


def test_rag_anahtari_kaynagi_es_anlamliyi_ve_puanlama_iznini_tasir(
    tmp_path, monkeypatch
):
    from sinav_okur import rag_anahtar
    from sinav_okur.yapay_zeka import YapayZekaCevabi

    kitap = tmp_path / "biyoloji.txt"
    kitap.write_text(
        "Hücre teorisine göre canlıların temel yapı ve görev birimi hücredir. "
        "Yeni hücreler daha önce var olan hücrelerin bölünmesiyle oluşur.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)
    monkeypatch.setattr(
        rag_anahtar, "claude_api_durumu", lambda: {"hazir": True}
    )

    def uretici(sorular, *, ders, kanitlar):
        assert kanitlar[1][0]["kaynak"].startswith("biyoloji.txt")
        return [
            YapayZekaCevabi(
                1,
                "Canlıların temel birimi hücredir.",
                ["Canlıların temel yapı birimi hücredir."],
                True,
                "",
                [["hücre teorisi"]],
            )
        ]

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [(1, "Hücre teorisi ne söyler?", 10)],
        ders="Biyoloji",
        uretici=uretici,
    )[0]

    assert sonuc.puanlanabilir is True
    assert sonuc.rubrik_es_anlamlilari == [["hücre teorisi"]]
    assert sonuc.kaynaklar == ["biyoloji.txt · pasaj 1"]


def test_rag_uretici_calismazsa_puan_uydurmaz(tmp_path, monkeypatch):
    from sinav_okur import rag_anahtar
    from sinav_okur.yapay_zeka import YapayZekaHatasi

    kitap = tmp_path / "not.txt"
    kitap.write_text(
        "Mitokondri hücresel solunumla ATP üretir ve hücreye enerji sağlar.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)
    monkeypatch.setattr(
        rag_anahtar, "claude_api_durumu", lambda: {"hazir": True}
    )
    deneme = []

    def bozuk_uretici(*args, **kwargs):
        deneme.append(1)
        raise YapayZekaHatasi("geçici hata")

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [(1, "Mitokondri ne işe yarar?", 10)],
        uretici=bozuk_uretici,
    )[0]

    assert len(deneme) == 4
    assert sonuc.puanlanabilir is False
    assert "otomatik puanlama kapalı" in sonuc.uyari


def test_fotografta_kesilen_soru_model_cagirilmadan_incelemeye_birakilir(
    tmp_path, monkeypatch
):
    from sinav_okur import rag_anahtar

    kitap = tmp_path / "not.txt"
    kitap.write_text(
        "Parlak renkler bazı canlılarda yırtıcılara karşı uyarıcı renklenmedir. "
        "Bu adaptasyon saldırı riskini azaltabilir ve hayatta kalmayı destekler.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)
    monkeypatch.setattr(
        rag_anahtar, "claude_api_durumu", lambda: {"hazir": True}
    )

    def cagrilmamali(*args, **kwargs):
        raise AssertionError("Eksik soru modele gönderilmemeli")

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [
            (
                4,
                "Parlak renkli kurbağalarda yırtıcı saldırısı bunun "
                "[fotoğrafta soru metni burada kesiliyor]",
                20,
            )
        ],
        uretici=cagrilmamali,
    )[0]

    assert sonuc.puanlanabilir is False
    assert "kesilmiş" in sonuc.uyari


def test_cok_parcali_soruyu_alt_madde_basina_kimlik_ve_katkiya_boler(
    tmp_path, monkeypatch
):
    from sinav_okur import rag_anahtar
    from sinav_okur.yapay_zeka import YapayZekaCevabi

    kitap = tmp_path / "donum.txt"
    kitap.write_text(
        "Mikroskobun keşfi hücrelerin gözlenmesini sağladı. Hücre teorisi "
        "canlıların hücrelerden oluştuğunu açıkladı. Bu iki keşif biyolojinin "
        "gelişimindeki önemli dönüm noktalarıdır.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)
    monkeypatch.setattr(
        rag_anahtar, "claude_api_durumu", lambda: {"hazir": True}
    )
    cagrilar = []

    def uretici(sorular, **kwargs):
        cagrilar.append(sorular[0][1])
        sira = len(cagrilar)
        return [
            YapayZekaCevabi(
                1,
                f"{sira}. alt cevap",
                [f"{sira}. keşif", f"{sira}. katkı"],
                True,
                "",
                [[], []],
            )
        ]

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [
            (
                1,
                "İki tarihî belge verilmiştir: "
                "1) Mercekle küçük yapılar görüldü. "
                "2) Canlıların yapı taşı açıklandı. "
                "Her keşfi ve biyolojiye katkısını yorumlayınız.",
                20,
            )
        ],
        uretici=uretici,
    )[0]

    assert len(cagrilar) == 2
    assert sonuc.rubrik == ["1. keşif", "1. katkı", "2. keşif", "2. katkı"]
    assert sonuc.puanlanabilir is True


def test_uretici_hazir_verilirse_claude_api_durumuna_bakilmaz(
    tmp_path, monkeypatch
):
    """Yerel üretici enjekte edilince bulut kapısı devreye girmemeli.

    Kapı üreticiden bağımsızlaştırılmazsa Claude API kapalı olduğunda yerel
    motor hiç çağrılmaz ve anahtar sessizce puanlanamayan taslağa düşerdi.
    """
    from sinav_okur import rag_anahtar
    from sinav_okur.yapay_zeka import YapayZekaCevabi

    kitap = tmp_path / "biyoloji.txt"
    kitap.write_text(
        "Mitokondri hücresel solunumla ATP üretir ve hücreye enerji sağlar.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)

    def cagrilmamali():
        raise AssertionError("uretici_hazir verildiğinde bulut durumu sorulmaz")

    monkeypatch.setattr(rag_anahtar, "claude_api_durumu", cagrilmamali)

    def uretici(sorular, *, ders, kanitlar):
        return [
            YapayZekaCevabi(
                1,
                "Mitokondri ATP üretir.",
                ["Mitokondri hücresel solunumla ATP üretir"],
                True,
                "",
                [["ATP"]],
            )
        ]

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [(1, "Mitokondri ne işe yarar?", 10)],
        uretici=uretici,
        uretici_hazir=True,
        uretim_yontemi="Yerel kitap RAG + yerel model (biyo-cozucu)",
    )[0]

    assert sonuc.puanlanabilir is True
    assert sonuc.uretim_yontemi == "Yerel kitap RAG + yerel model (biyo-cozucu)"


def test_uretici_hazir_degilse_model_cagrilmadan_taslak_uretilir(
    tmp_path, monkeypatch
):
    from sinav_okur import rag_anahtar

    kitap = tmp_path / "biyoloji.txt"
    kitap.write_text(
        "Ribozomlar protein sentezinin yapıldığı organellerdir. "
        "Hem sitoplazmada serbest hem de endoplazmik retikuluma bağlı bulunur.",
        encoding="utf-8",
    )
    depo = YerelRAGDeposu.kur([kitap])
    indeks = tmp_path / "indeks"
    depo.kaydet(indeks)

    def cagrilmamali(*_a, **_k):
        raise AssertionError("üretici hazır değilken model çağrılmamalı")

    sonuc = rag_anahtar.rag_anahtarlari_uret(
        indeks,
        [(1, "Ribozomlar ne işe yarar?", 10)],
        uretici=cagrilmamali,
        uretici_hazir=False,
    )[0]

    assert sonuc.puanlanabilir is False
    assert sonuc.uretim_yontemi == "Yerel kitap RAG · çıkarımsal taslak"
