#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici GUI — etkileşimli kutu editörü.

KutuModeli: web arayüzündeki DURUM sözleşmesinin süreç-içi eşleniği.
Kutular her yerde LAYOUT koordinatındadır (PDF: punto, raster: OCR pikseli);
ekran koordinatı = layout × olcek (sayfa.gorsel() ikinci dönüşü) × zoom.
Düzenlenen sayfalar `duzenlendi` kümesinde izlenir ve kesime
kutu_atama={sayfa_idx: kutular} olarak geçirilir (web ile aynı yol).

KutuEditor: tk.Canvas üzerinde taşı / köşeden boyutlandır / çiz / sil /
birleştir / sıfırla + zoom/pan + geri al-yinele. Ağır işler (sayfa render,
tespit) editörde YAPILMAZ; ana pencere IsYurutucu worker'ında hazırlayıp
`gorsel_hazir()` ile teslim eder.
"""

import copy
import threading

import tkinter as tk

from PIL import Image, ImageTk

import soru_kes as sk
from gui_yardimci import RENKLER

MIN_KUTU = 8.0        # layout biriminde en küçük kenar (web paritesi)
TUTAMAC_PX = 5        # köşe tutamacı yarı-kenarı (ekran pikseli)
ZOOM_MIN, ZOOM_MAKS = 0.25, 4.0
ZEMIN_PAY = 240       # görünür bölge çevresinde önden render edilen pay (px)


def _aday_ayikla(aday):
    """SoruKutu/sözlük adayını (kutu, meta) çiftine indirger.
    devam_aday (sütun başı yetimi) → None: bağımsız soru değildir."""
    ham = aday.to_dict() if hasattr(aday, "to_dict") else dict(aday)
    if ham.get("devam_aday"):
        return None
    kutu = tuple(float(v) for v in ham["kutu"])
    try:
        guven = max(0.0, min(1.0, float(
            ham.get("kalibre_guven", ham.get("guven", 0.0)))))
    except (TypeError, ValueError):
        guven = 0.0
    durum = ham.get("inceleme_durumu")
    if durum not in ("otomatik", "incele", "reddedildi"):
        durum = "otomatik"
    meta = {"guven": guven, "inceleme_durumu": durum,
            "numara": ham.get("numara"),
            "kanitlar": list(ham.get("kanitlar") or []),
            "uyarilar": list(ham.get("uyarilar") or [])}
    return kutu, meta


def _yeni_kutu_meta():
    return {"guven": 0.0, "inceleme_durumu": "incele", "numara": None,
            "kanitlar": ["kullanici_ekledi"], "uyarilar": []}


def _kutu_ayni(a, b, tol=0.01):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


class KutuModeli:
    """Sayfa-başına kutu listesi + meta; web DURUM sözleşmesiyle birebir."""

    def __init__(self):
        self._kilit = threading.Lock()
        self.temizle()

    def temizle(self):
        self.sayfalar = []
        self.fmt = None
        self.sutun_xler = [0.0]
        self.analiz_var = False
        self.kutu_onbellek = {}     # idx -> [(x0,y0,x1,y1), ...] layout
        self.kutu_meta = {}         # idx -> [dict, ...] (paralel)
        self.duzenlendi = set()

    # ------------------------------------------------------------ kurulum
    def belge_ata(self, sayfalar, fmt, sutun_xler, analizler=None):
        """belge_analiz_et çıktısından doldurur; analiz yoksa tembel yol."""
        with self._kilit:
            self.temizle()
            self.sayfalar = sayfalar
            self.fmt = fmt
            self.sutun_xler = list(sutun_xler or [0.0])
            self.analiz_var = analizler is not None
            for idx, analiz in enumerate(analizler or []):
                kutular, metalar = [], []
                for aday in getattr(analiz, "adaylar", ()) or ():
                    cift = _aday_ayikla(aday)
                    if cift is not None:
                        kutular.append(cift[0])
                        metalar.append(cift[1])
                self.kutu_onbellek[idx] = kutular
                self.kutu_meta[idx] = metalar

    # ------------------------------------------------------------ erişim
    def kutular(self, idx):
        """Sayfanın kutuları (tembel). DİKKAT: önbellekte yoksa tespit
        çalışır (OCR/fitz) — ilk erişim worker thread'inden yapılmalı."""
        with self._kilit:
            if idx in self.kutu_onbellek:
                return list(self.kutu_onbellek[idx])
        ham = sk.sorulari_tespit(self.sayfalar[idx], self.fmt)
        kutular = [tuple(float(v) for v in k) for k in ham]
        varsayilan = ({"guven": 1.0, "inceleme_durumu": "otomatik"}
                      if self.analiz_var else
                      {"guven": 0.0, "inceleme_durumu": "incele"})
        with self._kilit:
            self.kutu_onbellek.setdefault(idx, kutular)
            self.kutu_meta.setdefault(idx, [
                dict(varsayilan, numara=None, kanitlar=[], uyarilar=[])
                for _ in kutular])
            return list(self.kutu_onbellek[idx])

    def metalar(self, idx):
        with self._kilit:
            return [dict(m) for m in self.kutu_meta.get(idx, [])]

    def kutu_atama(self):
        """Kesim/özet için: düzenlenen sayfaların görünür planı (web
        _kutu_atama paritesi). Hiç düzenleme yoksa None."""
        with self._kilit:
            return {i: list(self.kutu_onbellek[i]) for i in self.duzenlendi
                    if i in self.kutu_onbellek} or None

    def toplam_soru(self):
        with self._kilit:
            return sum(len(k) for k in self.kutu_onbellek.values())

    # ------------------------------------------------------------ düzenleme
    def kutulari_degistir(self, idx, ogeler):
        """Sayfanın kutu planını bütünüyle değiştirir.
        ogeler: [(kutu, meta|None, degisti), ...] — meta None = yeni kutu.
        Clamp + min 8×8 eleme + (sütun, y) sıralaması uygulanır; değişen
        kutunun metasına 'kullanici_duzeltmesi' eklenir, reddedilmiş kutu
        düzenlenince 'incele'ye terfi eder (web paritesi)."""
        sayfa = self.sayfalar[idx]
        G, Y = float(sayfa.genislik), float(sayfa.yukseklik)
        kayitlar = []
        for kutu, meta, degisti in ogeler:
            x0 = max(0.0, min(float(kutu[0]), float(kutu[2])))
            y0 = max(0.0, min(float(kutu[1]), float(kutu[3])))
            x1 = min(G, max(float(kutu[0]), float(kutu[2])))
            y1 = min(Y, max(float(kutu[1]), float(kutu[3])))
            if x1 - x0 < MIN_KUTU or y1 - y0 < MIN_KUTU:
                continue            # minik parça: sessizce elenir
            if meta is None:
                meta = _yeni_kutu_meta()
            elif degisti:
                meta = dict(meta)
                kanit = list(meta.get("kanitlar") or [])
                if "kullanici_duzeltmesi" not in kanit:
                    kanit.append("kullanici_duzeltmesi")
                meta["kanitlar"] = kanit
                if meta.get("inceleme_durumu") == "reddedildi":
                    meta["inceleme_durumu"] = "incele"
            kayitlar.append(((x0, y0, x1, y1), meta))
        # (sütun, y) sıralaması ZORUNLU: soru numaralandırması buna dayanır.
        sx = self.sutun_xler or [0.0]
        kayitlar.sort(key=lambda r: (sk.sutun_indeksi(r[0][0], sx), r[0][1]))
        with self._kilit:
            eski = self.kutu_onbellek.get(idx, [])
            yeni = [r[0] for r in kayitlar]
            self.kutu_onbellek[idx] = yeni
            self.kutu_meta[idx] = [r[1] for r in kayitlar]
            if (len(yeni) != len(eski)
                    or any(not _kutu_ayni(a, b) for a, b in zip(yeni, eski))):
                self.duzenlendi.add(idx)
            return list(yeni)

    def sifirla(self, idx):
        """Sayfa planını otomatik tespite döndürür (önbellek düşer)."""
        with self._kilit:
            self.kutu_onbellek.pop(idx, None)
            self.kutu_meta.pop(idx, None)
            self.duzenlendi.discard(idx)

    # ------------------------------------------------------------ anlık görüntü
    def anlik(self, idx):
        """Geri al yığını için sayfanın derin kopyası."""
        with self._kilit:
            return (copy.deepcopy(self.kutu_onbellek.get(idx)),
                    copy.deepcopy(self.kutu_meta.get(idx)),
                    idx in self.duzenlendi)

    def anlik_yukle(self, idx, anlik):
        kutular, metalar, duzenli = anlik
        with self._kilit:
            if kutular is None:
                self.kutu_onbellek.pop(idx, None)
                self.kutu_meta.pop(idx, None)
            else:
                self.kutu_onbellek[idx] = copy.deepcopy(kutular)
                self.kutu_meta[idx] = copy.deepcopy(metalar)
            (self.duzenlendi.add if duzenli
             else self.duzenlendi.discard)(idx)


