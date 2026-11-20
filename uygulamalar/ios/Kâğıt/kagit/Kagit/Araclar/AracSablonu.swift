import KagitKit
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Uzun işin ilerleme durumu (ana iş parçacığında yaşar, `Ilerleme` kapanışıyla beslenir).
@Observable
final class IsDurumu {
    var oran: Double?
    var metin = "Çalışıyor…"

    /// Arka plandan çağrılabilen ilerleme kapanışı.
    var bildirim: Ilerleme {
        { [weak self] o in Task { @MainActor in self?.oran = o } }
    }
}

/// Bütün araç ekranlarının ortak iskeleti: girdi listesi → seçenekler → Başlat → sonuçlar.
///
/// `calistir` geçici çıktı dosyalarını döndürür; şablon bunları kitaplığa kaydeder,
/// sonuç listesinde açma, paylaşma ve zincirleme (sıradaki araç) sunar.
struct AracSablonu<Secenekler: View>: View {
    let arac: Arac
    @State var girdiler: [URL]
    /// Seçenekler geçerli mi (ör. parola boş değil).
    var hazir: Bool = true
    /// Çıktıların kaydedileceği kitaplık klasörü (nil: ilk girdinin klasörü).
    var ciktiKlasoru: String?
    /// Sonuçlar kitaplığa kaydedilmesin (ör. yalnız paylaşılacak görseller).
    var kitapligaKaydet = true
    @ViewBuilder var secenekler: () -> Secenekler
    let calistir: (_ girdiler: [URL], _ ilerleme: @escaping Ilerleme) async throws -> [URL]

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var durum = IsDurumu()
    @State private var calisiyor = false
    @State private var gorev: Task<Void, Never>?
    @State private var sonuclar: [URL] = []
    @State private var kayitli: [KitaplikOgesi] = []
    @State private var ileti: Ileti?
    @State private var kaynakSec = false
    @State private var paylasilacak: [URL]?
    @State private var sure: TimeInterval = 0

    init(arac: Arac, girdiler: [URL], hazir: Bool = true, ciktiKlasoru: String? = nil, kitapligaKaydet: Bool = true,
         @ViewBuilder secenekler: @escaping () -> Secenekler,
         calistir: @escaping (_ girdiler: [URL], _ ilerleme: @escaping Ilerleme) async throws -> [URL]) {
        self.arac = arac
        _girdiler = State(initialValue: girdiler)
        self.hazir = hazir
        self.ciktiKlasoru = ciktiKlasoru
        self.kitapligaKaydet = kitapligaKaydet
        self.secenekler = secenekler
        self.calistir = calistir
    }

    private var girdiYeterli: Bool {
        switch arac.girdi {
        case .yok: true
        case .cokPDF: girdiler.count >= 2
        default: !girdiler.isEmpty
        }
    }

