"""Kutu puanlamasını depo yazımından ayıran ortak servis.

Webapp'in inceleme akışı, toplu puanlama tezgâhı ve cevap anahtarı etki
önizlemesi aynı puanlama mantığına ihtiyaç duyar; fark yalnız sonucun
depoya yazılıp yazılmadığıdır. ``metni_puanla`` saf hesaplamadır (hiçbir
yan etkisi yoktur), ``kutuyu_yeniden_puanla`` aynı hesabı yapıp sonucu
kutuya işler.
"""

from __future__ import annotations

import json
from pathlib import Path

from .modeller import PuanSonucu, Sinav, TanimaSonucu
from .ogrenme import ogretmen_kalibrasyonu
from .puanlama import puanla

# Yerel RAG indeksi süreç içinde önbelleklenir; her kutu için diskten
# yeniden yüklemek toplu puanlamada baskın maliyet oluyordu.
_RAG_ONBELLEK: dict[str, object] = {}


def rag_onbellegini_temizle() -> None:
    """Referans indeksi değiştiğinde önbelleği düşür (testler ve /referans akışı)."""
    _RAG_ONBELLEK.clear()


def referans_pasajlari_getir(
    indeks_dizini: str | Path | None, soru_metni: str, k: int = 5
) -> list[str] | None:
    """Soruya ilgili ders kitabı pasajlarını döndürür; RAG yoksa ``None``."""
    if not indeks_dizini:
        return None
    from .referans import YerelRAGDeposu

    anahtar = str(indeks_dizini)
    if not YerelRAGDeposu.hazir_mi(indeks_dizini):
        return None
    rag = _RAG_ONBELLEK.get(anahtar)
    if rag is None:
        try:
            rag = YerelRAGDeposu.yukle(indeks_dizini)
        except (OSError, ValueError, json.JSONDecodeError):
            return None
        _RAG_ONBELLEK[anahtar] = rag
    try:
        return [pasaj.metin for pasaj, _skor in rag.ilgili(soru_metni, k=k)]
    except (OSError, ValueError):
        return None


def bilinen_terimleri_getir(
    sinav: Sinav, soru_no: int, indeks_dizini: str | Path | None = None
) -> set[str] | None:
    """Sorunun alanındaki gerçek terimler (rakip terim kapısı için).

    Sözlük anahtarın kendisinden + ders kitabından derleniyor; boşluk
    puanlamasında "cevap iki gerçek terime eşit yakın mı" sorusunu
    cevaplamak için kullanılır.
    """
    try:
        from .terim_sozlugu import sozluk_kur
    except ImportError:  # pragma: no cover - sözlük katmanı opsiyonel
        return None
    anahtar = f"terim::{id(sinav)}::{soru_no}::{indeks_dizini}"
    onbellek = _RAG_ONBELLEK.get(anahtar)
    if onbellek is not None:
        return onbellek if onbellek else None
    try:
        soru = sinav.soru(soru_no)
        sozluk = sozluk_kur(
            sinav,
            soru_no=soru_no,
            referans_pasajlari=referans_pasajlari_getir(
                indeks_dizini, soru.metin
            ),
        )
        terimler = set(getattr(sozluk, "terimler", {}) or {})
    except (KeyError, OSError, ValueError, TypeError):
        terimler = set()
    _RAG_ONBELLEK[anahtar] = terimler
    return terimler or None


