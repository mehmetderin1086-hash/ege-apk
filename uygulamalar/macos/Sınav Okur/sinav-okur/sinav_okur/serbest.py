"""Kullanıcıya ait serbest düzenli yazılıları tanıma ve öğrenci kâğıdı okuma.

Temiz yazılı sayfası görsel referanstır. Öğrenci kâğıdı basılı doku üzerinden
homografiyle hizalanır; referans sayfadan koyulaşan pikseller el yazısı adayı
olarak ayrılır. Düzen veya yayınevi bağımlılığı yoktur.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from itertools import combinations, permutations
from dataclasses import asdict, dataclass, field, replace
from difflib import SequenceMatcher
from pathlib import Path

import cv2
import numpy as np
from rapidfuzz import fuzz

from .metin import aksansiz
from .guvenlik_kapisi import (
    GECERLI_MODLAR,
    MOD_KAPALI,
    MOD_GOLGE,
    VARSAYILAN_MOD,
    kapi_karari_sozlugu,
    otomatik_karari_degerlendir,
)
from .htr import Taniyici
from .htr.yeniden_siralama import adaylari_yeniden_sirala, puan_sonucunu_kisitla
from .modeller import PuanSonucu, Sinav, SoruTipi, TanimaSonucu
from .ocr import OCRBlogu, coklu_ocr
from .puanlama import Gomlemci, PuanlamaAyar, puanla
from .tarama import bos_mu, dosya_sayfalari, dosyalar_sayfalari
from .terim_sozlugu import (
    TerimSozlugu,
    baglam_terimleri,
    sozluk_kur,
    sozlukle_duzelt,
)


@dataclass
class SerbestKutu:
    soru_no: int
    sayfa: int
    x: float
    y: float
    width: float
    height: float


@dataclass
class SerbestSablon:
    sinav_kimlik: str
    dpi: int
    sayfa_gorselleri: list[str]
    kutular: list[SerbestKutu]
    tur: str = "serbest_v1"

    def __post_init__(self) -> None:
        self.kutular = [
            SerbestKutu(**k) if isinstance(k, dict) else k for k in self.kutular
        ]
        if not self.sinav_kimlik.strip():
            raise ValueError("Yazılı tanımında sınav kimliği eksik.")
        if not 1 <= len(self.sayfa_gorselleri) <= 4:
            raise ValueError("Yazılı tanımı 1–4 ana sayfa içermelidir.")
        if not 72 <= int(self.dpi) <= 600:
            raise ValueError("Yazılı tanımının çözünürlüğü 72–600 DPI olmalıdır.")
        for kutu in self.kutular:
            if not 1 <= int(kutu.sayfa) <= len(self.sayfa_gorselleri):
                raise ValueError("Cevap bölgesi geçersiz bir sayfaya bağlı.")
            if int(kutu.soru_no) < 1:
                raise ValueError("Cevap bölgesinin soru numarası geçersiz.")
            if (
                kutu.x < 0
                or kutu.y < 0
                or kutu.width <= 0
                or kutu.height <= 0
                or kutu.x + kutu.width > 1.0001
                or kutu.y + kutu.height > 1.0001
            ):
                raise ValueError(
                    "Cevap bölgesi sayfa sınırlarının dışında veya boş."
                )

    def sayfa_kutulari(self, sayfa: int) -> list[SerbestKutu]:
        return [k for k in self.kutular if k.sayfa == sayfa]

    def json_kaydet(self, yol: str | Path) -> None:
        Path(yol).write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding="utf-8"
        )

    @classmethod
    def json_yukle(cls, yol: str | Path) -> "SerbestSablon":
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        if veri.get("tur") != "serbest_v1":
            raise ValueError("Bu dosya serbest sınav şablonu değil.")
        return cls(**veri)


@dataclass
class SerbestTaslakSorusu:
    no: int
    sayfa: int
    metin: str
    puan: float
    kutu: SerbestKutu
    guven: float
    ocr_alternatifleri: list[dict] = field(default_factory=list)
    yapay_zeka_cevabi: str = ""
    yapay_zeka_rubrik: list[str] = field(default_factory=list)
    yapay_zeka_rubrik_es_anlamlilari: list[list[str]] = field(default_factory=list)
    yapay_zeka_rubrik_kategorileri: list[str] = field(default_factory=list)
    yapay_zeka_rubrik_celiskileri: list[list[str]] = field(default_factory=list)
    yapay_zeka_yontem_adimlari: list[str] = field(default_factory=list)
    yapay_zeka_yaygin_hatalar: list[str] = field(default_factory=list)
    yapay_zeka_yasak_celiskiler: list[str] = field(default_factory=list)
    yapay_zeka_alternatifler: list[str] = field(default_factory=list)
    yapay_zeka_birimler: list[str] = field(default_factory=list)
    yapay_zeka_cevap_turu: str = "acik_uclu"
    yapay_zeka_kaynagi: str = ""
    yapay_zeka_kaynaklari: list[str] = field(default_factory=list)
    yapay_zeka_puanlanabilir: bool = False
    yapay_zeka_uyari: str = ""


@dataclass
class SerbestTaslak:
    token: str
    kaynak_dosya: str
    dpi: int
    sayfa_gorselleri: list[str]
    sorular: list[SerbestTaslakSorusu]
    kaynak_dosyalari: list[str] = field(default_factory=list)
    ek_kutular: list[SerbestKutu] = field(default_factory=list)
    kimlik: str = ""
    baslik: str = ""
    ders: str = ""
    ocr_uyarilari: list[str] = field(default_factory=list)
    ocr_raporu: list[dict] = field(default_factory=list)
    ocr_profili: str = "akilli"

    def __post_init__(self) -> None:
        self.sorular = [
            SerbestTaslakSorusu(
                **{
                    **s,
                    "kutu": (
                        SerbestKutu(**s["kutu"])
                        if isinstance(s.get("kutu"), dict)
                        else s["kutu"]
                    ),
                }
            )
            if isinstance(s, dict)
            else s
            for s in self.sorular
        ]
        self.ek_kutular = [
            SerbestKutu(**k) if isinstance(k, dict) else k for k in self.ek_kutular
        ]

    def json_kaydet(self, yol: str | Path) -> None:
        Path(yol).write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding="utf-8"
        )

    @classmethod
    def json_yukle(cls, yol: str | Path) -> "SerbestTaslak":
        return cls(**json.loads(Path(yol).read_text(encoding="utf-8")))


_SORU_DESENI = re.compile(
    r"^\s*(?:soru\s*[-: ]*\s*)?(\d{1,2})\s*"
    r"(?:(?:[.)=:\-]\s*)|(?:\.\s*soru\b)|(?:\s+soru\b))",
    re.IGNORECASE,
)
_ACIK_SORU_DESENI = re.compile(
    r"^\s*soru\s*[-: ]*\s*(\d{1,2})\s*"
    r"(?:(?:[.)=:\-]\s*)|(?:\.\s*soru\b)|(?:\s+soru\b))?",
    re.IGNORECASE,
)
_PUAN_DESENI = re.compile(
    r"(?:\b(\d{1,3})\s*puan\b|\bpuan\s*[:=\-]?\s*(\d{1,3})\b)",
    re.IGNORECASE,
)


def _vision_araci(proje_kok: Path, arac_dizini: Path) -> Path:
    if sys.platform != "darwin":
        # xcrun/swiftc yalnız macOS'ta var; başka platformda derleme hiç
        # denenmesin (çağıranlar: vision_ocr → coklu_ocr/VisionTaniyici).
        raise ValueError("Apple Vision OCR yalnız macOS'ta çalışır.")
    kaynak = proje_kok / "macos/VisionOCR.swift"
    hedef = arac_dizini / "vision-ocr"
    arac_dizini.mkdir(parents=True, exist_ok=True)
    if hedef.exists() and hedef.stat().st_mtime >= kaynak.stat().st_mtime:
        return hedef
    subprocess.run(
        [
            "/usr/bin/xcrun",
            "swiftc",
            "-O",
            "-target",
            "arm64-apple-macosx13.0",
            "-framework",
            "AppKit",
            "-framework",
            "Vision",
            str(kaynak),
            "-o",
            str(hedef),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return hedef


def vision_ocr(
    gorsel: str | Path,
    arac_dizini: str | Path,
    ozel_kelimeler: list[str] | None = None,
) -> list[OCRBlogu]:
    proje_kok = Path(__file__).resolve().parents[1]
    arac = _vision_araci(proje_kok, Path(arac_dizini))
    sonuc = subprocess.run(
        [str(arac), str(gorsel), *(ozel_kelimeler or [])[:160]],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    )
    veri = json.loads(sonuc.stdout)
    return [OCRBlogu(**b) for b in veri["blocks"]]


def _soru_baslangici(metin: str) -> int | None:
    eslesme = _SORU_DESENI.search(metin)
    return int(eslesme.group(1)) if eslesme else None


def _acik_soru_baslangici(metin: str) -> int | None:
    eslesme = _ACIK_SORU_DESENI.search(metin)
    return int(eslesme.group(1)) if eslesme else None


def _sutun_sinirlari(baslangiclar: list[tuple[OCRBlogu, int]]) -> list[tuple[float, float]]:
    xs = [b.x for b, _ in baslangiclar]
    if len(xs) >= 2 and min(xs) < 0.35 and max(xs) > 0.50:
        return [(0.04, 0.50), (0.50, 0.96)]
    return [(0.04, 0.96)]


def sorulari_bul(
    bloklar: list[OCRBlogu],
    *,
    sayfa: int,
    baslangic_no: int = 1,
) -> list[SerbestTaslakSorusu]:
    """Vision satırlarından üst düzey soru başlangıçlarını ve bölgelerini çıkarır."""
    baslangiclar: list[tuple[OCRBlogu, int]] = []
    sirali_bloklar = sorted(bloklar, key=lambda b: (b.y, b.x))
    acik_basliklar = [
        (blok, no)
        for blok in sirali_bloklar
        if (no := _acik_soru_baslangici(blok.text)) is not None
    ]
    # Bir sayfada birden çok açık "Soru N" başlığı varsa 1), 2) gibi
    # alt maddeleri yeni soru sayma. Açık başlık yoksa eski genel numara
    # desteği korunur.
    # Bir tane bile açık "Soru N" başlığı varsa 1), 2), 3) biçimindeki
    # etkinlik/alt madde numaralarını yeni ana soru sanma. Özellikle arka yüzde
    # önceki sorunun altı boşluğu ve ardından yalnız "Soru 5" bulunabilir.
    yalniz_acik_baslik = bool(acik_basliklar)
    for blok in sirali_bloklar:
        if yalniz_acik_baslik:
            no = _acik_soru_baslangici(blok.text)
        else:
            no = _soru_baslangici(blok.text)
        if no is None:
            continue
        if any(
            eski_no == no
            and abs(eski.y - blok.y) < 0.08
            and abs(eski.x - blok.x) < 0.22
            for eski, eski_no in baslangiclar
        ):
            continue
        baslangiclar.append((blok, no))

    if not baslangiclar:
        kutu = SerbestKutu(
            soru_no=baslangic_no,
            sayfa=sayfa,
            x=0.04,
            y=0.08,
            width=0.92,
            height=0.84,
        )
        return [
            SerbestTaslakSorusu(
                no=baslangic_no,
                sayfa=sayfa,
                metin=f"Sayfa {sayfa} - soru metni otomatik bulunamadı",
                puan=10.0,
                kutu=kutu,
                guven=0.15,
            )
        ]

    sutunlar = _sutun_sinirlari(baslangiclar)
    bolgeler: list[tuple[OCRBlogu, int, tuple[float, float], float]] = []
    for blok, algilanan_no in baslangiclar:
        sutun = next((s for s in sutunlar if s[0] <= blok.x < s[1]), sutunlar[0])
        sonraki_ayni = [
            b.y
            for b, _ in baslangiclar
            if b.y > blok.y + 0.015 and sutun[0] <= b.x < sutun[1]
        ]
        sonraki_herhangi = [
            b.y for b, _ in baslangiclar if b.y > blok.y + 0.05
        ]
        sonraki_y = min(
            sonraki_ayni or sonraki_herhangi or [0.94]
        )
        bolgeler.append((blok, algilanan_no, sutun, sonraki_y))

    sonuc: list[SerbestTaslakSorusu] = []
    kullanilan_nolar: set[int] = set()
    for blok, algilanan_no, sutun, sonraki_y in bolgeler:
        if len(sutunlar) > 1:
            diger_etkin = any(
                diger_sutun != sutun
                and diger_blok.y <= blok.y + 0.02
                and diger_son > blok.y + 0.02
                for diger_blok, _, diger_sutun, diger_son in bolgeler
            )
            if not diger_etkin:
                sutun = (0.04, 0.96)
        bolge_bloklari = [
            b
            for b in bloklar
            if blok.y - 0.012 <= b.y < sonraki_y
            and b.x + b.width > sutun[0]
            and b.x < sutun[1]
        ]
        metin = " ".join(
            b.text.strip() for b in sorted(bolge_bloklari, key=lambda x: (x.y, x.x))
            if b.text.strip()
        ).strip()
        puan_eslesmeleri = _PUAN_DESENI.findall(metin)
        puan_degerleri = [a or b for a, b in puan_eslesmeleri]
        puan = float(puan_degerleri[0]) if puan_degerleri else 10.0
        no = algilanan_no
        while no in kullanilan_nolar:
            no += 1
        kullanilan_nolar.add(no)
        kutu = SerbestKutu(
            soru_no=no,
            sayfa=sayfa,
            x=sutun[0],
            y=max(0.02, blok.y - 0.012),
            width=sutun[1] - sutun[0],
            # Bir sonraki soru başlığının başlangıcı zaten güvenli üst sınırdır.
            # Ek 0.008 sayfa payı, başlıktan hemen önceki el yazısı satırlarının
            # altını kesiyordu (200 DPI A4 fotoğrafta yaklaşık 45 piksel).
            height=max(0.04, min(0.96, sonraki_y) - max(0.02, blok.y - 0.012)),
        )
        guvenler = [b.confidence for b in bolge_bloklari]
        motor_satirlari: dict[str, list[str]] = {}
        motor_guvenleri: dict[str, list[float]] = {}
        for b in sorted(bolge_bloklari, key=lambda x: (x.y, x.x)):
            for alternatif in b.alternatives:
                motor = alternatif["motor"]
                motor_satirlari.setdefault(motor, []).append(alternatif["metin"])
                motor_guvenleri.setdefault(motor, []).append(
                    float(alternatif["guven"])
                )
        alternatifler = [
            {
                "motor": motor,
                "metin": " ".join(satirlar),
                "guven": sum(motor_guvenleri[motor]) / len(motor_guvenleri[motor]),
            }
            for motor, satirlar in motor_satirlari.items()
        ]
        alternatifler.sort(key=lambda a: a["guven"], reverse=True)
        sonuc.append(
            SerbestTaslakSorusu(
                no=no,
                sayfa=sayfa,
                metin=metin or blok.text,
                puan=puan,
                kutu=kutu,
                guven=float(np.mean(guvenler)) if guvenler else blok.confidence,
                ocr_alternatifleri=alternatifler,
            )
        )
    return sorted(
        sonuc,
        key=lambda s: (s.sayfa, round(s.kutu.y / 0.04), s.kutu.x, s.kutu.y),
    )


def serbest_sinav_cozumle(
    kaynak: str | Path | list[str | Path],
    hedef_dizin: str | Path,
    *,
    token: str,
    dpi: int = 200,
    ocr_profili: str = "akilli",
) -> SerbestTaslak:
    hedef = Path(hedef_dizin)
    hedef.mkdir(parents=True, exist_ok=True)
    kaynaklar = kaynak if isinstance(kaynak, list) else [kaynak]
    sayfalar = dosyalar_sayfalari(kaynaklar, dpi, azami_sayfa=4)
    if len(sayfalar) > 4:
        raise ValueError(
            f"Bir sınav en fazla 4 sayfa olabilir; {len(sayfalar)} sayfa yüklendi."
        )
    gorseller: list[str] = []
    tum_sorular: list[SerbestTaslakSorusu] = []
    uyarilar: list[str] = []
    ocr_raporu: list[dict] = []
    sonraki_no = 1
    onceki_soru_no: int | None = None
    ek_kutular: list[SerbestKutu] = []
    for sayfa_no, sayfa in enumerate(sayfalar, start=1):
        gorsel_yolu = hedef / f"ana_sayfa_{sayfa_no}.png"
        cv2.imwrite(str(gorsel_yolu), sayfa)
        gorseller.append(str(gorsel_yolu))
        if _renkli_kalem_orani(sayfa) > 0.0002:
            uyarilar.append(
                f"Sayfa {sayfa_no}: renkli kalem veya öğretmen işareti algılandı. "
                "Bu adım boş/temiz sınav içindir; cevaplı ya da notlandırılmış "
                "kâğıt kullanmayın."
            )
        bloklar, motor_raporu = coklu_ocr(
            gorsel_yolu,
            vision_cagir=lambda yol: vision_ocr(yol, hedef.parent / "araclar"),
            soru_kontrolu=lambda metin: _soru_baslangici(metin) is not None,
            profil=ocr_profili,
        )
        for rapor in motor_raporu:
            ocr_raporu.append({"sayfa": sayfa_no, **rapor})
            if rapor["hata"] and rapor["hata"] != "Motor ortamı kurulu değil.":
                uyarilar.append(
                    f"Sayfa {sayfa_no}: {rapor['motor']} OCR çalışmadı "
                    f"({rapor['hata']})."
                )
        sorular = sorulari_bul(bloklar, sayfa=sayfa_no, baslangic_no=sonraki_no)
        if sayfa_no > 1 and onceki_soru_no is not None:
            ilk_y = min((s.kutu.y for s in sorular), default=0.96)
            if ilk_y >= 0.20:
                ek_kutular.append(
                    SerbestKutu(
                        soru_no=onceki_soru_no,
                        sayfa=sayfa_no,
                        x=0.04,
                        y=0.02,
                        width=0.92,
                        height=max(0.08, ilk_y - 0.02),
                    )
                )
                uyarilar.append(
                    f"Sayfa {sayfa_no} üst bölümü, önceki sayfadan devam eden "
                    f"Soru {onceki_soru_no} ile otomatik birleştirildi."
                )
                devam_metni = " ".join(
                    b.text.strip()
                    for b in sorted(bloklar, key=lambda x: (x.y, x.x))
                    if 0.01 <= b.y < ilk_y and b.text.strip()
                ).strip()
                onceki_soru = next(
                    (s for s in reversed(tum_sorular) if s.no == onceki_soru_no),
                    None,
                )
                if onceki_soru is not None and len(devam_metni) >= 20:
                    onceki_soru.metin = (
                        f"{onceki_soru.metin.rstrip()} {devam_metni}"
                    ).strip()
        tum_sorular.extend(sorular)
        if sorular:
            onceki_soru_no = sorular[-1].no
        sonraki_no = max((s.no for s in tum_sorular), default=0) + 1
        if not bloklar:
            uyarilar.append(
                f"Sayfa {sayfa_no}: soru başlangıçları elle kontrol edilmelidir."
            )
    taslak = SerbestTaslak(
        token=token,
        kaynak_dosya=str(Path(kaynaklar[0]).resolve()),
        kaynak_dosyalari=[str(Path(k).resolve()) for k in kaynaklar],
        ek_kutular=ek_kutular,
        dpi=dpi,
        sayfa_gorselleri=gorseller,
        sorular=tum_sorular,
        ocr_uyarilari=uyarilar,
        ocr_raporu=ocr_raporu,
        ocr_profili=ocr_profili,
    )
    taslak.json_kaydet(hedef / "taslak.json")
    return taslak


def _tek_yon_hizala(ham: np.ndarray, ana: np.ndarray) -> tuple[np.ndarray, float]:
    """Tek yöndeki sayfayı basılı dokuyla referans sayfaya hizala."""
    hedef_h, hedef_w = ana.shape[:2]
    ham_olcekli = cv2.resize(ham, (hedef_w, hedef_h), interpolation=cv2.INTER_AREA)
    ana_gri = cv2.cvtColor(ana, cv2.COLOR_BGR2GRAY)
    ham_gri = cv2.cvtColor(ham_olcekli, cv2.COLOR_BGR2GRAY)
    orb = cv2.ORB_create(nfeatures=5000, fastThreshold=8)
    kp1, des1 = orb.detectAndCompute(ham_gri, None)
    kp2, des2 = orb.detectAndCompute(ana_gri, None)
    if des1 is None or des2 is None or len(kp1) < 20 or len(kp2) < 20:
        return ham_olcekli, 0.2
    eslesmeler = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True).match(des1, des2)
    eslesmeler = sorted(eslesmeler, key=lambda m: m.distance)[:400]
    if len(eslesmeler) < 15:
        return ham_olcekli, 0.25
    kaynak = np.float32([kp1[m.queryIdx].pt for m in eslesmeler])
    hedef = np.float32([kp2[m.trainIdx].pt for m in eslesmeler])
    homografi, maske = cv2.findHomography(kaynak, hedef, cv2.RANSAC, 4.0)
    if homografi is None or maske is None:
        return ham_olcekli, 0.3
    ic_oran = float(maske.ravel().mean())
    hizali = cv2.warpPerspective(
        ham_olcekli,
        homografi,
        (hedef_w, hedef_h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(255, 255, 255),
    )
    return hizali, min(1.0, ic_oran * 1.8)


def _doku_benzerligi(ana: np.ndarray, hizali: np.ndarray) -> float:
    ana_maske = cv2.cvtColor(ana, cv2.COLOR_BGR2GRAY) < 205
    ogrenci_maske = cv2.cvtColor(hizali, cv2.COLOR_BGR2GRAY) < 205
    birlesim = int(np.count_nonzero(ana_maske | ogrenci_maske))
    kesisim = int(np.count_nonzero(ana_maske & ogrenci_maske))
    return kesisim / birlesim if birlesim else 0.0


def _serbest_hizala(
    ham: np.ndarray, ana: np.ndarray
) -> tuple[np.ndarray, float, int]:
    """Sayfa yönünü bulup basılı dokuyu referans sayfaya hizala."""
    ham_yatay = ham.shape[1] > ham.shape[0]
    ana_yatay = ana.shape[1] > ana.shape[0]
    yonler = (
        ((0, ham), (180, cv2.rotate(ham, cv2.ROTATE_180)))
        if ham_yatay == ana_yatay
        else (
            (90, cv2.rotate(ham, cv2.ROTATE_90_CLOCKWISE)),
            (270, cv2.rotate(ham, cv2.ROTATE_90_COUNTERCLOCKWISE)),
        )
    )
    en_iyi: tuple[np.ndarray, float, int] | None = None
    en_iyi_skor = -1.0
    for derece, aday in yonler:
        hizali, guven = _tek_yon_hizala(aday, ana)
        doku = _doku_benzerligi(ana, hizali)
        skor = 0.35 * guven + 0.65 * doku
        if skor > en_iyi_skor:
            en_iyi = hizali, guven, derece
            en_iyi_skor = skor
    assert en_iyi is not None
    return en_iyi


def _sayfalari_esle(
    ham_sayfalar: list[np.ndarray],
    ana_sayfalar: list[np.ndarray],
) -> tuple[dict[int, tuple[int, np.ndarray, float, int]], list[str]]:
    """En fazla dört öğrenci sayfasını görsel dokuya göre şablon sayfalarıyla eşle."""
    if not ham_sayfalar or not ana_sayfalar:
        return {}, []
    hizalamalar: dict[tuple[int, int], tuple[np.ndarray, float]] = {}
    donusler: dict[tuple[int, int], int] = {}
    doku_skorlari: dict[tuple[int, int], float] = {}
    for ham_i, ham in enumerate(ham_sayfalar):
        for ana_i, ana in enumerate(ana_sayfalar):
            hizali, guven, donus = _serbest_hizala(ham, ana)
            hizalamalar[(ham_i, ana_i)] = (hizali, guven)
            donusler[(ham_i, ana_i)] = donus
            doku_skorlari[(ham_i, ana_i)] = _doku_benzerligi(ana, hizali)
    adet = min(len(ham_sayfalar), len(ana_sayfalar))
    en_iyi_skor = -1.0
    en_iyi: tuple[tuple[int, ...], tuple[int, ...]] | None = None
    for ana_secimi in combinations(range(len(ana_sayfalar)), adet):
        for ham_sirasi in permutations(range(len(ham_sayfalar)), adet):
            skor = sum(
                0.35 * hizalamalar[(ham_i, ana_i)][1]
                + 0.65 * doku_skorlari[(ham_i, ana_i)]
                for ana_i, ham_i in zip(ana_secimi, ham_sirasi)
            )
            if skor > en_iyi_skor:
                en_iyi_skor = skor
                en_iyi = (ana_secimi, ham_sirasi)
    if en_iyi is None:
        return {}, []
    eslesmeler = {
        ana_i: (
            ham_i,
            *hizalamalar[(ham_i, ana_i)],
            donusler[(ham_i, ana_i)],
        )
        for ana_i, ham_i in zip(*en_iyi)
    }
    uyarilar = []
    for ana_i, (ham_i, _hizali, _guven, donus) in sorted(eslesmeler.items()):
        if ana_i != ham_i:
            uyarilar.append(
                f"Yüklenen {ham_i + 1}. sayfa, görsel içeriğe göre sınavın "
                f"{ana_i + 1}. sayfasıyla eşleştirildi."
            )
        if donus:
            uyarilar.append(
                f"Yüklenen {ham_i + 1}. sayfa {donus}° döndürülerek okundu."
            )
    if len(ham_sayfalar) > len(ana_sayfalar):
        uyarilar.append(
            f"{len(ham_sayfalar) - len(ana_sayfalar)} ek sayfa sınav şablonunda "
            "karşılığı olmadığı için cevap puanlamasına katılmadı."
        )
    return eslesmeler, uyarilar


# Basılı metin ayıklamada bir kelimenin "soruda geçiyor" sayılması için
# gereken benzerlik. OCR basılı metni de hatalı okuyabildiği için
# ("bulaştırabileceğini" → "bulaştırabileceğiini") tam eşitlik aramak
# kalıntı bırakıyordu; ölçüldü: bu satırlar CER'i iki katına çıkarıyor.
BASILI_KELIME_ESIGI = 86
# Ardışık bu kadar eşleşen kelime "basılı cümle parçası" sayılır. Tek tek
# eşleşmeler silinmez: öğrencinin cevabı da sorunun kelimelerini kullanabilir
# ("hücre teorisinin keşfi" cevabında "hücre" soruda da geçer).
BASILI_ASGARI_BLOK = 3


# OCR metninin bu kadarı soru metninde geçiyorsa "basılı metin de okunmuş"
# sayılır. Altındaysa kutu temiz kesilmiş demektir ve ayıklama YAPILMAZ:
# öğrencinin cevabı sorunun kelimelerini ardışık kullanabilir ("hücre
# teorisine göre..."), temiz bir kutuda bunu silmek cevabı yok eder.
BASILI_KAPSAMA_ESIGI = 0.35


def basili_metin_karisimi(ocr_metni: str, soru_metni: str) -> float:
    """OCR metninin ne kadarı soru metninden geliyor (0-1)."""
    kelimeler = [
        aksansiz(k.casefold())
        for k in re.findall(r"\w+", ocr_metni, re.UNICODE)
        if len(k) > 2
    ]
    if not kelimeler:
        return 0.0
    soru_kelimeleri = [
        aksansiz(k) for k in re.findall(r"\w+", soru_metni.casefold(), re.UNICODE)
    ]
    soru_kumesi = set(soru_kelimeleri)
    eslesen = sum(
        1 for k in kelimeler if _soruda_gecer(k, soru_kumesi, soru_kelimeleri)
    )
    return eslesen / len(kelimeler)


def _basili_metni_cikar(ocr_metni: str, soru_metni: str) -> str:
    """Cevaplı kâğıt şablon olmuşsa OCR'dan basılı soru parçalarını ayıkla."""
    soru_kelimeleri = [
        aksansiz(k) for k in re.findall(r"\w+", soru_metni.casefold(), re.UNICODE)
    ]
    soru_kumesi = set(soru_kelimeleri)
    kalan_satirlar: list[str] = []
    for satir in ocr_metni.splitlines():
        kelimeler = re.findall(r"\w+", satir, re.UNICODE)
        norm = [aksansiz(k.casefold()) for k in kelimeler]
        if not norm:
            continue
        # Her kelime için "soruda var mı" (bulanık) — sonra ardışık bloklar.
        eslesenler = [
            _soruda_gecer(k, soru_kumesi, soru_kelimeleri) for k in norm
        ]
        silinecek: set[int] = set()
        blok_basi = None
        for i, esleti in enumerate([*eslesenler, False]):
            if esleti and blok_basi is None:
                blok_basi = i
            elif not esleti and blok_basi is not None:
                if i - blok_basi >= BASILI_ASGARI_BLOK:
                    silinecek.update(range(blok_basi, i))
                blok_basi = None
        kalan = [k for i, k in enumerate(kelimeler) if i not in silinecek]
        # Yalnız soru başlığı/puanı kaldıysa cevap sayma.
        kalan = [
            k for k in kalan
            if k.casefold() not in {"soru", "puan", "puandır", "puandir"}
            and not (k.isdigit() and len(k) <= 2)
        ]
        if kalan:
            kalan_satirlar.append(" ".join(kalan))
    return "\n".join(kalan_satirlar).strip()


