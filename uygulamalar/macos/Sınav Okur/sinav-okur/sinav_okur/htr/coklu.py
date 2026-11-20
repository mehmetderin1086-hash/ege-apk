"""Çoklu görüntü/motor uzlaşmalı el yazısı tanıma."""

from __future__ import annotations

import re
import time
from dataclasses import asdict

import numpy as np
from rapidfuzz import fuzz

from ..kalite import (
    kutu_kalitesini_olc,
    ocr_varyantlari,
    ocr_varyantlari_genis,
)
from ..metin import nfc
from ..modeller import TanimaSonucu
from .kalibrasyon import (
    GuvenKalibrasyonu,
    KosulluGuvenKalibrasyonu,
    dilim_anahtari,
)
from .model_kaydi import model_kaydi


def _norm(metin: str) -> str:
    return re.sub(r"\s+", " ", nfc(metin).casefold()).strip()


# Kanıt formülünün sürümü. Formül değişince `karar_marji`'nin (iki kümenin
# kanıt farkı) anlamı da değişir; gölge telemetride farklı sürümler karışırsa
# eşik süpürmesi sessizce yanlış sonuç verir. Değiştiren, telemetriyi bu
# alana göre gruplamalıdır.
#   kanit-v1: motor_destegi paydası TÜM motorlardı (susan motor cezalandırırdı)
#   kanit-v2: payda yalnız konuşan motorlar
KANIT_SURUMU = "kanit-v2"

# Hedefli ikinci geçiş eşiği: aşama-1'de en iyi motor güveni bunun altındaysa
# ya da tek motor konuştuysa pahalı görünümler denenir.
ASAMA2_KANIT_ESIGI = 0.72
# Kutu başına ikinci geçiş süre bütçesi (saniye).
ASAMA2_SURE_BUTCESI = 8.0
# Aşama-1'in süre bütçesi. Asıl emniyet supabı çağrı sayısı değil SÜRE
# olmalı: motorlar arasında 25 kata varan fark var (vision 3,2 sn vs
# surya 80,7 sn), bu yüzden "10 çağrı" bir kutuda 30 sn'ye bir başkasında
# 800 sn'ye karşılık gelebiliyor.
ASAMA1_SURE_BUTCESI = 20.0
# Motor başına denenecek görünüm sayısı (bütçe bununla ölçeklenir).
VARYANT_BASINA_CALISMA = 5
# İkinci geçişin KENDİ çağrı bütçesi. Aşama-1'in `azami_calisma` bütçesiyle
# paylaşılsaydı, 5 varyant × 2 motor = 10 ile varsayılan bütçe aşama-1'de
# tükenir ve ikinci geçiş üretimde hiç çalışmazdı.
ASAMA2_AZAMI_CALISMA = 6


