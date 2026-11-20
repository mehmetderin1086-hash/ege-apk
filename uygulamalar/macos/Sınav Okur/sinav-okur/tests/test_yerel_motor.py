"""yerel_motor sarmalayıcısının HTTP katmanı ve üretici protokolü testleri."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from sinav_okur import yerel_motor
from sinav_okur.yapay_zeka import YapayZekaHatasi


@pytest.fixture(autouse=True)
def temiz_durum(monkeypatch):
    monkeypatch.setattr(yerel_motor, "_surec", None)
    monkeypatch.setattr(yerel_motor, "_surec_adresi", None)
    monkeypatch.setattr(yerel_motor, "_model_sicak", False)
    monkeypatch.setattr(yerel_motor, "_baslatma_hatasi", None)
    monkeypatch.setattr(yerel_motor, "_baslatma_hatasi_zamani", 0.0)
    monkeypatch.setattr(yerel_motor, "_desteklemeyen_adresler", set())
    monkeypatch.delenv("SINAV_OKUR_BIYO_URL", raising=False)
    monkeypatch.delenv("SINAV_OKUR_BIYO_PORTLAR", raising=False)
    monkeypatch.delenv("SINAV_OKUR_BIYO_KOK", raising=False)

    # Testler geliştirme makinesinde çalışan gerçek biyo-cozucu .app'ini
    # görmemeli; her test kendi sahtesini kurar.
    def sunucu_yok(url, **_ayar):
        raise YapayZekaHatasi("test ortamında sunucu yok")

    monkeypatch.setattr(yerel_motor, "_json_istek", sunucu_yok)


def test_port_araligi_ayristirilir(monkeypatch):
    monkeypatch.setenv("SINAV_OKUR_BIYO_PORTLAR", "8031-8033")
    assert yerel_motor._alt_surec_portlari() == [8031, 8032, 8033]
    monkeypatch.setenv("SINAV_OKUR_BIYO_PORTLAR", "9001, 9005")
    assert yerel_motor._alt_surec_portlari() == [9001, 9005]


def test_sunucu_bulma_once_app_araligini_tarar(monkeypatch):
    gorulen = []

    def sahte_istek(url, **_ayar):
        gorulen.append(url)
        if ":8025/" in url:
            return {"app": "biyo-cozucu", "status": "ready"}
        raise YapayZekaHatasi("kapalı")

    monkeypatch.setattr(yerel_motor, "_json_istek", sahte_istek)
    assert yerel_motor.yerel_sunucu_bul() == "http://127.0.0.1:8025"
    # .app aralığı (8020-8030) alt süreç aralığından önce taranmalı.
    assert gorulen[0].startswith("http://127.0.0.1:8020")


def test_sunucu_bulma_yanlis_uygulamayi_reddeder(monkeypatch):
    monkeypatch.setattr(
        yerel_motor,
        "_json_istek",
        lambda url, **_a: {"app": "pdf-studio", "status": "ready"},
    )
    assert yerel_motor.yerel_sunucu_bul() is None


def test_ozel_adres_loopback_disina_kapali(monkeypatch):
    monkeypatch.setenv("SINAV_OKUR_BIYO_URL", "http://192.168.1.10:8020")
    monkeypatch.setattr(
        yerel_motor,
        "_json_istek",
        lambda url, **_a: {"app": "biyo-cozucu"},
    )
    assert yerel_motor.yerel_sunucu_bul() is None


def test_durum_fonksiyonu_sunucu_baslatmaz(monkeypatch, tmp_path):
    def patlat():
        raise AssertionError("durum fonksiyonu sunucu başlatmamalı")

    monkeypatch.setattr(yerel_motor, "yerel_sunucu_baslat", patlat)
    monkeypatch.setattr(yerel_motor, "yerel_sunucu_bul", lambda: None)
    monkeypatch.setenv("SINAV_OKUR_BIYO_KOK", str(tmp_path))
    durum = yerel_motor.yerel_motor_durumu()
    assert durum == {
        "hazir": False,
        "kullanilabilir": False,
        "mesaj": "biyo-cozucu kurulumu bulunamadı; yerel motor kapalı.",
    }

    (tmp_path / ".venv" / "bin").mkdir(parents=True)
    (tmp_path / ".venv" / "bin" / "biyo-cozucu").write_text("#!/bin/sh\n")
    durum = yerel_motor.yerel_motor_durumu()
    assert durum["kullanilabilir"] and not durum["hazir"]


def test_uret_bos_yaniti_reddeder(monkeypatch):
    monkeypatch.setattr(
        yerel_motor, "yerel_sunucu_bul", lambda: "http://127.0.0.1:8031"
    )
    monkeypatch.setattr(
        yerel_motor, "_json_istek", lambda url, **_a: {"metin": "  "}
    )
    with pytest.raises(YapayZekaHatasi, match="boş yanıt"):
        yerel_motor.yerel_uret([{"role": "user", "content": "soru"}])


def test_uret_ilk_istekte_uzun_zamanasimi_kullanir(monkeypatch):
    sureler = []

    def sahte_istek(url, *, veri=None, timeout=0, **_a):
        sureler.append(timeout)
        return {"metin": "cevap"}

    monkeypatch.setattr(
        yerel_motor, "yerel_sunucu_bul", lambda: "http://127.0.0.1:8031"
    )
    monkeypatch.setattr(yerel_motor, "_json_istek", sahte_istek)
    yerel_motor.yerel_uret([{"role": "user", "content": "a"}])
    yerel_motor.yerel_uret([{"role": "user", "content": "b"}])
    assert sureler == [
        yerel_motor.ILK_URETIM_ZAMANASIMI,
        yerel_motor.URETIM_ZAMANASIMI,
    ]


def _gecerli_anahtar_json(no: int) -> str:
    return json.dumps(
        {
            "cevaplar": [
                {
                    "no": no,
                    "cevap": "Mitokondri oksijenli solunum yapar.",
                    "rubrik": [
                        {
                            "olcut": "Mitokondri oksijenli solunum merkezidir",
                            "esanlamlilar": ["oksijenli solunum"],
                            "kategori": "kavram",
                            "celiskiler": [],
                        }
                    ],
                    "puanlanabilir": True,
                    "uyari": "",
                    "cevap_turu": "acik_uclu",
                }
            ]
        },
        ensure_ascii=False,
    )


def test_uretici_protokolu_yapay_zeka_cevabi_dondurur(monkeypatch):
    istekler = []

    def sahte_uret(mesajlar, **_ayar):
        istekler.append(mesajlar)
        govde = json.loads(mesajlar[1]["content"])
        return _gecerli_anahtar_json(govde["sorular"][0]["no"])

    monkeypatch.setattr(yerel_motor, "yerel_uret", sahte_uret)
    sonuc = yerel_motor.yerel_cevap_anahtarlari_uret(
        [(1, "Mitokondrinin görevi nedir?", 10.0), (2, "Ribozom nedir?", 5.0)],
        ders="Biyoloji",
    )
    assert [x.soru_no for x in sonuc] == [1, 2]
    assert sonuc[0].rubrik == ["Mitokondri oksijenli solunum merkezidir"]
    assert sonuc[0].rubrik_es_anlamlilari == [["oksijenli solunum"]]
    # Sorular yerel modele hep tek tek gönderilir.
    assert len(istekler) == 2
    assert all(m[0]["role"] == "system" for m in istekler)


def test_uretici_ikinci_denemede_kurtarir(monkeypatch):
    sayac = {"deneme": 0}

    def sahte_uret(mesajlar, **_ayar):
        sayac["deneme"] += 1
        if sayac["deneme"] == 1:
            return "geçerli JSON değil"
        return _gecerli_anahtar_json(1)

    monkeypatch.setattr(yerel_motor, "yerel_uret", sahte_uret)
    sonuc = yerel_motor.yerel_cevap_anahtarlari_uret([(1, "Soru?", 10.0)])
    assert sayac["deneme"] == 2
    assert sonuc[0].soru_no == 1


def test_uretici_iki_denemede_de_hata_firlatir(monkeypatch):
    monkeypatch.setattr(
        yerel_motor, "yerel_uret", lambda mesajlar, **_a: "bozuk"
    )
    with pytest.raises(YapayZekaHatasi):
        yerel_motor.yerel_cevap_anahtarlari_uret([(1, "Soru?", 10.0)])


def test_eski_surum_app_atlanir_ve_alt_surece_dusulur(monkeypatch):
    """Çalışan .app'te /api/v1/uret yoksa kendi sürecimize düşülmeli."""
    baslatildi = []

    def sahte_istek(url, *, veri=None, timeout=0, **_a):
        if url.startswith("http://127.0.0.1:8020"):
            raise YapayZekaHatasi("Yerel sunucu HTTP 404: Not Found")
        return {"metin": "yerel cevap"}

    def sahte_baslat():
        baslatildi.append(1)
        monkeypatch.setattr(yerel_motor, "_surec_adresi", "http://127.0.0.1:8031")
        return "http://127.0.0.1:8031"

    adresler = iter(["http://127.0.0.1:8020", None])
    monkeypatch.setattr(yerel_motor, "yerel_sunucu_bul", lambda: next(adresler))
    monkeypatch.setattr(yerel_motor, "yerel_sunucu_baslat", sahte_baslat)
    monkeypatch.setattr(yerel_motor, "_json_istek", sahte_istek)

    assert yerel_motor.yerel_uret([{"role": "user", "content": "a"}]) == "yerel cevap"
    assert baslatildi == [1]
    assert "http://127.0.0.1:8020" in yerel_motor._desteklemeyen_adresler


