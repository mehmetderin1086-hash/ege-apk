#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru-özel DocLayout-YOLO ince-ayar işçisi (.venv-ml altında koşar).

soru_model_egitim.egitim_plani_hazirla'nın ürettiği komut sözleşmesiyle
birebir uyumludur (--doclayout-repo --model --data --output --epochs
--imgsz --batch --device --workers) + --patience --resume. DocStructBench
ağırlığından transfer ile 4 sınıflı soru modeli eğitir; MPS'te güvenli
parametrelerle (amp kapalı, metin belgesi için ayna/döndürme kapalı).

Çevrimdışı ortam çağıran tarafından (CEVRIMDISI_ORTAM) verilir; bu betik
ağdan indirme yapmaz.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
import uuid


RESMI_BASE_MODEL_SHA256 = (
    "9a2ee0220fe3d9ad31b47e1d9f1282f46959a54e4618fce9cffcc9715b8286e2"
)
RESMI_BASE_MODEL_BOYUT = 40_709_302


def _dosya_sha256(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1 << 20), b""):
            h.update(parca)
    return h.hexdigest()


def _resmi_base_model_dogrula(yol):
    try:
        stat = os.stat(yol)
    except OSError as e:
        raise FileNotFoundError(
            f"resmi DocStructBench başlangıç ağırlığı bulunamadı: {yol}"
        ) from e
    if stat.st_size != RESMI_BASE_MODEL_BOYUT:
        raise ValueError(
            "DocStructBench başlangıç ağırlığı resmi boyutla uyuşmuyor")
    if _dosya_sha256(yol) != RESMI_BASE_MODEL_SHA256:
        raise ValueError(
            "DocStructBench başlangıç ağırlığı resmi SHA-256 ile uyuşmuyor")
    return {
        "sha256": RESMI_BASE_MODEL_SHA256,
        "size": RESMI_BASE_MODEL_BOYUT,
    }


def _best_yolu(cikti):
    return os.path.join(cikti, "ql_v3", "weights", "best.pt")


def _last_yolu(cikti):
    return os.path.join(cikti, "ql_v3", "weights", "last.pt")


