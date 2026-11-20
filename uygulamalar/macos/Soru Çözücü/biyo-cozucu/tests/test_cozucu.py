from __future__ import annotations

import json

import pytest

from biyo_cozucu.cozucu import Ayarlar, Cozucu, cevap_eslesiyor
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.modeller import Ornek, Pasaj
from biyo_cozucu.motor.temel import SahteMotor


def _yanit(adimlar, cevap, guven=0.9, **ek) -> str:
    veri = {"adimlar": adimlar, "cevap": cevap, "guven": guven, "uyari": ""}
    veri.update(ek)
    return json.dumps(veri, ensure_ascii=False)


def _tam_referansi_onayla(depo, ornek: Ornek, kalite: float = 0.95) -> None:
    ornek.kalite = kalite
    depo.ornek_guncelle(ornek)


@pytest.fixture
def cozucu(dolu_depo, ornekler, sahte_gomlemci) -> Cozucu:
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    return Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        motor=SahteMotor(_yanit(["Adım bir", "Adım iki"], "B")),
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(),
    )


def test_coz_temel_akis(cozucu):
    cozum = cozucu.coz("Mayoz bölünmede kromozom sayısı nasıl değişir?")
    assert cozum.adimlar == ["Adım bir", "Adım iki"]
    assert cozum.cevap == "B"
    assert cozum.uretim_yontemi == "model"
    assert cozum.id is not None


def test_coz_ilgili_ornekleri_isteme_koyar(cozucu):
    cozucu.coz("Aa x Aa çaprazlamasında olasılık nedir?")
    mesajlar = cozucu.motor.cagrilar[0]
    referanslar = [m for m in mesajlar if m["content"].startswith("[REFERANS ÇÖZÜM")]
    assert referanslar, "getirilen örnekler isteme eklenmeli"
    assert any("çaprazlan" in m["content"] for m in referanslar)


def test_coz_kullanilan_kitap_sayfalarini_kaynaklara_ekler(cozucu, monkeypatch):
    monkeypatch.setattr(
        cozucu,
        "_pasajlari_getir",
        lambda _soru: [
            Pasaj("Difüzyon açıklaması", "Campbell Biyoloji", sayfa=150),
            Pasaj("Aynı sayfadan ikinci pasaj", "Campbell Biyoloji", sayfa=150),
            Pasaj("MEB açıklaması", "MEB Biyoloji 9", sayfa=136),
        ],
    )

    cozum = cozucu.coz("Kolaylaştırılmış difüzyon nedir?", kaydet=False)

    assert cozum.kitap_kaynaklari == [
        "Campbell Biyoloji · s. 150",
        "MEB Biyoloji 9 · s. 136",
    ]
    assert "Campbell Biyoloji · s. 150" in cozum.kaynaklar()


def test_kitap_baglamini_alan_onbellek_anahtari_degisir(cozucu):
    pasaj = Pasaj(
        "Glomerüler filtrasyon net filtrasyon basıncına bağlıdır.",
        "Guyton ve Hall Tıbbi Fizyoloji",
        sayfa=16,
    )
    kitap_imzasi = cozucu.kitap_baglam_imzasi([pasaj])

    eski = cozucu.onbellek_kimligi("Glomerüler filtrasyon nedir?", None, "acik_uclu")
    yeni = cozucu.onbellek_kimligi(
        "Glomerüler filtrasyon nedir?", None, "acik_uclu", kitap_baglam=kitap_imzasi
    )

    assert kitap_imzasi
    assert eski != yeni


def test_motorsuz_kitap_baglaminda_eski_ornek_cevabi_donmez(
    dolu_depo, ornekler, sahte_gomlemci, monkeypatch
):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=None,
        gomlemci=sahte_gomlemci,
    )
    monkeypatch.setattr(
        cozucu,
        "_pasajlari_getir",
        lambda _soru: [
            Pasaj(
                "Tiroid hormonları bazal metabolizma hızını artırır.",
                "Guyton ve Hall Tıbbi Fizyoloji",
                sayfa=934,
            )
        ],
    )

    cozum = cozucu.coz("Tiroid hormonlarının temel etkileri nelerdir?", kaydet=False)

    assert cozum.cevap == ""
    assert cozum.uretim_yontemi == "kitap_rag_uyari"
    assert cozum.kitap_kaynaklari == ["Guyton ve Hall Tıbbi Fizyoloji · s. 934"]
    assert any("kitaptaki olgular" in uyari for uyari in cozum.uyarilar)


def test_bos_soru_reddedilir(cozucu):
    with pytest.raises(ValueError):
        cozucu.coz("   ")


def test_onbellek_tam_eslesmede_model_calismaz(cozucu):
    soru = "Enzimlerin optimum sıcaklığı aşılırsa ne olur?"
    cozucu.coz(soru)
    cagri_sayisi = len(cozucu.motor.cagrilar)

    ikinci = cozucu.coz("  enzimlerin OPTIMUM sıcaklığı aşılırsa ne olur?  ")
    assert ikinci.uretim_yontemi == "onbellek"
    assert len(cozucu.motor.cagrilar) == cagri_sayisi, "model yeniden çalışmamalı"


