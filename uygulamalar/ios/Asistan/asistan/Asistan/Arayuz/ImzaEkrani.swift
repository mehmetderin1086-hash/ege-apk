import SwiftUI
import PencilKit

/// P2.12: Kullanıcının el imzası. Bir kez çizilir; pdfIslem 'imzala' yalnız önizleme onaylanınca kullanır.
/// Saydam PNG: Application Support/Imza/imza.png (tam dosya koruması, yedeğe girmez).
nonisolated enum ImzaDeposu {
    static var dosya: URL {
        let k = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return k.appendingPathComponent("Imza", isDirectory: true).appendingPathComponent("imza.png")
    }

    nonisolated enum Hata: LocalizedError {
        case bos
        var errorDescription: String? { "İmza boş; önce çiz." }
    }

    /// Çizimi saydam PNG'ye çevirir (kenarda 8 pt pay, 3x). Açık görünümde çizilir: koyu kipte siyah mürekkep beyaza dönmesin.
    static func png(_ d: PKDrawing) -> Data? {
        guard !d.strokes.isEmpty, !d.bounds.isEmpty else { return nil }
        var veri: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            veri = d.image(from: d.bounds.insetBy(dx: -8, dy: -8), scale: 3).pngData()
        }
        return veri
    }

    static func kaydet(_ d: PKDrawing, dosya: URL = ImzaDeposu.dosya) throws {
        guard let veri = png(d) else { throw Hata.bos }
        try kaydet(png: veri, dosya: dosya)
    }

    static func kaydet(png veri: Data, dosya: URL = ImzaDeposu.dosya) throws {
        try FileManager.default.createDirectory(at: dosya.deletingLastPathComponent(), withIntermediateDirectories: true)
        try veri.write(to: dosya, options: [.atomic, .completeFileProtection])
        var u = dosya
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        try? u.setResourceValues(d)
    }

    static func yukle(dosya: URL = ImzaDeposu.dosya) -> CGImage? {
        guard let v = try? Data(contentsOf: dosya) else { return nil }
        return UIImage(data: v)?.cgImage
    }

    static func varMi(dosya: URL = ImzaDeposu.dosya) -> Bool { FileManager.default.fileExists(atPath: dosya.path) }

    static func sil(dosya: URL = ImzaDeposu.dosya) { try? FileManager.default.removeItem(at: dosya) }
}

/// Ayarlar → İmzam: imzayı parmakla ya da kalemle çiz, kaydet, sil.
struct ImzaEkrani: View {
    @State private var cizim = PKDrawing()
    @State private var kayitli: UIImage?
    @State private var hata: String?

    var body: some View {
        Form {
            Section {
                ImzaTuvali(cizim: $cizim)
                    .frame(height: 220)
                    .background(Color.white, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel("İmza tuvali").accessibilityIdentifier("imza-tuval")
                HStack {
                    Button("Temizle", systemImage: "eraser") { cizim = PKDrawing() }
                        .disabled(cizim.strokes.isEmpty)
                        .accessibilityIdentifier("imza-temizle")
                    Spacer()
                    Button("Kaydet", systemImage: "checkmark") { kaydet() }
                        .buttonStyle(.borderedProminent)
                        .disabled(cizim.strokes.isEmpty)
                        .accessibilityIdentifier("imza-kaydet")
                }
                .buttonStyle(.bordered)
            } header: { Text("İmzanı çiz") } footer: {
                Text("İmza yalnız bu telefonda saklanır. PDF'ye eklemeden önce her seferinde önizleme gösterilir ve onayın istenir; eklenen imza sayfaya kalıcı olarak işlenir.")
            }
            if let kayitli {
                Section("Kayıtlı imza") {
                    Image(uiImage: kayitli).resizable().scaledToFit().frame(maxHeight: 120)
                        .padding(8).frame(maxWidth: .infinity).background(Color.white, in: .rect(cornerRadius: 8))
                        .accessibilityLabel("Kayıtlı imza").accessibilityIdentifier("imza-kayitli")
                    Button("İmzayı sil", systemImage: "trash", role: .destructive) {
                        ImzaDeposu.sil(); self.kayitli = nil
                        TostDefteri.ortak.goster("İmza silindi", simge: "trash")
                    }
                    .accessibilityIdentifier("imza-sil")
                }
            }
            if let hata { Section { Text(hata).foregroundStyle(.red) } }
        }
        .navigationTitle("İmzam")
        .navigationBarTitleDisplayMode(.inline)
        .task { kayitli = ImzaDeposu.yukle().map { UIImage(cgImage: $0) } }
    }

    private func kaydet() {
        do {
            try ImzaDeposu.kaydet(cizim)
            kayitli = ImzaDeposu.yukle().map { UIImage(cgImage: $0) }
            cizim = PKDrawing(); hata = nil
            TostDefteri.ortak.goster("İmza kaydedildi", simge: "signature")
        } catch { hata = error.localizedDescription }
    }
}

/// PencilKit tuvali: siyah 3 pt kalem, parmakla da çizilir, açık görünüm (beyaz zemin üstünde siyah mürekkep).
private struct ImzaTuvali: UIViewRepresentable {
    @Binding var cizim: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.overrideUserInterfaceStyle = .light
        v.backgroundColor = .clear; v.isOpaque = false
        v.drawingPolicy = .anyInput
        v.tool = PKInkingTool(.pen, color: .black, width: 3)
        v.isScrollEnabled = false
        v.drawing = cizim
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ v: PKCanvasView, context: Context) { if v.drawing != cizim { v.drawing = cizim } }
    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, PKCanvasViewDelegate {
        let ana: ImzaTuvali
        init(_ ana: ImzaTuvali) { self.ana = ana }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { ana.cizim = canvasView.drawing }
    }
}

/// Önizlemeli onay (imza): imzalı sayfanın görseli, ayrıntı ve İmzala / Vazgeç. Sohbet ve Live ekranı ortak kullanır.
struct ImzaOnizlemeSayfasi: View {
    let istek: OnayKapisi.Istek
    let yanit: (Bool) -> Void
    @State private var gorsel: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let gorsel {
                        Image(uiImage: gorsel).resizable().scaledToFit()
                            .background(Color.white)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                            .accessibilityLabel("İmzalı sayfanın önizlemesi").accessibilityIdentifier("imza-onizleme")
                    } else {
                        ContentUnavailableView("Önizleme yüklenemedi", systemImage: "doc.questionmark")
                    }
                    Text(istek.ayrinti).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("İmza sayfaya kalıcı olarak işlenir; özgün dosya değişmez, yeni bir PDF oluşturulur.")
                        .font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Vazgeç", role: .cancel) { yanit(false) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("imza-vazgec")
                    Button("İmzala") { yanit(true) }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("imza-onay")
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .navigationTitle(istek.baslik)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if let url = istek.onizleme { gorsel = await GorselOnbellegi.tamBoy(url) }
        }
    }
}
