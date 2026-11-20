import KagitKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Dosyalar sekmesi: klasör gezintisi, arama, çoklu seçim ve toplu işlemler.
struct DosyalarGorunumu: View {
    @State private var yol: [String] = []

    var body: some View {
        NavigationStack(path: $yol) {
            KlasorGorunumu(klasor: "")
                .navigationDestination(for: String.self) { k in
                    switch k {
                    case "#yildiz": OzelListe(tur: .yildiz)
                    case "#cop": CopKutusu()
                    default:
                        if k.hasPrefix("#etiket:") { OzelListe(tur: .etiket(String(k.dropFirst(8)))) }
                        else { KlasorGorunumu(klasor: k) }
                    }
                }
        }
    }
}

/// Bir klasörün içeriği.
struct KlasorGorunumu: View {
    let klasor: String
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @AppStorage("dosyalar.izgara") private var izgara = false
    @AppStorage("dosyalar.siralama") private var siralama: Siralama = .tarih
    @State private var arama = ""
    @State private var secimKipi = false
    @State private var secili = Set<String>()
    @State private var yeniKlasorSor = false
    @State private var yeniAd = ""
    @State private var dosyaSec = false
    @State private var fotoSecimi: [PhotosPickerItem] = []
    @State private var fotoSec = false
    @State private var tasinacak: [KitaplikOgesi]?
    @State private var adlandirilacak: KitaplikOgesi?
    @State private var etiketlenecek: KitaplikOgesi?
    @State private var onizlenecek: KitaplikOgesi?
    @State private var paylasilacak: [URL]?
    @State private var topluArac = false
    @State private var ileti: Ileti?

    private var gosterilen: [KitaplikOgesi] {
        arama.isEmpty ? kitaplik.icerik(klasor, siralama: siralama) : kitaplik.ara(arama)
    }

    private var seciliOgeler: [KitaplikOgesi] { gosterilen.filter { secili.contains($0.yol) } }

