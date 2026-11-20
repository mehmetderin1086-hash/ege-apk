from __future__ import annotations

import json
import zipfile

import pytest

from biyo_cozucu.cli import main
from biyo_cozucu.depo import Depo


def _calistir(*argumanlar) -> int:
    return main(list(argumanlar))


def test_ornek_ekle_metin_dosyasindan(tmp_path, capsys):
    dosya = tmp_path / "ornekler.txt"
    dosya.write_text(
        "SORU: Ribozomun görevi nedir?\n"
        "ÇÖZÜM: Ribozom protein sentezler.\n"
        "CEVAP: Protein sentezi\n\n"
        "SORU: Lizozom ne yapar?\n"
        "ÇÖZÜM: Hücre içi sindirim yapar.\n",
        encoding="utf-8",
    )
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle", str(dosya))
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "Eklendi: 2" in cikti
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 2
    assert (tmp_path / "indeks" / "ornekler.jsonl").exists()


def test_ornek_ekle_jsonl_dosyasindan(tmp_path):
    dosya = tmp_path / "ornekler.jsonl"
    dosya.write_text(
        json.dumps({"soru": "Mitoz nedir?", "cozum": "Bölünme türüdür.",
                    "cevap": "Bölünme"}, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle", str(dosya)) == 0
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 1


def test_ornek_ekle_dogrudan_argumanla(tmp_path):
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
        "--soru", "Fotosentez hızını etkileyen faktörler nelerdir?",
        "--cozum", "Işık şiddeti, karbondioksit derişimi ve sıcaklık etkiler.",
        "--cevap", "Işık, CO2, sıcaklık",
    )
    assert kod == 0
    ornek = Depo(tmp_path / "biyo.db").ornekler()[0]
    assert ornek.konu == "fotosentez"
    assert ornek.etiket_kaynagi == "kural"


def test_ornek_ekle_girdisiz_hata(tmp_path):
    assert _calistir("--veri", str(tmp_path), "ornek-ekle") == 2


def test_yinelenen_ornek_atlanir(tmp_path, capsys):
    for _ in range(2):
        _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
                  "--soru", "Aynı soru?", "--cozum", "Aynı çözüm.")
    assert "Atlandı: 1" in capsys.readouterr().out
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 1


def test_uzerine_yaz_gunceller(tmp_path):
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Soru?", "--cozum", "İlk çözüm.")
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle", "--uzerine-yaz",
              "--soru", "Soru?", "--cozum", "İkinci çözüm.")
    depo = Depo(tmp_path / "biyo.db")
    assert depo.ornek_sayisi() == 1
    assert depo.ornekler()[0].cozum == "İkinci çözüm."


def test_indeksle_komutu(tmp_path, capsys):
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle", "--indekssiz",
              "--soru", "Soru?", "--cozum", "Çözüm.")
    assert not (tmp_path / "indeks").exists()
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "indeksle") == 0
    assert "1 örnek" in capsys.readouterr().out


def test_durum_komutu(tmp_path, capsys):
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Mitoz nedir?", "--cozum", "Bölünmedir.")
    assert _calistir("--veri", str(tmp_path), "durum") == 0
    cikti = capsys.readouterr().out
    assert "Örnek     : 1" in cikti
    assert "hücre bölünmesi" in cikti


@pytest.mark.parametrize(
    ("ocr_sayfasi", "ocr_bos", "hata"),
    [
        (40, 0, 4),
        (40, 9, 0),
    ],
)
def test_kitap_al_kismi_ocr_kaybini_basari_saymaz(
    tmp_path, capsys, monkeypatch, ocr_sayfasi, ocr_bos, hata
):
    """Dilimleyici yalnız sıfır çıkışta ilerler; eksik sayfa sessiz kalmamalı."""
    from biyo_cozucu.veri import kitap as kitap_modulu

    def sahte_kitabi_al(*_a, **_k):
        yield kitap_modulu.KitapOzeti(
            kaynak="Campbell Biyoloji",
            sayfa=1101,
            okunan_sayfa=40,
            ocr_sayfasi=ocr_sayfasi,
            pasaj=80,
            ocr_bos=ocr_bos,
            hata=hata,
        )

    monkeypatch.setattr(kitap_modulu, "kitabi_al", sahte_kitabi_al)
    kod = _calistir(
        "--veri",
        str(tmp_path),
        "kitap-al",
        str(tmp_path / "campbell.pdf"),
        "--kaynak",
        "Campbell Biyoloji",
        "--ocr",
        "zorla",
        "--indekssiz",
    )

    assert kod == 1
    cikti = capsys.readouterr()
    assert "hatalı:" in cikti.out