def test_yerel_arsivde_birebir_soru_modeli_calistirmaz(dolu_depo, ornekler, sahte_gomlemci):
    ornek = ornekler[3]
    _tam_referansi_onayla(dolu_depo, ornek)
    motor = SahteMotor(_yanit(["Yanlış model yolu."], "A"))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
    )

    sonuc = cozucu.coz(ornek.soru, secenekler=ornek.secenekler, kaydet=False)

    assert sonuc.cevap == "B"
    assert sonuc.uretim_yontemi == "tam_referans"
    assert sonuc.dogrulama["ornek_id"] == ornek.id
    assert motor.cagrilar == []


def _arsiv_cozucu(depo, ornek: Ornek, motor_cevabi: str = "B") -> tuple[Cozucu, SahteMotor]:
    ornek.id = depo.ornek_ekle(ornek)
    motor = SahteMotor(_yanit(["Model yolu."], motor_cevabi))
    return (
        Cozucu(
            depo=depo,
            indeks=OrnekIndeksi.kur([ornek], None),
            motor=motor,
            gomlemci=None,
            ayarlar=Ayarlar(ornek_sayisi=0, kanitsiz_ceza=0.0, inceleme_esigi=0.0),
        ),
        motor,
    )


@pytest.mark.parametrize(
    ("kayitli_soru", "gelen_soru"),
    [
        ("Ortam pH < 7 ise hangisidir?", "Ortam pH > 7 ise hangisidir?"),
        ("A+B birlikte etkiliyorsa sonuç nedir?", "A-B birlikte etkiliyorsa sonuç nedir?"),
    ],
)
def test_tam_referans_semantik_operatoru_silen_imzaya_guvenmez(
    depo, kayitli_soru: str, gelen_soru: str
):
    secenekler = {"A": "Asidik", "B": "Bazik"}
    ornek = Ornek(
        soru=kayitli_soru,
        secenekler=secenekler,
        cozum="Arşiv çözümü.",
        cevap="A",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="B")

    sonuc = cozucu.coz(gelen_soru, secenekler=secenekler, kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "B"
    assert len(motor.cagrilar) == 1


def test_tam_referans_semantik_operatoru_farkli_siklari_birebir_saymaz(depo):
    soru = "Ortamın niteliği hangisidir?"
    kayitli = {"A": "pH < 7", "B": "pH > 7"}
    gelen = {"A": "pH > 7", "B": "pH < 7"}
    ornek = Ornek(
        soru=soru,
        secenekler=kayitli,
        cozum="Arşiv çözümü.",
        cevap="A",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="B")

    sonuc = cozucu.coz(soru, secenekler=gelen, kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "B"
    assert len(motor.cagrilar) == 1


def test_tam_referans_nfc_bosluk_ve_soft_hyphen_farkini_normalize_eder(depo):
    ornek = Ornek(
        soru="H\u00fccrede  \n  ortak \u00f6zel\u00adlik hangisidir?",
        secenekler={"A": "C\u0327ekirdek", "B": "Zar"},
        cozum="Arşiv çözümü.",
        cevap="A",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek)

    sonuc = cozucu.coz(
        "Hücrede ortak özellik hangisidir?",
        secenekler={"A": "Çekirdek", "B": "Zar"},
        kaydet=False,
    )

    assert sonuc.uretim_yontemi == "tam_referans"
    assert sonuc.cevap == "A"
    assert motor.cagrilar == []


@pytest.mark.parametrize(("kayitli_gorsel", "gelen_gorsel"), [("abc123", ""), ("", "abc123")])
def test_tam_referans_gelen_veya_kayitli_soru_gorselliyse_kullanilmaz(
    depo, kayitli_gorsel: str, gelen_gorsel: str
):
    soru = "Şekle göre sonuç hangisidir?"
    secenekler = {"A": "I", "B": "II"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Şekilde II.",
        cevap="B",
        gorsel=kayitli_gorsel,
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="A")

    sonuc = cozucu.coz(soru, secenekler=secenekler, gorsel=gelen_gorsel, kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "A"
    assert len(motor.cagrilar) == 1


def test_tam_referans_eski_model_onbelleginden_once_gelir(depo):
    soru = "Kloroplastın görevi hangisidir?"
    secenekler = {"A": "Solunum", "B": "Fotosentez"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Fotosentez yapar.",
        cevap="B",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="A")
    cozucu.ayarlar.tam_referans_aktif = False
    ilk = cozucu.coz(soru, secenekler=secenekler)
    assert ilk.cevap == "A"
    cozucu.ayarlar.tam_referans_aktif = True

    sonuc = cozucu.coz(soru, secenekler=secenekler, kaydet=False)

    assert sonuc.uretim_yontemi == "tam_referans"
    assert sonuc.cevap == "B"
    assert len(motor.cagrilar) == 1


def test_bos_haric_imzalar_kumesi_de_kor_mod_sinyalidir(depo):
    soru = "Mayozda kromozom sayısı ne olur?"
    secenekler = {"A": "Aynı kalır", "B": "Yarıya iner"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Yarıya iner.",
        cevap="B",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="A")

    sonuc = cozucu.coz(soru, secenekler=secenekler, haric_imzalar=set(), kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "A"
    assert len(motor.cagrilar) == 1


def test_tam_referans_gecersiz_cevabi_kesin_cevap_saymaz(depo):
    soru = "Organel hangisidir?"
    secenekler = {"A": "Mitokondri", "B": "Ribozom"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Arşiv çözümü.",
        cevap="Z",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="B")

    sonuc = cozucu.coz(soru, secenekler=secenekler, kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "B"
    assert len(motor.cagrilar) == 1


def test_tam_referans_cevap_metnini_sik_harfine_kanoniklestirir(depo):
    soru = "Organel hangisidir?"
    secenekler = {"A": "Mitokondri", "B": "Ribozom"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Ribozomdur.",
        cevap="Ribozom",
        kalite=0.95,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek)

    sonuc = cozucu.coz(soru, secenekler=secenekler, kaydet=False)

    assert sonuc.uretim_yontemi == "tam_referans"
    assert sonuc.cevap == "B"
    assert motor.cagrilar == []


@pytest.mark.parametrize("kalite", [-1.0, 0.0, 0.89, float("inf")])
def test_tam_referans_pozitif_yuksek_kalite_yoksa_fallback_yapar(depo, kalite: float):
    soru = "Protein sentezi nerede olur?"
    secenekler = {"A": "Lizozom", "B": "Ribozom"}
    ornek = Ornek(
        soru=soru,
        secenekler=secenekler,
        cozum="Ribozomda olur.",
        cevap="B",
        kalite=kalite,
    )
    cozucu, motor = _arsiv_cozucu(depo, ornek, motor_cevabi="A")

    sonuc = cozucu.coz(soru, secenekler=secenekler, kaydet=False)

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "A"
    assert len(motor.cagrilar) == 1


def test_kor_degerlendirme_tam_referansi_kullanmaz(dolu_depo, ornekler, sahte_gomlemci):
    from biyo_cozucu.metin import imza

    ornek = ornekler[3]
    _tam_referansi_onayla(dolu_depo, ornek)
    motor = SahteMotor(_yanit(["Kör model çözümü."], "A"))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
    )

    sonuc = cozucu.coz(
        ornek.soru,
        secenekler=ornek.secenekler,
        haric_imzalar={imza(ornek.soru)},
        kaydet=False,
    )

    assert sonuc.cevap == "A"
    assert sonuc.uretim_yontemi == "model"
    assert len(motor.cagrilar) == 1


def test_incelemeye_dusen_cozum_onbellege_yazilmaz(dolu_depo, ornekler, sahte_gomlemci):
    """Şüpheli çözümü önbelleğe almak hatayı kalıcılaştırır."""
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(_yanit([], "", guven=0.1)),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Belirsiz bir soru?")
    assert cozum.incele
    assert dolu_depo.ozet()["onbellek"] == 0


def test_coktan_secmeli_gecersiz_sik_isaretlenir(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "Z")),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?", secenekler={"A": "bir", "B": "iki"})
    assert cozum.guven <= 0.3
    assert cozum.incele
    assert any("şıklarla eşleşmiyor" in u for u in cozum.uyarilar)


def test_coktan_secmeli_cevap_harfe_indirgenir(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "C)")),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?", secenekler={"A": "1", "B": "2", "C": "3"})
    assert cozum.cevap == "C"
    assert not any("eşleşmiyor" in u for u in cozum.uyarilar)


def test_kanitsizlik_guveni_dusurur(depo, sahte_gomlemci):
    """Hafıza boşken model kendi bilgisiyle çalışır; bu durum güvene yansımalı."""
    cozucu = Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "B", guven=0.9)),
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(kanitsiz_ceza=0.25),
    )
    cozum = cozucu.coz("Hiç örneği olmayan bir soru?")
    assert cozum.guven == pytest.approx(0.65)
    assert any("yalnız modelin" in u for u in cozum.uyarilar)


