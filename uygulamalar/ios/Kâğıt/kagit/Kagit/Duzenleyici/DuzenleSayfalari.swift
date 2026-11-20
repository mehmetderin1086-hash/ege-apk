import KagitKit
import PDFKit
import SwiftUI

extension View {
    /// Düzenleyici kiplerinin ortak sayfaları: metin kutusu, not, PDFium metni, bağlantı, damga seçici, açıklama listesi.
    func duzenleyiciSayfalari(_ d: DuzenleyiciDurumu) -> some View {
        modifier(DuzenleyiciSayfalari(durum: d))
    }
}

private struct DuzenleyiciSayfalari: ViewModifier {
    @Bindable var durum: DuzenleyiciDurumu

    func body(content: Content) -> some View {
        content
            .sheet(item: $durum.istek, onDismiss: { durum.vurgu = nil }) { istek in
                DuzenleIstegiSayfasi(istek: istek, durum: durum)
            }
            .sheet(isPresented: $durum.damgaSeciciAcik) { DamgaSecici(durum: durum) }
            .sheet(isPresented: $durum.aciklamaListesiAcik) { AciklamaListesi(durum: durum) }
    }
}

/// `DuzenleIstegi` türüne göre doğru sayfayı gösterir.
struct DuzenleIstegiSayfasi: View {
    let istek: DuzenleIstegi
    let durum: DuzenleyiciDurumu

    var body: some View {
        switch istek {
        case .kutuEkle(let s, let p): MetinKutusuSayfasi(durum: durum, sayfa: s, nokta: p, duzenlenen: nil)
        case .kutuDuzenle(let a): MetinKutusuSayfasi(durum: durum, sayfa: nil, nokta: .zero, duzenlenen: a)
        case .notEkle(let s, let p): NotSayfasi(durum: durum, sayfa: s, nokta: p, duzenlenen: nil)
        case .notDuzenle(let a): NotSayfasi(durum: durum, sayfa: nil, nokta: .zero, duzenlenen: a)
        case .pdfiumMetinEkle(let i, let p): PdfiumMetinSayfasi(durum: durum, sayfa: i, nokta: p, satir: nil)
        case .pdfiumSatir(let i, let s): PdfiumMetinSayfasi(durum: durum, sayfa: i, nokta: .zero, satir: s)
        case .baglanti(let s, let k): BaglantiSayfasi(durum: durum, sayfa: s, kutu: k)
        case .alanListesi: EmptyView()
        }
    }
}

// MARK: - Metin kutusu (açıklama)

struct MetinKutusuSayfasi: View {
    let durum: DuzenleyiciDurumu
    let sayfa: PDFPage?
    let nokta: CGPoint
    let duzenlenen: PDFAnnotation?

    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @State private var punto: Double = 16
    @State private var renk: Color = .black
    @State private var kalin = false
    @State private var hiza: IsaretAyarlari.Hiza = .sol
    @FocusState private var odak: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Metin", text: $metin, axis: .vertical).lineLimit(2...8).focused($odak)
                }
                Section {
                    Stepper("Punto: \(Int(punto))", value: $punto, in: 6...96)
                    Toggle("Kalın", isOn: $kalin)
                    ColorPicker("Renk", selection: $renk, supportsOpacity: false)
                    Picker("Hizalama", selection: $hiza) {
                        ForEach(IsaretAyarlari.Hiza.allCases) { Text($0.ad).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(duzenlenen == nil ? "Metin kutusu" : "Metni düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button("Tamam") { uygula() }.disabled(metin.isEmpty) }
            }
            .onAppear(perform: baslat)
        }
        .presentationDetents([.medium, .large])
    }

    private func baslat() {
        let a = durum.ayarlar
        if let d = duzenlenen {
            metin = d.contents ?? ""
            punto = Double(d.font?.pointSize ?? 16)
            kalin = d.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            renk = Color(d.fontColor ?? .black)
            hiza = d.alignment == .center ? .orta : d.alignment == .right ? .sag : .sol
        } else {
            punto = a.punto
            kalin = a.kalin
            renk = a.renk.opaklikla(1).swiftUIRengi
            hiza = a.hiza
        }
        odak = true
    }

    private func uygula() {
        let r = RGBA(renk)
        if let d = duzenlenen {
            durum.kutuGuncelle(d, metin: metin, punto: CGFloat(punto), renk: r, kalin: kalin, hiza: hiza.nsHiza)
        } else if let sayfa {
            durum.kutuEkle(sayfa, nokta: nokta, metin: metin, punto: CGFloat(punto), renk: r, kalin: kalin, hiza: hiza.nsHiza)
            durum.ayarlar.punto = punto
            durum.ayarlar.kalin = kalin
            durum.ayarlar.hiza = hiza
        }
        kapat()
    }
}

