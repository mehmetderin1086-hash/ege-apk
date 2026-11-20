"""Kitap/çözüm kaynağından onaylı içe aktarma rotaları.

Akış bilinçli olarak iki adımlı: yükle → **önizle ve seç** → aktar. Kitap
taraması ve ses dökümü gürültülüdür; tek adımda yazmak yanlış ayrıştırılmış
çözümleri kalıcı referans örneğe dönüştürür ve modeli sürekli yanlış
yönlendirir.
"""

from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse

from ..alim import DESTEKLENEN_UZANTILAR, AlimHatasi, adaylari_cikar, metni_cikar
from ..alim.ocr import MOTOR_SIRASI, kullanilabilir_motorlar
from ..hafiza.etiketleme import kural_ile_etiketle
from ..modeller import Ornek
from .durum import Uygulama
from .yardimcilar import hata_yaniti

# Yüklenen dosya diske alınır; 500 MB'lık bir kitabı belleğe almak makineyi
# zorlardı. `alim.cikarim` da aynı sınırı ayrıca uygular.
AZAMI_YUKLEME_MB = 500


def _guvenli_ad(ad: str) -> str:
    """Yalnız dosya adını bırakır — yol parçaları dizin kaçışına açık kapıdır."""
    temiz = Path(ad or "").name
    temiz = "".join(k for k in temiz if k.isalnum() or k in " -_.()[]").strip()
    return temiz or "yukleme"


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.get("/alim", response_class=HTMLResponse)
    def alim_formu(request: Request):
        return sablon.TemplateResponse(
            request,
            "alim.html",
            {
                "durum": durum.durum(),
                "etkin": "alim",
                "sonuc": None,
                "uzantilar": sorted(DESTEKLENEN_UZANTILAR),
                "ocr_motorlari": kullanilabilir_motorlar(),
                "tum_ocr_motorlari": list(MOTOR_SIRASI),
            },
        )

    @yonlendirici.post("/alim", response_class=HTMLResponse)
    async def alim_calistir(
        request: Request,
        dosya: UploadFile = File(...),
        ocr: str = Form("oto"),
        ocr_motoru: str = Form(""),
    ):
        ad = _guvenli_ad(dosya.filename or "")
        uzanti = Path(ad).suffix.casefold()
        if uzanti not in DESTEKLENEN_UZANTILAR:
            return hata_yaniti(
                sablon, durum, request,
                f"'{uzanti or ad}' desteklenmiyor.",
                baslik="Dosya alınamadı",
                oneri="Desteklenenler: " + ", ".join(sorted(DESTEKLENEN_UZANTILAR)),
                geri="/alim",
            )

        gecici_kok = Path(tempfile.mkdtemp(prefix="biyo-yukleme-"))
        hedef = gecici_kok / ad
        try:
            boyut = 0
            sinir = AZAMI_YUKLEME_MB * 1024 * 1024
            with hedef.open("wb") as cikti:
                while parca := await dosya.read(1 << 20):
                    boyut += len(parca)
                    if boyut > sinir:
                        return hata_yaniti(
                            sablon, durum, request,
                            f"Dosya {AZAMI_YUKLEME_MB} MB sınırını aştı.",
                            baslik="Dosya çok büyük", geri="/alim",
                        )
                    cikti.write(parca)

            try:
                kaynak = metni_cikar(
                    hedef,
                    ocr=ocr if ocr in {"oto", "kapali", "zorla"} else "oto",
                    ocr_motoru=ocr_motoru,
                )
            except AlimHatasi as exc:
                return hata_yaniti(
                    sablon, durum, request, str(exc),
                    baslik="Dosya okunamadı", geri="/alim",
                )
            adaylar = adaylari_cikar(kaynak.metin, kaynak=kaynak)
        finally:
            shutil.rmtree(gecici_kok, ignore_errors=True)

        return sablon.TemplateResponse(
            request,
            "alim.html",
            {
                "durum": durum.durum(),
                "etkin": "alim",
                "uzantilar": sorted(DESTEKLENEN_UZANTILAR),
                "ocr_motorlari": kullanilabilir_motorlar(),
                "tum_ocr_motorlari": list(MOTOR_SIRASI),
                "sonuc": {
                    "kaynak": kaynak,
                    "adaylar": adaylar,
                    # Adaylar gizli alanda taşınır: dosyayı ikinci kez okumak
                    # (ve saatlerce süren bir ses dökümünü tekrarlamak) gerekmesin.
                    "yuk": json.dumps(
                        [
                            dict(a.sozluk(), kaynak=kaynak.kaynak_adi())
                            for a in adaylar
                        ],
                        ensure_ascii=False,
                    ),
                },
            },
        )

    @yonlendirici.post("/alim/aktar")
    def alim_aktar(
        request: Request,
        yuk: str = Form(...),
        secilenler: list[int] = Form(default=[]),
        uzerine_yaz: str = Form(""),
    ):
        try:
            adaylar = json.loads(yuk)
        except json.JSONDecodeError:
            return hata_yaniti(
                sablon, durum, request,
                "Aday listesi okunamadı; dosyayı yeniden yükleyin.",
                baslik="Aktarma başarısız", geri="/alim",
            )

        secili = set(secilenler)
        eklenen = guncellenen = atlanan = 0
        hatalar: list[str] = []

        for sira, kayit in enumerate(adaylar):
            if sira not in secili:
                continue
            soru = str(kayit.get("soru", "")).strip()
            cozum = str(kayit.get("cozum", "")).strip()
            if not soru or not cozum:
                atlanan += 1
                continue
            konu, tur = kural_ile_etiketle(soru, cozum)
            yer = str(kayit.get("konum", "")).strip()
            kaynak_adi = str(kayit.get("kaynak", "")).strip()
            ornek = Ornek(
                soru=soru,
                cozum=cozum,
                cevap=str(kayit.get("cevap", "")).strip(),
                secenekler=dict(kayit.get("secenekler") or {}),
                cevap_turu=str(kayit.get("cevap_turu") or "acik_uclu"),
                konu=konu,
                cozum_turu=tur,
                kaynak=f"{kaynak_adi} · {yer}" if yer else kaynak_adi,
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
            durum.depo.denetim_yaz(
                "alim_aktar", f"eklenen={eklenen} guncellenen={guncellenen}"
            )
            durum.indeksi_yenile()

        return sablon.TemplateResponse(
            request,
            "alim.html",
            {
                "durum": durum.durum(),
                "etkin": "alim",
                "uzantilar": sorted(DESTEKLENEN_UZANTILAR),
                "ocr_motorlari": kullanilabilir_motorlar(),
                "tum_ocr_motorlari": list(MOTOR_SIRASI),
                "sonuc": None,
                "aktarma": {
                    "secilen": len(secili),
                    "eklenen": eklenen,
                    "guncellenen": guncellenen,
                    "atlanan": atlanan,
                    "hatalar": hatalar[:10],
                },
            },
        )

    return yonlendirici
