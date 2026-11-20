#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici GUI — test/soru ağacı (seçimli kesim).

test_ozeti çıktısını ttk.Treeview'e döker: test düğümleri altında sorular.
Aralık metni ("test 5: 2-10; 27-40") ve Türkçe-güvenli metin araması ile
seçim yapılabilir; seçim kesime secim_kutular={(si,ki)} olarak gider
(web tıkla-seç yolu ile aynı çekirdek sözleşme, soru_kes.py kirpma_seti).
"""

import tkinter as tk
from tkinter import ttk

import soru_kes as sk


class SoruAgaci:
    """on_secim(adet): seçim değişince; on_soru_git(si, ki): tek soru
    odaklanınca (editör o sayfaya atlar ve kutuyu seçer)."""

    def __init__(self, parent, on_secim, on_soru_git):
        self.on_secim = on_secim
        self.on_soru_git = on_soru_git
        self._pm = []
        self._kimlikler = []
        self._kimlik_idx = {}
        self._ara_isi = None
        self._ic_secim = False      # program seçimi olay tetiklemesin

        c = ttk.Frame(parent, padding=(6, 6, 0, 6))
        c.rowconfigure(3, weight=1)
        c.columnconfigure(0, weight=1)
        self.cerceve = c

        # arama satırı
        ara_c = ttk.Frame(c)
        ara_c.grid(row=0, column=0, columnspan=2, sticky="ew")
        ara_c.columnconfigure(0, weight=1)
        self.ara_var = tk.StringVar()
        ara_giris = ttk.Entry(ara_c, textvariable=self.ara_var)
        ara_giris.grid(row=0, column=0, sticky="ew")
        ara_giris.bind("<KeyRelease>", self._ara_planla)
        ttk.Label(ara_c, text="Ara").grid(row=0, column=1, padx=(4, 0))

        # aralık satırı ("test 5: 2-10; 27-40")
        aralik_c = ttk.Frame(c)
        aralik_c.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(4, 0))
        aralik_c.columnconfigure(0, weight=1)
        self.aralik_var = tk.StringVar()
        aralik_giris = ttk.Entry(aralik_c, textvariable=self.aralik_var)
        aralik_giris.grid(row=0, column=0, sticky="ew")
        aralik_giris.bind("<Return>", lambda e: self.aralik_uygula())
        ttk.Button(aralik_c, text="Seç", width=4,
                   command=self.aralik_uygula).grid(row=0, column=1,
                                                    padx=(4, 0))
        self.hata_etiket = ttk.Label(c, text="", foreground="#CD232D",
                                     wraplength=210, justify="left")
        self.hata_etiket.grid(row=2, column=0, columnspan=2, sticky="ew")

        self.agac = ttk.Treeview(c, columns=("cevap", "sayfa"),
                                 selectmode="extended")
        self.agac.grid(row=3, column=0, sticky="nsew", pady=(4, 0))
        vsb = ttk.Scrollbar(c, orient="vertical", command=self.agac.yview)
        vsb.grid(row=3, column=1, sticky="ns", pady=(4, 0))
        self.agac.configure(yscrollcommand=vsb.set)
        self.agac.heading("#0", text="Test / Soru", anchor="w")
        self.agac.heading("cevap", text="Cvp")
        self.agac.heading("sayfa", text="Syf")
        self.agac.column("#0", width=150, stretch=True)
        self.agac.column("cevap", width=36, anchor="center", stretch=False)
        self.agac.column("sayfa", width=44, anchor="center", stretch=False)
        self.agac.bind("<<TreeviewSelect>>", self._secim_olay)
        self.agac.bind("<Double-1>", self._cift_tik)
        self.on_cevap_duzelt = None    # ana pencere bağlar: (kimlik) -> None

        alt = ttk.Frame(c)
        alt.grid(row=4, column=0, columnspan=2, sticky="ew", pady=(4, 0))
        self.ozet_etiket = ttk.Label(alt, text="", foreground="#555")
        self.ozet_etiket.pack(side="left")
        ttk.Button(alt, text="Temizle", width=7,
                   command=self.secimi_temizle).pack(side="right")

    # ------------------------------------------------------------ doldurma
    def doldur(self, testler, parca_meta, kimlikler, sec=None):
        """Ağacı yeniden kurar; sec verilirse o kimlikler yeniden seçilir
        (özet tazelemesi kullanıcı seçimini kaybetmesin)."""
        self._ic_secim = True
        try:
            self.agac.delete(*self.agac.get_children())
            self._pm = list(parca_meta)
            self._kimlikler = list(kimlikler)
            self._kimlik_idx = {k: j for j, k in enumerate(kimlikler)}
            dugumler = {}
            for t in testler or []:
                ad = (f"Test {t['test_no']}" if t.get("test_no") is not None
                      else f"Bölüm #{t['test_sira']}")
                baslik = (t.get("baslik") or "").strip()
                if baslik:
                    ad += f" — {baslik[:34]}"
                dugumler[t["test_sira"]] = self.agac.insert(
                    "", "end", iid=f"T{t['test_sira']}", open=True,
                    text=f"{ad} ({t.get('adet', 0)})")
            genel = None
            for kml, pm in zip(kimlikler, parca_meta):
                ust = dugumler.get(pm.get("test_sira"))
                if ust is None:
                    if genel is None:
                        genel = self.agac.insert("", "end", iid="Tgenel",
                                                 open=True, text="Sorular")
                    ust = genel
                metin = (f"S{pm['soru_no']}" if pm.get("soru_no") is not None
                         else "Soru ?")
                self.agac.insert(ust, "end", iid=kml, text=metin,
                                 values=(pm.get("cevap") or "–",
                                         pm.get("sayfa") or "–"))
            if sec:
                mevcut = [k for k in sec if k in self._kimlik_idx]
                if mevcut:
                    self.agac.selection_set(mevcut)
        finally:
            self._ic_secim = False
        self._ozet_guncelle()

    def temizle(self):
        self.doldur([], [], [])
        self.ara_var.set("")
        self.aralik_var.set("")
        self.hata_etiket.config(text="")

    # ------------------------------------------------------------ seçim
    def secili_kimlikler(self):
        """Seçimden soru kimlikleri (test düğümü = tüm çocukları)."""
        kimlikler, gorulen = [], set()
        for iid in self.agac.selection():
            hedefler = (self.agac.get_children(iid)
                        if iid.startswith("T") else (iid,))
            for k in hedefler:
                if k in self._kimlik_idx and k not in gorulen:
                    gorulen.add(k)
                    kimlikler.append(k)
        return kimlikler

    def secim_kutulari(self):
        """Kesim için {(sayfa_idx, kutu_idx)} kümesi; boş seçim → None
        (= tüm sorular, kirpma_seti sözleşmesi)."""
        secim = set()
        for kml in self.secili_kimlikler():
            pm = self._pm[self._kimlik_idx[kml]]
            for si, ki in pm.get("parcalar_idx") or []:
                if ki is not None:
                    secim.add((si, ki))
        return secim or None

    def secimi_temizle(self):
        self.agac.selection_remove(*self.agac.selection())

    def _secim_olay(self, olay=None):
        if self._ic_secim:
            return
        self._ozet_guncelle()
        kimlikler = self.secili_kimlikler()
        self.on_secim(len(kimlikler))
        if len(kimlikler) == 1:
            pm = self._pm[self._kimlik_idx[kimlikler[0]]]
            parcalar = [p for p in (pm.get("parcalar_idx") or [])
                        if p[1] is not None]
            if parcalar:
                self.on_soru_git(parcalar[0][0], parcalar[0][1])

    def _cift_tik(self, olay):
        """Cvp sütununa çift tık → cevap düzeltme (ana pencere kancası)."""
        if self.on_cevap_duzelt is None:
            return
        satir = self.agac.identify_row(olay.y)
        if not satir or satir not in self._kimlik_idx:
            return
        if self.agac.identify_column(olay.x) == "#1":   # "cevap" sütunu
            self.on_cevap_duzelt(satir)
            return "break"

    def cevap_goster(self, kimlik, cevap):
        """Tek sorunun Cvp hücresini tazeler (özet beklemeden anlık)."""
        if kimlik in self._kimlik_idx:
            self.agac.set(kimlik, "cevap", cevap or "–")

    def _ozet_guncelle(self):
        adet = len(self.secili_kimlikler())
        toplam = len(self._kimlikler)
        self.ozet_etiket.config(
            text=(f"{adet}/{toplam} seçili" if adet else f"{toplam} soru"))

    # ------------------------------------------------------------ aralık / arama
    def aralik_uygula(self):
        metin = self.aralik_var.get().strip()
        self.hata_etiket.config(text="")
        if not metin or not self._pm:
            return
        try:
            kurallar = sk.secim_ayristir(metin)
        except ValueError as e:
            self.hata_etiket.config(text=str(e))
            return
        testler = self._testlerden()
        indeksler, uyarilar = sk.secim_uygula(self._pm, kurallar, testler)
        if uyarilar:
            self.hata_etiket.config(text=" ".join(uyarilar)[:300])
        self._sec([self._kimlikler[j] for j in sorted(indeksler)])

    def _testlerden(self):
        """secim_uygula'nın beklediği test özetini ağaç verisinden kur."""
        testler = {}
        for pm in self._pm:
            ts = pm.get("test_sira")
            if ts is None:
                continue
            t = testler.setdefault(ts, {
                "test_sira": ts, "test_no": pm.get("test_no"),
                "soru_bas": None, "soru_son": None, "adet": 0})
            t["adet"] += 1
            no = pm.get("soru_no")
            if no is not None:
                t["soru_bas"] = (no if t["soru_bas"] is None
                                 else min(t["soru_bas"], no))
                t["soru_son"] = (no if t["soru_son"] is None
                                 else max(t["soru_son"], no))
        return sorted(testler.values(), key=lambda t: t["test_sira"])

    def _ara_planla(self, olay=None):
        if self._ara_isi is not None:
            self.agac.after_cancel(self._ara_isi)
        self._ara_isi = self.agac.after(300, self._ara)

    def _ara(self):
        self._ara_isi = None
        q = sk._tr_normalize(self.ara_var.get().strip())
        if not q:
            return
        kelimeler = q.split()
        bulunan = []
        for kml, pm in zip(self._kimlikler, self._pm):
            havuz = sk._tr_normalize(" ".join(pm.get("metin") or []))
            if all(k in havuz for k in kelimeler):
                bulunan.append(kml)
        self.hata_etiket.config(
            text="" if bulunan else "Arama sonucu yok.")
        self._sec(bulunan)

    def _sec(self, kimlikler):
        self.agac.selection_set(kimlikler)
        if kimlikler:
            self.agac.see(kimlikler[0])
