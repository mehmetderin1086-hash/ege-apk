"""Alan sözlüğü ile OCR sonrası terim düzeltme.

El yazısı tanıma en çok alan terimlerinde tökezliyor ("mitokondri" →
"mitokondi", "rnitokondri"). Bu modül sınavın kendi cevap anahtarından,
ders kitabı pasajlarından, öğretmenin geçmiş düzeltmelerinden ve taban
biyoloji/tıp terim listesinden bir sözlük derleyip OCR çıktısındaki
sözcükleri buna göre düzeltir.

Model eğitimi yoktur; yalnız sözlük + bulanık eşleşme + öğretmen
düzeltmelerinden çıkarılan karakter karışıklıkları kullanılır.

**Sentetik veri yasağı:** ``veri.korpus`` modülünden yalnız TERİM LİSTESİ
okunur; ``satir_uret``/``korpus_uret`` gibi sentetik üretim çağrılmaz.
"""

from __future__ import annotations

import difflib
import json
import os
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from rapidfuzz import fuzz, process

from .metin import aksansiz, eslesme_bicimi
from .modeller import Sinav, TanimaSonucu
from .puanlama.rubrik import govde

# Kaynak güvenilirliğine göre ağırlık: sınavın kendi anahtarı en güçlü
# kanıt, taban terim listesi en zayıf.
AGIRLIK_ANAHTAR = 1.0
AGIRLIK_DUZELTME = 0.9
AGIRLIK_KITAP = 0.7
AGIRLIK_TABAN = 0.5

ASGARI_GOVDE_UZUNLUGU = 4
ASGARI_SKOR = 88.0
ASGARI_MARJ = 6.0
AZAMI_DEGISIM_ORANI = 0.35

_KELIME = re.compile(r"[^\W\d_]+", re.UNICODE)


@dataclass
class TerimSozlugu:
    """Kanonik terim → ağırlık eşlemesi ve öğrenilmiş karakter karışıklıkları."""

    terimler: dict[str, float] = field(default_factory=dict)
    karisikliklar: dict[str, str] = field(default_factory=dict)

    def ekle(self, ham: str, agirlik: float) -> None:
        for kelime in _KELIME.findall(str(ham or "")):
            kanonik = eslesme_bicimi(kelime)
            if len(kanonik) < ASGARI_GOVDE_UZUNLUGU:
                continue
            if self.terimler.get(kanonik, 0.0) < agirlik:
                self.terimler[kanonik] = agirlik

    def bos_mu(self) -> bool:
        return not self.terimler

    def sozluk(self) -> dict:
        return {
            "terimler": self.terimler,
            "karisikliklar": self.karisikliklar,
        }

    def kaydet(self, yol: str | Path) -> Path:
        """Atomik yazım: yarım kalmış dosya asla okunmaz."""
        yol = Path(yol)
        yol.parent.mkdir(parents=True, exist_ok=True)
        gecici = yol.with_suffix(yol.suffix + ".gecici")
        gecici.write_text(
            json.dumps(self.sozluk(), ensure_ascii=False, indent=2), encoding="utf-8"
        )
        os.replace(gecici, yol)
        return yol

    @classmethod
    def yukle(cls, yol: str | Path) -> "TerimSozlugu":
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        return cls(
            terimler={str(k): float(v) for k, v in veri.get("terimler", {}).items()},
            karisikliklar={
                str(k): str(v) for k, v in veri.get("karisikliklar", {}).items()
            },
        )


def _taban_terimleri() -> list[str]:
    """Biyoloji/tıp taban terim listesi; yoksa sessizce boş döner."""
    try:
        from .veri.korpus import BIYOLOJI_TERIMLERI, TIP_TERIMLERI
    except ImportError:
        return []
    return list(BIYOLOJI_TERIMLERI) + list(TIP_TERIMLERI)