def test_json_disi_yanit_kurtarilir_ama_incelemeye_duser(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor("Birinci satır\nİkinci satır"),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Bir soru?")
    assert cozum.adimlar == ["Birinci satır", "İkinci satır"]
    assert cozum.incele
    assert any("JSON" in u for u in cozum.uyarilar)


def test_motorsuz_calisma_en_benzer_ornegi_gosterir(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=None,
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Aa x Aa çaprazlamasında olasılık kaçtır?")
    assert cozum.uretim_yontemi == "yerel_rag"
    assert cozum.incele
    assert cozum.kanitlar
    assert any("uyarlanmamıştır" in u for u in cozum.uyarilar)


def test_motorsuz_ve_ornekiz_sistem_cokmez(depo, sahte_gomlemci):
    cozucu = Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=None,
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?")
    assert cozum.uretim_yontemi == "ragsiz"
    assert cozum.adimlar == []
    assert cozum.incele


def test_motor_hatasi_yerel_yola_duser(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor([]),  # ilk çağrıda MotorHatasi
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Mayoz kromozom sayısı?")
    assert cozum.uretim_yontemi in {"yerel_rag", "ragsiz"}
    assert any("Model çalıştırılamadı" in u for u in cozum.uyarilar)


def test_oz_kontrol_tutarsizligi_isaretler(dolu_depo, ornekler, sahte_gomlemci):
    motor = SahteMotor(
        [
            _yanit(["a"], "B", guven=0.95),
            json.dumps(
                {
                    "tutarli": False,
                    "gerekce": "adım cevabı desteklemiyor",
                    "duzeltilmis_cevap": "C",
                },
                ensure_ascii=False,
            ),
        ]
    )
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(oz_kontrol=True),
    )
    cozum = cozucu.coz("Bir soru?")
    assert cozum.guven <= 0.4
    assert any("tutarsızlık" in u for u in cozum.uyarilar)
    # Şık verilmediği için düzeltme kanonikleştirilemez, öneri olarak kalır.
    assert any("Öz-kontrol önerisi: C" in u for u in cozum.uyarilar)
    assert cozum.cevap == "B"


def test_oz_kontrol_secenekli_soruda_cevabi_duzeltir(dolu_depo, ornekler, sahte_gomlemci):
    """İkinci geçişin maliyeti ödeniyorsa faydası da alınmalı.

    Eskiden `duzeltilmis_cevap` yalnız uyarıya yazılıyordu; öz-kontrol açıkken
    bile cevap hiç değişmiyordu, yani doğruluğa katkısı sıfırdı.
    """
    motor = SahteMotor(
        [
            _yanit(["a"], "B", guven=0.95),
            json.dumps(
                {
                    "tutarli": False,
                    "gerekce": "adım cevabı desteklemiyor",
                    "duzeltilmis_cevap": "Cevap: C",
                },
                ensure_ascii=False,
            ),
        ]
    )
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(oz_kontrol=True),
    )
    cozum = cozucu.coz("Bir soru?", secenekler={"A": "bir", "B": "iki", "C": "üç"})

    assert cozum.cevap == "C"
    assert any("düzeltti" in u for u in cozum.uyarilar)
    # Çelişen iki geçiş insan gözü hak eder.
    assert cozum.incele


def test_indeksi_yenile_yeni_ornegi_gorur(dolu_depo, ornekler, sahte_gomlemci, tmp_path):
    from biyo_cozucu.modeller import Ornek

    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        gomlemci=sahte_gomlemci,
    )
    dolu_depo.ornek_ekle(Ornek(soru="Yepyeni bir soru?", cozum="Yeni çözüm."))
    yeni = cozucu.indeksi_yenile(tmp_path)
    assert len(yeni) == 6
    assert (tmp_path / "indeks" / "ornekler.jsonl").exists()