def _dosya_imzasi(yol):
    if not os.path.isfile(yol):
        return None
    stat = os.stat(yol)
    return {
        "sha256": _dosya_sha256(yol),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def _sonuc_yaz(cikti_dizin, kayit):
    os.makedirs(cikti_dizin, exist_ok=True)
    fd, gecici = tempfile.mkstemp(dir=cikti_dizin, suffix=".sonuc.tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(kayit, f, ensure_ascii=False, indent=1)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(gecici, os.path.join(cikti_dizin, "sonuc.json"))
    except BaseException:
        try:
            os.unlink(gecici)
        except OSError:
            pass
        raise


def _bitir(cikti_dizin, kosu_kimligi, kayit, kod):
    kayit = dict(kayit)
    kayit.setdefault("run_id", kosu_kimligi)
    kayit.setdefault("finished_at_ns", time.time_ns())
    try:
        _sonuc_yaz(cikti_dizin, kayit)
    except OSError as e:
        kayit["sonuc_yazma_hatasi"] = f"{type(e).__name__}: {e}"
        kod = kod or 1
    print(json.dumps(kayit, ensure_ascii=False))
    return kod


def _ilerleme_yaz(cikti_dizin, kayit):
    try:
        os.makedirs(cikti_dizin, exist_ok=True)
        with open(os.path.join(cikti_dizin, "ilerleme.jsonl"), "a") as f:
            f.write(json.dumps(kayit, ensure_ascii=False) + "\n")
    except OSError:
        pass
    print("ILERLEME " + json.dumps(kayit, ensure_ascii=False), flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--doclayout-repo", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--data", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--imgsz", type=int, default=1280)
    p.add_argument("--batch", type=int, default=4)
    p.add_argument("--device", default="mps")
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--patience", type=int, default=12)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--run-id")
    args = p.parse_args()

    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    os.makedirs(args.output, exist_ok=True)
    kosu_kimligi = args.run_id or uuid.uuid4().hex
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", kosu_kimligi):
        return _bitir(args.output, "gecersiz", {
            "ok": False,
            "hata": "run-id yalnız harf, rakam, nokta, _ ve - içerebilir",
        }, 2)

    best = _best_yolu(args.output)
    last = _last_yolu(args.output)
    try:
        onceki_best = _dosya_imzasi(best)
        onceki_last = _dosya_imzasi(last)
    except OSError as e:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"mevcut checkpoint okunamadı: {type(e).__name__}: {e}",
        }, 2)
    if not args.resume and (onceki_best is not None or onceki_last is not None):
        eski_ad = "best.pt" if onceki_best is not None else "last.pt"
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"çıktı dizininde eski {eski_ad} var; yeni eğitim için "
                    "boş/sürümlü bir --output kullanın",
            "best_path": best if onceki_best is not None else None,
            "last_path": last if onceki_last is not None else None,
        }, 2)
    if args.resume and onceki_last is None:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": "--resume için ilerletilecek last.pt bulunamadı",
            "last_path": last,
        }, 2)
    try:
        temel_imza = _resmi_base_model_dogrula(args.model)
        veri_baslangic_sha = _dosya_sha256(args.data)
    except (OSError, ValueError) as e:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"eğitim güven kökü/girdisi geçersiz: {type(e).__name__}: {e}",
        }, 2)

    # numpy 2.x uyumluluğu: np.trapz kaldırıldı (→ trapezoid). doclayout_yolo/
    # ultralytics metrik hesabı eski adı kullanıyor; güvenli takma ad kur.
    try:
        import numpy as _np
        if not hasattr(_np, "trapz") and hasattr(_np, "trapezoid"):
            _np.trapz = _np.trapezoid
    except Exception:  # noqa: BLE001
        pass

    try:
        import torch
        from doclayout_yolo import YOLOv10
    except Exception as e:  # noqa: BLE001
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"{type(e).__name__}: {e}",
        }, 1)

    cihaz = args.device
    if cihaz == "mps" and not torch.backends.mps.is_available():
        cihaz = "cpu"

    model_kaynagi = last if args.resume else args.model
    model_gecici = tempfile.mkdtemp(prefix="soru-egitim-model-")
    try:
        beklenen_model_sha = (
            onceki_last["sha256"]
            if args.resume else temel_imza["sha256"]
        )
        sabit_model = os.path.join(model_gecici, "dogrulanmis-model.pt")
        shutil.copy2(model_kaynagi, sabit_model)
        if _dosya_sha256(sabit_model) != beklenen_model_sha:
            raise RuntimeError("model kaynağı kopyalama sırasında değişti")
        asil_load = torch.load

        def sinirli_load(*load_args, **load_kwargs):
            if not load_args:
                raise RuntimeError("torch.load model yolu eksik")
            gelen = os.path.realpath(os.fspath(load_args[0]))
            if gelen != os.path.realpath(sabit_model):
                raise RuntimeError(
                    f"doğrulanmamış checkpoint reddedildi: {gelen}")
            load_kwargs["weights_only"] = False
            return asil_load(*load_args, **load_kwargs)

        torch.load = sinirli_load
        try:
            model = YOLOv10(sabit_model)
        finally:
            torch.load = asil_load
    except Exception as e:  # noqa: BLE001
        shutil.rmtree(model_gecici, ignore_errors=True)
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"model açılamadı: {type(e).__name__}: {e}",
            "model_path": model_kaynagi,
        }, 1)

    # Ultralytics epoch-sonu callback → ilerleme akışı
    def _epoch_bitti(egitici):
        try:
            m = getattr(egitici, "metrics", {}) or {}
            kayit = {
                "run_id": kosu_kimligi,
                "epoch": int(getattr(egitici, "epoch", -1)) + 1,
                "map50": float(m.get("metrics/mAP50(B)", 0) or 0),
                "map50_95": float(
                    m.get("metrics/mAP50-95(B)", 0) or 0),
                "box_loss": float(getattr(egitici, "loss", 0) or 0),
            }
            _ilerleme_yaz(args.output, kayit)
        except Exception:  # noqa: BLE001
            pass

    try:
        model.add_callback("on_fit_epoch_end", _epoch_bitti)
    except Exception:  # noqa: BLE001 — callback yoksa yine eğitilir
        pass

    baslangic_ns = time.time_ns()
    _ilerleme_yaz(args.output, {
        "run_id": kosu_kimligi,
        "asama": "basladı",
        "cihaz": cihaz,
        "imgsz": args.imgsz,
        "epochs": args.epochs,
        "resume": bool(args.resume),
    })
    try:
        model.train(
            data=args.data, epochs=args.epochs, imgsz=args.imgsz,
            batch=args.batch, device=cihaz, workers=args.workers,
            patience=args.patience, project=args.output, name="ql_v3",
            exist_ok=True, resume=args.resume,
            amp=False,                     # MPS'te fp16 kararsız
            fliplr=0.0, flipud=0.0, degrees=0.0,   # metin belgesi
            mosaic=0.5, close_mosaic=10,
            hsv_h=0.01, hsv_s=0.3, hsv_v=0.2,
            translate=0.05, scale=0.2,
            seed=42, deterministic=True, verbose=True)
    except Exception as e:  # noqa: BLE001
        # Bir checkpoint yazılmış olsa bile OOM/veri hatası/finalizasyon
        # istisnası eğitim başarısı değildir. Tamamlanma kanıtı olmadan eski
        # davranışın best.pt'yi kabul etmesi yarım modeli yayınlanabilir kılıyordu.
        try:
            hata_son_last = _dosya_imzasi(last)
        except OSError:
            hata_son_last = None
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"eğitim hatası: {type(e).__name__}: {e}",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
            "checkpoint_progressed": (
                hata_son_last is not None
                and (onceki_last is None
                     or hata_son_last["sha256"] != onceki_last["sha256"])
            ),
        }, 1)
    finally:
        # Resume sırasında DocLayout-YOLO self.ckpt_path'i train() içinde
        # yeniden açar; doğrulanmış geçici kopya bu çağrı bitene dek yaşamalı.
        shutil.rmtree(model_gecici, ignore_errors=True)

    try:
        son_best = _dosya_imzasi(best)
        son_last = _dosya_imzasi(last)
    except OSError as e:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"eğitim checkpoint'i okunamadı: {type(e).__name__}: {e}",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
        }, 1)
    if son_best is None:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": "yeni best.pt üretilmedi",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
        }, 1)
    if son_last is None:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": "eğitim ilerlemesini kanıtlayan last.pt üretilmedi",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
        }, 1)

    checkpoint_ilerledi = (
        onceki_last is None
        or son_last["sha256"] != onceki_last["sha256"]
    )
    if not checkpoint_ilerledi:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": "last.pt bu eğitim koşusunda ilerlemedi",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
            "checkpoint_progressed": False,
            "checkpoint_before_sha256": onceki_last["sha256"],
            "checkpoint_after_sha256": son_last["sha256"],
        }, 1)

    try:
        veri_sha = _dosya_sha256(args.data)
    except OSError as e:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": f"eğitim girdisi özetlenemedi: {type(e).__name__}: {e}",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
        }, 1)
    if veri_sha != veri_baslangic_sha:
        return _bitir(args.output, kosu_kimligi, {
            "ok": False,
            "hata": "eğitim data YAML dosyası koşu sırasında değişti",
            "started_at_ns": baslangic_ns,
            "resume": bool(args.resume),
        }, 1)

    sonuc = {
        "ok": True,
        "run_id": kosu_kimligi,
        "best_path": best,
        "best_sha256": son_best["sha256"],
        "best_size": son_best["size"],
        "best_mtime_ns": son_best["mtime_ns"],
        "checkpoint_path": last,
        "checkpoint_before_sha256": (
            onceki_last["sha256"] if onceki_last is not None else None),
        "checkpoint_after_sha256": son_last["sha256"],
        "checkpoint_progressed": True,
        "best_changed": (
            onceki_best is None
            or son_best["sha256"] != onceki_best["sha256"]),
        "started_at_ns": baslangic_ns,
        "finished_at_ns": time.time_ns(),
        "data_yaml_sha256": veri_sha,
        "base_model_sha256": temel_imza["sha256"],
        "cihaz": cihaz,
        "resume": bool(args.resume),
        "uyari": None,
    }
    return _bitir(args.output, kosu_kimligi, sonuc, 0)


if __name__ == "__main__":
    sys.exit(main())
