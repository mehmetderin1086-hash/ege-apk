#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""question_layout_v3 veri setini Colab eğitimi için paketler.

soru_model_veri.py çıktısını (manifest + images/labels) manifest_dogrula ile
doğrular, sayfa PNG'lerini JPEG'e çevirerek (~4-5× küçülme; tespit eğitimi
için kayıpsız sayılır) tek ZIP üretir ve DocStructBench başlangıç ağırlığını
``base/`` altına ekler. ``--parca-boyut`` verilirse ZIP'i sıralı parçalara
böler (tarayıcıdan Drive'a parça parça yükleme için); Colab not defteri
parçaları ``cat`` mantığıyla birleştirir.

``korpus_haritasi.json`` (sha→kaynak yolu) ve ``denetim/`` görselleri KASITLI
olarak pakete girmez: manifest sözleşmesi kaynak adlarını dışarıda tutar,
ZIP buluta çıkacağı için harita yerelde kalır.

Kullanım:
    .venv/bin/python soru_model_colab_paketle.py
    .venv/bin/python soru_model_colab_paketle.py --veri <dizin> \
        --cikti <zip> --parca-boyut 9500000 --parca-dizin <dizin>
"""

import argparse
import hashlib
import io
import json
import os
import pathlib
import re
import sys
import tempfile
import zipfile

from PIL import Image

import duzen_model
import soru_model_egitim

VARSAYILAN_VERI = os.path.expanduser(
    "~/Library/Application Support/soru-kesici/egitim/ql_v3")
VARSAYILAN_CIKTI = os.path.expanduser("~/Desktop/ql_v3_colab.zip")
ARSIV_KOKU = "ql_v3"
JPEG_KALITE = 92
PAKET_PARMAK_SURUMU = "soru-kesici.question-layout-colab-fingerprint/v3"
RESMI_BASE_MODEL_SHA256 = (
    "9a2ee0220fe3d9ad31b47e1d9f1282f46959a54e4618fce9cffcc9715b8286e2"
)
RESMI_BASE_MODEL_BOYUT = 40_709_302
RESMI_BASE_MODEL_REPO = "juliozhao/DocLayout-YOLO-DocStructBench"
RESMI_BASE_MODEL_REVIZYON = "8c3299a30b8ff29a1503c4431b035b93220f7b11"
# Eğitim imgsz=1280; uzun kenarı 1600'e indirmek eğitim çözünürlüğünü
# etkilemez (letterbox zaten 1280'e küçültür), paketi ~2× küçültür.
# YOLO etiketleri normalize [0,1] olduğundan yeniden boyutlamadan etkilenmez.
MAKS_KENAR = 1600


def _sha256_bayt(veri):
    return hashlib.sha256(veri).hexdigest()


def _dosya_sha256(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1 << 20), b""):
            h.update(parca)
    return h.hexdigest()


def _sabit_dosya_oku(yol):
    """Tek okuma boyunca kaynak dosyanın değişmediğini doğrulayarak bayt döndür."""
    once = os.stat(yol)
    with open(yol, "rb") as f:
        veri = f.read()
    sonra = os.stat(yol)
    once_imza = (once.st_dev, once.st_ino, once.st_size, once.st_mtime_ns)
    sonra_imza = (sonra.st_dev, sonra.st_ino, sonra.st_size, sonra.st_mtime_ns)
    if once_imza != sonra_imza or len(veri) != once.st_size:
        raise RuntimeError(f"kaynak paketleme sırasında değişti: {yol}")
    return veri


def _resmi_base_model_dogrula(yol):
    """Çalıştırılabilir pickle ağırlığını bağımsız resmi güven köküne bağla."""
    try:
        boyut = os.path.getsize(yol)
    except OSError as e:
        raise FileNotFoundError(
            "Resmi DocStructBench başlangıç ağırlığı bulunamadı: " + yol
        ) from e
    if boyut != RESMI_BASE_MODEL_BOYUT:
        raise ValueError(
            "DocStructBench başlangıç ağırlığı resmi boyutla uyuşmuyor: "
            f"{boyut} != {RESMI_BASE_MODEL_BOYUT}"
        )
    ozet = _dosya_sha256(yol)
    if ozet != RESMI_BASE_MODEL_SHA256:
        raise ValueError(
            "DocStructBench başlangıç ağırlığı resmi SHA-256 ile uyuşmuyor"
        )
    return ozet, boyut


def _doclayout_etiket_yolu(gorsel_yolu):
    """DocLayout-YOLO'nun image→label yol türetimini POSIX göreli yolda uygula."""
    if not isinstance(gorsel_yolu, str) or not gorsel_yolu:
        raise ValueError("görüntü yolu eksik")
    if "\\" in gorsel_yolu:
        raise ValueError("görüntü yolu POSIX biçiminde olmalı")
    posix = pathlib.PurePosixPath(gorsel_yolu)
    if posix.is_absolute() or posix.as_posix() != gorsel_yolu \
            or ".." in posix.parts:
        raise ValueError(f"görüntü yolu kanonik/göreli değil: {gorsel_yolu}")
    isaret = "/images/"
    tam = "/" + gorsel_yolu
    if isaret not in tam:
        raise ValueError(f"görüntü yolu /images/ içermiyor: {gorsel_yolu}")
    kok, kuyruk = tam.rsplit(isaret, 1)
    etiket = (kok + "/labels/" + kuyruk).rsplit(".", 1)[0] + ".txt"
    return etiket.lstrip("/")


def _parmak_satiri(parmak, oge):
    parmak.update(json.dumps(
        oge, ensure_ascii=False, separators=(",", ":"),
    ).encode("utf-8"))
    parmak.update(b"\n")


def _paket_parmagi_baslat(manifest):
    parmak = hashlib.sha256()
    _parmak_satiri(parmak, [
        "metadata",
        manifest["training_package_fingerprint_version"],
        manifest["package_schema_version"],
        manifest["source_dataset_fingerprint"],
        manifest["archive_root"],
        manifest["jpeg_quality"],
        manifest["max_edge"],
        manifest["classes"],
    ])
    return parmak


def _kaynak_dataset_parmagi(manifest, kaynak_parcalari):
    """manifest_dogrula ile aynı kaynak fingerprint'ini snapshot SHA'lardan üret."""
    manifest_kanonik = json.dumps(
        manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    parmak = hashlib.sha256()
    parmak.update(manifest_kanonik.encode("utf-8"))
    for parca in sorted(kaynak_parcalari):
        parmak.update(b"\0")
        parmak.update(parca.encode("utf-8"))
    return parmak.hexdigest()


def _arsiv_koku_dogrula(deger):
    if not isinstance(deger, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", deger):
        raise ValueError("arşiv kökü yalnız harf, rakam, nokta, _ ve - içerebilir")
    if deger in (".", ".."):
        raise ValueError("geçersiz arşiv kökü")
    return deger


def _jpeg_bayt(png_yolu, *, kalite=JPEG_KALITE, maks_kenar=MAKS_KENAR):
    kaynak = _sabit_dosya_oku(png_yolu)
    with Image.open(io.BytesIO(kaynak)) as im:
        im = im.convert("RGB")
        oran = maks_kenar / max(im.size)
        if oran < 1:
            im = im.resize((max(1, round(im.width * oran)),
                            max(1, round(im.height * oran))),
                           Image.LANCZOS)
        tampon = io.BytesIO()
        im.save(tampon, "JPEG", quality=kalite, optimize=True)
    return tampon.getvalue(), _sha256_bayt(kaynak)


def _gecici_yol(hedef, ek):
    dizin = os.path.dirname(os.path.abspath(hedef))
    os.makedirs(dizin, exist_ok=True)
    fd, yol = tempfile.mkstemp(
        dir=dizin, prefix="." + os.path.basename(hedef) + ".", suffix=ek)
    os.close(fd)
    return yol


def _dosya_fsync(yol):
    with open(yol, "rb") as f:
        os.fsync(f.fileno())


def _cifti_yayinla(gecici_zip, gecici_manifest, cikti):
    """ZIP+yan manifest çiftini istisnalarda eski çifte geri dönerek yayınla."""
    yan = cikti + ".manifest.json"
    yedek_zip = _gecici_yol(cikti, ".zip.bak")
    yedek_yan = _gecici_yol(yan, ".json.bak")
    os.unlink(yedek_zip)
    os.unlink(yedek_yan)
    zip_yedeklendi = yan_yedeklendi = False
    yeni_zip = yeni_yan = False
    try:
        if os.path.exists(cikti):
            os.replace(cikti, yedek_zip)
            zip_yedeklendi = True
        if os.path.exists(yan):
            os.replace(yan, yedek_yan)
            yan_yedeklendi = True
        os.replace(gecici_zip, cikti)
        yeni_zip = True
        os.replace(gecici_manifest, yan)
        yeni_yan = True
    except BaseException:
        for mevcut, yazildi in ((yan, yeni_yan), (cikti, yeni_zip)):
            if yazildi:
                try:
                    os.unlink(mevcut)
                except OSError:
                    pass
        if zip_yedeklendi:
            os.replace(yedek_zip, cikti)
            zip_yedeklendi = False
        if yan_yedeklendi:
            os.replace(yedek_yan, yan)
            yan_yedeklendi = False
        raise
    finally:
        for yol, gerekli in (
                (yedek_zip, zip_yedeklendi),
                (yedek_yan, yan_yedeklendi)):
            if gerekli:
                try:
                    os.unlink(yol)
                except OSError:
                    pass


def paketle(veri, cikti, parca_boyut=0, parca_dizin=None, *,
            arsiv_koku=ARSIV_KOKU, jpeg_kalite=JPEG_KALITE,
            maks_kenar=MAKS_KENAR):
    arsiv_koku = _arsiv_koku_dogrula(arsiv_koku)
    if not 90 <= jpeg_kalite <= 100:
        raise ValueError("JPEG kalite 90..100 aralığında olmalı")
    if maks_kenar < 1280:
        raise ValueError("maksimum kenar eğitim imgsz=1280'den küçük olamaz")
    manifest_yolu = os.path.join(veri, "manifest.json")
    rapor = soru_model_egitim.manifest_dogrula(manifest_yolu)
    if not rapor["ok"]:
        print("Manifest doğrulaması BAŞARISIZ; paket üretilmedi:")
        for h in rapor["hatalar"][:10]:
            print("  -", h)
        return 2
    ist = rapor["istatistik"]
    print("Manifest doğru:",
          json.dumps(ist["samples"], ensure_ascii=False),
          f"— {sum(ist['boxes'].values())} kutu,",
          f"{ist['documents']} belge, {ist['publisher_groups']} yayınevi grubu")

    # Colab manifesti: aynı splitler, görüntü yolları .jpg. Türev görüntü,
    # etiket ve bunları üreten kaynak-encoded snapshot özetleri kilitlenir;
    # böylece Colab'ın gerçekten eğittiği JPEG veri yerel PNG manifestiyle ya
    # da paketleme anındaki A-B-A dosya yarışıyla sessizce karıştırılamaz.
    colab_manifest = dict(rapor["manifest"])
    colab_manifest["splits"] = {}
    colab_manifest["package_schema_version"] = (
        "soru-kesici.question-layout-colab-package/v1")
    colab_manifest["training_package_fingerprint_version"] = (
        PAKET_PARMAK_SURUMU)
    colab_manifest["source_dataset_fingerprint"] = rapor[
        "dataset_fingerprint"]
    colab_manifest["archive_root"] = arsiv_koku
    colab_manifest["jpeg_quality"] = jpeg_kalite
    colab_manifest["max_edge"] = maks_kenar
    base_model_yolu = os.path.abspath(duzen_model.MODEL_YOLU)
    _resmi_base_model_dogrula(base_model_yolu)
    base_model_bayt = _sabit_dosya_oku(base_model_yolu)
    base_model_adi = os.path.basename(base_model_yolu)
    base_model_rel = "base/" + base_model_adi
    base_model_sha = _sha256_bayt(base_model_bayt)
    base_model_boyut = len(base_model_bayt)
    if (base_model_sha != RESMI_BASE_MODEL_SHA256
            or base_model_boyut != RESMI_BASE_MODEL_BOYUT):
        raise RuntimeError("başlangıç ağırlığı doğrulama sonrasında değişti")
    colab_manifest["base_model"] = {
        "path": base_model_rel,
        "sha256": base_model_sha,
        "size": base_model_boyut,
        "trust_root": {
            "kind": "pinned-official-huggingface-revision",
            "repository": RESMI_BASE_MODEL_REPO,
            "revision": RESMI_BASE_MODEL_REVIZYON,
        },
    }
    parmak = _paket_parmagi_baslat(colab_manifest)

    gecici = _gecici_yol(cikti, ".zip.tmp")
    gecici_yan = _gecici_yol(cikti + ".manifest.json", ".json.tmp")
    eklenen = 0
    arsiv_uyeleri = set()
    kaynak_parcalari = []
    try:
        with zipfile.ZipFile(gecici, "w") as z:
            for split, ornekler in rapor["samples"].items():
                yeni = []
                for o in ornekler:
                    jpg_rel = o["image"].rsplit(".", 1)[0] + ".jpg"
                    beklenen_etiket = _doclayout_etiket_yolu(jpg_rel)
                    if o["label"] != beklenen_etiket:
                        raise ValueError(
                            "manifest etiketi DocLayout image→label kuralıyla "
                            f"uyuşmuyor: {o['label']} != {beklenen_etiket}"
                        )
                    for uye in (jpg_rel, o["label"]):
                        kimlik = uye.casefold()
                        if kimlik in arsiv_uyeleri:
                            raise ValueError(
                                f"yinelenen paket üyesi yolu: {uye}")
                        arsiv_uyeleri.add(kimlik)
                    jpg, kaynak_gorsel_sha = _jpeg_bayt(
                        os.path.join(veri, *o["image"].split("/")),
                        kalite=jpeg_kalite, maks_kenar=maks_kenar)
                    etiket_yolu = os.path.join(veri, *o["label"].split("/"))
                    etiket = _sabit_dosya_oku(etiket_yolu)
                    kaynak_etiket_sha = _sha256_bayt(etiket)
                    jpg_sha = _sha256_bayt(jpg)
                    etiket_sha = kaynak_etiket_sha
                    z.writestr(arsiv_koku + "/" + jpg_rel, jpg,
                               compress_type=zipfile.ZIP_STORED)
                    z.writestr(arsiv_koku + "/" + o["label"], etiket,
                               compress_type=zipfile.ZIP_DEFLATED)
                    yeni_ornek = dict(
                        o, image=jpg_rel, image_sha256=jpg_sha,
                        label_sha256=etiket_sha,
                        source_encoded_image_sha256=kaynak_gorsel_sha,
                        source_encoded_label_sha256=kaynak_etiket_sha)
                    yeni.append(yeni_ornek)
                    _parmak_satiri(parmak, [
                        split, jpg_rel, o["label"], jpg_sha, etiket_sha,
                        kaynak_gorsel_sha, kaynak_etiket_sha])
                    kaynak_parcalari.append(
                        f"{split}\0{o['image']}\0{kaynak_gorsel_sha}"
                        f"\0{o['label']}\0{kaynak_etiket_sha}")
                    eklenen += 1
                    if eklenen % 200 == 0:
                        print(f"  … {eklenen} örnek paketlendi")
                colab_manifest["splits"][split] = yeni
            z.writestr(
                arsiv_koku + "/" + base_model_rel,
                base_model_bayt,
                compress_type=zipfile.ZIP_STORED,
            )
            arsiv_uyeleri.add(base_model_rel.casefold())
            _parmak_satiri(parmak, [
                "base_model", base_model_rel,
                base_model_sha, base_model_boyut])
            colab_manifest["training_package_sha256"] = parmak.hexdigest()
            z.writestr(
                arsiv_koku + "/manifest.json",
                json.dumps(colab_manifest, ensure_ascii=False, indent=1),
                compress_type=zipfile.ZIP_DEFLATED,
            )
            print(
                "Başlangıç ağırlığı resmi SHA-256 güven köküyle pakete eklendi: "
                + base_model_sha
            )
        _dosya_fsync(gecici)

        snapshot_fp = _kaynak_dataset_parmagi(
            rapor["manifest"], kaynak_parcalari)
        if snapshot_fp != rapor["dataset_fingerprint"]:
            raise RuntimeError(
                "paketlenen kaynak snapshot baytları başlangıç veri seti "
                "fingerprint'iyle uyuşmuyor; olası A-B-A değişimi")

        # Paket üretimi boyunca kalıcı bir kaynak değişikliği olduysa, başlangıç
        # fingerprint'ini yeni JPEG baytlarına yanlış bağlamadan fail-closed kal.
        son_rapor = soru_model_egitim.manifest_dogrula(manifest_yolu)
        if not son_rapor["ok"] or son_rapor.get(
                "dataset_fingerprint") != rapor["dataset_fingerprint"]:
            raise RuntimeError(
                "kaynak veri seti paketleme sırasında değişti; paket yayınlanmadı")

        boyut = os.path.getsize(gecici)
        yan_manifest = dict(colab_manifest)
        yan_manifest["archive_sha256"] = _dosya_sha256(gecici)
        yan_manifest["archive_size"] = boyut
        with open(gecici_yan, "w", encoding="utf-8") as f:
            json.dump(yan_manifest, f, ensure_ascii=False, indent=1)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        _cifti_yayinla(gecici, gecici_yan, cikti)
    finally:
        for yol in (gecici, gecici_yan):
            try:
                os.unlink(yol)
            except OSError:
                pass

    boyut = os.path.getsize(cikti)
    if (_dosya_sha256(cikti) != yan_manifest["archive_sha256"]
            or boyut != yan_manifest["archive_size"]):
        raise RuntimeError("yayınlanan ZIP yan manifestle uyuşmuyor")
    print(f"\n✓ {eklenen} örnek → {cikti} ({boyut / (1 << 20):.0f} MB)")
    print("  eğitim paketi SHA-256:",
          colab_manifest["training_package_sha256"])
    print("  ZIP SHA-256:", yan_manifest["archive_sha256"])

    if parca_boyut:
        parca_dizin = parca_dizin or (cikti + "_parcalar")
        os.makedirs(parca_dizin, exist_ok=True)
        ad = os.path.basename(cikti)
        parcalar = []
        with open(cikti, "rb") as f:
            i = 0
            while True:
                blok = f.read(parca_boyut)
                if not blok:
                    break
                yol = os.path.join(parca_dizin, f"{ad}.{i:03d}")
                with open(yol, "wb") as p:
                    p.write(blok)
                parcalar.append(yol)
                i += 1
        print(f"✓ {len(parcalar)} parça ({parca_boyut / 1e6:.1f} MB'lık) "
              f"→ {parca_dizin}")
        print("Parçalar Drive'da soru-kesici/parcalar/ klasörüne yüklenmeli;")
        print("not defteri onları otomatik birleştirir.")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Colab eğitimi için veri seti paketi")
    p.add_argument("--veri", default=VARSAYILAN_VERI)
    p.add_argument("--cikti", default=VARSAYILAN_CIKTI)
    p.add_argument("--parca-boyut", type=int, default=0,
                   help="0'dan büyükse ZIP bu bayt boyutunda parçalara bölünür")
    p.add_argument("--parca-dizin", default=None)
    p.add_argument("--arsiv-koku", default=ARSIV_KOKU,
                   help="ZIP içindeki veri kökü (örn. ql_v4_palme)")
    p.add_argument("--jpeg-kalite", type=int, default=JPEG_KALITE)
    p.add_argument("--maks-kenar", type=int, default=MAKS_KENAR)
    args = p.parse_args(argv)
    if not os.path.isfile(os.path.join(args.veri, "manifest.json")):
        p.error(f"manifest bulunamadı: {args.veri} "
                "(önce soru_model_veri.py --korpus ... çalıştırın)")
    return paketle(args.veri, os.path.abspath(args.cikti),
                   parca_boyut=args.parca_boyut,
                   parca_dizin=args.parca_dizin,
                   arsiv_koku=args.arsiv_koku,
                   jpeg_kalite=args.jpeg_kalite,
                   maks_kenar=args.maks_kenar)


if __name__ == "__main__":
    sys.exit(main())
