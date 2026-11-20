"""Kâğıt detayı, itiraz, kimlik düzeltme ve cevap kutusu puanlama uçları."""
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import quote

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .baglam import WebBaglam

# Toplu onayın mühürlemeyeceği karar türleri: puanın kendisi tartışmalı
# olduğu için öğretmenin tek tek bakması gerekir.
SUPHELI_KARARLAR = frozenset(
    {"kismi", "celiski", "kararsiz_terim", "sinirda_esleme"}
)
TOPLU_ONAY_ASGARI_GUVEN = 0.65
TOPLU_ONAY_AZAMI_RISK = 0.5


def _atlanan_detay(ham: str | None) -> list[dict]:
    """Yönlendirmede taşınan atlanan-kutu listesini güvenle çözer."""
    if not ham:
        return []
    try:
        veri = json.loads(ham)
    except (TypeError, ValueError):
        return []
    return [x for x in veri if isinstance(x, dict)][:20] if isinstance(veri, list) else []


def _toplu_onaya_uygun(kutu) -> tuple[bool, str]:
    """Kutu ayrım yapmayan toplu onaya uygun mu, değilse neden?"""
    metin = (
        kutu["duzeltilmis_metin"]
        if kutu["duzeltilmis_metin"] is not None
        else kutu["taninan_metin"]
    )
    if not (metin or "").strip():
        return False, "metin boş"
    if float(kutu["risk"] or 0.0) >= TOPLU_ONAY_AZAMI_RISK:
        return False, "risk yüksek"
    puanlama_guveni = kutu["puanlama_guveni"]
    if puanlama_guveni is not None and float(puanlama_guveni) < TOPLU_ONAY_ASGARI_GUVEN:
        return False, "puanlama güveni düşük"
    try:
        kararlar = json.loads(kutu["kararlar_json"] or "[]")
    except (TypeError, ValueError):
        kararlar = []
    for karar in kararlar:
        if not isinstance(karar, dict):
            continue
        if str(karar.get("karar", "")) in SUPHELI_KARARLAR:
            return False, f"şüpheli karar ({karar.get('karar')})"
        if karar.get("tur") == "sayisal_sonuc" and karar.get("ara_islemde"):
            return False, "doğru değer yalnız ara işlemde"
        if karar.get("tur") == "guvenlik_kapisi" and karar.get("nedenler"):
            return False, "güvenlik kapısı vetosu"
    return True, ""


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar

    @router.post("/kagit/{kagit_id}/itiraz")
    def kagit_itiraz_ac(
        kagit_id: int,
        kutu_id: str = Form(""),
        gerekce: str = Form(...),
    ):
        """Öğrenci itirazını kaydeder; puanı değiştirmez."""
        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        try:
            depo.itiraz_ac(
                kagit_id, int(kutu_id) if kutu_id else None, gerekce
            )
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        return RedirectResponse(f"/kagit/{kagit_id}?itiraz=1", status_code=303)
    @router.post("/kagit/{kagit_id}/kutulari-onayla")
    def kagit_kutularini_onayla(kagit_id: int):
        """Yalnız DÜŞÜK RİSKLİ bekleyenleri mühürler.

        Ayrım yapmayan toplu onay, puanı sorgulanabilir kutuları da (sınırda
        yazım eşleşmesi, kısmi rubrik kararı, kapı vetosu) tek tıkla
        kalıcılaştırıyordu; öğretmen yanlış puanı hiç görmeden onaylıyordu.
        """
        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        onaylanan = 0
        atlananlar: list[dict] = []
        for kutu in depo.kutular(kagit_id):
            if not kutu["incele"]:
                continue
            uygun, neden = _toplu_onaya_uygun(kutu)
            if not uygun:
                atlananlar.append({"soru_no": kutu["soru_no"], "neden": neden})
                continue
            depo.kutu_guncelle(
                kutu_id=kutu["id"], incele=False,
                neden="Toplu onay: öğretmen görüntüyle doğruladı",
            )
            onaylanan += 1
        return RedirectResponse(
            f"/kagit/{kagit_id}?toplu_onay={onaylanan}"
            f"&atlanan={len(atlananlar)}"
            f"&atlanan_detay={quote(json.dumps(atlananlar, ensure_ascii=False))}",
            status_code=303,
        )
    @router.get("/kagit/{kagit_id}", response_class=HTMLResponse)
    def kagit_detay(request: Request, kagit_id: int):
        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        sinav = depo.sinav_yukle(kagit["sinav_kimlik"])
        sirala = request.query_params.get("sirala")
        kutular = []
        def _json_alan(b, alan: str, varsayilan):
            try:
                return json.loads(b[alan] or json.dumps(varsayilan))
            except (json.JSONDecodeError, TypeError, IndexError):
                return varsayilan

        for b in depo.kutular(kagit_id):
            soru = sinav.soru(b["soru_no"])
            detaylar = []
            if b["detaylar"]:
                try:
                    ham_detay = json.loads(b["detaylar"])
                except (json.JSONDecodeError, TypeError):
                    ham_detay = b["detaylar"]
                if isinstance(ham_detay, dict):
                    detaylar = [
                        {"ad": str(ad).replace("_", " ").capitalize(), "deger": deger}
                        for ad, deger in ham_detay.items()
                    ]
                elif isinstance(ham_detay, list):
                    detaylar = [{"ad": "Açıklama", "deger": deger} for deger in ham_detay]
                else:
                    detaylar = [{"ad": "Açıklama", "deger": ham_detay}]
            kutular.append({
                "b": b, "soru": soru,
                "metin": b["duzeltilmis_metin"] if b["duzeltilmis_metin"] is not None else b["taninan_metin"],
                "kirp_url": baglam._kirp_url(b["kirp_yolu"]),
                "detaylar": detaylar,
                "alternatifler": (
                    json.loads(b["alternatifler_json"] or "[]")
                    if b["alternatifler_json"] else []
                ),
                "kararlar": (
                    json.loads(b["kararlar_json"] or "[]")
                    if b["kararlar_json"] else []
                ),
                "motor_sonuclari": _json_alan(b, "motor_sonuclari_json", []),
                "girdi_kalitesi": _json_alan(b, "girdi_kalitesi_json", {}),
                "model_surumu": _json_alan(b, "model_surumu_json", {}),
                "kabul_nedenleri": _json_alan(b, "kabul_nedenleri_json", []),
                "sozluk_duzeltmeleri": _json_alan(
                    b, "sozluk_duzeltmeleri_json", []
                ),
            })
        if sirala == "guven":
            # İncelenecekler önce; içlerinde en riskli/en düşük güvenli önce.
            kutular.sort(
                key=lambda c: (
                    not c["b"]["incele"],
                    -float(c["b"]["risk"] or 0),
                    float(c["b"]["tanima_guveni"] or 0),
                )
            )
        toplam, maxp = depo.kagit_toplam(kagit_id)
        bekleyen = sum(1 for c in kutular if c["b"]["incele"])
        try:
            islem_uyarilari = json.loads(kagit["islem_uyarilari"] or "[]")
        except (json.JSONDecodeError, TypeError):
            islem_uyarilari = []
        try:
            kimlik_bilgileri = json.loads(kagit["kimlik_json"] or "{}")
        except (json.JSONDecodeError, TypeError):
            kimlik_bilgileri = {}
        try:
            kalite_raporu = json.loads(kagit["kalite_json"] or "[]")
        except (json.JSONDecodeError, TypeError):
            kalite_raporu = []
        try:
            sayfa_eslesmeleri = json.loads(kagit["sayfa_eslesme_json"] or "[]")
        except (json.JSONDecodeError, TypeError):
            sayfa_eslesmeleri = []
        sinav_kagitlari = depo.kagitlar(kagit["sinav_kimlik"])
        kagit_siralari = [k["id"] for k in sinav_kagitlari]
        sira = kagit_siralari.index(kagit_id)
        onceki_kagit = kagit_siralari[sira - 1] if sira > 0 else None
        sonraki_kagit = kagit_siralari[sira + 1] if sira + 1 < len(kagit_siralari) else None
        return sablonlar.TemplateResponse(request, "kagit.html", {
            "kagit": kagit, "sinav": sinav,
            "kutular": kutular, "toplam": toplam, "max": maxp,
            "bekleyen": bekleyen,
            "puan_yuzdesi": toplam / maxp * 100 if maxp else 0,
            "onceki_kagit": onceki_kagit,
            "sonraki_kagit": sonraki_kagit,
            "islem_uyarilari": islem_uyarilari,
            "kimlik_bilgileri": kimlik_bilgileri,
            "kalite_raporu": kalite_raporu,
            "girdi_anomalisi": any(
                bool(r.get("kritik"))
                or float(r.get("ogretmen_murekkep_orani", 0) or 0) > 0
                for r in kalite_raporu
            ),
            "sayfa_eslesmeleri": sayfa_eslesmeleri,
            "denetim_kayitlari": depo.denetim_kayitlari("kagit", str(kagit_id)),
            "onay_hata": request.query_params.get("onay_hata"),
            "yeni_yuklendi": request.query_params.get("yeni") == "1",
            "yeniden_puanlandi": request.query_params.get("yeniden") == "1",
            "goruntu_yenilendi": request.query_params.get("goruntu_yenilendi") == "1",
            "sirala": sirala,
            "toplu_onay": request.query_params.get("toplu_onay"),
            "toplu_atlanan": request.query_params.get("atlanan"),
            "toplu_atlanan_detay": _atlanan_detay(
                request.query_params.get("atlanan_detay")
            ),
        })
    @router.post("/kagit/{kagit_id}/kimlik")
    def kagit_kimlik_kaydet(
        kagit_id: int,
        ogrenci_ad: str = Form(""),
        ogrenci_soyad: str = Form(""),
        ogrenci_no: str = Form(""),
        sinif: str = Form(""),
        sube: str = Form(""),
    ):
        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        depo.kagit_kimlik_guncelle(
            kagit_id,
            ogrenci_ad=ogrenci_ad,
            ogrenci_soyad=ogrenci_soyad,
            ogrenci_no=ogrenci_no,
            sinif=sinif,
            sube=sube,
        )
        depo.kagit_onayini_kaldir(kagit_id)
        return RedirectResponse(
            f"/kagit/{kagit_id}?kimlik_kaydedildi=1#ogrenci-kimligi",
            status_code=303,
        )
    @router.post("/kutu/{kutu_id}")
    def kutu_kaydet(kutu_id: int, kagit_id: int = Form(...),
                    metin: str = Form(""), puan: float | None = Form(None),
                    donus: str = Form(""), islem: str = Form("elle"),
                    neden: str = Form(""), hedef: str = Form("")):
        kutu = depo.kutu(kutu_id)
        kagit = depo.kagit(kagit_id)
        if kutu is None or kagit is None or kutu["kagit_id"] != kagit_id:
            raise HTTPException(404, "Cevap kutusu bulunamadı")
        if islem == "otomatik":
            sinav = depo.sinav_yukle(kagit["sinav_kimlik"])
            baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
        elif islem == "elle":
            if puan is None:
                raise HTTPException(400, "İstisna puanı gerekli")
            depo.kutu_guncelle(
                kutu_id,
                son_puan=puan,
                duzeltilmis_metin=metin,
                incele=False,
                neden=neden.strip() or "Öğretmen istisna puanı",
            )
        elif islem == "onayla":
            # Değiştirmeden kabul: mevcut puanı koru, incele'yi kapat. Yeniden
            # puanlama YAPILMAZ (aksi halde incele geri açılıp kuyruk dönebilir).
            depo.kutu_guncelle(
                kutu_id,
                incele=False,
                neden=neden.strip() or "Öğretmen görüntüyle doğruladı",
            )
        else:
            raise HTTPException(400, "Geçersiz puanlama işlemi")
        depo.kagit_onayini_kaldir(kagit_id)
        # Kuyruk ekranlarından gelen onaylar kuyruğa geri döner (yalnız yerel yol).
        if (
            hedef.startswith("/sinav/")
            and any(p in hedef for p in ("/inceleme", "/tutarlilik", "/tezgah"))
            and "//" not in hedef[1:]
        ):
            return RedirectResponse(hedef, status_code=303)
        parca = f"#{donus}" if re.fullmatch(r"soru-\d+", donus) else ""
        # Düzeltmenin kalibrasyon havuzuna aktığını öğretmene göster (flywheel).
        bekleyen = len(depo.kalibrasyon_ornekleri())
        sorgu = f"?kalibrasyon_bekleyen={bekleyen}" if bekleyen else ""
        return RedirectResponse(
            f"/kagit/{kagit_id}{sorgu}{parca}", status_code=303
        )
    @router.post("/kagit/{kagit_id}/yeniden-puanla")
    def kagit_yeniden_puanla(kagit_id: int):
        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        sinav = depo.sinav_yukle(kagit["sinav_kimlik"])
        for kutu in depo.kutular(kagit_id):
            metin = (
                kutu["duzeltilmis_metin"]
                if kutu["duzeltilmis_metin"] is not None
                else kutu["taninan_metin"] or ""
            )
            baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
        depo.kagit_onayini_kaldir(kagit_id)
        return RedirectResponse(
            f"/kagit/{kagit_id}?yeniden=1",
            status_code=303,
        )
    @router.post("/kagit/{kagit_id}/goruntu-analizi")
    def kagit_goruntu_analizi(kagit_id: int):
        """Önceden yüklenmiş bir kâğıdın tarama/renk kalite kaydını yenile."""
        from ..kalite import sayfalari_degerlendir
        from ..tarama import dosyalar_sayfalari

        kagit = depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        kaynak = str(kagit["kaynak_dosya"] or "").strip()
        try:
            cozulmus = json.loads(kaynak)
        except json.JSONDecodeError:
            cozulmus = kaynak
        yollar = cozulmus if isinstance(cozulmus, list) else [cozulmus]
        yollar = [str(yol) for yol in yollar if yol and Path(str(yol)).is_file()]
        if not yollar:
            raise HTTPException(
                400, "Bu kayıt için yeniden okunabilir kaynak görüntü bulunamadı."
            )
        if len(yollar) > 4:
            raise HTTPException(400, "Bir kâğıt en fazla dört sayfa olabilir.")
        sayfalar = dosyalar_sayfalari(yollar, dpi=300)
        raporlar = [rapor.sozluk() for rapor in sayfalari_degerlendir(sayfalar)]
        depo.kagit_kalitesini_guncelle(kagit_id, raporlar)
        depo.kagit_onayini_kaldir(kagit_id)
        return RedirectResponse(
            f"/kagit/{kagit_id}?goruntu_yenilendi=1#tarama-kalitesi",
            status_code=303,
        )
    @router.post("/kagit/{kagit_id}/onayla")
    def kagit_onayla(kagit_id: int):
        cozulmemis = depo.cozulmemis_kutular(kagit_id)
        if cozulmemis:
            return RedirectResponse(
                f"/kagit/{kagit_id}?onay_hata={len(cozulmemis)}"
                f"#soru-{cozulmemis[0]['soru_no']}",
                status_code=303,
            )
        depo.kagit_onayla(kagit_id)
        kagit = depo.kagit(kagit_id)
        return RedirectResponse(f"/sinav/{kagit['sinav_kimlik']}", status_code=303)
    @router.get("/kagit/{kagit_id}/geri-bildirim", response_class=HTMLResponse)
    def kagit_geri_bildirimi(request: Request, kagit_id: int):
        gorsel = request.query_params.get("gorsel") == "1"
        baglam_verisi = baglam._geri_bildirim_kagidi(kagit_id, gorsel)
        baglam_verisi.update({"gorsel": gorsel, "kagitlar": [baglam_verisi]})
        return sablonlar.TemplateResponse(request, "geri_bildirim.html", baglam_verisi)

    return router
