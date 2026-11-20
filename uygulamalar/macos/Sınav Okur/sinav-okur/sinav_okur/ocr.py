"""Yerel Türkçe OCR motorları ve satır düzeyinde topluluk çözümleyicisi.

Motorlar birbirinden yalıtılmış Python ortamlarında çalışabilir. Böylece
PaddleOCR ile PyTorch tabanlı EasyOCR/Surya bağımlılıkları ana uygulamanın
paketlerini değiştirmez. Apple Vision her zaman yerel, hızlı ilk motordur.

TrOCR (microsoft/trocr-base-handwritten) el yazısı uzmanı olarak katılır:
kendi satır algılayıcısı olmadığından öncü motorun (Vision) satır kutularını
kırpıp yeniden okur ve topluluk oylamasına aday olarak girer. İnce ayarlı
Türkçe model ``SINAV_OKUR_TROCR_MODEL`` ortam değişkeniyle verilebilir.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time
import unicodedata
from dataclasses import asdict, dataclass, field
from datetime import datetime
from difflib import SequenceMatcher
from pathlib import Path
from typing import Callable


@dataclass
class OCRBlogu:
    text: str
    confidence: float
    x: float
    y: float
    width: float
    height: float
    motor: str = ""
    alternatives: list[dict] = field(default_factory=list)


@dataclass
class OCRMotorSonucu:
    motor: str
    blocks: list[OCRBlogu] = field(default_factory=list)
    sure_ms: int = 0
    hata: str = ""

    @property
    def basarili(self) -> bool:
        return bool(self.blocks) and not self.hata

    def ozet(self) -> dict:
        return {
            "motor": self.motor,
            "basarili": self.basarili,
            "satir": len(self.blocks),
            "sure_ms": self.sure_ms,
            "hata": self.hata,
            "ortalama_guven": (
                round(sum(b.confidence for b in self.blocks) / len(self.blocks), 3)
                if self.blocks
                else 0.0
            ),
        }


MOTOR_ADLARI = {
    "vision": "Apple Vision",
    "tesseract": "Tesseract Türkçe",
    "easyocr": "EasyOCR Türkçe",
    "paddle": "PaddleOCR PP-OCRv5",
    "surya": "Surya OCR",
    "rapidocr": "RapidOCR",
    "trocr": "TrOCR El Yazısı",
}

MOTOR_AGIRLIKLARI = {
    "vision": 1.00,
    "paddle": 0.98,
    "surya": 0.94,
    "trocr": 0.90,
    "rapidocr": 0.88,  # easyocr (0.86) ile paddle (0.98) arası
    "easyocr": 0.86,
    "tesseract": 0.82,
}


def _proje_koku() -> Path:
    return Path(__file__).resolve().parents[1]


def _motor_python(motor: str) -> Path:
    ozel = os.environ.get(f"SINAV_OKUR_{motor.upper()}_PYTHON")
    if ozel:
        return Path(ozel).expanduser()
    return _proje_koku() / ".ocr-envs" / motor / "bin" / "python"


def motor_durumlari() -> list[dict]:
    """Arayüz için altı motorun çalıştırılabilirlik durumunu döndür."""
    durumlar = []
    for motor in MOTOR_ADLARI:
        if motor == "vision":
            hazir = sys.platform == "darwin" and Path("/usr/bin/xcrun").exists()
            aciklama = "macOS yerel metin tanıma"
        elif motor == "trocr":
            hazir = _trocr_hazir()
            aciklama = (
                "Satır-düzeyi el yazısı tanıma (ana ortam)"
                if hazir
                else "pip install 'sinav-okur[htr]' gerekli"
            )
        else:
            python = _motor_python(motor)
            hazir = python.is_file()
            aciklama = "Yalıtılmış yerel ortam" if hazir else "Henüz kurulmadı"
        durumlar.append(
            {
                "motor": motor,
                "ad": MOTOR_ADLARI[motor],
                "hazir": hazir,
                "aciklama": aciklama,
            }
        )
    return durumlar


def _normal_metin(metin: str) -> str:
    metin = unicodedata.normalize("NFC", metin)
    metin = re.sub(r"\s+", " ", metin).strip()
    return metin


# Devre kesici: art arda bu kadar çökme/zaman aşımından sonra motor bu süreç
# ömrü boyunca (başarı görülene dek) atlanır — 344 sn'lik ölü Paddle koşusu
# gibi kayıpları bir kez öder, tekrar tekrar ödemez. Başarı sayacı sıfırlar.
DEVRE_KESICI_ESIGI = 2
# Açık devre bu süre sonra tek denemelik yarı-açık moda geçer; başarı devreyi
# kapatır, yeni çökme yeniden açar (kalıcı kapanma yerine kendini toparlama).
DEVRE_SOGUMA_SN = 300.0
_DEVRE_KILIT = threading.Lock()
_ardisik_hatalar: dict[str, int] = {}
_son_hata_zamani: dict[str, float] = {}

# Motor başına istek zaman aşımı (sn). Paddle gerçek koşuda 343,7 sn'de
# bellekten öldü; 420 sn'lik cömert bütçe yalnız kaybı büyütüyordu.
MOTOR_ZAMAN_ASIMI = {
    "tesseract": 180, "easyocr": 300, "paddle": 180, "surya": 600, "rapidocr": 180,
}

_HAVUZ = None
_HAVUZ_KILIT = threading.Lock()


# Motor sağlığı oturumlar arası hatırlanır: süreç ömrüyle sınırlı devre
# kesici, her yeniden başlatmada aynı ölü motorun bedelini yeniden ödetiyordu
# (paddle ölçümde sayfa süresinin %76'sını hiç sonuç üretmeden yakıyordu).
SAGLIK_ASGARI_ISTEK = 3
SAGLIK_AZAMI_HATA_ORANI = 0.5
_saglik_yolu_onbellek: Path | None = None


def motor_saglik_yolu() -> Path:
    ozel = os.environ.get("SINAV_OKUR_MOTOR_SAGLIK")
    if ozel:
        return Path(ozel).expanduser()
    return (
        Path(__file__).resolve().parents[1]
        / "sinav_okur_veri"
        / "motor_saglik.json"
    )


def motor_sagligi_oku() -> dict:
    try:
        return json.loads(motor_saglik_yolu().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def motor_sagligi_yaz(veri: dict) -> None:
    yol = motor_saglik_yolu()
    try:
        yol.parent.mkdir(parents=True, exist_ok=True)
        gecici = yol.with_suffix(".yeni")
        gecici.write_text(
            json.dumps(veri, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        gecici.replace(yol)
    except OSError:
        pass  # sağlık kaydı yazılamazsa OCR yine çalışmalı


def _saglik_kaydet(motor: str, basarili: bool) -> None:
    veri = motor_sagligi_oku()
    kayit = veri.setdefault(motor, {"istek": 0, "hata": 0})
    kayit["istek"] = int(kayit.get("istek", 0)) + 1
    if not basarili:
        kayit["hata"] = int(kayit.get("hata", 0)) + 1
        kayit["son_hata"] = datetime.now().isoformat(timespec="seconds")
    motor_sagligi_yaz(veri)


def motor_saglikli_mi(motor: str, saglik: dict | None = None) -> bool:
    """Motor geçmişte sürekli başarısız olduysa varsayılan profillerden düşer."""
    kayit = (saglik if saglik is not None else motor_sagligi_oku()).get(motor)
    if not kayit:
        return True
    istek = int(kayit.get("istek", 0))
    if istek < SAGLIK_ASGARI_ISTEK:
        return True
    return (int(kayit.get("hata", 0)) / istek) <= SAGLIK_AZAMI_HATA_ORANI


def devre_kesiciyi_sifirla(*, saglik_da: bool = False) -> None:
    with _DEVRE_KILIT:
        _ardisik_hatalar.clear()
        _son_hata_zamani.clear()
    if saglik_da:
        motor_sagligi_yaz({})


def _devre_acik(motor: str) -> bool:
    with _DEVRE_KILIT:
        if _ardisik_hatalar.get(motor, 0) < DEVRE_KESICI_ESIGI:
            return False
        gecen = time.monotonic() - _son_hata_zamani.get(motor, 0.0)
        if gecen > DEVRE_SOGUMA_SN:
            # Yarı-açık: bir deneme hakkı — başarısız olursa yeniden açılır.
            _ardisik_hatalar[motor] = DEVRE_KESICI_ESIGI - 1
            return False
        return True


def _devre_kaydet(motor: str, basarili: bool) -> None:
    with _DEVRE_KILIT:
        if basarili:
            _ardisik_hatalar.pop(motor, None)
            _son_hata_zamani.pop(motor, None)
        else:
            _ardisik_hatalar[motor] = _ardisik_hatalar.get(motor, 0) + 1
            _son_hata_zamani[motor] = time.monotonic()
    _saglik_kaydet(motor, basarili)


def _havuz_getir():
    global _HAVUZ
    with _HAVUZ_KILIT:
        if _HAVUZ is None:
            import atexit

            from .ocr_havuz import MotorHavuzu

            _HAVUZ = MotorHavuzu()
            atexit.register(_HAVUZ.kapat)
    return _HAVUZ


def _alt_surec_ocr(motor: str, gorsel: Path, timeout: int) -> OCRMotorSonucu:
    baslangic = time.monotonic()
    python = _motor_python(motor)
    if not python.is_file():
        return OCRMotorSonucu(motor=motor, hata="Motor ortamı kurulu değil.")
    if _devre_acik(motor):
        return OCRMotorSonucu(
            motor=motor,
            hata=(
                f"Motor devre dışı: art arda {DEVRE_KESICI_ESIGI} "
                "çökme/zaman aşımı (bu oturumda atlanıyor)."
            ),
        )
    runner = _proje_koku() / "scripts" / "ocr_engine_runner.py"
    ortam = os.environ.copy()
    ortam.setdefault("TOKENIZERS_PARALLELISM", "false")
    ortam.setdefault("RECOGNITION_BATCH_SIZE", "4")
    ortam.setdefault("DETECTOR_BATCH_SIZE", "2")
    if motor == "surya":
        llama_server = next(
            _proje_koku().glob(".ocr-tools/llama.cpp/**/llama-server"), None
        )
        if llama_server:
            ortam.setdefault("LLAMA_CPP_BINARY", str(llama_server))
        ortam.setdefault("SURYA_INFERENCE_PARALLEL", "1")
        ortam.setdefault("SURYA_INFERENCE_CTX_SIZE", "16384")
        ortam.setdefault("HF_HUB_DISABLE_XET", "1")
    if os.environ.get("SINAV_OKUR_SICAK_HAVUZ") == "1":
        from .ocr_havuz import HavuzHatasi

        try:
            veri = _havuz_getir().oku(
                motor,
                [str(python), str(runner), motor, "--sunucu"],
                ortam,
                gorsel,
                timeout,
            )
            if "hata" in veri:
                # Motor içi hata: süreç sağlıklı yanıtladı, tek-atımlık
                # deneme aynı hatayı tekrar üretir; düşmeye gerek yok.
                # Görsele özgü olabilir — devre kesici sayacına girmez.
                return OCRMotorSonucu(
                    motor=motor,
                    sure_ms=round((time.monotonic() - baslangic) * 1000),
                    hata=str(veri["hata"]),
                )
            try:
                bloklar = _bloklari_ayikla(veri, motor)
            except (KeyError, TypeError, ValueError) as exc:
                return OCRMotorSonucu(
                    motor=motor,
                    sure_ms=round((time.monotonic() - baslangic) * 1000),
                    hata=f"Bozuk blok verisi: {exc}",
                )
            _devre_kaydet(motor, basarili=True)
            return OCRMotorSonucu(
                motor=motor,
                blocks=bloklar,
                sure_ms=round((time.monotonic() - baslangic) * 1000),
            )
        except HavuzHatasi:
            # Havuz yolu çöktü: bu çağrı için mevcut tek-atımlık yola düş.
            pass
    try:
        sonuc = subprocess.run(
            [str(python), str(runner), motor, str(gorsel)],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=ortam,
        )
        veri = json.loads(sonuc.stdout)
        bloklar = _bloklari_ayikla(veri, motor)
        _devre_kaydet(motor, basarili=True)
        return OCRMotorSonucu(
            motor=motor,
            blocks=bloklar,
            sure_ms=round((time.monotonic() - baslangic) * 1000),
        )
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError) as exc:
        # Devre kesici yalnız altyapı ölümünü sayar: zaman aşımı veya sinyalle
        # ölüm (ör. OOM SIGKILL). Görsele özgü motor hataları (rc>0, bozuk
        # çıktı) sayılmaz — iki sorunlu kâğıt sağlıklı motoru kapatmasın.
        cokme = isinstance(exc, subprocess.TimeoutExpired) or (
            isinstance(exc, subprocess.CalledProcessError)
            and (exc.returncode or 0) < 0
        )
        if cokme:
            _devre_kaydet(motor, basarili=False)
        return OCRMotorSonucu(
            motor=motor,
            sure_ms=round((time.monotonic() - baslangic) * 1000),
            hata=str(exc).strip()[-600:],
        )


def _bloklari_ayikla(veri: dict, motor: str) -> list[OCRBlogu]:
    return [
        OCRBlogu(
            text=_normal_metin(b["text"]),
            confidence=max(0.0, min(1.0, float(b.get("confidence", 0.0)))),
            x=float(b["x"]),
            y=float(b["y"]),
            width=float(b["width"]),
            height=float(b["height"]),
            motor=motor,
        )
        for b in veri.get("blocks", [])
        if _normal_metin(str(b.get("text", "")))
    ]


def _trocr_hazir() -> bool:
    from importlib.util import find_spec

    if find_spec("torch") is None or find_spec("transformers") is None:
        return False
    from .htr.trocr import yerel_model_yolu

    return yerel_model_yolu() is not None


_TROCR_TANIYICI = None
_TROCR_KILIT = threading.Lock()
# İnce ayarlı Türkçe model verilmediyse İngilizce taban model kullanılır;
# o modelin token güveni Türkçede aşırı iyimserdir ve sönümlemek gerekir.
_TROCR_VARSAYILAN = False
_TROCR_VARSAYILAN_SONUM = 0.75


def _trocr_getir():
    global _TROCR_TANIYICI, _TROCR_VARSAYILAN
    with _TROCR_KILIT:
        if _TROCR_TANIYICI is None:
            from .htr.trocr import TrocrTaniyici, yerel_model_yolu

            model = yerel_model_yolu()
            _TROCR_TANIYICI = TrocrTaniyici(model) if model else TrocrTaniyici()
            _TROCR_VARSAYILAN = model is None
    return _TROCR_TANIYICI


def _trocr_ocr(
    gorsel: Path,
    sonuclar: list[OCRMotorSonucu],
    azami_satir: int = 80,
    sure_butcesi_sn: float = 420.0,
) -> OCRMotorSonucu:
    """Öncü motorun satır kutularını TrOCR ile yeniden okur.

    TrOCR yalnız tanıma yapar (algılama yapmaz); bu yüzden Vision'ın (yoksa
    ilk başarılı motorun) satır geometrisini kırpar, aynı geometriyle blok
    üretir ve topluluk uzlaşmasına aday olarak girer. Süre bütçesi aşılırsa
    kalan satırlar atlanır; o ana dek okunan bloklar yine topluluğa girer.
    """
    baslangic = time.monotonic()
    if not _trocr_hazir():
        return OCRMotorSonucu(motor="trocr", hata="Motor ortamı kurulu değil.")
    basarililar = [s for s in sonuclar if s.basarili]
    ana = next(
        (s for s in basarililar if s.motor == "vision"),
        basarililar[0] if basarililar else None,
    )
    if ana is None:
        return OCRMotorSonucu(
            motor="trocr", hata="Satır geometrisi verecek öncü motor sonucu yok."
        )
    try:
        import cv2

        taniyici = _trocr_getir()
        goruntu = cv2.imread(str(gorsel), cv2.IMREAD_COLOR)
        if goruntu is None:
            raise OSError(f"Görsel okunamadı: {gorsel}")
        h, w = goruntu.shape[:2]
        # Satır bölütleyicinin mm eşikleri için A4 yüksekliğinden DPI kestir.
        dpi = min(600, max(96, round(h / 297.0 * 25.4)))
        bloklar: list[OCRBlogu] = []
        for anchor in sorted(ana.blocks, key=lambda b: (b.y, b.x))[:azami_satir]:
            if time.monotonic() - baslangic > sure_butcesi_sn:
                break
            pay_y = anchor.height * 0.35
            pay_x = anchor.width * 0.02
            y0 = max(0, round((anchor.y - pay_y) * h))
            y1 = min(h, round((anchor.y + anchor.height + pay_y) * h))
            x0 = max(0, round((anchor.x - pay_x) * w))
            x1 = min(w, round((anchor.x + anchor.width + pay_x) * w))
            if y1 - y0 < 8 or x1 - x0 < 8:
                continue
            # MPS backend'i eşzamanlı generate çağrılarını tolere etmeyebilir;
            # tanıma kilidin içinde serileştirilir.
            with _TROCR_KILIT:
                tanima = taniyici.kutu_taniy(goruntu[y0:y1, x0:x1], dpi)
            metin = _normal_metin(tanima.metin.replace("\n", " "))
            if not metin:
                continue
            guven = max(0.0, min(1.0, float(tanima.guven)))
            if _TROCR_VARSAYILAN:
                guven *= _TROCR_VARSAYILAN_SONUM
            bloklar.append(
                OCRBlogu(
                    text=metin,
                    confidence=guven,
                    x=anchor.x,
                    y=anchor.y,
                    width=anchor.width,
                    height=anchor.height,
                    motor="trocr",
                )
            )
        return OCRMotorSonucu(
            motor="trocr",
            blocks=bloklar,
            sure_ms=round((time.monotonic() - baslangic) * 1000),
        )
    except Exception as exc:
        return OCRMotorSonucu(
            motor="trocr",
            sure_ms=round((time.monotonic() - baslangic) * 1000),
            hata=str(exc).strip()[-600:],
        )


def _dikey_ortusme(a: OCRBlogu, b: OCRBlogu) -> float:
    ortak = max(0.0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    return ortak / max(1e-6, min(a.height, b.height))


def _yatay_ortusme(a: OCRBlogu, b: OCRBlogu) -> float:
    ortak = max(0.0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
    return ortak / max(1e-6, min(a.width, b.width))


def _en_benzer_kelime_penceresi(kaynak: str, hedef: str) -> tuple[str, float]:
    """Paragraf bloğundan hedef satıra en çok benzeyen kelime penceresini seç."""
    kelimeler = kaynak.split()
    hedef_sayisi = max(1, len(hedef.split()))
    if len(kelimeler) <= hedef_sayisi + 2:
        benzerlik = SequenceMatcher(None, kaynak.casefold(), hedef.casefold()).ratio()
        return kaynak, benzerlik
    adaylar: list[tuple[float, str]] = []
    for boyut in range(max(1, hedef_sayisi - 2), hedef_sayisi + 3):
        for baslangic in range(0, len(kelimeler) - boyut + 1):
            metin = " ".join(kelimeler[baslangic : baslangic + boyut])
            benzerlik = SequenceMatcher(
                None, metin.casefold(), hedef.casefold()
            ).ratio()
            adaylar.append((benzerlik, metin))
    benzerlik, metin = max(adaylar)
    return metin, benzerlik


def _aday_metin(anchor: OCRBlogu, bloklar: list[OCRBlogu]) -> tuple[str, float] | None:
    eslesen = [
        b
        for b in bloklar
        if _dikey_ortusme(anchor, b) >= 0.42
        and (
            _yatay_ortusme(anchor, b) >= 0.20
            or anchor.x - 0.025 <= b.x + b.width / 2 <= anchor.x + anchor.width + 0.025
        )
    ]
    if not eslesen:
        return None
    eslesen.sort(key=lambda b: b.x)
    ayarlanmis: list[tuple[str, float]] = []
    for b in eslesen:
        if b.height > anchor.height * 2.6 or len(b.text) > len(anchor.text) * 2.2:
            metin, benzerlik = _en_benzer_kelime_penceresi(b.text, anchor.text)
            if benzerlik < 0.38:
                continue
            ayarlanmis.append((metin, b.confidence * benzerlik))
        else:
            ayarlanmis.append((b.text, b.confidence))
    if not ayarlanmis:
        return None
    metin = _normal_metin(" ".join(a[0] for a in ayarlanmis))
    guven = sum(a[1] for a in ayarlanmis) / len(ayarlanmis)
    return metin, guven


def _en_iyi_aday(adaylar: list[tuple[str, str, float]]) -> tuple[str, float, list[dict]]:
    puanli: list[tuple[float, str, str, float]] = []
    for motor, metin, guven in adaylar:
        benzerlikler = [
            SequenceMatcher(None, metin.casefold(), diger.casefold()).ratio()
            for _, diger, _ in adaylar
            if diger != metin
        ]
        uzlasma = sum(benzerlikler) / len(benzerlikler) if benzerlikler else 0.5
        turkce_bonus = 0.03 if re.search(r"[çğıöşüÇĞİÖŞÜ]", metin) else 0.0
        puan = MOTOR_AGIRLIKLARI.get(motor, 0.75) * (0.68 * guven + 0.32 * uzlasma)
        if motor == "trocr":
            # Sentetik satırlarla eğitilmiş model gerçek el yazısında akıcı ama
            # ilgisiz metin üretebilir. Başka bir motorla en az orta düzeyde
            # örtüşmüyorsa aday raporda kalsın fakat topluluğu tek başına ele
            # geçirmesin; öğretmen alternatiflerde yine görebilir.
            en_yakin = max(benzerlikler, default=0.0)
            if en_yakin < 0.45:
                puan *= 0.45
        puanli.append((puan + turkce_bonus, motor, metin, guven))
    puanli.sort(reverse=True)
    _, _, secilen, _ = puanli[0]
    guven = min(0.995, max(p[0] for p in puanli))
    alternatifler = [
        {"motor": motor, "metin": metin, "guven": round(ham_guven, 4)}
        for _, motor, metin, ham_guven in puanli
    ]
    return secilen, guven, alternatifler


def bloklari_birlestir(sonuclar: list[OCRMotorSonucu]) -> list[OCRBlogu]:
    """Motor satırlarını Vision/ilk başarılı motor geometrisine göre uzlaştır."""
    basarililar = [s for s in sonuclar if s.basarili]
    if not basarililar:
        return []
    ana = next((s for s in basarililar if s.motor == "vision"), basarililar[0])
    birlesik: list[OCRBlogu] = []
    for anchor in sorted(ana.blocks, key=lambda b: (b.y, b.x)):
        adaylar = [(ana.motor, anchor.text, anchor.confidence)]
        for sonuc in basarililar:
            if sonuc is ana:
                continue
            aday = _aday_metin(anchor, sonuc.blocks)
            if aday:
                adaylar.append((sonuc.motor, aday[0], aday[1]))
        metin, guven, alternatifler = _en_iyi_aday(adaylar)
        birlesik.append(
            OCRBlogu(
                text=metin,
                confidence=guven,
                x=anchor.x,
                y=anchor.y,
                width=anchor.width,
                height=anchor.height,
                motor="topluluk",
                alternatives=alternatifler,
            )
        )
    return birlesik


def _belirsiz(sonuclar: list[OCRMotorSonucu], soru_kontrolu: Callable[[str], bool]) -> bool:
    basarililar = [s for s in sonuclar if s.basarili]
    if len(basarililar) < 2:
        return True
    bloklar = bloklari_birlestir(basarililar)
    ortalama = sum(b.confidence for b in bloklar) / len(bloklar) if bloklar else 0.0
    soru_var = any(soru_kontrolu(b.text) for b in bloklar)
    return ortalama < 0.78 or not soru_var


def coklu_ocr(
    gorsel: str | Path,
    *,
    vision_cagir: Callable[[str | Path], list[OCRBlogu]],
    soru_kontrolu: Callable[[str], bool],
    profil: str = "akilli",
) -> tuple[list[OCRBlogu], list[dict]]:
    """Altı motorlu, belirsizlikte genişleyen OCR çalıştır.

    ``akilli`` iki hızlı/erişilebilir motorla başlar ve gerektiğinde ağır
    motorlara (TrOCR dâhil) geçer. ``besli`` kurulu motorların tamamını
    çalıştırır. ``hizli`` yalnız Apple Vision kullanır. TrOCR el yazısı
    uzmanıdır ve öncü motor geometrisi üzerinden topluluğa katılır.
    """
    gorsel = Path(gorsel)
    sonuclar: list[OCRMotorSonucu] = []
    baslangic = time.monotonic()
    try:
        bloklar = vision_cagir(gorsel)
        for b in bloklar:
            b.motor = "vision"
        sonuclar.append(
            OCRMotorSonucu(
                motor="vision",
                blocks=bloklar,
                sure_ms=round((time.monotonic() - baslangic) * 1000),
            )
        )
    except Exception as exc:  # Vision hatası diğer motorları engellememeli.
        sonuclar.append(
            OCRMotorSonucu(
                motor="vision",
                sure_ms=round((time.monotonic() - baslangic) * 1000),
                hata=str(exc),
            )
        )

    if profil == "hizli":
        return bloklari_birlestir(sonuclar), [s.ozet() for s in sonuclar]

    sonuclar.append(
        _alt_surec_ocr("tesseract", gorsel, MOTOR_ZAMAN_ASIMI["tesseract"])
    )
    if profil == "besli":
        calisacaklar = ["easyocr", "paddle", "surya", "trocr"]
    elif _belirsiz(sonuclar, soru_kontrolu):
        # Sağlık kaydı kötü olan motorlar varsayılan yoldan düşer; "besli"
        # profili onları yine de dener (öğretmen bilinçli olarak istiyorsa).
        saglik = motor_sagligi_oku()
        calisacaklar = [
            m
            for m in ("easyocr", "paddle", "trocr")
            if motor_saglikli_mi(m, saglik)
        ]
    else:
        calisacaklar = []
    for motor in calisacaklar:
        if motor == "trocr":
            sonuclar.append(_trocr_ocr(gorsel, sonuclar))
        else:
            sonuclar.append(
                _alt_surec_ocr(motor, gorsel, MOTOR_ZAMAN_ASIMI.get(motor, 300))
            )
    if (
        profil == "akilli"
        and "surya" not in calisacaklar
        and _belirsiz(sonuclar, soru_kontrolu)
    ):
        sonuclar.append(
            _alt_surec_ocr("surya", gorsel, MOTOR_ZAMAN_ASIMI["surya"])
        )
    return bloklari_birlestir(sonuclar), [s.ozet() for s in sonuclar]