def test_coz_motorsuz_calisir(tmp_path, capsys):
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Mitoz bölünme nasıl gerçekleşir?",
              "--cozum", "Profaz, metafaz, anafaz, telofaz sırasıyla olur.")
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "coz",
                    "--motor", "yok", "Mayoz bölünme nasıl gerçekleşir?")
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "İNCELE" in cikti
    assert "yerel_rag" in cikti or "ragsiz" in cikti


def test_biyo_motor_ortam_degiskeni_bayraksiz_gecerli(tmp_path, capsys, monkeypatch):
    """Bayrak verilmezse motor türü BIYO_MOTOR'dan gelmeli (argparse onu ezmemeli)."""
    monkeypatch.setenv("BIYO_MOTOR", "yok")
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Enzim nedir?", "--cozum", "Biyolojik katalizördür.")
    capsys.readouterr()
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "coz",
                    "--json", "Enzimler ne işe yarar?")
    assert kod == 0
    veri = json.loads(capsys.readouterr().out)
    assert veri["model"] == "", "motor 'yok' iken model çalıştırılmamalı"


def test_motor_bayragi_ortam_degiskenini_ezer(tmp_path, capsys, monkeypatch):
    monkeypatch.setenv("BIYO_MOTOR", "mlx")
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Enzim nedir?", "--cozum", "Biyolojik katalizördür.")
    capsys.readouterr()
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "coz",
                    "--motor", "yok", "--json", "Enzimler ne işe yarar?")
    assert kod == 0  # mlx yüklenmeye çalışılmadan 'yok' uygulanmalı


def test_coz_json_ciktisi(tmp_path, capsys):
    _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
              "--soru", "Enzim nedir?", "--cozum", "Biyolojik katalizördür.")
    capsys.readouterr()  # ekleme çıktısını at, yalnız JSON kalsın
    _calistir("--veri", str(tmp_path), "--gommesiz", "coz", "--motor", "yok",
              "--json", "Enzimler ne işe yarar?")
    veri = json.loads(capsys.readouterr().out)
    assert "adimlar" in veri and "guven" in veri


def test_coz_sorusuz_hata(tmp_path):
    # --gommesiz şart: soru boşluğu çözücü kurulduktan SONRA yakalanıyor, yani
    # bayrak olmadan bu test gerçek gömme modelini indirip yüklüyor (~10 sn).
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "coz", "--motor", "yok") == 2


def test_coz_bozuk_secenek_bicimi(tmp_path):
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "coz", "--motor", "yok",
                    "--secenek", "A-bir", "Soru?")
    assert kod == 2


def test_disa_aktar_dosyalari_uretir(tmp_path):
    for i in range(6):
        _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
                  "--soru", f"Soru {i} nedir?", "--cozum", f"Çözüm {i}.")
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "disa-aktar", "--etiket", "v1")
    assert kod == 0
    hedef = tmp_path / "egitim" / "v1"
    assert (hedef / "train.jsonl").exists()
    assert json.loads((hedef / "ozet.json").read_text(encoding="utf-8"))["etiket"] == "v1"
    assert Depo(tmp_path / "biyo.db").egitim_surumleri()[0]["etiket"] == "v1"


def test_disa_aktar_bos_hafizada_hata(tmp_path):
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "disa-aktar") == 1


def test_degerlendir_bos_hafizada_hata(tmp_path):
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "degerlendir",
                     "--motor", "yok") == 1


def test_model_kur_zip_acar(tmp_path):
    arsiv = tmp_path / "model.zip"
    with zipfile.ZipFile(arsiv, "w") as z:
        z.writestr("config.json", "{}")
        z.writestr("agirlik.safetensors", "sahte")
    kod = _calistir("--veri", str(tmp_path), "model-kur", str(arsiv),
                    "--hedef", str(tmp_path / "kurulu"))
    assert kod == 0
    assert (tmp_path / "kurulu" / "config.json").exists()