def test_kendi_surecimiz_404_verirse_hata_yutulmaz(monkeypatch):
    monkeypatch.setattr(yerel_motor, "_surec_adresi", "http://127.0.0.1:8031")
    monkeypatch.setattr(
        yerel_motor, "yerel_sunucu_bul", lambda: "http://127.0.0.1:8031"
    )

    def sahte_istek(url, **_a):
        raise YapayZekaHatasi("Yerel sunucu HTTP 404: Not Found")

    monkeypatch.setattr(yerel_motor, "_json_istek", sahte_istek)
    with pytest.raises(YapayZekaHatasi, match="404"):
        yerel_motor.yerel_uret([{"role": "user", "content": "a"}])


def test_baslatma_hatasi_sogumada_aninda_doner(monkeypatch, tmp_path):
    monkeypatch.setenv("SINAV_OKUR_BIYO_KOK", str(tmp_path))
    with pytest.raises(YapayZekaHatasi, match="kurulumu bulunamadı"):
        yerel_motor.yerel_sunucu_baslat()

    # Kurulum sonradan gelse bile soğuma süresi dolana dek aynı hata
    # beklemeden döner; rag_anahtar'ın yeniden denemeleri 60 sn'lik
    # health-poll bedeli ödemez.
    (tmp_path / ".venv" / "bin").mkdir(parents=True)
    (tmp_path / ".venv" / "bin" / "biyo-cozucu").write_text("#!/bin/sh\n")
    with pytest.raises(YapayZekaHatasi, match="kurulumu bulunamadı"):
        yerel_motor.yerel_sunucu_baslat()


