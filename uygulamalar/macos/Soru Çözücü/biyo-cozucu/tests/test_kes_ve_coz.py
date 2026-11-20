"""Dayanikli Kes ve Coz backend sozlesmesi."""

from __future__ import annotations

import asyncio
import base64
import io
import json
import signal
import subprocess
import sys
import time
import zipfile
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest

pytest.importorskip("fastapi")

from fastapi import FastAPI, UploadFile
from fastapi.testclient import TestClient

from biyo_cozucu.cozucu import Ayarlar
from biyo_cozucu.depo import Depo
from biyo_cozucu.modeller import Cozum
from biyo_cozucu.motor.temel import SahteGorselMotor
from biyo_cozucu.webapp import uygulama_kur
from biyo_cozucu.webapp.durum import Uygulama
from biyo_cozucu.webapp.kes_ve_coz import (
    IS_TERMINAL,
    PAKET_SURUMU,
    KesVeCozServisi,
    PaketSorusu,
    _cozum_girdisi_imzalari,
    _model_gorseli_gerekli_mi,
    _referansi_dogrula,
    _surec_grubuna_sinyal,
    varsayilan_paketleyici_komutu,
    yonlendirici,
)

_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def test_referans_secenek_yokken_de_yalniz_a_e_harfi_olabilir():
    assert _referansi_dogrula("c", {}) == ("C", False)
    assert _referansi_dogrula("c", {"B": "Grafik", "D": "Tablo"}) == (
        "C",
        True,
    )
    assert _referansi_dogrula("GIZLI_REFERANS_CEVAP", {}) == ("", True)


def test_model_gorseli_yalniz_gorsel_bilgi_gerektiginde_kullanilir():
    duz = PaketSorusu(
        "duz",
        1,
        "Kloroplast organelinde ışık enerjisinin kimyasal enerjiye "
        "dönüştürüldüğü biyolojik olay aşağıdakilerden hangisidir?",
        {"A": "Solunum", "B": "Fotosentez"},
        Path("soru.png"),
    )
    soyagaci = PaketSorusu(
        "soyagaci",
        2,
        "Aşağıdaki soyağacında gösterilen hastalık hangi kalıtım modeliyle "
        "uyumludur?",
        {"A": "Otozomal çekinik", "B": "Otozomal baskın"},
        Path("soru.png"),
    )
    assert _model_gorseli_gerekli_mi(duz) is False
    assert _model_gorseli_gerekli_mi(soyagaci) is True


def _paketleyici_yaz(tmp_path: Path) -> Path:
    """Gercek subprocess sinirini kullanan kucuk, cevrimdisi paketleyici."""
    yol = tmp_path / "sahte_paketleyici.py"
    yol.write_text(
        """
import json
import sys
import time
import zipfile

CIKTI, MOD = sys.argv[1], sys.argv[2]
PNG = bytes.fromhex(sys.argv[3])
if MOD == "yavas-v1":
    with open(CIKTI + ".calls", "a", encoding="utf-8") as sayac:
        sayac.write("cagri\\n")
    time.sleep(0.6)
    MOD = "v1"
if MOD == "bekle":
    time.sleep(30)
    raise SystemExit(0)
with zipfile.ZipFile(CIKTI, "w", zipfile.ZIP_DEFLATED) as paket:
    if MOD == "zip-slip":
        paket.writestr("../disari.txt", b"tasamaz")
        raise SystemExit(0)
    paket.writestr("images/soru-1.png", PNG)
    paket.writestr("images/soru-2.png", PNG)
    sorular = [
        {
            "external_id": "soru-1",
            "text": "Asagidaki sekilde gosterilen mitokondrinin temel gorevi hangisidir?",
            "choices": {"A": "Protein", "B": "ATP", "C": "DNA"},
            "image": "images/soru-1.png",
            "source_document": "biyoloji-test.pdf",
            "source_page": 3,
            "source_box": [10, 20, 300, 180],
            "source_parts": [{"page": 3, "box": [10, 20, 300, 180]}],
            "cutter_version": "test-v1",
            "confidence": 0.96,
            "quality_status": "automatic",
            "review_required": False,
            "warnings": [],
            "reference_answer": "B",
        },
        {
            "external_id": "soru-2",
            "text": "Kloroplast organelinde isik enerjisinin kimyasal enerjiye donusturuldugu hangi olay gerceklesir?",
            "choices": {"A": "Solunum", "B": "Fotosentez", "C": "Bosaltim"},
            "image": "../disari.png" if MOD == "kotu-gorsel" else "images/soru-2.png",
            "quality_status": "automatic",
            "review_required": False,
            "warnings": ["Kesim kenari belirsiz."],
            "reference_answer": "GIZLI_REFERANS_CEVAP",
        },
    ]
    manifest = {
        "schema_version": "kes-ve-coz-question-package-v1",
        "source_app": "Soru Kesici",
        "source_version": "test-v1",
        "answer_policy": {"withheld_from_model": ["reference_answer"]},
        "questions": sorular,
    }
    if MOD == "yanlis-kaynak":
        manifest["source_app"] = "Bilinmeyen Uretici"
    if MOD == "eksik-cevap-politikasi":
        manifest.pop("answer_policy")
    paket.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
""",
        encoding="utf-8",
    )
    return yol


def _komut(
    betik: Path, mod: str
) -> Callable[[list[Path], Path], tuple[list[str], Path]]:
    def kur(girdiler: list[Path], cikti: Path) -> tuple[list[str], Path]:
        assert len(girdiler) == 1
        return [sys.executable, str(betik), str(cikti), mod, _PNG.hex()], betik.parent

    return kur


def _motorlu_durum(kok: Path) -> tuple[Uygulama, SahteGorselMotor]:
    motor = SahteGorselMotor(
        json.dumps(
            {
                "adimlar": ["Organellerin gorevi belirlenir.", "Secenekler elenir."],
                "cevap": "B",
                "guven": 0.93,
                "uyari": "",
            },
            ensure_ascii=False,
        )
    )
    durum = Uygulama(
        kok=kok,
        motor_turu="sahte",
        gommesiz=True,
        ayarlar=Ayarlar(
            ornek_sayisi=0,
            onbellek_aktif=False,
            inceleme_esigi=0.0,
            kanitsiz_ceza=0.0,
            kalitim_araci=False,
        ),
    )
    durum._motor = motor
    return durum, motor