def test_model_kur_zip_slip_engeller(tmp_path, capsys):
    """Arşiv içindeki "../" yolu hedef dizinin dışına yazmamalı."""
    arsiv = tmp_path / "kotu.zip"
    with zipfile.ZipFile(arsiv, "w") as z:
        z.writestr("../kacak.txt", "kötü")
    kod = _calistir("--veri", str(tmp_path), "model-kur", str(arsiv),
                    "--hedef", str(tmp_path / "kurulu"))
    assert kod == 1
    assert "Güvenlik" in capsys.readouterr().err
    assert not (tmp_path / "kacak.txt").exists()


def test_model_kur_olmayan_dosya(tmp_path):
    assert _calistir("--veri", str(tmp_path), "model-kur", str(tmp_path / "yok.zip")) == 1


def test_yardim_calisir():
    with pytest.raises(SystemExit) as hata:
        main(["--help"])
    assert hata.value.code == 0


# --- kaynaktan alım komutu ---


_AL_METNI = (
    "1. Aşağıdakilerden hangisi kloroplastta gerçekleşir?\n"
    "A) Krebs döngüsü\nB) Fotosentez\n"
    "ÇÖZÜM\nKloroplast fotosentezin gerçekleştiği organeldir.\n"
    "CEVAP: B\n\n"
    "2. Enzimlerin aktivasyon enerjisine etkisi nedir?\n"
    "ÇÖZÜM\nEnzimler aktivasyon enerjisini düşürerek tepkimeyi hızlandırır.\n"
    "Yanıt: Aktivasyon enerjisini düşürür\n"
)


def _kaynak_dosyasi(tmp_path):
    yol = tmp_path / "kitap.txt"
    yol.write_text(_AL_METNI, encoding="utf-8")
    return str(yol)


def test_al_varsayilan_olarak_yazmaz(tmp_path, capsys):
    """Önizleme varsayılan: kitap taraması gürültülü, otomatik yazmak riskli."""
    veri = tmp_path / "veri"
    kod = _calistir("--veri", str(veri), "--gommesiz", "al", _kaynak_dosyasi(tmp_path))
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "2 aday bulundu" in cikti
    assert "hiçbir şey yazılmadı" in cikti

    from biyo_cozucu.depo import Depo
    assert Depo(veri / "biyo.db").ornek_sayisi() == 0


def test_al_uygula_ile_hafizaya_yazar(tmp_path, capsys):
    veri = tmp_path / "veri"
    kod = _calistir("--veri", str(veri), "--gommesiz", "al",
                    _kaynak_dosyasi(tmp_path), "--uygula")
    assert kod == 0
    assert "Eklendi: 2" in capsys.readouterr().out

    from biyo_cozucu.depo import Depo
    depo = Depo(veri / "biyo.db")
    assert depo.ornek_sayisi() == 2
    ornek = next(o for o in depo.ornekler() if "kloroplastta" in o.soru)
    assert ornek.cevap == "B"
    assert ornek.secenekler == {"A": "Krebs döngüsü", "B": "Fotosentez"}
    assert "kitap.txt" in ornek.kaynak


def test_al_json_ciktisi(tmp_path, capsys):
    _calistir("--veri", str(tmp_path / "veri"), "--gommesiz", "al",
              _kaynak_dosyasi(tmp_path), "--json")
    veri = json.loads(capsys.readouterr().out)
    assert len(veri) == 2
    assert veri[0]["cevap"] == "B"
    assert veri[0]["cevap_turu"] == "coktan_secmeli"


def test_al_asgari_guven_suzer(tmp_path, capsys):
    veri = tmp_path / "veri"
    _calistir("--veri", str(veri), "--gommesiz", "al",
              _kaynak_dosyasi(tmp_path), "--uygula", "--asgari-guven", "0.85")
    cikti = capsys.readouterr().out
    assert "Eklendi: 1" in cikti, "yalnız yüksek güvenli aday geçmeli"


def test_al_olmayan_dosya_hata_verir(tmp_path):
    assert _calistir("--veri", str(tmp_path), "al", str(tmp_path / "yok.pdf")) == 1


