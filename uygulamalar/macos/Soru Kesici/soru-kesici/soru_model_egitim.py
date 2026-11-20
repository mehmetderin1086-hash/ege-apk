#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soru-özel DocLayout-YOLO veri sözleşmesi ve çevrimdışı eğitim planı.

Bu modül eğitim yapmaz, paket/model indirmez ve ağ çağrısı içermez. Yerel veri
manifestini, YOLO etiketlerini ve belge/yayınevi split izolasyonunu doğrular;
ardından resmi ``doclayout_yolo.YOLOv10`` API'sini kullanan yerel işçi için
komut + çevrimdışı ortam hazırlar.

Manifest özeti (V1)::

    {
      "schema_version": "soru-kesici.question-layout-training/v1",
      "dataset_id": "anonim-korpus-2026-01",
      "classes": ["question_anchor", "question_body",
                  "shared_stimulus", "solution_or_answer"],
      "root": ".",
      "splits": {
        "train": [{"image": "images/train/a.png",
                   "label": "labels/train/a.txt",
                   "document_sha256": "<64 hex>", "page": 1,
                   "publisher_group": "pub-opaque-01"}],
        "validation": [...], "calibration": [...], "holdout": [...]
      }
    }

Kaynak PDF/DOCX yolları/isimleri manifestte yasaktır. Yalnız türetilmiş yerel
sayfa görseli/etiketi ve kaynak belgenin SHA-256'sı bulunur. Aynı belge veya
``publisher_group`` birden fazla splitte görülürse doğrulama başarısız olur.
"""

import argparse
import contextlib
import datetime as _datetime
import hashlib
import json
import math
import os
import pathlib
import shutil
import sys
import tempfile

import duzen_model


EGITIM_SEMA_SURUMU = "soru-kesici.question-layout-training/v1"
SINIFLAR = duzen_model.SORU_MODEL_SINIFLARI
SPLITLER = ("train", "validation", "calibration", "holdout")
GORUNTU_UZANTILARI = frozenset({
    ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp"
})
YASAK_KAYNAK_ALANLARI = frozenset({
    "source", "source_path", "source_file", "source_name", "document_path",
    "pdf_path", "docx_path", "original_path", "original_filename", "uri",
    "url", "upload_url",
})
CEVRIMDISI_ORTAM = {
    "HF_HUB_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "ULTRALYTICS_OFFLINE": "true",
    "WANDB_DISABLED": "true",
    "WANDB_MODE": "disabled",
    "COMET_MODE": "DISABLED",
}


def _sha256_dosya(yol):
    ozet = hashlib.sha256()
    with open(yol, "rb") as f:
        while True:
            parca = f.read(1 << 20)
            if not parca:
                break
            ozet.update(parca)
    return ozet.hexdigest()


def _sha256_mi(deger):
    return (isinstance(deger, str) and len(deger) == 64
            and all(c in "0123456789abcdef" for c in deger.lower()))


def _guvenli_yerel_yol(kok, deger, alan):
    if not isinstance(deger, str) or not deger.strip():
        raise ValueError(f"{alan}: boş/olmayan yol")
    deger = deger.strip()
    if "://" in deger or os.path.isabs(deger):
        raise ValueError(f"{alan}: yalnız göreli yerel yol kullanılabilir")
    parcalar = pathlib.PurePosixPath(deger.replace("\\", "/")).parts
    if ".." in parcalar:
        raise ValueError(f"{alan}: üst dizine çıkış yasak")
    kok_gercek = os.path.realpath(kok)
    hedef = os.path.realpath(os.path.join(kok_gercek, *parcalar))
    try:
        ortak = os.path.commonpath((kok_gercek, hedef))
    except ValueError:
        ortak = ""
    if ortak != kok_gercek:
        raise ValueError(f"{alan}: veri kökü dışına çıkıyor")
    return hedef, "/".join(parcalar)


def _yolo_etiket_dogrula(yol, ornek_adi, hatalar, sinif_sayilari):
    try:
        with open(yol, encoding="utf-8") as f:
            satirlar = list(f)
    except OSError as e:
        hatalar.append(f"{ornek_adi}.label okunamadı: {e}")
        return 0
    kutu_sayisi = 0
    geometri_siniflari = {}
    for no, satir in enumerate(satirlar, 1):
        satir = satir.strip()
        if not satir:
            continue
        alanlar = satir.split()
        if len(alanlar) != 5:
            hatalar.append(
                f"{ornek_adi}.label:{no}: YOLO detection satırı 5 alan olmalı")
            continue
        try:
            sinif = int(alanlar[0])
            x, y, w, h = (float(v) for v in alanlar[1:])
        except ValueError:
            hatalar.append(f"{ornek_adi}.label:{no}: sayısal alan geçersiz")
            continue
        if not 0 <= sinif < len(SINIFLAR):
            hatalar.append(f"{ornek_adi}.label:{no}: sınıf kimliği geçersiz")
            continue
        if not all(math.isfinite(v) for v in (x, y, w, h)):
            hatalar.append(f"{ornek_adi}.label:{no}: sonlu olmayan koordinat")
            continue
        if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < w <= 1 and 0 < h <= 1):
            hatalar.append(
                f"{ornek_adi}.label:{no}: normalize kutu [0,1] dışında")
            continue
        if x - w / 2 < -1e-6 or x + w / 2 > 1 + 1e-6 \
                or y - h / 2 < -1e-6 or y + h / 2 > 1 + 1e-6:
            hatalar.append(f"{ornek_adi}.label:{no}: kutu görüntü dışına taşıyor")
            continue
        geometri = tuple(round(v, 6) for v in (x, y, w, h))
        onceki_sinif = geometri_siniflari.get(geometri)
        if onceki_sinif is not None and onceki_sinif != sinif:
            hatalar.append(
                f"{ornek_adi}.label:{no}: aynı kutu birden fazla sınıfta "
                f"({onceki_sinif}, {sinif})")
            continue
        geometri_siniflari[geometri] = sinif
        sinif_sayilari[SINIFLAR[sinif]] += 1
        kutu_sayisi += 1
    return kutu_sayisi


def _harici_baglanti_var_mi(nesne):
    if isinstance(nesne, dict):
        return any(_harici_baglanti_var_mi(k) or _harici_baglanti_var_mi(v)
                   for k, v in nesne.items())
    if isinstance(nesne, (list, tuple)):
        return any(_harici_baglanti_var_mi(v) for v in nesne)
    return isinstance(nesne, str) and any(
        nesne.strip().lower().startswith(on_ek)
        for on_ek in ("http://", "https://", "s3://", "gs://", "ftp://"))


def manifest_dogrula(manifest_yolu, dosyalari_dogrula=True):
    """Eğitim manifestini ve isteğe bağlı tüm yerel dosyaları doğrular.

    Hata için istisna atmaz; ``ok/hatalar/uyarilar/istatistik`` raporu döner.
    ``dataset_fingerprint`` manifest + mevcut türetilmiş sayfa/etiket
    içeriklerinin deterministik özetidir ve model manifestine yazılabilir.
    """
    manifest_yolu = os.path.abspath(os.fspath(manifest_yolu))
    hatalar, uyarilar = [], []
    try:
        with open(manifest_yolu, encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as e:
        return {"ok": False, "hatalar": [f"manifest okunamadı: {e}"],
                "uyarilar": [], "istatistik": {}, "manifest": None}
    if not isinstance(manifest, dict):
        return {"ok": False, "hatalar": ["manifest JSON nesnesi olmalı"],
                "uyarilar": [], "istatistik": {}, "manifest": None}
    if manifest.get("schema_version") != EGITIM_SEMA_SURUMU:
        hatalar.append("schema_version uyumsuz")
    if tuple(manifest.get("classes") or ()) != SINIFLAR:
        hatalar.append("classes sırası soru-modeli sözleşmesiyle aynı olmalı")
    dataset_id = manifest.get("dataset_id")
    if not isinstance(dataset_id, str) or not dataset_id.strip():
        hatalar.append("dataset_id eksik")
    if _harici_baglanti_var_mi(manifest):
        hatalar.append("manifest harici ağ adresi içeremez")
    kok_degeri = manifest.get("root", ".")
    try:
        veri_koku, _ = _guvenli_yerel_yol(
            os.path.dirname(manifest_yolu), kok_degeri, "root")
    except ValueError as e:
        hatalar.append(str(e))
        veri_koku = os.path.dirname(manifest_yolu)
    splitler = manifest.get("splits")
    if not isinstance(splitler, dict):
        hatalar.append("splits nesnesi eksik")
        splitler = {}
    bilinmeyen = sorted(set(splitler) - set(SPLITLER))
    if bilinmeyen:
        hatalar.append("bilinmeyen split: " + ", ".join(bilinmeyen))
    for zorunlu in ("train", "validation"):
        if not isinstance(splitler.get(zorunlu), list) or not splitler[zorunlu]:
            hatalar.append(f"{zorunlu} split'i boş/eksik")
    for onerilen in ("calibration", "holdout"):
        if not isinstance(splitler.get(onerilen), list) or not splitler[onerilen]:
            uyarilar.append(f"{onerilen} split'i yok; kalite kapısı için eklenmeli")

    sinif_sayilari = {sinif: 0 for sinif in SINIFLAR}
    split_sayilari = {split: 0 for split in SPLITLER}
    split_kutu_sayilari = {split: 0 for split in SPLITLER}
    belge_splitleri, yayinevi_splitleri = {}, {}
    gorulen_sayfalar = set()
    fingerprint_parcalari = []
    dogrulanmis_ornekler = {split: [] for split in SPLITLER}
    for split in SPLITLER:
        ornekler = splitler.get(split, [])
        if not isinstance(ornekler, list):
            hatalar.append(f"splits.{split} liste olmalı")
            continue
        for i, ornek in enumerate(ornekler):
            ad = f"splits.{split}[{i}]"
            if not isinstance(ornek, dict):
                hatalar.append(f"{ad}: nesne olmalı")
                continue
            yasak = sorted(set(ornek) & YASAK_KAYNAK_ALANLARI)
            if yasak:
                hatalar.append(f"{ad}: kaynak adı/yolu alanı yasak: {', '.join(yasak)}")
            sha = ornek.get("document_sha256")
            if not _sha256_mi(sha):
                hatalar.append(f"{ad}.document_sha256 geçersiz")
                sha = None
            else:
                sha = sha.lower()
                belge_splitleri.setdefault(sha, set()).add(split)
            sayfa = ornek.get("page")
            if not isinstance(sayfa, int) or isinstance(sayfa, bool) or sayfa < 1:
                hatalar.append(f"{ad}.page pozitif tam sayı olmalı")
            elif sha:
                anahtar = (sha, sayfa)
                if anahtar in gorulen_sayfalar:
                    hatalar.append(f"{ad}: aynı belge/sayfa birden fazla kez listelenmiş")
                gorulen_sayfalar.add(anahtar)
            grup = ornek.get("publisher_group")
            if grup is None:
                uyarilar.append(f"{ad}.publisher_group yok")
            elif not isinstance(grup, str) or not grup.strip() or len(grup) > 128:
                hatalar.append(f"{ad}.publisher_group geçersiz")
            else:
                yayinevi_splitleri.setdefault(grup.strip(), set()).add(split)
            try:
                g_yolu, g_goreli = _guvenli_yerel_yol(
                    veri_koku, ornek.get("image"), f"{ad}.image")
                e_yolu, e_goreli = _guvenli_yerel_yol(
                    veri_koku, ornek.get("label"), f"{ad}.label")
            except ValueError as e:
                hatalar.append(str(e))
                continue
            if os.path.splitext(g_goreli)[1].lower() not in GORUNTU_UZANTILARI:
                hatalar.append(f"{ad}.image desteklenmeyen uzantı")
            if os.path.splitext(e_goreli)[1].lower() != ".txt":
                hatalar.append(f"{ad}.label .txt olmalı")
            kayit = {"image": g_goreli, "label": e_goreli,
                     "document_sha256": sha, "page": sayfa,
                     "publisher_group": grup}
            dogrulanmis_ornekler[split].append(kayit)
            split_sayilari[split] += 1
            if not dosyalari_dogrula:
                continue
            if not os.path.isfile(g_yolu):
                hatalar.append(f"{ad}.image bulunamadı")
                continue
            if not os.path.isfile(e_yolu):
                hatalar.append(f"{ad}.label bulunamadı")
                continue
            try:
                g_sha, e_sha = _sha256_dosya(g_yolu), _sha256_dosya(e_yolu)
            except OSError as e:
                hatalar.append(f"{ad}: dosya özeti alınamadı: {e}")
                continue
            for alan, gercek in (("image_sha256", g_sha),
                                 ("label_sha256", e_sha)):
                beklenen = ornek.get(alan)
                if beklenen is not None and (not _sha256_mi(beklenen)
                                              or beklenen.lower() != gercek):
                    hatalar.append(f"{ad}.{alan} dosyayla eşleşmiyor")
            fingerprint_parcalari.append(
                f"{split}\0{g_goreli}\0{g_sha}\0{e_goreli}\0{e_sha}")
            split_kutu_sayilari[split] += _yolo_etiket_dogrula(
                e_yolu, ad, hatalar, sinif_sayilari)

    for sha, bolumler in belge_splitleri.items():
        if len(bolumler) > 1:
            hatalar.append(
                f"belge split sızıntısı {sha[:12]}: {', '.join(sorted(bolumler))}")
    for grup, bolumler in yayinevi_splitleri.items():
        if len(bolumler) > 1:
            hatalar.append(
                f"yayınevi split sızıntısı {grup}: {', '.join(sorted(bolumler))}")
    if dosyalari_dogrula:
        for sinif, sayi in sinif_sayilari.items():
            if sayi == 0:
                uyarilar.append(f"hiç {sinif} etiketi yok")
    # Uyarıların yüzlerce kez tekrarlanmasını engelle, ilk görülen sırası kalsın.
    uyarilar = list(dict.fromkeys(uyarilar))
    manifest_kanonik = json.dumps(manifest, ensure_ascii=False,
                                  sort_keys=True, separators=(",", ":"))
    fp = hashlib.sha256()
    fp.update(manifest_kanonik.encode("utf-8"))
    for parca in sorted(fingerprint_parcalari):
        fp.update(b"\0")
        fp.update(parca.encode("utf-8"))
    return {
        "ok": not hatalar,
        "hatalar": hatalar,
        "uyarilar": uyarilar,
        "istatistik": {
            "samples": split_sayilari,
            "boxes": split_kutu_sayilari,
            "classes": sinif_sayilari,
            "documents": len(belge_splitleri),
            "publisher_groups": len(yayinevi_splitleri),
        },
        "schema_version": EGITIM_SEMA_SURUMU,
        "dataset_id": dataset_id,
        "dataset_root": veri_koku,
        "dataset_fingerprint": fp.hexdigest(),
        "manifest_sha256": _sha256_dosya(manifest_yolu),
        "manifest": manifest,
        "samples": dogrulanmis_ornekler,
    }


def _atomik_json_yaz(yol, veri):
    os.makedirs(os.path.dirname(os.path.abspath(yol)), exist_ok=True)
    fd, gecici = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(yol)), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(veri, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(gecici, yol)
    except BaseException:
        try:
            os.unlink(gecici)
        except OSError:
            pass
        raise


def _liste_yaz(yol, satirlar):
    os.makedirs(os.path.dirname(os.path.abspath(yol)), exist_ok=True)
    fd, gecici = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(yol)), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            for satir in satirlar:
                f.write(satir + "\n")
        os.replace(gecici, yol)
    except BaseException:
        try:
            os.unlink(gecici)
        except OSError:
            pass
        raise


def _yaml_tirnak(deger):
    # JSON string YAML 1.2'de de geçerli ve platform yollarını güvenle kaçırır.
    return json.dumps(str(deger), ensure_ascii=False)


def egitim_plani_hazirla(manifest_yolu, doclayout_repo, baslangic_modeli,
                         cikti_dizini, python_yolu=None, epochs=100,
                         imgsz=1280, batch=8, device="mps", workers=4):
    """Doğrulanmış veri için yerel/offline DocLayout eğitim planı üretir.

    Yalnız ``train`` ve ``validation`` listeleri eğitim YAML'ına girer;
    ``calibration`` ve ``holdout`` bilinçli olarak dışarıda bırakılır. Dönen
    ``command`` yalnız yerel :mod:`soru_model_egitim_isci` betiğini çağırır.
    """
    rapor = manifest_dogrula(manifest_yolu, dosyalari_dogrula=True)
    if not rapor["ok"]:
        raise ValueError("eğitim manifesti geçersiz: " + "; ".join(
            rapor["hatalar"][:8]))
    doclayout_repo = os.path.abspath(os.fspath(doclayout_repo))
    baslangic_modeli = os.path.abspath(os.fspath(baslangic_modeli))
    cikti_dizini = os.path.abspath(os.fspath(cikti_dizini))
    if not os.path.isdir(doclayout_repo):
        raise ValueError("yerel DocLayout-YOLO deposu bulunamadı")
    if not (os.path.isdir(os.path.join(doclayout_repo, "doclayout_yolo"))
            or os.path.isfile(os.path.join(doclayout_repo, "pyproject.toml"))
            or os.path.isfile(os.path.join(doclayout_repo, "setup.py"))):
        raise ValueError("dizin DocLayout-YOLO deposuna benzemiyor")
    if not os.path.isfile(baslangic_modeli):
        raise ValueError("yerel başlangıç modeli bulunamadı; indirme yapılmaz")
    for ad, deger, alt, ust in (
            ("epochs", epochs, 1, 10000), ("imgsz", imgsz, 320, 4096),
            ("batch", batch, 1, 512), ("workers", workers, 0, 64)):
        if not isinstance(deger, int) or isinstance(deger, bool) \
                or not alt <= deger <= ust:
            raise ValueError(f"{ad} {alt}..{ust} arasında tam sayı olmalı")
    os.makedirs(cikti_dizini, exist_ok=True)
    liste_yollari = {}
    for split in ("train", "validation"):
        yol = os.path.join(cikti_dizini, split + ".txt")
        _liste_yaz(yol, [
            os.path.join(rapor["dataset_root"], *o["image"].split("/"))
            for o in rapor["samples"][split]
        ])
        liste_yollari[split] = yol
    yaml_yolu = os.path.join(cikti_dizini, "question_layout_v3.yaml")
    yaml_satirlari = [
        "# Otomatik üretildi; calibration/holdout bu dosyada kasıtlı yoktur.",
        "path: " + _yaml_tirnak(rapor["dataset_root"]),
        "train: " + _yaml_tirnak(liste_yollari["train"]),
        "val: " + _yaml_tirnak(liste_yollari["validation"]),
        "names:",
    ]
    yaml_satirlari.extend(
        f"  {i}: {_yaml_tirnak(sinif)}" for i, sinif in enumerate(SINIFLAR))
    _liste_yaz(yaml_yolu, yaml_satirlari)
    python_yolu = os.path.abspath(python_yolu or sys.executable)
    isci = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "soru_model_egitim_isci.py")
    komut = [
        python_yolu, isci,
        "--doclayout-repo", doclayout_repo,
        "--model", baslangic_modeli,
        "--data", yaml_yolu,
        "--output", os.path.join(cikti_dizini, "runs"),
        "--epochs", str(epochs), "--imgsz", str(imgsz),
        "--batch", str(batch), "--device", str(device),
        "--workers", str(workers),
    ]
    plan = {
        "schema_version": "soru-kesici.question-layout-training-plan/v1",
        "dataset_id": rapor["dataset_id"],
        "dataset_fingerprint": rapor["dataset_fingerprint"],
        "classes": list(SINIFLAR),
        "command": komut,
        "environment": dict(CEVRIMDISI_ORTAM),
        "network_required": False,
        "uploads_enabled": False,
        "training_splits": ["train", "validation"],
        "excluded_splits": ["calibration", "holdout"],
        "data_yaml": yaml_yolu,
        "output_dir": os.path.join(cikti_dizini, "runs"),
    }
    plan_yolu = os.path.join(cikti_dizini, "egitim_plani.json")
    _atomik_json_yaz(plan_yolu, plan)
    plan["plan_path"] = plan_yolu
    return plan


def model_manifesti_yaz(agirlik_yolu, dataset_fingerprint, model_version,
                         hedef_yolu=None, ek_bilgi=None):
    """Eğitim çıktısı için :mod:`duzen_model` tarafından kilitlenen manifest."""
    agirlik_yolu = os.path.abspath(os.fspath(agirlik_yolu))
    if not os.path.isfile(agirlik_yolu):
        raise ValueError("ağırlık dosyası bulunamadı")
    if not isinstance(model_version, str) or not model_version.strip():
        raise ValueError("model_version boş olamaz")
    if not _sha256_mi(dataset_fingerprint):
        raise ValueError("dataset_fingerprint SHA-256 olmalı")
    manifest = {
        "schema_version": duzen_model.SORU_MODEL_SEMA_SURUMU,
        "model_version": model_version.strip(),
        "classes": list(SINIFLAR),
        "weights_sha256": _sha256_dosya(agirlik_yolu),
        "weights_size": os.stat(agirlik_yolu).st_size,
        "training_dataset_sha256": dataset_fingerprint.lower(),
        "framework": "DocLayout-YOLO",
        "created_at": _datetime.datetime.now(
            _datetime.timezone.utc).replace(microsecond=0).isoformat(),
    }
    if ek_bilgi is not None:
        if not isinstance(ek_bilgi, dict):
            raise ValueError("ek_bilgi nesne olmalı")
        # Yerel kaynak yolunu model manifestine taşımayı önle.
        if _harici_baglanti_var_mi(ek_bilgi) or any(
                str(k).casefold() in YASAK_KAYNAK_ALANLARI for k in ek_bilgi):
            raise ValueError("ek_bilgi harici adres/kaynak yolu içeremez")
        manifest["metadata"] = ek_bilgi
    hedef_yolu = hedef_yolu or (agirlik_yolu + ".manifest.json")
    _atomik_json_yaz(hedef_yolu, manifest)
    return manifest


@contextlib.contextmanager
def _aday_model_degerlendirme_baglami(dm, best_yolu, dataset_fingerprint):
    """Aday ağırlığı üretim modelinden bütünüyle yalıtılmış biçimde etkinleştir.

    ``duzen_model`` süreç-global yollar ve tek bir uzun ömürlü soru işçisi
    kullanır. Holdout değerlendirmesinde bu globals'ların üretim ağırlığını
    göstermesi, yeni ``best.pt`` yerine kurulu eski modeli ölçer. Bu bağlam
    adayı geçici bir dosyaya kopyalar, ona doğrulanabilir bir yan manifest ve
    boş cache verir; mevcut işçiyi geçişten önce/sonra kapatır. Değiştirilen
    bütün globals hata halinde de geri yüklenir. Eski işçi süreç olarak geri
    getirilemez; üretim globals'larıyla bir sonraki istekte temiz başlatılır.
    """
    best_yolu = os.path.abspath(os.fspath(best_yolu))
    if not os.path.isfile(best_yolu):
        raise ValueError("aday model ağırlığı bulunamadı")

    degisen_adlar = (
        "SORU_MODEL_YOLU",
        "SORU_MODEL_MANIFEST_YOLU",
        "SORU_MODEL_CACHE_DIZIN",
        "SORU_MODEL_AKTIF_ZORLA",
        "_SORU_BOZUK",
        "_SORU_PROBE_SONUC",
        "_SORU_MANIFEST_CACHE",
        "_SORU_SAYAC",
        "_SORU_DURUM_KIMLIK",
    )
    onceki = {ad: getattr(dm, ad) for ad in degisen_adlar}
    gecici = None
    try:
        dm._soru_oldur()
        dm._SORU_ISCI = None
        gecici = tempfile.TemporaryDirectory(
            prefix="soru-model-aday-degerlendirme-")
        aday_model = os.path.join(gecici.name, "candidate.pt")
        aday_manifest = aday_model + ".manifest.json"
        aday_cache = os.path.join(gecici.name, "cache")
        # Ayrı inode: işçi/model kitaplığı beklenmedik biçimde dosyaya dokunsa
        # bile indirilen aday veya kurulu üretim ağırlığı değiştirilemez.
        shutil.copy2(best_yolu, aday_model)
        model_manifesti_yaz(
            aday_model,
            dataset_fingerprint,
            "candidate-evaluation",
            hedef_yolu=aday_manifest,
            ek_bilgi={"purpose": "holdout_evaluation"},
        )

        dm.SORU_MODEL_YOLU = aday_model
        dm.SORU_MODEL_MANIFEST_YOLU = aday_manifest
        dm.SORU_MODEL_CACHE_DIZIN = aday_cache
        dm.SORU_MODEL_AKTIF_ZORLA = True
        dm._SORU_BOZUK = False
        dm._SORU_PROBE_SONUC = None
        dm._SORU_MANIFEST_CACHE = None
        dm._SORU_SAYAC = 0
        dm._SORU_ISCI_KIMLIK = None

        kontrol = dm.soru_modeli_dogrula(derin=False)
        if not kontrol.get("ok"):
            raise RuntimeError(
                "aday model sözleşmesi geçersiz: "
                + str(kontrol.get("mesaj") or "bilinmeyen hata"))
        yield {
            "model_yolu": aday_model,
            "manifest_yolu": aday_manifest,
            "cache_dizini": aday_cache,
        }
    finally:
        # Geçici model silinmeden önce onu açık tutan işçiyi mutlaka kapat.
        try:
            dm._soru_oldur()
        finally:
            dm._SORU_ISCI = None
            dm._SORU_ISCI_KIMLIK = None
            for ad, deger in onceki.items():
                setattr(dm, ad, deger)
            if gecici is not None:
                gecici.cleanup()


def _venv_ml_python():
    kok = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(kok, ".venv-ml", "bin", "python")


def _doclayout_repo():
    """.venv-ml site-packages içindeki doclayout_yolo paket kökü."""
    import glob as _glob
    kok = os.path.dirname(os.path.abspath(__file__))
    for sp in _glob.glob(os.path.join(kok, ".venv-ml", "lib", "python*",
                                      "site-packages")):
        if os.path.isdir(os.path.join(sp, "doclayout_yolo")):
            return sp
    return None


def calistir(manifest_yolu, cikti_dizini, *, epochs=60, imgsz=1280, batch=4,
             device="mps", patience=12):
    """Eğitim planını hazırlar ve .venv-ml işçisini subprocess olarak koşar,
    ilerlemeyi akıtır. Dönüş: {ok, best_path} | {ok:False, hata}."""
    import subprocess
    import time
    import uuid

    import duzen_model
    repo = _doclayout_repo()
    if not repo:
        return {"ok": False, "hata": ".venv-ml/doclayout_yolo bulunamadı "
                "(önce python3 duzen_kur.py)"}
    baslangic = duzen_model.MODEL_YOLU
    if not os.path.isfile(baslangic):
        return {"ok": False, "hata": "DocStructBench başlangıç ağırlığı yok"}
    plan = egitim_plani_hazirla(
        manifest_yolu, repo, baslangic, cikti_dizini,
        python_yolu=_venv_ml_python(), epochs=epochs, imgsz=imgsz,
        batch=batch, device=device)
    kosu_kimligi = uuid.uuid4().hex
    orkestrator_baslangic_ns = time.time_ns()
    komut = list(plan["command"]) + [
        "--patience", str(patience),
        "--run-id", kosu_kimligi,
    ]
    ortam = dict(os.environ, **plan["environment"])
    print("Eğitim başlıyor (saatler sürebilir; Ctrl-C ile durdurulabilir)…")
    proc = subprocess.Popen(komut, env=ortam, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    son = None
    son_json = None
    for satir in proc.stdout:
        satir = satir.rstrip()
        if satir.startswith("ILERLEME ") or satir.startswith("{"):
            print(satir)
            son = satir
        if satir.startswith("{"):
            try:
                aday = json.loads(satir)
            except ValueError:
                aday = None
            if isinstance(aday, dict):
                son_json = aday
    proc.wait()

    # Eski sonuc.json hiçbir koşulda yeni, başarısız bir işçiyi başarıya
    # çeviremez. Nonzero dönüş, diskte ne bulunursa bulunsun fail-closed'dur.
    if proc.returncode != 0:
        hata = (son_json.get("hata") if isinstance(son_json, dict) else None)
        return {
            "ok": False,
            "hata": hata or f"eğitim işçisi {proc.returncode} koduyla kapandı",
            "run_id": kosu_kimligi,
            "returncode": proc.returncode,
            "cikti": son,
        }

    sonuc_yolu = os.path.join(cikti_dizini, "runs", "sonuc.json")
    try:
        with open(sonuc_yolu) as f:
            sonuc = json.load(f)
    except (OSError, ValueError) as e:
        return {
            "ok": False,
            "hata": f"bu koşuya ait geçerli sonuc.json yok: {e}",
            "run_id": kosu_kimligi,
            "returncode": proc.returncode,
            "cikti": son,
        }
    if not isinstance(sonuc, dict) or not sonuc.get("ok"):
        return {
            "ok": False,
            "hata": (sonuc.get("hata") if isinstance(sonuc, dict) else None)
                    or "eğitim sonucu başarısız/geçersiz",
            "run_id": kosu_kimligi,
            "returncode": proc.returncode,
            "cikti": son,
        }
    if sonuc.get("run_id") != kosu_kimligi:
        return {
            "ok": False,
            "hata": "sonuc.json bu eğitim koşusuna ait değil",
            "run_id": kosu_kimligi,
            "returncode": proc.returncode,
            "cikti": son,
        }
    baslangic_ns = sonuc.get("started_at_ns")
    if (not isinstance(baslangic_ns, int)
            or isinstance(baslangic_ns, bool)
            or baslangic_ns < orkestrator_baslangic_ns):
        return {
            "ok": False,
            "hata": "sonuc.json başlangıç zamanı bu koşuyla eşleşmiyor",
            "run_id": kosu_kimligi,
            "returncode": proc.returncode,
            "cikti": son,
        }
    sonuc["returncode"] = proc.returncode
    return sonuc


def _kutu_eslesme_sayilari(tahminler, gercekler, esik=0.5):
    """Tahmin/gerçek kutularını sıra-bağımsız bire-bir IoU eşleştir.

    IoU eşiğini geçen kenarlarda augmenting-path ile maksimum kardinaliteli
    bipartite eşleştirme bulunur. Kenarlar yüksek IoU'dan denenir, fakat daha
    yüksek tek bir IoU iki geçerli eşleşmeyi engelliyorsa mevcut eşleşme
    yeniden yönlendirilir.
    """
    import dogrula

    komsuluk = {}
    for ti, tahmin in enumerate(tahminler):
        kenarlar = []
        for gi, gercek in enumerate(gercekler):
            iou = dogrula.kutu_iou(tahmin, gercek)
            if iou >= esik:
                kenarlar.append((iou, gi))
        komsuluk[ti] = sorted(kenarlar, key=lambda x: (-x[0], x[1]))

    # gercek -> tahmin. Bir tahmin için augmenting path ararken daha önce
    # eşleşmiş tahminleri başka uygun gerçeğe taşıyabiliriz; Kuhn algoritmasının
    # bu özelliği açgözlü IoU seçiminin kardinalite kaybını kapatır.
    gercek_eslesmesi = {}

    def _yerlestir(ti, gorulen_gercekler):
        for _iou, gi in komsuluk[ti]:
            if gi in gorulen_gercekler:
                continue
            gorulen_gercekler.add(gi)
            onceki_tahmin = gercek_eslesmesi.get(gi)
            if (onceki_tahmin is None
                    or _yerlestir(onceki_tahmin, gorulen_gercekler)):
                gercek_eslesmesi[gi] = ti
                return True
        return False

    # Az seçeneği olan tahminleri önce denemek yalnız deterministik/ucuz bir
    # tercih; augmenting path sayesinde sıra maksimum kardinaliteyi değiştirmez.
    tahmin_sirasi = sorted(
        range(len(tahminler)),
        key=lambda ti: (
            len(komsuluk[ti]),
            -max((iou for iou, _gi in komsuluk[ti]), default=-1.0),
            ti,
        ),
    )
    for ti in tahmin_sirasi:
        _yerlestir(ti, set())

    tp = len(gercek_eslesmesi)
    return tp, len(tahminler) - tp, len(gercekler) - tp


def degerlendir(manifest_yolu, best_yolu):
    """Holdout split'inde sınıf-başı IoU-tabanlı P/R/F1 hesaplar (dogrula
    yardımcılarıyla). Dört sınıfın tamamı ayrı ayrı raporlanır."""
    import duzen_model
    rapor = manifest_dogrula(manifest_yolu)
    if not rapor["ok"]:
        return {"ok": False, "hata": "manifest geçersiz"}
    kok = rapor["dataset_root"]
    holdout = rapor["samples"].get("holdout", [])
    if not holdout:
        return {"ok": False, "hata": "holdout split boş"}
    # Basit değerlendirme: modelle her holdout görselini çıkar, etiketle
    # ve IoU tabanlı bire-bir eşleştir.
    from PIL import Image
    dm = duzen_model
    sayaclar = {
        sinif: {"tp": 0, "fp": 0, "fn": 0}
        for sinif in SINIFLAR
    }
    try:
        with _aday_model_degerlendirme_baglami(
                dm, best_yolu, rapor["dataset_fingerprint"]) as aday_baglami:
            # Yayın bağı, değişebilen kaynak best.pt'nin daha önce alınmış
            # özetiyle değil gerçekten ölçülen değişmez kopyanın özetiyle
            # kurulmalıdır.
            aday_sha = _sha256_dosya(aday_baglami["model_yolu"])
            for o in holdout:
                img_yolu = os.path.join(kok, *o["image"].split("/"))
                with Image.open(img_yolu) as img:
                    bolgeler = dm.soru_bolgeleri_gorsel(
                        img, onbellek_kimlik=None)
                    if not isinstance(bolgeler, list):
                        raise RuntimeError(
                            "aday model çıkarımı liste döndürmedi")
                    # duzen_model çıkarım hatalarını sezgisel üretim yolu için
                    # []'a çevirir. Yayın kapısında bu sessizlik güvenli değildir:
                    # işçi çöktüyse boş tahmini gerçek FN gibi puanlama.
                    if getattr(dm, "_SORU_BOZUK", False):
                        raise RuntimeError("aday model çıkarım işçisi hata verdi")
                    isci = getattr(dm, "_SORU_ISCI", None)
                    if not isci or isci[0].poll() is not None:
                        raise RuntimeError(
                            "aday model çıkarım işçisi çalışmıyor")
                    W, H = img.size
                    tahminler = {
                        sinif: [
                            b["kutu"] for b in bolgeler
                            if b.get("sinif") == sinif
                        ]
                        for sinif in SINIFLAR
                    }
                gercek = {sinif: [] for sinif in SINIFLAR}
                etiket_yolu = os.path.join(kok, *o["label"].split("/"))
                with open(etiket_yolu, encoding="utf-8") as etiket:
                    for satir in etiket:
                        p = satir.split()
                        if len(p) == 5 and p[0].isdigit():
                            sinif_no = int(p[0])
                            if not 0 <= sinif_no < len(SINIFLAR):
                                continue
                            cx, cy, w, h = (float(x) for x in p[1:])
                            gercek[SINIFLAR[sinif_no]].append((
                                (cx - w / 2) * W, (cy - h / 2) * H,
                                (cx + w / 2) * W, (cy + h / 2) * H,
                            ))
                for sinif in SINIFLAR:
                    say_tp, say_fp, say_fn = _kutu_eslesme_sayilari(
                        tahminler[sinif], gercek[sinif], esik=0.5)
                    sayaclar[sinif]["tp"] += say_tp
                    sayaclar[sinif]["fp"] += say_fp
                    sayaclar[sinif]["fn"] += say_fn
    except Exception as e:  # noqa: BLE001 — yayın kapısı kapalı kalmalı
        return {
            "ok": False,
            "hata": f"aday model değerlendirmesi başarısız: "
                    f"{type(e).__name__}: {e}",
        }
    sonuc = {
        "ok": True,
        "recommended_conf": 0.25,
        "candidate_weights_sha256": aday_sha,
        "dataset_fingerprint": rapor["dataset_fingerprint"],
        "holdout_sample_count": len(holdout),
    }
    for sinif, sayac in sayaclar.items():
        tp, fp, fn = sayac["tp"], sayac["fp"], sayac["fn"]
        destek = tp + fn
        if destek == 0 and fp == 0:
            prec = rec = f1 = 1.0
        else:
            prec = tp / max(1, tp + fp)
            rec = tp / max(1, destek)
            f1 = 2 * prec * rec / max(1e-9, prec + rec)
        sonuc[sinif] = {
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1": round(f1, 4),
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "support": destek,
        }
    return sonuc


def _json_nesnesi_oku(yol, ad):
    if not yol:
        raise ValueError(f"{ad} yolu gerekli")
    try:
        with open(yol, encoding="utf-8") as f:
            veri = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError(f"{ad} okunamadı: {e}") from e
    if not isinstance(veri, dict):
        raise ValueError(f"{ad} JSON nesnesi olmalı")
    return veri


def _egitim_bagliligini_dogrula(
        sonuc_yolu, paket_manifest_yolu, aday_sha, aday_boyut,
        dataset_fingerprint):
    """Colab sonucu, yerel paket yan manifesti ve aday ağırlığını bağlar."""
    sonuc = _json_nesnesi_oku(sonuc_yolu, "eğitim sonuc.json")
    paket = _json_nesnesi_oku(
        paket_manifest_yolu, "Colab paket manifesti")
    if not sonuc.get("ok"):
        raise ValueError("eğitim sonucu başarılı değil")
    if sonuc.get("resume") is not False:
        raise ValueError("yayın için taze, resume=False eğitim koşusu gerekli")
    run_id = sonuc.get("run_id")
    if (not isinstance(run_id, str) or not run_id.strip()
            or len(run_id) > 128 or any(ord(c) < 32 for c in run_id)):
        raise ValueError("eğitim run_id geçersiz")
    if sonuc.get("best_sha256") != aday_sha:
        raise ValueError("eğitim sonucu best_sha256 ile aday ağırlık farklı")
    if sonuc.get("best_size") != aday_boyut:
        raise ValueError("eğitim sonucu best_size ile aday ağırlık farklı")
    if paket.get("package_schema_version") != (
            "soru-kesici.question-layout-colab-package/v1"):
        raise ValueError("Colab paket şeması uyumsuz")
    if tuple(paket.get("classes") or ()) != SINIFLAR:
        raise ValueError("Colab paket sınıf sırası uyumsuz")
    if paket.get("source_dataset_fingerprint") != dataset_fingerprint:
        raise ValueError("paket farklı eğitim veri setine ait")
    if sonuc.get("source_dataset_fingerprint") != dataset_fingerprint:
        raise ValueError("eğitim sonucu farklı veri setine ait")

    paket_base = paket.get("base_model") or {}
    alan_eslesmeleri = (
        ("training_package_sha256", "training_package_sha256"),
        ("archive_sha256", "archive_sha256"),
    )
    for sonuc_alani, paket_alani in alan_eslesmeleri:
        deger = sonuc.get(sonuc_alani)
        if not _sha256_mi(deger) or deger != paket.get(paket_alani):
            raise ValueError(
                f"{sonuc_alani} eğitim sonucu ile paket arasında uyuşmuyor")
    base_sha = sonuc.get("base_model_sha256")
    if not _sha256_mi(base_sha) or base_sha != paket_base.get("sha256"):
        raise ValueError(
            "base_model_sha256 eğitim sonucu ile paket arasında uyuşmuyor")
    if not isinstance(paket_base.get("size"), int) \
            or paket_base["size"] <= 0:
        raise ValueError("paket base_model boyutu geçersiz")
    return {
        "run_id": run_id.strip(),
        "training_package_sha256": sonuc["training_package_sha256"],
        "archive_sha256": sonuc["archive_sha256"],
        "base_model_sha256": base_sha,
        "source_dataset_fingerprint": dataset_fingerprint,
        "resume": False,
        "started_at_ns": sonuc.get("started_at_ns"),
        "finished_at_ns": sonuc.get("finished_at_ns"),
        "config": sonuc.get("config") if isinstance(
            sonuc.get("config"), dict) else {},
    }


def _sinif_kalite_bulgulari(degerlendirme, minimum_destek=None):
    """Dört sınıf için yayın kapısını sınıf-başı kalite/destekle değerlendir."""
    esikler = {
        "question_anchor": {"f1": 0.30, "recall": 0.30},
        "question_body": {"f1": 0.55, "recall": 0.50},
        "shared_stimulus": {"f1": 0.10, "recall": 0.10},
        "solution_or_answer": {"f1": 0.10, "recall": 0.10},
    }
    destek_esikleri = minimum_destek or {
        "question_anchor": 10,
        "question_body": 10,
        "shared_stimulus": 3,
        "solution_or_answer": 10,
    }
    bulgular = []
    for sinif in SINIFLAR:
        metrik = degerlendirme.get(sinif)
        if not isinstance(metrik, dict):
            bulgular.append(f"{sinif}: sınıf-başı değerlendirme eksik")
            continue
        destek = metrik.get("support")
        fp = metrik.get("fp")
        if not isinstance(destek, int) or destek < 0 \
                or not isinstance(fp, int) or fp < 0:
            bulgular.append(f"{sinif}: support/fp geçersiz")
            continue
        gereken_destek = destek_esikleri.get(sinif)
        if not isinstance(gereken_destek, int) or gereken_destek < 1:
            bulgular.append(f"{sinif}: minimum holdout desteği geçersiz")
            continue
        if destek < gereken_destek:
            bulgular.append(
                f"{sinif}: holdout desteği {destek} < {gereken_destek}; "
                "dört sınıf kapısı ölçülemedi")
            if destek == 0 and fp:
                bulgular.append(
                    f"{sinif}: holdout desteği yokken {fp} yanlış pozitif")
            continue
        for olcut, esik in esikler[sinif].items():
            deger = metrik.get(olcut)
            if not isinstance(deger, (int, float)) or not math.isfinite(deger):
                bulgular.append(f"{sinif}: {olcut} geçersiz")
            elif deger < esik:
                bulgular.append(
                    f"{sinif}: {olcut}={deger:.4f} < {esik:.4f}")
    return bulgular


def _fsync_dosya(yol):
    with open(yol, "rb") as f:
        os.fsync(f.fileno())


def _fsync_dizin(yol):
    fd = os.open(yol, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _surumlu_model_yayinla(
        best_yolu, dataset_fingerprint, model_version, metadata,
        beklenen_sha):
    """Değişmez sürüm dizini hazırla; tek symlink replace ile çifti etkinleştir."""
    import fcntl
    import uuid

    import duzen_model

    surumler = os.path.abspath(duzen_model.SORU_MODEL_SURUMLER_DIZINI)
    aktif = os.path.abspath(duzen_model.SORU_MODEL_AKTIF_BAGLANTI)
    model_dizini = os.path.dirname(aktif)
    os.makedirs(surumler, exist_ok=True)
    os.makedirs(model_dizini, exist_ok=True)
    kilit_yolu = os.path.join(model_dizini, ".question-layout-publish.lock")
    slug = "".join(
        c if c.isalnum() or c in "._-" else "-"
        for c in str(model_version)
    ).strip(".-_")[:48] or "model"

    with open(kilit_yolu, "a+b") as kilit:
        fcntl.flock(kilit.fileno(), fcntl.LOCK_EX)
        surum_id = f"{slug}-{beklenen_sha[:16]}-{uuid.uuid4().hex[:8]}"
        staging = tempfile.mkdtemp(
            dir=surumler, prefix=f".{surum_id}-hazirlaniyor-")
        nihai = os.path.join(surumler, surum_id)
        pointer_degisti = False
        gecici_baglanti = None
        onceki_hedef = None
        try:
            staged_model = os.path.join(staging, "model.pt")
            shutil.copy2(best_yolu, staged_model)
            staged_sha = _sha256_dosya(staged_model)
            if staged_sha != beklenen_sha:
                raise RuntimeError("staging aday SHA-256 değişti")
            staged_manifest = staged_model + ".manifest.json"
            staged_manifest_verisi = model_manifesti_yaz(
                staged_model,
                dataset_fingerprint,
                model_version,
                hedef_yolu=staged_manifest,
                ek_bilgi=metadata,
            )
            if staged_manifest_verisi.get("weights_sha256") != beklenen_sha:
                raise RuntimeError(
                    "staging manifesti beklenen aday SHA-256 ile eşleşmiyor")
            kontrol = duzen_model.soru_modeli_dogrula(
                derin=False,
                model_yolu=staged_model,
                manifest_yolu=staged_manifest,
            )
            if not kontrol.get("ok"):
                raise RuntimeError(
                    "sürümlü staging doğrulaması başarısız: "
                    + str(kontrol.get("mesaj")))
            if _sha256_dosya(staged_model) != beklenen_sha:
                raise RuntimeError(
                    "staging model manifest doğrulamasından sonra değişti")
            _fsync_dosya(staged_model)
            _fsync_dosya(staged_manifest)
            _fsync_dizin(staging)
            os.rename(staging, nihai)
            staging = None
            _fsync_dizin(surumler)

            if os.path.lexists(aktif):
                if not os.path.islink(aktif):
                    raise RuntimeError(
                        "aktif model işaretçisi symlink değil; üzerine yazılmadı")
                onceki_hedef = os.readlink(aktif)
            gecici_baglanti = os.path.join(
                model_dizini,
                f".question-layout-active-{uuid.uuid4().hex}.tmp",
            )
            os.symlink(os.path.relpath(nihai, model_dizini), gecici_baglanti)
            duzen_model.kapat()
            os.replace(gecici_baglanti, aktif)
            gecici_baglanti = None
            pointer_degisti = True
            _fsync_dizin(model_dizini)
            aktif_model = os.path.join(aktif, "model.pt")
            aktif_manifest = aktif_model + ".manifest.json"
            son_kontrol = duzen_model.soru_modeli_dogrula(
                derin=False,
                model_yolu=aktif_model,
                manifest_yolu=aktif_manifest,
            )
            if not son_kontrol.get("ok"):
                raise RuntimeError(
                    "aktif sürüm doğrulaması başarısız: "
                    + str(son_kontrol.get("mesaj")))
            duzen_model.soru_model_yollarini_esitle(zorla=True)
            return {
                **son_kontrol,
                "model_yolu": aktif_model,
                "manifest_yolu": aktif_manifest,
                "version_directory": nihai,
            }
        except BaseException:
            if pointer_degisti and os.path.islink(aktif):
                if onceki_hedef is None:
                    os.unlink(aktif)
                else:
                    geri = os.path.join(
                        model_dizini,
                        f".question-layout-rollback-{uuid.uuid4().hex}.tmp",
                    )
                    os.symlink(onceki_hedef, geri)
                    os.replace(geri, aktif)
                _fsync_dizin(model_dizini)
                duzen_model.soru_model_yollarini_esitle(zorla=True)
            raise
        finally:
            if gecici_baglanti and os.path.lexists(gecici_baglanti):
                os.unlink(gecici_baglanti)
            if staging and os.path.isdir(staging):
                shutil.rmtree(staging, ignore_errors=True)
            fcntl.flock(kilit.fileno(), fcntl.LOCK_UN)


def yayinla(
        best_yolu, manifest_yolu, model_version, degerlendirme=None,
        egitim_sonucu_yolu=None, paket_manifest_yolu=None):
    """Dört sınıf ve eğitim-provenance kapıları geçerse modeli atomik yayınla."""
    import duzen_model

    deg = degerlendirme or {}
    if not deg.get("ok"):
        return {"ok": False, "yayinlandi": False,
                "neden": "aday değerlendirmesi başarılı değil"}
    rapor = manifest_dogrula(manifest_yolu)
    if not rapor["ok"]:
        return {"ok": False, "yayinlandi": False,
                "neden": "eğitim manifesti geçersiz"}
    if deg.get("dataset_fingerprint") != rapor["dataset_fingerprint"]:
        return {"ok": False, "yayinlandi": False,
                "neden": "değerlendirilen holdout veri parmak izi farklı"}

    try:
        with tempfile.TemporaryDirectory(
                prefix="soru-model-yayin-adayi-") as gecici:
            sabit_aday = os.path.join(gecici, "candidate.pt")
            shutil.copy2(best_yolu, sabit_aday)
            aday_sha = _sha256_dosya(sabit_aday)
            aday_boyut = os.path.getsize(sabit_aday)
            if deg.get("candidate_weights_sha256") != aday_sha:
                return {"ok": False, "yayinlandi": False,
                        "neden": "değerlendirilen aday SHA-256 ile "
                                 "yayın adayı farklı"}
            sinif_bulgulari = _sinif_kalite_bulgulari(deg)
            if sinif_bulgulari:
                return {
                    "ok": False,
                    "yayinlandi": False,
                    "neden": "sınıf-başı kalite kapısı: "
                             + "; ".join(sinif_bulgulari),
                }
            baglilik = _egitim_bagliligini_dogrula(
                egitim_sonucu_yolu,
                paket_manifest_yolu,
                aday_sha,
                aday_boyut,
                rapor["dataset_fingerprint"],
            )
            metadata = {
                "holdout_by_class": {
                    sinif: deg[sinif] for sinif in SINIFLAR
                },
                "holdout_sample_count": deg.get("holdout_sample_count"),
                "recommended_conf": deg.get("recommended_conf"),
                "evaluation_candidate_sha256": aday_sha,
                "training": baglilik,
            }
            yayin = _surumlu_model_yayinla(
                sabit_aday,
                rapor["dataset_fingerprint"],
                model_version,
                metadata,
                aday_sha,
            )
    except Exception as e:  # noqa: BLE001 — aktif pointer eski sürümde kalır
        return {"ok": False, "yayinlandi": False,
                "neden": f"atomik yayın başarısız: {type(e).__name__}: {e}"}
    return {
        "ok": True,
        "yayinlandi": True,
        "model_yolu": yayin["model_yolu"],
        "manifest_yolu": yayin["manifest_yolu"],
        "weights_sha256": aday_sha,
        "model_id": yayin.get("model_id"),
    }


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Soru-özel model veri doğrulama + eğitim orkestrasyonu")
    p.add_argument("manifest")
    p.add_argument("--doclayout-repo")
    p.add_argument("--model")
    p.add_argument("--output")
    p.add_argument("--calistir", action="store_true",
                   help=".venv-ml işçisiyle eğit (saatler sürer)")
    p.add_argument("--degerlendir", metavar="BEST.pt",
                   help="holdout'ta best.pt'yi değerlendir")
    p.add_argument("--yayinla", metavar="BEST.pt",
                   help="kalite kapısı geçerse modeli üretime al")
    p.add_argument("--sonuc", metavar="sonuc.json",
                   help="--yayinla: Colab eğitim sonucu (zorunlu)")
    p.add_argument("--paket-manifest", metavar="ZIP.manifest.json",
                   help="--yayinla: yerel Colab paket yan manifesti (zorunlu)")
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--imgsz", type=int, default=1280)
    p.add_argument("--batch", type=int, default=4)
    p.add_argument("--surum", default="v3.0.0")
    args = p.parse_args(argv)

    if args.degerlendir:
        deg = degerlendir(args.manifest, args.degerlendir)
        print(json.dumps(deg, ensure_ascii=False, indent=2))
        return 0 if deg.get("ok") else 1
    if args.yayinla:
        if not args.sonuc or not args.paket_manifest:
            p.error("--yayinla için --sonuc ve --paket-manifest zorunlu")
        deg = degerlendir(args.manifest, args.yayinla)
        sonuc = yayinla(
            args.yayinla,
            args.manifest,
            args.surum,
            deg,
            egitim_sonucu_yolu=args.sonuc,
            paket_manifest_yolu=args.paket_manifest,
        )
        print(json.dumps(sonuc, ensure_ascii=False, indent=2))
        return 0 if sonuc.get("ok") else 1
    if args.calistir:
        cikti = args.output or os.path.join(
            os.path.dirname(os.path.abspath(args.manifest)), "egitim_ciktisi")
        print(json.dumps(calistir(args.manifest, cikti, epochs=args.epochs,
                                  imgsz=args.imgsz, batch=args.batch),
                         ensure_ascii=False, indent=2))
        return 0

    rapor = manifest_dogrula(args.manifest)
    if not rapor["ok"]:
        print(json.dumps(rapor, ensure_ascii=False, indent=2))
        return 2
    if args.doclayout_repo or args.model or args.output:
        if not all((args.doclayout_repo, args.model, args.output)):
            p.error("plan için --doclayout-repo, --model ve --output birlikte gerekir")
        plan = egitim_plani_hazirla(
            args.manifest, args.doclayout_repo, args.model, args.output)
        print(json.dumps(plan, ensure_ascii=False, indent=2))
    else:
        ozet = {k: rapor[k] for k in (
            "ok", "hatalar", "uyarilar", "istatistik",
            "dataset_fingerprint")}
        print(json.dumps(ozet, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