@contextmanager
def _istemci(
    tmp_path: Path,
    *,
    mod: str = "v1",
    azami_yukleme_bayt: int | None = None,
    cozucu_fabrikasi: Callable[[], object] | None = None,
) -> Iterator[tuple[TestClient, KesVeCozServisi, SahteGorselMotor]]:
    betik = _paketleyici_yaz(tmp_path)
    durum, motor = _motorlu_durum(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        cozucu_fabrikasi or durum.cozucu,
        komut_kurucu=_komut(betik, mod),
        azami_yukleme_bayt=azami_yukleme_bayt or 400 * 1024 * 1024,
        baslangicta_kurtar=False,
    )
    uygulama = FastAPI()
    uygulama.include_router(yonlendirici(durum, servis=servis))
    try:
        with TestClient(uygulama) as istemci:
            yield istemci, servis, motor
    finally:
        servis.kapat()


def _terminal_bekle(
    durum_getir: Callable[[], dict], *, sure: float = 8.0
) -> dict:
    bitis = time.monotonic() + sure
    son: dict = {}
    while time.monotonic() < bitis:
        son = durum_getir()
        if son.get("durum") in IS_TERMINAL:
            return son
        time.sleep(0.03)
    pytest.fail(f"Is terminal duruma gelmedi: {son}")


def test_v1_paket_subprocess_ile_kesilir_cozulur_ve_referans_modele_sizmaz(
    tmp_path: Path,
):
    with _istemci(tmp_path) as (istemci, servis, motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"sahte-pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        assert yanit.status_code == 202
        is_id = yanit.json()["id"]
        sonuc = _terminal_bekle(
            lambda: istemci.get(f"/kes-ve-coz/api/is/{is_id}").json()
        )

        assert sonuc["durum"] == "tamamlandı"
        assert sonuc["toplam"] == sonuc["kesilen"] == sonuc["cozulen"] == 2
        assert sonuc["inceleme"] == 1
        assert [s["durum"] for s in sonuc["sorular"]] == [
            "tamamlandı",
            "inceleme",
        ]
        assert sonuc["sorular"][0]["referansla_eslesiyor"] is True
        assert sonuc["sorular"][1]["referansla_eslesiyor"] is None
        assert [soru["referans_var"] for soru in sonuc["sorular"]] == [True, False]
        assert [soru["kaynak_anahtar_cevabi"] for soru in sonuc["sorular"]] == [
            "",
            "",
        ]
        assert all("referans_cevap" not in soru for soru in sonuc["sorular"])
        assert "GIZLI_REFERANS_CEVAP" not in json.dumps(sonuc, ensure_ascii=False)
        ikinci_soru = servis.depo.soru_getir(is_id, 2)
        assert ikinci_soru is not None
        assert ikinci_soru["referans_cevap"] == ""
        assert sonuc["sorular"][0]["provenance"]["source_page"] == 3
        assert sonuc["sorular"][0]["provenance"]["source_parts"]
        assert "GIZLI_REFERANS_CEVAP" not in json.dumps(
            motor.cagrilar, ensure_ascii=False
        )
        # Şekil gerektiren ilk soru VLM'ye, tam çıkarılmış düz metin olan
        # ikinci soru metin motoruna gider. Kırpımların ikisi de arayüzde kalır.
        assert len(motor.gorseller) == 1
        assert len(motor.cagrilar) == 2

        gorsel = istemci.get(sonuc["sorular"][0]["gorsel_url"])
        assert gorsel.status_code == 200
        assert gorsel.headers["content-type"].startswith("image/png")
        assert gorsel.headers["x-content-type-options"] == "nosniff"
        assert (tmp_path / "kes_ve_coz" / "isler.db").is_file()
        assert (tmp_path / "biyo.db").is_file()
        assert Path(servis.depo.yol) != tmp_path / "biyo.db"
        is_koku = tmp_path / "kes_ve_coz"
        is_dizini = is_koku / "isler" / is_id
        girdi = next((is_dizini / "girdi").iterdir())
        assert is_koku.stat().st_mode & 0o777 == 0o700
        assert is_dizini.stat().st_mode & 0o777 == 0o700
        assert girdi.stat().st_mode & 0o777 == 0o600
        ana_depo = Depo(tmp_path / "biyo.db")
        try:
            ikinci_kayit = next(
                s for s in ana_depo.cozumler() if "Kloroplast" in s["soru"]
            )
            assert ikinci_kayit["incele"] == 1
            ikinci_cozum = json.loads(ikinci_kayit["cozum_json"])
            assert any("şıklarla uyumlu değil" in u for u in ikinci_cozum["uyarilar"])
        finally:
            ana_depo.kapat()
        normalize = json.loads(
            (
                tmp_path
                / "kes_ve_coz"
                / "isler"
                / is_id
                / "dogrulanmis-manifest.v1.json"
            ).read_text(encoding="utf-8")
        )
        assert normalize["schema_version"] == PAKET_SURUMU
        assert normalize["answer_policy"]["withheld_from_model"] == [
            "reference_answer"
        ]


class _AnahtarUyusmazligindaOylayanCozucu:
    def __init__(self):
        self.ayarlar = Ayarlar(deneme_sayisi=3)
        self.cagrilar: list[tuple[int, bool, str]] = []

    def coz(self, soru: str, **_ayarlar) -> Cozum:
        deneme = self.ayarlar.deneme_sayisi
        onbellek = self.ayarlar.onbellek_aktif
        self.cagrilar.append((deneme, onbellek, soru))
        # İlk soruda tek geçiş yanılır; üçlü oylama doğru B'ye ulaşır. İkinci
        # sorunun yapay gizli anahtarı hiçbir geçişte modele görünmemelidir.
        cevap = (
            "A"
            if onbellek and "mitokondri" in soru.lower()
            else "B"
        )
        return Cozum(
            soru=soru,
            adimlar=["Bağımsız çözüm."],
            cevap=cevap,
            guven=0.8,
        )

    def cozumleri_oyla(self, _soru: str, adaylar: list[Cozum]) -> Cozum:
        return max(adaylar, key=lambda aday: sum(a.cevap == aday.cevap for a in adaylar))


def test_anahtar_uyusmazligi_degeri_sizdirmadan_oylamaya_yukseltilir(
    tmp_path: Path,
):
    cozucu = _AnahtarUyusmazligindaOylayanCozucu()
    with _istemci(
        tmp_path, cozucu_fabrikasi=lambda: cozucu
    ) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"sahte-pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        sonuc = _terminal_bekle(
            lambda: istemci.get(
                f"/kes-ve-coz/api/is/{yanit.json()['id']}"
            ).json()
        )

    assert sonuc["sorular"][0]["referansla_eslesiyor"] is True
    ilk_soru = cozucu.cagrilar[0][2]
    assert cozucu.cagrilar[:3] == [
        (1, True, ilk_soru),
        (1, False, ilk_soru),
        (1, False, ilk_soru),
    ]
    assert [deneme for deneme, _onbellek, _soru in cozucu.cagrilar] == [1, 1, 1, 3]
    assert all(
        "GIZLI_REFERANS_CEVAP" not in soru
        for _deneme, _onbellek, soru in cozucu.cagrilar
    )
    assert "anahtar modele verilmeden" in " ".join(
        sonuc["sorular"][0]["cozum"]["uyarilar"]
    ).casefold()
    assert sonuc["sorular"][0]["cozum"]["dogrulama"] == {
        "referans_var": True,
        "ilk_cevap": "A",
        "ilk_eslesme": False,
        "hedef_deneme": 3,
        "tamamlanan_deneme": 3,
        "yeniden_denendi": True,
        "retry_hatasi": 0,
        "son_yontem": "model",
    }
    assert cozucu.ayarlar.deneme_sayisi == 3
    assert cozucu.ayarlar.onbellek_aktif is True