// MARK: - Yapışkan not

struct NotSayfasi: View {
    let durum: DuzenleyiciDurumu
    let sayfa: PDFPage?
    let nokta: CGPoint
    let duzenlenen: PDFAnnotation?

    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @FocusState private var odak: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Not", text: $metin, axis: .vertical).lineLimit(3...10).focused($odak)
            }
            .navigationTitle("Not")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button("Tamam") { uygula() }.disabled(metin.isEmpty) }
            }
            .onAppear { metin = duzenlenen?.contents ?? ""; odak = true }
        }
        .presentationDetents([.medium])
    }

    private func uygula() {
        if let d = duzenlenen {
            durum.degisiklik("Not", d) { d.contents = metin }
        } else if let sayfa {
            durum.notEkle(sayfa, nokta: nokta, metin: metin)
        }
        kapat()
    }
}

// MARK: - PDFium metni (gerçek içerik)

struct PdfiumMetinSayfasi: View {
    let durum: DuzenleyiciDurumu
    let sayfa: Int
    /// Yeni metin eklerken dokunulan nokta (taban çizgisi sol noktası).
    let nokta: CGPoint
    let satir: DuzenlemeSatiri?

    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @State private var punto: Double = 14
    @State private var yaziTipi: GomuluYaziTipi = .sans
    @State private var renk: Color = .black
    @FocusState private var odak: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Metin", text: $metin, axis: .vertical).lineLimit(1...5).focused($odak)
                } footer: {
                    if let satir {
                        Text("Özgün yazı tipi: \(satir.yaziTipiAdi.isEmpty ? "bilinmiyor" : satir.yaziTipiAdi). Metin gömülü bir Noto yazı tipiyle yeniden yazılır.")
                    } else {
                        Text("Metin sayfaya gerçek PDF metni olarak eklenir.")
                    }
                }
                Section {
                    Stepper("Punto: \(String(format: "%.1f", punto))", value: $punto, in: 4...144, step: 0.5)
                    Picker("Yazı tipi", selection: $yaziTipi) {
                        ForEach(GomuluYaziTipi.allCases, id: \.self) { Text($0.ad).tag($0) }
                    }
                    Toggle("Kalın", isOn: Binding(get: { kalinMi }, set: { kalinYap($0) }))
                    ColorPicker("Renk", selection: $renk, supportsOpacity: false)
                }
                if satir != nil {
                    Section {
                        Button("Satırı sil", role: .destructive) { sil() }
                    }
                }
            }
            .navigationTitle(satir == nil ? "Metin ekle" : "Metni düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button("Uygula") { uygula() }.disabled(metin.isEmpty) }
            }
            .onAppear(perform: baslat)
        }
        .presentationDetents([.medium, .large])
    }

    private var kalinMi: Bool { yaziTipi == .sansKalin || yaziTipi == .serifKalin }

    private func kalinYap(_ k: Bool) {
        switch (yaziTipi, k) {
        case (.sans, true), (.sansItalik, true), (.mono, true): yaziTipi = .sansKalin
        case (.serif, true): yaziTipi = .serifKalin
        case (.sansKalin, false): yaziTipi = .sans
        case (.serifKalin, false): yaziTipi = .serif
        default: break
        }
    }

    private func baslat() {
        if let satir {
            metin = satir.metin
            punto = Double((satir.punto * 2).rounded() / 2)
            yaziTipi = GomuluYaziTipi.eslestir(satir.yaziTipiAdi)
            renk = satir.renk.swiftUIRengi
        }
        odak = true
    }

    private func uygula() {
        let r = RGBA(renk)
        if let satir {
            durum.satiriDegistir(sayfa: sayfa, satir: satir, metin: metin, punto: CGFloat(punto), yaziTipi: yaziTipi, renk: r)
        } else {
            durum.pdfiumMetinEkle(sayfa: sayfa, taban: nokta, metin: metin, punto: CGFloat(punto), yaziTipi: yaziTipi, renk: r)
        }
        kapat()
    }

    private func sil() {
        if let satir {
            durum.satiriDegistir(sayfa: sayfa, satir: satir, metin: "", punto: CGFloat(punto), yaziTipi: yaziTipi, renk: RGBA(renk))
        }
        kapat()
    }
}

