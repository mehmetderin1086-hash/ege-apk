"""Sıcak motor havuzu ve devre kesici: sahte motor betiğiyle süreç senaryoları."""
from __future__ import annotations

import json
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

from sinav_okur.ocr_havuz import HavuzHatasi, MotorHavuzu

SAHTE_SUNUCU = textwrap.dedent(
    """
    import json, os, sys, time
    sayac = 0
    for satir in sys.stdin:
        satir = satir.strip()
        if not satir:
            continue
        istek = json.loads(satir)
        if istek.get("kapat"):
            break
        sayac += 1
        gorsel = istek.get("gorsel", "")
        if "yavas" in gorsel:
            time.sleep(5)
        if "cok" in gorsel:
            sys.exit(1)
        yanit = {
            "blocks": [{"text": "mitokondri", "confidence": 0.9,
                        "x": 0, "y": 0, "width": 1, "height": 1}],
            "pid": os.getpid(),
            "sayac": sayac,
        }
        print(json.dumps(yanit), flush=True)
    """
)


@pytest.fixture()
def sahte_komut(tmp_path):
    betik = tmp_path / "sahte_motor.py"
    betik.write_text(SAHTE_SUNUCU, encoding="utf-8")
    return [sys.executable, str(betik)]


def test_havuz_sureci_yeniden_kullanir(sahte_komut, tmp_path) -> None:
    havuz = MotorHavuzu()
    try:
        bir = havuz.oku("sahte", sahte_komut, None, tmp_path / "a.png", 10)
        iki = havuz.oku("sahte", sahte_komut, None, tmp_path / "b.png", 10)
    finally:
        havuz.kapat()
    assert bir["pid"] == iki["pid"]  # aynı süreç: model yeniden yüklenmedi
    assert iki["sayac"] == 2
    assert bir["blocks"][0]["text"] == "mitokondri"


def test_havuz_zaman_asiminda_sureci_oldurur(sahte_komut, tmp_path) -> None:
    havuz = MotorHavuzu()
    try:
        with pytest.raises(HavuzHatasi):
            havuz.oku("sahte", sahte_komut, None, tmp_path / "yavas.png", 0.3)
        # Havuz düşen süreci temizledi; sonraki istek taze süreçle çalışır.
        yeni = havuz.oku("sahte", sahte_komut, None, tmp_path / "a.png", 10)
        assert yeni["sayac"] == 1
    finally:
        havuz.kapat()


def test_havuz_cokmede_hata_yukseltir(sahte_komut, tmp_path) -> None:
    havuz = MotorHavuzu()
    try:
        with pytest.raises(HavuzHatasi):
            havuz.oku("sahte", sahte_komut, None, tmp_path / "cok.png", 10)
    finally:
        havuz.kapat()


def test_havuz_azami_istekte_tazeler(sahte_komut, tmp_path) -> None:
    havuz = MotorHavuzu(azami_istek=2)
    try:
        bir = havuz.oku("sahte", sahte_komut, None, tmp_path / "a.png", 10)
        havuz.oku("sahte", sahte_komut, None, tmp_path / "b.png", 10)
        uc = havuz.oku("sahte", sahte_komut, None, tmp_path / "c.png", 10)
    finally:
        havuz.kapat()
    assert bir["pid"] != uc["pid"]  # tazeleme yeni süreç başlattı
    assert uc["sayac"] == 1


def test_kapat_zombi_birakmaz(sahte_komut, tmp_path) -> None:
    havuz = MotorHavuzu()
    havuz.oku("sahte", sahte_komut, None, tmp_path / "a.png", 10)
    surec = havuz._motorlar["sahte"].surec
    havuz.kapat()
    assert surec.poll() is not None
    assert not havuz._motorlar


