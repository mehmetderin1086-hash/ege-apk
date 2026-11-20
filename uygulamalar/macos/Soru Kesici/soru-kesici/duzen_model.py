#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ML düzen tespiti istemcisi (isteğe bağlı katman) — yalnız stdlib.

DocLayout-YOLO ayrı bir sanal ortamda (.venv-ml, Python 3.10+) koşar; bu
modül işçi sürecini (duzen_isci.py) başlatıp satır-JSON protokolüyle
konuşur. Ortam/model yoksa, bozuksa veya özellik kapalıysa her API
sessizce None/[]/False döner → soru_kes.py'nin sezgisel yolu aynen
çalışır (regresyon nötr, gemini_konu.py deseni). Kurulum:
    python3 duzen_kur.py

Açma/kapama önceliği: AKTIF_ZORLA > SORU_KESICI_DUZEN ortam değişkeni
("1"/"0") > ~/.soru_kesici.json içindeki duzen_model_aktif > kapalı.

Tespitler sayfa başına deterministtir ve diske önbelleklenir
(~/Library/Caches/soru-kesici/duzen/<sha1>.json) — önbellek isabetinde
işçi süreci hiç başlatılmaz.
"""
import atexit
import hashlib
import json
import math
import os
import queue
import subprocess
import tempfile
import threading

import isci_ortam
import veri_yollari

AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")
PROJE = os.path.dirname(os.path.abspath(__file__))
ISCI_PY = isci_ortam.isci_python()
ISCI_BETIK = os.path.join(PROJE, "duzen_isci.py")
MODELLER_DIZIN = os.path.join(veri_yollari.veri_koku(), "modeller")
MODEL_YOLU = os.path.join(
    MODELLER_DIZIN, "doclayout_yolo_docstructbench_imgsz1024.pt")
CACHE_DIZIN = os.path.join(veri_yollari.onbellek_koku(), "duzen")
LOG_YOLU = os.path.join(CACHE_DIZIN, "isci.log")
CACHE_SURUM = 2           # V2: belirsiz sayfada global + yerel ikinci geçiş
IMGSZ = 1024
GUVEN_ALT = 0.20          # işçiye giden conf tabanı; çağıranlar üstüne
                          # kendi eşiklerini koyar (ör. 0.35)
HAZIR_ZAMAN = 120.0       # torch import + model yükleme payı
YANIT_ZAMAN = 30.0
AKTIF_ZORLA = None        # CLI/test geçersiz kılma: True/False/None

# DocStructBench sınıflarından soru segmentasyonunda kullanılanlar
SEKIL_SINIFLARI = frozenset({"figure", "table", "isolate_formula"})
GOVDE_SINIFLARI = SEKIL_SINIFLARI | frozenset({"plain text", "title"})

# Soru-özel V3 modeli genel DocStructBench modelinden ayrı tutulur. Ağırlık
# dosyasının yanında bulunan manifest sınıf sırasını ve ağırlık özetini
# kilitler; böylece yanlış/eskimiş bir YOLO ağırlığı sessizce kullanılamaz.
SORU_MODEL_SEMA_SURUMU = "soru-kesici.question-layout-model/v1"
SORU_MODEL_CIKTI_SURUMU = "soru-kesici.question-layout-prediction/v1"
SORU_MODEL_CACHE_SURUMU = 1
SORU_MODEL_SINIFLARI = (
    "question_anchor",
    "question_body",
    "shared_stimulus",
    "solution_or_answer",
)
SORU_MODEL_LEGACY_YOLU = os.path.join(
    MODELLER_DIZIN, "question_layout_v3.pt")
SORU_MODEL_SURUMLER_DIZINI = os.path.join(
    MODELLER_DIZIN, "question-layout-versions")
SORU_MODEL_AKTIF_BAGLANTI = os.path.join(
    MODELLER_DIZIN, "question-layout-active")


def _aktif_veya_legacy_soru_model_yollari():
    aktif_model = os.path.join(SORU_MODEL_AKTIF_BAGLANTI, "model.pt")
    aktif_manifest = aktif_model + ".manifest.json"
    if os.path.isfile(aktif_model) and os.path.isfile(aktif_manifest):
        return aktif_model, aktif_manifest
    return SORU_MODEL_LEGACY_YOLU, SORU_MODEL_LEGACY_YOLU + ".manifest.json"


SORU_MODEL_YOLU, SORU_MODEL_MANIFEST_YOLU = (
    _aktif_veya_legacy_soru_model_yollari()
)
_SORU_MODEL_OTOMATIK_YOLLAR = (
    SORU_MODEL_YOLU,
    SORU_MODEL_MANIFEST_YOLU,
)
SORU_MODEL_CACHE_DIZIN = os.path.join(CACHE_DIZIN, "soru-v3")
SORU_MODEL_IMGSZ = 1280
SORU_MODEL_GUVEN_ALT = 0.12
SORU_MODEL_HAZIR_ZAMAN = 120.0
SORU_MODEL_YANIT_ZAMAN = 45.0
SORU_MODEL_AKTIF_ZORLA = None

_SORU_SINIF_ESLE = {
    "question_anchor": "question_anchor",
    "question anchor": "question_anchor",
    "question-anchor": "question_anchor",
    "soru_capasi": "question_anchor",
    "soru çapası": "question_anchor",
    "question_body": "question_body",
    "question body": "question_body",
    "question-body": "question_body",
    "soru_govdesi": "question_body",
    "soru gövdesi": "question_body",
    "shared_stimulus": "shared_stimulus",
    "shared stimulus": "shared_stimulus",
    "shared-stimulus": "shared_stimulus",
    "ortak_uyaran": "shared_stimulus",
    "ortak uyaran": "shared_stimulus",
    "solution_or_answer": "solution_or_answer",
    "solution or answer": "solution_or_answer",
    "solution-or-answer": "solution_or_answer",
    "cozum_veya_cevap": "solution_or_answer",
    "çözüm veya cevap": "solution_or_answer",
}

_KILIT = threading.Lock()
_ISCI = None              # (Popen, Queue) | None
_BOZUK = False            # işçi bir kez çökerse süreç boyu tekrar denenmez
_PROBE_SONUC = None       # hafif doğrulamanın süreç-içi önbelleği
_SAYAC = 0

_SORU_KILIT = threading.Lock()
_SORU_ISCI = None         # (Popen, Queue) | None; genel işçiden bağımsız
_SORU_ISCI_KIMLIK = None  # çalışan işçinin doğrulanmış ağırlık SHA-256'sı
_SORU_BOZUK = False
_SORU_PROBE_SONUC = None
_SORU_SAYAC = 0
_SORU_MANIFEST_CACHE = None
_SORU_DURUM_KIMLIK = None
_SORU_GOZLENEN_KIMLIKLER = set()


def _ayar():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def aktif_mi():
    if AKTIF_ZORLA is not None:
        return bool(AKTIF_ZORLA)
    ortam = os.environ.get("SORU_KESICI_DUZEN")
    if ortam in ("0", "1"):
        return ortam == "1"
    return bool(_ayar().get("duzen_model_aktif"))


def duzen_dogrula(derin=False):
    """Kullanılabilirlik durumu: {"ok": bool, "mesaj": str}.
    derin=True işçiyi --probe ile gerçekten başlatır (kurulum testi)."""
    if not (os.path.isfile(ISCI_PY) and os.access(ISCI_PY, os.X_OK)):
        return {"ok": False,
                "mesaj": "ML ortamı kurulu değil — python3 duzen_kur.py"}
    if not os.path.isfile(ISCI_BETIK):
        return {"ok": False, "mesaj": "duzen_isci.py bulunamadı"}
    try:
        if os.stat(MODEL_YOLU).st_size < 1_000_000:
            return {"ok": False, "mesaj": "model dosyası bozuk görünüyor — "
                                          "python3 duzen_kur.py ile yeniden indirin"}
    except OSError:
        return {"ok": False,
                "mesaj": "model ağırlığı yok — python3 duzen_kur.py"}
    if derin:
        try:
            model_sha = _dosya_sha256(MODEL_YOLU)
            s = subprocess.run(
                [ISCI_PY, ISCI_BETIK, "--model", MODEL_YOLU,
                 "--model-sha256", model_sha, "--probe"],
                capture_output=True, text=True, encoding="utf-8",
                timeout=300)
            ilk = (s.stdout or "").strip().splitlines()
            durum = json.loads(ilk[0]) if ilk else {}
            if durum.get("ok"):
                return {"ok": True,
                        "mesaj": f"hazır (cihaz: {durum.get('cihaz')})"}
            return {"ok": False, "mesaj": durum.get("hata")
                    or f"işçi başlatılamadı — bkz. {LOG_YOLU}"}
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "mesaj": f"{type(e).__name__}: {e}"}
    return {"ok": True, "mesaj": "hazır"}


def kullanilabilir():
    """Sıcak yol kapısı: aktif + kurulu. Sonuç (probe kısmı) süreç-içi
    önbelleklenir; işçi bozulduysa kalıcı False."""
    global _PROBE_SONUC
    if _BOZUK or not aktif_mi():
        return False
    if _PROBE_SONUC is None:
        _PROBE_SONUC = bool(duzen_dogrula()["ok"])
    return _PROBE_SONUC


def kimlik(temel):
    """Önbellek anahtarı: çağıranın sayfa kimliği (ör. _ocr_kimlik tabanı)
    + model dosyası + tespit ayarları. Model değişince anahtar değişir."""
    if not temel:
        return None
    try:
        st = os.stat(MODEL_YOLU)
    except OSError:
        return None
    ham = (f"{temel}|{st.st_size}|{st.st_mtime_ns}|{CACHE_SURUM}|"
           f"{IMGSZ}|{GUVEN_ALT}")
    return hashlib.sha1(ham.encode("utf-8")).hexdigest()


def _cache_oku(anahtar):
    if not anahtar:
        return None
    try:
        with open(os.path.join(CACHE_DIZIN, anahtar + ".json"),
                  encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _cache_yaz(anahtar, bolgeler):
    if not anahtar:
        return
    try:
        os.makedirs(CACHE_DIZIN, exist_ok=True)
        fd, gecici = tempfile.mkstemp(dir=CACHE_DIZIN, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(bolgeler, f, ensure_ascii=False)
        os.replace(gecici, os.path.join(CACHE_DIZIN, anahtar + ".json"))
    except OSError:
        pass


def _isci_baslat():
    """İşçiyi başlatır, el sıkışmayı bekler. _KILIT altında çağrılır."""
    global _ISCI
    os.makedirs(CACHE_DIZIN, exist_ok=True)
    log = open(LOG_YOLU, "a", encoding="utf-8")
    model_sha = _dosya_sha256(MODEL_YOLU)
    proc = subprocess.Popen(
        [ISCI_PY, ISCI_BETIK, "--model", MODEL_YOLU,
         "--model-sha256", model_sha,
         "--imgsz", str(IMGSZ), "--conf", str(GUVEN_ALT)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
        text=True, encoding="utf-8", bufsize=1)
    log.close()  # alt süreç fd'yi devraldı
    q = queue.Queue()

    def _oku():
        try:
            for satir in proc.stdout:
                satir = satir.strip()
                if not satir:
                    continue
                try:
                    q.put(json.loads(satir))
                except ValueError:
                    continue  # protokol dışı satır (savunma)
        except Exception:  # noqa: BLE001
            pass
        q.put(None)  # EOF işareti

    threading.Thread(target=_oku, daemon=True).start()
    durum = q.get(timeout=HAZIR_ZAMAN)
    if not (
            isinstance(durum, dict)
            and durum.get("ok")
            and durum.get("model_sha256") == model_sha):
        raise RuntimeError(f"işçi hazır değil: {durum}")
    _ISCI = (proc, q)


def _oldur():
    global _ISCI
    if _ISCI is None:
        return
    proc, _ = _ISCI
    _ISCI = None
    try:
        if proc.poll() is None:
            try:
                proc.stdin.write(json.dumps({"cikis": True}) + "\n")
                proc.stdin.flush()
            except OSError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
    except Exception:  # noqa: BLE001
        pass
    finally:
        for akis in (getattr(proc, "stdin", None),
                     getattr(proc, "stdout", None)):
            kapat = getattr(akis, "close", None)
            if callable(kapat):
                try:
                    kapat()
                except OSError:
                    pass


def _istek(png_yolu):
    """Tek görüntü için tespit ister. Her hata → None + kalıcı _BOZUK."""
    global _BOZUK, _SAYAC
    with _KILIT:
        try:
            if _ISCI is None:
                _isci_baslat()
            proc, q = _ISCI
            _SAYAC += 1
            no = _SAYAC
            proc.stdin.write(json.dumps({"id": no, "png": png_yolu}) + "\n")
            proc.stdin.flush()
            while True:
                yanit = q.get(timeout=YANIT_ZAMAN)
                if yanit is None:
                    raise RuntimeError("işçi beklenmedik şekilde kapandı")
                if yanit.get("id") == no:
                    if "hata" in yanit:
                        raise RuntimeError(yanit["hata"])
                    return yanit.get("bolgeler") or []
        except Exception:  # noqa: BLE001 — sessiz geri düşüş
            _oldur()
            _BOZUK = True
            return None


def bolgeler_gorsel(pil_img, onbellek_kimlik=None):
    """PIL görüntüsü için düzen bölgeleri: [{"sinif","kutu","guven"}] |
    None. Kutular girdinin piksel uzayında. Önbellek isabeti işçiyi hiç
    başlatmaz; özellik kapalı/kurulu değilse None."""
    if not kullanilabilir():
        return None
    onbellek = _cache_oku(onbellek_kimlik)
    if onbellek is not None:
        return onbellek
    gecici = None
    try:
        os.makedirs(CACHE_DIZIN, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=CACHE_DIZIN, suffix=".png",
                                         delete=False) as f:
            gecici = f.name
        # compress_level=1: kayıpsız, hızlı (vision_satirlar gerekçesi)
        pil_img.save(gecici, "PNG", compress_level=1)
        bolgeler = _istek(gecici)
        if bolgeler is not None:
            _cache_yaz(onbellek_kimlik, bolgeler)
        return bolgeler
    except Exception:  # noqa: BLE001
        return None
    finally:
        if gecici:
            try:
                os.unlink(gecici)
            except OSError:
                pass


def _dosya_sha256(yol):
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


def soru_modeli_aktif_mi():
    """Soru-özel model için ayrı özellik kapısı.

    Ağırlık/manifest yoksa varsayılan açık olması bir yan etki üretmez;
    :func:`soru_modeli_kullanilabilir` güvenli biçimde False döner. Kullanıcı
    ortam değişkeniyle veya ayar dosyasıyla özelliği bütünüyle kapatabilir.
    """
    if SORU_MODEL_AKTIF_ZORLA is not None:
        return bool(SORU_MODEL_AKTIF_ZORLA)
    ortam = os.environ.get("SORU_KESICI_SORU_MODELI")
    if ortam in ("0", "1"):
        return ortam == "1"
    ayar = _ayar()
    if "soru_model_aktif" in ayar:
        return bool(ayar["soru_model_aktif"])
    return True


def soru_model_yollarini_esitle(zorla=False):
    """Atomik ``question-layout-active`` işaretçisini süreç globals'ına yansıt.

    Test/aday değerlendirmesi yolları açıkça değiştirdiyse ``zorla=False`` bu
    özel yolları korur. Normal web süreci aktif symlink değişimini sonraki
    istekte görür ve model+manifest çiftini birlikte değiştirir.
    """
    global SORU_MODEL_YOLU, SORU_MODEL_MANIFEST_YOLU
    global _SORU_MODEL_OTOMATIK_YOLLAR
    mevcut = (SORU_MODEL_YOLU, SORU_MODEL_MANIFEST_YOLU)
    if not zorla and mevcut != _SORU_MODEL_OTOMATIK_YOLLAR:
        return mevcut
    yeni = _aktif_veya_legacy_soru_model_yollari()
    SORU_MODEL_YOLU, SORU_MODEL_MANIFEST_YOLU = yeni
    _SORU_MODEL_OTOMATIK_YOLLAR = yeni
    return yeni


def soru_model_yollarini_dondur():
    """Etkin model çiftini tek sürüm dizinine çözüp değişmez yollar döndür.

    ``question-layout-active`` tek bir symlink olsa da ``model.pt`` ve yan
    manifesti iki ayrı pathname çözümlemesiyle açmak pointer tam o sırada
    değişirse iki sürümü karıştırabilir. Aktif symlink dizini için önce üst
    dizini bir kez ``realpath`` ile çözer, sonra iki dosya yolunu o değişmez
    sürüm dizininden kurar. Legacy/özel test yolları için dosyaların gerçek
    yollarını döndürür.
    """
    soru_model_yollarini_esitle()
    model_yolu = os.path.abspath(SORU_MODEL_YOLU)
    manifest_yolu = os.path.abspath(SORU_MODEL_MANIFEST_YOLU)
    model_dizini = os.path.dirname(model_yolu)
    manifest_dizini = os.path.dirname(manifest_yolu)
    if model_dizini == manifest_dizini and os.path.islink(model_dizini):
        donmus_dizin = os.path.realpath(model_dizini)
        return (
            os.path.join(donmus_dizin, os.path.basename(model_yolu)),
            os.path.join(donmus_dizin, os.path.basename(manifest_yolu)),
        )
    return os.path.realpath(model_yolu), os.path.realpath(manifest_yolu)


def soru_modeli_dogrula(derin=False, model_yolu=None, manifest_yolu=None):
    """Soru-özel ağırlık sözleşmesini ve isteğe bağlı işçi açılışını doğrula.

    Doğrulama hiçbir dosya indirmez ve manifestteki SHA-256 ile yerel ağırlığı
    karşılaştırır. Dönüş her zaman ``{"ok": bool, "mesaj": str, ...}``
    biçimindedir; eksik model normal/güvenli bir durumdur.
    """
    if model_yolu is None and manifest_yolu is None:
        soru_model_yollarini_esitle()
    model_yolu = model_yolu or SORU_MODEL_YOLU
    manifest_yolu = manifest_yolu or SORU_MODEL_MANIFEST_YOLU
    if not os.path.isfile(model_yolu):
        return {"ok": False, "mesaj": "soru-özel model ağırlığı yok"}
    try:
        if os.stat(model_yolu).st_size <= 0:
            return {"ok": False, "mesaj": "soru-özel model ağırlığı boş"}
    except OSError as e:
        return {"ok": False, "mesaj": f"model okunamadı: {e}"}
    try:
        with open(manifest_yolu, encoding="utf-8") as f:
            manifest = json.load(f)
    except FileNotFoundError:
        return {"ok": False, "mesaj": "soru-özel model manifesti yok"}
    except (OSError, ValueError) as e:
        return {"ok": False, "mesaj": f"model manifesti okunamadı: {e}"}
    if not isinstance(manifest, dict):
        return {"ok": False, "mesaj": "model manifesti nesne olmalı"}
    if manifest.get("schema_version") != SORU_MODEL_SEMA_SURUMU:
        return {"ok": False, "mesaj": "model manifest sürümü uyumsuz"}
    if tuple(manifest.get("classes") or ()) != SORU_MODEL_SINIFLARI:
        return {"ok": False, "mesaj": "model sınıf sırası/sözleşmesi uyumsuz"}
    model_surumu = manifest.get("model_version")
    if not isinstance(model_surumu, str) or not model_surumu.strip():
        return {"ok": False, "mesaj": "model_version eksik"}
    agirlik_ozeti = manifest.get("weights_sha256")
    if not _sha256_mi(agirlik_ozeti):
        return {"ok": False, "mesaj": "weights_sha256 geçersiz"}
    veri_ozeti = manifest.get("training_dataset_sha256")
    if not _sha256_mi(veri_ozeti):
        return {"ok": False, "mesaj": "training_dataset_sha256 geçersiz"}
    try:
        gercek_ozet = _dosya_sha256(model_yolu)
    except OSError as e:
        return {"ok": False, "mesaj": f"model özeti okunamadı: {e}"}
    if gercek_ozet.lower() != agirlik_ozeti.lower():
        return {"ok": False, "mesaj": "model ağırlığı SHA-256 ile eşleşmiyor"}
    beklenen_boyut = manifest.get("weights_size")
    if (beklenen_boyut is not None
            and (not isinstance(beklenen_boyut, int)
                 or beklenen_boyut != os.stat(model_yolu).st_size)):
        return {"ok": False, "mesaj": "model ağırlığı boyutu eşleşmiyor"}
    model_id = f"{model_surumu}:{gercek_ozet[:16]}"
    sonuc = {
        "ok": True,
        "mesaj": "soru-özel model sözleşmesi geçerli",
        "model_id": model_id,
        "model_version": model_surumu,
        "classes": list(SORU_MODEL_SINIFLARI),
        "weights_sha256": gercek_ozet,
        "training_dataset_sha256": veri_ozeti.lower(),
    }
    if not derin:
        return sonuc
    if not (os.path.isfile(ISCI_PY) and os.access(ISCI_PY, os.X_OK)):
        return {"ok": False, "mesaj": "ML ortamı kurulu değil", **{
            k: v for k, v in sonuc.items() if k != "ok"}}
    if not os.path.isfile(ISCI_BETIK):
        return {"ok": False, "mesaj": "duzen_isci.py bulunamadı"}
    try:
        s = subprocess.run(
            [ISCI_PY, ISCI_BETIK, "--model", model_yolu,
             "--model-sha256", gercek_ozet, "--probe"],
            capture_output=True, text=True, encoding="utf-8", timeout=300,
            env={**os.environ, "HF_HUB_OFFLINE": "1",
                 "WANDB_DISABLED": "true"})
        ilk = (s.stdout or "").strip().splitlines()
        durum = json.loads(ilk[0]) if ilk else {}
        if not durum.get("ok"):
            return {"ok": False,
                    "mesaj": durum.get("hata") or "soru modeli işçisi açılamadı"}
        sonuc["mesaj"] = f"hazır (cihaz: {durum.get('cihaz')})"
        return sonuc
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "mesaj": f"{type(e).__name__}: {e}"}


def _soru_model_bilgisi():
    """Model sözleşmesi için stat-duyarlı süreç içi önbellek."""
    global _SORU_MANIFEST_CACHE
    soru_model_yollarini_esitle()
    try:
        ms = os.stat(SORU_MODEL_YOLU)
        js = os.stat(SORU_MODEL_MANIFEST_YOLU)
        anahtar = (
            SORU_MODEL_YOLU, ms.st_ino, ms.st_size, ms.st_mtime_ns,
            ms.st_ctime_ns, SORU_MODEL_MANIFEST_YOLU, js.st_ino,
            js.st_size, js.st_mtime_ns, js.st_ctime_ns,
        )
    except OSError:
        anahtar = (SORU_MODEL_YOLU, None, SORU_MODEL_MANIFEST_YOLU, None)
    if (_SORU_MANIFEST_CACHE is not None
            and _SORU_MANIFEST_CACHE[0] == anahtar):
        return _SORU_MANIFEST_CACHE[1]
    sonuc = soru_modeli_dogrula()
    _SORU_MANIFEST_CACHE = (anahtar, sonuc)
    return sonuc


def soru_modeli_kullanilabilir():
    global _SORU_BOZUK, _SORU_DURUM_KIMLIK, _SORU_PROBE_SONUC
    if not soru_modeli_aktif_mi():
        return False
    bilgi = _soru_model_bilgisi()
    yeni_kimlik = bilgi.get("weights_sha256") if bilgi.get("ok") else None
    if yeni_kimlik != _SORU_DURUM_KIMLIK:
        with _SORU_KILIT:
            if yeni_kimlik != _SORU_DURUM_KIMLIK:
                _soru_oldur()
                _SORU_BOZUK = False
                _SORU_PROBE_SONUC = None
                _SORU_DURUM_KIMLIK = yeni_kimlik
    if _SORU_BOZUK or not bilgi.get("ok"):
        return False
    # Buradaki probe yalnız sözleşme/dosya kontrolüdür; ağır torch yüklemesi
    # ilk gerçek çıkarıma ertelenir.
    if _SORU_PROBE_SONUC is None:
        _SORU_PROBE_SONUC = True
    return _SORU_PROBE_SONUC


def _soru_model_kimlik_bilgiden(temel, bilgi):
    """Önbellek anahtarını tek, doğrulanmış model bilgisine bağla."""
    if not temel:
        return None
    if not bilgi.get("ok"):
        return None
    ham = (f"{temel}|{bilgi['model_id']}|{bilgi['training_dataset_sha256']}|"
           f"{SORU_MODEL_CACHE_SURUMU}|{SORU_MODEL_IMGSZ}|"
           f"{SORU_MODEL_GUVEN_ALT}|{SORU_MODEL_CIKTI_SURUMU}")
    return hashlib.sha256(ham.encode("utf-8")).hexdigest()


def soru_model_kimlik(temel):
    """Soru-modeli önbellek anahtarı; ağırlık/manifest değişiminde yenilenir."""
    return _soru_model_kimlik_bilgiden(temel, _soru_model_bilgisi())


def _soru_cache_oku(anahtar, beklenen_model_id=None):
    if not anahtar:
        return None
    try:
        with open(os.path.join(SORU_MODEL_CACHE_DIZIN, anahtar + ".json"),
                  encoding="utf-8") as f:
            veri = json.load(f)
        if (isinstance(veri, dict)
                and veri.get("schema_version") == SORU_MODEL_CIKTI_SURUMU
                and isinstance(veri.get("regions"), list)
                and (beklenen_model_id is None
                     or veri.get("model_id") == beklenen_model_id)):
            return veri["regions"]
    except (OSError, ValueError):
        pass
    return None


def _soru_cache_yaz(anahtar, bolgeler, model_id):
    if not anahtar:
        return
    try:
        os.makedirs(SORU_MODEL_CACHE_DIZIN, exist_ok=True)
        fd, gecici = tempfile.mkstemp(dir=SORU_MODEL_CACHE_DIZIN,
                                      suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"schema_version": SORU_MODEL_CIKTI_SURUMU,
                       "model_id": model_id, "regions": bolgeler}, f,
                      ensure_ascii=False, sort_keys=True)
        os.replace(gecici,
                   os.path.join(SORU_MODEL_CACHE_DIZIN, anahtar + ".json"))
    except OSError:
        pass


def _soru_isci_baslat():
    global _SORU_ISCI, _SORU_ISCI_KIMLIK
    bilgi = _soru_model_bilgisi()
    if not bilgi.get("ok"):
        raise RuntimeError(
            "soru modeli sözleşmesi geçersiz: " + str(bilgi.get("mesaj")))
    model_sha = bilgi["weights_sha256"]
    os.makedirs(SORU_MODEL_CACHE_DIZIN, exist_ok=True)
    log_yolu = os.path.join(SORU_MODEL_CACHE_DIZIN, "isci.log")
    log = open(log_yolu, "a", encoding="utf-8")
    ortam = {**os.environ, "HF_HUB_OFFLINE": "1", "WANDB_DISABLED": "true",
             "ULTRALYTICS_OFFLINE": "true"}
    proc = subprocess.Popen(
        [ISCI_PY, ISCI_BETIK, "--model", SORU_MODEL_YOLU,
         "--model-sha256", model_sha,
         "--imgsz", str(SORU_MODEL_IMGSZ),
         "--conf", str(SORU_MODEL_GUVEN_ALT)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
        text=True, encoding="utf-8", bufsize=1, env=ortam)
    log.close()
    q = queue.Queue()

    def _oku():
        try:
            for satir in proc.stdout:
                satir = satir.strip()
                if not satir:
                    continue
                try:
                    q.put(json.loads(satir))
                except ValueError:
                    continue
        except Exception:  # noqa: BLE001
            pass
        q.put(None)

    threading.Thread(target=_oku, daemon=True).start()
    durum = q.get(timeout=SORU_MODEL_HAZIR_ZAMAN)
    if not (
            isinstance(durum, dict)
            and durum.get("ok")
            and durum.get("model_sha256") == model_sha):
        raise RuntimeError(f"soru modeli işçisi hazır değil: {durum}")
    _SORU_ISCI = (proc, q)
    _SORU_ISCI_KIMLIK = model_sha


def _soru_oldur():
    global _SORU_ISCI, _SORU_ISCI_KIMLIK
    if _SORU_ISCI is None:
        _SORU_ISCI_KIMLIK = None
        return
    proc, _ = _SORU_ISCI
    _SORU_ISCI = None
    _SORU_ISCI_KIMLIK = None
    try:
        if proc.poll() is None:
            try:
                proc.stdin.write(json.dumps({"cikis": True}) + "\n")
                proc.stdin.flush()
            except OSError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
    except Exception:  # noqa: BLE001
        pass
    finally:
        for akis in (getattr(proc, "stdin", None),
                     getattr(proc, "stdout", None)):
            kapat = getattr(akis, "close", None)
            if callable(kapat):
                try:
                    kapat()
                except OSError:
                    pass


def _soru_istek(png_yolu):
    """Bir çıkarımı bölgeler + o çıkarımı yapan donmuş model bilgisiyle döndür."""
    global _SORU_BOZUK, _SORU_SAYAC
    with _SORU_KILIT:
        try:
            bilgi = _soru_model_bilgisi()
            donmus_bilgi = dict(bilgi)
            model_sha = bilgi.get("weights_sha256")
            if not bilgi.get("ok") or not model_sha:
                raise RuntimeError("soru modeli kimliği geçersiz")
            if (_SORU_ISCI is not None
                    and _SORU_ISCI_KIMLIK != model_sha):
                _soru_oldur()
            if _SORU_ISCI is None:
                _soru_isci_baslat()
            proc, q = _SORU_ISCI
            _SORU_SAYAC += 1
            no = _SORU_SAYAC
            proc.stdin.write(json.dumps({"id": no, "png": png_yolu}) + "\n")
            proc.stdin.flush()
            while True:
                yanit = q.get(timeout=SORU_MODEL_YANIT_ZAMAN)
                if yanit is None:
                    raise RuntimeError("soru modeli işçisi kapandı")
                if yanit.get("id") == no:
                    if "hata" in yanit:
                        raise RuntimeError(yanit["hata"])
                    son_bilgi = _soru_model_bilgisi()
                    if (
                            yanit.get("model_sha256") != model_sha
                            or son_bilgi.get("weights_sha256") != model_sha):
                        raise RuntimeError(
                            "çıkarım sırasında soru modeli kimliği değişti")
                    _SORU_GOZLENEN_KIMLIKLER.add(model_sha)
                    return {
                        "bolgeler": yanit.get("bolgeler") or [],
                        "model_bilgisi": donmus_bilgi,
                        "model_sha256": model_sha,
                    }
        except Exception:  # noqa: BLE001 -- güvenli boş geri düşüş
            _soru_oldur()
            _SORU_BOZUK = True
            return None


def _soru_iou(a, b):
    ax0, ay0, ax1, ay1 = a["kutu"]
    bx0, by0, bx1, by1 = b["kutu"]
    w = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    h = max(0.0, min(ay1, by1) - max(ay0, by0))
    kesisim = w * h
    if not kesisim:
        return 0.0
    aa = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    ba = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    return kesisim / max(aa + ba - kesisim, 1e-9)


def _soru_alan(bolge):
    x0, y0, x1, y1 = bolge["kutu"]
    return max(0.0, x1 - x0) * max(0.0, y1 - y0)


def _soru_kucuk_kapsama(a, b):
    """İki kutunun kesişiminin küçük kutuya oranı."""
    ax0, ay0, ax1, ay1 = a["kutu"]
    bx0, by0, bx1, by1 = b["kutu"]
    w = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    h = max(0.0, min(ay1, by1) - max(ay0, by0))
    return w * h / max(min(_soru_alan(a), _soru_alan(b)), 1e-9)


def _soru_aggregate_gruplari(bolgeler, semantik_bolgeler):
    """Global parent ile ayrık, anlamlı yerel çocuklarını bilgi kayıpsız bul.

    Ayrık çocuklar iki gerçek soru da, tek uzun sorunun metin/şekil parçaları
    da olabilir. Kanonik katman bu yorumu yapmaz: many-to-one hiyerarşisini
    korur ve çağıranların açık ``layout``/``instance`` görünümünü seçmesini
    sağlar. En az iki ayrık çocuk yoksa ilişki 1:1 tekrardır ve eski geniş
    global-kutu tekilleştirmesi geçerlidir.
    """
    gruplar = []
    tumu = list(bolgeler or [])
    for global_bolge in tumu:
        sinif = global_bolge.get("sinif")
        if (sinif not in semantik_bolgeler
                or str(global_bolge.get("olcek") or "global") != "global"):
            continue
        global_guven = float(global_bolge.get("guven", 0.0))
        global_alan = _soru_alan(global_bolge)
        if global_guven < 0.50 or global_alan <= 0.0:
            continue
        yereller = []
        for cocuk in tumu:
            if (cocuk is global_bolge or cocuk.get("sinif") != sinif
                    or not str(cocuk.get("olcek") or "").startswith(
                        "yerel_")):
                continue
            cocuk_alan = _soru_alan(cocuk)
            if (cocuk_alan < global_alan * 0.02
                    or float(cocuk.get("guven", 0.0))
                    < max(SORU_MODEL_GUVEN_ALT, global_guven - 0.35)
                    or _soru_kucuk_kapsama(global_bolge, cocuk) < 0.88):
                continue
            yereller.append(cocuk)
        ayrik_cocuk_ids = set()
        for i, sol in enumerate(yereller):
            for sag in yereller[i + 1:]:
                if _soru_kucuk_kapsama(sol, sag) <= 0.10:
                    ayrik_cocuk_ids.update((id(sol), id(sag)))
        ayrik_cocuklar = [
            b for b in yereller if id(b) in ayrik_cocuk_ids]
        if len(ayrik_cocuklar) >= 2:
            gruplar.append((global_bolge, ayrik_cocuklar))
    return gruplar


def _soru_bolgeleri_tekillestir(bolgeler):
    """Global/yerel aynı-sınıf tekrarlarını güvenle tekilleştir.

    Klasik IoU, büyük bir global ``question_body`` içinde kalan kısa yerel
    gövdeyi tekrar olarak göremez. Birleşme koruması da bu iç içe ikiliyi iki
    ayrı soru sanır. Yüksek küçük-kutu kapsamasında, güven farkı aşırı değilse
    semantik bölge sınıfları için daha kapsamlı kutu korunur. Bir global kutu
    birden çok ayrık yerel çocuğu topluyorsa hiçbir katman silinmez; ilişki
    metadata'sı daha sonra iki ayrı görünüm üretmek üzere korunur.
    """
    tekil = []
    semantik_bolgeler = {
        "question_body", "shared_stimulus", "solution_or_answer"}
    tumu = list(bolgeler or [])
    gruplar = _soru_aggregate_gruplari(tumu, semantik_bolgeler)
    parent_ids = {id(parent) for parent, _cocuklar in gruplar}
    korunan_ciftler = {
        frozenset((id(parent), id(cocuk)))
        for parent, cocuklar in gruplar for cocuk in cocuklar
    }
    # Bir global duplicate seçilecekse hiyerarşi kanıtı taşıyan parent önce
    # gelir; aksi halde daha güvenli ama çocukları tam kapsamayan komşu global
    # kutu many-to-one bilgisini dolaylı biçimde yok edebilir.
    for aday in sorted(
            tumu,
            key=lambda b: (id(b) in parent_ids,
                           float(b.get("guven", 0.0))),
            reverse=True):
        birlesti = False
        for i, onceki in enumerate(tekil):
            if aday.get("sinif") != onceki.get("sinif"):
                continue
            if frozenset((id(aday), id(onceki))) in korunan_ciftler:
                continue
            if _soru_iou(aday, onceki) >= 0.55:
                birlesti = True
                break
            if (aday.get("sinif") in semantik_bolgeler
                    and _soru_kucuk_kapsama(aday, onceki) >= 0.88):
                aday_alan, onceki_alan = _soru_alan(aday), _soru_alan(onceki)
                buyuk, kucuk = ((aday, onceki) if aday_alan >= onceki_alan
                                else (onceki, aday))
                if (float(buyuk.get("guven", 0.0)) + 0.20
                        >= float(kucuk.get("guven", 0.0))):
                    tekil[i] = buyuk
                birlesti = True
                break
        if not birlesti:
            tekil.append(aday)
    return tekil


def _soru_bolgelerini_sirala(bolgeler):
    """Soğuk çıkarım ve cache isabeti için aynı kanonik y/x sırası."""
    return sorted(
        bolgeler,
        key=lambda b: (b["kutu"][1], b["kutu"][0], b["sinif"],
                       -float(b.get("guven", 0.0))))


def _soru_bolgelerini_kimliklendir(bolgeler):
    """Bölge kimliklerini sıralama/cache yolundan bağımsız yeniden üret."""
    for bolge in bolgeler:
        model_id = str(bolge.get("model_id") or "unknown")
        ham_id = (f"{model_id}|{bolge['sinif']}|"
                  + ",".join(f"{float(v):.3f}" for v in bolge["kutu"]))
        bolge["id"] = "qm-" + hashlib.sha256(
            ham_id.encode("utf-8")).hexdigest()[:20]
    return bolgeler


def _soru_aggregate_iliskilerini_ata(bolgeler):
    """Parent/leaf ilişkisini deterministik kimliklerle metadata'ya yaz."""
    semantik_bolgeler = {
        "question_body", "shared_stimulus", "solution_or_answer"}
    for bolge in bolgeler:
        bolge.pop("iliski", None)
        bolge.pop("parent_id", None)
        bolge.pop("child_ids", None)
    gruplar = _soru_aggregate_gruplari(bolgeler, semantik_bolgeler)
    atanmis_cocuk_ids = set()
    # Bir çocuk birden çok geniş parent içinde kalırsa en dar parent kazanır;
    # eşitlikler güven ve kanonik konum/kimlikle çözülür.
    for parent, cocuklar in sorted(
            gruplar, key=lambda g: (
                _soru_alan(g[0]), -float(g[0].get("guven", 0.0)),
                g[0]["kutu"][1], g[0]["kutu"][0], g[0]["id"])):
        musait = [
            c for c in cocuklar if c["id"] not in atanmis_cocuk_ids]
        ayrik_ids = set()
        for i, sol in enumerate(musait):
            for sag in musait[i + 1:]:
                if _soru_kucuk_kapsama(sol, sag) <= 0.10:
                    ayrik_ids.update((sol["id"], sag["id"]))
        sirali_cocuklar = _soru_bolgelerini_sirala(
            [c for c in musait if c["id"] in ayrik_ids])
        if len(sirali_cocuklar) < 2:
            continue
        parent["iliski"] = "aggregate_parent"
        parent["child_ids"] = [cocuk["id"] for cocuk in sirali_cocuklar]
        for cocuk in sirali_cocuklar:
            cocuk["iliski"] = "instance_leaf"
            cocuk["parent_id"] = parent["id"]
            atanmis_cocuk_ids.add(cocuk["id"])
    return bolgeler


