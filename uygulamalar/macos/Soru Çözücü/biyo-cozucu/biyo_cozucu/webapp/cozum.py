"""Soru çözme, çözüm görüntüleme ve öğretmen onayı rotaları."""

from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, File, Form, Request, UploadFile
from fastapi.responses import (
    FileResponse,
    HTMLResponse,
    JSONResponse,
    RedirectResponse,
    StreamingResponse,
)

from ..gorsel import GorselDeposu, GorselHatasi
from ..modeller import CEVAP_TURLERI, CEVAP_TURU_ADLARI, Cozum, Ornek
from .dosya_sorulari import (
    SoruDosyasiHatasi,
    dosya_sorularini_hazirla,
    gorsel_imzasi_gecerli_mi,
)
from .durum import Uygulama
from .yardimcilar import hata_yaniti, sayfa_araligi

SAYFA_BOYU = 50


def _sse(olay: str, veri: dict) -> str:
    """Tek bir SSE çerçevesi.

    JSON gövdesi satır sonu içerebileceğinden `data:` alanı satır satır
    yazılır; tek satırda gönderilirse çerçeve erken kapanır ve istemci
    ayrıştırması bozulur.
    """
    govde = json.dumps(veri, ensure_ascii=False)
    satirlar = "".join(f"data: {s}\n" for s in govde.split("\n"))
    return f"event: {olay}\n{satirlar}\n"


def _gorseli_al(durum: Uygulama, yuklenen) -> str:
    """Yüklenen görüntüyü depoya yazar ve imzasını döndürür.

    Boş dosya alanı `UploadFile` olarak da gelebiliyor (tarayıcı boş bir
    `input[type=file]` gönderdiğinde); adı ve içeriği yoksa görsel yok sayılır.
    """
    if yuklenen is None or not getattr(yuklenen, "filename", ""):
        return ""
    veri = yuklenen.file.read()
    if not veri:
        return ""
    return GorselDeposu(durum.kok).yaz(veri)


def _dosyalari_oku(yuklenenler: list[UploadFile] | None) -> list[tuple[str, bytes]]:
    """Boş tarayıcı alanlarını atıp yüklemeleri ad+bayt çiftlerine çevirir."""
    return [
        (Path(yuklenen.filename or "isimsiz-dosya").name, yuklenen.file.read())
        for yuklenen in (yuklenenler or [])
        if getattr(yuklenen, "filename", "")
    ]


def _hazir_sorular(
    durum: Uygulama,
    yuklenenler: list[UploadFile] | None,
    *,
    soru_notu: str = "",
):
    dosyalar = _dosyalari_oku(yuklenenler)
    if not dosyalar:
        return []
    return dosya_sorularini_hazirla(durum.kok, dosyalar, soru_notu=soru_notu)


