#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — grafik arayüz (Tkinter).

PDF / JPG / PNG test dosyalarını açıp tespit edilen soru kutularını
etkileşimli düzenleyen (taşı / boyutlandır / çiz / sil / birleştir /
geri al), test-soru ağacından seçim yapan ve seçileni Arşiv.zip'e kesen
masaüstü uygulaması. Çekirdek mantık soru_kes.py'den, web arayüzüyle aynı
public API üzerinden kullanılır; çekirdeğe dokunulmaz.

Mimari: tüm soru_kes çağrıları tek IsYurutucu worker thread'inde çalışır
(fitz + raster LRU eşzamanlılığı), sonuçlar queue + after(100) ile ana
thread'e taşınır; ImageTk üretimi yalnız ana thread'dedir.

Çalıştırma:
    .venv/bin/python soru_kes_gui.py
"""

import os
import queue
import subprocess
import tempfile

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

from PIL import ImageTk

import soru_kes as sk
from gui_yardimci import IsYurutucu
from gui_kutu_editor import KutuModeli, KutuEditor
from gui_agac import SoruAgaci
from gui_dialogs import (SinavPdfDialog, IncelemeDialog, TopluIslemDialog,
                         OptikFormDialog)

KUCUK_RESIM_EN = 240    # seçili soru önizlemesinin genişliği (px)


class SoruKesiciGUI:
    def __init__(self, root):
        self.root = root
        root.title("Soru Kesici")
        root.geometry("1280x860")
        root.minsize(980, 660)
        # Tk 8.5'in "aqua" ttk teması modern macOS'ta HİÇ çizilmiyor
        # (pencere boş kalıyor). Tk 8.6+ / 9'da aqua doğru çalışır ve
        # yerli görünür; yalnız eski Tk'de "clam"a düş.
        if tk.TkVersion < 8.6:
            try:
                stil = ttk.Style()
                if stil.theme_use() == "aqua":
                    stil.theme_use("clam")
            except tk.TclError:
                pass

        # durum
        self.girdiler = []
        self.sayfalar = []
        self.acik_docs = []
        self.sutun_xler = None
        self.fmt = None
        self.testler = []
        self.parca_meta = []
        self.kimlikler = []
        self.cevaplar = None
        self.onizleme_sayfa = 0
        self.mesgul = False
        self.secili_adet = 0
        self.sayfa_kararlari = {}      # idx0 -> "onayli" | "soru_yok"
        self.cevap_duzeltmeler = {}    # kimlik -> 'A'..'E' | '' (elle cevap)
        self._bekleyen_eylem = None    # kalite kapısı sonrası tekrar
        self._tk_kucuk = None          # küçük resim ImageTk referansı
        self._kucuk_jeton = None
        self._kucuk_isi = None
        self._ozet_isi = None

        self.kuyruk = queue.Queue()    # worker → UI mesajları
        self.yurutucu = IsYurutucu(self.kuyruk)
        self.model = KutuModeli()

        self._arayuzu_kur()
        self._menu_kur()
        self._kisayollar_kur()
        self.root.after(100, self._kuyruk_yokla)

    # ------------------------------------------------------------ arayüz
    def _arayuzu_kur(self):
        self.root.rowconfigure(1, weight=1)
        self.root.columnconfigure(0, weight=1)

        # r0: araç çubuğu
        arac = ttk.Frame(self.root, padding=(8, 6))
        arac.grid(row=0, column=0, sticky="ew")
        ttk.Button(arac, text="Aç…",
                   command=self.dosya_sec).pack(side="left")
        self.dosya_etiket = ttk.Label(arac, text="Henüz dosya seçilmedi",
                                      foreground="#555")
        self.dosya_etiket.pack(side="left", padx=8)

        ttk.Separator(arac, orient="vertical").pack(side="left", fill="y",
                                                    padx=6, pady=2)
        self.ciz_btn = ttk.Button(arac, text="✏ Kutu Çiz",
                                  command=self._ciz_degistir,
                                  state="disabled")
        self.ciz_btn.pack(side="left", padx=1)
        self.sil_btn = ttk.Button(arac, text="✂ Sil",
                                  command=lambda: self.editor.secilileri_sil(),
                                  state="disabled")
        self.sil_btn.pack(side="left", padx=1)
        self.birlestir_btn = ttk.Button(
            arac, text="⊞ Birleştir",
            command=lambda: self.editor.secilileri_birlestir(),
            state="disabled")
        self.birlestir_btn.pack(side="left", padx=1)
        self.sifirla_btn = ttk.Button(
            arac, text="↺ Sayfayı Sıfırla", command=self._sayfa_sifirla,
            state="disabled")
        self.sifirla_btn.pack(side="left", padx=1)

        ttk.Separator(arac, orient="vertical").pack(side="left", fill="y",
                                                    padx=6, pady=2)
        self.geri_al_btn = ttk.Button(arac, text="↶", width=3,
                                      command=self._geri_al,
                                      state="disabled")
        self.geri_al_btn.pack(side="left", padx=1)
        self.yinele_btn = ttk.Button(arac, text="↷", width=3,
                                     command=self._yinele, state="disabled")
        self.yinele_btn.pack(side="left", padx=1)

        ttk.Separator(arac, orient="vertical").pack(side="left", fill="y",
                                                    padx=6, pady=2)
        ttk.Button(arac, text="−", width=3,
                   command=lambda: self._zoom(1 / 1.25)).pack(side="left")
        ttk.Button(arac, text="+", width=3,
                   command=lambda: self._zoom(1.25)).pack(side="left")
        ttk.Button(arac, text="Sığdır",
                   command=lambda: self._editor_hazirsa(
                       self.editor.sigdir)).pack(side="left", padx=(1, 0))

        # r1: sol ağaç · orta editör · sağ panel
        bolme = ttk.Panedwindow(self.root, orient="horizontal")
        bolme.grid(row=1, column=0, sticky="nsew")

        self.agac = SoruAgaci(bolme, on_secim=self._agac_secim,
                              on_soru_git=self._soruya_git)
        self.agac.on_cevap_duzelt = self._cevap_duzelt_ac
        bolme.add(self.agac.cerceve, weight=0)

        self.editor = KutuEditor(
            bolme, self.model, gorsel_iste=self._gorsel_iste,
            on_degisiklik=self._kutular_degisti,
            on_secim=self._editor_secim, on_durum=self._durum_yaz)
        self.editor.on_sayfa_atla = self._sayfaya_git
        self.editor.on_mod = self._mod_degisti
        bolme.add(self.editor.cerceve, weight=1)

        sag = ttk.Frame(bolme, padding=(8, 6))
        bolme.add(sag, weight=0)

        ayar = ttk.LabelFrame(sag, text="Ayarlar", padding=8)
        ayar.pack(side="top", fill="x")
        ttk.Label(ayar, text="Çözünürlük (DPI):").grid(row=0, column=0,
                                                       sticky="w")
        self.dpi_degeri = tk.IntVar(value=300)
        ttk.Spinbox(ayar, from_=120, to=600, increment=30, width=6,
                    textvariable=self.dpi_degeri).grid(row=0, column=1,
                                                       padx=6, pady=2)
        self.klasor_de = tk.BooleanVar(value=False)
        ttk.Checkbutton(ayar, text="PNG klasörü de üret",
                        variable=self.klasor_de).grid(row=1, column=0,
                                                      columnspan=2,
                                                      sticky="w")
        self.numara_gizle = tk.BooleanVar(value=False)
        ttk.Checkbutton(ayar, text="Soru numarasını gizle",
                        variable=self.numara_gizle).grid(row=2, column=0,
                                                         columnspan=2,
                                                         sticky="w")
        self.cevap_bandi = tk.BooleanVar(value=False)
        ttk.Checkbutton(ayar, text="Cevabı altına bas (bant)",
                        variable=self.cevap_bandi).grid(row=3, column=0,
                                                        columnspan=2,
                                                        sticky="w")
        self.cozum_ilistir = tk.BooleanVar(value=False)
        ttk.Checkbutton(ayar, text="Çözümü sorunun altına iliştir",
                        variable=self.cozum_ilistir).grid(row=4, column=0,
                                                          columnspan=2,
                                                          sticky="w")
        ttk.Label(ayar, text="Kalite kapısı:").grid(row=5, column=0,
                                                    sticky="w")
        self.kalite = tk.StringVar(value="legacy")
        ttk.Combobox(ayar, textvariable=self.kalite, width=8,
                     state="readonly",
                     values=list(sk.KALITE_MODLARI)).grid(row=5, column=1,
                                                          padx=6, pady=2)

        self.tespit_etiket = ttk.Label(sag, text="", foreground="#186a3b",
                                       wraplength=220, justify="left")
        self.tespit_etiket.pack(side="top", fill="x", pady=(8, 4))

        eylem = ttk.Frame(sag)
        eylem.pack(side="top", fill="x", pady=4)
        self.onizle_btn = ttk.Button(eylem, text="Ön İzle",
                                     command=self.onizle, state="disabled")
        self.onizle_btn.pack(side="top", fill="x", pady=2)
        self.kes_btn = ttk.Button(eylem, text="Kes ve Kaydet →",
                                  command=self.kes, state="disabled")
        self.kes_btn.pack(side="top", fill="x", pady=2)

        gez = ttk.Frame(sag)
        gez.pack(side="top", fill="x", pady=(10, 0))
        self.geri_btn = ttk.Button(gez, text="◀", width=3,
                                   command=lambda: self._sayfa_degis(-1),
                                   state="disabled")
        self.geri_btn.pack(side="left")
        self.sayfa_etiket = ttk.Label(gez, text="–", anchor="center")
        self.sayfa_etiket.pack(side="left", expand=True)
        self.ileri_btn = ttk.Button(gez, text="▶", width=3,
                                    command=lambda: self._sayfa_degis(1),
                                    state="disabled")
        self.ileri_btn.pack(side="right")

        kucuk = ttk.LabelFrame(sag, text="Seçili Soru", padding=4)
        kucuk.pack(side="top", fill="x", pady=(10, 0))
        self.kucuk_etiket = ttk.Label(kucuk, text="—", anchor="center",
                                      foreground="#888")
        self.kucuk_etiket.pack(fill="both", expand=True)

        # r3: durum çubuğu
        alt = ttk.Frame(self.root)
        alt.grid(row=3, column=0, sticky="ew")
        self.durum = ttk.Label(alt, text="Hazır.", anchor="w",
                               relief="sunken", padding=(8, 3))
        self.durum.pack(side="left", fill="x", expand=True)
        self.bilgi_etiket = ttk.Label(alt, text="", padding=(8, 3))
        self.bilgi_etiket.pack(side="left")
        self.durdur_btn = ttk.Button(alt, text="Durdur", width=6,
                                     command=self._durdur, state="disabled")
        self.durdur_btn.pack(side="right", padx=(2, 6), pady=2)
        self.ilerleme = ttk.Progressbar(alt, mode="determinate", length=180)
        self.ilerleme.pack(side="right", padx=4, pady=3)

    def _menu_kur(self):
        cubugu = tk.Menu(self.root)
        dosya = tk.Menu(cubugu, tearoff=0)
        dosya.add_command(label="Aç…", accelerator="⌘O",
                          command=self.dosya_sec)
        dosya.add_command(label="Kes ve Kaydet…", accelerator="⌘S",
                          command=self.kes)
        dosya.add_separator()
        dosya.add_command(label="Toplu İşlem…", command=self.toplu_islem)
        cubugu.add_cascade(label="Dosya", menu=dosya)

        duzen = tk.Menu(cubugu, tearoff=0)
        duzen.add_command(label="Geri Al", accelerator="⌘Z",
                          command=self._geri_al)
        duzen.add_command(label="Yinele", accelerator="⇧⌘Z",
                          command=self._yinele)
        duzen.add_separator()
        duzen.add_command(label="Seçilileri Sil", accelerator="⌫",
                          command=lambda: self._editor_hazirsa(
                              self.editor.secilileri_sil))
        duzen.add_command(label="Seçilileri Birleştir",
                          command=lambda: self._editor_hazirsa(
                              self.editor.secilileri_birlestir))
        duzen.add_command(label="Tümünü Seç", accelerator="⌘A",
                          command=lambda: self._editor_hazirsa(
                              self.editor.tumunu_sec))
        duzen.add_command(label="Sayfayı Sıfırla",
                          command=self._sayfa_sifirla)
        cubugu.add_cascade(label="Düzen", menu=duzen)

        disa = tk.Menu(cubugu, tearoff=0)
        disa.add_command(label="CSV (Excel uyumlu)…",
                         command=lambda: self.disa_aktar("csv"))
        disa.add_command(label="Markdown…",
                         command=lambda: self.disa_aktar("md"))
        disa.add_command(label="HTML (görüntülü, tek dosya)…",
                         command=lambda: self.disa_aktar("html"))
        disa.add_separator()
        disa.add_command(label="Word (.docx, düzenlenebilir)…",
                         command=lambda: self.disa_aktar("docx"))
        disa.add_command(label="PDF (metin öncelikli)…",
                         command=lambda: self.disa_aktar("pdf-metin"))
        cubugu.add_cascade(label="Dışa Aktar", menu=disa)

        araclar = tk.Menu(cubugu, tearoff=0)
        araclar.add_command(label="Sınav PDF'i Üret…",
                            command=self.sinav_pdf)
        araclar.add_command(label="Optik Form Üret…",
                            command=self.optik_form)
        araclar.add_command(label="Soru Bankasına Aktar",
                            command=self.bankaya_aktar)
        cubugu.add_cascade(label="Araçlar", menu=araclar)

        gorunum = tk.Menu(cubugu, tearoff=0)
        gorunum.add_command(label="Yakınlaştır", accelerator="⌘+",
                            command=lambda: self._zoom(1.25))
        gorunum.add_command(label="Uzaklaştır", accelerator="⌘−",
                            command=lambda: self._zoom(1 / 1.25))
        gorunum.add_command(label="%100", accelerator="⌘0",
                            command=lambda: self._editor_hazirsa(
                                lambda: self.editor.zoom_ayarla(mutlak=1.0)))
        gorunum.add_command(label="Sığdır",
                            command=lambda: self._editor_hazirsa(
                                self.editor.sigdir))
        cubugu.add_cascade(label="Görünüm", menu=gorunum)
        self.root.config(menu=cubugu)

    def _kisayollar_kur(self):
        # aqua menü accelerator'ları otomatik bağlanmaz → bind_all;
        # yazı alanlarında (Entry/Spinbox/Text) kısayol çalışmaz.
        def sar(fn):
            def sarici(olay):
                odak = self.root.focus_get()
                if isinstance(odak, (tk.Entry, ttk.Entry, tk.Text,
                                     tk.Spinbox, ttk.Spinbox,
                                     ttk.Combobox)):
                    return None
                fn()
                return "break"
            return sarici

        b = self.root.bind_all
        b("<Command-o>", sar(self.dosya_sec))
        b("<Command-s>", sar(self.kes))
        b("<Command-z>", sar(self._geri_al))
        b("<Shift-Command-z>", sar(self._yinele))
        b("<Command-a>", sar(lambda: self._editor_hazirsa(
            self.editor.tumunu_sec)))
        b("<Command-plus>", sar(lambda: self._zoom(1.25)))
        b("<Command-equal>", sar(lambda: self._zoom(1.25)))
        b("<Command-minus>", sar(lambda: self._zoom(1 / 1.25)))
        b("<Command-0>", sar(lambda: self._editor_hazirsa(
            lambda: self.editor.zoom_ayarla(mutlak=1.0))))
        b("<BackSpace>", sar(lambda: self._editor_hazirsa(
            self.editor.secilileri_sil)))
        b("<Delete>", sar(lambda: self._editor_hazirsa(
            self.editor.secilileri_sil)))
        b("<Escape>", sar(self._vazgec))
        # sayfa gezinme yalnız tuval odaklıyken (ağaç kendi oklarını kullanır)
        self.editor.tuval.bind("<Left>",
                               lambda e: self._sayfa_degis(-1))
        self.editor.tuval.bind("<Right>",
                               lambda e: self._sayfa_degis(1))

    # ------------------------------------------------------------ küçük yardımcılar
    def _editor_hazirsa(self, fn):
        if self.sayfalar and not self.mesgul:
            fn()

    def _zoom(self, carpan):
        self._editor_hazirsa(lambda: self.editor.zoom_ayarla(carpan=carpan))

    def _vazgec(self):
        if self.editor.mod == "ciz":
            self.editor.mod_ayarla("sec")
        else:
            self.editor.secimi_birak()

    def _ciz_degistir(self):
        self.editor.mod_ayarla("sec" if self.editor.mod == "ciz" else "ciz")

    def _mod_degisti(self, mod):
        self.ciz_btn.config(text="✋ Vazgeç" if mod == "ciz"
                            else "✏ Kutu Çiz")
        if mod == "ciz":
            self._durum_yaz("Kutu çizmek için tuval üzerinde sürükleyin.")

    def _sayfa_sifirla(self):
        if not self.sayfalar or self.mesgul:
            return
        if messagebox.askyesno(
                "Sayfayı Sıfırla",
                "Bu sayfadaki tüm elle düzenlemeler geri alınacak ve "
                "otomatik tespit geri gelecek. Devam edilsin mi?"):
            self.editor.sayfayi_sifirla()

    def _geri_al(self):
        self._editor_hazirsa(self.editor.geri_al)

    def _yinele(self):
        self._editor_hazirsa(self.editor.yinele)

    def _durum_yaz(self, metin):
        self.durum.config(text=metin)

    def _bilgi_guncelle(self):
        if not self.sayfalar:
            self.bilgi_etiket.config(text="")
            self.sayfa_etiket.config(text="–")
            return
        idx = self.onizleme_sayfa
        sayfa_soru = len(self.model.kutular(idx)) \
            if idx in self.model.kutu_onbellek else "?"
        self.bilgi_etiket.config(
            text=f"Sayfa {idx + 1}/{len(self.sayfalar)} · "
                 f"{len(self.parca_meta)} soru · "
                 f"%{self.editor.zoom * 100:.0f}")
        self.sayfa_etiket.config(
            text=f"Sayfa {idx + 1}/{len(self.sayfalar)} — "
                 f"{sayfa_soru} kutu")

    def _dugme_durumlari(self):
        var = bool(self.sayfalar) and not self.mesgul
        durum = "normal" if var else "disabled"
        for b in (self.ciz_btn, self.sil_btn, self.birlestir_btn,
                  self.sifirla_btn, self.kes_btn):
            b.config(state=durum)
        self.geri_btn.config(state=durum)
        self.ileri_btn.config(state=durum)
        self.onizle_btn.config(
            state="normal" if self.girdiler and not self.mesgul
            else "disabled")
        self.geri_al_btn.config(
            state="normal" if var and self.editor.undo.geri_var
            else "disabled")
        self.yinele_btn.config(
            state="normal" if var and self.editor.undo.ileri_var
            else "disabled")

    def _mesgul_yap(self, mesgul, mesaj=""):
        self.mesgul = mesgul
        if mesaj:
            self.durum.config(text=mesaj)
        self.durdur_btn.config(state="normal" if mesgul else "disabled")
        if mesgul:
            self.ilerleme.config(mode="indeterminate")
            self.ilerleme.start(12)
        else:
            self.ilerleme.stop()
            self.ilerleme.config(mode="determinate", value=0)
        self._dugme_durumlari()

    def _durdur(self):
        self.yurutucu.iptal_et()
        self._durum_yaz("Durduruluyor…")

    # ------------------------------------------------------------ dosya + yükleme
    def dosya_sec(self):
        if self.mesgul:
            return
        yollar = filedialog.askopenfilenames(
            title="Test dosyaları seç",
            filetypes=[("Test dosyaları", "*.pdf *.png *.jpg *.jpeg "
                        "*.tif *.tiff *.bmp *.webp"), ("Tümü", "*.*")])
        if not yollar:
            return
        self.girdiler = list(yollar)
        ad = ", ".join(os.path.basename(y) for y in self.girdiler)
        self.dosya_etiket.config(text=ad if len(ad) < 70 else ad[:67] + "…")
        # durumu sıfırla (bekleyen debounce işleri eski belgeye ait)
        if self._ozet_isi is not None:
            self.root.after_cancel(self._ozet_isi)
            self._ozet_isi = None
        if self._kucuk_isi is not None:
            self.root.after_cancel(self._kucuk_isi)
            self._kucuk_isi = None
        self._kucuk_jeton = None
        self.sayfalar = []
        self.testler, self.parca_meta, self.kimlikler = [], [], []
        self.cevaplar = None
        self.sayfa_kararlari = {}
        self.cevap_duzeltmeler = {}
        self._bekleyen_eylem = None
        self.model.temizle()
        self.editor.temizle()
        self.agac.temizle()
        self.tespit_etiket.config(text="")
        self._kucuk_goster(None)
        self._dugme_durumlari()
        self._bilgi_guncelle()
        self._durum_yaz(f"{len(self.girdiler)} dosya seçildi. "
                        "Ön izlemek için 'Ön İzle'ye basın.")
        self.onizle()               # seçer seçmez yüklemeye başla

    def onizle(self):
        if not self.girdiler or self.mesgul:
            return
        self._mesgul_yap(True, "Dosyalar yükleniyor ve kalibre ediliyor…")
        eski_docs, self.acik_docs = self.acik_docs, []
        self.yurutucu.is_ver(self._yukle_isi, list(self.girdiler),
                             self.dpi_degeri.get(), eski_docs)

    def _yukle_isi(self, yollar, dpi, eski_docs):
        """(worker) Yükle + analiz + özet: tek mesajla teslim."""
        if eski_docs:
            sk.belge_kapat(eski_docs)

        def ilerleme(i, n):
            self.yurutucu.ilerleme_kancasi()
            if i == 1:
                self.kuyruk.put(("ilerleme_kur", n))
            self.kuyruk.put(("ilerleme", i, f"Sayfa {i}/{n} okunuyor…"))

        sayfalar, acik, fmt, sx = sk.belge_hazirla(yollar, dpi,
                                                   ilerleme=ilerleme)
        try:
            self.kuyruk.put(("ilerleme", 0, "Sayfalar analiz ediliyor…"))
            _profil, analizler = sk.belge_analiz_et(sayfalar, fmt=fmt,
                                                    girdiler=yollar)
        except Exception:  # noqa: BLE001 — analiz düşerse tembel yol
            analizler = None
        self.yurutucu.ilerleme_kancasi()
        cevaplar = sk.cevap_anahtari_bul(sayfalar)
        self.kuyruk.put(("ilerleme", 0, "Test yapısı çıkarılıyor…"))
        # kutu planını model sözleşmesiyle aynı kaynaktan sabitle
        self.model.belge_ata(sayfalar, fmt, sx, analizler)
        atama = self.model.kutu_atama()  # None (henüz düzenleme yok)
        testler, parca_meta = sk.test_ozeti(sayfalar, fmt,
                                            kutu_atama=atama,
                                            cevaplar=cevaplar)
        kimlikler = sk.soru_kimlikleri(parca_meta)
        self.kuyruk.put(("yuklendi", sayfalar, acik, sx, fmt,
                         testler, parca_meta, kimlikler, cevaplar))

    def _yukleme_bitti(self, sayfalar, acik, sx, fmt, testler,
                       parca_meta, kimlikler, cevaplar):
        self.sayfalar = sayfalar
        self.acik_docs = acik
        self.sutun_xler = sx
        self.fmt = fmt
        self._cevaplari_bindir(parca_meta, kimlikler)
        self.testler = testler
        self.parca_meta = parca_meta
        self.kimlikler = kimlikler
        self.cevaplar = cevaplar
        self.onizleme_sayfa = 0
        self.editor.undo.temizle()

        raster = sum(1 for s in sayfalar if s.raster)
        mod = ("taranmış (OCR)" if raster == len(sayfalar)
               else "metin katmanı" if raster == 0 else "karışık")
        self.tespit_etiket.config(
            text=f"✓ {len(sayfalar)} sayfa\n{len(sx)} sütun · {mod}\n"
                 f"{fmt}\nToplam {len(parca_meta)} soru bulundu")
        self.agac.doldur(testler, parca_meta, kimlikler)
        self._mesgul_yap(False, f"{len(parca_meta)} soru tespit edildi. "
                                "Kutuları düzenleyip 'Kes'e basın.")
        self._sayfaya_git(0)

    # ------------------------------------------------------------ sayfa görüntüsü
    def _gorsel_iste(self, idx):
        self.yurutucu.is_ver(self._gorsel_isi, idx)

    def _gorsel_isi(self, idx):
        """(worker) Sayfa görüntüsü + kutu planını hazırla."""
        if idx >= len(self.sayfalar):
            return                  # bayat iş: bu arada yeni belge seçildi
        self.model.kutular(idx)     # tembel tespiti worker'da materialize et
        pil, olcek = self.sayfalar[idx].gorsel()
        self.kuyruk.put(("sayfa_gorsel", idx, pil, olcek))

    def _sayfaya_git(self, idx, sec_kutu=None):
        if not self.sayfalar:
            return
        self.onizleme_sayfa = max(0, min(len(self.sayfalar) - 1, idx))
        self.editor.sayfa_goster(self.onizleme_sayfa, sec_kutu=sec_kutu)
        self._bilgi_guncelle()

    def _sayfa_degis(self, yon):
        if not self.sayfalar or self.mesgul:
            return
        self._sayfaya_git(self.onizleme_sayfa + yon)

    def _soruya_git(self, si, ki):
        """Ağaçta tek soru odaklanınca editörde göster."""
        if not self.sayfalar or self.mesgul:
            return
        if si == self.onizleme_sayfa and self.editor._pil is not None:
            self.editor.secim = [ki]
            self.editor._kutulari_ciz()
            self.editor._secim_bildir()
        else:
            self._sayfaya_git(si, sec_kutu=ki)

    # ------------------------------------------------------------ özet tazeleme
    def _kutular_degisti(self, idx):
        """Editör commit'i: durum + (debounce) özet tazeleme.
        test_ozeti ve kirpma_seti AYNI kutu_atama'yı görmeli — yoksa
        (si,ki) indeksleri kayar ve yanlış soru kesilir."""
        self._bilgi_guncelle()
        self._dugme_durumlari()
        if self._ozet_isi is not None:
            self.root.after_cancel(self._ozet_isi)
        self._ozet_isi = self.root.after(400, self._ozet_tazele)

    def _ozet_tazele(self):
        self._ozet_isi = None
        if not self.sayfalar:
            return
        self.yurutucu.is_ver(self._ozet_isi_calistir,
                             self.model.kutu_atama())

    def _ozet_isi_calistir(self, atama):
        """(worker) Düzenlenmiş plana göre test/soru özetini tazele."""
        testler, parca_meta = sk.test_ozeti(self.sayfalar, self.fmt,
                                            kutu_atama=atama,
                                            cevaplar=self.cevaplar)
        kimlikler = sk.soru_kimlikleri(parca_meta)
        self.kuyruk.put(("ozet", testler, parca_meta, kimlikler))

    def _cevaplari_bindir(self, parca_meta, kimlikler):
        """Elle cevap düzeltmelerini özet verisine bindirir (web paritesi:
        düzeltme anahtar eşlemesini ezer; '' = cevap yok)."""
        if not self.cevap_duzeltmeler:
            return
        for pm, kml in zip(parca_meta, kimlikler):
            if kml in self.cevap_duzeltmeler:
                pm["cevap"] = self.cevap_duzeltmeler[kml] or None

    def _cevap_duzelt_ac(self, kimlik):
        """Ağaçta Cvp hücresine çift tık → düzeltme diyaloğu."""
        if self.mesgul or kimlik not in self.kimlikler:
            return
        pm = self.parca_meta[self.kimlikler.index(kimlik)]
        etiket = (f"T{pm['test_no']} S{pm['soru_no']}"
                  if pm.get("test_no") is not None
                  else f"S{pm.get('soru_no', '?')}")
        from gui_dialogs import CevapDialog

        def secildi(cevap):
            if cevap is None:
                self.cevap_duzeltmeler.pop(kimlik, None)
            else:
                self.cevap_duzeltmeler[kimlik] = cevap
            self._ozet_tazele()      # bindirme özet dönüşünde uygulanır
            self._durum_yaz("Cevap düzeltmesi kaydedildi." if cevap is not None
                            else "Cevap otomatik eşlemeye döndü.")
        CevapDialog(self.root, etiket, pm.get("cevap"), secildi)

    def _ozet_geldi(self, testler, parca_meta, kimlikler):
        onceki_secim = self.agac.secili_kimlikler()
        self._cevaplari_bindir(parca_meta, kimlikler)
        self.testler = testler
        self.parca_meta = parca_meta
        self.kimlikler = kimlikler
        self.agac.doldur(testler, parca_meta, kimlikler, sec=onceki_secim)
        self.tespit_etiket.config(
            text=f"✓ {len(self.sayfalar)} sayfa\n"
                 f"{len(self.sutun_xler or [])} sütun\n{self.fmt}\n"
                 f"Toplam {len(parca_meta)} soru")
        self._bilgi_guncelle()

    # ------------------------------------------------------------ seçim geri bildirimi
    def _agac_secim(self, adet):
        self.secili_adet = adet
        self.kes_btn.config(text=(f"Kes ({adet} seçili) →" if adet
                                  else "Kes ve Kaydet →"))

    def _editor_secim(self, secim):
        if len(secim) == 1 and self.sayfalar:
            idx = self.onizleme_sayfa
            kutular = self.model.kutular(idx)
            if secim[0] < len(kutular):
                self._kucuk_planla(idx, kutular[secim[0]])
                self._durum_yaz(f"Kutu {secim[0] + 1} seçildi — kenar/köşe "
                                "tutamaçlarıyla düzenleyin.")
                return
        if len(secim) > 1:
            self._durum_yaz(f"{len(secim)} kutu seçili — silebilir veya "
                            "birleştirebilirsiniz.")
        self._kucuk_goster(None)

    def _kucuk_planla(self, idx, kutu):
        if self._kucuk_isi is not None:
            self.root.after_cancel(self._kucuk_isi)
        jeton = (idx, tuple(round(v, 2) for v in kutu))
        self._kucuk_jeton = jeton
        self._kucuk_isi = self.root.after(
            250, lambda: self.yurutucu.is_ver(self._kucuk_isi_calistir,
                                              idx, kutu, jeton))

    def _kucuk_isi_calistir(self, idx, kutu, jeton):
        """(worker) Seçili kutunun kırpma önizlemesi."""
        if idx >= len(self.sayfalar):
            return                  # bayat iş: bu arada yeni belge seçildi
        pil = sk.trasla(self.sayfalar[idx].kirp(kutu))
        oran = KUCUK_RESIM_EN / max(pil.width, 1)
        if oran < 1.0:
            pil = pil.resize((KUCUK_RESIM_EN,
                              max(1, int(pil.height * oran))))
        self.kuyruk.put(("kucuk_resim", jeton, pil))

    def _kucuk_goster(self, pil):
        if pil is None:
            self._tk_kucuk = None
            self.kucuk_etiket.config(image="", text="—")
            return
        self._tk_kucuk = ImageTk.PhotoImage(pil)
        self.kucuk_etiket.config(image=self._tk_kucuk, text="")

    # ------------------------------------------------------------ kesim / eylemler
    def _eylem_baslat(self, mesaj, eylem):
        """Ağır eylemi başlatır ve kalite kapısı engellerse (inceleme
        sonrası) yeniden denenebilmesi için saklar. eylem: her çağrıda
        model/karar durumunu YENİDEN okuyup worker'a iş veren closure."""
        self._bekleyen_eylem = eylem
        self._mesgul_yap(True, mesaj)
        eylem()

    def _kapi_kontrol(self, kalite, kararlar):
        """(worker) Katı kalite kapısı. Engel varsa inceleme paketi üretip
        ("kalite_engel", ...) koyar ve True döner (eylem iptal olur).
        Elle düzenlenen sayfalar (kutu_atama sabitler) kapıdan geçer —
        web'de 'sayfa doğru' onayının eşdeğeri."""
        if kalite != "strict":
            return False
        sonuc, profil, analizler = sk.kalite_kapisi(
            self.sayfalar, self.fmt, self.girdiler, kalite,
            sayfa_kararlari=kararlar)
        bekleyen = [dict(b) for b in sonuc.bekleyen_sayfalar
                    if (b["sayfa"] - 1) not in self.model.duzenlendi]
        if sonuc.izin or not bekleyen:
            return False
        gorseller = {}
        try:
            klasor = tempfile.mkdtemp(prefix="soru_kesici_inceleme_")
            _, yollar = sk.inceleme_paketi_uret(
                self.sayfalar, self.fmt, klasor, girdiler=self.girdiler,
                kalite=kalite, kapi_sonucu=sonuc, profil=profil,
                analizler=analizler)
            for y in yollar:
                ad = os.path.basename(y)          # inceleme_sayfaNNNN.png
                gorseller[int(ad[len("inceleme_sayfa"):-4])] = y
        except Exception:  # noqa: BLE001 — bindirme üretilemezse listesiz devam
            pass
        self.kuyruk.put(("kalite_engel", bekleyen, gorseller))
        return True

    def _kes_ortak(self, secim_kutular, atama, numara_temizle,
                   rastgele=None, tohum=None):
        """(worker) Web _kes_ortak paritesi: seçim + elle kutular + cevap
        eşleme + ilerleme ile kirpma_seti."""
        def ilerleme(i, n):
            self.yurutucu.ilerleme_kancasi()
            if i == 1:
                self.kuyruk.put(("ilerleme_kur", n))
            self.kuyruk.put(("ilerleme", i, f"Soru {i}/{n} kesiliyor…"))

        return sk.kirpma_seti(
            self.sayfalar, self.fmt, girdiler=self.girdiler,
            kutu_atama=atama, secim_kutular=secim_kutular,
            cevaplar=self.cevaplar, numara_temizle=numara_temizle,
            ilerleme=ilerleme, rastgele=rastgele, tohum=tohum,
            cevap_duzeltmeler=dict(self.cevap_duzeltmeler) or None)

    def kes(self):
        if not self.sayfalar or self.mesgul:
            return
        varsayilan = os.path.join(
            os.path.dirname(os.path.abspath(self.girdiler[0])), "Arşiv.zip")
        yol = filedialog.asksaveasfilename(
            title="Arşiv.zip'i kaydet", defaultextension=".zip",
            initialfile=os.path.basename(varsayilan),
            initialdir=os.path.dirname(varsayilan),
            filetypes=[("Zip arşivi", "*.zip")])
        if not yol:
            return
        adet = self.secili_adet or len(self.parca_meta)
        self._eylem_baslat(
            f"{adet} soru kesiliyor…",
            lambda: self.yurutucu.is_ver(
                self._kes_isi, yol, self.agac.secim_kutulari(),
                self.model.kutu_atama(), self.numara_gizle.get(),
                self.klasor_de.get(), self.kalite.get(),
                dict(self.sayfa_kararlari), self.cevap_bandi.get(),
                self.cozum_ilistir.get()))

    def _kes_isi(self, yol, secim_kutular, atama, numara_gizle,
                 klasor_de, kalite, kararlar, cevap_bandi=False,
                 cozum_ilistir=False):
        """(worker) Kalite kapısı + kirpma_seti + zip. Çözüm iliştirme ve
        cevap bandı YALNIZ bu zip yolunda uygulanır (banka/sınav bantsız)."""
        if self._kapi_kontrol(kalite, kararlar):
            return
        kirpmalar, sorular, uyarilar = self._kes_ortak(
            secim_kutular, atama, numara_gizle)
        if not kirpmalar:
            self.kuyruk.put(("hata", "Seçime uyan soru bulunamadı."))
            return
        uyarilar = list(uyarilar)
        if cozum_ilistir:
            kirpmalar, sorular, cu = sk.cozumleri_ilistir(kirpmalar, sorular)
            uyarilar.extend(cu[:8])
        if cevap_bandi:
            kirpmalar = [sk.cevap_bandi_ekle(im, so["cevap"])
                         if so.get("cevap") else im
                         for im, so in zip(kirpmalar, sorular)]
        sk.zip_yaz(kirpmalar, yol, klasor_de, sorular=sorular)
        self.kuyruk.put(("kesildi", yol, len(kirpmalar), uyarilar))

    # ------------------------------------------------------------ dışa aktarma
    def disa_aktar(self, tur):
        if not self.sayfalar or self.mesgul:
            return
        uzanti = {"csv": ".csv", "md": ".md", "html": ".html",
                  "docx": ".docx", "pdf-metin": ".pdf"}[tur]
        temel = os.path.splitext(
            os.path.basename(self.girdiler[0]))[0] if self.girdiler else "sorular"
        yol = filedialog.asksaveasfilename(
            title="Dışa aktar", defaultextension=uzanti,
            initialfile=f"{temel}_soru_bankasi{uzanti}",
            initialdir=os.path.dirname(os.path.abspath(self.girdiler[0])),
            filetypes=[(uzanti[1:].upper(), f"*{uzanti}")])
        if not yol:
            return
        self._eylem_baslat(
            "Dışa aktarılıyor…",
            lambda: self.yurutucu.is_ver(
                self._disa_isi, tur, yol,
                [dict(pm) for pm in self.parca_meta],
                list(self.kimlikler),
                self.agac.secili_kimlikler(),
                self.agac.secim_kutulari(), self.model.kutu_atama(),
                self.numara_gizle.get(), self.kalite.get(),
                dict(self.sayfa_kararlari)))

    def _disa_isi(self, tur, yol, parca_meta, kimlikler, secili_kimlikler,
                  secim_kutular, atama, numara_gizle, kalite, kararlar):
        """(worker) CSV/MD: kesimsiz metadata; HTML/DOCX/PDF: seçimli kesim
        (web disa_aktar_kaydet paritesi)."""
        if tur in ("html", "docx", "pdf-metin"):
            if self._kapi_kontrol(kalite, kararlar):
                return
            kirpmalar, sorular, _uyar = self._kes_ortak(
                secim_kutular, atama, numara_gizle)
            if not kirpmalar:
                self.kuyruk.put(("hata", "Seçime uyan soru bulunamadı."))
                return
            if tur == "html":
                metin, _uz = sk.disa_aktar(sorular, "html",
                                           kirpmalar=kirpmalar)
                with open(yol, "w", encoding="utf-8") as f:
                    f.write(metin)
            else:
                try:
                    import belge_disa
                    if tur == "docx":
                        belge_disa.docx_uret(sorular, kirpmalar, yol)
                    else:
                        belge_disa.pdf_metin_uret(sorular, kirpmalar, yol)
                except ImportError as e:
                    self.kuyruk.put(("hata",
                                     f"Bu format için ek paket gerekli: {e}"
                                     "\n(ör. pip install python-docx)"))
                    return
            self.kuyruk.put(("disa_bitti", yol, len(sorular)))
            return
        # csv / md: kesim yok, hızlı metadata dökümü
        kaynak = (os.path.basename(self.girdiler[0])
                  if self.girdiler else None)
        secili = set(secili_kimlikler or [])
        sorular = [{"test_no": pm.get("test_no"),
                    "soru_no": pm.get("soru_no"),
                    "sayfa": pm.get("sayfa"), "cevap": pm.get("cevap"),
                    "kaynak": kaynak,
                    "metin": " ".join(pm.get("metin") or [])}
                   for pm, kml in zip(parca_meta, kimlikler)
                   if not secili or kml in secili]
        metin, _uz = sk.disa_aktar(sorular, tur)
        with open(yol, "w", encoding="utf-8") as f:
            f.write(metin)
        self.kuyruk.put(("disa_bitti", yol, len(sorular)))

    # ------------------------------------------------------------ sınav PDF
    def sinav_pdf(self):
        if not self.sayfalar or self.mesgul:
            return
        temel = os.path.splitext(
            os.path.basename(self.girdiler[0]))[0] if self.girdiler else "Sınav"
        SinavPdfDialog(self.root, temel, self._sinav_ayarlandi)

    def _sinav_ayarlandi(self, ayarlar, rastgele, tohum):
        temel = ayarlar.get("baslik") or "Sınav"
        yol = filedialog.asksaveasfilename(
            title="Sınav PDF'ini kaydet", defaultextension=".pdf",
            initialfile=f"{temel}.pdf",
            initialdir=os.path.dirname(os.path.abspath(self.girdiler[0])),
            filetypes=[("PDF", "*.pdf")])
        if not yol:
            return
        self._eylem_baslat(
            "Sınav PDF'i üretiliyor…",
            lambda: self.yurutucu.is_ver(
                self._sinav_isi, yol, ayarlar, rastgele, tohum,
                self.agac.secim_kutulari(), self.model.kutu_atama(),
                self.kalite.get(), dict(self.sayfa_kararlari)))

    def _sinav_isi(self, yol, ayarlar, rastgele, tohum, secim_kutular,
                   atama, kalite, kararlar):
        """(worker) Seçimli kes (numara temiz) + sinav_pdf_uret."""
        if self._kapi_kontrol(kalite, kararlar):
            return
        kirpmalar, sorular, _uyar = self._kes_ortak(
            secim_kutular, atama, numara_temizle=True,
            rastgele=rastgele, tohum=tohum)
        if not kirpmalar:
            self.kuyruk.put(("hata", "Seçime uyan soru bulunamadı."))
            return
        import sinav_pdf
        sonuc = sinav_pdf.sinav_pdf_uret(kirpmalar, sorular, ayarlar, yol)
        if ayarlar.get("optik_form"):
            try:
                import optik_koprusu
                kok, _ = os.path.splitext(yol)
                optik = optik_koprusu.sinavdan_optik(
                    sorular, ayarlar, kok + "_optik.pdf")
                sonuc["yollar"] = list(sonuc.get("yollar") or []) \
                    + [optik["pdf"]]
                sonuc["optik"] = optik
            except Exception as e:  # noqa: BLE001 — sınav üretimi bozulmaz
                sonuc["optik"] = {"hata": str(e)}
        self.kuyruk.put(("sinav_bitti", sonuc, len(kirpmalar)))

    # ------------------------------------------------------------ optik form
    def optik_form(self):
        """Optik cevap kâğıdı üretimi — belge yüklü olmasa da çalışır."""
        OptikFormDialog(self.root, self._optik_ayarlandi)

    def _optik_ayarlandi(self, tanim, on_ayar):
        from tkinter import messagebox
        temel = tanim.get("ad") or on_ayar or "optik_form"
        yol = filedialog.asksaveasfilename(
            title="Optik formu kaydet", defaultextension=".pdf",
            initialfile=f"{temel}.pdf", filetypes=[("PDF", "*.pdf")])
        if not yol:
            return
        try:
            import optik_form
            import optik_kayit
            sonuc = optik_form.form_uret(tanim, yol=yol, on_ayar=on_ayar)
            conn = optik_kayit.baglan()
            try:
                optik_kayit.sinav_ekle(
                    conn, sonuc["sablon"],
                    {"kurum": tanim.get("kurum", ""),
                     "yanlis_boler": sonuc["sablon"]
                     .puan_kurali.get("yanlis_boler", 0)})
            finally:
                conn.close()
            messagebox.showinfo(
                "Optik Form", f"Üretildi: {os.path.basename(yol)}\n"
                f"{sonuc['sablon'].soru_sayisi()} soru, "
                f"{sonuc['sayfa']} sayfa\n"
                f"Sınav kimliği: {sonuc['sinav_id']}\n\n"
                "Taramaları okumak için web arayüzündeki 🔘 Optik "
                "sekmesini kullanın.", parent=self.root)
        except Exception as e:  # noqa: BLE001
            messagebox.showerror("Optik Form", f"Üretilemedi: {e}",
                                 parent=self.root)

    # ------------------------------------------------------------ soru bankası
    def bankaya_aktar(self):
        if not self.sayfalar or self.mesgul:
            return
        adet = self.secili_adet or len(self.parca_meta)
        if not messagebox.askyesno(
                "Soru Bankasına Aktar",
                f"{adet} soru kesilerek yerel soru bankasına eklenecek "
                "(mükerrerler atlanır). Devam edilsin mi?"):
            return
        self._eylem_baslat(
            "Soru bankasına aktarılıyor…",
            lambda: self.yurutucu.is_ver(
                self._banka_isi, self.agac.secim_kutulari(),
                self.model.kutu_atama(), self.kalite.get(),
                dict(self.sayfa_kararlari)))

    def _banka_isi(self, secim_kutular, atama, kalite, kararlar):
        """(worker) Seçimli kes + banka_ekle (içerik-hash tekilleştirme)."""
        if self._kapi_kontrol(kalite, kararlar):
            return
        kirpmalar, sorular, _uyar = self._kes_ortak(
            secim_kutular, atama, numara_temizle=True)
        if not kirpmalar:
            self.kuyruk.put(("hata", "Seçime uyan soru bulunamadı."))
            return
        import soru_bankasi
        kaynak = (os.path.basename(self.girdiler[0])
                  if self.girdiler else None)
        sonuc = soru_bankasi.banka_ekle(sorular, kirpmalar, kaynak=kaynak)
        self.kuyruk.put(("banka_bitti", sonuc))

    # ------------------------------------------------------------ toplu işlem
    def toplu_islem(self):
        if self.mesgul:
            return
        TopluIslemDialog(self.root, self._toplu_baslat)

    def _toplu_baslat(self, dosyalar, klasor):
        self._mesgul_yap(True,
                         f"Toplu işlem: {len(dosyalar)} dosya sıraya "
                         "alındı…")
        self._bekleyen_eylem = None
        self.yurutucu.is_ver(self._toplu_isi, dosyalar, klasor,
                             self.dpi_degeri.get(), self.klasor_de.get(),
                             self.numara_gizle.get())

    def _toplu_isi(self, dosyalar, klasor, dpi, klasor_de, numara_gizle):
        """(worker) Her girdi ayrı arşive (CLI --coklu paritesi); hatalı
        dosya atlanır ve raporlanır."""
        rapor = []
        n = len(dosyalar)
        for i, dosya in enumerate(dosyalar, 1):
            self.yurutucu.ilerleme_kancasi()
            ad = os.path.basename(dosya)
            self.kuyruk.put(("ilerleme_kur", n))
            self.kuyruk.put(("ilerleme", i,
                             f"[{i}/{n}] {ad} işleniyor…"))
            acik = []
            try:
                sayfalar, acik, fmt, _sx = sk.belge_hazirla(
                    [dosya], dpi,
                    ilerleme=lambda a, b: self.yurutucu.ilerleme_kancasi())
                cevaplar = sk.cevap_anahtari_bul(sayfalar)
                kirpmalar, sorular, _uyar = sk.kirpma_seti(
                    sayfalar, fmt, girdiler=[dosya], cevaplar=cevaplar,
                    numara_temizle=numara_gizle,
                    ilerleme=lambda a, b: self.yurutucu.ilerleme_kancasi())
                if not kirpmalar:
                    rapor.append(f"⚠ {ad}: soru bulunamadı")
                    continue
                kok = os.path.splitext(ad)[0]
                hedef = os.path.join(klasor, f"{kok}_Arşiv.zip")
                sk.zip_yaz(kirpmalar, hedef, klasor_de, sorular=sorular)
                rapor.append(f"✓ {ad}: {len(kirpmalar)} soru")
            except Exception as e:  # noqa: BLE001 — tek dosya tümünü durdurmasın
                rapor.append(f"✗ {ad}: {e}")
            finally:
                if acik:
                    sk.belge_kapat(acik)
        self.kuyruk.put(("toplu_bitti", rapor, klasor))

    def _inceleme_tamam(self, kararlar):
        """İnceleme diyaloğu kapandı: kararları işle, bekleyen eylemi
        yeniden dene (kapı bu kez kararları görür)."""
        self.sayfa_kararlari.update(kararlar)
        eylem = self._bekleyen_eylem
        if eylem is not None:
            self._mesgul_yap(True, "İnceleme kararlarıyla yeniden "
                                   "deneniyor…")
            eylem()

    # ------------------------------------------------------------ kuyruk
    def _kuyruk_yokla(self):
        try:
            while True:
                mesaj = self.kuyruk.get_nowait()
                tur = mesaj[0]
                if tur == "ilerleme_kur":
                    self.ilerleme.stop()
                    self.ilerleme.config(mode="determinate",
                                         maximum=mesaj[1], value=0)
                elif tur == "ilerleme":
                    if mesaj[1]:
                        self.ilerleme.config(value=mesaj[1])
                    self.durum.config(text=mesaj[2])
                elif tur == "yuklendi":
                    self._yukleme_bitti(*mesaj[1:])
                elif tur == "sayfa_gorsel":
                    self.editor.gorsel_hazir(mesaj[1], mesaj[2], mesaj[3])
                    self._bilgi_guncelle()
                elif tur == "ozet":
                    self._ozet_geldi(*mesaj[1:])
                elif tur == "kucuk_resim":
                    if mesaj[1] == self._kucuk_jeton:
                        self._kucuk_goster(mesaj[2])
                elif tur == "kesildi":
                    self._mesgul_yap(False,
                                     f"✓ {mesaj[2]} soru kaydedildi.")
                    if mesaj[3]:
                        messagebox.showwarning(
                            "Uyarılar", "\n".join(mesaj[3][:12]))
                    if messagebox.askyesno(
                            "Tamamlandı",
                            f"{mesaj[2]} soru şuraya kaydedildi:\n"
                            f"{mesaj[1]}\n\nKlasörü açmak ister misiniz?"):
                        subprocess.run(["open", "-R", mesaj[1]],
                                       check=False)
                elif tur == "disa_bitti":
                    self._mesgul_yap(False,
                                     f"✓ {mesaj[2]} soru dışa aktarıldı.")
                    if messagebox.askyesno(
                            "Dışa Aktarıldı",
                            f"{mesaj[2]} soru şuraya aktarıldı:\n"
                            f"{mesaj[1]}\n\nDosyayı göstereyim mi?"):
                        subprocess.run(["open", "-R", mesaj[1]],
                                       check=False)
                elif tur == "sinav_bitti":
                    sonuc = mesaj[1]
                    optik = sonuc.get("optik") or {}
                    ek = ""
                    if optik.get("sinav_id"):
                        ek = (f" Optik: kimlik {optik['sinav_id']}, "
                              f"{optik.get('anahtarli_soru', 0)} anahtar.")
                    elif optik.get("hata"):
                        ek = f" Optik üretilemedi: {optik['hata']}"
                    self._mesgul_yap(
                        False, f"✓ Sınav PDF'i: {mesaj[2]} soru, "
                               f"{sonuc.get('sayfa', '?')} sayfa.{ek}")
                    yollar = sonuc.get("yollar") or []
                    if yollar and messagebox.askyesno(
                            "Sınav Hazır",
                            "Üretilen PDF:\n" + "\n".join(yollar)
                            + "\n\nAçmak ister misiniz?"):
                        for y in yollar:
                            subprocess.run(["open", y], check=False)
                elif tur == "banka_bitti":
                    sonuc = mesaj[1]
                    self._mesgul_yap(
                        False,
                        f"✓ Bankaya {sonuc.get('eklenen', 0)} soru "
                        f"eklendi, {sonuc.get('atlanan', 0)} mükerrer "
                        "atlandı.")
                elif tur == "toplu_bitti":
                    self._mesgul_yap(False, "Toplu işlem tamamlandı.")
                    messagebox.showinfo(
                        "Toplu İşlem", "\n".join(mesaj[1]) or "Dosya yok.")
                    subprocess.run(["open", mesaj[2]], check=False)
                elif tur == "kalite_engel":
                    self._mesgul_yap(False, "Kalite kapısı: inceleme "
                                            "bekleyen sayfalar var.")
                    IncelemeDialog(self.root, mesaj[1], mesaj[2],
                                   self._inceleme_tamam)
                elif tur == "iptal":
                    self._mesgul_yap(False, "İşlem durduruldu.")
                    if self.sayfalar and self.editor._pil is None:
                        self._gorsel_iste(self.onizleme_sayfa)
                elif tur == "hata":
                    self._mesgul_yap(False, "Hata oluştu.")
                    messagebox.showerror("Hata", mesaj[1])
        except queue.Empty:
            pass
        self.root.after(100, self._kuyruk_yokla)