class CokluTaniyici:
    """Birden çok OCR motorunu ve görüntü varyantını uzlaştırır.

    Motor bulunmadığında aynı yerel motor farklı kurşun-kalem ön işlemleri
    üzerinde çalışır. Aynı motorun varyantları bağımsız kanıt sayılmaz.
    """

    def __init__(
        self,
        motorlar: list[tuple],
        azami_calisma: int | None = None,
        kalibrasyon: GuvenKalibrasyonu | KosulluGuvenKalibrasyonu | None = None,
        asama_iki_acik: bool = True,
        asama_iki_sure_butcesi: float = ASAMA2_SURE_BUTCESI,
        asama_iki_azami_calisma: int = ASAMA2_AZAMI_CALISMA,
        asama_bir_sure_butcesi: float = ASAMA1_SURE_BUTCESI,
    ):
        if not motorlar:
            raise ValueError("Çoklu tanıyıcı için en az bir OCR motoru gerekli.")
        self.motorlar = motorlar
        # Bütçe motor sayısıyla ölçeklenir. Sabit 10, tam olarak 5 varyant ×
        # 2 motor demekti: üçüncü bir motor eklendiğinde döngü
        # (varyant → motor) sırasıyla ilerlediği için son varyantlar hiç
        # koşmadan bütçe tükeniyordu.
        self.azami_calisma = max(
            1,
            int(
                azami_calisma
                if azami_calisma is not None
                else VARYANT_BASINA_CALISMA * len(motorlar)
            ),
        )
        self.asama_bir_sure_butcesi = float(asama_bir_sure_butcesi)
        self.kalibrasyon = kalibrasyon or GuvenKalibrasyonu()
        self.asama_iki_acik = bool(asama_iki_acik)
        self.asama_iki_sure_butcesi = float(asama_iki_sure_butcesi)
        self.asama_iki_azami_calisma = max(1, int(asama_iki_azami_calisma))

    def _kalibre(self, ham_guven: float, dilim: str) -> float:
        """Kalibrasyon koşulluysa dilimi kullan, değilse tek eğriye düş."""
        if isinstance(self.kalibrasyon, KosulluGuvenKalibrasyonu):
            return self.kalibrasyon.olasilik(ham_guven, dilim)
        return self.kalibrasyon.olasilik(ham_guven)

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        return self.kutu_taniy_baglamli(kirp, dpi, [])

    def _varyantlari_calistir(
        self,
        varyantlar: list[tuple[str, np.ndarray]],
        dpi: int,
        baglam: list[str] | None,
        ham_sonuclar: list[dict],
        calisma: int,
        asama: int,
        sure_butcesi: float | None = None,
        calisma_siniri: int | None = None,
    ) -> int:
        """Verilen varyant/motor çarpımını çalıştırıp ``calisma`` sayacını döndürür."""
        baslangic = time.monotonic()
        sinir = self.azami_calisma if calisma_siniri is None else calisma_siniri
        for varyant_adi, varyant in varyantlar:
            for motor_verisi in self.motorlar:
                motor_adi, motor = motor_verisi[0], motor_verisi[1]
                motor_agirligi = (
                    float(motor_verisi[2]) if len(motor_verisi) >= 3 else 1.0
                )
                if calisma >= sinir:
                    return calisma
                if (
                    sure_butcesi is not None
                    and time.monotonic() - baslangic > sure_butcesi
                ):
                    return calisma
                calisma += 1
                try:
                    if hasattr(motor, "kutu_taniy_baglamli"):
                        sonuc = motor.kutu_taniy_baglamli(
                            varyant, dpi, baglam or []
                        )
                    else:
                        sonuc = motor.kutu_taniy(varyant, dpi)
                    ham_sonuclar.append(
                        {
                            "motor": str(motor_adi),
                            "varyant": varyant_adi,
                            "metin": str(sonuc.metin or "").strip(),
                            "guven": float(sonuc.guven or 0.0),
                            "motor_agirligi": motor_agirligi,
                            "asama": asama,
                            "hata": "",
                        }
                    )
                except Exception as exc:  # Bir motor diğerlerini engellememeli.
                    ham_sonuclar.append(
                        {
                            "motor": str(motor_adi),
                            "varyant": varyant_adi,
                            "metin": "",
                            "guven": 0.0,
                            "motor_agirligi": motor_agirligi,
                            "asama": asama,
                            "hata": type(exc).__name__,
                        }
                    )
        return calisma

    def _asama_iki_gerekli(self, dolu: list[dict]) -> bool:
        """Aşama-1 kanıtı zayıfsa ikinci geçiş açılır.

        Motor sayısı ölçütü yalnız KURULU motorların bir kısmı susmuşsa
        anlamlıdır: tek motorlu bir kurulumda ikinci geçiş yeni bağımsız
        kanıt üretemez, o yüzden boşuna çalıştırılmaz.
        """
        if not dolu:
            return True
        en_iyi = max(float(s["guven"] or 0.0) for s in dolu)
        if en_iyi < ASAMA2_KANIT_ESIGI:
            return True
        konusan = {s["motor"] for s in dolu}
        hedef_motor = min(2, len(self.motorlar))
        return len(konusan) < hedef_motor

    def kutu_taniy_baglamli(
        self,
        kirp: np.ndarray,
        dpi: int = 300,
        baglam: list[str] | None = None,
    ) -> TanimaSonucu:
        ham_sonuclar: list[dict] = []
        calisma = self._varyantlari_calistir(
            ocr_varyantlari(kirp),
            dpi,
            baglam,
            ham_sonuclar,
            0,
            asama=1,
            sure_butcesi=self.asama_bir_sure_butcesi,
        )
        dolu = [s for s in ham_sonuclar if s["metin"]]
        # Hedefli ikinci geçiş: pahalı görünümler yalnız kanıt zayıfken denenir.
        # Kendi çağrı bütçesiyle çalışır; aşama-1'in bütçesi tükenmiş olabilir.
        if self.asama_iki_acik and self._asama_iki_gerekli(dolu):
            ek_varyantlar = ocr_varyantlari_genis(kirp)
            if ek_varyantlar:
                self._varyantlari_calistir(
                    ek_varyantlar,
                    dpi,
                    baglam,
                    ham_sonuclar,
                    0,
                    asama=2,
                    sure_butcesi=self.asama_iki_sure_butcesi,
                    calisma_siniri=self.asama_iki_azami_calisma,
                )
                dolu = [s for s in ham_sonuclar if s["metin"]]
        if not dolu:
            return TanimaSonucu(
                metin="",
                guven=0.0,
                alternatifler=[],
                motor_sonuclari=ham_sonuclar,
                belirsizlik_nedeni="Hiçbir OCR motoru metin üretemedi.",
                model_surumu=model_kaydi(self.motorlar),
            )

        # Yakın transkripsiyonları aynı kümeye al; en çok desteklenen ve en
        # güvenli kümenin en güvenli yazımını nihai metin seç.
        kumeler: list[list[dict]] = []
        for sonuc in sorted(dolu, key=lambda x: x["guven"], reverse=True):
            eslesen = next(
                (
                    kume
                    for kume in kumeler
                    if fuzz.ratio(_norm(kume[0]["metin"]), _norm(sonuc["metin"])) >= 78
                ),
                None,
            )
            if eslesen is None:
                kumeler.append([sonuc])
            else:
                eslesen.append(sonuc)
        def _kume_kaniti(kume: list[dict]) -> dict:
            motor_en_iyi: dict[str, dict] = {}
            for s in kume:
                onceki = motor_en_iyi.get(s["motor"])
                if onceki is None or s["guven"] > onceki["guven"]:
                    motor_en_iyi[s["motor"]] = s
            agirlik_toplami = sum(
                float(s.get("motor_agirligi", 1.0)) for s in motor_en_iyi.values()
            )
            motor_guveni = (
                sum(
                    float(s["guven"]) * float(s.get("motor_agirligi", 1.0))
                    for s in motor_en_iyi.values()
                )
                / max(1e-6, agirlik_toplami)
            )
            temsilci = max(kume, key=lambda s: s["guven"])
            anlasma = float(
                np.mean(
                    [
                        fuzz.ratio(_norm(temsilci["metin"]), _norm(s["metin"])) / 100
                        for s in kume
                    ]
                )
            )
            varyant_destegi = len(kume) / max(1, len(dolu))
            # Payda KONUŞAN motorlar: susan ya da çöken bir motor payda'da
            # kalırsa kazanan kümenin skorunu düşürür, yani topluluğa motor
            # eklemek kanıtı azaltır ve güvenlik kapısını daha da kapatır.
            # Anlaşmayan (konuşan ama farklı okuyan) motor paydada kalmalı —
            # o gerçek bir uyuşmazlık kanıtıdır.
            konusan = {s["motor"] for s in dolu}
            motor_destegi = len(motor_en_iyi) / max(1, len(konusan))
            kanit = (
                0.42 * motor_guveni
                + 0.23 * varyant_destegi
                + 0.20 * anlasma
                + 0.15 * motor_destegi
            )
            return {
                "kanit": float(kanit),
                "motor_guveni": float(motor_guveni),
                "anlasma": anlasma,
                "motorlar": sorted(motor_en_iyi),
                "temsilci": temsilci,
            }

        kanitlar = [(k, _kume_kaniti(k)) for k in kumeler]
        kanitlar.sort(key=lambda x: x[1]["kanit"], reverse=True)
        kumeler = [k for k, _ in kanitlar]
        kazanan = kumeler[0]
        kazanan_kaniti = kanitlar[0][1]
        secilen = kazanan_kaniti["temsilci"]
        destek = len(kazanan) / len(dolu)
        anlasma = float(kazanan_kaniti["anlasma"])
        ham_guven = float(kazanan_kaniti["kanit"])
        ikinci_kanit = float(kanitlar[1][1]["kanit"]) if len(kanitlar) > 1 else 0.0
        karar_marji = max(0.0, ham_guven - ikinci_kanit)
        bagimsiz_motor = len(kazanan_kaniti["motorlar"])
        # Kalibrasyon dilimi kanıt koşulundan (motor sayısı × görüntü kalitesi)
        # türetilir; koşullu eğri varsa aynı ham güven dilime göre farklı
        # olasılığa çevrilir.
        try:
            bolge_kalitesi = float(kutu_kalitesini_olc(kirp).kalite)
        except Exception:
            bolge_kalitesi = 0.0
        dilim = dilim_anahtari(bagimsiz_motor, bolge_kalitesi)
        guven = self._kalibre(ham_guven, dilim)
        belirsizlikler: list[str] = []
        if bagimsiz_motor < 2:
            belirsizlikler.append("Yalnız bir bağımsız OCR motoru kanıt sağladı.")
        if karar_marji < 0.12 and len(kanitlar) > 1:
            belirsizlikler.append("En iyi OCR adayı ile ikinci aday birbirine çok yakın.")
        if anlasma < 0.86:
            belirsizlikler.append("Görüntü varyantlarının metin uzlaşması düşük.")
        alternatifler = [
            {
                "metin": max(k, key=lambda s: s["guven"])["metin"],
                "guven": round(kanit["kanit"], 4),
                "destek": len(k),
                "motorlar": kanit["motorlar"],
            }
            for k, kanit in kanitlar[:4]
        ]
        return TanimaSonucu(
            metin=nfc(secilen["metin"]),
            guven=guven,
            alternatifler=alternatifler,
            motor_sonuclari=ham_sonuclar,
            uzlasma_guveni=anlasma,
            bagimsiz_motor_sayisi=bagimsiz_motor,
            karar_marji=karar_marji,
            belirsizlik_nedeni=" ".join(belirsizlikler),
            model_surumu=model_kaydi(self.motorlar),
            kanit_surumu=KANIT_SURUMU,
        )


def tanima_sonucu_sozluk(sonuc: TanimaSonucu) -> dict:
    """Depo/UI için kararlı JSON gösterimi."""
    return asdict(sonuc)