    var body: some View {
        Group {
            if gosterilen.isEmpty && klasor.isEmpty && arama.isEmpty {
                BosKitaplik(dosyaSec: $dosyaSec)
            } else if izgara {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16)], spacing: 18) {
                        ForEach(gosterilen) { o in hucre(o) }
                    }
                    .padding()
                    if klasor.isEmpty && arama.isEmpty { ozelBaglantilar.padding(.horizontal) }
                }
            } else {
                List {
                    if klasor.isEmpty && arama.isEmpty && !secimKipi { Section { ozelBaglantilar } }
                    Section {
                        ForEach(gosterilen) { o in hucre(o) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(klasor.isEmpty ? "Dosyalar" : (klasor as NSString).lastPathComponent)
        .searchable(text: $arama, prompt: "Dosyalarda ara")
        .refreshable { await kitaplik.tara() }
        .toolbar { araclar }
        .safeAreaInset(edge: .bottom) { if secimKipi { secimCubugu } }
        .alert("Yeni klasör", isPresented: $yeniKlasorSor) {
            TextField("Klasör adı", text: $yeniAd)
            Button("Oluştur") { Task { await calistir { _ = try await kitaplik.yeniKlasor(yeniAd, ust: klasor) } } }
            Button("Vazgeç", role: .cancel) {}
        }
        .fileImporter(isPresented: $dosyaSec, allowedContentTypes: [.item], allowsMultipleSelection: true) { sonuc in
            if case .success(let urller) = sonuc {
                Task { await calistir { try await kitaplik.iceAktar(urller, klasor: klasor) } }
            }
        }
        .photosPicker(isPresented: $fotoSec, selection: $fotoSecimi, matching: .images)
        .onChange(of: fotoSecimi) { _, yeni in
            guard !yeni.isEmpty else { return }
            Task {
                let urller = await FotoAktarici.dosyalaraYaz(yeni)
                fotoSecimi = []
                if let a = AracKatalogu.bul("gorseldenPDF") { yon.aracAc(a, girdiler: urller) }
            }
        }
        .sheet(item: Binding(get: { tasinacak.map { TasimaIstegi(ogeler: $0) } }, set: { tasinacak = $0?.ogeler })) { istek in
            KlasorSecici(baslik: "Taşı") { hedef in
                Task { await calistir { try await kitaplik.tasi(istek.ogeler, klasor: hedef) } }
                secimKipi = false; secili = []
            }
        }
        .sheet(item: $adlandirilacak) { o in
            AdlandirmaSayfasi(oge: o) { ad in Task { await calistir { try await kitaplik.yenidenAdlandir(o, ad) } } }
        }
        .sheet(item: $etiketlenecek) { o in EtiketSayfasi(oge: o) }
        .sheet(item: $onizlenecek) { o in OnizlemeSayfasi(oge: o) }
        .sheet(item: Binding(get: { paylasilacak.map { PaylasimIstegi(urller: $0) } }, set: { paylasilacak = $0?.urller })) { p in
            PaylasimSayfasi(ogeler: p.urller)
        }
        .sheet(isPresented: $topluArac) {
            NavigationStack { TopluAracSecici(girdiler: seciliOgeler.filter(\.pdfMi).map(\.url)) }
        }
        .iletiGoster($ileti)
    }

    // MARK: Hücre

    @ViewBuilder private func hucre(_ o: KitaplikOgesi) -> some View {
        let secim = Button {
            if secimKipi {
                if secili.contains(o.yol) { secili.remove(o.yol) } else { secili.insert(o.yol) }
            } else {
                ac(o)
            }
        } label: {
            if izgara { IzgaraHucresi(oge: o, secili: secimKipi ? secili.contains(o.yol) : nil) }
            else { SatirHucresi(oge: o, secili: secimKipi ? secili.contains(o.yol) : nil) }
        }
        .buttonStyle(.plain)
        .contextMenu { baglamMenusu(o) }

        if o.klasorMu && !secimKipi {
            NavigationLink(value: o.yol) {
                if izgara { IzgaraHucresi(oge: o, secili: nil) } else { SatirHucresi(oge: o, secili: nil) }
            }
            .buttonStyle(.plain)
            .contextMenu { baglamMenusu(o) }
        } else {
            secim
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await calistir { try await kitaplik.copeAt([o]) } } } label: {
                        Label("Çöpe at", systemImage: "trash")
                    }
                    Button { adlandirilacak = o } label: { Label("Ad", systemImage: "pencil") }.tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button { kitaplik.yildizDegistir(o) } label: { Label("Yıldız", systemImage: "star") }.tint(.yellow)
                }
        }
    }

    @ViewBuilder private func baglamMenusu(_ o: KitaplikOgesi) -> some View {
        if !o.klasorMu {
            Button { ac(o) } label: { Label("Aç", systemImage: "doc.text") }
            Button { paylasilacak = [o.url] } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
        }
        Button { adlandirilacak = o } label: { Label("Yeniden adlandır", systemImage: "pencil") }
        if !o.klasorMu {
            Button { kitaplik.yildizDegistir(o) } label: {
                Label(kitaplik.bilgi(o).yildiz ? "Yıldızı kaldır" : "Yıldızla", systemImage: "star")
            }
            Button { etiketlenecek = o } label: { Label("Etiketler", systemImage: "tag") }
            Button { Task { await calistir { _ = try await kitaplik.kopyala(o) } } } label: {
                Label("Çoğalt", systemImage: "plus.square.on.square")
            }
        }
        Button { tasinacak = [o] } label: { Label("Taşı", systemImage: "folder") }
        if o.pdfMi {
            Menu {
                ForEach(AracKatalogu.pdfAraclari) { a in
                    Button { yon.aracAc(a, girdiler: [o.url]) } label: { Label(a.ad, systemImage: a.simge) }
                }
            } label: { Label("Araçla aç", systemImage: "wrench.and.screwdriver") }
        } else if !o.klasorMu {
            Button { yon.aracAc(id: o.gorselMi ? "gorseldenPDF" : "belgedenPDF", girdiler: [o.url]) } label: {
                Label("PDF'e dönüştür", systemImage: "doc.badge.arrow.up")
            }
        }
        Divider()
        Button(role: .destructive) { Task { await calistir { try await kitaplik.copeAt([o]) } } } label: {
            Label("Çöpe at", systemImage: "trash")
        }
    }

    private var ozelBaglantilar: some View {
        Group {
            NavigationLink(value: "#yildiz") { Label("Yıldızlılar", systemImage: "star.fill").foregroundStyle(.primary) }
            ForEach(kitaplik.tumEtiketler, id: \.self) { e in
                NavigationLink(value: "#etiket:\(e)") { Label(e, systemImage: "tag.fill").foregroundStyle(.primary) }
            }
            NavigationLink(value: "#cop") {
                Label("Çöp Kutusu (\(kitaplik.copOgeleri.count))", systemImage: "trash").foregroundStyle(.primary)
            }
        }
    }

    // MARK: Araç çubuğu

    @ToolbarContentBuilder private var araclar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if secimKipi {
                Button("Bitti") { secimKipi = false; secili = [] }
            } else {
                Menu {
                    Button { yeniAd = "Yeni klasör"; yeniKlasorSor = true } label: { Label("Yeni klasör", systemImage: "folder.badge.plus") }
                    Button { dosyaSec = true } label: { Label("Dosyalar'dan al", systemImage: "folder") }
                    Button { fotoSec = true } label: { Label("Fotoğraflardan PDF", systemImage: "photo") }
                    Button { yon.taramaAcik = true } label: { Label("Belge tara", systemImage: "doc.viewfinder") }
                    Button { yon.aracAc(id: "bosPDF") } label: { Label("Boş PDF", systemImage: "doc.badge.plus") }
                } label: { Image(systemName: "plus") }
                Menu {
                    Button { secimKipi = true } label: { Label("Seç", systemImage: "checkmark.circle") }
                    Picker("Görünüm", selection: $izgara) {
                        Label("Liste", systemImage: "list.bullet").tag(false)
                        Label("Izgara", systemImage: "square.grid.2x2").tag(true)
                    }
                    Picker("Sırala", selection: $siralama) {
                        ForEach(Siralama.allCases) { s in Text(s.baslik).tag(s) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var secimCubugu: some View {
        let s = seciliOgeler
        let pdfler = s.filter(\.pdfMi)
        return HStack(spacing: 20) {
            Button { secili = secili.count == gosterilen.count ? [] : Set(gosterilen.map(\.yol)) } label: {
                Text(secili.count == gosterilen.count ? "Hiçbiri" : "Tümü")
            }
            Spacer()
            Button { paylasilacak = s.filter { !$0.klasorMu }.map(\.url) } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(s.allSatisfy(\.klasorMu))
            Button { if let a = AracKatalogu.bul("birlestir") { yon.aracAc(a, girdiler: pdfler.map(\.url)) } } label: {
                Image(systemName: "rectangle.stack.badge.plus")
            }
            .disabled(pdfler.count < 2)
            Button { topluArac = true } label: { Image(systemName: "square.stack.3d.down.right") }
                .disabled(pdfler.isEmpty)
            Button { tasinacak = s } label: { Image(systemName: "folder") }.disabled(s.isEmpty)
            Button(role: .destructive) {
                Task { await calistir { try await kitaplik.copeAt(s) }; secili = [] }
            } label: { Image(systemName: "trash") }
            .disabled(s.isEmpty)
        }
        .font(.title3)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Eylemler

    private func ac(_ o: KitaplikOgesi) {
        if o.pdfMi { yon.ac(o) } else if !o.klasorMu { onizlenecek = o }
    }

    private func calistir(_ govde: () async throws -> Void) async {
        do { try await govde() } catch { ileti = Ileti(error) }
    }
}

// MARK: - Hücreler

struct SatirHucresi: View {
    let oge: KitaplikOgesi
    let secili: Bool?
    @Environment(Kitaplik.self) private var kitaplik

    var body: some View {
        HStack(spacing: 12) {
            if let secili {
                Image(systemName: secili ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(secili ? Tema.vurgu : .secondary).font(.title3)
            }
            KucukResimGorunumu(oge: oge, boyut: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(oge.klasorMu ? oge.ad : oge.tamAd).lineLimit(2)
                    if kitaplik.bilgi(oge).yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text(altBilgi).font(.caption).foregroundStyle(.secondary)
                let etiketler = kitaplik.bilgi(oge).etiketler
                if !etiketler.isEmpty {
                    Text(etiketler.joined(separator: " · ")).font(.caption2).foregroundStyle(Tema.vurgu)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var altBilgi: String {
        if oge.klasorMu {
            let n = kitaplik.icerik(oge.yol).count
            return "\(n) öge"
        }
        return "\(oge.degistirilme.formatted(date: .abbreviated, time: .shortened)) · \(BicimYardimci.boyut(oge.boyut))"
    }
}

struct IzgaraHucresi: View {
    let oge: KitaplikOgesi
    let secili: Bool?

    var body: some View {
        VStack(spacing: 6) {
            KucukResimGorunumu(oge: oge, boyut: 84)
                .overlay(alignment: .topTrailing) {
                    if let secili {
                        Image(systemName: secili ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(secili ? Tema.vurgu : .secondary)
                            .background(Circle().fill(.background))
                    }
                }
            Text(oge.ad).font(.caption).lineLimit(2).multilineTextAlignment(.center)
        }
        .contentShape(Rectangle())
    }
}

struct BosKitaplik: View {
    @Binding var dosyaSec: Bool
    @Environment(Yonlendirici.self) private var yon

    var body: some View {
        ContentUnavailableView {
            Label("Kitaplık boş", systemImage: "doc.on.doc")
        } description: {
            Text("PDF'lerini Dosyalar'dan al, belge tara ya da Paylaş menüsünden Kâğıt'a gönder.")
        } actions: {
            Button("Dosyalar'dan al") { dosyaSec = true }.buttonStyle(.borderedProminent)
            Button("Belge tara") { yon.taramaAcik = true }
        }
    }
}

// MARK: - Özel listeler

struct OzelListe: View {
    enum Tur { case yildiz, etiket(String) }
    let tur: Tur
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon

    var body: some View {
        let ogeler: [KitaplikOgesi] = switch tur {
        case .yildiz: kitaplik.yildizlilar
        case .etiket(let e): kitaplik.etiketli(e)
        }
        List(ogeler) { o in
            Button { if o.pdfMi { yon.ac(o) } } label: { SatirHucresi(oge: o, secili: nil) }.buttonStyle(.plain)
        }
        .overlay { if ogeler.isEmpty { ContentUnavailableView("Boş", systemImage: "tray") } }
        .navigationTitle({ if case .etiket(let e) = tur { return e } else { return "Yıldızlılar" } }())
    }
}

struct CopKutusu: View {
    @Environment(Kitaplik.self) private var kitaplik
    @State private var bosaltSor = false

    var body: some View {
        List(kitaplik.copOgeleri) { o in
            SatirHucresi(oge: o, secili: nil)
                .swipeActions {
                    Button { Task { try? await kitaplik.copGeriAl(o) } } label: { Label("Geri al", systemImage: "arrow.uturn.backward") }
                        .tint(.blue)
                }
        }
        .overlay { if kitaplik.copOgeleri.isEmpty { ContentUnavailableView("Çöp kutusu boş", systemImage: "trash") } }
        .navigationTitle("Çöp Kutusu")
        .toolbar {
            Button("Boşalt", role: .destructive) { bosaltSor = true }.disabled(kitaplik.copOgeleri.isEmpty)
        }
        .confirmationDialog("Çöp kutusundaki her şey kalıcı olarak silinecek.", isPresented: $bosaltSor, titleVisibility: .visible) {
            Button("Kalıcı olarak sil", role: .destructive) { Task { await kitaplik.copuBosalt() } }
        }
        .task { await kitaplik.copuBosalt(gun: 30) }
    }
}

// MARK: - Yardımcı sayfalar

struct TasimaIstegi: Identifiable { let id = UUID(); let ogeler: [KitaplikOgesi] }
struct PaylasimIstegi: Identifiable { let id = UUID(); let urller: [URL] }

/// Hedef klasör seçimi.
struct KlasorSecici: View {
    let baslik: String
    let secildi: (String) -> Void
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            List {
                Button { secildi(""); kapat() } label: { Label("Kâğıt (kök)", systemImage: "house") }
                ForEach(kitaplik.klasorler.sorted { $0.yol.localizedStandardCompare($1.yol) == .orderedAscending }) { k in
                    Button { secildi(k.yol); kapat() } label: {
                        Label(k.yol, systemImage: "folder").padding(.leading, CGFloat(k.yol.filter { $0 == "/" }.count) * 14)
                    }
                }
            }
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AdlandirmaSayfasi: View {
    let oge: KitaplikOgesi
    let kaydet: (String) -> Void
    @State private var ad = ""
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            Form { TextField("Ad", text: $ad).submitLabel(.done).onSubmit { tamam() } }
                .navigationTitle("Yeniden adlandır")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { tamam() }.disabled(ad.isEmpty) }
                }
                .onAppear { ad = oge.ad }
        }
        .presentationDetents([.height(200)])
    }

    private func tamam() { kaydet(ad); kapat() }
}

struct EtiketSayfasi: View {
    let oge: KitaplikOgesi
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.dismiss) private var kapat
    @State private var etiketler: [String] = []
    @State private var yeni = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Bu belgenin etiketleri") {
                    ForEach(etiketler, id: \.self) { Text($0) }
                        .onDelete { etiketler.remove(atOffsets: $0) }
                    HStack {
                        TextField("Yeni etiket (ör. 9-A, Sınav)", text: $yeni).onSubmit(ekle)
                        Button("Ekle", action: ekle).disabled(yeni.isEmpty)
                    }
                }
                let digerleri = kitaplik.tumEtiketler.filter { !etiketler.contains($0) }
                if !digerleri.isEmpty {
                    Section("Önceki etiketler") {
                        ForEach(digerleri, id: \.self) { e in Button(e) { etiketler.append(e) } }
                    }
                }
            }
            .navigationTitle(oge.ad)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { kitaplik.etiketle(oge, etiketler); kapat() }
                }
            }
            .onAppear { etiketler = kitaplik.bilgi(oge).etiketler }
        }
    }

    private func ekle() {
        let e = yeni.trimmingCharacters(in: .whitespaces)
        if !e.isEmpty, !etiketler.contains(e) { etiketler.append(e) }
        yeni = ""
    }
}

/// PDF olmayan dosyaların önizlemesi + PDF'e dönüştürme kısayolu.
struct OnizlemeSayfasi: View {
    let oge: KitaplikOgesi
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            HizliBakis(url: oge.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(oge.tamAd)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button("PDF'e dönüştür") {
                            kapat()
                            yon.aracAc(id: oge.gorselMi ? "gorseldenPDF" : "belgedenPDF", girdiler: [oge.url])
                        }
                    }
                }
        }
    }
}

/// Sistem paylaşım sayfası.
struct PaylasimSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
    }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

/// Fotoğraflar seçimini geçici JPEG dosyalarına yazar.
enum FotoAktarici {
    static func dosyalaraYaz(_ secim: [PhotosPickerItem]) async -> [URL] {
        let klasor = Gecici.klasor()
        var sonuc: [URL] = []
        for (i, oge) in secim.enumerated() {
            guard let veri = try? await oge.loadTransferable(type: Data.self) else { continue }
            let uzanti = oge.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = klasor.appendingPathComponent(String(format: "Fotoğraf %03d", i + 1)).appendingPathExtension(uzanti)
            if (try? veri.write(to: url)) != nil { sonuc.append(url) }
        }
        return sonuc
    }
}
