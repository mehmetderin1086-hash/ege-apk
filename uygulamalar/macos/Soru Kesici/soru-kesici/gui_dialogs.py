#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici GUI — diyaloglar (Faz 2).

SinavPdfDialog: sinav_pdf.sinav_pdf_uret parametre formu.
IncelemeDialog: katı kalite kapısı bekleyen sayfaları — risk nedenleri +
çekirdek inceleme bindirmesi (inceleme_paketi_uret çıktısı) + sayfa kararı.
TopluIslemDialog: çok dosyalı kuyruk işleme (CLI --coklu'nun GUI karşılığı).
"""

import os

import tkinter as tk
from tkinter import ttk, filedialog

from PIL import Image, ImageTk

ONIZLEME_EN = 520      # inceleme bindirmesi önizleme genişliği (px)


class _Dialog(tk.Toplevel):
    """Ortak modal iskelet: transient + grab + Esc ile kapanış."""

    def __init__(self, parent, baslik):
        super().__init__(parent)
        self.title(baslik)
        self.transient(parent)
        self.resizable(False, False)
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()


class CevapDialog(_Dialog):
    """Tek sorunun cevabını elle düzeltme: A-E / ∅ (cevabı sil) /
    ↺ (otomatik eşlemeye dön). on_secim(cevap|''|None): None=geri al."""

    def __init__(self, parent, etiket, mevcut, on_secim):
        super().__init__(parent, f"Cevap düzelt — {etiket}")
        self.on_secim = on_secim
        g = ttk.Frame(self, padding=12)
        g.pack(fill="both", expand=True)
        ttk.Label(g, text=f"Mevcut cevap: {mevcut or '—'}").grid(
            row=0, column=0, columnspan=7, pady=(0, 8))
        for i, harf in enumerate("ABCDE"):
            ttk.Button(g, text=harf, width=3,
                       command=lambda h=harf: self._sec(h)).grid(
                row=1, column=i, padx=2)
        ttk.Button(g, text="∅", width=3,
                   command=lambda: self._sec("")).grid(row=1, column=5,
                                                       padx=(10, 2))
        ttk.Button(g, text="↺", width=3,
                   command=lambda: self._sec(None)).grid(row=1, column=6,
                                                         padx=2)
        ttk.Label(g, text="∅ cevabı sil · ↺ otomatik eşlemeye dön",
                  foreground="#888").grid(row=2, column=0, columnspan=7,
                                          pady=(8, 0))

    def _sec(self, cevap):
        self.destroy()
        self.on_secim(cevap)


class SinavPdfDialog(_Dialog):
    """Sınav kağıdı ayar formu; Tamam → on_tamam(ayarlar, rastgele, tohum)."""

    def __init__(self, parent, varsayilan_baslik, on_tamam):
        super().__init__(parent, "Sınav PDF'i Üret")
        self.on_tamam = on_tamam
        g = ttk.Frame(self, padding=12)
        g.pack(fill="both", expand=True)

        self.baslik = tk.StringVar(value=varsayilan_baslik)
        self.kurum = tk.StringVar()
        self.puan = tk.StringVar()
        self.rastgele = tk.StringVar()
        self.tohum = tk.StringVar()
        self.sutun = tk.IntVar(value=2)
        self.kitapcik = tk.IntVar(value=1)

        satirlar = [("Sınav başlığı:", self.baslik, 28),
                    ("Kurum / okul:", self.kurum, 28),
                    ("Toplam puan (boş=yok):", self.puan, 8),
                    ("Rastgele N soru (boş=hepsi):", self.rastgele, 8),
                    ("Tohum (tekrarlanabilirlik):", self.tohum, 8)]
        for i, (etiket, degisken, en) in enumerate(satirlar):
            ttk.Label(g, text=etiket).grid(row=i, column=0, sticky="w",
                                           pady=2)
            ttk.Entry(g, textvariable=degisken, width=en).grid(
                row=i, column=1, sticky="w", padx=6, pady=2)

        ttk.Label(g, text="Sütun sayısı:").grid(row=5, column=0, sticky="w",
                                                pady=2)
        ttk.Spinbox(g, from_=1, to=4, width=4,
                    textvariable=self.sutun).grid(row=5, column=1,
                                                  sticky="w", padx=6)
        ttk.Label(g, text="Kitapçık (A/B/…):").grid(row=6, column=0,
                                                    sticky="w", pady=2)
        ttk.Spinbox(g, from_=1, to=4, width=4,
                    textvariable=self.kitapcik).grid(row=6, column=1,
                                                     sticky="w", padx=6)

        kutu = ttk.LabelFrame(g, text="Üst bilgi alanları", padding=6)
        kutu.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(8, 2))
        self.alanlar = {}
        for i, (ad, etiket, sec) in enumerate([
                ("ad_soyad", "Ad Soyad", True), ("tarih", "Tarih", True),
                ("sinif", "Sınıf", True), ("no", "Numara", True),
                ("cevap_anahtari", "Cevap anahtarı sayfası", True),
                ("yeniden_numarala", "Soruları yeniden numarala", True),
                ("optik_form", "Optik cevap kâğıdı da üret", False)]):
            v = tk.BooleanVar(value=sec)
            self.alanlar[ad] = v
            ttk.Checkbutton(kutu, text=etiket, variable=v).grid(
                row=i // 2, column=i % 2, sticky="w", padx=4)

        dugme = ttk.Frame(g)
        dugme.grid(row=8, column=0, columnspan=2, pady=(10, 0))
        ttk.Button(dugme, text="Vazgeç",
                   command=self.destroy).pack(side="left", padx=4)
        ttk.Button(dugme, text="PDF Üret…",
                   command=self._tamam).pack(side="left", padx=4)

    def _tamam(self):
        def _sayi(v):
            v = v.get().strip()
            try:
                return int(v) if v else None
            except ValueError:
                return None
        ayarlar = {"baslik": self.baslik.get().strip(),
                   "kurum": self.kurum.get().strip(),
                   "sutun": max(1, min(4, self.sutun.get())),
                   "kitapcik": max(1, min(4, self.kitapcik.get())),
                   "toplam_puan": _sayi(self.puan),
                   "tohum": _sayi(self.tohum)}
        for ad, v in self.alanlar.items():
            ayarlar[ad] = v.get()
        rastgele, tohum = _sayi(self.rastgele), _sayi(self.tohum)
        self.destroy()
        self.on_tamam(ayarlar, rastgele, tohum)


class IncelemeDialog(_Dialog):
    """Katı kalite kapısı: bekleyen sayfalar için karar ekranı.
    bekleyen: kalite_kapisi bekleyen_sayfalar listesi (sayfa 1-tabanlı).
    gorseller: {sayfa_no: bindirme_png_yolu}. on_tamam(kararlar):
    kararlar={sayfa_idx0: "onayli"|"soru_yok"} — hepsi kararlaştırılınca."""

    def __init__(self, parent, bekleyen, gorseller, on_tamam):
        super().__init__(parent, "Kalite Kapısı — İnceleme Gerekli")
        self.resizable(True, True)
        self.bekleyen = list(bekleyen)
        self.gorseller = dict(gorseller)
        self.on_tamam = on_tamam
        self.kararlar = {}
        self._tk_img = None

        govde = ttk.Frame(self, padding=10)
        govde.pack(fill="both", expand=True)
        govde.columnconfigure(1, weight=1)
        govde.rowconfigure(1, weight=1)

        ttk.Label(govde, wraplength=760, justify="left", text=(
            f"Katı kalite kapısı: {len(self.bekleyen)} sayfa inceleme "
            "bekliyor. Her sayfayı bindirme görselinden denetleyin; sayfa "
            "doğruysa onaylayın, soru içermiyorsa işaretleyin. Kutuları "
            "düzeltmek için pencereyi kapatıp editörde düzenleyin "
            "(düzeltilen sayfa kapıdan otomatik geçer).")).grid(
            row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))

        sol = ttk.Frame(govde)
        sol.grid(row=1, column=0, sticky="nsw", padx=(0, 10))
        self.liste = tk.Listbox(sol, width=34, height=16,
                                exportselection=False)
        self.liste.pack(side="left", fill="y")
        vsb = ttk.Scrollbar(sol, orient="vertical",
                            command=self.liste.yview)
        vsb.pack(side="right", fill="y")
        self.liste.configure(yscrollcommand=vsb.set)
        self.liste.bind("<<ListboxSelect>>", self._sayfa_sec)

        sag = ttk.Frame(govde)
        sag.grid(row=1, column=1, sticky="nsew")
        sag.rowconfigure(0, weight=1)
        sag.columnconfigure(0, weight=1)
        self.gorsel_etiket = ttk.Label(sag, text="Soldan sayfa seçin",
                                       anchor="center")
        self.gorsel_etiket.grid(row=0, column=0, sticky="nsew")
        self.neden_etiket = ttk.Label(sag, text="", wraplength=520,
                                      justify="left", foreground="#B26B00")
        self.neden_etiket.grid(row=1, column=0, sticky="ew", pady=(6, 0))

        dugme = ttk.Frame(govde)
        dugme.grid(row=2, column=0, columnspan=2, pady=(10, 0))
        self.onay_btn = ttk.Button(dugme, text="✓ Sayfa doğru (onayla)",
                                   command=lambda: self._karar("onayli"),
                                   state="disabled")
        self.onay_btn.pack(side="left", padx=4)
        self.yok_btn = ttk.Button(dugme, text="∅ Bu sayfada soru yok",
                                  command=lambda: self._karar("soru_yok"),
                                  state="disabled")
        self.yok_btn.pack(side="left", padx=4)
        ttk.Button(dugme, text="Vazgeç",
                   command=self.destroy).pack(side="left", padx=12)
        self.devam_btn = ttk.Button(dugme, text="Devam Et →",
                                    command=self._devam, state="disabled")
        self.devam_btn.pack(side="left", padx=4)

        self._liste_tazele()
        if self.bekleyen:
            self.liste.selection_set(0)
            self._sayfa_sec()

    def _liste_tazele(self):
        secili = self.liste.curselection()
        self.liste.delete(0, "end")
        for b in self.bekleyen:
            idx0 = b["sayfa"] - 1
            karar = self.kararlar.get(idx0)
            isaret = {"onayli": "✓ ", "soru_yok": "∅ "}.get(karar, "• ")
            self.liste.insert("end", f"{isaret}Sayfa {b['sayfa']}")
        if secili:
            self.liste.selection_set(secili[0])
        self.devam_btn.config(
            state="normal" if len(self.kararlar) == len(self.bekleyen)
            else "disabled")

    def _secili(self):
        s = self.liste.curselection()
        return self.bekleyen[s[0]] if s else None

    def _sayfa_sec(self, olay=None):
        b = self._secili()
        if not b:
            return
        self.onay_btn.config(state="normal")
        self.yok_btn.config(state="normal")
        nedenler = ", ".join(b.get("risk_nedenleri") or []) or "belirsiz"
        self.neden_etiket.config(text=f"Risk nedenleri: {nedenler}")
        yol = self.gorseller.get(b["sayfa"])
        if yol and os.path.exists(yol):
            img = Image.open(yol)
            oran = ONIZLEME_EN / img.width
            img = img.resize((ONIZLEME_EN, max(1, int(img.height * oran))))
            self._tk_img = ImageTk.PhotoImage(img)
            self.gorsel_etiket.config(image=self._tk_img, text="")
        else:
            self._tk_img = None
            self.gorsel_etiket.config(image="",
                                      text="(bindirme görseli yok)")

    def _karar(self, karar):
        b = self._secili()
        if not b:
            return
        self.kararlar[b["sayfa"] - 1] = karar
        self._liste_tazele()

    def _devam(self):
        kararlar = dict(self.kararlar)
        self.destroy()
        self.on_tamam(kararlar)


class TopluIslemDialog(_Dialog):
    """Çok dosyalı işleme: her girdi kendi Arşiv.zip'ine kesilir
    (CLI --coklu davranışı). Başlat → on_baslat(dosyalar, cikti_klasoru)."""

    def __init__(self, parent, on_baslat):
        super().__init__(parent, "Toplu İşlem")
        self.on_baslat = on_baslat
        g = ttk.Frame(self, padding=12)
        g.pack(fill="both", expand=True)
        g.columnconfigure(0, weight=1)

        ttk.Label(g, text="Her dosya kendi Arşiv.zip'ine kesilir "
                          "(tüm sorular, geçerli DPI/ayarlarla).").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))

        self.liste = tk.Listbox(g, width=56, height=10,
                                selectmode="extended")
        self.liste.grid(row=1, column=0, sticky="nsew")
        vsb = ttk.Scrollbar(g, orient="vertical", command=self.liste.yview)
        vsb.grid(row=1, column=1, sticky="ns")
        self.liste.configure(yscrollcommand=vsb.set)

        dugme = ttk.Frame(g)
        dugme.grid(row=2, column=0, columnspan=2, sticky="ew", pady=6)
        ttk.Button(dugme, text="Dosya Ekle…",
                   command=self._ekle).pack(side="left")
        ttk.Button(dugme, text="Çıkar",
                   command=self._cikar).pack(side="left", padx=4)

        klasor_c = ttk.Frame(g)
        klasor_c.grid(row=3, column=0, columnspan=2, sticky="ew")
        klasor_c.columnconfigure(1, weight=1)
        ttk.Label(klasor_c, text="Çıktı klasörü:").grid(row=0, column=0,
                                                        sticky="w")
        self.klasor = tk.StringVar()
        ttk.Label(klasor_c, textvariable=self.klasor,
                  foreground="#555").grid(row=0, column=1, sticky="w",
                                          padx=6)
        ttk.Button(klasor_c, text="Seç…",
                   command=self._klasor_sec).grid(row=0, column=2)

        alt = ttk.Frame(g)
        alt.grid(row=4, column=0, columnspan=2, pady=(10, 0))
        ttk.Button(alt, text="Vazgeç",
                   command=self.destroy).pack(side="left", padx=4)
        self.baslat_btn = ttk.Button(alt, text="Başlat",
                                     command=self._baslat,
                                     state="disabled")
        self.baslat_btn.pack(side="left", padx=4)

    def _durum(self):
        hazir = self.liste.size() > 0 and bool(self.klasor.get())
        self.baslat_btn.config(state="normal" if hazir else "disabled")

    def _ekle(self):
        yollar = filedialog.askopenfilenames(
            parent=self, title="Dosya ekle",
            filetypes=[("Test dosyaları", "*.pdf *.png *.jpg *.jpeg "
                        "*.tif *.tiff *.bmp *.webp"), ("Tümü", "*.*")])
        mevcut = set(self.liste.get(0, "end"))
        for y in yollar:
            if y not in mevcut:
                self.liste.insert("end", y)
        if yollar and not self.klasor.get():
            self.klasor.set(os.path.dirname(yollar[0]))
        self._durum()

    def _cikar(self):
        for i in reversed(self.liste.curselection()):
            self.liste.delete(i)
        self._durum()

    def _klasor_sec(self):
        yol = filedialog.askdirectory(parent=self, title="Çıktı klasörü")
        if yol:
            self.klasor.set(yol)
        self._durum()

    def _baslat(self):
        dosyalar = list(self.liste.get(0, "end"))
        klasor = self.klasor.get()
        self.destroy()
        self.on_baslat(dosyalar, klasor)


class OptikFormDialog(_Dialog):
    """Optik cevap kâğıdı üretimi (optik_form.form_uret parametre formu).

    Okuma/puanlama web arayüzündedir (🔘 Optik sekmesi); masaüstünden
    yalnız basılabilir form + şablon üretilir. Tamam →
    on_tamam(tanim, on_ayar)."""

    def __init__(self, parent, on_tamam):
        super().__init__(parent, "Optik Form Üret")
        self.on_tamam = on_tamam
        import optik_form
        g = ttk.Frame(self, padding=12)
        g.pack(fill="both", expand=True)

        self.on_ayar = tk.StringVar()
        self.ad = tk.StringVar()
        self.kurum = tk.StringVar()
        self.dersler = tk.StringVar(value="")
        self.kitapcik = tk.IntVar(value=2)
        self.no_hane = tk.IntVar(value=5)
        self.tc = tk.BooleanVar(value=False)
        self.ad_soyad = tk.BooleanVar(value=True)
        self.bolen = tk.IntVar(value=0)

        ttk.Label(g, text="Hazır tip:").grid(row=0, column=0, sticky="w",
                                             pady=2)
        secenekler = [""] + sorted(optik_form.ON_AYARLAR)
        ttk.Combobox(g, textvariable=self.on_ayar, values=secenekler,
                     state="readonly", width=24).grid(
            row=0, column=1, sticky="w", padx=6, pady=2)
        for i, (etiket, degisken) in enumerate(
                [("Sınav adı:", self.ad), ("Kurum:", self.kurum)],
                start=1):
            ttk.Label(g, text=etiket).grid(row=i, column=0, sticky="w",
                                           pady=2)
            ttk.Entry(g, textvariable=degisken, width=27).grid(
                row=i, column=1, sticky="w", padx=6, pady=2)
        ttk.Label(g, text="Dersler (Ad:soru:şık,\nvirgülle; boş=hazır tip):",
                  justify="left").grid(row=3, column=0, sticky="w", pady=2)
        ttk.Entry(g, textvariable=self.dersler, width=27).grid(
            row=3, column=1, sticky="w", padx=6, pady=2)

        satir = ttk.Frame(g)
        satir.grid(row=4, column=0, columnspan=2, sticky="w", pady=(6, 2))
        ttk.Label(satir, text="Kitapçık:").pack(side="left")
        ttk.Spinbox(satir, from_=1, to=4, width=3,
                    textvariable=self.kitapcik).pack(side="left", padx=(2, 10))
        ttk.Label(satir, text="Öğr. no hane:").pack(side="left")
        ttk.Spinbox(satir, from_=0, to=10, width=3,
                    textvariable=self.no_hane).pack(side="left", padx=(2, 10))
        ttk.Label(satir, text="Yanlış böleni:").pack(side="left")
        ttk.Combobox(satir, textvariable=self.bolen, values=(0, 3, 4),
                     state="readonly", width=3).pack(side="left", padx=2)
        kutu = ttk.Frame(g)
        kutu.grid(row=5, column=0, columnspan=2, sticky="w")
        ttk.Checkbutton(kutu, text="Ad-Soyad grid",
                        variable=self.ad_soyad).pack(side="left", padx=4)
        ttk.Checkbutton(kutu, text="T.C. Kimlik",
                        variable=self.tc).pack(side="left", padx=4)

        dugme = ttk.Frame(g)
        dugme.grid(row=6, column=0, columnspan=2, pady=(10, 0))
        ttk.Button(dugme, text="Vazgeç",
                   command=self.destroy).pack(side="left", padx=4)
        ttk.Button(dugme, text="Form Üret…",
                   command=self._tamam).pack(side="left", padx=4)
        ttk.Label(g, text="Okuma/puanlama: web arayüzü → 🔘 Optik",
                  foreground="#888").grid(row=7, column=0, columnspan=2,
                                          pady=(8, 0))

    def _tamam(self):
        dersler = []
        for parca in self.dersler.get().split(","):
            parca = parca.strip()
            if not parca:
                continue
            alanlar = parca.rsplit(":", 2)
            if len(alanlar) != 3:
                continue
            try:
                dersler.append({"ad": alanlar[0].strip(),
                                "soru": int(alanlar[1]),
                                "secenek": int(alanlar[2])})
            except ValueError:
                continue
        tanim = {"ad": self.ad.get().strip() or None,
                 "kurum": self.kurum.get().strip() or None,
                 "kitapcik": max(1, min(4, self.kitapcik.get())),
                 "ogrenci_no_hane": max(0, min(10, self.no_hane.get())),
                 "tc": self.tc.get(), "ad_soyad": self.ad_soyad.get(),
                 "yanlis_boler": self.bolen.get()}
        if dersler:
            tanim["dersler"] = dersler
        tanim = {k: v for k, v in tanim.items() if v is not None}
        on_ayar = self.on_ayar.get() or None
        self.destroy()
        self.on_tamam(tanim, on_ayar)
