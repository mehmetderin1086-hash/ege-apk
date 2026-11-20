#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — çok-motorlu OCR hakemliği (istemci).

Apple Vision birincil kalır; yalnız ŞÜPHELİ satırlarda diğer yerel motorlar
(easyocr, rapidocr, tesseract, surya) hakem olarak çağrılıp oy verir. Ağır
motorlar .venv-ml altındaki tek `ocr_isci.py` alt-sürecinde çalışır
(duzen_model istemci deseni). Bu modül YALNIZ stdlib kullanır → ana .venv
(Py3.9) her koşulda içe aktarabilir; motor yoksa her API nötr döner
(regresyon-nötr).

Sözleşme:
- hakemlik(pil_img, meta, duzelt, kimlik) -> (yeni_meta, kayit)
    meta: OCRSatiri (frozen dataclass) listesi; duck-typing ile .metin/.kutu/
    .guven/.adaylar okunur, dataclasses.replace ile yenisi üretilir.
- motor_satirlar(pil_img, motor) -> [(metin, kutu_px), ...]  (ocr_kiyas için)
- mod_al() / kullanilabilir() / motor_imzasi() / motor_durumlari()
"""

import dataclasses
import difflib
import json
import os
import queue
import subprocess
import tempfile
import threading

import isci_ortam

HAKEM_SURUM = 1

KOK = os.path.dirname(os.path.abspath(__file__))
ISCI_PY = isci_ortam.isci_python()
ISCI_BETIK = os.path.join(KOK, "ocr_isci.py")
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")
LOG_YOLU = os.path.join(tempfile.gettempdir(), "soru_kesici_ocr_isci.log")

MODLAR = ("hizli", "dengeli", "tam")
MOD_ZORLA = None               # CLI --ocr-modu bunu ayarlar

# Motor ağırlıkları (kıyas kalibrasyonuyla güncellenebilir; ayar override).
MOTOR_AGIRLIK = {"vision": 1.0, "surya": 0.9, "rapidocr": 0.8,
                 "easyocr": 0.75, "tesseract": 0.7}

# Hakemlik parametreleri
HAKEM_SATIR_LIMIT = 8          # dengeli modda sayfa başına hakemlenecek satır
HAKEM_SATIR_LIMIT_GENIS = 16   # düşük güvenli sayfa
MARJ = 0.25                    # kazanan Vision'ı bu kadar aşmadıkça değişmez
GUVEN_ESIK_DENGELI = 0.80
GUVEN_ESIK_DIAKRITIK = 0.86
CAPA_ESIK = 0.90
YANIT_ZAMAN = 30
YANIT_ZAMAN_TAM = 120
HAZIR_ZAMAN = 60

_KILIT = threading.RLock()
_ISCI = None                   # (proc, kuyruk) | None
_BOZUK = False                 # kalıcı devre kesici
_SAYAC = 0
_PROBE = None                  # {"motorlar": {...}, "cihaz": ...} | False


# --------------------------------------------------------------- ayar / mod
def _ayar_oku():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def mod_al():
    """hizli | dengeli | tam. Öncelik: MOD_ZORLA > env > ayar > hizli."""
    if MOD_ZORLA in MODLAR:
        return MOD_ZORLA
    env = os.environ.get("SORU_KESICI_OCR_MODU")
    if env in MODLAR:
        return env
    ayar = _ayar_oku().get("ocr_modu")
    return ayar if ayar in MODLAR else "hizli"


def _agirliklar():
    a = dict(MOTOR_AGIRLIK)
    try:
        a.update(_ayar_oku().get("ocr_motor_agirliklari") or {})
    except Exception:  # noqa: BLE001
        pass
    return a


# --------------------------------------------------------------- işçi köprüsü
def _isci_baslat():
    """İşçiyi başlatır, el sıkışmayı bekler. _KILIT altında çağrılır."""
    global _ISCI, _PROBE
    if not os.path.exists(ISCI_PY) or not os.path.exists(ISCI_BETIK):
        _PROBE = False
        raise RuntimeError("ocr_isci veya .venv-ml yok")
    log = open(LOG_YOLU, "a", encoding="utf-8")
    proc = subprocess.Popen(
        [ISCI_PY, ISCI_BETIK],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
        text=True, encoding="utf-8", bufsize=1)
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
    durum = q.get(timeout=HAZIR_ZAMAN)
    if not (isinstance(durum, dict) and durum.get("ok")):
        raise RuntimeError(f"ocr işçisi hazır değil: {durum}")
    _PROBE = {"motorlar": durum.get("motorlar") or {},
              "cihaz": durum.get("cihaz")}
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


def _istek(govde, zaman=YANIT_ZAMAN):
    """İşçiye JSON istek gönderir, yanıt sözlüğü | None (hata → _BOZUK)."""
    global _BOZUK, _SAYAC
    with _KILIT:
        if _BOZUK:
            return None
        try:
            if _ISCI is None:
                _isci_baslat()
            proc, q = _ISCI
            _SAYAC += 1
            no = _SAYAC
            govde = dict(govde, id=no)
            proc.stdin.write(json.dumps(govde, ensure_ascii=False) + "\n")
            proc.stdin.flush()
            while True:
                yanit = q.get(timeout=zaman)
                if yanit is None:
                    raise RuntimeError("ocr işçisi kapandı")
                if yanit.get("id") == no:
                    return yanit
        except Exception:  # noqa: BLE001 — sessiz geri düşüş
            _oldur()
            _BOZUK = True
            return None


def _probe_al():
    """İşçi el sıkışma bilgisini (motor durumları) döndürür; başlatmayı dener."""
    global _PROBE
    with _KILIT:
        if _PROBE is not None:
            return _PROBE
        if _BOZUK:
            return False
        try:
            if _ISCI is None:
                _isci_baslat()
        except Exception:  # noqa: BLE001
            _PROBE = False
        return _PROBE


def kullanilabilir():
    """Ensemble devrede mi: mod != hizli VE işçi + en az bir hakem motoru."""
    if mod_al() == "hizli":
        return False
    p = _probe_al()
    if not p:
        return False
    return any(v for k, v in (p.get("motorlar") or {}).items()
               if k != "vision")


def motor_imzasi():
    """Kurulu-aktif hakem motorlarının kararlı imzası (cache anahtarına girer).
    hizli modda boş dize → cache anahtarı sabit kalır."""
    if mod_al() == "hizli":
        return ""
    p = _probe_al()
    if not p:
        return ""
    aktif = sorted(k for k, v in (p.get("motorlar") or {}).items()
                   if v and k != "vision")
    return "+".join(aktif)


def motor_durumlari():
    """Web /ocr-durum için: {"mod", "motorlar": {ad: bool}, "cihaz"}."""
    mod = mod_al()
    kurulu = os.path.exists(ISCI_PY) and os.path.exists(ISCI_BETIK)
    p = _probe_al() if mod != "hizli" else None
    motorlar = {"vision": True}
    if isinstance(p, dict):
        motorlar.update(p.get("motorlar") or {})
    return {"mod": mod, "kurulu": kurulu,
            "motorlar": motorlar,
            "cihaz": (p or {}).get("cihaz") if isinstance(p, dict) else None,
            "kurulum_komutu": ".venv-ml/bin/python ocr_kur.py"}


# --------------------------------------------------------------- saf mantık
_SUPHELI = set("ìíî")          # bağlam-dışı işaretli küçük harfler
_TR_DISI = set("qwxQWX")       # Türkçe'de nadir → OCR şüphesi


def _capa_mi(metin):
    import re
    return bool(re.match(r"^\s*\d{1,3}\s*[.)]", metin or ""))


def _rakam_var(metin):
    return any(c.isdigit() for c in (metin or ""))


def _yalniz_diakritik_farki(a, b):
    """İki dize yalnız diakritik/tek-karakter değişimiyle mi ayrışıyor?"""
    if a == b or abs(len(a) - len(b)) > 2:
        return abs(len(a) - len(b)) <= 2 and _benzerlik(a, b) >= 0.85
    return _benzerlik(a, b) >= 0.85


def _benzerlik(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


def satir_hizala(ana_kutu, aday_satirlar):
    """ana_kutu (x0,y0,x1,y1) ile dikeyde ≥%50 örtüşen + yatayda kesişen
    aday satırları döndürür (metin, guven ikilileri)."""
    ax0, ay0, ax1, ay1 = ana_kutu
    ah = max(1.0, ay1 - ay0)
    eslesme = []
    for metin, kutu, guven in aday_satirlar:
        bx0, by0, bx1, by1 = kutu
        ortu = min(ay1, by1) - max(ay0, by0)
        if ortu / ah < 0.5:
            continue
        if min(ax1, bx1) - max(ax0, bx0) <= 0:
            continue
        eslesme.append((metin, guven))
    return eslesme


def kelime_oyla(vision_metin, vision_guven, adaylar, agirliklar,
                sozluk=None, capa=False):
    """Aday havuzundan kazanan metni seçer. adaylar: [(motor, metin, guven)].
    Dönüş: (kazanan_metin, kazanan_skor, degisti). Muhafazakâr: kazanan
    Vision'ı MARJ aşmadıkça vision_metin döner (capa hariç: ≥2 motor aynı
    numarayı okursa kazanır)."""
    sozluk = sozluk or set()
    havuz = {}   # metin -> skor
    vw = agirliklar.get("vision", 1.0)
    havuz[vision_metin] = havuz.get(vision_metin, 0.0) + vw * vision_guven
    for motor, metin, guven in adaylar:
        if not metin:
            continue
        w = agirliklar.get(motor, 0.7)
        skor = w * max(0.05, guven)
        if sozluk and metin in sozluk:
            skor += 0.15
        havuz[metin] = havuz.get(metin, 0.0) + skor

    if capa:
        # Rakam/çapa satırı: ≥2 motor (Vision dahil) aynı metni okursa kazanır.
        sayim = {}
        tum = [(vision_metin, vision_guven)] + [(m, g) for _, m, g in adaylar]
        for metin, _ in tum:
            sayim[metin] = sayim.get(metin, 0) + 1
        en_cok = max(sayim.items(), key=lambda kv: kv[1])
        if en_cok[1] >= 2 and en_cok[0] != vision_metin:
            return en_cok[0], havuz.get(en_cok[0], 0.0), True
        return vision_metin, havuz[vision_metin], False

    kazanan = max(havuz.items(), key=lambda kv: kv[1])
    v_skor = havuz[vision_metin]
    if kazanan[0] != vision_metin and kazanan[1] >= v_skor * (1 + MARJ):
        return kazanan[0], kazanan[1], True
    return vision_metin, v_skor, False


def _tetikleyici(satir, mod, sozluk):
    """Bu satır hakemliği tetikliyor mu? (T1 çapa, T2 düzeltme-sonrası şüphe,
    T3 düşük güven, T4 sözlük-dışılık)."""
    metin, guven = satir.metin, satir.guven
    if _capa_mi(metin) or _rakam_var(metin):
        if guven < CAPA_ESIK:
            return True
    if any(c in _SUPHELI for c in metin) or any(c in _TR_DISI for c in metin):
        return True
    esik = GUVEN_ESIK_DENGELI
    # Vision adayları yalnız diakritikle ayrışıyorsa eşik yükselir
    if len(satir.adaylar) >= 2:
        m0 = satir.adaylar[0][0]
        if any(_yalniz_diakritik_farki(m0, a[0]) and a[0] != m0
               for a in satir.adaylar[1:]):
            esik = GUVEN_ESIK_DIAKRITIK
    if guven < esik:
        return True
    if sozluk and len(metin) >= 12:
        tokenlar = [t for t in metin.split() if len(t) >= 3]
        if tokenlar:
            yabanci = sum(1 for t in tokenlar if t.lower() not in sozluk)
            if yabanci / len(tokenlar) >= 0.5:
                return True
    return False


def _belge_sozlugu(meta):
    """Belge-içi dinamik sözlük: yüksek güvenli satırların token'ları."""
    sozluk = set()
    for s in meta:
        if s.guven >= 0.95:
            for t in s.metin.split():
                t = t.strip(".,;:()[]").lower()
                if len(t) >= 3:
                    sozluk.add(t)
    return sozluk