def _secenekleri_ayristir(ham: str) -> dict[str, str]:
    """Satır başına "A) metin" biçimindeki şıkları sözlüğe çevirir."""
    secenekler: dict[str, str] = {}
    for satir in (ham or "").splitlines():
        satir = satir.strip()
        if not satir:
            continue
        for ayirac in (")", ".", "-", ":"):
            harf, _, metin = satir.partition(ayirac)
            if len(harf.strip()) == 1 and metin.strip():
                secenekler[harf.strip().upper()] = metin.strip()
                break
    return secenekler


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.get("/coz", response_class=HTMLResponse)
    def coz_formu(request: Request):
        return sablon.TemplateResponse(
            request,
            "coz.html",
            {
                "durum": durum.durum(),
                "etkin": "coz",
                "cozum": None,
                "cozumler": [],
                "soru": "",
                "secenek_metni": "",
                "secili_tur": "",
                "cevap_turleri": CEVAP_TURLERI,
                "tur_adlari": CEVAP_TURU_ADLARI,
            },
        )

    @yonlendirici.post("/coz", response_class=HTMLResponse)
    def coz_calistir(
        request: Request,
        soru: str = Form(""),
        secenekler: str = Form(""),
        ornek_sayisi: int = Form(3),
        oz_kontrol: str = Form(""),
        cevap_turu: str = Form(""),
        gorsel: UploadFile | None = File(None),
        dosyalar: list[UploadFile] | None = File(None),
    ):
        soru = soru.strip()
        try:
            hazir_sorular = _hazir_sorular(durum, dosyalar, soru_notu=soru)
        except SoruDosyasiHatasi as exc:
            return hata_yaniti(
                sablon,
                durum,
                request,
                str(exc),
                baslik="Soru dosyası kabul edilmedi",
                geri="/coz",
            )
        if not soru and not hazir_sorular:
            return sablon.TemplateResponse(
                request,
                "coz.html",
                {
                    "durum": durum.durum(),
                    "etkin": "coz",
                    "cozum": None,
                    "cozumler": [],
                    "soru": "",
                    "secenek_metni": secenekler,
                    "secili_tur": cevap_turu,
                    "cevap_turleri": CEVAP_TURLERI,
                    "tur_adlari": CEVAP_TURU_ADLARI,
                    "hata": "Soru boş olamaz; bir soru yazın veya resim/PDF yükleyin.",
                },
                status_code=400,
            )

        # Ayarlar isteğe özel kopyadır: paylaşılan nesneyi değiştirmek, eşzamanlı
        # başka bir isteğin yarıda kalan üretimini o isteğin ayarlarıyla
        # sürdürürdü (öz-kontrol açılıp kapanabilir, örnek sayısı sızabilir).
        cozucu = durum.cozucu(
            ornek_sayisi=max(0, min(8, int(ornek_sayisi))),
            oz_kontrol=bool(oz_kontrol),
        )
        secenek_sozlugu = _secenekleri_ayristir(secenekler)
        if hazir_sorular:
            cozumler: list[Cozum] = []
            for hazir in hazir_sorular:
                hazir_secenekler = _secenekleri_ayristir(hazir.secenekler)
                # Dosyadan ayrılan her soru kendi şıklarını taşır. Formdaki
                # elle yazılmış şıkları çoklu PDF'nin bütün sorularına vermek
                # sessiz ve ciddi bir cevap kaymasına yol açar. Elle şıklar
                # yalnız tek, şıksız bir dosya sorusunu tamamlayabilir.
                kullanilacak_secenekler = hazir_secenekler
                if not kullanilacak_secenekler and len(hazir_sorular) == 1:
                    kullanilacak_secenekler = secenek_sozlugu
                cozumler.append(
                    cozucu.coz(
                        hazir.soru,
                        secenekler=kullanilacak_secenekler or None,
                        cevap_turu=cevap_turu or None,
                        gorsel=hazir.gorsel,
                    )
                )
            return sablon.TemplateResponse(
                request,
                "coz.html",
                {
                    "durum": durum.durum(),
                    "etkin": "coz",
                    "cozum": None,
                    "cozumler": cozumler,
                    "soru": soru,
                    "secenek_metni": secenekler,
                    "secili_tur": cevap_turu,
                    "cevap_turleri": CEVAP_TURLERI,
                    "tur_adlari": CEVAP_TURU_ADLARI,
                },
            )
        try:
            gorsel_imza = _gorseli_al(durum, gorsel)
        except GorselHatasi as exc:
            return hata_yaniti(
                sablon,
                durum,
                request,
                str(exc),
                baslik="Görsel kabul edilmedi",
                geri="/coz",
            )
        cozum = cozucu.coz(
            soru,
            secenekler=secenek_sozlugu or None,
            cevap_turu=cevap_turu or None,
            gorsel=gorsel_imza,
        )
        return sablon.TemplateResponse(
            request,
            "coz.html",
            {
                "durum": durum.durum(),
                "etkin": "coz",
                "cozum": cozum,
                "cozumler": [],
                "soru": soru,
                "secenek_metni": secenekler,
                "secili_tur": cevap_turu,
                "cevap_turleri": CEVAP_TURLERI,
                "tur_adlari": CEVAP_TURU_ADLARI,
            },
        )

    @yonlendirici.post("/coz/akis")
    def coz_akis(
        request: Request,
        soru: str = Form(...),
        secenekler: str = Form(""),
        ornek_sayisi: int = Form(3),
        oz_kontrol: str = Form(""),
        cevap_turu: str = Form(""),
        gorsel: UploadFile | None = File(None),
        gorsel_imza: str = Form(""),
    ):
        """Çözümü parça parça bildiren SSE ucu.

        Üretici **senkron**: çözücü de öyle. Starlette senkron üreticileri iş
        parçacığı havuzunda koşturur, böylece uzun süren yerel model çağrısı
        olay döngüsünü bloklamaz.
        """
        soru = soru.strip()
        secenek_sozlugu = _secenekleri_ayristir(secenekler)
        ornek_sayisi = max(0, min(8, int(ornek_sayisi)))
        oz_kontrol_acik = bool(oz_kontrol)
        secili_tur = cevap_turu if cevap_turu in CEVAP_TURLERI else ""
        # Görsel akış BAŞLAMADAN önce yazılır: akış açıldıktan sonra HTTP
        # durum kodu değiştirilemiyor, dolayısıyla dosya hatasını normal bir
        # hata yanıtı olarak vermenin tek yolu bu.
        try:
            yuklenen_imza = _gorseli_al(durum, gorsel)
            if yuklenen_imza:
                gorsel_imza = yuklenen_imza
            elif gorsel_imza and not gorsel_imzasi_gecerli_mi(durum.kok, gorsel_imza):
                raise GorselHatasi("Hazırlanan görsel bulunamadı veya geçersiz.")
            gorsel_hatasi = ""
        except GorselHatasi as exc:
            gorsel_imza, gorsel_hatasi = "", str(exc)

        def uret():
            if not soru:
                yield _sse("hata", {"mesaj": "Soru boş olamaz."})
                return
            if gorsel_hatasi:
                yield _sse("hata", {"mesaj": gorsel_hatasi})
                return
            try:
                cozucu = durum.cozucu(ornek_sayisi=ornek_sayisi, oz_kontrol=oz_kontrol_acik)
                for ad, veri in cozucu.coz_akis(
                    soru,
                    secenekler=secenek_sozlugu or None,
                    cevap_turu=secili_tur or None,
                    gorsel=gorsel_imza,
                ):
                    if ad == "parca":
                        yield _sse("parca", {"metin": veri})
                    elif ad == "durum":
                        yield _sse("durum", {"mesaj": veri})
                    elif ad == "bitti":
                        html = sablon.get_template("parcalar/cozum_karti.html").render(cozum=veri)
                        yield _sse("bitti", {"html": html})
            except Exception as exc:  # noqa: BLE001
                # Akış başladıktan sonra HTTP durum kodu değiştirilemez;
                # hatayı olay olarak bildirmek tek yol.
                yield _sse("hata", {"mesaj": f"Çözüm üretilemedi: {exc}"})

        return StreamingResponse(
            uret(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache, no-transform",
                "X-Accel-Buffering": "no",  # ara vekil tamponlamasın
            },
        )

    @yonlendirici.post("/coz/dosya/hazirla")
    def dosya_hazirla(
        dosyalar: list[UploadFile] = File(...),
        soru_notu: str = Form(""),
    ):
        """Çoklu resim/PDF yüklemesini çözüm kuyruğu öğelerine dönüştürür."""
        try:
            sorular = _hazir_sorular(durum, dosyalar, soru_notu=soru_notu.strip())
        except SoruDosyasiHatasi as exc:
            return JSONResponse({"hata": str(exc)}, status_code=400)
        return {
            "sorular": [soru.sozluk() for soru in sorular],
            "toplam": len(sorular),
        }

    @yonlendirici.get("/coz/gorsel/{imza}.png", response_class=FileResponse)
    def hazir_gorsel(imza: str):
        """Yalnız hazırlanmış, SHA-imzalı görselleri önizleme için sunar."""
        if not gorsel_imzasi_gecerli_mi(durum.kok, imza):
            return JSONResponse({"hata": "Görsel bulunamadı."}, status_code=404)
        return FileResponse(
            GorselDeposu(durum.kok).yol(imza),
            media_type="image/png",
            headers={"Cache-Control": "private, max-age=3600"},
        )

    @yonlendirici.get("/cozumler", response_class=HTMLResponse)
    def cozum_listesi(
        request: Request,
        onay: str = "",
        ara: str = "",
        incele: str = "",
        sayfa: int = 1,
    ):
        yalniz_incele = bool(incele)
        toplam = durum.depo.cozum_say(
            onay_durumu=onay or None, ara=ara, yalniz_incele=yalniz_incele
        )
        aralik = sayfa_araligi(sayfa, SAYFA_BOYU, toplam)
        satirlar = durum.depo.cozumler(
            limit=aralik["boyut"],
            offset=aralik["offset"],
            onay_durumu=onay or None,
            ara=ara,
            yalniz_incele=yalniz_incele,
        )
        return sablon.TemplateResponse(
            request,
            "cozumler.html",
            {
                "durum": durum.durum(),
                "etkin": "cozumler",
                "satirlar": satirlar,
                "secili_onay": onay,
                "ara": ara,
                "yalniz_incele": yalniz_incele,
                "sayfalama": aralik,
                "temel_yol": "/cozumler",
                "sorgu": {"onay": onay, "ara": ara, "incele": incele},
            },
        )

    @yonlendirici.get("/cozum/{cozum_id}", response_class=HTMLResponse)
    def cozum_goster(request: Request, cozum_id: int):
        kayit = durum.depo.cozum(cozum_id)
        if kayit is None:
            return hata_yaniti(
                sablon,
                durum,
                request,
                f"#{cozum_id} numaralı çözüm bulunamadı.",
                kod=404,
                baslik="Çözüm bulunamadı",
                geri="/cozumler",
            )
        cozum, satir = kayit
        return sablon.TemplateResponse(
            request,
            "cozum.html",
            {"durum": durum.durum(), "cozum": cozum, "satir": satir},
        )

    @yonlendirici.post("/cozum/{cozum_id}/onay")
    def cozum_onayla(
        request: Request,
        cozum_id: int,
        islem: str = Form(...),
        duzeltilmis_cozum: str = Form(""),
        duzeltilmis_cevap: str = Form(""),
    ):
        kayit = durum.depo.cozum(cozum_id)
        if kayit is None:
            return hata_yaniti(
                sablon,
                durum,
                request,
                f"#{cozum_id} numaralı çözüm bulunamadı.",
                kod=404,
                baslik="Çözüm bulunamadı",
                geri="/cozumler",
            )
        cozum, _satir = kayit

        if islem == "reddet":
            durum.depo.cozum_onayla(cozum_id, durum="reddedildi")
            return RedirectResponse(f"/cozum/{cozum_id}", status_code=303)

        if islem == "onayla":
            metin = cozum.metin()
            cevap = cozum.cevap
            yeni_durum = "onaylandi"
        elif islem == "duzelt":
            metin = duzeltilmis_cozum.strip()
            cevap = duzeltilmis_cevap.strip() or cozum.cevap
            if not metin:
                return hata_yaniti(
                    sablon,
                    durum,
                    request,
                    "Düzeltilmiş çözüm boş olamaz.",
                    baslik="Düzeltme kaydedilemedi",
                    oneri="Çözüm metnini doldurup yeniden gönderin.",
                    geri=f"/cozum/{cozum_id}",
                )
            yeni_durum = "duzeltildi"
        else:
            return hata_yaniti(
                sablon,
                durum,
                request,
                f"Bilinmeyen işlem: {islem}",
                geri=f"/cozum/{cozum_id}",
            )

        # Onaylanan/düzeltilen çözüm yeni bir referans örneğe dönüşür: döngünün
        # kapandığı yer burası. Aynı soru zaten örnekse üzerine yazılır.
        ornek = Ornek(
            soru=cozum.soru,
            # Şıklar olmadan "B" cevabı anlamsızdır: çözümde saklananlar aynen
            # taşınır, yoksa yeni örnek çoktan seçmeli görünüp şıksız kalır.
            secenekler=dict(cozum.secenekler),
            cozum=metin,
            cevap=cevap,
            cevap_turu=cozum.cevap_turu if cozum.secenekler else "acik_uclu",
            konu=cozum.konu,
            cozum_turu=cozum.cozum_turu,
            kaynak="öğretmen onayı",
            etiket_kaynagi="elle",
        )
        ornek.id = durum.depo.ornek_ekle(ornek, uzerine_yaz=True)
        durum.depo.cozum_onayla(cozum_id, durum=yeni_durum, duzeltme=metin)
        durum.depo.denetim_yaz("cozum_onay", f"cozum={cozum_id} durum={yeni_durum}")
        durum.ornegi_indeksle(ornek)
        return RedirectResponse(f"/cozum/{cozum_id}", status_code=303)

    @yonlendirici.post("/coz/api")
    def coz_api(soru: str = Form(...), secenekler: str = Form("")):
        """Basit JSON ucu — betikten toplu çözüm için."""
        cozum: Cozum = durum.cozucu().coz(
            soru, secenekler=_secenekleri_ayristir(secenekler) or None
        )
        return json.loads(cozum.json())

    return yonlendirici