// MARK: - Bağlantı

struct BaglantiSayfasi: View {
    let durum: DuzenleyiciDurumu
    let sayfa: PDFPage
    let kutu: CGRect

    @Environment(\.dismiss) private var kapat
    @State private var tur = 0
    @State private var adres = ""
    @State private var hedefSayfa = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tür", selection: $tur) {
                    Text("Web adresi").tag(0)
                    Text("Sayfaya git").tag(1)
                }
                .pickerStyle(.segmented)
                if tur == 0 {
                    TextField("https://…", text: $adres).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    TextField("Sayfa numarası (1-\(durum.oturum?.belge?.pageCount ?? 1))", text: $hedefSayfa).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Bağlantı ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ekle") { ekle() }.disabled(tur == 0 ? adres.isEmpty : Int(hedefSayfa) == nil) }
            }
        }
        .presentationDetents([.medium])
    }

    private func ekle() {
        if tur == 0 {
            var s = adres.trimmingCharacters(in: .whitespaces)
            if !s.contains("://") && !s.hasPrefix("mailto:") && !s.hasPrefix("tel:") { s = "https://" + s }
            durum.baglantiEkle(sayfa, kutu: kutu, url: URL(string: s), hedefSayfa: nil)
        } else {
            durum.baglantiEkle(sayfa, kutu: kutu, url: nil, hedefSayfa: Int(hedefSayfa))
        }
        kapat()
    }
}

// MARK: - Damga seçici

struct DamgaSecici: View {
    let durum: DuzenleyiciDurumu
    @Environment(\.dismiss) private var kapat
    @State private var depo = DamgaDeposu.paylasilan
    @State private var yeniAcik = false

    var body: some View {
        NavigationStack {
            List {
                Section("Hazır damgalar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(DamgaTanimi.hazirlar) { t in damgaDugmesi(t) }
                    }
                }
                Section("Tarih ve ad") {
                    damgaDugmesi(DamgaTanimi.tarihDamgasi(ad: Ayarlar.paylasilan.yazarAdi))
                }
                Section("Özel damgalar") {
                    ForEach(depo.ozel) { t in
                        damgaDugmesi(t)
                            .swipeActions { Button("Sil", role: .destructive) { depo.sil(t) } }
                    }
                    Button { yeniAcik = true } label: { Label("Yeni özel damga", systemImage: "plus.circle") }
                }
            }
            .navigationTitle("Damga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat(); durum.arac = .sec } } }
            .sheet(isPresented: $yeniAcik) { OzelDamgaSayfasi() }
        }
        .presentationDetents([.medium, .large])
    }