@pytest.mark.parametrize(
    "uretilen,beklenen,sonuc",
    [
        ("B", "B", True),
        ("b", " B ", True),
        ("Cevap C", "C", True),
        ("C şıkkı", "c", True),
        ("1/4", "1/4", True),
        ("B", "C", False),
        ("", "B", False),
        ("mitokondri", "kloroplast", False),
    ],
)
def test_cevap_eslesiyor(uretilen, beklenen, sonuc):
    assert cevap_eslesiyor(uretilen, beklenen) is sonuc


def test_onbellek_kimligi_modeli_ayirir():
    """Model değişince önbellek isabet etmemeli.

    LoRA eğitimi sonrası kör koşuda eğitilmiş model hiç çalıştırılmadan taban
    modelin önbellekteki çözümü geri geldi; anahtar modeli içermediği için iki
    sürüm aynı kaydı paylaşıyordu ve karşılaştırma anlamsızlaşıyordu.
    """
    ortak = ("Mitoz nedir?", None, "acik_uclu", "")
    taban = Cozucu.onbellek_kimligi(*ortak, "mlx-community/Qwen3.5-4B-MLX-4bit")
    egitilmis = Cozucu.onbellek_kimligi(*ortak, "biyo-mlx-v1")
    assert taban != egitilmis
    # Modelsiz çağrı eski davranışı korur (geriye dönük uyumluluk).
    assert Cozucu.onbellek_kimligi(*ortak) == "Mitoz nedir?\n[acik_uclu]"


def test_onbellek_farkli_modelde_isabet_etmez(dolu_depo, ornekler, sahte_gomlemci):
    from biyo_cozucu.motor.temel import SahteMotor

    yanit = json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9})
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)

    ilk_motor = SahteMotor(yanit)
    ilk_motor.ad = "model-a"
    c1 = Cozucu(depo=dolu_depo, indeks=indeks, motor=ilk_motor, gomlemci=sahte_gomlemci)
    c1.coz("Bambaşka bir soru?")

    ikinci_motor = SahteMotor(json.dumps({"adimlar": ["b"], "cevap": "C", "guven": 0.9}))
    ikinci_motor.ad = "model-b"
    c2 = Cozucu(depo=dolu_depo, indeks=indeks, motor=ikinci_motor, gomlemci=sahte_gomlemci)
    sonuc = c2.coz("Bambaşka bir soru?")

    assert sonuc.uretim_yontemi == "model"
    assert sonuc.cevap == "C"


