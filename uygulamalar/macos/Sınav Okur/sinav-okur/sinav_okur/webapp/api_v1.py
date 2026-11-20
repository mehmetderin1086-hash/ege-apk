"""Öğretmen Çantası yerel API'si (v1).

Sınav paketi içe aktarma ve onaylı sonuç dökümü. Tüm uçlar Bearer token ister;
token dosyası yoksa istekler 401 alır (kapalı-varsayılan). İçe aktarılan sorular
her zaman `otomatik_puanlama=False` ile gelir — öğretmen onayı olmadan hiçbir
soru otomatik puanlanmaz.
"""
from __future__ import annotations

import io
import json
import os
import re
import secrets
import zipfile
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from fastapi.responses import Response

from .baglam import WebBaglam


def _api_yetkili(request: Request) -> None:
    yol = Path(
        os.environ.get("OGRETMEN_API_TOKEN_YOLU")
        or Path.home()
        / (
            "Library/Application Support/OgretmenCantasi/"
            "entegrasyonlar/yerel-api.token"
        )
    )
    try:
        beklenen = yol.read_text(encoding="utf-8").strip()
    except OSError:
        beklenen = ""
    sunulan = request.headers.get("authorization", "")
    if not beklenen or not secrets.compare_digest(
        sunulan.encode("utf-8"), f"Bearer {beklenen}".encode("utf-8")
    ):
        raise HTTPException(401, "Yerel API yetkisi geçersiz.")


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    entegrasyon_dizini = baglam.entegrasyon_dizini

    @router.get("/api/v1/health")
    def api_saglik(request: Request):
        _api_yetkili(request)
        return {
            "app": "sinav-okur",
            "app_version": "gelistirme",
            "protocol_version": "v1",
            "status": "ready",
        }

    @router.get("/api/v1/capabilities")
    def api_yetenekler(request: Request):
        _api_yetkili(request)
        return {
            "protocol_version": "v1",
            "capabilities": ["exam-package-import", "exam-results-export"],
        }

    @router.post("/api/v1/exams/import")
    async def api_sinav_al(request: Request, package: UploadFile = File(...)):
        _api_yetkili(request)
        icerik = await package.read(100 * 1024 * 1024 + 1)
        if len(icerik) > 100 * 1024 * 1024:
            raise HTTPException(413, "Sınav paketi 100 MiB sınırını aşıyor.")
        try:
            with zipfile.ZipFile(io.BytesIO(icerik)) as paket:
                bilgi = paket.getinfo("manifest.json")
                if bilgi.file_size > 10 * 1024 * 1024:
                    raise HTTPException(
                        413, "manifest.json açılmış boyutu 10 MiB sınırını aşıyor."
                    )
                manifest = json.loads(paket.read("manifest.json"))
        except (zipfile.BadZipFile, KeyError, json.JSONDecodeError) as exc:
            raise HTTPException(400, "Geçerli manifest içeren ZIP gerekli.") from exc
        if (
            manifest.get("schema_version") != 1
            or manifest.get("source_app") != "ogretmen-cantasi"
            or manifest.get("type") != "exam"
        ):
            raise HTTPException(400, "Desteklenmeyen sınav paketi.")
        from ..modeller import CevapAnahtari, RubrikKalemi, Sinav, Soru, SoruTipi

        sinav_ham = manifest.get("exam") or {}
        dis_kimlik = str(sinav_ham.get("external_id") or "").strip()
        if not dis_kimlik:
            raise HTTPException(400, "Sınav dış kimliği eksik.")
        kimlik = "oc-" + re.sub(r"[^A-Za-z0-9_-]+", "-", dis_kimlik).strip("-")
        # Okunmuş kâğıt kontrolü eşleme dosyasından bağımsızdır: dosya
        # silinmiş/farklı veri dizini olsa da depo durumu üzerine yazmayı önler.
        if depo.kagitlar(kimlik):
            raise HTTPException(
                409,
                "Bu dış kimlikli sınav daha önce içe aktarılmış ve okunmuş "
                "kâğıtları var; üzerine yazma reddedildi. Yeni sürüm için "
                "farklı bir dış kimlik kullanın.",
            )
        esleme_yolu = entegrasyon_dizini / f"{kimlik}.json"
        if esleme_yolu.is_file():
            try:
                onceki_dis = json.loads(
                    esleme_yolu.read_text(encoding="utf-8")
                ).get("exam_external_id")
            except (OSError, ValueError):
                onceki_dis = None
            # İç kimlik kayıplı normalizasyondan gelir; farklı bir dış kimlik
            # aynı iç kimliğe çarpışırsa başka sınav sessizce ezilir.
            if onceki_dis is not None and onceki_dis != dis_kimlik:
                raise HTTPException(
                    409,
                    f"Dış kimlik çakışması: '{onceki_dis}' zaten '{kimlik}' iç "
                    "kimliğine bağlı. Farklı bir dış kimlik kullanın.",
                )
        sorular = []
        soru_esleme = {}
        for ham in manifest.get("questions") or []:
            try:
                no = int(ham.get("order") or 0)
                puan = float(ham.get("max_score") or 0)
            except (TypeError, ValueError) as exc:
                raise HTTPException(
                    400, "Soru numarası ve puanı sayısal olmalı."
                ) from exc
            if no <= 0 or puan <= 0 or not str(ham.get("text") or "").strip():
                raise HTTPException(400, "Soru numarası, metni ve puanı zorunlu.")
            if str(no) in soru_esleme:
                raise HTTPException(400, f"Soru sırası {no} pakette iki kez var.")
            soru_esleme[str(no)] = str(ham.get("external_id") or "")
            sorular.append(
                Soru(
                    no=no,
                    tip=SoruTipi.ACIK_UCLU,
                    metin=str(ham["text"]),
                    puan=puan,
                    anahtar=CevapAnahtari(
                        rubrik=[
                            RubrikKalemi(
                                metin=str(ham.get("rubric") or "Öğretmen değerlendirmesi"),
                                puan=puan,
                            )
                        ],
                        otomatik_puanlama=False,
                        uyari="Cevap anahtarı Öğretmen Çantası paketinden geldi; öğretmen onayı gerekir.",
                        onay_durumu="taslak",
                    ),
                    kazanımlar=[str(ham.get("outcome_code") or "")],
                )
            )
        sinav = Sinav(
            kimlik=kimlik,
            baslik=str(sinav_ham.get("name") or "Öğretmen Çantası sınavı"),
            ders="Biyoloji",
            sorular=sorular,
        )
        depo.sinav_kaydet(sinav)
        ogrenciler = []
        ogrenci_esleme = {}
        for ham in manifest.get("students") or []:
            no = str(ham.get("school_number") or "").strip()
            if not no:
                continue
            ad_parcalari = str(ham.get("name") or "").strip().rsplit(" ", 1)
            ad = ad_parcalari[0]
            soyad = ad_parcalari[1] if len(ad_parcalari) > 1 else ""
            ogrenciler.append(
                {
                    "ogrenci_no": no,
                    "ad": ad,
                    "soyad": soyad,
                    "sinif": str(sinav_ham.get("grade") or ""),
                    "sube": str(sinav_ham.get("class_name") or ""),
                }
            )
            ogrenci_esleme[no] = str(ham.get("external_id") or "")
        depo.ogrenci_listesi_kaydet(kimlik, ogrenciler)
        esleme = {
            "schema_version": 1,
            "source_app": "ogretmen-cantasi",
            "exam_external_id": dis_kimlik,
            "internal_exam_id": kimlik,
            "question_external_ids": soru_esleme,
            "student_external_ids": ogrenci_esleme,
        }
        (entegrasyon_dizini / f"{kimlik}.json").write_text(
            json.dumps(esleme, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return {"status": "imported", "exam_id": kimlik, "protocol_version": "v1"}

    @router.get("/api/v1/exams/{kimlik}/results")
    def api_sonuclar(request: Request, kimlik: str):
        _api_yetkili(request)
        esleme_yolu = entegrasyon_dizini / f"{kimlik}.json"
        if not esleme_yolu.is_file():
            raise HTTPException(404, "Entegrasyon sınav eşlemesi bulunamadı.")
        esleme = json.loads(esleme_yolu.read_text(encoding="utf-8"))
        sonuclar = []
        for kagit in depo.kagitlar(kimlik):
            if not kagit["onaylandi"]:
                continue
            ogrenci_dis = esleme["student_external_ids"].get(
                str(kagit["ogrenci_no"] or "")
            )
            if not ogrenci_dis:
                continue
            for kutu in depo.kutular(kagit["id"]):
                soru_dis = esleme["question_external_ids"].get(str(kutu["soru_no"]))
                if not soru_dis or kutu["son_puan"] is None:
                    continue
                sonuclar.append(
                    {
                        "student_external_id": ogrenci_dis,
                        "question_external_id": soru_dis,
                        "final_score": kutu["son_puan"],
                        "confidence": kutu["puanlama_guveni"],
                        "approved": True,
                        "decision_source": (
                            "teacher" if kutu["degistirildi"] else "teacher_approved"
                        ),
                    }
                )
        manifest = {
            "schema_version": 1,
            "protocol_version": "v1",
            "source_app": "sinav-okur",
            "export_id": f"results:{kimlik}:{uuid4()}",
            "type": "exam_results",
            "exam_external_id": esleme["exam_external_id"],
            "results": sonuclar,
        }
        tampon = io.BytesIO()
        with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
            paket.writestr(
                "manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2)
            )
        return Response(
            tampon.getvalue(),
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={kimlik}-results.zip"},
        )

    return router