def _soru_model_gorunumleri(bolgeler):
    """Aynı hiyerarşiden çakışmasız layout ve instance görünümleri üret."""
    sirali = _soru_bolgelerini_sirala(list(bolgeler or []))
    layout_view = [
        b for b in sirali if b.get("iliski") != "instance_leaf"]
    instance_view = [
        b for b in sirali if b.get("iliski") != "aggregate_parent"]
    return {
        "layout_view": layout_view,
        "instance_view": instance_view,
    }


def _soru_bolgelerini_kanoniklestir(bolgeler):
    """Tekilleştirme, sıra, kimlik ve hiyerarşiyi tek yolda uygula."""
    tekil = _soru_bolgelerini_sirala(
        _soru_bolgeleri_tekillestir(bolgeler))
    _soru_bolgelerini_kimliklendir(tekil)
    return _soru_aggregate_iliskilerini_ata(tekil)


def kanonik_soru_bolgeleri(ham_bolgeler, boyut, model_bilgisi=None):
    """İşçi sonuçlarını tek, sürümlü soru-bölgesi sözleşmesine dönüştürür.

    Bilinmeyen sınıflar ve geçersiz kutular atılır; koordinatlar görüntüye
    kırpılır; global/yerel aynı-sınıf tekrarları güvene göre NMS edilir.
    ``guven`` ham model güvenidir ve özellikle kalibre edilmiş gibi sunulmaz.
    """
    try:
        genislik, yukseklik = (float(boyut[0]), float(boyut[1]))
    except (TypeError, ValueError, IndexError):
        return []
    if not (math.isfinite(genislik) and math.isfinite(yukseklik)
            and genislik > 0 and yukseklik > 0):
        return []
    bilgi = model_bilgisi or _soru_model_bilgisi()
    model_id = bilgi.get("model_id", "unknown")
    model_surumu = bilgi.get("model_version", "unknown")
    adaylar = []
    for ham in ham_bolgeler or []:
        if not isinstance(ham, dict):
            continue
        sinif_ham = str(ham.get("sinif", "")).strip().casefold()
        sinif = _SORU_SINIF_ESLE.get(sinif_ham)
        if sinif not in SORU_MODEL_SINIFLARI:
            continue
        kutu = ham.get("kutu")
        if not isinstance(kutu, (list, tuple)) or len(kutu) != 4:
            continue
        try:
            x0, y0, x1, y1 = (float(v) for v in kutu)
            guven = float(ham.get("guven", 0.0))
        except (TypeError, ValueError):
            continue
        if not all(math.isfinite(v) for v in (x0, y0, x1, y1, guven)):
            continue
        x0, x1 = sorted((max(0.0, min(genislik, x0)),
                         max(0.0, min(genislik, x1))))
        y0, y1 = sorted((max(0.0, min(yukseklik, y0)),
                         max(0.0, min(yukseklik, y1))))
        if x1 - x0 < 2.0 or y1 - y0 < 2.0:
            continue
        olcek = str(ham.get("olcek") or "global")
        if not (olcek == "global" or olcek.startswith("yerel_")):
            olcek = "global"
        adaylar.append({
            "schema_version": SORU_MODEL_CIKTI_SURUMU,
            "sinif": sinif,
            "kutu": [round(x0, 3), round(y0, 3),
                     round(x1, 3), round(y1, 3)],
            "guven": round(max(0.0, min(1.0, guven)), 6),
            "guven_turu": "ham_model",
            "olcek": olcek,
            "gecis": "globalden_yerele" if olcek.startswith("yerel_")
                     else "global",
            "kaynak": "question_specific_model",
            "kaynak_yontemler": ["question_specific_model", olcek],
            "model_id": model_id,
            "model_surumu": model_surumu,
        })
    return _soru_bolgelerini_kanoniklestir(adaylar)