def test_al_desteklenmeyen_tur_hata_verir(tmp_path):
    yol = tmp_path / "sunum.pptx"
    yol.write_bytes(b"x")
    assert _calistir("--veri", str(tmp_path), "al", str(yol)) == 1


# --- açık veri setleri ---


def test_set_listele_durum_ve_lisansi_gosterir(capsys):
    assert _calistir("set-listele") == 0
    cikti = capsys.readouterr().out
    assert "openbookqa" in cikti
    assert "Apache-2.0" in cikti
    # Alınamayan setler nedenini de yazmalı; sessiz "hazır değil" yetmez.
    assert "kapılı" in cikti and "HF_TOKEN" in cikti
    assert "görsel" in cikti and "görüntü" in cikti


def test_set_al_lisans_kapisini_cli_uzerinden_de_uygular(tmp_path, capsys):
    """Kapı yalnız kütüphane katmanında değil, kullanıcının gerçekten
    kullandığı yolda da tutmalı."""
    kod = _calistir("--veri", str(tmp_path), "set-al", "turkish_mmlu", "--amac", "egitim")
    assert kod == 2
    assert "eğitim verisine katılmaya" in capsys.readouterr().err


def test_set_al_kapili_seti_anlamli_reddeder(tmp_path, capsys):
    kod = _calistir(
        "--veri", str(tmp_path), "set-al", "turkish_mmlu", "--amac", "degerlendirme"
    )
    assert kod == 2
    assert "HF_TOKEN" in capsys.readouterr().err


def test_set_al_gorsel_seti_anlamli_reddeder(tmp_path, capsys):
    kod = _calistir("--veri", str(tmp_path), "set-al", "yksbench")
    assert kod == 2
    assert "görüntü" in capsys.readouterr().err


def test_set_al_bilinmeyen_seti_reddeder(tmp_path, capsys):
    assert _calistir("--veri", str(tmp_path), "set-al", "uydurma") == 2
    assert "Bilinmeyen veri seti" in capsys.readouterr().err


def test_set_al_uygulanmadan_hicbir_sey_yazmaz(tmp_path, capsys, monkeypatch):
    """Varsayılan önizleme: `al` komutuyla aynı disiplin — otomatik yazma yok."""
    from biyo_cozucu.modeller import Ornek
    from biyo_cozucu.veri import acik_setler

    monkeypatch.setattr(
        acik_setler, "_hf_yukle",
        lambda veri_seti, bolum: [
            {
                "question_stem": "Which organelle makes ATP in animal cells?",
                "choices": {"text": ["ribosome", "mitochondrion"], "label": ["A", "B"]},
                "answerKey": "B",
                "fact1": "the mitochondrion is the cell organelle that produces ATP",
            }
        ],
    )
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "set-al", "openbookqa",
        "--amac", "egitim", "--tum-konular",
    )
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "1 örnek üretildi" in cikti
    assert "Hiçbir şey yazılmadı" in cikti
    assert not (tmp_path / "biyo.db").exists() or Depo(
        tmp_path / "biyo.db"
    ).ornek_sayisi() == 0
    assert Ornek  # içe aktarma kullanıldı


def test_set_al_uygula_ile_hafizaya_yazar(tmp_path, capsys, monkeypatch):
    from biyo_cozucu.veri import acik_setler

    monkeypatch.setattr(
        acik_setler, "_hf_yukle",
        lambda veri_seti, bolum: [
            {
                "question_stem": "Which organelle makes ATP in animal cells?",
                "choices": {"text": ["ribosome", "mitochondrion"], "label": ["A", "B"]},
                "answerKey": "B",
                "fact1": "the mitochondrion is the cell organelle that produces ATP",
            }
        ],
    )
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "set-al", "openbookqa",
        "--amac", "egitim", "--tum-konular", "--uygula",
    )
    assert kod == 0
    assert "Eklenen: 1" in capsys.readouterr().out
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 1


# --- toplu alım: dizin, dayanıklılık, yinelenen kaynak ---