def _kanitli_cozucu(dolu_depo, ornekler, sahte_gomlemci, yanit_guven=0.9):
    return Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(_yanit(["adım"], "B", guven=yanit_guven)),
        gomlemci=sahte_gomlemci,
    )


def test_zayif_kanit_guveni_dusurur(dolu_depo, ornekler, sahte_gomlemci):
    """Model her çözüme ~0,90 veriyor; ayırt edici sinyal erişim skorundan gelir.

    Ölçümde eşik 0,20'den 0,90'a çıkarıldığında kapsama ve doğruluk hiç
    değişmedi — yani kalibre edilmemiş güvenle seçici cevaplama imkânsızdı.
    """
    from biyo_cozucu.modeller import Cozum, Kanit

    cozucu = _kanitli_cozucu(dolu_depo, ornekler, sahte_gomlemci)

    def _cozum(skor: float, tur_uyumlu: bool) -> Cozum:
        return Cozum(
            soru="s",
            adimlar=["a"],
            cevap="B",
            guven=0.9,
            cozum_turu="ezber_bilgi",
            kanitlar=[
                Kanit(
                    etiket="Ö1",
                    ornek_id=1,
                    soru="k",
                    cozum="ç",
                    konu="hücre",
                    cozum_turu="ezber_bilgi",
                    skor=skor,
                    tur_uyumlu=tur_uyumlu,
                )
            ],
        )

    guclu = cozucu._kanit_kalibrasyonu(_cozum(0.95, True))
    zayif = cozucu._kanit_kalibrasyonu(_cozum(0.30, True))
    assert guclu == pytest.approx(0.9, abs=0.01)  # güçlü kanıt cezalandırılmaz
    assert zayif < guclu * 0.7  # zayıf kanıt belirgin düşürür


def test_tur_uyumu_kademeli_cezalandirilir(dolu_depo, ornekler, sahte_gomlemci):
    """1/3 uyum ile 3/3 uyum aynı değil; eskiden ikisi de aynı sabit cezayı alıyordu."""
    from biyo_cozucu.modeller import Cozum, Kanit

    cozucu = _kanitli_cozucu(dolu_depo, ornekler, sahte_gomlemci)

    def _cozum(uyumlu_sayisi: int) -> Cozum:
        kanitlar = [
            Kanit(
                etiket=f"Ö{i}",
                ornek_id=i,
                soru="k",
                cozum="ç",
                konu="hücre",
                cozum_turu="ezber_bilgi",
                skor=0.9,
                tur_uyumlu=i < uyumlu_sayisi,
            )
            for i in range(3)
        ]
        return Cozum(
            soru="s",
            adimlar=["a"],
            cevap="B",
            guven=0.9,
            cozum_turu="ezber_bilgi",
            kanitlar=kanitlar,
        )

    hepsi = cozucu._kanit_kalibrasyonu(_cozum(3))
    biri = cozucu._kanit_kalibrasyonu(_cozum(1))
    hicbiri = cozucu._kanit_kalibrasyonu(_cozum(0))
    assert hepsi > biri > hicbiri


# --- self-consistency oylama (Ayarlar.deneme_sayisi) ---


class _SicaklikSayanMotor(SahteMotor):
    """Hangi denemenin hangi sıcaklıkla yapıldığını kaydeden sahte motor."""

    def __init__(self, yanitlar):
        super().__init__(yanitlar)
        self.sicakliklar: list[float] = []

    def uret(self, mesajlar, *, sicaklik=0.2, azami_token=1536):
        self.sicakliklar.append(sicaklik)
        return super().uret(mesajlar, sicaklik=sicaklik, azami_token=azami_token)


def _oylayan_cozucu(dolu_depo, ornekler, sahte_gomlemci, yanitlar, deneme=3):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    motor = _SicaklikSayanMotor(yanitlar)
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        motor=motor,
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(deneme_sayisi=deneme, sicaklik=0.0, deneme_sicakligi=0.7),
    )
    return cozucu, motor


def test_oylama_cogunluk_cevabini_secer(dolu_depo, ornekler, sahte_gomlemci):
    cozucu, motor = _oylayan_cozucu(
        dolu_depo,
        ornekler,
        sahte_gomlemci,
        [_yanit(["a"], "C"), _yanit(["b"], "B"), _yanit(["c"], "B")],
    )
    cozum = cozucu.coz("Fotosentezde ışık evresi nerede gerçekleşir?", kaydet=False)
    assert cozum.cevap == "B"
    assert len(motor.cagrilar) == 3
    assert cozum.uretim_yontemi == "oylama"