    var body: some View {
        Form {
            if arac.girdi != .yok {
                Section {
                    ForEach(girdiler, id: \.self) { u in GirdiSatiri(url: u) }
                        .onDelete { girdiler.remove(atOffsets: $0) }
                        .onMove { girdiler.move(fromOffsets: $0, toOffset: $1) }
                    Button { kaynakSec = true } label: {
                        Label(girdiler.isEmpty ? "Dosya seç" : "Dosya ekle", systemImage: "plus.circle")
                    }
                } header: {
                    Text(girdiBasligi)
                } footer: {
                    if arac.girdi == .cokPDF || girdiler.count > 1 { Text("Sırayı değiştirmek için basılı tutup sürükleyin.") }
                }
            }

            secenekler()

            if !sonuclar.isEmpty || !kayitli.isEmpty { sonucBolumu }
        }
        .environment(\.editMode, .constant(girdiler.count > 1 && !calisiyor ? .active : .inactive))
        .navigationTitle(arac.ad)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Kapat") { gorev?.cancel(); kapat() } }
        }
        .safeAreaInset(edge: .bottom) { baslatDugmesi }
        .overlay { if calisiyor { CalisiyorKatmani(metin: durum.metin, oran: durum.oran) } }
        .iletiGoster($ileti)
        .kaynakSecici(isPresented: $kaynakSec, girdi: arac.girdi) { girdiler.append(contentsOf: $0) }
        .sheet(item: Binding(get: { paylasilacak.map { PaylasimIstegi(urller: $0) } }, set: { paylasilacak = $0?.urller })) {
            PaylasimSayfasi(ogeler: $0.urller)
        }
    }

    private var girdiBasligi: String {
        switch arac.girdi {
        case .gorseller: "Görseller"
        case .dosyalar: "Dosyalar"
        case .cokPDF: "PDF'ler (en az 2)"
        default: girdiler.count > 1 ? "PDF'ler" : "PDF"
        }
    }

    private var baslatDugmesi: some View {
        Button {
            baslat()
        } label: {
            Label(sonuclar.isEmpty && kayitli.isEmpty ? "Başlat" : "Yeniden çalıştır", systemImage: "play.fill")
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!girdiYeterli || !hazir || calisiyor)
        .padding()
        .background(.bar)
    }

    @ViewBuilder private var sonucBolumu: some View {
        Section {
            if kitapligaKaydet {
                ForEach(kayitli) { o in
                    HStack {
                        KucukResimGorunumu(oge: o, boyut: 36)
                        VStack(alignment: .leading) {
                            Text(o.tamAd).lineLimit(2)
                            Text(boyutKarsilastirma(o)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            if o.pdfMi {
                                Button { kapat(); yon.ac(o) } label: { Label("Aç", systemImage: "doc.text") }
                            }
                            Button { paylasilacak = [o.url] } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                            if o.pdfMi {
                                Menu {
                                    ForEach(AracKatalogu.pdfAraclari.filter { $0.id != arac.id }) { a in
                                        Button { zincirle(a, o) } label: { Label(a.ad, systemImage: a.simge) }
                                    }
                                } label: { Label("Sıradaki araç", systemImage: "arrow.right.circle") }
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    }
                }
            } else {
                ForEach(sonuclar, id: \.self) { u in Text(u.lastPathComponent) }
            }
            if (kitapligaKaydet ? kayitli.count : sonuclar.count) > 1 {
                Button { paylasilacak = kitapligaKaydet ? kayitli.map(\.url) : sonuclar } label: {
                    Label("Hepsini paylaş", systemImage: "square.and.arrow.up.on.square")
                }
            }
        } header: {
            Text("Sonuç")
        } footer: {
            Text(kitapligaKaydet ? "Kitaplığa kaydedildi · \(String(format: "%.1f", sure)) sn" : String(format: "%.1f sn", sure))
        }
    }

    private func boyutKarsilastirma(_ o: KitaplikOgesi) -> String {
        let girdiBoyu = girdiler.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard girdiBoyu > 0, girdiler.count == 1 else { return BicimYardimci.boyut(o.boyut) }
        let oran = Double(o.boyut) / Double(girdiBoyu)
        let fark = oran < 1 ? " (%\(Int((1 - oran) * 100)) küçüldü)" : ""
        return "\(BicimYardimci.boyut(girdiBoyu)) → \(BicimYardimci.boyut(o.boyut))\(fark)"
    }

    private func baslat() {
        calisiyor = true
        durum.oran = nil
        durum.metin = "\(arac.ad)…"
        let bas = Date()
        let girdiler = girdiler
        gorev = Task {
            defer { calisiyor = false }
            do {
                let cikti = try await calistir(girdiler, durum.bildirim)
                try Task.checkCancellation()
                sonuclar = cikti
                if kitapligaKaydet {
                    var yeni: [KitaplikOgesi] = []
                    for u in cikti {
                        yeni.append(try await kitaplik.ciktiKaydet(u, ad: u.deletingPathExtension().lastPathComponent,
                                                                   klasor: ciktiKlasoru, kaynak: girdiler.first))
                    }
                    kayitli = yeni
                }
                sure = Date().timeIntervalSince(bas)
            } catch is CancellationError {
            } catch KagitHata.iptal {
            } catch {
                ileti = Ileti(error)
            }
        }
    }

    private func zincirle(_ a: Arac, _ o: KitaplikOgesi) {
        kapat()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            yon.aracAc(a, girdiler: [o.url])
        }
    }
}

/// Girdi satırı: ad, boyut ve (PDF ise) sayfa sayısı.
struct GirdiSatiri: View {
    let url: URL
    @State private var ayrinti = ""

    var body: some View {
        HStack {
            Image(systemName: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc")
                .foregroundStyle(Tema.vurgu)
            VStack(alignment: .leading) {
                Text(url.lastPathComponent).lineLimit(2)
                Text(ayrinti).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            let u = url
            ayrinti = await Task.detached {
                let boy = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                var s = BicimYardimci.boyut(boy)
                if u.pathExtension.lowercased() == "pdf", let b = PDFDocument(url: u) {
                    s += b.isLocked ? " · parolalı" : " · \(b.pageCount) sayfa"
                }
                return s
            }.value
        }
    }
}

// MARK: - Seçenek bileşenleri

/// Sayfa aralığı alanı (boş = hepsi).
struct SayfaAraligiAlani: View {
    @Binding var metin: String
    var baslik = "Sayfalar"

    var body: some View {
        LabeledContent(baslik) {
            TextField("Hepsi (ör. 1-3, 5, tek)", text: $metin)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Kaynak seçici

extension View {
    /// Girdi türüne göre dosya seçme menüsü: Kitaplık, Dosyalar, Fotoğraflar.
    func kaynakSecici(isPresented: Binding<Bool>, girdi: GirdiTuru, secildi: @escaping ([URL]) -> Void) -> some View {
        modifier(KaynakSeciciDuzenleyici(acik: isPresented, girdi: girdi, secildi: secildi))
    }
}

private struct KaynakSeciciDuzenleyici: ViewModifier {
    @Binding var acik: Bool
    let girdi: GirdiTuru
    let secildi: ([URL]) -> Void
    @State private var kitaplikAcik = false
    @State private var dosyalarAcik = false
    @State private var fotoAcik = false
    @State private var fotoSecimi: [PhotosPickerItem] = []

    private var turler: [UTType] {
        switch girdi {
        case .gorseller: [.image]
        case .dosyalar(let t): t
        case .yok: []
        default: [.pdf]
        }
    }

    private var coklu: Bool { girdi != .tekPDF }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Dosya kaynağı", isPresented: $acik) {
                Button("Kâğıt kitaplığından") { kitaplikAcik = true }
                Button("Dosyalar uygulamasından") { dosyalarAcik = true }
                if turler.contains(where: { $0.conforms(to: .image) }) {
                    Button("Fotoğraflardan") { fotoAcik = true }
                }
            }
            .sheet(isPresented: $kitaplikAcik) {
                KitaplikSecici(turler: turler, coklu: coklu, secildi: secildi)
            }
            .fileImporter(isPresented: $dosyalarAcik, allowedContentTypes: turler, allowsMultipleSelection: coklu) { sonuc in
                guard case .success(let urller) = sonuc else { return }
                // Güvenlik kapsamlı URL'leri geçici kopyaya al (araç arka planda okuyabilsin)
                let klasor = Gecici.klasor()
                let kopyalar: [URL] = urller.compactMap { u in
                    let e = u.startAccessingSecurityScopedResource()
                    defer { if e { u.stopAccessingSecurityScopedResource() } }
                    let h = klasor.appendingPathComponent(u.lastPathComponent)
                    return (try? FileManager.default.copyItem(at: u, to: h)) != nil ? h : nil
                }
                secildi(kopyalar)
            }
            .photosPicker(isPresented: $fotoAcik, selection: $fotoSecimi, matching: .images)
            .onChange(of: fotoSecimi) { _, yeni in
                guard !yeni.isEmpty else { return }
                Task {
                    secildi(await FotoAktarici.dosyalaraYaz(yeni))
                    fotoSecimi = []
                }
            }
    }
}

/// Kitaplıktan (türe göre süzülmüş) dosya seçimi.
struct KitaplikSecici: View {
    let turler: [UTType]
    let coklu: Bool
    let secildi: ([URL]) -> Void
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.dismiss) private var kapat
    @State private var secili: [String] = []
    @State private var arama = ""

    private var adaylar: [KitaplikOgesi] {
        let hepsi = arama.isEmpty ? kitaplik.belgeler.sorted { $0.degistirilme > $1.degistirilme } : kitaplik.ara(arama)
        return hepsi.filter { o in !o.klasorMu && turler.contains { t in o.tur?.conforms(to: t) ?? false } }
    }

    var body: some View {
        NavigationStack {
            List(adaylar) { o in
                Button {
                    if !coklu { secildi([o.url]); kapat(); return }
                    if let i = secili.firstIndex(of: o.yol) { secili.remove(at: i) } else { secili.append(o.yol) }
                } label: {
                    HStack {
                        SatirHucresi(oge: o, secili: coklu ? secili.contains(o.yol) : nil)
                        if let i = secili.firstIndex(of: o.yol) {
                            Text("\(i + 1)").font(.caption.bold()).padding(6).background(Circle().fill(Tema.vurgu.opacity(0.15)))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $arama)
            .overlay { if adaylar.isEmpty { ContentUnavailableView("Uygun dosya yok", systemImage: "doc") } }
            .navigationTitle("Kitaplıktan seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                if coklu {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle (\(secili.count))") {
                            secildi(secili.compactMap { kitaplik.oge(yol: $0)?.url })
                            kapat()
                        }
                        .disabled(secili.isEmpty)
                    }
                }
            }
        }
    }
}