    private func damgaDugmesi(_ t: DamgaTanimi) -> some View {
        Button {
            durum.damgaYerlestirmeyiBaslat(t)
            kapat()
        } label: {
            DamgaOnizleme(tanim: t).frame(height: 48).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// Damganın küçük önizlemesi.
struct DamgaOnizleme: View {
    let tanim: DamgaTanimi

    var body: some View {
        let boyut = tanim.varsayilanBoyut()
        Canvas { ctx, size in
            let olcek = min(size.width / boyut.width, size.height / boyut.height)
            let g = boyut.width * olcek, y = boyut.height * olcek
            let kutu = CGRect(x: (size.width - g) / 2, y: (size.height - y) / 2, width: g, height: y)
            if let img = tanim.goruntu(boyut: CGSize(width: g, height: y), olcek: 3) {
                ctx.draw(Image(decorative: img, scale: 3), in: kutu)
            }
        }
    }
}

struct OzelDamgaSayfasi: View {
    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @State private var altMetin = ""
    @State private var renk: Color = .red
    @State private var cerceve = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Damga metni", text: $metin).textInputAutocapitalization(.characters)
                    TextField("Alt satır (isteğe bağlı)", text: $altMetin)
                    ColorPicker("Renk", selection: $renk, supportsOpacity: false)
                    Toggle("Çerçeve", isOn: $cerceve)
                }
                Section("Önizleme") {
                    DamgaOnizleme(tanim: tanim).frame(height: 70).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Özel damga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { DamgaDeposu.paylasilan.ekle(tanim); kapat() }.disabled(metin.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var tanim: DamgaTanimi {
        DamgaTanimi(metin: metin.uppercased(with: Locale(identifier: "tr_TR")), altMetin: altMetin.isEmpty ? nil : altMetin,
                    renk: RGBA(renk), cerceve: cerceve)
    }
}

// MARK: - Açıklamalar listesi

struct AciklamaListesi: View {
    let durum: DuzenleyiciDurumu
    @Environment(\.dismiss) private var kapat
    @State private var silinecekHepsi = false
    @State private var yenile = 0

    private struct Satir: Identifiable {
        let id = UUID()
        let sayfa: PDFPage
        let sayfaNo: Int
        let aciklama: PDFAnnotation
    }

    private var gruplar: [(Int, [Satir])] {
        guard let belge = durum.oturum?.belge else { return [] }
        _ = yenile
        var sonuc: [(Int, [Satir])] = []
        for i in 0..<belge.pageCount {
            guard let s = belge.page(at: i) else { continue }
            let satirlar = s.annotations.filter { AciklamaFabrikasi.duzenlenebilir($0) }
                .map { Satir(sayfa: s, sayfaNo: i + 1, aciklama: $0) }
            if !satirlar.isEmpty { sonuc.append((i + 1, satirlar)) }
        }
        return sonuc
    }

    var body: some View {
        NavigationStack {
            List {
                if gruplar.isEmpty {
                    ContentUnavailableView("Açıklama yok", systemImage: "highlighter",
                                           description: Text("Bu belgede henüz işaret, not ya da çizim yok."))
                }
                ForEach(gruplar, id: \.0) { no, satirlar in
                    Section("Sayfa \(no)") {
                        ForEach(satirlar) { s in
                            Button { git(s) } label: {
                                HStack {
                                    Text(AciklamaFabrikasi.ad(s.aciklama))
                                    if let ic = s.aciklama.contents, !ic.isEmpty {
                                        Text(ic).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Sil", role: .destructive) {
                                    if durum.secili === s.aciklama { durum.secili = nil }
                                    durum.oturum?.aciklamaSil(s.aciklama)
                                    yenile += 1
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Açıklamalar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Tümünü sil", role: .destructive) { silinecekHepsi = true }.disabled(gruplar.isEmpty)
                }
            }
            .confirmationDialog("Tüm açıklamalar silinsin mi?", isPresented: $silinecekHepsi, titleVisibility: .visible) {
                Button("Hepsini sil", role: .destructive) { hepsiniSil() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("İşlem geri alınabilir.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func git(_ s: Satir) {
        durum.oturum?.pdfView?.go(to: s.aciklama.bounds.insetBy(dx: -40, dy: -40), on: s.sayfa)
        if durum.seciliOlabilir(s.aciklama) { durum.secili = s.aciklama }
        kapat()
    }

    private func hepsiniSil() {
        guard let oturum = durum.oturum else { return }
        let liste = gruplar.flatMap { $0.1 }.map { ($0.sayfa, $0.aciklama) }
        durum.secili = nil
        oturum.degistir("Tüm açıklamaları sil", yap: { for (s, a) in liste { s.removeAnnotation(a) } },
                        geriAl: { for (s, a) in liste { s.addAnnotation(a) } })
        yenile += 1
    }
}