def test_oylama_guveni_oy_oraniyla_carpar(dolu_depo, ornekler, sahte_gomlemci):
    """2/3 ile 3/3 aynı güveni taşımamalı — seçici doğruluğun temel sinyali."""
    bolunmus, _ = _oylayan_cozucu(
        dolu_depo,
        ornekler,
        sahte_gomlemci,
        [
            _yanit(["a"], "B", guven=0.9),
            _yanit(["b"], "B", guven=0.9),
            _yanit(["c"], "D", guven=0.9),
        ],
    )
    ayrik = bolunmus.coz("Mitozda kardeş kromatitler ne zaman ayrılır?", kaydet=False)

    birlesik, _ = _oylayan_cozucu(
        dolu_depo,
        ornekler,
        sahte_gomlemci,
        [_yanit(["a"], "B", guven=0.9)],
    )
    ortak = birlesik.coz("Mitozda kardeş kromatitler ne zaman ayrılır?", kaydet=False)

    assert ayrik.guven < ortak.guven
    assert any("3 denemeden 2" in u for u in ayrik.uyarilar)


def test_oylama_ilk_denemeyi_deterministik_yapar(dolu_depo, ornekler, sahte_gomlemci):
    """İlk deneme ayarlardaki sıcaklıkla olmalı ki tek atışlı koşuyla
    karşılaştırılabilsin; çeşitlilik sonrakilerden gelir."""
    cozucu, motor = _oylayan_cozucu(
        dolu_depo,
        ornekler,
        sahte_gomlemci,
        [_yanit(["a"], "B")],
    )
    cozucu.coz("Enzimlerin çalışmasını sıcaklık nasıl etkiler?", kaydet=False)
    assert motor.sicakliklar == [0.0, 0.7, 0.7]


def test_deneme_bir_iken_oylama_devrede_degil(dolu_depo, ornekler, sahte_gomlemci):
    cozucu, motor = _oylayan_cozucu(
        dolu_depo,
        ornekler,
        sahte_gomlemci,
        [_yanit(["a"], "B")],
        deneme=1,
    )
    cozum = cozucu.coz("Ribozomun görevi nedir?", kaydet=False)
    assert len(motor.cagrilar) == 1
    assert cozum.uretim_yontemi == "model"


# --- bozuk JSON onarımı ve cevap kurtarma (ölçümde %23'lük dilim) ---


BOZUK = (
    '{"adimlar": ["Mantarlar hayvanlara daha yakındır.", '
    '"E seçeneği bu yüzden yanlıştır."}'  # dizi kapatılmadı, cevap alanı yok
)


def test_bozuk_json_adimlari_kurtarilir(dolu_depo, ornekler, sahte_gomlemci):
    """Model `adimlar`ı kapatmadan objeyi bitiriyor; yanıt tümden atılmamalı."""
    from biyo_cozucu.motor.temel import json_ayikla

    veri = json_ayikla(BOZUK)
    assert len(veri["adimlar"]) == 2
    assert veri["cevap"] == ""  # yok olan cevap UYDURULMAZ
    assert veri["_onarildi"] is True


def test_bozuk_jsondan_cevap_alani_okunur():
    from biyo_cozucu.motor.temel import json_ayikla

    veri = json_ayikla('{"adimlar": ["a", "b"], "cevap": "C", "guven": 0.8')
    assert veri["cevap"] == "C"
    assert veri["guven"] == 0.8


def test_onarilmis_yanit_guven_tavani_alir(dolu_depo, ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    c = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        motor=SahteMotor([BOZUK, "-"]),
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False),
    )
    cozum = c.coz("Mantarlarla ilgili hangisi yanlıştır?", kaydet=False)
    assert cozum.guven <= 0.5
    assert cozum.adimlar


def test_bos_cevap_kurtarma_cagrisiyla_doldurulur(dolu_depo, ornekler, sahte_gomlemci):
    """Muhakeme var ama cevap alanı boşsa ikinci kısa çağrı şık harfini alır."""
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    motor = SahteMotor([_yanit(["Adım"], ""), "C"])
    c = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        motor=motor,
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False),
    )
    cozum = c.coz("Hangisi doğrudur?", secenekler={"A": "bir", "B": "iki", "C": "üç"}, kaydet=False)
    assert cozum.cevap == "C"
    assert len(motor.cagrilar) == 2
    # Kurtarılan cevap kapsamayı şişirmemeli: düşük güven + incelemeye düşer.
    assert cozum.guven <= 0.35
    assert cozum.incele


def test_kurtarma_sonuca_varmayan_cozumde_cevap_uydurmaz(dolu_depo, ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    motor = SahteMotor([_yanit(["Adım"], ""), "-"])
    c = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        motor=motor,
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False),
    )
    cozum = c.coz("Hangisi doğrudur?", secenekler={"A": "bir", "B": "iki"}, kaydet=False)
    assert cozum.cevap == ""


# --- tür bazlı güven kalibrasyonu ---


def test_tur_guvenilirligi_guveni_indirir(dolu_depo, ornekler, sahte_gomlemci):
    """Sistemin zayıf olduğu türde model 0,9 dese bile güven inmeli."""
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    ayarlar = Ayarlar(onbellek_aktif=False, tur_guvenilirligi={"kalitim_hesabi": 0.3})
    c = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        gomlemci=sahte_gomlemci,
        ayarlar=ayarlar,
        motor=SahteMotor(_yanit(["a"], "B", guven=0.9, cozum_turu="kalitim_hesabi")),
    )
    cozum = c.coz("Çaprazlamada oran nedir?", kaydet=False)
    assert cozum.guven < 0.5
    assert any("başarısı düşük" in u for u in cozum.uyarilar)


