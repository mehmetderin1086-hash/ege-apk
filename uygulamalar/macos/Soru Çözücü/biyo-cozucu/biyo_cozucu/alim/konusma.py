"""Konuşma dökümünden soru-çözüm çıkarımı (model birincil, kural yedek).

`bolutleme.adaylari_cikar` kitap düzenine benzetilmiş metinde çalışır;
serbest konuşmada ("şimdi arkadaşlar burada mayozu düşünelim…") soru
sınırlarını kaçırır. Bu modül dökümü zaman pencerelerine bölüp her pencereyi
dil modeline verir. Kural yolu ÖN FİLTRE DEĞİL, yedektir: regex'in kaçırdığı
soru modele hiç ulaşamazdı.

Model çıktısı ham kabul edilmez — her aday dökümle örtüşme (dayanak) puanından
geçer ve bilinen bozulma biçimleri (uydurulmuş şık, yarım şık listesi, ezberden
tamamlanmış soru) güven düşürülerek işaretlenir. Eleme yok, işaretleme var:
nihai karar onay kuyruğunda insanındır.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass

from rapidfuzz import fuzz, process

from ..metin import imza, sadelestir
from .bolutleme import SoruAdayi, adaylari_cikar
from .cikarim import Kaynak, Parca

# Gerçek bir soru çözümü videosunda (221 bölüt / 8336 karakter) ölçüldü;
# ölçüt "filtrelerden uyarısız geçen aday sayısı" ve ortalama güven:
#
#   boyut  pencere  aday  temiz  ort.güven  süre
#    1200        9     8      1       0,43  77 sn
#    1800        6     7      1       0,43  60 sn
#    2600        4     4      0       0,35  42 sn
#    3600        3     3      2       0,72  26 sn   ← tepe (iki koşuda da)
#    4500        2     2      0       0,32  22 sn
#    6500        2     2      1       0,60  28 sn
#
# Sezgiye aykırı ama mekanizması açık: küçük pencere soruyu şıklarından ve
# çözümünden ayırıyor, model de eksik bağlamı çevredeki konuşmayla tamamlayıp
# sahte şık üretiyor. Büyük pencere daha az ama daha temiz aday veriyor ve
# daha az LLM çağrısı olduğu için daha hızlı. Tavan var: tüm döküm tek
# pencereye sığdırıldığında (8336 karakter) aday sayısı sıfıra düşüyor.
# Tek videoluk ölçüm — ikinci bir video eklendiğinde yeniden bakılmalı.
PENCERE_KARAKTERI = 3600
# Örtüşme, pencere sınırına denk gelen sorunun iki parçada da yarım kalmasını
# önler; sınırda tam çıkan kopya `_yinelenenleri_ele` ile düşer. Yukarıdaki
# ölçüm bu değerle yapıldı; değiştirmek ölçümü geçersiz kılar.
ORTUSME_KARAKTERI = 250
# Bunun altındaki örtüşme "model bunu dökümden değil ezberinden yazdı" işareti.
ASGARI_DAYANAK = 0.60
# Tek sözcük eşleşmesinde bulanıklık payı: whisper'ın terim bozmalarını
# ("mayoz" → "may oz") tolere eder ama farklı sözcükleri eşleştirmez.
BULANIK_ESLESME_ESIGI = 85

_SIK_HARFLERI = {"A", "B", "C", "D", "E"}

# Konuşma artığı işaretleri. Gerçek koşuda ölçüldü: anlatıcı şıkları tek tek
# okumadığında model, dökümdeki sohbet cümlelerini şık diye kaydediyor
# ("A) Evet hocam.", "B) Değil mi?"). Dayanak puanı bunu YAKALAYAMAZ — o
# cümleler gerçekten dökümde geçiyor; yakalanması gereken şey metnin sınav
# şıkkı değil konuşma olduğu.
# Sınav kökünün soru sözcükleri. Soru işareti yoksa bunlardan biri
# bulunmalı: "…aşağıdakilerden hangisidir." gibi noktayla biten gerçek
# kökler de böylece geçiyor.
_SORU_SOZCUKLERI = re.compile(
    r"\b(hangi\w*|kaç\w*|ne\w*|nasıl|niçin|neden|nerede|kim\w*|"
    r"yanlıştır|doğrudur|değildir|söylenebilir|beklenir|olabilir)\b",
    re.IGNORECASE,
)

_SOHBET_ISARETLERI = re.compile(
    r"\b(hocam|arkadaşlar|çocuklar|evet|tamam\s*mı|peki|bakın|bakalım|"
    r"unutmayın|unutmayalım|dikkat\s+edin|görüyorsunuz|demiştik|dedik|"
    r"söylemiştim|değil\s*mi|değil\s*midir|geçelim|başlayalım)\b",
    re.IGNORECASE,
)


@dataclass
class Pencere:
    """Dökümün, parça sınırlarına hizalı bir dilimi."""

    metin: str
    baslangic_sn: float = 0.0
    bitis_sn: float = 0.0

    def konum(self) -> str:
        toplam = int(self.baslangic_sn)
        return f"{toplam // 60:02d}:{toplam % 60:02d}"


def pencerele(
    parcalar: list[Parca],
    *,
    boyut: int = PENCERE_KARAKTERI,
    ortusme: int = ORTUSME_KARAKTERI,
) -> list[Pencere]:
    """Zaman damgalı parçaları örtüşmeli metin pencerelerine böler.

    Kesim her zaman PARÇA sınırında: whisper bölütleri zaten cümle/soluk
    sınırlarına yakındır ve karakter ortasından kesmek modele yarım sözcük
    gösterirdi.
    """
    # Sıfır/negatif boyut `_metni_dilimle`yi sonsuz döngüye sokardı: video
    # indirilip yazıya döküldükten SONRA kilitlenmek, en pahalı hata anı.
    boyut = max(1, int(boyut))
    ortusme = max(0, min(int(ortusme), boyut - 1))

    dolu = [p for p in parcalar if p.metin.strip()]
    if not dolu:
        return []
    dolu = _buyuk_parcalari_bol(dolu, boyut)

    pencereler: list[Pencere] = []
    mevcut: list[Parca] = []
    uzunluk = 0
    for parca in dolu:
        # Denetim EKLEMEDEN önce: sonradan bakılırsa pencere hedefi aşan son
        # parçayı da içine alır ve boy hedefin iki katına çıkabilir (ölçüldü:
        # 1800 hedefte 3553 karakter).
        if mevcut and uzunluk + len(parca.metin) > boyut:
            pencereler.append(_pencere_kur(mevcut))
            mevcut, uzunluk = _ortusme_kuyrugu(mevcut, ortusme)
        mevcut.append(parca)
        uzunluk += len(parca.metin) + 1
    if mevcut:
        pencereler.append(_pencere_kur(mevcut))
    return pencereler


def _ortusme_kuyrugu(mevcut: list[Parca], ortusme: int) -> tuple[list[Parca], int]:
    """Kapanan pencerenin sonundan, bir sonrakine taşınacak bağlam dilimi.

    Örtüşme, pencere sınırına denk gelen sorunun iki pencerede de yarım
    kalmasını önler.
    """
    kuyruk: list[Parca] = []
    kuyruk_uzunlugu = 0
    for geri in reversed(mevcut):
        if kuyruk_uzunlugu + len(geri.metin) > ortusme:
            if not kuyruk:
                # Tek parça bile örtüşme bütçesini aşıyor: tamamını taşımak
                # sonraki pencereyi şişirirdi; yalnız kuyruğundan bir dilim
                # taşınır — bağlam korunur, boy patlamaz.
                kuyruk.insert(0, _parca_kuyrugu(geri, ortusme))
                kuyruk_uzunlugu = len(kuyruk[0].metin) + 1
            break
        kuyruk.insert(0, geri)
        kuyruk_uzunlugu += len(geri.metin) + 1
    return kuyruk, kuyruk_uzunlugu


def _buyuk_parcalari_bol(parcalar: list[Parca], boyut: int) -> list[Parca]:
    """Pencereden büyük tek parçaları satır/cümle sınırından böler.

    Gerçek koşuda görüldü: whisper-server bazı yapılandırmalarda 9 dakikalık
    bir videoyu TEK bölüt olarak döndürüyor. Pencereleme yalnız parça
    sınırında kestiği için o durumda tüm döküm tek dev pencere oluyor, model
    de bu bağlamda hiçbir soru çıkaramıyordu.

    Bölünen alt parçaların zaman damgası, parçanın süresi karakter sayısına
    orantılanarak dağıtılır — konuşma hızı sabit varsayılır. Kaba ama tek
    parçanın başlangıç saniyesini tüm videoya yaymaktan iyi.
    """
    sonuc: list[Parca] = []
    for parca in parcalar:
        metin = parca.metin
        if len(metin) <= boyut:
            sonuc.append(parca)
            continue
        bas_sn = parca.baslangic_sn or 0.0
        bitis_sn = parca.bitis_sn if parca.bitis_sn is not None else bas_sn
        sure = max(0.0, bitis_sn - bas_sn)
        for bas, son, dilim in _metni_dilimle(metin, boyut):
            if sure <= 0:
                # Süre bilinmiyor (whisper `segments` döndürmediğinde tek
                # parça 0→0 gelir). Hepsine 0 yazmak "gerçekten 0. saniyede"
                # ile "bilinmiyor"u ayırt edilemez kılar ve onay arayüzünde
                # her satıra çalışmayan bir 00:00 bağlantısı koyar.
                sonuc.append(Parca(metin=dilim))
                continue
            sonuc.append(
                Parca(
                    metin=dilim,
                    baslangic_sn=bas_sn + sure * (bas / len(metin)),
                    bitis_sn=bas_sn + sure * (son / len(metin)),
                )
            )
    return sonuc


def _parca_kuyrugu(parca: Parca, uzunluk: int) -> Parca:
    """Parçanın son `uzunluk` karakterini taşıyan kopya (örtüşme dilimi)."""
    kuyruk_metni = parca.metin[-uzunluk:].lstrip()
    bas_sn = parca.baslangic_sn or 0.0
    bitis_sn = parca.bitis_sn if parca.bitis_sn is not None else bas_sn
    oran = 1.0 - (len(kuyruk_metni) / max(1, len(parca.metin)))
    return Parca(
        metin=kuyruk_metni,
        baslangic_sn=bas_sn + (bitis_sn - bas_sn) * oran,
        bitis_sn=bitis_sn,
    )


def _metni_dilimle(metin: str, boyut: int) -> list[tuple[int, int, str]]:
    """Metni (başlangıç, bitiş, dilim) üçlülerine böler; satır/boşluk tercihli."""
    # Koruma burada da duruyor, yalnız çağıranda değil: sıfır/negatif boyut
    # bu döngüyü ilerletmez ve süreç video indirildikten SONRA kilitlenirdi.
    boyut = max(1, int(boyut))
    dilimler: list[tuple[int, int, str]] = []
    bas = 0
    while bas < len(metin):
        son = min(bas + boyut, len(metin))
        if son < len(metin):
            # Sözcük ortasından kesmemek için geriye doğru en yakın sınırı ara.
            for ayrac in ("\n", ". ", " "):
                kesim = metin.rfind(ayrac, bas + boyut // 2, son)
                if kesim > bas:
                    son = kesim + len(ayrac)
                    break
        dilim = metin[bas:son].strip()
        if dilim:
            dilimler.append((bas, son, dilim))
        bas = son
    return dilimler


def _pencere_kur(parcalar: list[Parca]) -> Pencere:
    return Pencere(
        metin="\n".join(p.metin for p in parcalar),
        baslangic_sn=parcalar[0].baslangic_sn or 0.0,
        bitis_sn=parcalar[-1].bitis_sn or 0.0,
    )


def sorulari_cikar(
    kaynak: Kaynak,
    motor=None,
    *,
    boyut: int = PENCERE_KARAKTERI,
    ortusme: int = ORTUSME_KARAKTERI,
    ilerleme: Callable[[int, int], None] | None = None,
) -> tuple[list[SoruAdayi], str]:
    """Dökümden soru adayları çıkarır → (adaylar, yöntem).

    Yöntem ``model`` ya da ``kural``: kuyruk kaydına yazılır ki onaylayan
    kişi adayın nereden geldiğini bilsin. Motor verilmişse ama hiç aday
    bulamamışsa kural yoluna düşülür — boş dönmek yerine zayıf adaylar
    göstermek, kullanıcıya en azından elle düzeltme şansı verir.
    """
    if motor is not None:
        adaylar = _model_ile_cikar(
            kaynak, motor, boyut=boyut, ortusme=ortusme, ilerleme=ilerleme
        )
        if adaylar:
            return adaylar, "model"
    return adaylari_cikar(kaynak.metin, kaynak=kaynak), "kural"


def _model_ile_cikar(
    kaynak: Kaynak,
    motor,
    *,
    boyut: int,
    ortusme: int,
    ilerleme: Callable[[int, int], None] | None,
) -> list[SoruAdayi]:
    from ..istemler import konusma_cikarim_mesajlari
    from ..motor.temel import MotorHatasi, json_ayikla

    pencereler = pencerele(kaynak.parcalar, boyut=boyut, ortusme=ortusme)
    adaylar: list[SoruAdayi] = []
    for sira, pencere in enumerate(pencereler, start=1):
        if ilerleme is not None:
            ilerleme(sira, len(pencereler))
        mesajlar = konusma_cikarim_mesajlari(
            pencere.metin, kaynak_adi=kaynak.ad, konum=pencere.konum()
        )
        try:
            yanit = motor.uret(mesajlar, sicaklik=0.1, azami_token=2048)
            veri = json_ayikla(yanit)
        except (MotorHatasi, ValueError):
            # Tek bozuk pencere koca videoyu düşürmemeli; kalanlar işlenir.
            continue
        adaylar.extend(_yaniti_adaylara_cevir(veri, pencere))
    return _yinelenenleri_ele(adaylar)


def _yaniti_adaylara_cevir(veri: dict, pencere: Pencere) -> list[SoruAdayi]:
    """Model yanıtını doğrulanmış adaylara çevirir.

    Buradaki düzeltmeler ELEMEZ, işaretler: yanlış pozitifin bedeli onay
    kuyruğunda bir satır, yanlış negatifin bedeli kaybolmuş bir sorudur.
    """
    ham_sorular = veri.get("sorular")
    if not isinstance(ham_sorular, list):
        return []

    adaylar: list[SoruAdayi] = []
    for kayit in ham_sorular:
        if not isinstance(kayit, dict):
            continue
        soru = str(kayit.get("soru") or "").strip()
        if not soru:
            continue
        cozum = str(kayit.get("cozum") or "").strip()
        cevap = str(kayit.get("cevap") or "").strip()
        uyarilar: list[str] = []
        guven = _guveni_oku(kayit.get("guven"))

        secenekler = _secenekleri_oku(kayit.get("secenekler"))
        if 0 < len(secenekler) < 3:
            # 1-2 şık ya yarım okunmuş ya uydurulmuştur; ikisinde de şıksız
            # (açık uçlu) kayıt daha dürüst.
            secenekler = {}
            uyarilar.append("eksik_secenek")
            guven = min(guven, 0.5)

        if secenekler and _bozuk_sik_kumesi_mi(secenekler, soru):
            secenekler = {}
            uyarilar.append("bozuk_sik_kumesi")
            guven = min(guven, 0.35)

        if secenekler and _sohbet_sikki_var_mi(secenekler):
            # Şık kümesinin TAMAMI düşürülür, kirli olanlar ayıklanmaz:
            # eksik bir şık listesi yanlış bir cevap anahtarı üretir ve
            # few-shot örneği olarak modele yanlış biçim öğretir.
            secenekler = {}
            uyarilar.append("sohbet_sikki")
            guven = min(guven, 0.35)

        if not secenekler and cevap.upper() in _SIK_HARFLERI and len(cevap) == 1:
            # Şıksız "C" cevabı few-shot'a girerse modele zararlı bir davranış
            # öğretir; harf nota düşülür, cevap boşaltılır.
            uyarilar.append(f"sik_okunmadi:{cevap.upper()}")
            cevap = ""
            guven = min(guven, 0.4)

        if bool(kayit.get("eksik")):
            uyarilar.append("soru_metni_eksik")
            guven = min(guven, 0.3)

        if not _soru_cumlesi_mi(soru):
            uyarilar.append("soru_cumlesi_degil")
            guven = min(guven, 0.35)

        if _SOHBET_ISARETLERI.search(soru):
            # "Anafaz 1 ile Anafaz 2 zaten aynı değil midir?" — öğrencinin
            # ara sorusu, çözülen sınav sorusu değil.
            uyarilar.append("sohbet_sorusu")
            guven = min(guven, 0.3)

        dayanak = _dayanak_puani(soru, pencere.metin)
        if dayanak < ASGARI_DAYANAK:
            uyarilar.append("dokumde_dayanagi_zayif")
            guven = min(guven, 0.35)

        # Çözüm de dökümden gelmeli: model burada kendi ders kitabı bilgisini
        # ("Temel bilgi: Mayoz bir DNA eşlenmesini izleyen…") videonun
        # anlatımı diye yazmaya eğilimli ve soru dayanaklı olduğu için bu
        # tek başına yakalanmıyordu.
        if cozum and _dayanak_puani(cozum, pencere.metin) < ASGARI_DAYANAK:
            uyarilar.append("cozum_dokumde_yok")
            guven = min(guven, 0.4)

        adaylar.append(
            SoruAdayi(
                soru=soru,
                cozum=cozum,
                cevap=cevap,
                secenekler=secenekler,
                konum=pencere.konum(),
                guven=guven,
                uyarilar=uyarilar,
                baslangic_sn=pencere.baslangic_sn,
                dayanak=dayanak,
            )
        )
    return adaylar


def _secenekleri_oku(ham) -> dict[str, str]:
    if not isinstance(ham, dict):
        return {}
    secenekler: dict[str, str] = {}
    for harf, metin in ham.items():
        anahtar = str(harf).strip().upper()
        deger = str(metin or "").strip()
        if anahtar in _SIK_HARFLERI and deger:
            secenekler[anahtar] = deger
    return secenekler


def _soru_cumlesi_mi(soru: str) -> bool:
    """Metin gerçekten bir soru kökü mü?

    Ölçüldü: model, anlatının düz bir cümlesini ("Soğanın yumrusundan yeni
    soğan oluşması.") soru diye kaydedip çevresindeki konuşmayı şık yapıyor.
    Bu kayıt dayanak, yinelenen şık ve konuşma artığı denetimlerinin
    hepsinden geçiyordu. Gerçek sınav kökü ya soru işaretiyle biter ya da
    bir soru sözcüğü taşır.
    """
    if "?" in soru:
        return True
    return bool(_SORU_SOZCUKLERI.search(soru))


def _bozuk_sik_kumesi_mi(secenekler: dict[str, str], soru: str) -> bool:
    """Şık kümesi kendi içinde çökmüş mü?

    10 saatlik bir dersin çıkarımında ölçüldü: anlatıcı şıkları okumadığında
    model listeyi ya AYNI cümleyi tekrarlayarak ("B, C, D: Vücudu
    savunmasıdır") ya da SORUNUN kendi metnini şık yaparak dolduruyor. İkisi
    de dökümde geçtiği için dayanak puanı 1,00 çıkıyor ve konuşma artığı
    dedektörüne de takılmıyorlardı — uyarısız, 0,90 güvenli çöp kayıtlar.
    """
    degerler = [sadelestir(m) for m in secenekler.values() if m.strip()]
    if len(degerler) < 2:
        return False
    # Yinelenen şık: gerçek bir sınav sorusunda iki şık aynı olmaz.
    if len(set(degerler)) < len(degerler):
        return True
    # Sorunun metnini şık diye geri yazma.
    sade_soru = sadelestir(soru)
    return any(d and len(d) > 20 and d in sade_soru for d in degerler)


def _sohbet_sikki_var_mi(secenekler: dict[str, str]) -> bool:
    """Şık kümesinde konuşma artığı var mı?

    Tek bir kirli şık yeter: model şıkları dökümden okuyamadığında listeyi
    çevredeki cümlelerle dolduruyor, yani biri sohbetse gerisine de
    güvenilemez. Soru işaretiyle biten şık da aynı işaret — sınav şıkları
    soru değil ifadedir.
    """
    return any(
        _SOHBET_ISARETLERI.search(metin) or metin.rstrip().endswith("?")
        for metin in secenekler.values()
    )


def _guveni_oku(ham) -> float:
    try:
        deger = float(ham)
    except (TypeError, ValueError):
        return 0.5
    return min(max(deger, 0.0), 1.0)


def _dayanak_puani(soru: str, pencere_metni: str) -> float:
    """Aday sorunun sözcüklerinin ne kadarı dökümde geçiyor (0-1).

    Hazır `partial_token_set_ratio` denendi ve elendi: kesişim boş olmadığı
    sürece 100 döndürüyor, yani dökümle tek ortak sözcüğü olan uydurma bir
    soru da tam puan alıyordu. Ölçülmesi gereken şey benzerlik değil KAPSAMA:
    sorunun sözcüklerinin kaçının karşılığı dökümde var.

    Eşleşme birebir değil bulanık — whisper Türkçe terimleri bozabiliyor
    ("mayoz" → "may oz") ve birebir eşleşme bu bozulmaları dayanaksızlık
    sanardı.
    """
    if not soru or not pencere_metni:
        return 0.0
    # 2 harften kısa belirteçler ("ve", "bu") ayırt edici değil, kapsama
    # oranını yapay olarak yükseltirdi.
    soru_belirtecleri = [b for b in sadelestir(soru).split() if len(b) > 2]
    pencere_belirtecleri = [b for b in sadelestir(pencere_metni).split() if len(b) > 2]
    if not soru_belirtecleri or not pencere_belirtecleri:
        return 0.0
    havuz = set(pencere_belirtecleri)
    eslesen = 0
    for belirtec in soru_belirtecleri:
        if belirtec in havuz or process.extractOne(
            belirtec, havuz, scorer=fuzz.ratio, score_cutoff=BULANIK_ESLESME_ESIGI
        ):
            eslesen += 1
    return eslesen / len(soru_belirtecleri)


def _yinelenenleri_ele(adaylar: list[SoruAdayi]) -> list[SoruAdayi]:
    """Pencere örtüşmesinden doğan kopyaları eler; yüksek güvenli kalır."""
    en_iyi: dict[str, SoruAdayi] = {}
    sira: list[str] = []
    for aday in adaylar:
        anahtar = imza(aday.soru)
        onceki = en_iyi.get(anahtar)
        if onceki is None:
            en_iyi[anahtar] = aday
            sira.append(anahtar)
        elif aday.guven > onceki.guven:
            en_iyi[anahtar] = aday
    return [en_iyi[anahtar] for anahtar in sira]
