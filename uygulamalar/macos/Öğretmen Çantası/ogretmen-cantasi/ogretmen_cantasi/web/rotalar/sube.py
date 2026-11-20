"""Şube sayfası ve öğrenci listesi yönetimi."""

from __future__ import annotations

from collections import Counter
from typing import Annotated

from fastapi import FastAPI, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import depo, servis
from ... import yoklama as yk
from ...cikti import grafik
from ...okuma import ogrenci_listesi as liste_okuma
from ...okuma import tablo as tablo_okuma
from ..ortak import (
    TABLO_YUKLEME_SINIRI,
    _onizleme_ac,
    _onizleme_imzala,
    _ortak,
    _revizyon_ilerlet,
    _sinirli_oku,
    _yuklenen_dosya,
    sablonlar,
)


def _not_dagilimi(karneler) -> str:
    """MEB karne dilimlerine göre güncel puan dağılımı grafiği."""
    # Yarı açık aralıklar: 59,5 gibi kesirli ortalamalar dilim arasına düşmesin.
    dilimler = [
        (0, 50, "0–49"),
        (50, 60, "50–59"),
        (60, 70, "60–69"),
        (70, 85, "70–84"),
        (85, 101, "85–100"),
    ]
    sayilar = dict.fromkeys((d[2] for d in dilimler), 0)
    for karne in karneler:
        # En güncel gösterge: yıl sonu, yoksa girilen son dönem ortalaması.
        donem2 = karne.donemler.get(2)
        donem1 = karne.donemler.get(1)
        deger = karne.yil_sonu
        if deger is None and donem2 is not None:
            deger = donem2.ortalama
        if deger is None and donem1 is not None:
            deger = donem1.ortalama
        if deger is None:
            continue
        for alt, ust, etiket in dilimler:
            if alt <= deger < ust:
                sayilar[etiket] += 1
                break
    return grafik.sutun_grafigi(
        [(etiket, adet) for etiket, adet in sayilar.items()],
        baslik="Not dağılımı (MEB puan dilimleri)",
    )


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/sube/{sube_id}", response_class=HTMLResponse)
    def sube_sayfasi(istek: Request, sube_id: int, mesaj: str = ""):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        gerceklesme = servis.sube_gerceklesmesi(baglanti, sube)
        not_dagilimi = _not_dagilimi(servis.karneler(baglanti, sube_id))
        return sablonlar.TemplateResponse(
            istek,
            "sube.html",
            _ortak(
                istek,
                sube=sube,
                ogrenciler=servis.ogrencileri_oku(baglanti, sube_id),
                devamsizlik=servis.devamsizlik_tablosu(baglanti, sube_id),
                gerceklesme=gerceklesme,
                not_dagilimi=not_dagilimi,
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/sube/{sube_id}/ogrenci/yukle")
    async def ogrenci_yukle(istek: Request, sube_id: int, dosya: UploadFile):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        icerik = await _sinirli_oku(dosya, TABLO_YUKLEME_SINIRI)
        try:
            with _yuklenen_dosya(dosya, icerik) as gecici:
                sonuc = liste_okuma.listeyi_coz(tablo_okuma.tabloyu_oku(gecici))
        except tablo_okuma.OkunamadiError as hata:
            return RedirectResponse(f"/sube/{sube_id}?mesaj={hata}", status_code=303)
        if not sonuc.ogrenciler:
            return RedirectResponse(
                f"/sube/{sube_id}?mesaj={' '.join(sonuc.uyarilar)}", status_code=303
            )
        # Önizleme, aktarımın (ogrenci_ekle) eşleştirme tabanının AYNISINI
        # kullanmalı: pasifler dahil ve aynı yk.eslesme_indeksi kuralıyla.
        # Yalnız aktiflere bakınca numarası yeniden kullanılan pasif kayıt
        # "Yeni öğrenci" görünüyor ama aktarım eski kaydı not/yoklama
        # geçmişiyle geri getiriyordu.
        mevcut = servis.ogrencileri_oku(baglanti, sube_id, hepsi=True)
        indeks = yk.eslesme_indeksi((o["numara"], o["ad_soyad"], o) for o in mevcut)
        dosya_numaralari = Counter(
            o.numara.strip() for o in sonuc.ogrenciler if o.numara.strip()
        )
        satirlar: list[dict] = []
        for ogrenci in sonuc.ogrenciler:
            adaylar = yk.aday_bul(indeks, ogrenci.numara, ogrenci.ad_soyad)
            if dosya_numaralari.get(ogrenci.numara.strip(), 0) > 1:
                durum = "Çakışma — dosyada aynı numara birden çok satırda, aktarım reddedilir"
            elif len(adaylar) > 1:
                durum = "Çakışma — aktarım öncesi mevcut kayıtları düzeltin"
            elif adaylar:
                aday = adaylar[0]
                ad_farkli = aday["ad_soyad"] != ogrenci.ad_soyad
                if not aday["aktif"] and ad_farkli:
                    durum = (
                        f"DİKKAT: listeden çıkarılmış '{aday['ad_soyad']}' kaydı bu "
                        "adla geri gelecek ve not/yoklama geçmişini devralacak"
                    )
                elif not aday["aktif"]:
                    durum = "Listeden çıkarılmış kayıt geri gelecek"
                elif ad_farkli:
                    durum = "Adı güncellenecek"
                else:
                    durum = "Zaten kayıtlı"
            else:
                durum = "Yeni öğrenci"
            satirlar.append(
                {"numara": ogrenci.numara, "ad_soyad": ogrenci.ad_soyad, "durum": durum}
            )
        uyusmazlik = bool(sonuc.sube_adi and sonuc.sube_adi != sube.ad)
        paket = _onizleme_imzala(
            istek.app,
            {
                "tur": "ogrenci",
                "sube_id": sube_id,
                "dosya_sube": sonuc.sube_adi,
                # Önizleme hangi liste durumuna bakılarak onaylandıysa onu
                # taşır; aktarım anında liste değiştiyse paket bayattır.
                "revizyon": depo.revizyon_oku(baglanti, f"ogrenciler:{sube_id}"),
                "satirlar": [
                    {"numara": o.numara, "ad_soyad": o.ad_soyad}
                    for o in sonuc.ogrenciler
                ],
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "ogrenci_onizle.html",
            _ortak(
                istek,
                sube=sube,
                satirlar=satirlar,
                dosya_sube=sonuc.sube_adi,
                uyusmazlik=uyusmazlik,
                paket=paket,
                uyarilar=sonuc.uyarilar,
            ),
        )

    @uygulama.post("/sube/{sube_id}/ogrenci/aktar")
    async def ogrenci_aktar(istek: Request, sube_id: int):
        veri = await istek.form()
        paket = _onizleme_ac(istek.app, str(veri.get("paket", "")))
        if paket.get("tur") != "ogrenci" or int(paket.get("sube_id", 0)) != sube_id:
            raise HTTPException(status_code=400, detail="Önizleme hedef şubeyle uyuşmuyor.")
        sube = servis.sube_al(istek.state.db, sube_id)
        dosya_sube = str(paket.get("dosya_sube", ""))
        if dosya_sube and dosya_sube != sube.ad and not veri.get("sube_onay"):
            return PlainTextResponse(
                f"Dosyadaki {dosya_sube} ile hedef {sube.ad} farklı; açık onay gerekiyor.",
                status_code=409,
            )
        baglanti = istek.state.db
        beklenen = paket.get("revizyon")
        if beklenen is not None and int(beklenen) != depo.revizyon_oku(
            baglanti, f"ogrenciler:{sube_id}"
        ):
            return PlainTextResponse(
                "Öğrenci listesi bu önizleme alındıktan sonra değişti; dosyayı "
                "yeniden yükleyip güncel önizlemeyi onaylayın.",
                status_code=409,
            )
        kayitlar = [
            (str(s.get("numara", "")), str(s.get("ad_soyad", "")))
            for s in paket.get("satirlar", [])
        ]
        try:
            # Mutasyon ve sürüm artışı AYNI işlemde: ayrı commit'lenirlerse
            # aktarım başarılı olup sürüm artmayabilir ve iyimser kilit tam
            # koruması gereken senaryoda devre dışı kalırdı.
            with depo.islem(baglanti, immediate=True):
                degisen = servis.ogrenci_ekle(baglanti, sube_id, kayitlar)
                _revizyon_ilerlet(baglanti, f"ogrenciler:{sube_id}", None)
        except ValueError as hata:
            return PlainTextResponse(str(hata), status_code=409)
        return RedirectResponse(
            f"/sube/{sube_id}?mesaj={degisen}+öğrenci+kaydı+eklendi+veya+güncellendi",
            status_code=303,
        )

    @uygulama.post("/sube/{sube_id}/ogrenci/yapistir")
    def ogrenci_yapistir(istek: Request, sube_id: int, metin: Annotated[str, Form()]):
        baglanti = istek.state.db
        sonuc = liste_okuma.metinden_coz(metin)
        with depo.islem(baglanti, immediate=True):
            eklenen = servis.ogrenci_ekle(
                baglanti, sube_id, [(o.numara, o.ad_soyad) for o in sonuc.ogrenciler]
            )
            if eklenen:
                _revizyon_ilerlet(baglanti, f"ogrenciler:{sube_id}", None)
        return RedirectResponse(
            f"/sube/{sube_id}?mesaj={eklenen} öğrenci eklendi", status_code=303
        )

    @uygulama.post("/sube/{sube_id}/ogrenci/{ogrenci_id}/sil")
    def ogrenci_sil(istek: Request, sube_id: int, ogrenci_id: int):
        baglanti = istek.state.db
        with depo.islem(baglanti, immediate=True):
            servis.ogrenci_sil(baglanti, ogrenci_id, sube_id=sube_id)
            _revizyon_ilerlet(baglanti, f"ogrenciler:{sube_id}", None)
        return RedirectResponse(f"/sube/{sube_id}?mesaj=Öğrenci+çıkarıldı", status_code=303)