def karisikliklari_ogren(
    ornekler: list[dict], asgari_destek: int = 3
) -> dict[str, str]:
    """Öğretmen düzeltmelerinden yinelenen karakter karışıklıklarını çıkarır.

    ``rn`` → ``m`` gibi OCR'a özgü hatalar aynı öğretmenin kâğıtlarında
    tekrar eder; ``asgari_destek`` kez görülenler kabul edilir.
    """
    sayac: Counter = Counter()
    for ornek in ornekler:
        ham = eslesme_bicimi(str(ornek.get("ocr_metni") or ""))
        duzeltilmis = eslesme_bicimi(str(ornek.get("duzeltilmis_metin") or ""))
        if not ham or not duzeltilmis or ham == duzeltilmis:
            continue
        eslestirici = difflib.SequenceMatcher(None, ham, duzeltilmis)
        for etiket, i1, i2, j1, j2 in eslestirici.get_opcodes():
            if etiket != "replace":
                continue
            kaynak, hedef = ham[i1:i2], duzeltilmis[j1:j2]
            # Yalnız kısa, harf içeren değişimler kalıp sayılır.
            if 0 < len(kaynak) <= 3 and 0 < len(hedef) <= 3:
                if kaynak.isalpha() and hedef.isalpha():
                    sayac[(kaynak, hedef)] += 1
    return {
        kaynak: hedef
        for (kaynak, hedef), adet in sayac.items()
        if adet >= asgari_destek
    }


def sozluk_kur(
    sinav: Sinav | None = None,
    *,
    soru_no: int | None = None,
    referans_pasajlari: list[str] | None = None,
    duzeltme_ornekleri: list[dict] | None = None,
    taban_dahil: bool = True,
) -> TerimSozlugu:
    """Dört kaynaktan ağırlıklı terim sözlüğü derler."""
    sozluk = TerimSozlugu()
    if sinav is not None:
        sorular = (
            [sinav.soru(soru_no)] if soru_no is not None else list(sinav.sorular)
        )
        for soru in sorular:
            anahtar = soru.anahtar
            parcalar: list[str] = [
                *anahtar.dogru_cevaplar,
                *anahtar.kabul_edilen_alternatifler,
                *anahtar.siralama,
                *anahtar.birimler,
                *anahtar.yontem_adimlari,
                anahtar.ornek_cevap,
            ]
            for kalem in anahtar.rubrik:
                parcalar.extend(kalem.tum_bicimler())
            for sol, sag in anahtar.eslestirmeler.items():
                parcalar.extend([sol, sag])
            for parca in parcalar:
                sozluk.ekle(parca, AGIRLIK_ANAHTAR)
    for pasaj in referans_pasajlari or []:
        sozluk.ekle(pasaj, AGIRLIK_KITAP)
    # Düzeltme örnekleri soru bazında süzülür: 7. sorunun cevap metinleri
    # 1. sorunun sözlüğüne girerse konu bütünlüğü olmayan bir terim havuzu
    # oluşur ve düzeltme kararı gereksiz yere genişler.
    # Soru numarası taşımayan kayıtlar (eski/serbest çağrılar) hangi soruya
    # ait olduğu bilinemediği için elenmez.
    ilgili_duzeltmeler = [
        o
        for o in (duzeltme_ornekleri or [])
        if soru_no is None
        or o.get("soru_no") is None
        or int(o["soru_no"]) == int(soru_no)
    ]
    for ornek in ilgili_duzeltmeler:
        sozluk.ekle(str(ornek.get("duzeltilmis_metin") or ""), AGIRLIK_DUZELTME)
    if taban_dahil:
        for terim in _taban_terimleri():
            sozluk.ekle(terim, AGIRLIK_TABAN)
    # Karakter karışıklıkları tüm sorulardan öğrenilir: bunlar konuya değil
    # yazı stiline özgüdür ("rn"→"m" aynı öğretmenin her kâğıdında geçerli).
    if duzeltme_ornekleri:
        sozluk.karisikliklar = karisikliklari_ogren(duzeltme_ornekleri)
    return sozluk


def _adaylar(hedef: str, sozluk: TerimSozlugu) -> list[tuple[str, float]]:
    """En yakın iki sözlük terimi (ad, skor)."""
    bulunanlar = process.extract(
        hedef, list(sozluk.terimler.keys()), scorer=fuzz.ratio, limit=2
    )
    return [(ad, float(skor)) for ad, skor, _ in bulunanlar]