def test_uyusmayan_model_cevabinda_kaynak_anahtari_sonucta_gosterilir(
    tmp_path: Path,
):
    class HepYanlisCozucu(_AnahtarUyusmazligindaOylayanCozucu):
        def coz(self, soru: str, **_ayarlar) -> Cozum:
            self.cagrilar.append((self.ayarlar.deneme_sayisi, False, soru))
            return Cozum(soru=soru, adimlar=["Yanlış model açıklaması."], cevap="A")

    cozucu = HepYanlisCozucu()
    with _istemci(tmp_path, cozucu_fabrikasi=lambda: cozucu) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"sahte-pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        sonuc = _terminal_bekle(
            lambda: istemci.get(
                f"/kes-ve-coz/api/is/{yanit.json()['id']}"
            ).json()
        )

    ilk = sonuc["sorular"][0]
    assert ilk["referansla_eslesiyor"] is False
    assert ilk["kaynak_anahtar_cevabi"] == "B"
    assert ilk["cozum"]["cevap"] == "A"
    assert all("B" not in soru for _deneme, _onbellek, soru in cozucu.cagrilar)


class _YenidenDenemesiBozulanCozucu(_AnahtarUyusmazligindaOylayanCozucu):
    def coz(self, soru: str, **ayarlar) -> Cozum:
        if not self.ayarlar.onbellek_aktif:
            self.cagrilar.append((self.ayarlar.deneme_sayisi, False, soru))
            raise RuntimeError("gecici model hatasi")
        return super().coz(soru, **ayarlar)


def test_retry_hatasi_ilk_cozumu_korur_ve_ayarlari_geri_alir(tmp_path: Path):
    cozucu = _YenidenDenemesiBozulanCozucu()
    with _istemci(
        tmp_path, cozucu_fabrikasi=lambda: cozucu
    ) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        sonuc = _terminal_bekle(
            lambda: istemci.get(
                f"/kes-ve-coz/api/is/{yanit.json()['id']}"
            ).json()
        )

    ilk = sonuc["sorular"][0]
    assert sonuc["hata_sayisi"] == 0
    assert ilk["durum"] == "inceleme"
    assert ilk["cozum"]["cevap"] == "A"
    assert ilk["cozum"]["dogrulama"]["retry_hatasi"] == 2
    assert ilk["cozum"]["dogrulama"]["tamamlanan_deneme"] == 1
    assert "ilk bağımsız çözüm korundu" in " ".join(
        ilk["cozum"]["uyarilar"]
    ).casefold()
    assert cozucu.ayarlar.deneme_sayisi == 3
    assert cozucu.ayarlar.onbellek_aktif is True


class _DeterministikCozucu(_AnahtarUyusmazligindaOylayanCozucu):
    def coz(self, soru: str, **_ayarlar) -> Cozum:
        self.cagrilar.append(
            (self.ayarlar.deneme_sayisi, self.ayarlar.onbellek_aktif, soru)
        )
        return Cozum(
            soru=soru,
            adimlar=["Kural sonucu."],
            cevap="A",
            guven=0.9,
            uretim_yontemi="kalitim_araci",
        )


def test_deterministik_yol_oylama_yapmis_gibi_gosterilmez(tmp_path: Path):
    cozucu = _DeterministikCozucu()
    with _istemci(
        tmp_path, cozucu_fabrikasi=lambda: cozucu
    ) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        sonuc = _terminal_bekle(
            lambda: istemci.get(
                f"/kes-ve-coz/api/is/{yanit.json()['id']}"
            ).json()
        )

    ilk = sonuc["sorular"][0]["cozum"]
    assert ilk["dogrulama"]["yeniden_denendi"] is False
    assert "deterministik" in ilk["dogrulama"]["yeniden_deneme_atlandi"]
    assert "oylandı" not in " ".join(ilk["uyarilar"]).casefold()
    # İkinci, geçersiz anahtarlı soru normal anahtarsız yolunda tek fake çağrıdır.
    assert len(cozucu.cagrilar) == 2