def test_al_dizini_ozyinelemeli_tarar(tmp_path, capsys):
    kaynaklar = tmp_path / "kitaplik" / "unite3"
    kaynaklar.mkdir(parents=True)
    (kaynaklar / "bir.txt").write_text(_AL_METNI, encoding="utf-8")
    (tmp_path / "kitaplik" / "iki.txt").write_text(
        "5. Mitoz bölünmede kromozom sayısı neden korunur?\n"
        "ÇÖZÜM\nDNA interfazda eşlendiği için sayı korunur.\n"
        "Yanıt: DNA eşlendiği için\n",
        encoding="utf-8",
    )
    kod = _calistir(
        "--veri", str(tmp_path / "veri"), "--gommesiz",
        "al", str(tmp_path / "kitaplik"), "--uygula",
    )
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "2 dosya işlenecek" in cikti
    assert Depo(tmp_path / "veri" / "biyo.db").ornek_sayisi() == 3


def test_al_dizinde_desteklenmeyen_dosyalari_atlar(tmp_path, capsys):
    """Kitaplık klasöründe kapak görseli, not ve .DS_Store olur; hepsini
    ayrıştırıcıya vermek her koşuda onlarca sahte hata üretirdi."""
    kaynaklar = tmp_path / "kitaplik"
    kaynaklar.mkdir()
    (kaynaklar / "kitap.txt").write_text(_AL_METNI, encoding="utf-8")
    (kaynaklar / "sunum.pptx").write_bytes(b"x")
    (kaynaklar / ".DS_Store").write_bytes(b"x")
    (kaynaklar / "notlar.numbers").write_bytes(b"x")

    kod = _calistir("--veri", str(tmp_path / "veri"), "--gommesiz",
                    "al", str(kaynaklar))
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "Okunamayan dosya" not in cikti, "desteklenmeyenler hata sayılmamalı"


def test_al_gizli_dizinleri_atlar(tmp_path):
    kaynaklar = tmp_path / "kitaplik"
    (kaynaklar / ".gecici").mkdir(parents=True)
    (kaynaklar / ".gecici" / "kopya.txt").write_text(_AL_METNI, encoding="utf-8")
    (kaynaklar / "kitap.txt").write_text(_AL_METNI, encoding="utf-8")

    from biyo_cozucu.cli import _alinacak_dosyalar
    dosyalar = _alinacak_dosyalar([str(kaynaklar)])
    assert [d.name for d in dosyalar] == ["kitap.txt"]


def test_al_bozuk_dosya_klasorun_kalanini_durdurmaz(tmp_path, capsys):
    kaynaklar = tmp_path / "kitaplik"
    kaynaklar.mkdir()
    (kaynaklar / "saglam.txt").write_text(_AL_METNI, encoding="utf-8")
    (kaynaklar / "bozuk.pdf").write_bytes(b"bu bir PDF degil")

    kod = _calistir("--veri", str(tmp_path / "veri"), "--gommesiz",
                    "al", str(kaynaklar), "--uygula")
    assert kod == 0, "bir bozuk dosya tüm koşuyu düşürmemeli"
    cikti = capsys.readouterr().out
    assert "Okunamayan dosya: 1" in cikti
    assert Depo(tmp_path / "veri" / "biyo.db").ornek_sayisi() == 2


def test_al_hicbir_dosya_okunamazsa_hata_doner(tmp_path):
    kaynaklar = tmp_path / "kitaplik"
    kaynaklar.mkdir()
    (kaynaklar / "bozuk.pdf").write_bytes(b"bu bir PDF degil")
    assert _calistir("--veri", str(tmp_path / "veri"), "--gommesiz",
                     "al", str(kaynaklar)) == 1


def test_al_ayni_icerigi_ikinci_kez_islemez(tmp_path, capsys):
    """İmza dosya ADINA değil içeriğe bağlı: yeniden adlandırılan ya da
    başka klasöre kopyalanan aynı kitap tekrar işlenmemeli."""
    veri = tmp_path / "veri"
    ilk = tmp_path / "kitap.txt"
    ilk.write_text(_AL_METNI, encoding="utf-8")
    assert _calistir("--veri", str(veri), "--gommesiz", "al", str(ilk), "--uygula") == 0
    capsys.readouterr()

    kopya = tmp_path / "kitap-yedek.txt"
    kopya.write_text(_AL_METNI, encoding="utf-8")
    assert _calistir("--veri", str(veri), "--gommesiz", "al", str(kopya), "--uygula") == 0
    cikti = capsys.readouterr().out
    assert "daha önce alınmış" in cikti
    assert Depo(veri / "biyo.db").ornek_sayisi() == 2, "yeni örnek eklenmemeli"


