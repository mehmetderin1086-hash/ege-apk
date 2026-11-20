import SwiftUI
struct SunucuGorevEkrani: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @State private var tur = "text"
    @State private var ekleniyor = false
    @State private var gonderimKimligi = UUID()
    private let sunucu = SunucuGorevleri.ortak
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ana özellikler iPhone'da. Kodlama sunucudaki CLIProxy ile yapılır; Python standart kütüphane kodu izole ortamda sınanır. Diğer diller şu an çalıştırılmaz. Buraya verdiğin uzun işler mevcut sunucunda sürer; uygulamayı tekrar açıp sonucu görebilirsin. Görevler 7 gün saklanır. Bildirim gönderilmez. Sunucu web araştırması, CLIProxy desteklemezse mevcut OpenAI API hesabını kullanır; API kullanımı ücret doğurabilir.").font(.footnote)
                    if !ayarlar.sunucuGorevleri { Text("Sunucu görevleri Ayarlar'dan kapalı.").foregroundStyle(.orange) }
                    Picker("Görev", selection: $tur) {
                        Text("Metin / rapor").tag("text"); Text("Web araştırması").tag("research"); Text("Kodlama").tag("code")
                    }
                    TextField("Sunucuda hazırlanacak iş…", text: $metin, axis: .vertical).lineLimit(3...8)
                    Button(ekleniyor ? "Gönderiliyor…" : "Sunucuda başlat") {
                        ekleniyor = true
                        Task {
                            do { _ = try await sunucu.ekle(metin, tur: tur, id: gonderimKimligi); metin = ""; gonderimKimligi = UUID(); sunucu.hata = nil }
                            catch { sunucu.hata = error.localizedDescription }
                            ekleniyor = false
                        }
                    }.disabled(!ayarlar.sunucuGorevleri || ekleniyor || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || metin.count > 8000)
                    if let hata = sunucu.hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                }
                Section("Görevler") {
                    if sunucu.gorevler.isEmpty { Text("Henüz görev yok.").foregroundStyle(.secondary) }
                    ForEach(sunucu.gorevler) { g in
                        DisclosureGroup {
                            Text(g.prompt).textSelection(.enabled)
                            if !g.result.isEmpty { Text(g.result).textSelection(.enabled); ShareLink(item: g.result) { Label("Sonucu paylaş", systemImage: "square.and.arrow.up") } }
                            if !g.error.isEmpty { Text(g.error).foregroundStyle(.red) }
                            if g.etkin { Button("Görevi durdur", role: .destructive) { Task { do { try await sunucu.iptal(g.id) } catch { sunucu.hata = error.localizedDescription } } } }
                        } label: {
                            VStack(alignment: .leading) { Text(g.prompt).lineLimit(2); Text(g.durum).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Sunucu görevleri")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .refreshable { await sunucu.yenile() }
            .task { while !Task.isCancelled { if ayarlar.sunucuGorevleri { await sunucu.yenile() }; do { try await Task.sleep(for: .seconds(5)) } catch { break } } }
            .onChange(of: metin) { _, _ in gonderimKimligi = UUID() }
            .onChange(of: tur) { _, _ in gonderimKimligi = UUID() }
        }
    }
}