def test_tur_guvenilirligi_iyi_turu_cezalandirmaz(dolu_depo, ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    ayarlar = Ayarlar(onbellek_aktif=False, tur_guvenilirligi={"kalitim_hesabi": 0.3})
    c = Cozucu(
        depo=dolu_depo,
        indeks=indeks,
        gomlemci=sahte_gomlemci,
        ayarlar=ayarlar,
        motor=SahteMotor(_yanit(["a"], "B", guven=0.9, cozum_turu="siniflandirma")),
    )
    cozum = c.coz("Hangi âleme girer?", kaydet=False)
    # Tabloda olmayan tür hiç dokunulmadan geçmeli: buradaki tek indirim
    # kanıtsızlık cezası (0,9 → 0,65), tür cezası değil.
    assert cozum.guven == pytest.approx(0.65)
    assert not any("başarısı düşük" in u for u in cozum.uyarilar)


def test_kalibrasyon_dosyasi_okunur(tmp_path):
    from biyo_cozucu.cozucu import KALIBRASYON_DOSYASI, kalibrasyonu_oku

    (tmp_path / KALIBRASYON_DOSYASI).write_text(
        json.dumps({"tur_guvenilirligi": {"kalitim_hesabi": 0.3, "bozuk": "x"}}),
        encoding="utf-8",
    )
    tablo = kalibrasyonu_oku(tmp_path)
    assert tablo == {"kalitim_hesabi": 0.3}


def test_kalibrasyon_dosyasi_yoksa_katman_etkisiz(tmp_path):
    from biyo_cozucu.cozucu import kalibrasyonu_oku

    assert kalibrasyonu_oku(tmp_path) == {}


# --- v2 şeması: `on_cevap` sigortasının çözücüdeki karşılığı ---


def _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit: str) -> Cozucu:
    # Önbellek kapalı: aynı soruyu iki ayarla çözüp karşılaştıran testlerde
    # ikinci çözüm önbellekten dönüp ilkinin güvenini tekrar eder ve
    # karşılaştırma sessizce anlamsızlaşır.
    return Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(yanit),
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False),
    )


def test_cevap_gelmeyince_on_cevaba_dusulur(dolu_depo, ornekler, sahte_gomlemci):
    """Eskiden bu yanıt cevapsız sayılıp tümden incelemeye düşüyordu."""
    kesik = '{"on_cevap":"D","adimlar":["ilk adım","yarım kalan'
    cozucu = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, kesik)

    cozum = cozucu.coz("Mayoz bölünmede kromozom sayısı nasıl değişir?")

    assert cozum.cevap == "D"
    assert cozum.uretim_yontemi == "on_cevap"
    # Muhakeme yarım kaldığı için tam güvenle geçemez.
    assert cozum.guven <= 0.60
    assert any("ön cevap" in u.lower() for u in cozum.uyarilar)


def test_on_cevap_celisirse_guven_dusurulur(dolu_depo, ornekler, sahte_gomlemci):
    celisen = _yanit(["Adım bir"], "B", guven=0.9, on_cevap="A")
    uyumlu = _yanit(["Adım bir"], "B", guven=0.9, on_cevap="B")

    celisen_cozum = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, celisen).coz(
        "Mayoz bölünmede kromozom sayısı nasıl değişir?"
    )
    uyumlu_cozum = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, uyumlu).coz(
        "Mayoz bölünmede kromozom sayısı nasıl değişir?"
    )

    assert celisen_cozum.cevap == "B"  # geçerli olan nihai cevap
    assert celisen_cozum.guven < uyumlu_cozum.guven
    assert any("değiştirdi" in u for u in celisen_cozum.uyarilar)


def test_on_cevap_uyumluysa_ceza_yok(dolu_depo, ornekler, sahte_gomlemci):
    """Sigorta, normal yanıtı cezalandırmamalı — yoksa kapsamayı geri alır."""
    with_on = _yanit(["Adım bir", "Adım iki"], "B", on_cevap="B")
    cozum = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, with_on).coz(
        "Mayoz bölünmede kromozom sayısı nasıl değişir?"
    )
    assert cozum.uretim_yontemi == "model"
    assert not any("değiştirdi" in u for u in cozum.uyarilar)


# --- kesme kalitesi → çözüm güveni ---
#
# Soru bir kesme/OCR hattından geldiğinde çözüm kaynağından daha güvenilir
# olamaz. Bağ kurulmadan önce yarım kesilmiş bir soru tam güvenle
# cevaplanabiliyordu: model eksik metni fark etmiyor, emin görünüyordu.


def test_dusuk_kesme_guveni_cozum_guvenine_tavan_olur(dolu_depo, ornekler, sahte_gomlemci):
    yanit = _yanit(["Adım bir", "Adım iki"], "B", guven=0.95)
    soru = "Mayoz bölünmede kromozom sayısı nasıl değişir?"

    sinirsiz = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit).coz(soru)
    sinirli = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit).coz(soru, kaynak_guveni=0.4)

    assert sinirli.guven <= 0.4
    assert sinirli.guven < sinirsiz.guven
    assert any("kesilmiş" in u for u in sinirli.uyarilar)


