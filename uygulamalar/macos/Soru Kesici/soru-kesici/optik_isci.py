#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik okuma işçisi — YALNIZ .venv-ml (OpenCV) altında koşar.

optik_oku.py bu betiği alt süreç olarak başlatır ve satır-JSON protokolüyle
konuşur (duzen_isci.py deseni):
  başlangıç → {"ok": true, "cv2": "5.0.0"} | {"ok": false, "hata": "..."}
  stdin     ← {"id": N, "png": "/tarama.png", "sablon": "/sablon.json",
               "warp_png": "/onizleme.png" | null}
  stdout    → {"id": N, "ok": true, "sayfa_no": 1, "qr": "SKO1|..|1" | null,
               "kayit": {"yontem", "isaretci_sayisi", "yeniden_yansitma_px",
                         "yerel_kaymalar": {alan: [dx,dy]}},
               "olcumler": [{"alan","satir","sutun","doluluk","parlaklik",
                             "erozyon_dayanimi"}, ...]}
  stdin     ← {"cikis": true}

İşçi piksel→ölçüm katmanıdır; eşikleme/hüküm istemcidedir (optik_oku).
Tek atım kipleri: --probe (açılış doğrulaması), --qr-uret İÇERİK ÇIKTI.png.

Boru hattı: gri + aydınlatma normalizasyonu (morfolojik kapama arka planına
bölme) → ArUco (SUBPIX) ≥3 işaretçi → homografi; yedek: sayfa kontur dörtgeni
→ warp + 4 dönüş denemesi (işaretçi/köşe karesi karanlığı skoru); son çare:
kanonik boyuta ölçekleme. 200 dpi kanonik warp → alan başına ±ARAMA px
matchTemplate yerel arıtma (halka şablonu) → balon başına 0.75r disk ölçümü.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

DPI = 200.0
OLCEK = DPI / 72.0
ARAMA = 12          # yerel arıtma yarıçapı (px, kanonik uzay)
DISK_ORAN = 0.75    # ölçüm diski = balon yarıçapının bu katı


def _sablon_onbellek():
    cache = {}

    def yukle(yol):
        import optik_sema as osm
        st = os.stat(yol)
        anahtar = (yol, st.st_mtime_ns, st.st_size)
        if cache.get("anahtar") != anahtar:
            cache["anahtar"] = anahtar
            cache["sablon"] = osm.sablon_oku(yol)
        return cache["sablon"]
    return yukle


def _kanonik_boyut(sablon):
    return (int(round(sablon.sayfa_boyu[0] * OLCEK)),
            int(round(sablon.sayfa_boyu[1] * OLCEK)))


