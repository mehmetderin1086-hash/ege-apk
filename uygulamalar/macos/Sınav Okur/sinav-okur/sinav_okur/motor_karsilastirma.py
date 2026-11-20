"""Kurulu OCR motorlarını KENDİ kâğıtlarınızda karşılaştırır.

Hangi motorun daha iyi okuduğu genel bir gerçek değil, yazıya ve kâğıda
bağlıdır: bir kıyaslama tablosundaki sıralama sizin sınıfınızın el yazısında
tersine dönebilir. Bu modül altın seti kullanarak sıralamayı yerelde
ölçer — model seçimi tahmine değil ölçüme dayansın.

Ölçülen (2026-08, 2 gerçek kutu, Türkçe el yazısı):
    qwen3-vl (mlx)   CER 0.594   ~8.7 sn/kutu
    apple-vision     CER 0.841   ~0.4 sn/kutu
    topluluk         CER 0.884   ~23  sn/kutu   ← tek motordan KÖTÜ

Son satır önemli: motor eklemek kendiliğinden iyileştirmez. Kalite farkı
büyükken oylama, zayıf motorun uzun/gürültülü çıktısını öne çıkarabiliyor.
"""

from __future__ import annotations

import time
from pathlib import Path

# Alt süreç motorları (kendi sanal ortamlarında çalışır).
ALT_SUREC_MOTORLARI = ("tesseract", "easyocr", "paddle", "surya")
# Süreç içi tanıyıcılar (htr fabrikası üzerinden).
YERLESIK_MOTORLAR = ("vision", "trocr", "mlx", "keras-karakter", "keras-ctc")


def _ayikla(metin: str, soru) -> str:
    """Üretimdeki basılı-metin ayıklamasını uygular (adil karşılaştırma)."""
    from .serbest import (
        BASILI_KAPSAMA_ESIGI,
        _basili_metni_cikar,
        basili_metin_karisimi,
    )

    if not metin:
        return ""
    if basili_metin_karisimi(metin, soru.metin) >= BASILI_KAPSAMA_ESIGI:
        return _basili_metni_cikar(metin, soru.metin)
    return metin


def _alt_surec_okuyucu(motor: str):
    from . import ocr as ocr_mod

    def oku(yol: Path, _kirp):
        sonuc = ocr_mod._alt_surec_ocr(
            motor, yol, ocr_mod.MOTOR_ZAMAN_ASIMI.get(motor, 300)
        )
        if sonuc.hata and not sonuc.blocks:
            raise RuntimeError(sonuc.hata)
        return "\n".join(b.text for b in sonuc.blocks)

    return oku


# Yerleşik motorların varsayılan model yolları. TrOCR'ın Colab'da eğitilmiş
# Türkçe modeli proje içinde durur; yol verilmezse tanıyıcı İngilizce tabana
# düşer ve karşılaştırma yanıltıcı olur.
VARSAYILAN_MODEL_YOLLARI = {
    "trocr": "modeller/trocr-tr",
    "keras-karakter": "modeller/karakter_cnn/turkce_karakter_cnn.keras",
    "keras-ctc": "modeller/gercek_satir_ctc/turkce_gercek_satir_ctc.keras",
}


def _yerlesik_okuyucu(motor: str, model_yolu: str | None = None):
    from .htr import taniyici_yukle

    if model_yolu is None:
        aday = VARSAYILAN_MODEL_YOLLARI.get(motor)
        if aday and Path(aday).exists():
            model_yolu = aday
    taniyici = taniyici_yukle(motor, model_yolu)

    def oku(_yol, kirp):
        return taniyici.kutu_taniy(kirp).metin

    return oku


def motorlari_karsilastir(
    depo,
    *,
    sinav_kimlik: str | None = None,
    motorlar: list[str] | None = None,
    azami_ornek: int | None = None,
) -> dict:
    """Altın set üzerinde motorları CER'e göre sıralar.

    Kurulu olmayan ya da çöken motor "hata" ile raporlanır, ölçüm durmaz.
    """
    import cv2

    from .tezgah import karakter_hata_orani

    ornekler = [
        o
        for o in depo.altin_ornekler(sinav_kimlik)
        if o["kirp_yolu"] and Path(o["kirp_yolu"]).is_file()
    ]
    if azami_ornek:
        ornekler = ornekler[:azami_ornek]
    if not ornekler:
        return {"ornek": 0, "motorlar": [], "uyarilar": ["Altın örnek yok."]}

    # Varsayılan küme: hızlı yerleşikler (vision, trocr) + alt süreç motorları.
    # VLM (mlx) yavaş ve bellek istediği için açıkça istenmedikçe ölçülmez.
    secilen = list(
        motorlar or ("vision", "trocr", *ALT_SUREC_MOTORLARI)
    )
    sinav_onbellek: dict[str, object] = {}
    satirlar = []
    for motor in secilen:
        try:
            oku = (
                _alt_surec_okuyucu(motor)
                if motor in ALT_SUREC_MOTORLARI
                else _yerlesik_okuyucu(motor)
            )
        except Exception as exc:  # motor kurulu değil / model yüklenemedi
            satirlar.append({"motor": motor, "hata": str(exc)[:120]})
            continue

        cerler: list[float] = []
        sure = 0.0
        hatalar = 0
        for ornek in ornekler:
            kimlik = ornek["sinav_kimlik"]
            if kimlik not in sinav_onbellek:
                try:
                    sinav_onbellek[kimlik] = depo.sinav_yukle(kimlik)
                except KeyError:
                    sinav_onbellek[kimlik] = None
            sinav = sinav_onbellek[kimlik]
            if sinav is None:
                continue
            try:
                soru = sinav.soru(ornek["soru_no"])
            except KeyError:
                continue
            kirp = cv2.imread(ornek["kirp_yolu"])
            if kirp is None:
                continue
            basla = time.monotonic()
            try:
                ham = oku(Path(ornek["kirp_yolu"]), kirp)
            except Exception:
                hatalar += 1
                ham = ""
            sure += time.monotonic() - basla
            cerler.append(
                karakter_hata_orani(ornek["beklenen_metin"], _ayikla(ham, soru))
            )
        if not cerler:
            satirlar.append({"motor": motor, "hata": "ölçülebilir örnek yok"})
            continue
        satirlar.append(
            {
                "motor": motor,
                "cer": round(sum(cerler) / len(cerler), 4),
                "ornek": len(cerler),
                "hata_sayisi": hatalar,
                "ort_sn": round(sure / len(cerler), 2),
            }
        )

    olculenler = [s for s in satirlar if "cer" in s]
    olculenler.sort(key=lambda s: s["cer"])
    uyarilar = []
    if len(ornekler) < 30:
        uyarilar.append(
            f"{len(ornekler)} örnek: sıralama yön gösterir, istatistik değildir."
        )
    return {
        "ornek": len(ornekler),
        "motorlar": olculenler + [s for s in satirlar if "cer" not in s],
        "en_iyi": olculenler[0]["motor"] if olculenler else None,
        "uyarilar": uyarilar,
    }