# Türkçe çekim zinciri "-lardan"/"-lerden" ile 6 karaktere çıkabilir. Bu
# sınır kısa tutulursa gövde ekin ORTASINDAN kesilir ve doğru yazılmış bir
# sözcük ("kloroplastlarda") bozularak "düzeltilir" ("kloroplastarda").
AZAMI_EK_UZUNLUGU = 6


def _turetilmis_mi(kok: str, terim: str) -> bool:
    """Gövde, sözlük terimini bütün olarak içeriyor mu (ön ek/son ek türevi)?

    "deplazmoliz" sözlükteki "plazmoliz"i olduğu gibi içerir; bu bir OCR
    hatası değil, ZIT anlamlı ayrı bir terimdir. Böyle sözcüklere dokunmak
    öğrencinin doğru cevabını yanlışa çevirir.
    """
    if kok == terim:
        return True
    return (kok.endswith(terim) or kok.startswith(terim)) and len(kok) > len(terim)


def _kelimeyi_duzelt(kelime: str, sozluk: TerimSozlugu) -> str | None:
    """Tek sözcüğü sözlüğe göre düzeltir; emin değilse ``None``.

    Türkçe çekim eki listesi kapalı olmadığından gövde, sondan en fazla
    ``AZAMI_EK_UZUNLUGU`` karakter kırpılarak aranır: hangi kırpım sözlükte
    en iyi eşleşmeyi veriyorsa gövde odur, kalan kısım ek olarak korunur
    ("mitokondiye" → gövde "mitokondi" + ek "ye" → "mitokondriye").
    """
    kanonik = eslesme_bicimi(kelime)
    if not kanonik or any(ch.isdigit() for ch in kelime):
        return None
    if len(kanonik) < ASGARI_GOVDE_UZUNLUGU:
        return None
    if kanonik in sozluk.terimler or govde(kanonik) in sozluk.terimler:
        return None  # zaten bilinen terim, dokunma
    en_iyi_secim: tuple[float, str, str] | None = None  # (skor, terim, ek)
    for kirpim in range(0, AZAMI_EK_UZUNLUGU + 1):
        kok = kanonik[: len(kanonik) - kirpim] if kirpim else kanonik
        if len(kok) < ASGARI_GOVDE_UZUNLUGU:
            break
        if kok in sozluk.terimler:
            # Bir çekim eki soyulunca sözlükteki terime birebir oturuyor:
            # sözcük zaten doğru yazılmış, düzeltme gerekmez.
            return None
        adaylar = _adaylar(kok, sozluk)
        if not adaylar:
            continue
        terim, skor = adaylar[0]
        if skor < ASGARI_SKOR:
            continue
        if len(adaylar) > 1 and skor - adaylar[1][1] < ASGARI_MARJ:
            continue  # iki terim arasında kalmışsa karar verme
        if aksansiz(terim) == aksansiz(kok):
            continue  # yalnız aksan farkı; puanlama zaten tolere ediyor
        if _turetilmis_mi(kok, terim):
            continue  # türev/zıt terim; OCR hatası değil
        if en_iyi_secim is None or skor > en_iyi_secim[0]:
            en_iyi_secim = (skor, terim, kanonik[len(kok):])
    if en_iyi_secim is None and sozluk.karisikliklar:
        # Öğrenilmiş karakter karışıklıklarını uygulayıp bir kez daha dene:
        # "rnitokondri" gibi hatalar fuzzy eşiğini tek başına geçemeyebilir.
        onarilmis = kanonik
        for kaynak, hedef in sozluk.karisikliklar.items():
            onarilmis = onarilmis.replace(kaynak, hedef)
        if onarilmis != kanonik and len(onarilmis) >= ASGARI_GOVDE_UZUNLUGU:
            if onarilmis in sozluk.terimler:
                return onarilmis
            adaylar = _adaylar(onarilmis, sozluk)
            if adaylar and adaylar[0][1] >= ASGARI_SKOR:
                terim = adaylar[0][0]
                if not _turetilmis_mi(onarilmis, terim):
                    en_iyi_secim = (adaylar[0][1], terim, "")
    if en_iyi_secim is None:
        return None
    _skor, terim, ek = en_iyi_secim
    sonuc = terim + ek
    # Son kapı: üretilen sözcük özgün yazımdan çok uzaklaşmamalı. Ek yanlış
    # yerden kesildiyse bu kapı sonucu eler.
    if fuzz.ratio(kanonik, sonuc) < ASGARI_SKOR:
        return None
    return sonuc


