"""Yerel kitap RAG'ından kaynaklı ve puanlanabilir cevap anahtarı üretimi."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Callable

from .referans import YerelRAGDeposu
from .yapay_zeka import (
    YapayZekaCevabi,
    YapayZekaHatasi,
    cevap_anahtarlari_uret,
    claude_api_durumu,
)


@dataclass
class RAGAnahtarCevabi:
    soru_no: int
    cevap: str
    rubrik: list[str]
    kaynaklar: list[str]
    uretim_yontemi: str
    puanlanabilir: bool
    uyari: str = ""
    rubrik_es_anlamlilari: list[list[str]] | None = None
    rubrik_kategorileri: list[str] | None = None
    rubrik_celiskileri: list[list[str]] | None = None
    yontem_adimlari: list[str] | None = None
    yaygin_hatalar: list[str] | None = None
    yasak_celiskiler: list[str] | None = None
    kabul_edilen_alternatifler: list[str] | None = None
    birimler: list[str] | None = None
    cevap_turu: str = "acik_uclu"


def _asgari_rubrik_sayisi(soru: str) -> int:
    """Çok parçalı soruda modelin alt maddeleri eksik bırakmasını engelle."""
    alt_madde = len(re.findall(r"(?:^|\s)\d{1,2}\)\s*", soru))
    if alt_madde < 2:
        return 1
    norm = soru.casefold()
    iki_boyut = any(
        istek in norm
        for istek in (
            "katkısını",
            "katkısı",
            "katkılarını",
            "açıklayınız",
            "yorumlayınız",
        )
    )
    return alt_madde * (2 if iki_boyut else 1)


def _numarali_alt_maddeler(soru: str) -> list[str]:
    parcalar = [
        p.strip()
        for p in re.split(r"(?:^|\s)\d{1,2}\)\s*", soru)
        if p.strip()
    ]
    return parcalar[1:] if len(parcalar) >= 3 else []


def _kanitlari_hazirla(
    depo: YerelRAGDeposu,
    sorular: list[tuple[int, str, float]],
) -> tuple[dict[int, list[dict[str, str]]], dict[int, list[str]]]:
    """Her soru için güçlü RAG pasajlarını ve gösterilecek kaynak adlarını hazırla."""
    kanitlar: dict[int, list[dict[str, str]]] = {}
    kaynaklar: dict[int, list[str]] = {}
    for no, soru, _puan in sorular:
        # Uzun ve numaralı sorularda bütün metni tek sorgu yapmak BM25'in yalnız
        # bir alt maddeye yoğunlaşmasına yol açar. Her numaralı ipucunu ayrı
        # arayıp sonuçları birleştirerek çok parçalı rubriğin kanıtını koru.
        parcalar = [
            p.strip()
            for p in re.split(r"(?:^|\s)\d{1,2}\)\s*", soru)
            if len(p.split()) >= 5
        ]
        sorgular = [soru]
        if len(parcalar) > 1:
            sorgular.extend(parcalar[1:13])
        adaylar: list[tuple[object, float]] = []
        for sorgu in sorgular:
            bulunan = depo.ilgili(sorgu, k=3)
            if not bulunan:
                continue
            en_iyi = max(bulunan[0][1], 1e-9)
            adaylar.extend(
                (pasaj, skor / en_iyi)
                for pasaj, skor in bulunan
                if skor >= en_iyi * 0.42
            )
        if not adaylar:
            kanitlar[int(no)] = []
            kaynaklar[int(no)] = []
            continue
        adaylar.sort(key=lambda x: x[1], reverse=True)
        secilen = []
        gorulen = set()
        for pasaj, skor in adaylar:
            kimlik = (pasaj.kaynak, pasaj.sira)
            if kimlik in gorulen:
                continue
            gorulen.add(kimlik)
            secilen.append((pasaj, skor))
            if len(secilen) == 12:
                break
        # En güçlü pasaj bir tablo/etkinlik parçasının sınırında bitiyorsa bitişik
        # pasaj bağlamın devamını (ör. aynı dönüm noktaları listesinin 4–6.
        # maddelerini) taşıyabilir. İlk sonucun iki komşusunu kanıta ekle.
        if secilen:
            ilk_pasaj = secilen[0][0]
            pasaj_haritasi = {
                (p.kaynak, p.sira): p for p in depo.pasajlar
            }
            for komsu_sira in (ilk_pasaj.sira - 1, ilk_pasaj.sira + 1):
                komsu = pasaj_haritasi.get((ilk_pasaj.kaynak, komsu_sira))
                if komsu is None:
                    continue
                kimlik = (komsu.kaynak, komsu.sira)
                if kimlik not in gorulen:
                    gorulen.add(kimlik)
                    secilen.append((komsu, 0.95))
        kanitlar[int(no)] = [
            {
                "etiket": f"S{i}",
                "kaynak": f"{pasaj.kaynak} · pasaj {pasaj.sira + 1}",
                "metin": pasaj.metin[:1400],
            }
            for i, (pasaj, _skor) in enumerate(secilen, 1)
        ]
        kaynaklar[int(no)] = list(
            dict.fromkeys(k["kaynak"] for k in kanitlar[int(no)])
        )
    return kanitlar, kaynaklar


def rag_anahtarlari_uret(
    indeks_dizini: str | Path,
    sorular: list[tuple[int, str, float]],
    *,
    ders: str = "",
    uretici: Callable[..., list[YapayZekaCevabi]] | None = None,
    uretici_hazir: bool | None = None,
    uretim_yontemi: str | None = None,
) -> list[RAGAnahtarCevabi]:
    """Yerel pasajları getir, anahtarı bu kanıtlara bağla ve güvenliğini bildir.

    Üretici kullanılabiliyorsa yalnız yerel RAG kanıtlarından atomik rubrik
    sentezler. Sağlayıcı yoksa kaynak cümlelerinden bir taslak oluşturur ancak
    otomatik puanlamayı kapatır; öğretmen doğrulaması olmadan not uydurmaz.

    ``uretici_hazir`` verilmezse varsayılan üreticinin (Claude API) durumuna
    bakılır; yerel motor gibi farklı bir üretici enjekte edilirken hazırlık
    bilgisi de birlikte verilmelidir — aksi hâlde bulut kapalı diye yerel
    üretici hiç çağrılmaz.
    """
    if not sorular:
        return []
    if not YerelRAGDeposu.hazir_mi(indeks_dizini):
        raise ValueError(
            "Otomatik cevap anahtarı için önce Kitaplar ekranından kaynak yükleyin."
        )

    depo = YerelRAGDeposu.yukle(indeks_dizini)
    kanitlar, kaynaklar = _kanitlari_hazirla(depo, sorular)
    kanitsiz = [int(no) for no, _soru, _puan in sorular if not kanitlar[int(no)]]
    if kanitsiz:
        sirali = ", ".join(str(no) for no in kanitsiz)
        raise ValueError(f"{sirali}. soru için yerel kitaplarda kanıt bulunamadı.")

    uretici = uretici or cevap_anahtarlari_uret
    if uretici_hazir is None:
        uretici_hazir = claude_api_durumu()["hazir"]
    if uretici_hazir:
        sonuc = []
        for soru_kaydi in sorular:
            no = int(soru_kaydi[0])
            soru_metni = str(soru_kaydi[1]).casefold()
            if any(
                isaret in soru_metni
                for isaret in (
                    "metni burada kesiliyor",
                    "soru metni eksik",
                    "[fotoğrafta",
                    "[fotografta",
                )
            ):
                yerel = depo.cevap_uret([soru_kaydi])[0]
                sonuc.append(
                    RAGAnahtarCevabi(
                        soru_no=no,
                        cevap=yerel.cevap,
                        rubrik=yerel.rubrik,
                        kaynaklar=kaynaklar[no],
                        uretim_yontemi="Yerel kitap RAG · eksik soru",
                        puanlanabilir=False,
                        uyari=(
                            "Soru metni fotoğrafta kesilmiş; tam metin girilene "
                            "kadar otomatik cevap anahtarı ve puanlama kapalı."
                        ),
                        rubrik_es_anlamlilari=[[] for _ in yerel.rubrik],
                    )
                )
                continue
            son_hata: YapayZekaHatasi | None = None
            cevap = None
            asgari_rubrik = _asgari_rubrik_sayisi(str(soru_kaydi[1]))
            try:
                alt_maddeler = _numarali_alt_maddeler(str(soru_kaydi[1]))
                if alt_maddeler and asgari_rubrik == 2 * len(alt_maddeler):
                    alt_cevaplar: list[str] = []
                    alt_rubrikler: list[str] = []
                    alt_esler: list[list[str]] = []
                    alt_puanlanabilir = True
                    alt_uyarilar: list[str] = []
                    for sira, alt_madde in enumerate(alt_maddeler, 1):
                        alt_soru = (
                            "Aşağıdaki tarihî ipucunun temsil ettiği bilimsel "
                            "keşfin adını/kişisini ve biyolojiye katkısını ver. "
                            "Tam olarak iki atomik rubrik ölçütü üret: ilk ölçüt "
                            "keşfin kimliği, ikinci ölçüt katkısı olsun. "
                            f"Alt madde: {alt_madde}"
                        )
                        alt_cevap = None
                        for _alt_deneme in range(2):
                            try:
                                uretilen = uretici(
                                    [(no, alt_soru, float(soru_kaydi[2]))],
                                    ders=ders,
                                    kanitlar={no: kanitlar[no]},
                                )
                                aday = next(
                                    (x for x in uretilen if x.soru_no == no),
                                    None,
                                )
                                if aday is not None and len(aday.rubrik) >= 2:
                                    alt_cevap = aday
                                    break
                            except YapayZekaHatasi as exc:
                                son_hata = exc
                        if alt_cevap is None:
                            raise son_hata or YapayZekaHatasi(
                                f"{no}. sorunun {sira}. alt maddesi üretilemedi."
                            )
                        alt_cevaplar.append(f"{sira}) {alt_cevap.cevap}")
                        alt_rubrikler.extend(alt_cevap.rubrik[:2])
                        esler = alt_cevap.rubrik_es_anlamlilari or [
                            [] for _ in alt_cevap.rubrik
                        ]
                        alt_esler.extend(esler[:2])
                        alt_puanlanabilir = bool(
                            alt_puanlanabilir and alt_cevap.puanlanabilir
                        )
                        if alt_cevap.uyari:
                            alt_uyarilar.append(alt_cevap.uyari)
                    cevap = YapayZekaCevabi(
                        soru_no=no,
                        cevap=" ".join(alt_cevaplar),
                        rubrik=alt_rubrikler,
                        puanlanabilir=alt_puanlanabilir,
                        uyari=" ".join(dict.fromkeys(alt_uyarilar)),
                        rubrik_es_anlamlilari=alt_esler,
                    )

                for _deneme in range(4):
                    if cevap is not None:
                        break
                    try:
                        uretilen = uretici(
                            [soru_kaydi],
                            ders=ders,
                            kanitlar={no: kanitlar[no]},
                        )
                        cevap = next(
                            (x for x in uretilen if x.soru_no == no),
                            None,
                        )
                        if cevap is not None and len(cevap.rubrik) >= asgari_rubrik:
                            break
                        cevap = None
                        son_hata = YapayZekaHatasi(
                            f"{no}. soru için en az {asgari_rubrik} atomik "
                            "rubrik ölçütü gerekli."
                        )
                    except YapayZekaHatasi as exc:
                        son_hata = exc
                if cevap is None:
                    raise son_hata or YapayZekaHatasi(
                        f"{no}. soru için anahtar üretilmedi."
                    )
                puanlanabilir = bool(
                    cevap.puanlanabilir and cevap.rubrik and kaynaklar[no]
                )
                uyari = cevap.uyari
                if not puanlanabilir and not uyari:
                    uyari = "RAG kanıtı otomatik puanlama için yeterli bulunmadı."
                sonuc.append(
                    RAGAnahtarCevabi(
                        soru_no=no,
                        cevap=cevap.cevap,
                        rubrik=cevap.rubrik,
                        kaynaklar=kaynaklar[no],
                        uretim_yontemi=(
                            uretim_yontemi
                            or "Yerel kitap RAG + kaynakla sınırlandırılmış model"
                        ),
                        puanlanabilir=puanlanabilir,
                        uyari=uyari,
                        rubrik_es_anlamlilari=(
                            cevap.rubrik_es_anlamlilari
                            or [[] for _ in cevap.rubrik]
                        ),
                        rubrik_kategorileri=(
                            cevap.rubrik_kategorileri
                            or ["kavram" for _ in cevap.rubrik]
                        ),
                        rubrik_celiskileri=(
                            cevap.rubrik_celiskileri
                            or [[] for _ in cevap.rubrik]
                        ),
                        yontem_adimlari=cevap.yontem_adimlari or [],
                        yaygin_hatalar=cevap.yaygin_hatalar or [],
                        yasak_celiskiler=cevap.yasak_celiskiler or [],
                        kabul_edilen_alternatifler=(
                            cevap.kabul_edilen_alternatifler or []
                        ),
                        birimler=cevap.birimler or [],
                        cevap_turu=cevap.cevap_turu,
                    )
                )
            except YapayZekaHatasi:
                yerel = depo.cevap_uret([soru_kaydi])[0]
                sonuc.append(
                    RAGAnahtarCevabi(
                        soru_no=no,
                        cevap=yerel.cevap,
                        rubrik=yerel.rubrik,
                        kaynaklar=kaynaklar[no],
                        uretim_yontemi="Yerel kitap RAG · çıkarımsal taslak",
                        puanlanabilir=False,
                        uyari=(
                            "Kaynaklar bulundu ancak atomik rubrik üreticisi "
                            "bu soru için kullanılamadı; öğretmen doğrulayana "
                            "kadar otomatik puanlama kapalı."
                        ),
                        rubrik_es_anlamlilari=[[] for _ in yerel.rubrik],
                    )
                )
        return sonuc

    yerel = {x.soru_no: x for x in depo.cevap_uret(sorular)}
    return [
        RAGAnahtarCevabi(
            soru_no=int(no),
            cevap=yerel[int(no)].cevap,
            rubrik=yerel[int(no)].rubrik,
            kaynaklar=kaynaklar[int(no)],
            uretim_yontemi="Yerel kitap RAG · çıkarımsal taslak",
            puanlanabilir=False,
            uyari=(
                "Kaynaklar bulundu ancak atomik rubrik üreticisi kullanılamadı; "
                "öğretmen doğrulayana kadar otomatik puanlama kapalı."
            ),
            rubrik_es_anlamlilari=[[] for _ in yerel[int(no)].rubrik],
        )
        for no, _soru, _puan in sorular
    ]