def test_bos_soru_listesi_istek_atmaz(monkeypatch):
    def patlat(*_a, **_k):
        raise AssertionError("istek atılmamalı")

    monkeypatch.setattr(yerel_motor, "yerel_uret", patlat)
    assert yerel_motor.yerel_cevap_anahtarlari_uret([]) == []


def test_sohbet_isaretleri_temizlenir(monkeypatch):
    """Ölçüldü: MLX motoru yanıtın sonuna <|im_end|> bırakabiliyor."""
    monkeypatch.setattr(
        yerel_motor, "yerel_sunucu_bul", lambda: "http://127.0.0.1:8031"
    )
    monkeypatch.setattr(
        yerel_motor,
        "_json_istek",
        lambda url, **_a: {"metin": "Mitokondri ATP üretir.<|im_end|>"},
    )

    metin = yerel_motor.yerel_uret([{"role": "user", "content": "a"}])

    assert metin == "Mitokondri ATP üretir."


def test_bozuk_json_kurtarma_olculen_bozulmayi_cozer(monkeypatch):
    """Ölçüldü: model bir dizinin içine "sonuc": "..." sokup JSON'u bozuyor."""
    bozuk = (
        '{"cevaplar": [{"no": 1, "cevap": "Enerji üretmek", '
        '"rubrik": ["Mitokondri çift zarlıdır", "ATP üretir"], '
        '"yontem_adimlari": ["Temel bilgi", "sonuc": "Doğru cevap B"]}]}'
    )
    monkeypatch.setattr(yerel_motor, "yerel_uret", lambda m, **_a: bozuk)

    sonuc = yerel_motor.yerel_cevap_anahtarlari_uret([(1, "Soru?", 10.0)])

    assert sonuc[0].soru_no == 1
    assert sonuc[0].cevap == "Enerji üretmek"
    assert sonuc[0].rubrik == ["Mitokondri çift zarlıdır", "ATP üretir"]