def test_devre_kesici_ardisik_hatada_motoru_atlar(monkeypatch, tmp_path) -> None:
    from sinav_okur import ocr

    ocr.devre_kesiciyi_sifirla()
    monkeypatch.setattr(ocr, "_motor_python", lambda motor: Path(sys.executable))
    cagri_sayaci = {"n": 0}

    def patlayan_run(*args, **kwargs):
        cagri_sayaci["n"] += 1
        raise subprocess.CalledProcessError(-9, args[0])

    monkeypatch.setattr(ocr.subprocess, "run", patlayan_run)
    gorsel = tmp_path / "sayfa.png"
    gorsel.write_bytes(b"x")
    ilk = ocr._alt_surec_ocr("paddle", gorsel, 5)
    ikinci = ocr._alt_surec_ocr("paddle", gorsel, 5)
    ucuncu = ocr._alt_surec_ocr("paddle", gorsel, 5)
    assert ilk.hata and ikinci.hata
    assert "devre dışı" in ucuncu.hata
    assert cagri_sayaci["n"] == 2  # üçüncü çağrı alt sürece hiç gitmedi
    ocr.devre_kesiciyi_sifirla()


def test_devre_kesici_sogumadan_sonra_yari_acik(monkeypatch, tmp_path) -> None:
    """Açık devre soğuma süresi geçince tek deneme hakkı verir (yarı-açık)."""
    from sinav_okur import ocr

    ocr.devre_kesiciyi_sifirla()
    monkeypatch.setattr(ocr, "_motor_python", lambda motor: Path(sys.executable))
    cagri_sayaci = {"n": 0}

    def patlayan_run(*args, **kwargs):
        cagri_sayaci["n"] += 1
        raise subprocess.CalledProcessError(-9, args[0])

    monkeypatch.setattr(ocr.subprocess, "run", patlayan_run)
    gorsel = tmp_path / "sayfa.png"
    gorsel.write_bytes(b"x")
    ocr._alt_surec_ocr("surya", gorsel, 5)
    ocr._alt_surec_ocr("surya", gorsel, 5)
    assert "devre dışı" in ocr._alt_surec_ocr("surya", gorsel, 5).hata
    # Soğuma süresi geçmiş gibi son hata zamanını geri al: bir deneme verilir.
    with ocr._DEVRE_KILIT:
        ocr._son_hata_zamani["surya"] -= ocr.DEVRE_SOGUMA_SN + 1
    yari_acik = ocr._alt_surec_ocr("surya", gorsel, 5)
    assert "devre dışı" not in yari_acik.hata  # gerçek deneme yapıldı
    assert cagri_sayaci["n"] == 3
    # Deneme yine çöktü: devre yeniden açık.
    assert "devre dışı" in ocr._alt_surec_ocr("surya", gorsel, 5).hata
    ocr.devre_kesiciyi_sifirla()


def test_devre_kesici_basari_sayaci_sifirlar(monkeypatch, tmp_path) -> None:
    from sinav_okur import ocr

    ocr.devre_kesiciyi_sifirla()
    monkeypatch.setattr(ocr, "_motor_python", lambda motor: Path(sys.executable))
    durum = {"patla": True}

    def kosullu_run(*args, **kwargs):
        if durum["patla"]:
            raise subprocess.TimeoutExpired(args[0], 5)
        class Sonuc:
            stdout = json.dumps({"blocks": []})
        return Sonuc()

    monkeypatch.setattr(ocr.subprocess, "run", kosullu_run)
    gorsel = tmp_path / "sayfa.png"
    gorsel.write_bytes(b"x")
    ocr._alt_surec_ocr("easyocr", gorsel, 5)  # 1. hata
    durum["patla"] = False
    basarili = ocr._alt_surec_ocr("easyocr", gorsel, 5)  # başarı → sayaç sıfır
    assert not basarili.hata
    durum["patla"] = True
    ocr._alt_surec_ocr("easyocr", gorsel, 5)  # yeniden 1. hata
    hala_deneniyor = ocr._alt_surec_ocr("easyocr", gorsel, 5)  # 2. hata
    assert "devre dışı" not in (hala_deneniyor.hata or "")
    ocr.devre_kesiciyi_sifirla()