def _soruda_gecer(
    kelime: str, soru_kumesi: set[str], soru_kelimeleri: list[str]
) -> bool:
    """Kelime soru metninde (OCR hatasına toleranslı) geçiyor mu?"""
    if len(kelime) <= 2:
        # Kısa kelimeler ("bir", "ve") her yerde geçer; blok kuralı zaten
        # bunları ancak uzun bir dizinin parçasıysa siler.
        return kelime in soru_kumesi
    if kelime in soru_kumesi:
        return True
    return any(
        fuzz.ratio(kelime, aday) >= BASILI_KELIME_ESIGI
        for aday in soru_kelimeleri
        if abs(len(aday) - len(kelime)) <= 3
    )


def _el_yazisi_farki(ana: np.ndarray, ogrenci: np.ndarray) -> np.ndarray:
    from .kalite import kursun_kalem_gri

    ana_gri = kursun_kalem_gri(ana)
    ogrenci_gri = kursun_kalem_gri(ogrenci)
    ana_gri = cv2.GaussianBlur(ana_gri, (3, 3), 0)
    ogrenci_gri = cv2.GaussianBlur(ogrenci_gri, (3, 3), 0)
    koyulasma = ana_gri.astype(np.int16) - ogrenci_gri.astype(np.int16)
    maske = np.where(koyulasma > 32, 255, 0).astype(np.uint8)
    maske = cv2.morphologyEx(maske, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    bileşen_sayisi, etiketler, istatistikler, _ = cv2.connectedComponentsWithStats(
        maske, 8
    )
    temiz = np.zeros_like(maske)
    for i in range(1, bileşen_sayisi):
        if istatistikler[i, cv2.CC_STAT_AREA] >= 8:
            temiz[etiketler == i] = 255
    return cv2.cvtColor(255 - temiz, cv2.COLOR_GRAY2BGR)


def _soluk_iz_orani(ana: np.ndarray, ogrenci: np.ndarray) -> float:
    """Öğrenci bölgesinde ana sayfaya göre en hafif koyulaşma oranı.

    ``_el_yazisi_farki`` soluk (koyulaşma ≤32) veya küçük izleri geri
    döndürülemez biçimde siler; bu ölçüm daha düşük bir eşikle (>12) o silinmiş
    soluk el yazısını yakalar. Boş kutu otomatik kabulünün, farkta kaybolan
    gerçek bir cevabı sıfırlamasını önlemek için bağımsız kanıt sağlar.
    """
    from .kalite import kursun_kalem_gri

    if ana is None or ogrenci is None or not ana.size or not ogrenci.size:
        return 0.0
    if ana.shape != ogrenci.shape:
        ogrenci = cv2.resize(ogrenci, (ana.shape[1], ana.shape[0]))
    ana_gri = cv2.GaussianBlur(kursun_kalem_gri(ana), (3, 3), 0).astype(np.int16)
    ogrenci_gri = cv2.GaussianBlur(kursun_kalem_gri(ogrenci), (3, 3), 0).astype(np.int16)
    koyulasma = ana_gri - ogrenci_gri
    return float(np.mean(koyulasma > 12))


def _sayfa_fark_olcumu(
    ana: np.ndarray, ogrenci: np.ndarray
) -> tuple[float, float]:
    """Ana sayfaya göre ortalama değişimi ve yeni koyu piksel oranını döndürür."""
    from .kalite import kursun_kalem_gri

    ana_gri = kursun_kalem_gri(ana).astype(np.int16)
    ogrenci_gri = kursun_kalem_gri(ogrenci).astype(np.int16)
    fark = ana_gri - ogrenci_gri
    ortalama_mutlak_fark = float(np.mean(np.abs(fark)))
    yeni_murekkep_orani = float(np.mean(fark > 32))
    return ortalama_mutlak_fark, yeni_murekkep_orani


def _renkli_kalem_orani(goruntu: np.ndarray) -> float:
    """Sayfanın iç bölümündeki baskın kırmızı/renkli kalem piksellerini ölçer."""
    h, w = goruntu.shape[:2]
    ic = goruntu[
        max(0, round(h * 0.10)):min(h, round(h * 0.90)),
        max(0, round(w * 0.10)):min(w, round(w * 0.90)),
    ]
    if ic.size == 0:
        return 0.0
    b, g, r = cv2.split(ic)
    r16, g16, b16 = r.astype(np.int16), g.astype(np.int16), b.astype(np.int16)
    renkli = (r16 - g16 > 45) & (r16 - b16 > 45) & (r > 90)
    return float(np.mean(renkli))


def _oransal_kirp(goruntu: np.ndarray, kutu: SerbestKutu) -> np.ndarray:
    h, w = goruntu.shape[:2]
    x0 = max(0, round(kutu.x * w))
    y0 = max(0, round(kutu.y * h))
    x1 = min(w, round((kutu.x + kutu.width) * w))
    y1 = min(h, round((kutu.y + kutu.height) * h))
    return goruntu[y0:y1, x0:x1]


# Gerçek el yazısında doğrulanmamış motorlar: kazanan okuma YALNIZ bunlardan
# geliyorsa otomatik kabul edilmez (bkz docs/trocr_egitim_tanisi.md).
DOGRULANMAMIS_MOTORLAR = frozenset({"trocr"})


def _yalniz_dogrulanmamis_motor(tanima) -> bool:
    """Kazanan kümeyi yalnız doğrulanmamış bir motor mu destekliyor?"""
    if not tanima.alternatifler:
        return False
    motorlar = tanima.alternatifler[0].get("motorlar") or []
    if not motorlar:
        return False
    return set(motorlar).issubset(DOGRULANMAMIS_MOTORLAR)


def serbest_kagit_isle(
    dosya: str | Path | list[str | Path],
    sinav: Sinav,
    sablon: SerbestSablon,
    taniyici: Taniyici,
    gomlemci: Gomlemci | None = None,
    ayar: PuanlamaAyar | None = None,
    referans_deposu=None,
    *,
    kirp_dizini: str | Path | None = None,
    guvenlik_kapisi_modu: str | None = None,
    duzeltme_ornekleri: list[dict] | None = None,
    ogrenilmis_kabuller: dict[int, list[str]] | None = None,
    sozluk_kullan: bool = True,
    yeniden_siralama_kullan: bool = True,
):
    from .sonuclar import KagitSonucu, KutuSonucu

    # Soru başına terim sözlüğü; aynı sınavın her kutusunda yeniden derlenmez.
    sozlukler: dict[int, TerimSozlugu] = {}
    kapi_modu = (
        guvenlik_kapisi_modu
        if guvenlik_kapisi_modu is not None
        else os.environ.get("SINAV_OKUR_GUVENLIK_KAPISI", VARSAYILAN_MOD)
    )
    if kapi_modu not in GECERLI_MODLAR:
        kapi_modu = VARSAYILAN_MOD
    ayar = ayar or PuanlamaAyar()
    sonuc = KagitSonucu(sinav_kimlik=sinav.kimlik, islenen_sayfalar=[])
    kirp_kok = Path(kirp_dizini) if kirp_dizini else None
    if kirp_kok:
        kirp_kok.mkdir(parents=True, exist_ok=True)
    parca_sayaci: dict[int, int] = {}
    ham_sayfalar = (
        dosyalar_sayfalari(dosya, sablon.dpi, azami_sayfa=4)
        if isinstance(dosya, list)
        else dosya_sayfalari(dosya, sablon.dpi, azami_sayfa=4)
    )
    if len(ham_sayfalar) > 4:
        raise ValueError(
            f"Bir öğrenci kâğıdı en fazla 4 sayfa olabilir; "
            f"{len(ham_sayfalar)} sayfa yüklendi."
        )
    from .kalite import (
        kagit_bolgesini_yalit,
        kutu_kalitesini_olc,
        sayfalari_degerlendir,
    )

    kalite_raporlari = sayfalari_degerlendir(ham_sayfalar)
    sonuc.kalite_raporu = [rapor.sozluk() for rapor in kalite_raporlari]
    for rapor in kalite_raporlari:
        for uyari in rapor.uyarilar:
            sonuc.uyarilar.append(f"Sayfa {rapor.sayfa}: {uyari}")
    from .kimlik import kimlik_bilgisi_oku

    if len(ham_sayfalar) != len(sablon.sayfa_gorselleri):
        sonuc.uyarilar.append(
            f"Sayfa sayısı farklı: ana sınav {len(sablon.sayfa_gorselleri)}, "
            f"yüklenen kâğıt {len(ham_sayfalar)}."
        )
    ana_sayfalar = [
        cv2.imread(ana_yolu, cv2.IMREAD_COLOR)
        for ana_yolu in sablon.sayfa_gorselleri
    ]
    gecerli_ana = [a for a in ana_sayfalar if a is not None]
    if len(gecerli_ana) != len(ana_sayfalar):
        sonuc.uyarilar.append("Bir veya daha fazla ana şablon sayfası bulunamadı.")
        return sonuc
    eslesmeler, eslesme_uyarilari = _sayfalari_esle(
        ham_sayfalar, gecerli_ana
    )
    sonuc.uyarilar.extend(eslesme_uyarilari)
    yonu_duzeltilmis = [
        eslesmeler[sayfa_i][1]
        for sayfa_i in sorted(eslesmeler)
    ]
    sonuc.kimlik_bilgileri = kimlik_bilgisi_oku(
        yonu_duzeltilmis or ham_sayfalar,
        taniyici,
        sablon.dpi,
    )
    sonuc.uyarilar.extend(sonuc.kimlik_bilgileri.get("uyarilar", []))
    for sayfa_no, ana in enumerate(gecerli_ana, start=1):
        if sayfa_no - 1 not in eslesmeler:
            continue
        if ana is None:
            sonuc.uyarilar.append(f"Sayfa {sayfa_no}: ana şablon görüntüsü bulunamadı.")
            continue
        _ham_i, hizali, hizalama_guveni, donus = eslesmeler[sayfa_no - 1]
        # Siyah kurşun modunda renk silinmez. Gölge normalizasyonu fark
        # görüntüsünün içinde uygulanır; orijinal sayfa görsel kanıt olarak kalır.
        ana_temiz = ana
        hizali_temiz = hizali
        ortalama_fark, yeni_murekkep_orani = _sayfa_fark_olcumu(
            ana_temiz, hizali_temiz
        )
        sayfa_ana_ile_ayni = (
            ortalama_fark < 0.8 and yeni_murekkep_orani < 0.0003
        )
        fark = _el_yazisi_farki(ana_temiz, hizali_temiz)
        sonuc.islenen_sayfalar.append(sayfa_no)
        sonuc.sayfa_eslesmeleri.append(
            {
                "yukleme_sirasi": _ham_i + 1,
                "sinav_sayfasi": sayfa_no,
                "hizalama_guveni": hizalama_guveni,
                "donus_derecesi": donus,
            }
        )
        if sayfa_ana_ile_ayni:
            sonuc.uyarilar.append(
                f"Sayfa {sayfa_no}: öğrenci kâğıdı ana şablonla aynı görünüyor; "
                "cevaplı kâğıdın şablon olarak kullanıldığı anlaşıldı. Sistem "
                "basılı soru metnini OCR sonucundan ayırmayı denedi; sonucu doğrulayın."
            )
        if hizalama_guveni < 0.55:
            sonuc.uyarilar.append(
                f"Sayfa {sayfa_no}: otomatik hizalama güveni düşük "
                f"(%{hizalama_guveni * 100:.0f}); cevaplar elle kontrol edilmelidir."
            )
        for kutu in sablon.sayfa_kutulari(sayfa_no):
            kirp = _oransal_kirp(fark, kutu)
            # Aynı görüntü yanlışlıkla hem ana şablon hem öğrenci kâğıdı olarak
            # kullanıldıysa fark görüntüsü bembeyazdır. İnceleme ekranında en
            # azından gerçek sayfa bölgesini göster; OCR'ı basılı soruyla
            # kirletmemek için otomatik tanımaya sokma.
            gosterilecek_kirp = (
                _oransal_kirp(hizali, kutu) if sayfa_ana_ile_ayni else kirp
            )
            soru = sinav.soru(kutu.soru_no)
            kutu_bos = bos_mu(kirp) and not sayfa_ana_ile_ayni
            # Bağımsız soluk-iz kanıtı: fark görüntüsünde silinen soluk el
            # yazısını daha düşük eşikle yakalar. Boş otomatik kabulünün gerçek
            # ama soluk bir cevabı sıfırlamasını önler (kapının bos_dogrulandi
            # yolu yalnız bu bağımsız kontrol de boş derse tetiklenir).
            soluk_iz = _soluk_iz_orani(
                _oransal_kirp(ana_temiz, kutu), _oransal_kirp(hizali, kutu)
            )
            ocr_kirp = (
                _oransal_kirp(hizali_temiz, kutu)
                if sayfa_ana_ile_ayni else kirp
            )
            # Kâğıt dışı arka planı (masa, örtü, komşu kâğıt) beyazlat: OCR
            # oradaki dokuları metin sanıp gürültü üretiyordu. Ölçüldü:
            # kırpıntının %40'ı arka plan olan bir kutuda CER 3.31 → 1.11.
            ocr_kirp, kagit_orani = kagit_bolgesini_yalit(ocr_kirp)
            bolge_kalitesi = kutu_kalitesini_olc(ocr_kirp)
            # Referans pasajları hem tanıma bağlamını hem puanlamayı besler;
            # bu yüzden tanımadan ÖNCE hazırlanır.
            referans_pasajlari = None
            if referans_deposu is not None:
                try:
                    referans_pasajlari = [
                        pasaj.metin
                        for pasaj, _skor in referans_deposu.ilgili(soru.metin, k=5)
                    ]
                except Exception:
                    referans_pasajlari = None
            soru_sozlugu = sozlukler.get(soru.no)
            if soru_sozlugu is None:
                soru_sozlugu = (
                    sozluk_kur(
                        sinav,
                        soru_no=soru.no,
                        referans_pasajlari=referans_pasajlari,
                        duzeltme_ornekleri=duzeltme_ornekleri,
                    )
                    if sozluk_kullan
                    else TerimSozlugu()
                )
                sozlukler[soru.no] = soru_sozlugu
            tanima = (
                TanimaSonucu(
                    metin="",
                    guven=1.0,
                    uzlasma_guveni=1.0,
                    girdi_kalitesi=bolge_kalitesi.kalite,
                )
                if kutu_bos
                else (
                    taniyici.kutu_taniy_baglamli(
                        ocr_kirp,
                        sablon.dpi,
                        [
                            bicim
                            for kalem in soru.anahtar.rubrik
                            for bicim in kalem.tum_bicimler()
                        ]
                        + baglam_terimleri(soru_sozlugu),
                    )
                    if hasattr(taniyici, "kutu_taniy_baglamli")
                    else taniyici.kutu_taniy(ocr_kirp, sablon.dpi)
                )
            )
            tanima.girdi_kalitesi = bolge_kalitesi.kalite
            sozluk_degisimleri: list[dict] = []
            siralama_karari: dict | None = None
            if not kutu_bos and not sayfa_ana_ile_ayni:
                tanima, sozluk_degisimleri = sozlukle_duzelt(tanima, soru_sozlugu)
                # Kanıt marjı darsa bağlama en tutarlı adayı seç. "Cevaplı
                # şablon" dalı alternatifleri düşürdüğü için orada atlanır.
                if yeniden_siralama_kullan:
                    tanima, siralama_karari = adaylari_yeniden_sirala(
                        tanima, soru, soru_sozlugu, referans_pasajlari
                    )
            # Basılı soru metni ayıklama. Eskiden yalnız "cevaplı şablon"
            # dalında çalışıyordu; oysa öğrencinin soru kâğıdının üstüne
            # yazdığı her kutuda OCR basılı metni de okuyor ve bu, ölçülen
            # tek büyük hata kaynağı: gerçek bir kâğıtta CER 8.21 → 0.97.
            # Karar metne bakılarak verilir (karışım oranı), kâğıt tipine
            # değil — temiz kesilmiş bir kutuda ayıklama YAPILMAZ, yoksa
            # sorunun kelimelerini kullanan bir cevap silinebilir.
            karisim = (
                basili_metin_karisimi(tanima.metin, soru.metin)
                if tanima.metin
                else 0.0
            )
            if tanima.metin and (
                sayfa_ana_ile_ayni or karisim >= BASILI_KAPSAMA_ESIGI
            ):
                ayrilmis = _basili_metni_cikar(tanima.metin, soru.metin)
                # replace: motor sonuçları, girdi kalitesi ve kapı kanıtları
                # (uzlasma_guveni, bagimsiz_motor_sayisi, karar_marji)
                # korunur — sıfırdan kurmak bu dalda tüm telemetriyi
                # düşürüyordu. alternatifler boşaltılır: metin değiştiği için
                # aday listesi geçersizdir ve "metni değişen kutu
                # kalibrasyona girmez" değişmezi kendiliğinden uygulanır.
                tanima = replace(
                    tanima,
                    metin=ayrilmis,
                    guven=min(tanima.guven, 0.62 if ayrilmis else 0.0),
                    alternatifler=[],
                    belirsizlik_nedeni=(
                        tanima.belirsizlik_nedeni
                        + f" Basılı soru metni ayıklandı (karışım %{karisim * 100:.0f})."
                    ).strip(),
                )
            kirp_yolu = None
            if kirp_kok:
                parca_sayaci[kutu.soru_no] = parca_sayaci.get(kutu.soru_no, 0) + 1
                kirp_yolu = str(
                    kirp_kok
                    / f"soru_{kutu.soru_no}_parca_{parca_sayaci[kutu.soru_no]}.png"
                )
                cv2.imwrite(kirp_yolu, gosterilecek_kirp)
            puan_sonucu: PuanSonucu = puanla(
                tanima, soru, gomlemci, ayar,
                referans_pasajlari=referans_pasajlari,
                # Öğretmenin onayladığı kabul yazımları ilk işlemede de
                # geçerli olmalı; aksi halde aynı sınavda iki puanlama
                # rejimi oluşur (ilk şube 0, ikinci şube 10 alır).
                ogrenilmis_kabuller=(ogrenilmis_kabuller or {}).get(soru.no),
            )
            if siralama_karari is not None:
                # Bağlamla seçilen okuma tek başına puan kesinleştiremez.
                onceki_sonuc = puanla(
                    TanimaSonucu(
                        metin=siralama_karari["onceki"], guven=tanima.guven
                    ),
                    soru,
                    gomlemci,
                    ayar,
                    referans_pasajlari=referans_pasajlari,
                    ogrenilmis_kabuller=(ogrenilmis_kabuller or {}).get(soru.no),
                )
                puan_sonucu.kararlar.append(siralama_karari)
                puan_sonucunu_kisitla(puan_sonucu, onceki_sonuc.puan)
            if soru.tip in {SoruTipi.GRAFIK, SoruTipi.CIZIM, SoruTipi.TABLO}:
                from .gorsel_cevap import gorsel_cevabi_incele

                gorsel_karar = gorsel_cevabi_incele(ocr_kirp, soru.tip)
                puan_sonucu.kararlar.append(gorsel_karar)
                puan_sonucu.detaylar.append(
                    "Görsel yapı: " + gorsel_karar["neden"]
                )
            puan_sonucu.guven = min(
                puan_sonucu.guven, tanima.guven, hizalama_guveni
            )
            if kalite_raporlari[_ham_i].kritik:
                puan_sonucu.guven = min(puan_sonucu.guven, 0.35)
                puan_sonucu.detaylar.append(
                    "⚠ Tarama kalite kapısı: sayfa yeniden çekilmeli; puan "
                    "kesinleştirilmedi."
                )
            # Seçici kabul kapısı: bütün kanıtlar yeterliyse otomatik kesinleştir,
            # değilse insan incelemesine gönder. Kapalı modda kapı hiç çağrılmaz;
            # gölge modda karar yalnız telemetriye yazılır ve davranış (incele,
            # risk dahil) birebir geri sarılır — kutu her durumda incelemeye düşer.
            if kapi_modu == MOD_KAPALI:
                puan_sonucu.incele = True
                puan_sonucu.otomatik_kabul = False
                puan_sonucu.detaylar.append(
                    "Serbest sınav: basılı ana sayfa çıkarıldı; görseli doğrulayın."
                )
            else:
                onceki_risk = puan_sonucu.risk
                ek_kapi_nedenleri: list[str] = []
                if sayfa_ana_ile_ayni:
                    ek_kapi_nedenleri.append(
                        "Cevaplı şablon modu: el yazısı düşük güvenle ayrıştırıldı."
                    )
                if siralama_karari is not None:
                    # Vetoyu kapıya GİRDİ olarak ver: kapı kabul_nedenleri'ni
                    # üzerine yazdığı için yalnız puan_sonucunu_kisitla'ya
                    # güvenmek, ASGARI_KARAR_MARJI değişirse sessizce kırılır.
                    ek_kapi_nedenleri.append(
                        "Aday yeniden sıralama devrede: okuma bağlamla seçildi."
                    )
                if sozluk_degisimleri:
                    ek_kapi_nedenleri.append(
                        f"Alan sözlüğü {len(sozluk_degisimleri)} terimi düzeltti."
                    )
                if _yalniz_dogrulanmamis_motor(tanima):
                    # Kanıt formülüne motor adına özel çarpan konmaz (her yeni
                    # motorda yeniden yazılır); veto kapıya girdi olarak verilir.
                    ek_kapi_nedenleri.append(
                        "Kazanan okuma yalnız TrOCR'dan geldi; bu model gerçek "
                        "el yazısında doğrulanmadı."
                    )
                puan_sonucu = otomatik_karari_degerlendir(
                    tanima,
                    puan_sonucu,
                    soru,
                    bos_dogrulandi=(
                        kutu_bos
                        and bolge_kalitesi.onplan_orani < 0.001
                        and soluk_iz < 0.002
                    ),
                    sayfa_kritik=kalite_raporlari[_ham_i].kritik,
                    hizalama_guveni=hizalama_guveni,
                    ek_nedenler=ek_kapi_nedenleri,
                )
                puan_sonucu.kararlar.append(
                    kapi_karari_sozlugu(tanima, puan_sonucu, kapi_modu)
                )
                if kapi_modu == MOD_GOLGE:
                    # Gölge: kararı yalnız telemetriye yaz, davranışı tam geri sar.
                    puan_sonucu.incele = True
                    puan_sonucu.otomatik_kabul = False
                    tanima.otomatik_kabul = False
                    puan_sonucu.kabul_nedenleri = []
                    puan_sonucu.risk = onceki_risk
                    puan_sonucu.detaylar = [
                        d for d in puan_sonucu.detaylar
                        if not d.startswith("⚠ Güvenli karar kapısı:")
                    ]
                if puan_sonucu.incele:
                    puan_sonucu.detaylar.append(
                        "Serbest sınav: basılı ana sayfa çıkarıldı; görseli doğrulayın."
                    )
            if bolge_kalitesi.uyarilar:
                puan_sonucu.detaylar.extend(
                    f"⚠ Bölgesel kalite: {uyari}"
                    for uyari in bolge_kalitesi.uyarilar
                )
            if soru.anahtar.otomatik_uretildi:
                puan_sonucu.detaylar.append(
                    "Cevap anahtarı RAG kaynaklarından otomatik oluşturuldu."
                )
            if sayfa_ana_ile_ayni:
                puan_sonucu.detaylar.append(
                    "Cevaplı şablon modu: basılı soru OCR metninden çıkarıldı; "
                    "el yazısı düşük güvenle ayrıştırıldı."
                )
            elif kutu_bos:
                puan_sonucu.detaylar.append(
                    "Cevap bölgesinde ana şablona eklenmiş yeni yazı algılanmadı."
                )
            sonuc.kutular.append(
                KutuSonucu(
                    soru_no=kutu.soru_no,
                    tanima=tanima,
                    puan=puan_sonucu,
                    kirp_yolu=kirp_yolu,
                    kalite=bolge_kalitesi.sozluk(),
                    sozluk_duzeltmeleri=sozluk_degisimleri,
                )
            )
    # Ön yüzde başlayıp arka yüzde devam eden soruların metin ve görüntülerini
    # birleştir; aynı soruyu iki kez puanlayıp toplam puanı şişirme.
    soru_gruplari: dict[int, list[KutuSonucu]] = {}
    for kutu_sonucu in sonuc.kutular:
        soru_gruplari.setdefault(kutu_sonucu.soru_no, []).append(kutu_sonucu)
    birlesmis_kutular: list[KutuSonucu] = []
    for soru_no, parcalar in soru_gruplari.items():
        if len(parcalar) == 1:
            birlesmis_kutular.append(parcalar[0])
            continue
        metin_parcalari = list(
            dict.fromkeys(
                p.tanima.metin.strip()
                for p in parcalar
                if p.tanima.metin.strip()
            )
        )
        birlesik_tanima = TanimaSonucu(
            metin="\n".join(metin_parcalari),
            guven=min(
                (p.tanima.guven for p in parcalar if p.tanima.metin.strip()),
                default=0.0,
            ),
        )
        soru = sinav.soru(soru_no)
        referans_pasajlari = None
        if referans_deposu is not None:
            try:
                referans_pasajlari = [
                    pasaj.metin
                    for pasaj, _skor in referans_deposu.ilgili(soru.metin, k=5)
                ]
            except Exception:
                referans_pasajlari = None
        birlesik_puan = puanla(
            birlesik_tanima,
            soru,
            gomlemci,
            ayar,
            referans_pasajlari=referans_pasajlari,
        )
        birlesik_puan.guven = min(
            birlesik_puan.guven,
            birlesik_tanima.guven,
            *(p.puan.guven for p in parcalar),
        )
        birlesik_puan.detaylar.append(
            f"Çok sayfalı cevap: {len(parcalar)} bölge birleştirilip tek kez puanlandı."
        )
        # Birleşik tanımada bağımsız motor kanıtı sıfırdır; kapı bu kutuyu her
        # durumda reddeder. Tek-kutu yoluyla aynı mod sözleşmesi: kapalıda kapı
        # hiç çağrılmaz, gölgede karar telemetriye yazılır ama risk dahil geri sarılır.
        if kapi_modu != MOD_KAPALI:
            onceki_birlesik_risk = birlesik_puan.risk
            birlesik_puan = otomatik_karari_degerlendir(
                birlesik_tanima,
                birlesik_puan,
                soru,
                ek_nedenler=[
                    "Çok sayfalı birleşik cevap tek kanıt zinciriyle doğrulanamaz."
                ],
            )
            birlesik_puan.kararlar.append(
                kapi_karari_sozlugu(birlesik_tanima, birlesik_puan, kapi_modu)
            )
            if kapi_modu == MOD_GOLGE:
                birlesik_puan.otomatik_kabul = False
                birlesik_puan.kabul_nedenleri = []
                birlesik_puan.risk = onceki_birlesik_risk
                birlesik_puan.detaylar = [
                    d for d in birlesik_puan.detaylar
                    if not d.startswith("⚠ Güvenli karar kapısı:")
                ]
        birlesik_puan.incele = True
        birlesik_yol = next((p.kirp_yolu for p in parcalar if p.kirp_yolu), None)
        if kirp_kok:
            gorseller = [
                cv2.imread(p.kirp_yolu, cv2.IMREAD_COLOR)
                for p in parcalar
                if p.kirp_yolu
            ]
            gorseller = [g for g in gorseller if g is not None and g.size]
            if gorseller:
                genislik = max(g.shape[1] for g in gorseller)
                eslenmis = [
                    cv2.copyMakeBorder(
                        g,
                        0,
                        0,
                        0,
                        genislik - g.shape[1],
                        cv2.BORDER_CONSTANT,
                        value=(255, 255, 255),
                    )
                    for g in gorseller
                ]
                birlesik_yol = str(kirp_kok / f"soru_{soru_no}.png")
                cv2.imwrite(birlesik_yol, cv2.vconcat(eslenmis))
        birlesmis_kutular.append(
            KutuSonucu(
                soru_no=soru_no,
                tanima=birlesik_tanima,
                puan=birlesik_puan,
                kirp_yolu=birlesik_yol,
            )
        )
    sonuc.kutular = sorted(birlesmis_kutular, key=lambda k: k.soru_no)
    return sonuc