def soru_bolgeleri_gorsel(pil_img, onbellek_kimlik=None):
    """Soru-özel global→yerel çıkarım; hata/eksik modelde daima ``[]``.

    Model ağırlığı yalnız yerel diskten okunur. İşçi internet erişimini teşvik
    eden entegrasyonları çevre değişkenleriyle kapalı başlatır. Dönen her kayıt
    :func:`kanonik_soru_bolgeleri` sözleşmesindedir.
    """
    if not soru_modeli_kullanilabilir():
        return []
    baslangic_bilgisi = _soru_model_bilgisi()
    anahtar = _soru_model_kimlik_bilgiden(
        onbellek_kimlik, baslangic_bilgisi)
    onbellek = _soru_cache_oku(
        anahtar, baslangic_bilgisi.get("model_id"))
    if onbellek is not None:
        # V1 cache kayıtlarında iç içe global/yerel tekrarlar bulunabilir.
        # Okuma anındaki tekilleştirme eski güvenli cache'i yeniden çıkarım
        # gerektirmeden yeni karar sözleşmesine yükseltir.
        return _soru_bolgelerini_kanoniklestir(onbellek)
    gecici = None
    try:
        os.makedirs(SORU_MODEL_CACHE_DIZIN, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=SORU_MODEL_CACHE_DIZIN,
                                         suffix=".png", delete=False) as f:
            gecici = f.name
        pil_img.save(gecici, "PNG", compress_level=1)
        cikarim = _soru_istek(gecici)
        if cikarim is None:
            return []
        bilgi = cikarim["model_bilgisi"]
        bolgeler = kanonik_soru_bolgeleri(
            cikarim["bolgeler"], pil_img.size, bilgi)
        donmus_anahtar = _soru_model_kimlik_bilgiden(
            onbellek_kimlik, bilgi)
        _soru_cache_yaz(
            donmus_anahtar, bolgeler, bilgi.get("model_id"))
        return bolgeler
    except Exception:  # noqa: BLE001 -- soru tespiti sezgisel yola düşer
        return []
    finally:
        if gecici:
            try:
                os.unlink(gecici)
            except OSError:
                pass


# Açık ve kolay keşfedilen API adları; Türkçe ana API geriye dönük stile uyar.
soru_model_bolgeleri_gorsel = soru_bolgeleri_gorsel
question_regions_image = soru_bolgeleri_gorsel


def kapat():
    with _KILIT:
        _oldur()
    with _SORU_KILIT:
        _soru_oldur()


atexit.register(kapat)