def main():
    root = tk.Tk()
    SoruKesiciGUI(root)
    # DİKKAT: Bu Tk (8.5.9) + güncel macOS'ta root.update() HİÇ DÖNMEYEN
    # bir idle-redraw döngüsüne giriyor (uygulama açılışta kilitleniyor).
    # update_idletasks güvenli, mainloop normal çalışıyor; pencereyi öne
    # getirme işleri bu yüzden mainloop İÇİNDEN after ile yapılır.
    root.update_idletasks()

    def one_getir():
        root.lift()
        root.attributes("-topmost", True)
        root.after(700, lambda: root.attributes("-topmost", False))
        try:
            root.focus_force()
        except tk.TclError:
            pass

    def cizim_durt():
        # Tk 8.5 + modern macOS: pencere ilk açılışta BOŞ kalabiliyor
        # (Mojave yeniden-çizim hatası; içerik ancak elle boyutlandırınca
        # belirir). 1 px'lik geometri dürtmesi AppKit'e gerçek bir redraw
        # yaptırır. update() burada KULLANILMAZ (yukarıdaki kilitlenme).
        try:
            boyut = root.winfo_geometry().split("+", 1)[0]
            w, h = (int(v) for v in boyut.split("x"))
        except (ValueError, tk.TclError):
            return
        root.geometry(f"{w + 1}x{h}")
        root.after(80, lambda: root.geometry(f"{w}x{h}"))

    root.after(50, one_getir)
    root.after(250, cizim_durt)
    root.after(1200, cizim_durt)    # ilk dürtme erken kaçarsa ikinci tur
    root.mainloop()


if __name__ == "__main__":
    main()
