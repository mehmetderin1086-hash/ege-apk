import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DosyalarEkrani: View {
    private let kutup = DosyaKitapligi.ortak
    @State private var sorgu = ""
    @State private var icerik = true
    @State private var klasorSec = false
    @State private var islem: Task<Void, Never>?
    @Environment(\.dismiss) private var kapat
    var body: some View {
        @Bindable var k = kutup
        NavigationStack {
            List {
                Section("Aranacak klasörler") {
                    ForEach(k.klasorler) { klasor in
                        HStack { Label(klasor.ad, systemImage: "folder"); Spacer(); Button(role: .destructive) { k.kaldir(klasor.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("\(klasor.ad) bağlantısını kaldır") }
                    }
                    Button { klasorSec = true } label: { Label("Klasör bağla", systemImage: "folder.badge.plus") }
                    Text("Dosyalar veya iCloud Drive’dan bir klasör seç. Seçtiğin klasör ve alt klasörleri aranır. Bağlantıyı kaldırmak dosyalarını silmez.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Dosya ve içerik ara") {
                    TextField("Dosya adı veya aranacak ifade", text: $sorgu).autocorrectionDisabled().onSubmit { ara() }
                    Toggle("Dosya içeriğinde de ara", isOn: $icerik)
                    Button(k.araniyor ? "Aranıyor…" : "Ara") { ara() }.disabled(k.araniyor || sorgu.trimmingCharacters(in: .whitespaces).count < 2)
                    if k.araniyor { Button("Aramayı durdur") { islem?.cancel(); k.durdur() }; ProgressView() }
                    Text("Arama telefonda yapılır. Sohbetten aradığında yalnız sonuç alıntıları, ‘oku/özetle’ istediğinde seçilen belgenin metni modele iletilir.").font(.footnote).foregroundStyle(.secondary)
                }
                if let hata = k.hata { Text(hata).foregroundStyle(.red) }
                Section("Sonuçlar · \(k.rapor.sonuclar.count)") {
                    ForEach(k.rapor.sonuclar) { sonuc in
                        Button {
                            do { try k.goster(sonuc.id.uuidString) } catch { k.hata = error.localizedDescription }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(sonuc.ad, systemImage: "doc.text").font(.headline)
                                Text(sonuc.yol).font(.caption).foregroundStyle(.secondary)
                                Text(sonuc.alinti).font(.subheadline).lineLimit(4).foregroundStyle(.primary)
                            }
                        }
                    }
                    if k.rapor.taranan > 0 { Text("\(k.rapor.taranan) dosya tarandı.").font(.footnote) }
                    ForEach(k.rapor.notlar, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Dosyalarım")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .fileImporter(isPresented: $klasorSec, allowedContentTypes: [.folder], allowsMultipleSelection: true) { sonuc in
                do { for url in try sonuc.get() { try k.bagla(url) } }
                catch { k.hata = error.localizedDescription }
            }
            .quickLookPreview($k.onizleme)
            .onChange(of: k.onizleme) { _, yeni in if yeni == nil { k.onizlemeyiKapat() } }
            .onDisappear { islem?.cancel(); k.onizlemeyiKapat() }
        }
    }
    private func ara() {
        islem?.cancel()
        islem = Task { do { _ = try await kutup.ara(sorgu, icerikte: icerik) } catch {} }
    }
}