# --------------------------------------------------------------- ana giriş
def hakemlik(pil_img, meta, duzelt=None, kimlik=None):
    """ŞÜPHELİ satırlarda çok-motor hakemliği uygular. meta: OCRSatiri
    listesi. Dönüş: (yeni_meta, kayit). Ensemble kapalı/motor yoksa meta
    değişmeden döner (kayit['mod']='hizli')."""
    duzelt = duzelt or (lambda x: x)
    mod = mod_al()
    if mod == "hizli" or not kullanilabilir():
        return meta, {"mod": "hizli", "degisen": 0, "tetiklenen": 0}

    sozluk = _belge_sozlugu(meta)
    agirliklar = _agirliklar()
    limit = HAKEM_SATIR_LIMIT
    if meta:
        ort = sum(s.guven for s in meta) / len(meta)
        if ort < 0.75:
            limit = HAKEM_SATIR_LIMIT_GENIS

    # Tetiklenen satır indekslerini seç (öncelik: çapa/rakam önce)
    adaylar = [(i, s) for i, s in enumerate(meta)
               if _tetikleyici(s, mod, sozluk)]
    adaylar.sort(key=lambda it: (0 if _capa_mi(it[1].metin)
                                 or _rakam_var(it[1].metin) else 1,
                                 it[1].guven))
    adaylar = adaylar[:limit]
    if not adaylar:
        return meta, {"mod": mod, "degisen": 0, "tetiklenen": 0}

    # İşçiye tek istek: her aday satırın bölgesini hakem motorlar okusun
    hakem_motorlar = ["rapidocr", "tesseract"] if mod == "dengeli" \
        else ["rapidocr", "tesseract", "easyocr", "surya"]
    p = _probe_al()
    if isinstance(p, dict):
        var = p.get("motorlar") or {}
        hakem_motorlar = [m for m in hakem_motorlar if var.get(m)]
    if not hakem_motorlar:
        return meta, {"mod": mod, "degisen": 0, "tetiklenen": len(adaylar)}

    gecici = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            gecici = f.name
        pil_img.save(gecici, "PNG", compress_level=1)
        bolgeler = [[float(v) for v in meta[i].kutu] for i, _ in adaylar]
        yanit = _istek({"png": gecici, "motorlar": hakem_motorlar,
                        "bolgeler": bolgeler},
                       zaman=YANIT_ZAMAN_TAM if mod == "tam" else YANIT_ZAMAN)
    finally:
        if gecici:
            try:
                os.unlink(gecici)
            except OSError:
                pass

    if not yanit or "bolge_sonuclari" not in yanit:
        return meta, {"mod": mod, "degisen": 0, "tetiklenen": len(adaylar),
                      "butce_asildi": bool(yanit and yanit.get("butce_asildi"))}

    yeni = list(meta)
    degisen = 0
    sonuclar = yanit["bolge_sonuclari"]   # [{motor: [metin,...]}, ...]
    for (i, satir), bolge in zip(adaylar, sonuclar):
        motor_adaylari = []
        for motor, satlar in (bolge or {}).items():
            if not isinstance(satlar, list):
                continue
            # bölge içindeki tüm satır metinlerini birleştir (tek çapa/kısa satır)
            metin = duzelt(" ".join(str(s.get("metin", "")) for s in satlar
                                    if s.get("metin")).strip())
            if not metin:
                continue
            guven = max((float(s.get("guven", 0)) for s in satlar), default=0.5)
            motor_adaylari.append((motor, metin, guven))
        # Vision adaylarını da havuza kat
        for am, ag in satir.adaylar[:3]:
            motor_adaylari.append(("vision", duzelt(am), ag))
        capa = _capa_mi(satir.metin) or _rakam_var(satir.metin)
        kazanan, skor, degisti = kelime_oyla(
            satir.metin, satir.guven, motor_adaylari, agirliklar,
            sozluk=sozluk, capa=capa)
        # adaylar her hâlükârda zenginleşir
        yeni_adaylar = tuple(satir.adaylar) + tuple(
            (m, g) for _, m, g in motor_adaylari
            if m not in {a[0] for a in satir.adaylar})
        if degisti and kazanan != satir.metin:
            degisen += 1
            yeni[i] = dataclasses.replace(
                satir, metin=kazanan,
                guven=min(0.99, max(satir.guven, skor / max(1, len(
                    motor_adaylari) + 1))),
                adaylar=yeni_adaylar, kaynak="hakem:" + "+".join(
                    m for m, _, _ in motor_adaylari[:3]))
        else:
            yeni[i] = dataclasses.replace(satir, adaylar=yeni_adaylar)

    return yeni, {"mod": mod, "degisen": degisen,
                  "tetiklenen": len(adaylar),
                  "motorlar": hakem_motorlar}


def motor_satirlar(pil_img, motor, duzelt=False):
    """Tek motorla tüm sayfayı okur (ocr_kiyas MOTORLAR sözleşmesi).
    Dönüş: [(metin, kutu_px), ...]. Motor yoksa []."""
    gecici = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            gecici = f.name
        pil_img.save(gecici, "PNG", compress_level=1)
        yanit = _istek({"png": gecici, "motorlar": [motor], "bolgeler": None})
    finally:
        if gecici:
            try:
                os.unlink(gecici)
            except OSError:
                pass
    if not yanit or "sonuclar" not in yanit:
        return []
    satlar = (yanit["sonuclar"] or {}).get(motor) or []
    if isinstance(satlar, dict):    # {"hata": ...}
        return []
    return [(str(s.get("metin", "")), tuple(s.get("kutu") or (0, 0, 0, 0)))
            for s in satlar if s.get("metin")]


def kapat():
    with _KILIT:
        _oldur()


import atexit
atexit.register(kapat)