def test_kaynak_guveni_bilinmiyorsa_tavan_uygulanmaz(dolu_depo, ornekler, sahte_gomlemci):
    """0 = 'puanlanmamış'. Tavan sayılsaydı puansız arşiv her cevabı susturur."""
    yanit = _yanit(["Adım bir"], "B", guven=0.9)
    soru = "Mayoz bölünmede kromozom sayısı nasıl değişir?"

    varsayilan = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit).coz(soru)
    sifir = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit).coz(soru, kaynak_guveni=0.0)

    assert sifir.guven == varsayilan.guven
    assert sifir.guven > 0


def test_yuksek_kesme_guveni_cozumu_cezalandirmaz(dolu_depo, ornekler, sahte_gomlemci):
    yanit = _yanit(["Adım bir"], "B", guven=0.8)
    soru = "Mayoz bölünmede kromozom sayısı nasıl değişir?"

    temiz = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, yanit).coz(soru, kaynak_guveni=0.99)
    assert not any("kesilmiş" in u for u in temiz.uyarilar)


# --- inceleme bulguları: sessizce kapanan korumalar ---
#
# Aşağıdaki dördü de kod incelemesinde çıktı ve HİÇBİRİ mevcut testlerce
# yakalanmıyordu. Ortak yanları: hepsi "başarılı" görünüp sessizce yanlış
# sonuç üretiyor.


def test_uc_deneme_de_on_cevaba_duserse_oylama_yine_calisir(dolu_depo, ornekler, sahte_gomlemci):
    """Kesilme denemeler arası korelasyonlu; oylama tam burada kapanmamalı."""
    from biyo_cozucu.cozucu import Cozum

    cozucu = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, _yanit(["a"], "A"))
    adaylar = [
        Cozum(soru="S", adimlar=["x"], cevap=c, guven=0.6, uretim_yontemi="on_cevap")
        for c in ("A", "B", "B")
    ]

    kazanan = cozucu.cozumleri_oyla("S", adaylar)

    # Çoğunluk B; eskiden oylama hiç çalışmayıp ilk aday (A) tam güvenle geçiyordu.
    assert kazanan.cevap == "B"
    assert kazanan.guven < 0.6, "oy oranı çarpanı uygulanmalı"


def test_bicimsiz_cozum_de_oylamaya_girer(dolu_depo, ornekler, sahte_gomlemci):
    from biyo_cozucu.cozucu import Cozum

    cozucu = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, _yanit(["a"], "A"))
    adaylar = [
        Cozum(soru="S", adimlar=[], cevap=c, guven=0.2, uretim_yontemi="bicimsiz")
        for c in ("A", "C", "C")
    ]
    assert cozucu.cozumleri_oyla("S", adaylar).cevap == "C"


def test_onbellekten_gelen_cozum_de_kesme_guveniyle_sinirlanir(dolu_depo, ornekler, sahte_gomlemci):
    """Temiz metinle çözülüp önbelleğe giren cevap, kötü kesimde miras alınmamalı."""
    soru = "Enzimlerin optimum sıcaklığı aşılırsa ne olur?"
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(_yanit(["Adım bir"], "B", guven=0.95)),
        gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(),  # önbellek AÇIK: senaryonun kendisi bu
    )
    temiz = cozucu.coz(soru)
    assert temiz.guven > 0.4

    kirli = cozucu.coz(soru, kaynak_guveni=0.4)

    assert kirli.uretim_yontemi == "onbellek"
    assert kirli.guven <= 0.4


def test_tam_referans_yolu_da_kesme_guveniyle_sinirlanir(depo):
    ornek = Ornek(
        soru="Kloroplastın görevi hangisidir?",
        secenekler={"A": "Solunum", "B": "Fotosentez"},
        cozum="Fotosentez yapar.",
        cevap="B",
        kalite=0.95,
    )
    cozucu, _motor = _arsiv_cozucu(depo, ornek)

    sonuc = cozucu.coz(ornek.soru, secenekler=ornek.secenekler, kaydet=False, kaynak_guveni=0.3)

    assert sonuc.uretim_yontemi == "tam_referans"
    assert sonuc.guven <= 0.3


def test_kanitsiz_on_cevap_cozumu_de_ceza_alir(dolu_depo, ornekler, sahte_gomlemci):
    """Tek etikete (== 'model') bakmak, bozuk şema yollarını cezadan muaf tutuyordu."""
    from biyo_cozucu.cozucu import Cozum

    cozucu = _cozucu_kur(dolu_depo, ornekler, sahte_gomlemci, _yanit(["a"], "A"))
    cozum = Cozum(
        soru="S",
        adimlar=["x"],
        cevap="A",
        guven=0.6,
        kanitlar=[],
        uretim_yontemi="on_cevap",
    )

    cozucu._oz_kontrol(cozum, None)

    assert cozum.guven < 0.6
    assert any("yalnız modelin" in u for u in cozum.uyarilar)
