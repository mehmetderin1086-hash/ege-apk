import SwiftUI

struct GorselEkrani: View {
    var baslangicIstemi = ""
    var otomatikBaslat = false
    @AppStorage("ayar.gorselModeli") private var sonModel = ""
    @Environment(\.dismiss) private var kapat
    @State private var istem = ""
    @State private var model = ""
    @State private var sonuc: UIImage?
    @State private var hata: String?
    @State private var calisiyor = false
    @State private var islem: Task<Void, Never>?
    @State private var baslatildi = false
    private var modeller: [TelefonProxy.Model] { TelefonProxy.ortak.modeller.filter(\.gorselUretir) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Görseli anlat") {
                    TextField("Örneğin: uzayda yüzen bir kütüphane, suluboya", text: $istem, axis: .vertical).lineLimit(3...8)
                    Picker("Görsel modeli", selection: $model) {
                        Text("Model seç").tag("")
                        ForEach(modeller) { Text($0.id).tag($0.id) }
                    }
                    if modeller.isEmpty { Text("CLIProxy'de bir görsel modeli listelenmiyor. Önce Ayarlar'dan bağlantıyı sına.").font(.footnote) }
                    Button(calisiyor ? "Üretiliyor…" : "Görsel üret") {
                        islem = Task { await uret() }
                    }.disabled(calisiyor || model.isEmpty || istem.trimmingCharacters(in: .whitespaces).isEmpty)
                    if calisiyor { ProgressView("Görsel hazırlanıyor; birkaç dakika sürebilir.") }
                    if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                }
                if let sonuc {
                    Section("Sonuç") {
                        Image(uiImage: sonuc).resizable().scaledToFit()
                        ShareLink(item: Image(uiImage: sonuc), preview: SharePreview("Asistan görseli", image: Image(uiImage: sonuc))) {
                            Label("Paylaş veya kaydet", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }.navigationTitle("Görsel üret")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { islem?.cancel(); kapat() } } }
                .onDisappear { islem?.cancel() }
                .task {
                    guard !baslatildi else { return }
                    baslatildi = true
                    istem = baslangicIstemi
                    if TelefonProxy.ortak.modeller.isEmpty { await TelefonProxy.ortak.sina() }
                    guard !Task.isCancelled else { return }
                    model = modeller.first(where: { $0.id == sonModel })?.id
                        ?? modeller.first(where: { $0.id == "gemini-3-pro-image" })?.id
                        ?? modeller.first?.id ?? ""
                    if otomatikBaslat, !model.isEmpty, !istem.isEmpty { await uret() }
                }
        }
    }

    private func uret() async {
        calisiyor = true; hata = nil
        sonModel = model
        defer { calisiyor = false }
        do {
            sonuc = try await GorselUretici.uret(model: model, istem: istem)
        } catch {
            if !Task.isCancelled { hata = error.localizedDescription }
        }
    }
}