def test_al_ayni_dosya_iki_kez_verilirse_bir_kez_islenir(tmp_path, capsys):
    yol = _kaynak_dosyasi(tmp_path)
    kod = _calistir("--veri", str(tmp_path / "veri"), "--gommesiz", "al", yol, yol)
    assert kod == 0
    assert capsys.readouterr().out.count("aday bulundu") == 1


def test_al_onizlemede_kaynak_isaretlenmez(tmp_path, capsys):
    """Önizleme hiçbir kalıcı iz bırakmamalı; aksi halde `--uygula` ile
    yapılan ikinci koşu "zaten alınmış" diye atlanırdı."""
    veri = tmp_path / "veri"
    yol = _kaynak_dosyasi(tmp_path)
    _calistir("--veri", str(veri), "--gommesiz", "al", yol)
    capsys.readouterr()
    assert _calistir("--veri", str(veri), "--gommesiz", "al", yol, "--uygula") == 0
    assert Depo(veri / "biyo.db").ornek_sayisi() == 2


# --- Soru Kesici arşivi ---


def _soru_kesici_arsivi(tmp_path):
    import io
    import zipfile

    from PIL import Image

    tampon = io.BytesIO()
    Image.new("RGB", (12, 8), (20, 160, 90)).save(tampon, format="PNG")
    png = tampon.getvalue()

    kayitlar = [
        {
            "dosya": f"soru_{i:02d}.png",
            "sayfa": i,
            "kaynak": "10.sinif.pdf",
            "cevap": None,
            "metin": f"Soru-{i}) Fotosentezde klorofilin görevi nedir?",
            "siklar": {"A": "Işık soğurur", "B": "Su üretir"},
            "konu": "Fotosentez ve Solunum",
            "guven": 0.9,
        }
        for i in (1, 2)
    ]
    yol = tmp_path / "arsiv.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("sorular.json", json.dumps(kayitlar, ensure_ascii=False))
        for kayit in kayitlar:
            z.writestr(kayit["dosya"], png)
    return yol


def test_arsiv_coz_varsayilan_olarak_cozmez(tmp_path, capsys):
    """`al` ile aynı disiplin: çözme soru başına bir model çağrısı, 1200
    soruluk arşivde saatler sürer — yanlışlıkla başlatılmamalı."""
    pytest.importorskip("PIL")
    veri = tmp_path / "veri"
    kod = _calistir("--veri", str(veri), "--gommesiz",
                    "arsiv-coz", str(_soru_kesici_arsivi(tmp_path)))
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "Soru: 2" in cikti
    assert "görselli: 2" in cikti
    assert "hiçbir soru çözülmedi" in cikti
    # Önizleme hiçbir çözüm yazmamalı; veritabanı hiç açılmamış da olabilir.
    if (veri / "biyo.db").exists():
        assert Depo(veri / "biyo.db").ozet()["cozum"] == 0
    assert not (veri / "gorseller").exists(), "önizlemede görsel kopyalanmamalı"


def test_arsiv_coz_sorulari_cozer_ve_gorseli_depoya_alir(tmp_path, capsys):
    pytest.importorskip("PIL")
    veri = tmp_path / "veri"
    kod = _calistir("--veri", str(veri), "--gommesiz", "arsiv-coz",
                    str(_soru_kesici_arsivi(tmp_path)), "--coz", "--motor", "yok")
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "Çözülen: 2" in cikti
    # Görseller çözüm deposuna alınmalı; VLM yolu bunları okuyacak.
    assert len(list((veri / "gorseller").glob("*.png"))) >= 1
    assert Depo(veri / "biyo.db").ozet()["cozum"] == 2


