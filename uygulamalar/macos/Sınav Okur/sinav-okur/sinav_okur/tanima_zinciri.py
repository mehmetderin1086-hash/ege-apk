"""Bir cevap kutusunun ÜRETİMDEKİ okuma zinciri, tek yerde.

Üretim hattı (``serbest.py``) bir kutuyu üç katmandan geçiriyor: bağlamlı
OCR → terim sözlüğü düzeltmesi → aday yeniden sıralama. Tezgâh ise çıplak
``kutu_taniy`` çağırıyordu; yani ölçülen şey ürünün yaptığı şey değildi ve
"iyileştirme işe yaradı mı" sorusu cevapsız kalıyordu.

Bu modül zinciri tek imza altında toplar. Katmanların her birinin katkısı
ayrı ayrı raporlanabilsin diye ham okuma da döndürülür.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .modeller import Soru, TanimaSonucu


@dataclass
class ZincirSonucu:
    """Zincirin çıktısı ve hangi katmanın ne değiştirdiği."""

    tanima: TanimaSonucu
    ham_tanima: TanimaSonucu
    sozluk_degisimleri: list[dict] = field(default_factory=list)
    siralama_karari: dict | None = None
    ipuclari: list[str] = field(default_factory=list)
    basili_karisimi: float = 0.0
    basili_ayiklandi: bool = False
    kagit_orani: float = 1.0


def baglam_ipuclari(soru: Soru, sozluk=None) -> list[str]:
    """Motora verilecek okuma ipuçları: rubrik biçimleri + alan terimleri.

    Bunlar cevabı DAYATMAZ, yalnız tanıyıcının sözcük dağarcığını daraltır;
    motorun görüntüde olmayan bir terimi yazmaması ayrı bir sözleşmedir.
    """
    ipuclari = [
        bicim
        for kalem in soru.anahtar.rubrik
        for bicim in kalem.tum_bicimler()
    ]
    if sozluk is not None:
        from .terim_sozlugu import baglam_terimleri

        ipuclari.extend(baglam_terimleri(sozluk))
    return ipuclari


def baglam_sizmasi(
    uretilen: str, beklenen: str, ipuclari: list[str]
) -> float:
    """İpucu listesinden gelip cevapta OLMAYAN terimlerin oranı.

    Bağlamlı okuma bir motoru güçlendirebilir ama aynı zamanda ona cevabı
    fısıldayabilir: model, görüntüde olmayan bir terimi "okumuş" gibi yazarsa
    puanlama yanlış yönde açılır. Bu ölçüm, bağlamlı motoru açmadan önce
    bakılacak kapıdır — bağlamsız koldan anlamlı yüksekse bağlam verilmez.
    """
    from .metin import eslesme_bicimi

    if not ipuclari:
        return 0.0
    uretilen_norm = eslesme_bicimi(uretilen or "")
    beklenen_norm = eslesme_bicimi(beklenen or "")
    if not uretilen_norm:
        return 0.0
    adaylar = {
        eslesme_bicimi(t)
        for t in ipuclari
        if len(eslesme_bicimi(t)) >= 4
    }
    if not adaylar:
        return 0.0
    sizan = sum(
        1
        for terim in adaylar
        if terim in uretilen_norm and terim not in beklenen_norm
    )
    return round(sizan / len(adaylar), 4)


def kutuyu_oku(
    taniyici,
    kirp: np.ndarray,
    soru: Soru,
    *,
    dpi: int = 300,
    sozluk=None,
    referans_pasajlari: list[str] | None = None,
    yeniden_siralama: bool = True,
) -> ZincirSonucu:
    """Kutuyu üretimdeki zincirle okur.

    ``sozluk`` verilmezse sorunun kendi anahtarından derlenir (tezgâh yolu);
    üretim hattı önceden derlediği sözlüğü geçirerek soru başına yeniden
    derlemeyi önler.
    """
    from .htr.yeniden_siralama import adaylari_yeniden_sirala
    from .terim_sozlugu import sozlukle_duzelt

    if sozluk is None:
        from .modeller import Sinav
        from .terim_sozlugu import sozluk_kur

        try:
            sozluk = sozluk_kur(
                Sinav(kimlik="tezgah", baslik="", sorular=[soru]),
                soru_no=soru.no,
                referans_pasajlari=referans_pasajlari,
            )
        except (ValueError, TypeError):
            sozluk = None

    # Kâğıt yalıtımı: gerçek fotoğraflarda masa/örtü/komşu kâğıt da kadraja
    # giriyor ve OCR oradaki dokuları metin sanıyor. Ölçüldü: bir kutuda
    # CER 3.31 → 1.11. Kâğıt zaten baskınsa fonksiyon dokunmuyor.
    from .kalite import kagit_bolgesini_yalit

    kirp, kagit_orani = kagit_bolgesini_yalit(kirp)

    ipuclari = baglam_ipuclari(soru, sozluk)
    if hasattr(taniyici, "kutu_taniy_baglamli") and ipuclari:
        ham = taniyici.kutu_taniy_baglamli(kirp, dpi, ipuclari)
    else:
        ham = taniyici.kutu_taniy(kirp, dpi)

    tanima = ham
    # Basılı soru metni ayıklama: üretimdeki ilk katman. Ölçüldü — gerçek bir
    # kâğıtta CER 8.87 → 3.39. Tezgâh bunu atlarsa yine ürünü ölçmez.
    basili_karisimi = 0.0
    basili_ayiklandi = False
    if tanima.metin:
        from .serbest import (
            BASILI_KAPSAMA_ESIGI,
            _basili_metni_cikar,
            basili_metin_karisimi,
        )

        basili_karisimi = basili_metin_karisimi(tanima.metin, soru.metin)
        if basili_karisimi >= BASILI_KAPSAMA_ESIGI:
            from dataclasses import replace as _replace

            ayrilmis = _basili_metni_cikar(tanima.metin, soru.metin)
            tanima = _replace(tanima, metin=ayrilmis, alternatifler=[])
            basili_ayiklandi = True

    degisimler: list[dict] = []
    if sozluk is not None:
        tanima, degisimler = sozlukle_duzelt(tanima, sozluk)
    siralama_karari = None
    if yeniden_siralama:
        tanima, siralama_karari = adaylari_yeniden_sirala(
            tanima, soru, sozluk, referans_pasajlari
        )
    return ZincirSonucu(
        tanima=tanima,
        ham_tanima=ham,
        sozluk_degisimleri=degisimler,
        siralama_karari=siralama_karari,
        ipuclari=ipuclari,
        basili_karisimi=round(basili_karisimi, 4),
        basili_ayiklandi=basili_ayiklandi,
        kagit_orani=round(kagit_orani, 4),
    )
