#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik okuma istemcisi — yalnız stdlib (+ PIL/fitz girdi hazırlığında),
ana .venv'de (Python 3.9) çalışır.

İşçi (optik_isci.py, .venv-ml) piksel→ölçüm katmanıdır; ölçüm→hüküm
(eşikleme, bos/tek/coklu/belirsiz, güven, iptal) BURADADIR ve cv2'siz
birim-testlenir (duzen_model.py istemci deseni).

Eşikleme: skor = 0.6·doluluk + 0.4·(1−parlaklık). Sayfadaki tüm skorlar
sıralanır; boş küme ile dolu küme arasındaki EN BÜYÜK SIÇRAMA eşiği verir
(OMRChecker mantığı — sabit oran değil, sayfa-uyarlamalı). Alan bazında
yeterince güçlü yerel sıçrama varsa yerel eşik kullanılır. Hiçbir yerde
argmax yoktur: her soru bos/tek/coklu/belirsiz hükmü + güven (0-1) alır;
belirsiz/çoklu kağıtlar inceleme kuyruğuna düşer.
"""
import atexit
import json
import os
import queue
import subprocess
import threading

import isci_ortam
import veri_yollari

AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")
PROJE = os.path.dirname(os.path.abspath(__file__))
ISCI_PY = isci_ortam.isci_python()
ISCI_BETIK = os.path.join(PROJE, "optik_isci.py")
CACHE_DIZIN = os.path.join(veri_yollari.onbellek_koku(), "optik")
LOG_YOLU = os.path.join(CACHE_DIZIN, "isci.log")
HAZIR_ZAMAN = 60.0
YANIT_ZAMAN = 60.0
GIRDI_DPI = 200

# Hüküm parametreleri (golden testlerle ayarlandı)
MIN_SICRAMA = 0.18        # dolu/boş kümeleri ayıran asgari sıçrama
TABAN_ESIK = 0.30         # eşik tabanı: boş kümenin gürültüsü işaret sayılmaz
BELIRSIZ_MARJ = 0.07      # eşiğe bu kadar yakın skor → belirsiz
YEREL_SICRAMA_KAT = 0.75  # yerel eşik ancak global sıçramanın bu katıysa
IPTAL_DAYANIM = 0.22      # erozyon dayanımı altı + dolu görünüm → iptal (X)
IPTAL_DOLULUK = 0.80      # tam dolu balon iptal sayılmaz

_KILIT = threading.Lock()
_ISCI = None
_BOZUK = False
_SAYAC = 0


# ------------------------------------------------------------ kullanılabilirlik

def optik_dogrula(derin=False):
    """{"ok": bool, "mesaj": str}; derin=True işçiyi --probe ile açar."""
    if not (os.path.isfile(ISCI_PY) and os.access(ISCI_PY, os.X_OK)):
        return {"ok": False,
                "mesaj": "optik ortamı kurulu değil — python3 optik_kur.py"}
    if not os.path.isfile(ISCI_BETIK):
        return {"ok": False, "mesaj": "optik_isci.py bulunamadı"}
    if derin:
        try:
            s = subprocess.run([ISCI_PY, ISCI_BETIK, "--probe"],
                               capture_output=True, text=True,
                               encoding="utf-8", timeout=120)
            ilk = (s.stdout or "").strip().splitlines()
            durum = json.loads(ilk[0]) if ilk else {}
            if durum.get("ok"):
                return {"ok": True, "mesaj": f"hazır (cv2 {durum.get('cv2')})"}
            return {"ok": False, "mesaj": durum.get("hata")
                    or f"işçi başlatılamadı — bkz. {LOG_YOLU}"}
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "mesaj": f"{type(e).__name__}: {e}"}
    return {"ok": True, "mesaj": "hazır"}


def kullanilabilir():
    return not _BOZUK and optik_dogrula()["ok"]


# ------------------------------------------------------------------ işçi yönetimi

def _isci_baslat():
    global _ISCI
    os.makedirs(CACHE_DIZIN, exist_ok=True)
    log = open(LOG_YOLU, "a", encoding="utf-8")
    proc = subprocess.Popen([ISCI_PY, ISCI_BETIK],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=log, text=True, encoding="utf-8",
                            bufsize=1)
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
        for akis in (proc.stdin, proc.stdout):
            try:
                akis.close()
            except OSError:
                pass
    except Exception:  # noqa: BLE001
        pass


def isci_istek(istek):
    """Tek sayfa isteği → işçi yanıtı | RuntimeError. Kalıcı işçi süreci."""
    global _BOZUK, _SAYAC
    with _KILIT:
        if _BOZUK:
            raise RuntimeError("optik işçisi daha önce çöktü "
                               f"(bkz. {LOG_YOLU})")
        try:
            if _ISCI is None:
                _isci_baslat()
            proc, q = _ISCI
            _SAYAC += 1
            istek = dict(istek, id=_SAYAC)
            proc.stdin.write(json.dumps(istek) + "\n")
            proc.stdin.flush()
            while True:
                yanit = q.get(timeout=YANIT_ZAMAN)
                if yanit is None:
                    raise RuntimeError("işçi beklenmedik şekilde kapandı")
                if yanit.get("id") == istek["id"]:
                    if "hata" in yanit:
                        raise RuntimeError(yanit["hata"])
                    return yanit
        except Exception:
            _oldur()
            _BOZUK = True
            raise


def kapat():
    with _KILIT:
        _oldur()


atexit.register(kapat)


# ------------------------------------------------------------------ girdi hazırlığı

RASTER_UZANTILAR = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp",
                    ".gif", ".webp", ".heic"}


def girdileri_hazirla(yollar, hedef_dizin, dpi=GIRDI_DPI):
    """PDF/görüntü girdilerini işçi için PNG'lere açar.

    Dönüş: [{"kaynak": yol, "kaynak_sayfa": n, "png": png_yolu}].
    Fotoğraflar EXIF yönü uygulanıp alfa beyaza bindirilerek normalize
    edilir (soru_kes._raster_rgb_hazirla ile aynı kurallar).
    """
    from PIL import Image, ImageOps
    os.makedirs(hedef_dizin, exist_ok=True)
    sonuc = []
    sira = 0
    for yol in yollar:
        uzanti = os.path.splitext(yol)[1].lower()
        if uzanti == ".pdf":
            import fitz
            doc = fitz.open(yol)
            for i, sayfa in enumerate(doc):
                sira += 1
                png = os.path.join(hedef_dizin, f"g{sira:04d}.png")
                pix = sayfa.get_pixmap(matrix=fitz.Matrix(dpi / 72, dpi / 72))
                pix.save(png)
                sonuc.append({"kaynak": yol, "kaynak_sayfa": i + 1,
                              "png": png})
            doc.close()
        elif uzanti in RASTER_UZANTILAR:
            with Image.open(yol) as img:
                kare_sayisi = getattr(img, "n_frames", 1)
                for k in range(kare_sayisi):
                    if kare_sayisi > 1:
                        img.seek(k)
                    kare = ImageOps.exif_transpose(img)
                    if kare.mode in ("RGBA", "LA", "PA") or \
                            (kare.mode == "P" and
                             "transparency" in kare.info):
                        kare = kare.convert("RGBA")
                        from PIL import Image as _I
                        zemin = _I.new("RGBA", kare.size,
                                       (255, 255, 255, 255))
                        kare = _I.alpha_composite(zemin, kare)
                    kare = kare.convert("RGB")
                    sira += 1
                    png = os.path.join(hedef_dizin, f"g{sira:04d}.png")
                    kare.save(png)
                    sonuc.append({"kaynak": yol, "kaynak_sayfa": k + 1,
                                  "png": png})
        else:
            raise ValueError(f"desteklenmeyen girdi türü: {yol}")
    return sonuc


# ------------------------------------------------------------------ hüküm mantığı

def _skor(o):
    return 0.6 * o["doluluk"] + 0.4 * (1.0 - o["parlaklik"])


def _sicrama_esigi(skorlar):
    """Sıralı skorlarda İLK büyük sıçramadan eşik türetir (OMRChecker).

    İlk sıçrama boş kümenin bittiği yerdir → silik ama gerçek işaretler
    (ikinci, daha büyük sıçramanın altında kalsalar da) dolu sayılır.
    TABAN_ESIK, tek bir aşırı-açık boş balonun eşiği çökertmesini önler.
    Dönüş: (esik, sicrama); sıçrama yoksa sayfa tamamen boş kabul edilir."""
    if not skorlar:
        return 1.0, 0.0
    sirali = sorted(skorlar)
    n = len(sirali)
    pencere = max(1, n // 64)
    for i in range(n - pencere):
        fark = sirali[i + pencere] - sirali[i]
        if fark >= MIN_SICRAMA:
            esik = (sirali[i] + sirali[i + pencere]) / 2.0
            return max(esik, TABAN_ESIK), fark
    return max(sirali[-1] + BELIRSIZ_MARJ * 2, TABAN_ESIK), 0.0


def _iptal_mi(o):
    """Çizilerek iptal edilmiş işaret: CNN sınıfı varsa (işçi çapraz
    kontrolü, optik_model_egitim) o esas alınır; yoksa klasik sezgisel —
    mürekkep var ama ince (erozyona dayanıksız) ve disk tam dolu değil."""
    sinif = o.get("sinif")
    if sinif is not None and o.get("sinif_guven", 0.0) >= 0.6:
        if sinif == "iptal":
            return True
        if sinif == "dolu":
            return False
    return (o["doluluk"] < IPTAL_DOLULUK
            and o["erozyon_dayanimi"] < IPTAL_DAYANIM)


def _grup_hukmu(grup, esik, sicrama, semboller):
    """Bir soru/karakter grubunun hükmü.

    grup: aynı satır (coktan_secmeli) veya sütun (grid) ölçümleri,
    sembol sırasıyla. Dönüş: {"hukum","sembol","guven","adaylar"}."""
    isaretli, iptaller = [], []
    en_yakin = 1.0
    for sembol, o in zip(semboller, grup):
        s = _skor(o)
        en_yakin = min(en_yakin, abs(s - esik))
        if s >= esik:
            if _iptal_mi(o):
                iptaller.append(sembol)
            else:
                isaretli.append((s, sembol))
    guven = max(0.0, min(1.0, en_yakin / max(BELIRSIZ_MARJ * 2, 1e-6)))
    if sicrama:
        guven = min(guven, max(0.0, min(1.0, sicrama / (MIN_SICRAMA * 2))))
    if not isaretli:
        hukum = "bos"
        sembol = None
    elif len(isaretli) == 1:
        hukum = "tek"
        sembol = isaretli[0][1]
    else:
        hukum = "coklu"
        sembol = None
    if en_yakin < BELIRSIZ_MARJ and hukum != "coklu":
        hukum = "belirsiz"
    return {"hukum": hukum, "sembol": sembol,
            "guven": round(guven, 3),
            "adaylar": [s for _, s in
                        sorted(isaretli, key=lambda t: -t[0])],
            "iptal": iptaller}


def hukum_ver(olcumler, sablon, sayfa_no):
    """Sayfa ölçümleri → alan bazında hükümler (cv2'siz, saf fonksiyon).

    Dönüş: {alan_ad: [grup_hukmu, ...]} — coktan_secmeli'de soru sırasına,
    grid'lerde sütun (karakter) sırasına göre.
    """
    sayfa = next((s for s in sablon.sayfalar if s.sayfa_no == sayfa_no),
                 None)
    if sayfa is None:
        raise ValueError(f"şablonda sayfa yok: {sayfa_no}")
    dizin = {}
    for o in olcumler:
        dizin.setdefault(o["alan"], {})[(o["satir"], o["sutun"])] = o

    global_esik, global_sicrama = _sicrama_esigi(
        [_skor(o) for o in olcumler])

    sonuc = {}
    for alan in sayfa.alanlar:
        hucreler = dizin.get(alan.ad, {})
        alan_skorlar = [_skor(o) for o in hucreler.values()]
        esik, sicrama = global_esik, global_sicrama
        yerel_esik, yerel_sicrama = _sicrama_esigi(alan_skorlar)
        if yerel_sicrama >= max(MIN_SICRAMA,
                                global_sicrama * YEREL_SICRAMA_KAT):
            esik, sicrama = yerel_esik, yerel_sicrama
        gruplar = []
        if alan.tip in ("coktan_secmeli", "dogru_yanlis", "kitapcik"):
            for r in range(alan.satir):
                grup = [hucreler.get((r, c),
                                     {"doluluk": 0, "parlaklik": 1,
                                      "erozyon_dayanimi": 0})
                        for c in range(alan.sutun)]
                gruplar.append(_grup_hukmu(grup, esik, sicrama,
                                           alan.semboller))
        else:                                     # harf/rakam grid: sütun
            for c in range(alan.sutun):
                grup = [hucreler.get((r, c),
                                     {"doluluk": 0, "parlaklik": 1,
                                      "erozyon_dayanimi": 0})
                        for r in range(alan.satir)]
                gruplar.append(_grup_hukmu(grup, esik, sicrama,
                                           alan.semboller))
        sonuc[alan.ad] = gruplar
    return sonuc


def kagit_birlestir(hukumler, sablon, sayfa_no, kayit_bilgi, qr=None):
    """Alan hükümleri → tek kağıt kaydı (kimlikler + cevaplar + durum)."""
    sayfa = next(s for s in sablon.sayfalar if s.sayfa_no == sayfa_no)
    kagit = {"sayfa_no": sayfa_no, "qr": qr, "kayit": kayit_bilgi,
             "ogrenci_no": None, "ad_soyad": None, "tc_kimlik": None,
             "kitapcik": None, "cevaplar": {}, "sorunlar": []}
    supheli = 0
    for alan in sayfa.alanlar:
        gruplar = hukumler.get(alan.ad) or []
        if alan.tip in ("coktan_secmeli", "dogru_yanlis"):
            ders = kagit["cevaplar"].setdefault(alan.ders or "", {})
            for i, g in enumerate(gruplar):
                no = alan.soru_baslangic + i
                ders[str(no)] = {"hukum": g["hukum"], "sembol": g["sembol"],
                                 "guven": g["guven"],
                                 "adaylar": g["adaylar"],
                                 "iptal": g["iptal"]}
                if g["hukum"] in ("coklu", "belirsiz"):
                    supheli += 1
        elif alan.tip == "kitapcik":
            g = gruplar[0] if gruplar else None
            if g and g["hukum"] == "tek":
                kagit["kitapcik"] = g["sembol"]
            elif g and g["hukum"] != "bos":
                kagit["sorunlar"].append("kitapçık türü net değil")
        elif alan.tip in ("rakam_grid", "harf_grid"):
            parcalar = []
            eksik = False
            for g in gruplar:
                if g["hukum"] == "tek":
                    parcalar.append(g["sembol"])
                elif g["hukum"] == "bos":
                    parcalar.append(" " if alan.tip == "harf_grid" else "")
                else:
                    parcalar.append("?")
                    eksik = True
            deger = "".join(parcalar).strip() or None
            if alan.ad == "ogrenci_no":
                kagit["ogrenci_no"] = deger
                if eksik or not deger:
                    kagit["sorunlar"].append("öğrenci no eksik/şüpheli")
            elif alan.ad == "tc_kimlik":
                kagit["tc_kimlik"] = deger
            elif alan.ad == "ad_soyad":
                kagit["ad_soyad"] = deger
    yontem = (kayit_bilgi or {}).get("yontem") or ""
    hata_px = (kayit_bilgi or {}).get("yeniden_yansitma_px")
    if "aruco" not in yontem:
        kagit["sorunlar"].append(f"zayıf kayıt yöntemi: {yontem or 'yok'}")
    if hata_px is not None and hata_px > 3.0:
        kagit["sorunlar"].append(f"kayıt hatası yüksek: {hata_px}px")
    if supheli:
        kagit["sorunlar"].append(f"{supheli} soru belirsiz/çoklu")
    if not sablon.alan_bul("kitapcik") is None and not kagit["kitapcik"] \
            and sayfa_no == 1 and len(sablon.kitapcik_turleri) > 1:
        kagit["sorunlar"].append("kitapçık türü kodlanmamış")
    kagit["durum"] = "incelenecek" if kagit["sorunlar"] else "okundu"
    return kagit


# ------------------------------------------------------------------ parti okuma

def parti_oku(sablon, sablon_yolu, girdi_yollari, warp_dizin=None,
              ilerleme_cb=None):
    """Girdi dosyalarını okuyup kağıt kayıtları döndürür.

    Dönüş: [{"kaynak", "kaynak_sayfa", "png", "warp_png", "hata"?,
             ...kagit_birlestir alanları}]
    """
    import tempfile
    if not kullanilabilir():
        raise RuntimeError(optik_dogrula()["mesaj"])
    os.makedirs(CACHE_DIZIN, exist_ok=True)
    gecici = tempfile.mkdtemp(prefix="parti-", dir=CACHE_DIZIN)
    girdiler = girdileri_hazirla(girdi_yollari, gecici)
    sonuclar = []
    for i, g in enumerate(girdiler):
        if ilerleme_cb:
            ilerleme_cb(i, len(girdiler), g["kaynak"])
        warp_png = None
        if warp_dizin:
            os.makedirs(warp_dizin, exist_ok=True)
            warp_png = os.path.join(warp_dizin,
                                    f"warp{i + 1:04d}.png")
        try:
            yanit = isci_istek({"png": g["png"], "sablon": sablon_yolu,
                                "warp_png": warp_png})
            hukumler = hukum_ver(yanit["olcumler"], sablon,
                                 yanit["sayfa_no"])
            kagit = kagit_birlestir(hukumler, sablon, yanit["sayfa_no"],
                                    yanit.get("kayit"), yanit.get("qr"))
            # QR başka sınava işaret ediyorsa uyar (parti bağlamı esastır)
            import optik_sema as osm
            qr_bilgi = osm.qr_coz(yanit.get("qr") or "")
            if qr_bilgi and qr_bilgi["sinav_id"] != sablon.sinav_id:
                kagit["sorunlar"].append(
                    f"QR başka sınava ait: {qr_bilgi['sinav_id']}")
                kagit["durum"] = "incelenecek"
            kagit.update(kaynak=g["kaynak"],
                         kaynak_sayfa=g["kaynak_sayfa"],
                         png=g["png"], warp_png=warp_png,
                         olcumler=yanit["olcumler"])
        except Exception as e:  # noqa: BLE001 — kağıt bazında hata izole
            kagit = {"kaynak": g["kaynak"],
                     "kaynak_sayfa": g["kaynak_sayfa"], "png": g["png"],
                     "warp_png": None, "durum": "hatali",
                     "hata": f"{type(e).__name__}: {e}", "sorunlar": [],
                     "cevaplar": {}, "ogrenci_no": None, "ad_soyad": None,
                     "tc_kimlik": None, "kitapcik": None,
                     "sayfa_no": None, "qr": None, "kayit": None}
        sonuclar.append(kagit)
    if ilerleme_cb:
        ilerleme_cb(len(girdiler), len(girdiler), None)
    return sonuclar