def test_arsiv_coz_limit_ve_asgari_guven_suzer(tmp_path, capsys):
    pytest.importorskip("PIL")
    veri = tmp_path / "veri"
    _calistir("--veri", str(veri), "--gommesiz", "arsiv-coz",
              str(_soru_kesici_arsivi(tmp_path)), "--coz", "--motor", "yok",
              "--limit", "1")
    assert "Çözülen: 1" in capsys.readouterr().out

    veri2 = tmp_path / "veri2"
    _calistir("--veri", str(veri2), "--gommesiz", "arsiv-coz",
              str(_soru_kesici_arsivi(tmp_path)), "--coz", "--motor", "yok",
              "--asgari-guven", "0.99")
    assert "Çözülen: 0" in capsys.readouterr().out


def test_arsiv_coz_bozuk_arsivi_anlamli_reddeder(tmp_path, capsys):
    yol = tmp_path / "bos.zip"
    import zipfile
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("okuma.txt", "içerik")
    assert _calistir("--veri", str(tmp_path / "veri"), "arsiv-coz", str(yol)) == 1
    assert "sorular.json" in capsys.readouterr().err


# --- paket-al -----------------------------------------------------------


def _paket_zip(yol, kayitlar, *, gorsel=True) -> None:
    """Sentetik AYT paketi: künye + soru görselleri."""
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr(
            "ayt_cozumleri.json",
            json.dumps({"sorular": kayitlar}, ensure_ascii=False),
        )
        z.writestr("README.txt", "kısa açıklama")
        if gorsel:
            from tests.test_soru_kesici import _png

            for kayit in kayitlar:
                z.writestr(kayit["soru_gorseli"], _png())


def _ayt_kaydi(no: int) -> dict:
    return {
        "soru_no": no,
        "yil": 2019,
        "unite": "Bitki Biyolojisi",
        "konu": "Bitkilerin Yapısı",
        "kaynak_kitap_sayfa": 40 + no,
        "soru_metni": f"Ksilem hakkında {no}. soru?",
        "secenekler": {"A": "Su taşır", "B": "Besin taşır"},
        "soru_gorseli": f"sorular_png/soru_{no:02d}.png",
        "cevap_anahtari": "A",
        "cevap_anahtari_ile_uyumlu": True,
        "confidence": 0.95,
        "ayrintili_cozum": {
            "cozum_adimlari": [f"Ksilem suyu {no} yönde taşır."],
            "secenek_analizi": {"A": {"aciklama": "Doğru."}},
            "sonuc": "Cevap A.",
        },
    }