def metni_puanla(
    sinav: Sinav,
    soru_no: int,
    metin: str,
    *,
    referans_pasajlari: list[str] | None = None,
    duzeltme_ornekleri: list[dict] | None = None,
    ogrenilmis_kabuller: list[str] | None = None,
    gomlemci=None,
    bilinen_terimler: set[str] | None = None,
    ayar=None,
) -> PuanSonucu:
    """Öğretmenin doğruladığı metni puanlar; depoya hiçbir şey yazmaz.

    ``duzeltme_ornekleri`` verilirse öğretmen kalibrasyon eğilimi yalnız
    açıklama olarak eklenir — puana asla uygulanmaz (mevcut sözleşme).
    ``ayar`` motor etkisi raporunun iki farklı eşik takımını karşılaştırması
    için vardır; verilmezse varsayılan ayarlar kullanılır.
    """
    soru = sinav.soru(soru_no)
    sonuc = puanla(
        TanimaSonucu(metin=metin, guven=1.0),
        soru,
        gomlemci=gomlemci,
        ayar=ayar,
        referans_pasajlari=referans_pasajlari,
        ogrenilmis_kabuller=ogrenilmis_kabuller,
        bilinen_terimler=bilinen_terimler,
    )
    if duzeltme_ornekleri is not None:
        kalibrasyon = ogretmen_kalibrasyonu(
            duzeltme_ornekleri, soru_no=soru.no, max_puan=soru.puan
        )
        if kalibrasyon["uygulanabilir"]:
            sonuc.detaylar.append(
                "Öğretmen düzeltmelerinde tutarlı bir kalibrasyon eğilimi "
                f"görüldü ({kalibrasyon['ornek']} örnek, "
                f"{kalibrasyon['duzeltme']:+g} puan); program puanına "
                "otomatik uygulanmadı."
            )
            sonuc.aciklama = (
                f"{sonuc.aciklama} Program puanı yalnız cevap anahtarı ve "
                "rubrikten üretildi; geçmiş öğretmen puanları sonuca katılmadı."
            ).strip()
    if not metin.strip():
        sonuc.incele = True
        sonuc.guven = 0.0
        sonuc.detaylar.append(
            "Metin boş; el yazısı görüntüsü öğretmen tarafından kontrol edilmeli."
        )
    if soru.anahtar.kaynaklar:
        sonuc.detaylar.append(
            "RAG kaynakları: " + " · ".join(soru.anahtar.kaynaklar[:4])
        )
    sonuc.otomatik_kabul = not sonuc.incele
    sonuc.kabul_nedenleri = (
        ["Öğretmenin doğruladığı transkripsiyon cevap anahtarıyla program tarafından puanlandı."]
        if sonuc.otomatik_kabul
        else ["Düzeltilmiş metin puanlama motorunun inceleme eşiğini geçmedi."]
    )
    return sonuc


def kutuyu_yeniden_puanla(
    depo,
    sinav: Sinav,
    kutu,
    metin: str,
    *,
    referans_indeks_dizini: str | Path | None = None,
    referans_pasajlari: list[str] | None = None,
    gomlemci=None,
) -> PuanSonucu:
    """``metni_puanla`` sonucunu kutuya işler ve sonucu döndürür."""
    soru_no = kutu["soru_no"]
    if referans_pasajlari is None:
        referans_pasajlari = referans_pasajlari_getir(
            referans_indeks_dizini, sinav.soru(soru_no).metin
        )
    sonuc = metni_puanla(
        sinav,
        soru_no,
        metin,
        referans_pasajlari=referans_pasajlari,
        duzeltme_ornekleri=[dict(x) for x in depo.duzeltme_ornekleri(sinav.kimlik)],
        ogrenilmis_kabuller=[
            k["yazim"]
            for k in depo.ogrenilmis_kabuller(
                sinav.kimlik, soru_no, onay_durumu="onayli"
            )
        ],
        gomlemci=gomlemci,
        bilinen_terimler=bilinen_terimleri_getir(
            sinav, soru_no, referans_indeks_dizini
        ),
    )
    depo.kutu_otomatik_puan_guncelle(
        kutu["id"],
        metin=metin,
        puan=sonuc.puan,
        guven=sonuc.guven,
        incele=sonuc.incele,
        detaylar=sonuc.detaylar,
        kararlar=sonuc.kararlar,
        aciklama=sonuc.aciklama,
        risk=sonuc.risk,
        otomatik_kabul=sonuc.otomatik_kabul,
        kabul_nedenleri=sonuc.kabul_nedenleri,
    )
    return sonuc
