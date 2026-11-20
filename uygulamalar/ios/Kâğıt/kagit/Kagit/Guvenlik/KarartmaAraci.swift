import KagitKit
import SwiftUI

/// Gerçek karartma aracı: arama tabanlı (sözcük, düzenli ifade, hazır desenler) + elle bölge çizme.
struct KarartmaEkrani: View {
    static let arac = Arac(id: "karart", ad: "Karart",
                           aciklama: "Gizli bilgiyi kalıcı olarak sil: sayfa görüntüye dönüşür, metin geri getirilemez.",
                           simge: "rectangle.and.pencil.and.ellipsis", kategori: .guvenlik, girdi: .tekPDF) {
        KarartmaEkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var terimler = ""
    @State private var duzenli = false
    @State private var duyarli = false
    @State private var desenler = Set<HazirDesen>()
    @State private var parola = ""
    @State private var dpi: CGFloat = 250
    @State private var ocrKatmani = true
    @State private var aciklamaSil = true
    @State private var ustVeriTemizle = true
    @State private var yerImiSil = true

    @State private var bulunan: [KarartmaBolgesi] = []
    @State private var arandi = false
    @State private var araniyor = false
    @State private var aramaHatasi: String?
    @State private var elle: [KarartmaBolgesi] = []
    @State private var elleAcik = false

    private var kurallar: [KarartmaKurali] {
        var k: [KarartmaKurali] = terimler.split(whereSeparator: { "\n;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { duzenli ? .duzenliIfade($0, buyukKucukDuyarli: duyarli) : .ifade($0, buyukKucukDuyarli: duyarli) }
        k += HazirDesen.allCases.filter { desenler.contains($0) }.map { .hazir($0) }
        return k
    }

    private var hazir: Bool { !kurallar.isEmpty || !elle.isEmpty }

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler, hazir: hazir) {
            Section {
                TextField("Karartılacak sözcük ya da ifadeler", text: $terimler, axis: .vertical)
                    .lineLimit(2...6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Toggle("Düzenli ifade", isOn: $duzenli)
                Toggle("Büyük/küçük harfe duyarlı", isOn: $duyarli)
            } header: {
                Text("Aranacak metin")
            } footer: {
                Text("Her satıra bir ifade yaz. Eşleşen metnin bulunduğu alan siyaha boyanır.")
            }
            Section {
                ForEach(HazirDesen.allCases) { d in
                    Toggle(d.ad, isOn: Binding(get: { desenler.contains(d) },
                                               set: { if $0 { desenler.insert(d) } else { desenler.remove(d) } }))
                }
            } header: {
                Text("Hazır desenler")
            } footer: {
                Text("T.C. kimlik no ve IBAN sağlama toplamıyla doğrulanır; rastgele rakam dizileri karartılmaz.")
            }
            Section {
                Button { elleAcik = true } label: {
                    Label(elle.isEmpty ? "Sayfada alan çiz…" : "Elle çizilen alanlar: \(elle.count)", systemImage: "pencil.and.scribble")
                }
                SecureField("Parola (dosya parolalıysa)", text: $parola)
            } header: {
                Text("Elle")
            }
            Section {
                Button { Task { await ara() } } label: {
                    HStack {
                        Label("Eşleşmeleri bul", systemImage: "magnifyingglass")
                        if araniyor { Spacer(); ProgressView() }
                    }
                }
                .disabled(kurallar.isEmpty || araniyor)
                if arandi {
                    if let aramaHatasi {
                        Text(aramaHatasi).font(.footnote).foregroundStyle(.red)
                    } else {
                        LabeledContent("Bulunan alan", value: "\(bulunan.count)")
                        LabeledContent("Etkilenen sayfa", value: sayfaOzeti)
                    }
                }
            } header: {
                Text("Önizleme")
            } footer: {
                Text("Taranmış sayfalarda eşleşme OCR ile bulunur; OCR bir sözcüğü yanlış okursa eşleşmeyebilir, sonucu mutlaka kontrol et.")
            }
            Section {
                Picker("Çözünürlük", selection: $dpi) {
                    Text("200 dpi (küçük)").tag(CGFloat(200))
                    Text("250 dpi").tag(CGFloat(250))
                    Text("300 dpi (keskin)").tag(CGFloat(300))
                }
                Toggle("Kalan metin için aranabilir katman", isOn: $ocrKatmani)
                Toggle("Diğer sayfalardaki açıklamaları sil", isOn: $aciklamaSil)
                Toggle("Yer imlerini sil", isOn: $yerImiSil)
                Toggle("Üst veriyi temizle (yazar, XMP…)", isOn: $ustVeriTemizle)
            } header: {
                Text("Seçenekler")
            } footer: {
                Text("Karartılan sayfalar görüntüye dönüştürülür: özgün metin, gizli katmanlar ve form değerleri dosyada kalmaz. Bu işlem geri alınamaz; özgün dosya korunur, sonuç yeni bir dosya olur.")
            }
        } calistir: { girdiler, ilerleme in
            guard let u = girdiler.first else { return [] }
            let p = parola.isEmpty ? nil : parola
            var s = KarartmaSecenekleri()
            s.dpi = dpi
            s.kalanMetinIcinOCR = ocrKatmani
            s.aciklamalariSil = aciklamaSil
            s.yerImleriniSil = yerImiSil
            s.ustVeriyiTemizle = ustVeriTemizle
            let veri = try await arkaplandaCalistir { try Data(contentsOf: u) }
            let (cikti, rapor) = try await Karartma.karart(veri: veri, parola: p, kurallar: kurallar,
                                                           elleBolgeler: elle, secenekler: s, ilerleme: ilerleme)
            guard rapor.karartilanBolge > 0 else { throw KagitHata.genel("Eşleşen metin bulunamadı; hiçbir şey karartılmadı.") }
            let h = Gecici.dosya("\(u.adSiz) (karartılmış).pdf")
            try Belge.yaz(cikti, h, parola: p)
            return [h]
        }
        .onChange(of: terimler) { _, _ in arandi = false }
        .onChange(of: desenler) { _, _ in arandi = false }
        .onChange(of: duzenli) { _, _ in arandi = false }
        .sheet(isPresented: $elleAcik) {
            if let u = baglam.girdiler.first {
                ElleKarartmaGorunumu(url: u, parola: parola.isEmpty ? nil : parola, otomatik: bulunan, elle: $elle)
            }
        }
    }

    private var sayfaOzeti: String {
        let s = Set(bulunan.map(\.sayfa)).sorted()
        guard !s.isEmpty else { return "—" }
        return SayfaAraligi.metin(s)
    }

    private func ara() async {
        guard let u = baglam.girdiler.first else { return }
        araniyor = true
        aramaHatasi = nil
        defer { araniyor = false; arandi = true }
        do {
            let veri = try await arkaplandaCalistir { try Data(contentsOf: u) }
            bulunan = try await Karartma.bul(veri: veri, parola: parola.isEmpty ? nil : parola, kurallar: kurallar)
        } catch {
            bulunan = []
            aramaHatasi = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Sayfa önizlemesi üzerinde sürükleyerek karartma alanı çizme.
struct ElleKarartmaGorunumu: View {
    let url: URL
    let parola: String?
    /// Arama ile bulunanlar (yalnız gösterilir).
    let otomatik: [KarartmaBolgesi]
    @Binding var elle: [KarartmaBolgesi]
    @Environment(\.dismiss) private var kapat

    @State private var sayfa = 0
    @State private var sayfaSayisi = 1
    @State private var goruntu: CGImage?
    @State private var ekranBoyutu = CGSize(width: 1, height: 1)
    @State private var hata: String?
    @State private var cizilen: (CGPoint, CGPoint)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    if let goruntu {
                        let alan = sigdir(ekranBoyutu, geo.size)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: goruntu, scale: 1)
                                .resizable().frame(width: alan.width, height: alan.height)
                                .border(Color.secondary.opacity(0.4))
                                .position(x: alan.midX, y: alan.midY)
                            ForEach(otomatik.filter { $0.sayfa == sayfa }) { b in
                                let r = ekranaCevir(b.kutu, alan)
                                Rectangle().fill(Color.orange.opacity(0.45))
                                    .overlay(Rectangle().stroke(Color.orange, lineWidth: 1))
                                    .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                                    .allowsHitTesting(false)
                            }
                            ForEach(elle.filter { $0.sayfa == sayfa }) { b in
                                let r = ekranaCevir(b.kutu, alan)
                                Rectangle().fill(Color.black.opacity(0.85))
                                    .overlay(Rectangle().stroke(Tema.vurgu, lineWidth: 1.5))
                                    .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                                    .onTapGesture { elle.removeAll { $0.id == b.id } }
                                    .accessibilityLabel("Karartma alanı, silmek için dokun")
                            }
                            if let c = cizilen {
                                let r = CGRect(x: min(c.0.x, c.1.x), y: min(c.0.y, c.1.y),
                                               width: abs(c.0.x - c.1.x), height: abs(c.0.y - c.1.y))
                                Rectangle().fill(Color.black.opacity(0.5)).frame(width: r.width, height: r.height)
                                    .position(x: r.midX, y: r.midY).allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { v in
                                    cizilen = (sinirla(v.startLocation, alan), sinirla(v.location, alan))
                                }
                                .onEnded { v in
                                    cizilen = nil
                                    ekle(sinirla(v.startLocation, alan), sinirla(v.location, alan), alan)
                                }
                        )
                    } else if let hata {
                        ContentUnavailableView("Sayfa açılamadı", systemImage: "exclamationmark.triangle", description: Text(hata))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(12)
                Text("Karartılacak yeri parmağınla çerçeveleyerek seç. Turuncu alanlar aramanın bulduklarıdır. Siyah bir alanı silmek için ona dokun.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                HStack {
                    Button { sayfa -= 1 } label: { Image(systemName: "chevron.left") }.disabled(sayfa == 0)
                    Spacer()
                    Text("Sayfa \(sayfa + 1) / \(sayfaSayisi)").monospacedDigit()
                    Spacer()
                    Button { sayfa += 1 } label: { Image(systemName: "chevron.right") }.disabled(sayfa >= sayfaSayisi - 1)
                }
                .padding()
            }
            .navigationTitle("Alan çiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } }
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Son alanı geri al") { _ = elle.popLast() }.disabled(elle.isEmpty)
                        Button("Bu sayfadakileri temizle", role: .destructive) { elle.removeAll { $0.sayfa == sayfa } }
                        Button("Hepsini temizle", role: .destructive) { elle.removeAll() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task(id: sayfa) { await yukle() }
    }

    // MARK: - Geometri

    private func sigdir(_ resim: CGSize, _ kutu: CGSize) -> CGRect {
        guard resim.width > 0, resim.height > 0 else { return .zero }
        let o = min(kutu.width / resim.width, kutu.height / resim.height)
        let g = resim.width * o, y = resim.height * o
        return CGRect(x: (kutu.width - g) / 2, y: (kutu.height - y) / 2, width: g, height: y)
    }

    /// Sayfa noktası (sol alt köken) → görünüm dikdörtgeni.
    private func ekranaCevir(_ r: CGRect, _ alan: CGRect) -> CGRect {
        let sx = alan.width / ekranBoyutu.width, sy = alan.height / ekranBoyutu.height
        return CGRect(x: alan.minX + r.minX * sx, y: alan.minY + (ekranBoyutu.height - r.maxY) * sy,
                      width: r.width * sx, height: r.height * sy)
    }

    private func sinirla(_ p: CGPoint, _ alan: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, alan.minX), alan.maxX), y: min(max(p.y, alan.minY), alan.maxY))
    }

    private func ekle(_ a: CGPoint, _ b: CGPoint, _ alan: CGRect) {
        guard alan.width > 0 else { return }
        let sx = ekranBoyutu.width / alan.width, sy = ekranBoyutu.height / alan.height
        let x0 = (min(a.x, b.x) - alan.minX) * sx, x1 = (max(a.x, b.x) - alan.minX) * sx
        let y0 = (alan.maxY - max(a.y, b.y)) * sy, y1 = (alan.maxY - min(a.y, b.y)) * sy
        let kutu = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard kutu.width >= 4, kutu.height >= 4 else { return }
        elle.append(KarartmaBolgesi(sayfa: sayfa, kutu: kutu))
    }

    private func yukle() async {
        goruntu = nil
        hata = nil
        let u = url, p = parola, i = sayfa
        do {
            let (g, boyut, adet) = try await arkaplandaCalistir { () -> (CGImage, CGSize, Int) in
                let b = try Belge.ac(u, parola: p)
                guard let s = b.page(at: i), let g = PDFCizim.goruntu(s, dpi: 130) else { throw KagitHata.acilamadi(u.lastPathComponent) }
                return (g, Karartma.ekranBoyutu(s), b.pageCount)
            }
            guard !Task.isCancelled else { return }
            goruntu = g
            ekranBoyutu = boyut
            sayfaSayisi = adet
        } catch {
            hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