def test_paket_al_onizleme_hicbir_sey_yazmaz(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    _paket_zip(yol, [_ayt_kaydi(1), _ayt_kaydi(2)], gorsel=False)
    veri = tmp_path / "veri"
    assert _calistir("--veri", str(veri), "paket-al", str(yol)) == 0
    cikti = capsys.readouterr().out
    assert "Soru: 2" in cikti
    assert "bitki biyolojisi" in cikti
    assert "Önizleme modu" in cikti
    assert not (veri / "biyo.db").exists()


def test_paket_al_jsonl_yazar(tmp_path):
    yol = tmp_path / "paket.zip"
    _paket_zip(yol, [_ayt_kaydi(1)], gorsel=False)
    hedef = tmp_path / "cikti" / "ayt.jsonl"
    kod = _calistir(
        "--veri", str(tmp_path / "veri"), "paket-al", str(yol),
        "--jsonl", str(hedef), "--kaynak", "AYT Paketi", "--gorselsiz",
    )
    assert kod == 0
    kayit = json.loads(hedef.read_text(encoding="utf-8").splitlines()[0])
    assert kayit["konu"] == "bitki biyolojisi"
    assert kayit["kaynak"] == "AYT Paketi (s. 41)"
    assert kayit["etiket_kaynagi"] == "kural"
    assert "id" not in kayit


def test_paket_al_uygula_hafizaya_yazar(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    _paket_zip(yol, [_ayt_kaydi(1), _ayt_kaydi(2)], gorsel=False)
    veri = tmp_path / "veri"
    kod = _calistir(
        "--veri", str(veri), "--gommesiz", "paket-al", str(yol),
        "--uygula", "--gorselsiz",
    )
    assert kod == 0
    assert "Eklendi: 2" in capsys.readouterr().out
    assert Depo(veri / "biyo.db").ornek_sayisi() == 2


def test_paket_al_gorseli_depoya_yazar(tmp_path):
    pytest.importorskip("PIL")
    yol = tmp_path / "paket.zip"
    _paket_zip(yol, [_ayt_kaydi(1)])
    veri = tmp_path / "veri"
    hedef = tmp_path / "ayt.jsonl"
    assert _calistir(
        "--veri", str(veri), "paket-al", str(yol), "--jsonl", str(hedef)
    ) == 0
    kayit = json.loads(hedef.read_text(encoding="utf-8").splitlines()[0])
    assert kayit["gorsel"]
    assert (veri / "gorseller" / f"{kayit['gorsel']}.png").exists()


def test_paket_al_dusuk_guveni_eler(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    dusuk = _ayt_kaydi(1)
    dusuk["confidence"] = 0.3
    _paket_zip(yol, [dusuk, _ayt_kaydi(2)], gorsel=False)
    assert _calistir("--veri", str(tmp_path / "veri"), "paket-al", str(yol)) == 0
    assert "Süzgeçten geçen: 1/2" in capsys.readouterr().out


def test_paket_al_hepsi_kademesi_elemez(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    dusuk = _ayt_kaydi(1)
    dusuk["confidence"] = 0.3
    _paket_zip(yol, [dusuk, _ayt_kaydi(2)], gorsel=False)
    assert _calistir(
        "--veri", str(tmp_path / "veri"), "paket-al", str(yol), "--guven", "hepsi"
    ) == 0
    assert "Süzgeçten geçen: 2/2" in capsys.readouterr().out


def test_paket_al_taninmayan_sema_hata_verir(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("kunye.json", json.dumps({"veriler": []}))
    assert _calistir("--veri", str(tmp_path / "veri"), "paket-al", str(yol)) == 2
    assert "tanınmadı" in capsys.readouterr().err


def test_paket_al_kunyesiz_arsiv_hata_verir(tmp_path, capsys):
    yol = tmp_path / "paket.zip"
    with zipfile.ZipFile(yol, "w") as z:
        z.writestr("okuma.txt", "içerik")
    assert _calistir("--veri", str(tmp_path / "veri"), "paket-al", str(yol)) == 2
    assert "json" in capsys.readouterr().err


def test_ornek_ekle_gorsel_imzasini_okur(tmp_path):
    """JSON alımı `gorsel` alanını atlıyordu; paket görselleri sessizce kayboluyordu."""
    dosya = tmp_path / "ornek.jsonl"
    dosya.write_text(
        json.dumps(
            {"soru": "Şekildeki organel hangisidir?", "cozum": "Mitokondri.",
             "cevap": "Mitokondri", "gorsel": "abc123", "cozum_turu": "ezber_bilgi",
             "etiket_kaynagi": "kural"},
            ensure_ascii=False,
        ) + "\n",
        encoding="utf-8",
    )
    assert _calistir("--veri", str(tmp_path), "--gommesiz", "ornek-ekle", str(dosya)) == 0
    ornek = Depo(tmp_path / "biyo.db").ornekler()[0]
    assert ornek.gorsel == "abc123"
    assert ornek.etiket_kaynagi == "kural"


def test_degerlendir_varsayilan_sicaklik_sifir():
    """Kör koşu koşular ARASI farkı ölçüyor; sıcaklık > 0 bunu gürültüye boğuyordu.

    Ölçümde 12 soruluk kümede boş cevap sayısı aynı ayarla 3 ile 6 arasında
    değişti; sıfırda iki ardışık koşu birebir aynı sonucu verdi.
    """
    from biyo_cozucu.cli import ayristirici

    argumanlar = ayristirici().parse_args(["degerlendir"])
    assert argumanlar.sicaklik == 0.0


def test_coz_varsayilan_sicakligi_ayarlardan_alir():
    """`coz` yolunda `--sicaklik` yok; çözücü kendi varsayılanını korumalı."""
    from biyo_cozucu.cli import _cozucu_kur
    from biyo_cozucu.cozucu import Ayarlar

    class SahteArgumanlar:
        veri = None
        motor = "yok"
        gommesiz = True
        ornek_sayisi = 3

    cozucu = _cozucu_kur(SahteArgumanlar(), motor_gerekli=False)
    assert cozucu.ayarlar.sicaklik == Ayarlar().sicaklik