def sozlukle_duzelt(
    tanima: TanimaSonucu, sozluk: TerimSozlugu
) -> tuple[TanimaSonucu, list[dict]]:
    """OCR metnini sözlükle düzeltir; ham metni alternatiflerde saklar.

    Güvenlik kapısının dayandığı kanıt alanları (``karar_marji``,
    ``uzlasma_guveni``, ``bagimsiz_motor_sayisi``) DEĞİŞTİRİLMEZ — düzeltme
    okumayı iyileştirir, kanıtı güçlendirmez.
    """
    ham = tanima.metin or ""
    if not ham.strip() or sozluk.bos_mu():
        return tanima, []
    parcalar = re.split(r"(\W+)", ham, flags=re.UNICODE)
    degisimler: list[dict] = []
    yeni_parcalar = list(parcalar)
    kelime_sayisi = 0
    for i, parca in enumerate(parcalar):
        if not parca or not _KELIME.fullmatch(parca):
            continue
        kelime_sayisi += 1
        duzeltme = _kelimeyi_duzelt(parca, sozluk)
        if duzeltme is None:
            continue
        # Özgün büyük/küçük harf düzenini kabaca koru.
        if parca[:1].isupper():
            duzeltme = duzeltme[:1].upper() + duzeltme[1:]
        yeni_parcalar[i] = duzeltme
        degisimler.append({"onceki": parca, "sonraki": duzeltme})
    if not degisimler:
        return tanima, []
    if (
        len(degisimler) > 1
        and kelime_sayisi
        and len(degisimler) / kelime_sayisi > AZAMI_DEGISIM_ORANI
    ):
        # Çok fazla sözcük değişiyorsa metin muhtemelen bambaşka; hiç dokunma.
        # Tek sözcüklük düzeltme bu kapıdan muaf: kısa cevaplarda ("mitokondi")
        # oran daima yüksektir ama düzeltme tam da orada gerekiyor.
        return tanima, []
    yeni_metin = "".join(yeni_parcalar)
    alternatifler = list(tanima.alternatifler)
    alternatifler.append({"metin": ham, "kaynak": "ham_ocr", "guven": tanima.guven})
    neden = "; ".join(f"{d['onceki']}→{d['sonraki']}" for d in degisimler[:4])
    yeni = TanimaSonucu(
        metin=yeni_metin,
        guven=tanima.guven,
        alternatifler=alternatifler,
        motor_sonuclari=list(tanima.motor_sonuclari),
        ogretmen_murekkebi_ayrildi=tanima.ogretmen_murekkebi_ayrildi,
        uzlasma_guveni=tanima.uzlasma_guveni,
        bagimsiz_motor_sayisi=tanima.bagimsiz_motor_sayisi,
        karar_marji=tanima.karar_marji,
        belirsizlik_nedeni=(
            f"{tanima.belirsizlik_nedeni} · sözlük düzeltmesi: {neden}".strip(" ·")
        ),
        girdi_kalitesi=tanima.girdi_kalitesi,
        model_surumu=dict(tanima.model_surumu),
        otomatik_kabul=tanima.otomatik_kabul,
    )
    return yeni, degisimler


def baglam_terimleri(sozluk: TerimSozlugu, azami: int = 60) -> list[str]:
    """Motorlara bağlam olarak verilecek en güçlü terimler."""
    sirali = sorted(sozluk.terimler.items(), key=lambda x: (-x[1], x[0]))
    return [terim for terim, _agirlik in sirali[:azami]]