def test_kurtarma_cevap_uydurmaz(monkeypatch):
    """Kurtarılacak alan yoksa hata verilmeli; boş anahtar üretilmemeli."""
    monkeypatch.setattr(
        yerel_motor, "yerel_uret", lambda m, **_a: "Bu bir açıklama metnidir."
    )

    with pytest.raises(YapayZekaHatasi):
        yerel_motor.yerel_cevap_anahtarlari_uret([(1, "Soru?", 10.0)])


def test_yerel_istem_duz_rubrik_ister():
    """Küçük model nesne biçimli rubriği bozuyordu; istem düz liste istemeli."""
    assert "DÜZ METİN listesidir" in yerel_motor.YEREL_ANAHTAR_SISTEM_ISTEMI


# --- Windows taşınabilirlik: yorumlayıcı/log yolu çözümü ---
#
# `os.name`'i "nt" yaparak WindowsPath üretimini bu Mac'te tetiklemek Python
# 3.12'de anında NotImplementedError verir (yanlış platformda somut Path alt
# sınıfı kurulamaz); bu yüzden "nt" dalının tam Path DEĞERİ yalnız gerçek bir
# Windows makinesinde doğrulanabilir. Burada env önceliği ve macOS varsayılan
# davranışının BİREBİR korunduğu doğrulanır.


def test_biyo_calistirilabilir_env_oncelikli(monkeypatch):
    monkeypatch.setenv("SINAV_OKUR_BIYO_PY", "~/ozel/python")
    assert yerel_motor._biyo_calistirilabilir() == Path("~/ozel/python").expanduser()


def test_biyo_calistirilabilir_macos_varsayilani(monkeypatch, tmp_path):
    monkeypatch.delenv("SINAV_OKUR_BIYO_PY", raising=False)
    monkeypatch.setenv("SINAV_OKUR_BIYO_KOK", str(tmp_path))
    monkeypatch.setattr(yerel_motor.os, "name", "posix")
    assert (
        yerel_motor._biyo_calistirilabilir()
        == tmp_path / ".venv" / "bin" / "biyo-cozucu"
    )


def test_kayit_yolu_macosta_degismez(monkeypatch):
    monkeypatch.setattr(yerel_motor.os, "name", "posix")
    yol = yerel_motor._kayit_yolu()
    assert yol == Path.home() / "Library" / "Logs" / "SinavOkur" / "biyo-motor.log"


def test_baslatma_komutu_windowsta_ortamsh_kullanmaz(monkeypatch):
    monkeypatch.setattr(yerel_motor.sys, "platform", "win32")
    komut = yerel_motor._baslatma_komutu(
        Path("C:/biyo/runtime/python.exe"), 8031, "mlx"
    )
    assert komut == [
        "C:/biyo/runtime/python.exe", "-m", "biyo_cozucu.cli", "sunucu",
        "--adres", "127.0.0.1", "--port", "8031", "--motor", "mlx",
    ]
    assert "/bin/zsh" not in komut


def test_baslatma_komutu_macosta_degismez():
    """macOS davranışı birebir korunmalı: login kabuğu + ortam.sh."""
    komut = yerel_motor._baslatma_komutu(
        Path("/biyo/.venv/bin/biyo-cozucu"), 8031, "mlx"
    )
    assert komut[0] == "/bin/zsh"
    assert komut[1] == "-lc"
    assert "ortam.sh" in komut[2]
    assert "/biyo/.venv/bin/biyo-cozucu sunucu" in komut[2]