def _aydinlatma_duzelt(gri):
    """Arka plan kestirimi (morfolojik kapama) ile bölme → gölge/gradyan
    bastırılır; kağıt ~beyaza normalize olur."""
    import cv2
    import numpy as np
    yan = max(15, (min(gri.shape) // 24) | 1)
    cekirdek = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (yan, yan))
    arka = cv2.morphologyEx(gri, cv2.MORPH_CLOSE, cekirdek)
    arka = np.maximum(arka, 1)
    duz = np.clip(gri.astype(np.float32) / arka * 245.0, 0, 255)
    return duz.astype(np.uint8)


def _aruco_bul(gri):
    """{aruco_id: 4x2 köşe dizisi} — SUBPIX arıtmalı."""
    import cv2
    sozluk = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    parametre = cv2.aruco.DetectorParameters()
    parametre.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    dedektor = cv2.aruco.ArucoDetector(sozluk, parametre)
    koseler, idler, _ = dedektor.detectMarkers(gri)
    sonuc = {}
    if idler is None:
        return sonuc
    for kose, aid in zip(koseler, idler.flatten()):
        sonuc[int(aid)] = kose.reshape(4, 2)
    return sonuc


def _sayfa_sec(bulunan, sablon):
    """Bulunan işaretçi kimliklerinden sayfayı (çoğunlukla) seç."""
    oylar = {}
    for aid in bulunan:
        sayfa = aid // 4 + 1
        oylar[sayfa] = oylar.get(sayfa, 0) + 1
    gecerli = {sf.sayfa_no for sf in sablon.sayfalar}
    aday = [(n, s) for s, n in oylar.items() if s in gecerli]
    if not aday:
        return None
    return max(aday)[1]


def _isaretci_hedefleri(kayit):
    """Şablon işaretçi köşeleri (kanonik px, aruco köşe sırasıyla)."""
    hedef = {}
    for im in kayit.isaretciler:
        cx, cy = im.merkez[0] * OLCEK, im.merkez[1] * OLCEK
        y = im.boy / 2.0 * OLCEK
        hedef[im.id] = [(cx - y, cy - y), (cx + y, cy - y),
                        (cx + y, cy + y), (cx - y, cy + y)]
    return hedef


def _aruco_homografi(bulunan, kayit):
    """≥3 işaretçiden homografi + ortalama yeniden yansıtma hatası."""
    import cv2
    import numpy as np
    hedefler = _isaretci_hedefleri(kayit)
    kaynak, hedef = [], []
    for aid, koseler in bulunan.items():
        if aid in hedefler:
            kaynak.extend(koseler.tolist())
            hedef.extend(hedefler[aid])
    if len(kaynak) < 12:                      # 3 işaretçi × 4 köşe
        return None, None, 0
    kaynak = np.asarray(kaynak, dtype=np.float32)
    hedef = np.asarray(hedef, dtype=np.float32)
    H, maske = cv2.findHomography(kaynak, hedef, cv2.RANSAC, 4.0)
    if H is None:
        return None, None, 0
    yansit = cv2.perspectiveTransform(kaynak.reshape(-1, 1, 2), H)
    hata = float(np.mean(np.linalg.norm(
        yansit.reshape(-1, 2) - hedef, axis=1)))
    return H, hata, len(kaynak) // 4


def _kontur_dortgen(gri):
    """Sayfa sınırı dörtgeni (kağıt ↔ koyu zemin) | None."""
    import cv2
    import numpy as np
    kucuk = cv2.resize(gri, None, fx=0.25, fy=0.25)
    bulanik = cv2.GaussianBlur(kucuk, (5, 5), 0)
    _, esik = cv2.threshold(bulanik, 0, 255,
                            cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    konturlar, _ = cv2.findContours(esik, cv2.RETR_EXTERNAL,
                                    cv2.CHAIN_APPROX_SIMPLE)
    if not konturlar:
        return None
    en_buyuk = max(konturlar, key=cv2.contourArea)
    if cv2.contourArea(en_buyuk) < 0.35 * kucuk.shape[0] * kucuk.shape[1]:
        return None
    cevre = cv2.arcLength(en_buyuk, True)
    yaklasik = cv2.approxPolyDP(en_buyuk, 0.02 * cevre, True)
    if len(yaklasik) != 4:
        return None
    nokta = yaklasik.reshape(4, 2).astype(np.float32) * 4.0
    toplam = nokta.sum(axis=1)
    fark = np.diff(nokta, axis=1).flatten()
    return np.asarray([nokta[np.argmin(toplam)],   # sol-üst
                       nokta[np.argmin(fark)],     # sağ-üst
                       nokta[np.argmax(toplam)],   # sağ-alt
                       nokta[np.argmax(fark)]],    # sol-alt
                      dtype=np.float32)


def _donus_skoru(warp, kayit):
    """İşaretçi bordürleri + köşe karelerindeki karanlık (düşük = iyi)."""
    h, w = warp.shape
    toplam, adet = 0.0, 0
    for im in kayit.isaretciler:
        cx, cy = im.merkez[0] * OLCEK, im.merkez[1] * OLCEK
        hucre = im.boy / 6.0 * OLCEK
        for dx, dy in ((-2.5, -2.5), (2.5, -2.5), (2.5, 2.5), (-2.5, 2.5)):
            x = int(round(cx + dx * hucre))
            y = int(round(cy + dy * hucre))
            # bordürün hemen dışı beyaz olmalı; içi (bordür) siyah
            ix = int(round(cx + dx * hucre * 0.8))
            iy = int(round(cy + dy * hucre * 0.8))
            if 0 <= iy < h and 0 <= ix < w:
                toplam += float(warp[iy, ix])
                adet += 1
            if 0 <= y < h and 0 <= x < w:
                toplam -= 0.5 * float(warp[y, x])
                adet += 0
    for kare in kayit.kose_kareleri:
        x = int(round(kare["merkez"][0] * OLCEK))
        y = int(round(kare["merkez"][1] * OLCEK))
        if 0 <= y < h and 0 <= x < w:
            toplam += float(warp[y, x])
            adet += 1
    return toplam / max(adet, 1)


def _en_iyi_donus(warp, kayit):
    import cv2
    adaylar = [(warp, 0)]
    donen = warp
    for k in (cv2.ROTATE_90_CLOCKWISE, cv2.ROTATE_180,
              cv2.ROTATE_90_COUNTERCLOCKWISE):
        adaylar.append((cv2.rotate(warp, k), k + 1))
    puanli = [(_donus_skoru(g, kayit), i, g) for i, (g, _) in
              enumerate(adaylar)]
    puanli.sort(key=lambda t: t[0])
    return puanli[0][2]


def _halka_sablonu(alan):
    """Alan grid'inin sentetik halka şablonu (beyaz zemin, siyah çemberler)."""
    import cv2
    import numpy as np
    import optik_sema as osm
    merkezler = osm.baloncuk_merkezleri(alan)
    xler = [m[2] for m in merkezler]
    yler = [m[3] for m in merkezler]
    yari = alan.hucre.cap / 2.0 * OLCEK
    x0 = min(xler) * OLCEK - yari - 2
    y0 = min(yler) * OLCEK - yari - 2
    w = int(round(max(xler) * OLCEK + yari + 2 - x0))
    h = int(round(max(yler) * OLCEK + yari + 2 - y0))
    sab = np.full((h, w), 255, dtype=np.uint8)
    for _, _, x, y in merkezler:
        cv2.circle(sab, (int(round(x * OLCEK - x0)),
                         int(round(y * OLCEK - y0))),
                   int(round(yari)), 0, 2)
    return sab, x0, y0


def _blok_kaydir(warp, alan):
    """Alan bloğunun kanonik konuma göre (dx, dy) yerel kayması."""
    import cv2
    sab, x0, y0 = _halka_sablonu(alan)
    h, w = sab.shape
    ax0 = int(round(x0)) - ARAMA
    ay0 = int(round(y0)) - ARAMA
    ax1 = ax0 + w + 2 * ARAMA
    ay1 = ay0 + h + 2 * ARAMA
    if ax0 < 0 or ay0 < 0 or ax1 > warp.shape[1] or ay1 > warp.shape[0]:
        return 0.0, 0.0
    bolge = warp[ay0:ay1, ax0:ax1]
    sonuc = cv2.matchTemplate(bolge, sab, cv2.TM_CCOEFF_NORMED)
    _, deger, _, konum = cv2.minMaxLoc(sonuc)
    if deger < 0.12:
        return 0.0, 0.0
    return float(konum[0] - ARAMA), float(konum[1] - ARAMA)


def _disk_maskesi(yari):
    import cv2
    import numpy as np
    boy = 2 * yari + 1
    maske = np.zeros((boy, boy), dtype=np.uint8)
    cv2.circle(maske, (yari, yari), yari, 1, -1)
    return maske.astype(bool)


def _olc(warp, ink, alan, dx, dy, model=None):
    """Balon başına ölçümler; ink = ikili mürekkep maskesi (0/255).

    model verilirse (CNN, optik_model_egitim) her balona sinif +
    sinif_guven eklenir — istemci bunu iptal/dolu çapraz kontrolünde
    kullanır."""
    import cv2
    import numpy as np
    import optik_sema as osm
    yari = max(3, int(round(alan.hucre.cap / 2.0 * OLCEK * DISK_ORAN)))
    maske = _disk_maskesi(yari)
    alan_px = int(maske.sum())
    kirp_yari = max(6, int(round(alan.hucre.cap / 2.0 * OLCEK * 1.35)))
    h, w = warp.shape
    olcumler = []
    kirpmalar = []
    for r, c, x, y in osm.baloncuk_merkezleri(alan):
        px = int(round(x * OLCEK + dx))
        py = int(round(y * OLCEK + dy))
        x0, x1 = px - yari, px + yari + 1
        y0, y1 = py - yari, py + yari + 1
        if x0 < 0 or y0 < 0 or x1 > w or y1 > h:
            olcumler.append({"alan": alan.ad, "satir": r, "sutun": c,
                             "doluluk": 0.0, "parlaklik": 1.0,
                             "erozyon_dayanimi": 0.0})
            kirpmalar.append(None)
            continue
        gri_p = warp[y0:y1, x0:x1]
        ink_p = ink[y0:y1, x0:x1]
        ink_disk = (ink_p > 0) & maske
        doluluk = float(ink_disk.sum()) / alan_px
        parlaklik = float(gri_p[maske].mean()) / 255.0
        dayanim = 0.0
        ham = int(ink_disk.sum())
        if ham >= 8:
            erimis = cv2.erode(ink_disk.astype(np.uint8), None, iterations=2)
            dayanim = float(erimis.sum()) / ham
        olcumler.append({"alan": alan.ad, "satir": r, "sutun": c,
                         "doluluk": round(doluluk, 4),
                         "parlaklik": round(parlaklik, 4),
                         "erozyon_dayanimi": round(dayanim, 4)})
        if model is not None:
            kx0 = max(0, px - kirp_yari)
            ky0 = max(0, py - kirp_yari)
            kirp = warp[ky0:py + kirp_yari, kx0:px + kirp_yari]
            kirpmalar.append(cv2.resize(kirp, (64, 64)))
        else:
            kirpmalar.append(None)
    if model is not None:
        _cnn_uygula(model, olcumler, kirpmalar)
    return olcumler


def _cnn_uygula(model, olcumler, kirpmalar):
    """Toplu CNN sınıflandırması; her hata sessizce atlanır (çapraz
    kontrol katmanı zorunlu değildir)."""
    try:
        import numpy as np
        import torch
        import optik_model_egitim as ome
        gecerli = [(i, k) for i, k in enumerate(kirpmalar)
                   if k is not None]
        if not gecerli:
            return
        yigin = torch.from_numpy(
            np.stack([k for _, k in gecerli])).float()
        yigin = yigin.unsqueeze(1) / 255.0
        with torch.no_grad():
            cikti = torch.softmax(model(yigin), dim=1)
        for (i, _), olasilik in zip(gecerli, cikti):
            en_iyi = int(olasilik.argmax())
            olcumler[i]["sinif"] = ome.SINIFLAR[en_iyi]
            olcumler[i]["sinif_guven"] = round(float(olasilik[en_iyi]), 3)
    except Exception:  # noqa: BLE001
        pass


def _qr_oku(dedektor, gri, warp, sayfa_kaydi):
    """Önce warp'taki QR bölgesi (kayıt sonrası kolay), sonra tüm görüntü."""
    import cv2
    adaylar = []
    if sayfa_kaydi.qr:
        x0, y0, x1, y1 = sayfa_kaydi.qr["kutu"]
        pay = 8 * OLCEK
        ax0 = max(0, int((x0 - 8) * OLCEK))
        ay0 = max(0, int((y0 - 8) * OLCEK))
        ax1 = min(warp.shape[1], int(x1 * OLCEK + pay))
        ay1 = min(warp.shape[0], int(y1 * OLCEK + pay))
        if ax1 > ax0 and ay1 > ay0:
            bolge = warp[ay0:ay1, ax0:ax1]
            adaylar.append(cv2.resize(bolge, None, fx=3, fy=3,
                                      interpolation=cv2.INTER_CUBIC))
    adaylar.append(gri)
    for gorsel in adaylar:
        try:
            metin, _, _ = dedektor.detectAndDecode(gorsel)
        except cv2.error:
            continue
        if metin:
            return metin
    return None


def _kagit_isle(istek, sablon_yukle, dedektor, model=None):
    import cv2
    import numpy as np

    gorsel = cv2.imread(istek["png"], cv2.IMREAD_COLOR)
    if gorsel is None:
        raise RuntimeError(f"görüntü okunamadı: {istek['png']}")
    gri = cv2.cvtColor(gorsel, cv2.COLOR_BGR2GRAY)
    sablon = sablon_yukle(istek["sablon"])
    W, H = _kanonik_boyut(sablon)

    duz = _aydinlatma_duzelt(gri)
    bulunan = _aruco_bul(duz)
    if not bulunan:
        bulunan = _aruco_bul(gri)
    sayfa_no = _sayfa_sec(bulunan, sablon)
    ipucu = istek.get("sayfa_ipucu")
    if sayfa_no is None and ipucu:
        sayfa_no = int(ipucu)
    kayit_bilgi = {"yontem": None, "isaretci_sayisi": len(bulunan),
                   "yeniden_yansitma_px": None, "yerel_kaymalar": {}}

    warp = None
    if sayfa_no is not None:
        sayfa_kaydi = next((s for s in sablon.sayfalar
                            if s.sayfa_no == sayfa_no), None)
    else:
        sayfa_kaydi = sablon.sayfalar[0] if sablon.sayfalar else None
    if sayfa_kaydi is None:
        raise RuntimeError("şablonda uygun sayfa yok")

    Hm, hata, isaretci = (None, None, 0)
    if bulunan and sayfa_no is not None:
        Hm, hata, isaretci = _aruco_homografi(bulunan, sayfa_kaydi)
    if Hm is not None:
        warp = cv2.warpPerspective(duz, Hm, (W, H),
                                   flags=cv2.INTER_LINEAR,
                                   borderValue=255)
        kayit_bilgi.update(yontem="aruco", isaretci_sayisi=isaretci,
                           yeniden_yansitma_px=round(hata, 2))
    else:
        dortgen = _kontur_dortgen(duz)
        if dortgen is not None:
            hedef = np.asarray([[0, 0], [W, 0], [W, H], [0, H]],
                               dtype=np.float32)
            Hm = cv2.getPerspectiveTransform(dortgen, hedef)
            warp = cv2.warpPerspective(duz, Hm, (W, H),
                                       flags=cv2.INTER_LINEAR,
                                       borderValue=255)
            kayit_bilgi["yontem"] = "kontur"
        else:
            warp = cv2.resize(duz, (W, H), interpolation=cv2.INTER_AREA)
            kayit_bilgi["yontem"] = "olcek"
        warp = _en_iyi_donus(warp, sayfa_kaydi)
        # warp sonrası işaretçileri yeniden dene → sayfa/kayıt doğrulanır
        tekrar = _aruco_bul(warp)
        if tekrar:
            yeni_sayfa = _sayfa_sec(tekrar, sablon)
            if yeni_sayfa is not None and yeni_sayfa != sayfa_no:
                sayfa_no = yeni_sayfa
                sayfa_kaydi = next(s for s in sablon.sayfalar
                                   if s.sayfa_no == sayfa_no)
            H2, hata2, isaretci2 = _aruco_homografi(tekrar, sayfa_kaydi)
            if H2 is not None:
                warp = cv2.warpPerspective(warp, H2, (W, H),
                                           flags=cv2.INTER_LINEAR,
                                           borderValue=255)
                kayit_bilgi.update(yontem=kayit_bilgi["yontem"] + "+aruco",
                                   isaretci_sayisi=isaretci2,
                                   yeniden_yansitma_px=round(hata2, 2))

    qr = _qr_oku(dedektor, gri, warp, sayfa_kaydi)
    if sayfa_no is None and qr:
        import optik_sema as osm
        cozum = osm.qr_coz(qr)
        if cozum:
            sayfa_no = cozum["sayfa_no"]
            sayfa_kaydi = next((s for s in sablon.sayfalar
                                if s.sayfa_no == sayfa_no), sayfa_kaydi)

    # ölçüm: ikili mürekkep maskesi (Otsu; aydınlatma zaten düzeltildi)
    _, ink = cv2.threshold(warp, 0, 255,
                           cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    olcumler = []
    for alan in sayfa_kaydi.alanlar:
        dx, dy = _blok_kaydir(warp, alan)
        if dx or dy:
            kayit_bilgi["yerel_kaymalar"][alan.ad] = [dx, dy]
        olcumler.extend(_olc(warp, ink, alan, dx, dy, model))

    if istek.get("warp_png"):
        try:
            cv2.imwrite(istek["warp_png"],
                        cv2.resize(warp, (W // 2, H // 2)))
        except cv2.error:
            pass

    return {"ok": True,
            "sayfa_no": sayfa_no if sayfa_no is not None
            else sayfa_kaydi.sayfa_no,
            "qr": qr, "kayit": kayit_bilgi, "olcumler": olcumler}


def _qr_uret(icerik, hedef):
    import cv2
    import numpy as np
    enc = cv2.QRCodeEncoder.create()
    kod = enc.encode(icerik)
    kod = np.pad(kod, 4, constant_values=255)      # sessiz bölge
    olcek = max(1, 320 // max(kod.shape))
    buyuk = cv2.resize(kod, None, fx=olcek, fy=olcek,
                       interpolation=cv2.INTER_NEAREST)
    if not cv2.imwrite(hedef, buyuk):
        raise RuntimeError(f"QR yazılamadı: {hedef}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--probe", action="store_true")
    p.add_argument("--qr-uret", nargs=2, metavar=("ICERIK", "CIKTI"))
    args = p.parse_args()

    if args.qr_uret:
        _qr_uret(args.qr_uret[0], args.qr_uret[1])
        return 0

    # Protokol kanalını kütüphane gürültüsünden ayır (duzen_isci deseni).
    proto = os.fdopen(os.dup(1), "w", buffering=1)
    os.dup2(2, 1)

    def yaz(obj):
        proto.write(json.dumps(obj, ensure_ascii=False) + "\n")

    try:
        import cv2
        dedektor = cv2.QRCodeDetector()
        surum = cv2.__version__
    except Exception as e:  # noqa: BLE001
        yaz({"ok": False, "hata": f"{type(e).__name__}: {e}"})
        return 1
    # CNN çapraz kontrol modeli isteğe bağlıdır (torch hafif profilde yok)
    model = None
    try:
        import optik_model_egitim as ome
        model = ome.model_yukle()
    except Exception:  # noqa: BLE001
        model = None
    yaz({"ok": True, "cv2": surum, "cnn": bool(model)})
    if args.probe:
        return 0

    sablon_yukle = _sablon_onbellek()
    for satir in sys.stdin:
        satir = satir.strip()
        if not satir:
            continue
        try:
            istek = json.loads(satir)
        except ValueError:
            continue
        if istek.get("cikis"):
            break
        no = istek.get("id")
        try:
            yanit = _kagit_isle(istek, sablon_yukle, dedektor, model)
            yanit["id"] = no
            yaz(yanit)
        except Exception as e:  # noqa: BLE001
            yaz({"id": no, "hata": f"{type(e).__name__}: {e}"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