class GeriAlYigini:
    """Belge-genel geri al/yinele: (sayfa_idx, önce, sonra) kayıtları."""

    def __init__(self, sinir=100):
        self.sinir = sinir
        self._geri = []
        self._ileri = []

    def push(self, idx, once, sonra):
        self._geri.append((idx, once, sonra))
        del self._geri[:-self.sinir]
        self._ileri.clear()

    def geri_al(self):
        if not self._geri:
            return None
        kayit = self._geri.pop()
        self._ileri.append(kayit)
        return kayit[0], kayit[1]       # (sayfa_idx, uygulanacak anlık)

    def yinele(self):
        if not self._ileri:
            return None
        kayit = self._ileri.pop()
        self._geri.append(kayit)
        return kayit[0], kayit[2]

    def temizle(self):
        self._geri.clear()
        self._ileri.clear()

    @property
    def geri_var(self):
        return bool(self._geri)

    @property
    def ileri_var(self):
        return bool(self._ileri)


class KutuEditor:
    """Kaydırmalı/zoomlu tuval + kutu düzenleme etkileşimleri.

    Ana pencere sözleşmesi:
      - gorsel_iste(idx): sayfa görüntüsünü worker'da hazırlatıp
        gorsel_hazir(idx, pil, olcek) çağırmalı (kutular da materialize).
      - on_degisiklik(idx): her model commit'i sonrası (özet tazeleme).
      - on_secim(secim): seçim değişince (küçük resim + durum çubuğu).
      - on_durum(metin): kısa durum iletileri.
    """

    def __init__(self, parent, model, gorsel_iste, on_degisiklik,
                 on_secim, on_durum=None):
        self.model = model
        self.gorsel_iste = gorsel_iste
        self.on_degisiklik = on_degisiklik
        self.on_secim = on_secim
        self.on_durum = on_durum or (lambda m: None)
        self.undo = GeriAlYigini()

        self.sayfa_idx = None
        self.zoom = 1.0
        self._pil = None            # geçerli sayfanın taban görüntüsü
        self._olcek = 1.0           # layout → taban görüntü pikseli
        self._foto = None           # ImageTk referansı (GC engeli)
        self.secim = []             # model listesine indeksler
        self.mod = "sec"            # "sec" | "ciz"
        self._surukleme = None
        self._zemin_isi = None
        self._zoom_isi = None
        self._space_basili = False

        cerceve = tk.Frame(parent)
        cerceve.rowconfigure(0, weight=1)
        cerceve.columnconfigure(0, weight=1)
        self.cerceve = cerceve
        self.tuval = tk.Canvas(cerceve, bg="#8e8e93", highlightthickness=0)
        self.tuval.grid(row=0, column=0, sticky="nsew")
        self._vsb = tk.Scrollbar(cerceve, orient="vertical",
                                 command=self._yview)
        self._vsb.grid(row=0, column=1, sticky="ns")
        self._hsb = tk.Scrollbar(cerceve, orient="horizontal",
                                 command=self._xview)
        self._hsb.grid(row=1, column=0, sticky="ew")
        self.tuval.configure(yscrollcommand=self._vsb.set,
                             xscrollcommand=self._hsb.set)

        t = self.tuval
        t.bind("<ButtonPress-1>", self._bas)
        t.bind("<B1-Motion>", self._hareket)
        t.bind("<ButtonRelease-1>", self._birak)
        t.bind("<ButtonPress-2>", lambda e: self._pan_basla(e))
        t.bind("<B2-Motion>", lambda e: self._pan_surukle(e))
        t.bind("<ButtonRelease-2>", lambda e: self._zemin_planla())
        t.bind("<MouseWheel>", self._teker)
        t.bind("<Shift-MouseWheel>", self._teker_yatay)
        t.bind("<Command-MouseWheel>", self._teker_zoom)
        t.bind("<KeyPress-space>", self._space_bas)
        t.bind("<KeyRelease-space>", self._space_birak)
        t.bind("<Configure>", lambda e: self._zemin_planla())
        self._bos_mesaj()

    # ------------------------------------------------------------ sayfa akışı
    def _bos_mesaj(self, metin="Bir dosya açın (⌘O), ardından 'Ön İzle'."):
        self.tuval.delete("all")
        self.tuval.create_text(24, 24, anchor="nw", fill="#f2f2f7",
                               font=("TkDefaultFont", 13), text=metin,
                               tags="ipucu")

    def temizle(self):
        self.sayfa_idx = None
        self._pil = None
        self._foto = None
        self.secim = []
        self.undo.temizle()
        self._bos_mesaj()

    def sayfa_goster(self, idx, sec_kutu=None):
        """Sayfayı (worker'dan görüntü isteyerek) gösterir; sec_kutu
        verilirse yüklenince o kutu seçilir."""
        self.sayfa_idx = idx
        self.secim = []
        self._bekleyen_secim = sec_kutu
        self._pil = None
        self.tuval.delete("all")
        self.tuval.create_text(24, 24, anchor="nw", fill="#f2f2f7",
                               text="Sayfa hazırlanıyor…", tags="ipucu")
        self._secim_bildir()
        self.gorsel_iste(idx)

    def gorsel_hazir(self, idx, pil, olcek):
        """Worker'ın hazırladığı sayfa görüntüsü (ana thread'de çağrılır)."""
        if idx != self.sayfa_idx:
            return                  # bayat sonuç: kullanıcı sayfa değiştirdi
        self._pil = pil
        self._olcek = float(olcek) or 1.0
        self._sigdir(ciz=False)
        if getattr(self, "_bekleyen_secim", None) is not None:
            ki = self._bekleyen_secim
            if 0 <= ki < len(self.model.kutular(idx)):
                self.secim = [ki]
            self._bekleyen_secim = None
        self._hepsini_ciz()
        self._secim_bildir()

    # ------------------------------------------------------------ koordinat
    @property
    def _k(self):
        """layout → canvas çarpanı."""
        return self._olcek * self.zoom

    def _l2c(self, kutu):
        k = self._k
        return [v * k for v in kutu]

    def _c2l(self, kutu):
        k = self._k
        return [v / k for v in kutu]

    # ------------------------------------------------------------ çizim
    def _hepsini_ciz(self):
        self.tuval.delete("all")
        if self._pil is None:
            return
        W = int(self._pil.width * self.zoom)
        H = int(self._pil.height * self.zoom)
        self.tuval.configure(scrollregion=(0, 0, W, H))
        self._zemin_ciz()
        self._kutulari_ciz()

    def _zemin_planla(self, gecikme=60):
        if self._zemin_isi is not None:
            self.tuval.after_cancel(self._zemin_isi)
        self._zemin_isi = self.tuval.after(gecikme, self._zemin_ciz)

    def _zemin_ciz(self):
        """Yalnız görünür bölgeyi (+ pay) render eder — 300 DPI sayfada
        4x zoom'un tamamını çözmek yerine pencere kadarını çözer."""
        self._zemin_isi = None
        if self._pil is None:
            return
        z = self.zoom
        W, H = int(self._pil.width * z), int(self._pil.height * z)
        gw = max(self.tuval.winfo_width(), 1)
        gh = max(self.tuval.winfo_height(), 1)
        vx0 = max(0, int(self.tuval.canvasx(0)) - ZEMIN_PAY)
        vy0 = max(0, int(self.tuval.canvasy(0)) - ZEMIN_PAY)
        vx1 = min(W, int(self.tuval.canvasx(gw)) + ZEMIN_PAY)
        vy1 = min(H, int(self.tuval.canvasy(gh)) + ZEMIN_PAY)
        if vx1 <= vx0 or vy1 <= vy0:
            return
        kx0, ky0 = int(vx0 / z), int(vy0 / z)
        kx1 = min(self._pil.width, int(vx1 / z) + 1)
        ky1 = min(self._pil.height, int(vy1 / z) + 1)
        parca = self._pil.crop((kx0, ky0, kx1, ky1))
        hedef = (max(1, int((kx1 - kx0) * z)), max(1, int((ky1 - ky0) * z)))
        if hedef != parca.size:
            parca = parca.resize(hedef, Image.LANCZOS)
        self._foto = ImageTk.PhotoImage(parca)
        self.tuval.delete("zemin")
        self.tuval.create_image(int(kx0 * z), int(ky0 * z), anchor="nw",
                                image=self._foto, tags="zemin")
        self.tuval.tag_lower("zemin")

    def _kutulari_ciz(self):
        t = self.tuval
        t.delete("kutu")
        if self.sayfa_idx is None or self._pil is None:
            return
        kutular = self.model.kutular(self.sayfa_idx)
        metalar = self.model.metalar(self.sayfa_idx)
        rozet_goster = self.zoom >= 0.5
        for i, kutu in enumerate(kutular):
            meta = metalar[i] if i < len(metalar) else {}
            durum = meta.get("inceleme_durumu", "otomatik")
            secili = i in self.secim
            renk = RENKLER["secili"] if secili else RENKLER.get(
                durum, RENKLER["otomatik"])
            x0, y0, x1, y1 = self._l2c(kutu)
            t.create_rectangle(x0, y0, x1, y1, outline=renk,
                               width=3 if secili else 2,
                               tags=("kutu", f"kutu_{i}"))
            # sol-üst sıra numarası etiketi
            t.create_rectangle(x0, y0, x0 + 22, y0 + 16, fill=renk,
                               outline=renk, tags=("kutu", f"kutu_{i}"))
            t.create_text(x0 + 11, y0 + 8, text=str(i + 1), fill="white",
                          font=("TkDefaultFont", 10, "bold"),
                          tags=("kutu", f"kutu_{i}"))
            # sağ-üst güven rozeti (yalnız dikkat gerektirenlerde)
            if rozet_goster and durum != "otomatik":
                ad = "İncele" if durum == "incele" else "Reddedildi"
                metin = f"{ad} %{meta.get('guven', 0) * 100:.0f}"
                rw = 9 + 6 * len(metin)
                t.create_rectangle(x1 - rw, y0, x1, y0 + 16, fill=renk,
                                   outline=renk, tags=("kutu", f"kutu_{i}"))
                t.create_text(x1 - rw / 2, y0 + 8, text=metin, fill="white",
                              font=("TkDefaultFont", 9),
                              tags=("kutu", f"kutu_{i}"))
            if secili:
                for cx, cy, kose in ((x0, y0, "nw"), (x1, y0, "ne"),
                                     (x0, y1, "sw"), (x1, y1, "se")):
                    t.create_rectangle(cx - TUTAMAC_PX, cy - TUTAMAC_PX,
                                       cx + TUTAMAC_PX, cy + TUTAMAC_PX,
                                       fill="white", outline=renk, width=2,
                                       tags=("kutu", f"tut_{i}_{kose}"))
        t.tag_raise("kutu")

    # ------------------------------------------------------------ zoom / pan
    def _sigdir(self, ciz=True):
        if self._pil is None:
            return
        gw = max(self.tuval.winfo_width(), 100)
        gh = max(self.tuval.winfo_height(), 100)
        self.zoom = max(ZOOM_MIN, min(
            ZOOM_MAKS, min(gw / self._pil.width, gh / self._pil.height)))
        if ciz:
            self._hepsini_ciz()

    def zoom_ayarla(self, carpan=None, mutlak=None, merkez=None):
        """carpan: mevcut zoom'a çarpan; mutlak: doğrudan değer;
        merkez: (ekran_x, ekran_y) — o nokta sabit kalır."""
        if self._pil is None:
            return
        eski = self.zoom
        yeni = mutlak if mutlak is not None else eski * (carpan or 1.0)
        yeni = max(ZOOM_MIN, min(ZOOM_MAKS, yeni))
        if abs(yeni - eski) < 1e-6:
            return
        ex, ey = merkez if merkez else (self.tuval.winfo_width() / 2,
                                        self.tuval.winfo_height() / 2)
        # imleç altındaki nokta sabit kalsın
        cx, cy = self.tuval.canvasx(ex), self.tuval.canvasy(ey)
        self.zoom = yeni
        oran = yeni / eski
        W = max(int(self._pil.width * yeni), 1)
        H = max(int(self._pil.height * yeni), 1)
        self._hepsini_ciz()
        self.tuval.xview_moveto(max(0.0, (cx * oran - ex) / W))
        self.tuval.yview_moveto(max(0.0, (cy * oran - ey) / H))
        self._zemin_planla(20)
        self.on_durum(f"Yakınlaştırma %{self.zoom * 100:.0f}")

    def sigdir(self):
        self._sigdir(ciz=True)

    def _yview(self, *a):
        self.tuval.yview(*a)
        self._zemin_planla()

    def _xview(self, *a):
        self.tuval.xview(*a)
        self._zemin_planla()

    def _teker(self, olay):
        # aqua'da event.delta küçük ham değerdir; /120 YAPMA
        self.tuval.yview_scroll(-olay.delta, "units")
        self._zemin_planla()
        return "break"

    def _teker_yatay(self, olay):
        self.tuval.xview_scroll(-olay.delta, "units")
        self._zemin_planla()
        return "break"

    def _teker_zoom(self, olay):
        carpan = 1.0 + max(-8, min(8, olay.delta)) * 0.03
        self.zoom_ayarla(carpan=carpan, merkez=(olay.x, olay.y))
        return "break"

    def _space_bas(self, olay):
        self._space_basili = True

    def _space_birak(self, olay):
        self._space_basili = False

    def _pan_basla(self, olay):
        self.tuval.scan_mark(olay.x, olay.y)

    def _pan_surukle(self, olay):
        self.tuval.scan_dragto(olay.x, olay.y, gain=1)
        self._zemin_planla()

    # ------------------------------------------------------------ etkileşim
    def _vurulan(self, cx, cy):
        """(tur, kutu_idx, kose) — tutamaç > kutu gövdesi > boşluk."""
        for oge in reversed(self.tuval.find_overlapping(
                cx - 1, cy - 1, cx + 1, cy + 1)):
            for tag in self.tuval.gettags(oge):
                if tag.startswith("tut_"):
                    _, i, kose = tag.split("_")
                    return "tutamac", int(i), kose
                if tag.startswith("kutu_"):
                    return "kutu", int(tag.split("_")[1]), None
        return "bos", None, None

    def _bas(self, olay):
        self.tuval.focus_set()
        if self._pil is None or self.sayfa_idx is None:
            return
        cx, cy = self.tuval.canvasx(olay.x), self.tuval.canvasy(olay.y)
        if self._space_basili:
            self.tuval.scan_mark(olay.x, olay.y)
            self._surukleme = {"tur": "pan"}
            return
        if self.mod == "ciz":
            self._surukleme = {"tur": "ciz", "bas": (cx, cy),
                               "oge": self.tuval.create_rectangle(
                                   cx, cy, cx, cy, dash=(4, 3), width=2,
                                   outline=RENKLER["secili"], tags="lastik")}
            return
        tur, i, kose = self._vurulan(cx, cy)
        shift = bool(olay.state & 0x0001)
        if tur == "tutamac":
            kutu = self._l2c(self.model.kutular(self.sayfa_idx)[i])
            sabit = {"nw": (kutu[2], kutu[3]), "ne": (kutu[0], kutu[3]),
                     "sw": (kutu[2], kutu[1]), "se": (kutu[0], kutu[1])}[kose]
            self._surukleme = {"tur": "boyut", "i": i, "sabit": sabit,
                               "oldu": False}
        elif tur == "kutu":
            if shift:
                if i in self.secim:
                    self.secim.remove(i)
                else:
                    self.secim.append(i)
                self._kutulari_ciz()
                self._secim_bildir()
                return
            if i not in self.secim:
                self.secim = [i]
                self._kutulari_ciz()
                self._secim_bildir()
            kutu = self._l2c(self.model.kutular(self.sayfa_idx)[i])
            self._surukleme = {"tur": "tasi", "i": i, "bas": (cx, cy),
                               "kutu": kutu, "oldu": False}
        else:
            if self.secim:
                self.secim = []
                self._kutulari_ciz()
                self._secim_bildir()
            self._surukleme = None

    def _hareket(self, olay):
        s = self._surukleme
        if not s:
            return
        cx, cy = self.tuval.canvasx(olay.x), self.tuval.canvasy(olay.y)
        if s["tur"] == "pan":
            self.tuval.scan_dragto(olay.x, olay.y, gain=1)
            self._zemin_planla()
            return
        if s["tur"] == "ciz":
            bx, by = s["bas"]
            self.tuval.coords(s["oge"], bx, by, cx, cy)
            return
        if s["tur"] == "boyut":
            s["oldu"] = True
            sx, sy = s["sabit"]
            self._gecici_kutu_ciz(s["i"], (min(sx, cx), min(sy, cy),
                                           max(sx, cx), max(sy, cy)))
        elif s["tur"] == "tasi":
            bx, by = s["bas"]
            dx, dy = cx - bx, cy - by
            if abs(dx) + abs(dy) > 2:
                s["oldu"] = True
            k = s["kutu"]
            self._gecici_kutu_ciz(s["i"], (k[0] + dx, k[1] + dy,
                                           k[2] + dx, k[3] + dy))

    def _gecici_kutu_ciz(self, i, kutu):
        """Sürükleme sırasında yalnız çerçeveyi taşı (60fps; model bekler)."""
        s = self._surukleme
        s["son"] = kutu
        if "gecici" not in s:
            for oge in self.tuval.find_withtag(f"kutu_{i}"):
                self.tuval.delete(oge)
            for oge in self.tuval.find_withtag("kutu"):
                for tag in self.tuval.gettags(oge):
                    if tag.startswith(f"tut_{i}_"):
                        self.tuval.delete(oge)
            s["gecici"] = self.tuval.create_rectangle(
                *kutu, outline=RENKLER["secili"], width=3, tags="gecici")
        else:
            self.tuval.coords(s["gecici"], *kutu)

    def _birak(self, olay):
        s, self._surukleme = self._surukleme, None
        if not s:
            return
        if s["tur"] == "pan":
            self._zemin_planla()
            return
        idx = self.sayfa_idx
        if s["tur"] == "ciz":
            self.tuval.delete("lastik")
            self.mod_ayarla("sec")
            bx, by = s["bas"]
            cx = self.tuval.canvasx(olay.x)
            cy = self.tuval.canvasy(olay.y)
            kutu = self._c2l((min(bx, cx), min(by, cy),
                              max(bx, cx), max(by, cy)))
            if (kutu[2] - kutu[0] < MIN_KUTU
                    or kutu[3] - kutu[1] < MIN_KUTU):
                self.on_durum("Kutu çok küçük — eklenmedi.")
                return
            ogeler = self._ogeler() + [(tuple(kutu), None, True)]
            self._commit(ogeler, sec_geometri=[tuple(kutu)])
            return
        if s["tur"] in ("boyut", "tasi"):
            if not s.get("oldu") or "son" not in s:
                self._kutulari_ciz()   # tıklama: geçiciyi geri sar
                return
            yeni = tuple(self._c2l(s["son"]))
            ogeler = []
            for i, (kutu, meta, deg) in enumerate(self._ogeler()):
                if i == s["i"]:
                    ogeler.append((yeni, meta, True))
                else:
                    ogeler.append((kutu, meta, deg))
            self._commit(ogeler, sec_geometri=[yeni])

    # ------------------------------------------------------------ eylemler
    def mod_ayarla(self, mod):
        self.mod = mod
        self.tuval.configure(cursor="crosshair" if mod == "ciz" else "")
        if hasattr(self, "on_mod"):
            self.on_mod(mod)

    def secilileri_sil(self):
        if self.sayfa_idx is None or not self.secim:
            return
        ogeler = [o for i, o in enumerate(self._ogeler())
                  if i not in self.secim]
        self._commit(ogeler)

    def secilileri_birlestir(self):
        if self.sayfa_idx is None or len(self.secim) < 2:
            return
        ogeler = self._ogeler()
        parcalar = [ogeler[i] for i in sorted(self.secim)
                    if i < len(ogeler)]
        if len(parcalar) < 2:
            return
        zarf = (min(p[0][0] for p in parcalar),
                min(p[0][1] for p in parcalar),
                max(p[0][2] for p in parcalar),
                max(p[0][3] for p in parcalar))
        # meta: en yüksek güvenli üyeden devralınır
        meta = dict(max(parcalar, key=lambda p: (p[1] or {}).get(
            "guven", 0))[1] or _yeni_kutu_meta())
        kalan = [o for i, o in enumerate(ogeler) if i not in self.secim]
        kalan.append((zarf, meta, True))
        self._commit(kalan, sec_geometri=[zarf])

    def sayfayi_sifirla(self):
        if self.sayfa_idx is None:
            return
        idx = self.sayfa_idx
        once = self.model.anlik(idx)
        self.model.sifirla(idx)
        self.model.kutular(idx)     # yeniden tespit (önbellekten; ucuz)
        sonra = self.model.anlik(idx)
        self.undo.push(idx, once, sonra)
        self.secim = []
        self._kutulari_ciz()
        self._secim_bildir()
        self.on_degisiklik(idx)

    def tumunu_sec(self):
        if self.sayfa_idx is None:
            return
        self.secim = list(range(len(self.model.kutular(self.sayfa_idx))))
        self._kutulari_ciz()
        self._secim_bildir()

    def secimi_birak(self):
        if self.secim:
            self.secim = []
            self._kutulari_ciz()
            self._secim_bildir()

    def geri_al(self):
        kayit = self.undo.geri_al()
        self._anlik_uygula(kayit)

    def yinele(self):
        kayit = self.undo.yinele()
        self._anlik_uygula(kayit)

    def _anlik_uygula(self, kayit):
        if not kayit:
            return
        idx, anlik = kayit
        self.model.anlik_yukle(idx, anlik)
        self.secim = []
        if idx == self.sayfa_idx:
            self._kutulari_ciz()
            self._secim_bildir()
        else:
            # geri alınan değişiklik başka sayfada: oraya atla
            self.on_sayfa_atla(idx) if hasattr(self, "on_sayfa_atla") \
                else self.sayfa_goster(idx)
        self.on_degisiklik(idx)

    # ------------------------------------------------------------ iç yardımcılar
    def _ogeler(self):
        """Geçerli sayfanın (kutu, meta, degisti=False) listesi."""
        idx = self.sayfa_idx
        kutular = self.model.kutular(idx)
        metalar = self.model.metalar(idx)
        return [(kutular[i],
                 metalar[i] if i < len(metalar) else None, False)
                for i in range(len(kutular))]

    def _commit(self, ogeler, sec_geometri=None):
        idx = self.sayfa_idx
        once = self.model.anlik(idx)
        yeni = self.model.kutulari_degistir(idx, ogeler)
        sonra = self.model.anlik(idx)
        if once[:2] != sonra[:2]:
            self.undo.push(idx, once, sonra)
        # seçim: sıralama değişmiş olabilir — geometriyle yeniden bul
        self.secim = []
        for geo in sec_geometri or []:
            for i, kutu in enumerate(yeni):
                if _kutu_ayni(kutu, geo, tol=0.5):
                    self.secim.append(i)
                    break
        self._kutulari_ciz()
        self._secim_bildir()
        self.on_degisiklik(idx)

    def _secim_bildir(self):
        self.on_secim(list(self.secim))