def test_zip_slip_ve_manifest_gorsel_yol_gezintisi_reddedilir(tmp_path: Path):
    for mod in ("zip-slip", "kotu-gorsel"):
        kok = tmp_path / mod
        kok.mkdir()
        with _istemci(kok, mod=mod) as (istemci, _servis, _motor):
            yanit = istemci.post(
                "/kes-ve-coz/is",
                files={"dosyalar": ("test.pdf", b"pdf", "application/pdf")},
                headers={"Accept": "application/json"},
            )
            is_id = yanit.json()["id"]
            sonuc = _terminal_bekle(
                lambda is_id=is_id: istemci.get(
                    f"/kes-ve-coz/api/is/{is_id}"
                ).json()
            )
            assert sonuc["durum"] == "hata"
            assert "guvensiz" in sonuc["mesaj"].casefold()
        assert not list(kok.rglob("disari.txt"))
        assert not list(kok.rglob("disari.png"))


@pytest.mark.parametrize(
    ("mod", "beklenen"),
    [
        ("yanlis-kaynak", "guvenilir soru kesici"),
        ("eksik-cevap-politikasi", "modelden saklama sozlesmesini"),
    ],
)
def test_v1_paket_kaynagi_ve_cevap_saklama_sozlesmesi_zorunludur(
    tmp_path: Path, mod: str, beklenen: str
):
    with _istemci(tmp_path, mod=mod) as (istemci, _servis, motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("test.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        is_id = yanit.json()["id"]
        sonuc = _terminal_bekle(
            lambda: istemci.get(f"/kes-ve-coz/api/is/{is_id}").json()
        )

        assert sonuc["durum"] == "hata"
        assert beklenen in sonuc["mesaj"].casefold()
        assert motor.cagrilar == []


def test_subprocess_kesimi_durdurulur_ve_is_terminal_olur(tmp_path: Path):
    with _istemci(tmp_path, mod="bekle") as (istemci, servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("kitap.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        is_id = yanit.json()["id"]
        bitis = time.monotonic() + 3
        while time.monotonic() < bitis and is_id not in servis._surecler:
            time.sleep(0.02)
        assert is_id in servis._surecler

        durdur = istemci.post(f"/kes-ve-coz/api/is/{is_id}/durdur")
        assert durdur.status_code == 200
        sonuc = _terminal_bekle(
            lambda: istemci.get(f"/kes-ve-coz/api/is/{is_id}").json()
        )
        assert sonuc["durum"] == "durduruldu"
        assert is_id not in servis._surecler


def test_yeniden_baslatma_bekleyen_isi_kaldigi_yerden_yurutur(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    durum, _motor = _motorlu_durum(tmp_path)
    ilk = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    yukleme = UploadFile(filename="kitap.pdf", file=io.BytesIO(b"pdf"))
    is_id = asyncio.run(ilk.yukle([yukleme]))
    assert ilk.durum(is_id)["durum"] == "bekliyor"
    ilk.kapat()

    ikinci = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=True,
    )
    try:
        sonuc = _terminal_bekle(lambda: ikinci.durum(is_id))
        assert sonuc["durum"] == "tamamlandı"
        assert sonuc["cozulen"] == 2
    finally:
        ikinci.kapat()


def test_iki_servis_ayni_isi_surecler_arasi_kilitle_yalniz_bir_kez_calistirir(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    durum, _motor = _motorlu_durum(tmp_path)
    ilk = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "yavas-v1"),
        baslangicta_kurtar=False,
    )
    ikinci = None
    try:
        yukleme = UploadFile(filename="kitap.pdf", file=io.BytesIO(b"pdf"))
        is_id = asyncio.run(ilk.yukle([yukleme]))
        kayit = ilk.depo.is_getir(is_id)
        assert kayit is not None
        sayac = Path(str(kayit["arsiv_yolu"]) + ".calls")

        ilk.baslat(is_id)
        bitis = time.monotonic() + 3
        while time.monotonic() < bitis and not sayac.exists():
            time.sleep(0.02)
        assert sayac.exists()

        # Uvicorn reload/ikinci worker gibi ayni veri kokunu acip kurtarma
        # taramasi yapan servis de isi gorur; flock ikinci icrayi engeller.
        ikinci = KesVeCozServisi(
            tmp_path,
            durum.cozucu,
            komut_kurucu=_komut(betik, "yavas-v1"),
            baslangicta_kurtar=True,
        )
        sonuc = _terminal_bekle(lambda: ilk.durum(is_id))
        assert sonuc["durum"] == "tamamlandı"
        assert sayac.read_text(encoding="utf-8").splitlines() == ["cagri"]
    finally:
        if ikinci is not None:
            ikinci.kapat()
        ilk.kapat()


def test_lider_ciksa_da_sinyal_ayni_gruptaki_cocuga_ulasir(tmp_path: Path):
    hazir = tmp_path / "cocuk-hazir"
    sinyal_alindi = tmp_path / "sinyal-alindi"
    cocuk_kodu = """
import signal
import sys
import time
from pathlib import Path

hazir = Path(sys.argv[1])
sinyal_alindi = Path(sys.argv[2])

def durdur(_sinyal, _cerceve):
    sinyal_alindi.write_text("term", encoding="utf-8")
    raise SystemExit(0)

signal.signal(signal.SIGTERM, durdur)
hazir.write_text(str(__import__("os").getpid()), encoding="utf-8")
while True:
    time.sleep(1)
"""
    lider_kodu = """
import subprocess
import sys
import time
from pathlib import Path

subprocess.Popen(
    [sys.executable, "-c", sys.argv[1], sys.argv[2], sys.argv[3]],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
hazir = Path(sys.argv[2])
bitis = time.monotonic() + 3
while time.monotonic() < bitis and not hazir.exists():
    time.sleep(0.02)
raise SystemExit(0 if hazir.exists() else 2)
"""
    lider = subprocess.Popen(  # noqa: S603 - test girdileri sabit ve yerel
        [sys.executable, "-c", lider_kodu, cocuk_kodu, str(hazir), str(sinyal_alindi)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        assert lider.wait(timeout=5) == 0
        assert hazir.exists()
        # Eski uygulama poll()!=None gorup burada erken donuyordu.
        _surec_grubuna_sinyal(lider, signal.SIGTERM)
        bitis = time.monotonic() + 3
        while time.monotonic() < bitis and not sinyal_alindi.exists():
            time.sleep(0.02)
        assert sinyal_alindi.read_text(encoding="utf-8") == "term"
    finally:
        _surec_grubuna_sinyal(lider, signal.SIGKILL)


def test_kesim_sirasinda_uygulama_kapanisi_isi_hata_yapmaz_ve_kurtarir(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    durum, _motor = _motorlu_durum(tmp_path)
    ilk = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "bekle"),
        baslangicta_kurtar=False,
    )
    yukleme = UploadFile(filename="kitap.pdf", file=io.BytesIO(b"pdf"))
    is_id = asyncio.run(ilk.yukle([yukleme]))
    ilk.baslat(is_id)
    bitis = time.monotonic() + 3
    while time.monotonic() < bitis and is_id not in ilk._surecler:
        time.sleep(0.02)
    assert is_id in ilk._surecler
    ilk.kapat()

    ikinci = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=True,
    )
    try:
        sonuc = _terminal_bekle(lambda: ikinci.durum(is_id))
        assert sonuc["durum"] == "tamamlandı"
        assert sonuc["cozulen"] == 2
    finally:
        ikinci.kapat()


class _BirSorudaBozulanCozucu:
    def __init__(self):
        self.cagri = 0

    def coz(self, soru: str, **_ayarlar) -> Cozum:
        self.cagri += 1
        if self.cagri == 2:
            raise RuntimeError("ikinci soru arizasi")
        return Cozum(
            soru=soru,
            adimlar=["Birinci soru cozuldu."],
            cevap="B",
            guven=0.9,
        )


def test_tek_soru_hatasi_isi_kismi_yapar_diger_sonucu_korur(tmp_path: Path):
    arizali = _BirSorudaBozulanCozucu()
    with _istemci(
        tmp_path, cozucu_fabrikasi=lambda: arizali
    ) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("test.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "application/json"},
        )
        is_id = yanit.json()["id"]
        sonuc = _terminal_bekle(
            lambda: istemci.get(f"/kes-ve-coz/api/is/{is_id}").json()
        )
        assert sonuc["durum"] == "kısmi"
        assert sonuc["cozulen"] == 1
        assert sonuc["hata_sayisi"] == 1
        assert [s["durum"] for s in sonuc["sorular"]] == ["tamamlandı", "hata"]


@pytest.mark.parametrize(
    ("files", "sinir", "beklenen"),
    [
        (
            [("dosyalar", ("buyuk.pdf", b"x" * 33, "application/pdf"))],
            32,
            413,
        ),
        (
            [("dosyalar", ("calisiyor.exe", b"x", "application/octet-stream"))],
            None,
            400,
        ),
        (
            [
                ("dosyalar", ("bir.pdf", b"1", "application/pdf")),
                ("dosyalar", ("iki.pdf", b"2", "application/pdf")),
            ],
            None,
            400,
        ),
    ],
)
def test_yukleme_sinirlari_is_olusturmadan_uygulanir(
    tmp_path: Path,
    files: list[tuple[str, tuple[str, bytes, str]]],
    sinir: int | None,
    beklenen: int,
):
    with _istemci(
        tmp_path, azami_yukleme_bayt=sinir
    ) as (istemci, servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files=files,
            headers={"Accept": "application/json"},
        )
        assert yanit.status_code == beklenen
        assert servis.depo.son_isler() == []


def test_javascriptsiz_form_is_kimligine_yonlendirilir(tmp_path: Path):
    with _istemci(tmp_path) as (istemci, _servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("test.pdf", b"pdf", "application/pdf")},
            headers={"Accept": "text/html"},
            follow_redirects=False,
        )
        assert yanit.status_code == 303
        assert yanit.headers["location"].startswith("/kes-ve-coz?is=")


def test_ana_urun_yonlendirmesi_ve_servis_yasam_dongusu(tmp_path: Path):
    uygulama = uygulama_kur(
        kok=tmp_path,
        motor_turu="yok",
        gommesiz=True,
    )
    servis = uygulama.state.kes_ve_coz_servisi

    with TestClient(uygulama, follow_redirects=False) as istemci:
        yanit = istemci.get("/")
        assert yanit.status_code == 303
        assert yanit.headers["location"] == "/merkez"
        assert servis._kapandi is False

    assert servis._kapandi is True


def test_varsayilan_komut_bas_siz_v1_paketleyiciyi_ve_kendi_venvini_secer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    kesici = tmp_path / "soru-kesici"
    yorumlayici = kesici / ".venv" / "bin" / "python"
    yorumlayici.parent.mkdir(parents=True)
    yorumlayici.write_text("", encoding="utf-8")
    (kesici / "soru_kes.py").write_text("", encoding="utf-8")
    paketleyici = kesici / "kes_ve_coz_paketle.py"
    paketleyici.write_text("", encoding="utf-8")
    monkeypatch.setenv("SORU_KESICI_KOK", str(kesici))

    girdi = tmp_path / "kitap.pdf"
    cikti = tmp_path / "paket.zip"
    komut, cwd = varsayilan_paketleyici_komutu([girdi], cikti)

    assert komut[:3] == [str(yorumlayici), str(paketleyici), str(girdi)]
    assert komut[3:5] == ["--output", str(cikti)]
    assert "--max-input-mb" in komut
    assert cwd == kesici.resolve()


def test_kurtarmada_ayni_siraya_farkli_soru_gelirse_eski_cozum_tasinmaz(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "00000000-0000-0000-0000-000000000001"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        servis.depo.soru_ekle(
            is_id, PaketSorusu(external_id="eski", sira=1, metin="Eski soru")
        )
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )

        servis.depo.soru_ekle(
            is_id, PaketSorusu(external_id="yeni", sira=1, metin="Yeni soru")
        )
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["external_id"] == "yeni"
        assert satir["durum"] == "bekliyor"
        assert satir["cozum_json"] == ""
        assert satir["referans_eslesmesi"] is None
    finally:
        servis.kapat()


@pytest.mark.parametrize(
    "degisen",
    [
        "metin",
        "secenekler",
        "gorsel",
        "referans",
        "referans_bos",
        "inceleme",
        "uyarilar",
    ],
)
def test_kurtarmada_ayni_kimligin_cozum_girdisi_degismisse_eski_cozum_tasinmaz(
    tmp_path: Path, degisen: str
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = f"degisen-{degisen}"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        ilk = PaketSorusu(
            external_id="ayni-kimlik",
            sira=1,
            metin="Eski soru",
            secenekler={"A": "Bir", "B": "Iki"},
            gorsel_yolu=tmp_path / "eski.png",
            referans_cevap="A",
        )
        servis.depo.soru_ekle(is_id, ilk)
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )
        yeni = PaketSorusu(
            external_id=ilk.external_id,
            sira=ilk.sira,
            metin="Yeni soru" if degisen == "metin" else ilk.metin,
            secenekler=(
                {"A": "Bir", "B": "Uc"}
                if degisen == "secenekler"
                else ilk.secenekler
            ),
            gorsel_yolu=(
                tmp_path / "yeni.png" if degisen == "gorsel" else ilk.gorsel_yolu
            ),
            referans_cevap=(
                "B"
                if degisen == "referans"
                else ""
                if degisen == "referans_bos"
                else ilk.referans_cevap
            ),
            inceleme_gerekli=degisen == "inceleme",
            uyarilar=["Yeni paket uyarısı"] if degisen == "uyarilar" else ilk.uyarilar,
        )

        servis.depo.soru_ekle(is_id, yeni)
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["durum"] == "bekliyor"
        assert satir["cozum_json"] == ""
        assert satir["referans_eslesmesi"] is None
    finally:
        servis.kapat()


def test_kurtarmada_ayni_cozum_imzasi_sozluk_sirasindan_etkilenmez(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "ayni-cozum-imzasi"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        ilk = PaketSorusu(
            external_id="ayni-kimlik",
            sira=1,
            metin="Ayni soru",
            secenekler={"A": "Bir", "B": "Iki"},
            referans_cevap="A",
            uyarilar=["İkinci uyarı", "Birinci uyarı", "Birinci uyarı"],
        )
        servis.depo.soru_ekle(is_id, ilk)
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )
        ayni = PaketSorusu(
            external_id=ilk.external_id,
            sira=ilk.sira,
            metin=ilk.metin,
            secenekler={"B": "Iki", "A": "Bir"},
            referans_cevap=ilk.referans_cevap,
            uyarilar=["Birinci uyarı", "İkinci uyarı"],
        )

        servis.depo.soru_ekle(is_id, ayni)
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["durum"] == "tamamlandı"
        assert satir["cozum_json"] == '{"cevap":"A"}'
        assert satir["referans_eslesmesi"] == 1
        assert satir["cozum_girdisi_imzasi"].startswith("v2:")
    finally:
        servis.kapat()


@pytest.mark.parametrize("durum", ["ayni", "degisen-uyari", "bozuk-provenance"])
def test_v1_fingerprint_yalniz_ayni_uyariyla_v2ye_kayipsiz_yukselir(
    tmp_path: Path, durum: str
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = f"v1-gecis-{durum}"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        ilk = PaketSorusu(
            external_id="soru",
            sira=1,
            metin="Ayni soru",
            referans_cevap="A",
            uyarilar=["Kesim uyarısı"],
        )
        _v2_imza, v1_imza = _cozum_girdisi_imzalari(ilk)
        servis.depo.soru_ekle(is_id, ilk)
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )
        with servis.depo._kilit, servis.depo._db:
            servis.depo._db.execute(
                "UPDATE sorular SET cozum_girdisi_imzasi=? WHERE is_id=? AND sira=1",
                (v1_imza, is_id),
            )
            if durum == "bozuk-provenance":
                servis.depo._db.execute(
                    "UPDATE sorular SET provenance_json='{' WHERE is_id=? AND sira=1",
                    (is_id,),
                )

        yeni = PaketSorusu(
            external_id=ilk.external_id,
            sira=ilk.sira,
            metin=ilk.metin,
            referans_cevap=ilk.referans_cevap,
            uyarilar=(
                ["Yeni uyarı"] if durum == "degisen-uyari" else ilk.uyarilar
            ),
        )
        servis.depo.soru_ekle(is_id, yeni)
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        if durum == "ayni":
            assert satir["durum"] == "tamamlandı"
            assert satir["cozum_json"] == '{"cevap":"A"}'
            assert satir["referans_eslesmesi"] == 1
            assert satir["cozum_girdisi_imzasi"].startswith("v2:")
        else:
            assert satir["durum"] == "bekliyor"
            assert satir["cozum_json"] == ""
            assert satir["referans_eslesmesi"] is None
    finally:
        servis.kapat()


def test_imzasiz_eski_terminal_cozum_acilista_incelemeye_alinir(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    ilk = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    is_id = "imzasiz-eski-cozum"
    ilk.depo.is_ekle(
        is_id,
        girdiler=[],
        girdi_imzasi="imza",
        arsiv_yolu=tmp_path / "paket.zip",
    )
    ilk.depo.soru_ekle(
        is_id,
        PaketSorusu(
            external_id="soru",
            sira=1,
            metin="Eski soru",
            referans_cevap="A",
        ),
    )
    ilk.depo.soru_guncelle(
        is_id,
        1,
        durum="tamamlandı",
        cozum_json='{"cevap":"A","uyarilar":[]}',
        referans_eslesmesi=1,
    )
    ilk.depo.is_guncelle(
        is_id,
        durum="tamamlandı",
        asama="bitti",
        ilerleme=100,
        toplam=1,
        kesilen=1,
        cozulen=1,
        inceleme=0,
    )
    with ilk.depo._kilit, ilk.depo._db:
        ilk.depo._db.execute(
            "UPDATE sorular SET cozum_girdisi_imzasi='' WHERE is_id=?", (is_id,)
        )
    ilk.kapat()

    ikinci = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        satir = ikinci.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["durum"] == "tamamlandı"
        assert satir["inceleme_gerekli"] == 1
        assert satir["referans_eslesmesi"] is None
        sonuc = ikinci.durum(is_id)
        assert sonuc["inceleme"] == 1
        assert sonuc["sorular"][0]["incele"] is True
        assert any(
            "doğrulanmış çözüm girdisi imzası yok" in uyari
            for uyari in sonuc["sorular"][0]["uyarilar"]
        )
    finally:
        ikinci.kapat()


def test_kurtarmada_ayni_gorsel_yolunun_baytlari_degismisse_cozum_tasinmaz(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "degisen-gorsel-bayti"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        gorsel = tmp_path / "soru.png"
        gorsel.write_bytes(b"ilk-gorsel")
        soru = PaketSorusu(
            external_id="ayni-kimlik",
            sira=1,
            metin="Ayni soru",
            gorsel_yolu=gorsel,
            referans_cevap="A",
        )
        servis.depo.soru_ekle(is_id, soru)
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )
        gorsel.write_bytes(b"farkli-gorsel")

        servis.depo.soru_ekle(is_id, soru)
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["durum"] == "bekliyor"
        assert satir["cozum_json"] == ""
        assert satir["referans_eslesmesi"] is None
    finally:
        servis.kapat()


def test_bos_referans_eski_eslesme_bayragini_koruyamaz(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "bos-referans"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        soru = PaketSorusu(external_id="soru", sira=1, metin="Ayni soru")
        servis.depo.soru_ekle(is_id, soru)
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=0,
        )

        servis.depo.soru_ekle(is_id, soru)
        satir = servis.depo.soru_getir(is_id, 1)
        assert satir is not None
        assert satir["durum"] == "tamamlandı"
        assert satir["cozum_json"] == '{"cevap":"A"}'
        assert satir["referans_eslesmesi"] is None
    finally:
        servis.kapat()


def test_manifest_esitleme_artik_olmayan_soruyu_sayac_ve_apiden_kaldirir(
    tmp_path: Path,
):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "kisalan-manifest"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        kalan = PaketSorusu(external_id="kalan", sira=1, metin="Kalan soru")
        eski = PaketSorusu(external_id="eski", sira=2, metin="Silinen soru")
        servis.depo.sorulari_esitle(is_id, [kalan, eski])
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
        )
        servis.depo.soru_guncelle(
            is_id,
            2,
            durum="inceleme",
            cozum_json='{"cevap":"B","incele":true}',
            referans_eslesmesi=0,
        )

        servis.depo.sorulari_esitle(is_id, [kalan])

        assert [satir["external_id"] for satir in servis.depo.sorular(is_id)] == [
            "kalan"
        ]
        assert servis.depo.soru_sayaclari(is_id) == {
            "toplam": 1,
            "cozulmus": 1,
            "inceleme": 0,
            "hata": 0,
            "atlanmis": 0,
        }
        assert [soru["id"] for soru in servis.durum(is_id)["sorular"]] == ["kalan"]
    finally:
        servis.kapat()


def test_okunamayan_gorsel_eski_terminal_cozumu_koruyamaz(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "okunamayan-gorsel"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        soru = PaketSorusu(
            external_id="soru",
            sira=1,
            metin="Ayni soru",
            gorsel_yolu=tmp_path / "bulunamayan.png",
            referans_cevap="A",
        )
        servis.depo.soru_ekle(is_id, soru)
        onceki = servis.depo.soru_getir(is_id, 1)
        assert onceki is not None
        servis.depo.soru_guncelle(
            is_id,
            1,
            durum="tamamlandı",
            cozum_json='{"cevap":"A"}',
            referans_eslesmesi=1,
        )

        servis.depo.soru_ekle(is_id, soru)

        sonraki = servis.depo.soru_getir(is_id, 1)
        assert sonraki is not None
        assert sonraki["cozum_girdisi_imzasi"] != onceki["cozum_girdisi_imzasi"]
        assert sonraki["durum"] == "bekliyor"
        assert sonraki["cozum_json"] == ""
        assert sonraki["referans_eslesmesi"] is None
    finally:
        servis.kapat()


def test_crash_oncesi_durdurma_istegi_acilista_terminale_tasinir(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    durum, _motor = _motorlu_durum(tmp_path)
    ilk = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    is_id = "00000000-0000-0000-0000-000000000002"
    ilk.depo.is_ekle(
        is_id, girdiler=[], girdi_imzasi="imza", arsiv_yolu=tmp_path / "paket.zip"
    )
    ilk.depo.soru_ekle(
        is_id, PaketSorusu(external_id="tamam", sira=1, metin="Cozulen")
    )
    ilk.depo.soru_ekle(
        is_id, PaketSorusu(external_id="bekleyen", sira=2, metin="Bekleyen")
    )
    ilk.depo.soru_guncelle(is_id, 1, durum="tamamlandı", cozum_json="{}")
    assert ilk.depo.durdur_iste(is_id)
    ilk.kapat()

    ikinci = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=True,
    )
    try:
        sonuc = ikinci.durum(is_id)
        assert sonuc["durum"] == "durduruldu"
        assert [s["durum"] for s in sonuc["sorular"]] == [
            "tamamlandı",
            "atlanmış",
        ]
        assert sonuc["cozulen"] == 1
    finally:
        ikinci.kapat()


def test_fatal_is_hatasi_gecici_soru_durumlarini_terminal_yapar(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        lambda: _BirSorudaBozulanCozucu(),
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        is_id = "00000000-0000-0000-0000-000000000003"
        servis.depo.is_ekle(
            is_id,
            girdiler=[],
            girdi_imzasi="imza",
            arsiv_yolu=tmp_path / "paket.zip",
        )
        servis.depo.soru_ekle(
            is_id, PaketSorusu(external_id="aktif", sira=1, metin="Aktif")
        )
        servis.depo.soru_ekle(
            is_id,
            PaketSorusu(
                external_id="bekleyen",
                sira=2,
                metin="Bekleyen",
                inceleme_gerekli=True,
            ),
        )
        servis.depo.soru_guncelle(is_id, 1, durum="çözülüyor")

        servis._hata_ile_bitir(is_id, RuntimeError("fatal is hatasi"))
        sonuc = servis.durum(is_id)
        assert sonuc["durum"] == "hata"
        assert [s["durum"] for s in sonuc["sorular"]] == ["hata", "atlanmış"]
        assert sonuc["sorular"][0]["hata"] == "fatal is hatasi"
        assert sonuc["inceleme"] == 1
        assert sonuc["sorular"][1]["review_required"] is True
    finally:
        servis.kapat()


def test_kuyruktaki_girdi_degistirilirse_subprocess_baslatilmaz(tmp_path: Path):
    betik = _paketleyici_yaz(tmp_path)
    durum, _motor = _motorlu_durum(tmp_path)
    servis = KesVeCozServisi(
        tmp_path,
        durum.cozucu,
        komut_kurucu=_komut(betik, "v1"),
        baslangicta_kurtar=False,
    )
    try:
        yukleme = UploadFile(filename="kitap.pdf", file=io.BytesIO(b"orijinal"))
        is_id = asyncio.run(servis.yukle([yukleme]))
        kayit = servis.depo.is_getir(is_id)
        assert kayit is not None
        girdi = Path(json.loads(kayit["girdiler_json"])[0]["yol"])
        girdi.write_bytes(b"degistirildi")

        servis.baslat(is_id)
        sonuc = _terminal_bekle(lambda: servis.durum(is_id))
        assert sonuc["durum"] == "hata"
        assert "degismis veya bozulmus" in sonuc["mesaj"]
        assert not (girdi.parents[1] / "soru-kesici.log").exists()
    finally:
        servis.kapat()


def _v1_arsiv_baytlari() -> bytes:
    """Soru Kesici'nin urettigi bicimde kucuk bir v1 paketi kurar."""
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("images/hazir-1.png", _PNG)
        paket.writestr(
            "kes-ve-coz-manifest.json",
            json.dumps(
                {
                    "schema_version": PAKET_SURUMU,
                    "source_app": "Soru Kesici",
                    "source_version": "3.4",
                    "answer_policy": {"withheld_from_model": ["reference_answer"]},
                    "questions": [
                        {
                            "external_id": "hazir-1",
                            "text": "Mitokondrinin temel gorevi asagidakilerden hangisidir?",
                            "choices": {"A": "Protein", "B": "ATP"},
                            "image": "images/hazir-1.png",
                            "quality_status": "automatic",
                            "review_required": False,
                            "warnings": [],
                            "reference_answer": "B",
                        }
                    ],
                },
                ensure_ascii=False,
            ),
        )
    return tampon.getvalue()


def _legacy_arsiv_baytlari() -> bytes:
    """Eski Soru Kesici cikti bicimi: soru_NN.png + sorular.json."""
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("soru_01.png", _PNG)
        paket.writestr(
            "sorular.json",
            json.dumps(
                [
                    {
                        "dosya": "soru_01.png",
                        "metin": "Fotosentez hangi organelde gerceklesir?",
                        "siklar": {"A": "Mitokondri", "B": "Kloroplast"},
                        "sayfa": 3,
                        "soru_no": 1,
                        "cevap": "B",
                    }
                ],
                ensure_ascii=False,
            ),
        )
    return tampon.getvalue()


@pytest.mark.parametrize(
    ("ad", "baytlar_uret"),
    [("v1-paket.zip", _v1_arsiv_baytlari), ("legacy-arsiv.zip", _legacy_arsiv_baytlari)],
)
def test_hazir_arsiv_kesici_calistirilmadan_cozulur(
    tmp_path: Path, ad: str, baytlar_uret
):
    # ``bekle`` modundaki paketleyici 30 sn uyur: kesici cagrilsaydi is
    # terminal duruma gelmezdi. Hizli tamamlanmasi kesimin atlandiginin kanitidir.
    with _istemci(tmp_path, mod="bekle") as (istemci, servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": (ad, baytlar_uret(), "application/zip")},
            headers={"Accept": "application/json"},
        )
        assert yanit.status_code == 202
        is_id = yanit.json()["id"]
        sonuc = _terminal_bekle(
            lambda: istemci.get(f"/kes-ve-coz/api/is/{is_id}").json()
        )
        assert sonuc["durum"] == "tamamlandı"
        assert sonuc["toplam"] == 1
        assert sonuc["cozulen"] == 1
        # Kesici alt sureci hic calismadigi icin log dosyasi da olusmaz.
        assert not (servis.is_dizini / is_id / "soru-kesici.log").exists()


def test_alakasiz_zip_is_olusturmadan_reddedilir(tmp_path: Path):
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as paket:
        paket.writestr("tatil/foto.jpg", b"jpeg-degil-ama-onemli-degil")
    with _istemci(tmp_path) as (istemci, servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("tatil.zip", tampon.getvalue(), "application/zip")},
            headers={"Accept": "application/json"},
        )
        assert yanit.status_code == 400
        assert "Soru Kesici paketi degil" in yanit.json()["hata"]
        assert servis.depo.son_isler() == []


def test_bozuk_zip_reddedilir(tmp_path: Path):
    with _istemci(tmp_path) as (istemci, servis, _motor):
        yanit = istemci.post(
            "/kes-ve-coz/is",
            files={"dosyalar": ("bozuk.zip", b"PK bu bir zip degil", "application/zip")},
            headers={"Accept": "application/json"},
        )
        assert yanit.status_code == 400
        assert "gecerli bir zip" in yanit.json()["hata"]
        assert servis.depo.son_isler() == []
