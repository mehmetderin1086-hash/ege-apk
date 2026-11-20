"""Referans örnek yönetimi rotaları (ekleme, toplu yapıştırma, düzenleme)."""

from __future__ import annotations

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ..hafiza.etiketleme import bloklari_ayristir, kural_ile_etiketle
from ..modeller import CEVAP_TURLERI, CEVAP_TURU_ADLARI, COZUM_TURLERI, Ornek
from ..soru_turu import cevap_turunu_cikar
from .cozum import _secenekleri_ayristir
from .durum import Uygulama
from .yardimcilar import hata_yaniti, sayfa_araligi

SAYFA_BOYU = 50


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.get("/ornekler", response_class=HTMLResponse)
    def ornek_listesi(request: Request, ara: str = "", tur: str = "", sayfa: int = 1):
        toplam = durum.depo.ornek_say(ara=ara, cozum_turu=tur)
        aralik = sayfa_araligi(sayfa, SAYFA_BOYU, toplam)
        ornekler = durum.depo.ornekler(
            ara=ara, cozum_turu=tur, limit=aralik["boyut"], offset=aralik["offset"]
        )
        return sablon.TemplateResponse(
            request,
            "ornekler.html",
            {
                "durum": durum.durum(),
                "etkin": "ornekler",
                "ornekler": ornekler,
                "ara": ara,
                "secili_tur": tur,
                "turler": COZUM_TURLERI,
                "sayfalama": aralik,
                "temel_yol": "/ornekler",
                "sorgu": {"ara": ara, "tur": tur},
            },
        )

    @yonlendirici.get("/ornek/yeni", response_class=HTMLResponse)
    def yeni_form(request: Request):
        return sablon.TemplateResponse(
            request,
            "ornek_duzenle.html",
            {"durum": durum.durum(), "etkin": "ornekler", "ornek": None,
             "turler": COZUM_TURLERI, "cevap_turleri": CEVAP_TURLERI,
             "tur_adlari": CEVAP_TURU_ADLARI},
        )

    @yonlendirici.post("/ornek/yeni")
    def yeni_kaydet(
        request: Request,
        soru: str = Form(...),
        cozum: str = Form(...),
        cevap: str = Form(""),
        secenekler: str = Form(""),
        konu: str = Form(""),
        cozum_turu: str = Form(""),
        cevap_turu: str = Form(""),
        kaynak: str = Form(""),
    ):
        soru, cozum = soru.strip(), cozum.strip()
        if not soru or not cozum:
            return hata_yaniti(
                sablon, durum, request,
                "Soru ve çözüm alanları zorunludur.",
                baslik="Örnek kaydedilemedi", geri="/ornek/yeni",
            )
        kural_konu, kural_tur = kural_ile_etiketle(soru, cozum)
        secenek_sozlugu = _secenekleri_ayristir(secenekler)
        ornek = Ornek(
            soru=soru,
            cozum=cozum,
            cevap=cevap.strip(),
            secenekler=secenek_sozlugu,
            # Tür artık yalnız "şık var mı" ile değil, soru metninden de
            # çıkarılıyor: doğru/yanlış, boşluk doldurma, eşleştirme ve
            # sıralama soruları sessizce açık uçlu sayılıyordu.
            cevap_turu=cevap_turu or cevap_turunu_cikar(soru, secenek_sozlugu, cozum),
            konu=konu.strip() or kural_konu,
            cozum_turu=cozum_turu or kural_tur,
            kaynak=kaynak.strip(),
            etiket_kaynagi="elle" if cozum_turu else "kural",
        )
        try:
            kimlik = durum.depo.ornek_ekle(ornek)
        except ValueError as exc:
            return hata_yaniti(
                sablon, durum, request, str(exc), kod=409,
                baslik="Bu soru zaten hafızada",
                oneri="Var olan örneği açıp düzenleyebilir ya da farklı bir soru girebilirsiniz.",
                geri="/ornekler",
            )
        ornek.id = kimlik
        durum.ornegi_indeksle(ornek)
        return RedirectResponse(f"/ornek/{kimlik}", status_code=303)

    @yonlendirici.get("/ornek/toplu", response_class=HTMLResponse)
    def toplu_form(request: Request):
        return sablon.TemplateResponse(
            request, "ornek_toplu.html",
            {"durum": durum.durum(), "etkin": "toplu", "sonuc": None},
        )

    @yonlendirici.post("/ornek/toplu", response_class=HTMLResponse)
    def toplu_kaydet(request: Request, metin: str = Form(...), uzerine_yaz: str = Form("")):
        kayitlar = bloklari_ayristir(metin)
        eklenen = guncellenen = atlanan = 0
        hatalar: list[str] = []
        for kayit in kayitlar:
            konu, tur = kural_ile_etiketle(str(kayit["soru"]), str(kayit["cozum"]))
            ornek = Ornek(
                soru=str(kayit["soru"]),
                cozum=str(kayit["cozum"]),
                cevap=str(kayit["cevap"]),
                secenekler=dict(kayit["secenekler"]),  # type: ignore[arg-type]
                cevap_turu=str(kayit["cevap_turu"]),
                konu=konu,
                cozum_turu=tur,
                etiket_kaynagi="kural",
            )
            try:
                onceki = durum.depo.ornek_sayisi()
                durum.depo.ornek_ekle(ornek, uzerine_yaz=bool(uzerine_yaz))
                if durum.depo.ornek_sayisi() > onceki:
                    eklenen += 1
                else:
                    guncellenen += 1
            except ValueError as exc:
                atlanan += 1
                hatalar.append(str(exc))
        if eklenen or guncellenen:
            durum.indeksi_yenile()
        return sablon.TemplateResponse(
            request,
            "ornek_toplu.html",
            {
                "durum": durum.durum(),
                "etkin": "toplu",
                "sonuc": {
                    "bulunan": len(kayitlar),
                    "eklenen": eklenen,
                    "guncellenen": guncellenen,
                    "atlanan": atlanan,
                    "hatalar": hatalar[:10],
                },
            },
        )

    @yonlendirici.get("/ornek/{ornek_id}", response_class=HTMLResponse)
    def ornek_goster(request: Request, ornek_id: int):
        ornek = durum.depo.ornek(ornek_id)
        if ornek is None:
            return hata_yaniti(
                sablon, durum, request,
                f"#{ornek_id} numaralı örnek bulunamadı.",
                kod=404, baslik="Örnek bulunamadı", geri="/ornekler",
            )
        return sablon.TemplateResponse(
            request,
            "ornek_duzenle.html",
            {"durum": durum.durum(), "etkin": "ornekler", "ornek": ornek,
             "turler": COZUM_TURLERI, "cevap_turleri": CEVAP_TURLERI,
             "tur_adlari": CEVAP_TURU_ADLARI},
        )

    @yonlendirici.post("/ornek/{ornek_id}")
    def ornek_guncelle(
        request: Request,
        ornek_id: int,
        soru: str = Form(...),
        cozum: str = Form(...),
        cevap: str = Form(""),
        secenekler: str = Form(""),
        konu: str = Form(""),
        cozum_turu: str = Form(""),
        cevap_turu: str = Form(""),
        kaynak: str = Form(""),
    ):
        mevcut = durum.depo.ornek(ornek_id)
        if mevcut is None:
            return hata_yaniti(
                sablon, durum, request,
                f"#{ornek_id} numaralı örnek bulunamadı.",
                kod=404, baslik="Örnek bulunamadı", geri="/ornekler",
            )
        if not soru.strip() or not cozum.strip():
            return hata_yaniti(
                sablon, durum, request,
                "Soru ve çözüm alanları zorunludur.",
                baslik="Örnek güncellenemedi", geri=f"/ornek/{ornek_id}",
            )
        mevcut.soru = soru.strip()
        mevcut.cozum = cozum.strip()
        mevcut.cevap = cevap.strip()
        mevcut.secenekler = _secenekleri_ayristir(secenekler)
        # Cevap türü her iki yönde de yeniden hesaplanır: şıklar silindiğinde
        # örnek "çoktan seçmeli ama şıksız" durumunda kalmamalı.
        mevcut.cevap_turu = cevap_turu or cevap_turunu_cikar(
            mevcut.soru, mevcut.secenekler, mevcut.cozum
        )
        mevcut.konu = konu.strip()
        mevcut.cozum_turu = cozum_turu or mevcut.cozum_turu
        mevcut.kaynak = kaynak.strip()
        mevcut.etiket_kaynagi = "elle"
        try:
            durum.depo.ornek_guncelle(mevcut)
        except ValueError as exc:
            # Soru metnini başka bir örneğinkiyle aynı yapmak `soru_imza`
            # UNIQUE kısıtını düşürüyor. Yakalanmadığında bu HTTP 500'e
            # dönüşüyordu; yeni örnek yolunda aynı durum zaten 409 veriyor.
            return hata_yaniti(
                sablon, durum, request, str(exc), kod=409,
                baslik="Bu soru zaten hafızada",
                oneri="Aynı soru başka bir örnekte var; onu açıp düzenleyebilir "
                      "ya da soruyu farklı yazabilirsiniz.",
                geri=f"/ornek/{ornek_id}",
            )
        durum.ornegi_indeksle(mevcut)
        return RedirectResponse(f"/ornek/{ornek_id}", status_code=303)

    @yonlendirici.post("/ornek/{ornek_id}/sil")
    def ornek_sil(ornek_id: int):
        durum.depo.ornek_sil(ornek_id)
        durum.ornegi_indeksten_sil(ornek_id)
        return RedirectResponse("/ornekler", status_code=303)

    return yonlendirici
