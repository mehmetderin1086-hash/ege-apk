import SwiftUI

/// Sistem ayarları köprüsünün kurulumu: imzalı kestirmeyi paylaş → Kestirmeler'e ekle → Dene.
/// iOS kestirmenin eklendiğini bildirmez; "Dene" köprüyü boş bir dalla çalıştırır, dönüş gelirse kurulu sayılır.
struct SistemKoprusuEkrani: View {
    private let kopru = SistemKoprusu.ortak
    @State private var dosya: URL?
    @State private var hata: String?
    @State private var deneniyor = false
    @State private var sonuc: String?

    private let yetenekler: [(String, String)] = [
        ("wifi", "Wi-Fi aç / kapat"), ("antenna.radiowaves.left.and.right", "Bluetooth, mobil veri, kişisel erişim noktası"),
        ("airplane", "Uçak modu"), ("moon.fill", "Rahatsız Etme"), ("circle.lefthalf.filled", "Karanlık / açık görünüm"),
        ("speaker.wave.2.fill", "Ses düzeyi"), ("battery.25percent", "Düşük güç modu"), ("lock.rotation", "Dikey yön kilidi"),
        ("sun.max", "Night Shift, True Tone"), ("lock.fill", "Ekranı kilitle"),
    ]

    var body: some View {
        List {
            Section {
                Label(kopru.kuruldu ? "Köprü kurulu ve çalışıyor" : "Köprü henüz kurulmadı",
                      systemImage: kopru.kuruldu ? "checkmark.seal.fill" : "exclamationmark.circle")
                    .foregroundStyle(kopru.kuruldu ? .green : .orange)
                    .accessibilityIdentifier("sistem-koprusu-durum")
                Text("iOS, Wi-Fi ve uçak modu gibi ayarları uygulamalara açmaz; yalnız Kestirmeler değiştirebilir. Bu köprü bir kez eklenince “Wi-Fi’yi kapat”, “uçak moduna geç”, “sesi yüzde 40 yap” gibi komutları Asistan yerine getirir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("1 · Kestirmeler'e ekle") {
                Button("Köprü dosyasını hazırla") {
                    do { dosya = try Self.hazirla(); hata = nil } catch { hata = "Köprü dosyası açılamadı: \(error.localizedDescription)" }
                }
                .accessibilityIdentifier("sistem-koprusu-hazirla")
                if let dosya {
                    ShareLink(item: dosya) { Label("Asistan Sistem Köprüsü'nü paylaş", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("sistem-koprusu-paylas")
                }
                Text("Paylaş'ta Kestirmeler'i seç ve Kestirme Ekle'ye dokun. Kestirmeler görünmüyorsa Dosyalar'a kaydedip dosyayı aç. Kestirmenin adını değiştirme.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let hata { Text(hata).foregroundStyle(.red) }
            }
            Section("2 · Dene") {
                Button {
                    deneniyor = true; sonuc = nil
                    Task {
                        let s = await kopru.calistir(.deneme)
                        sonuc = s == .tamam ? "Köprü çalışıyor. Artık sistem ayarlarını sesle değiştirebilirsin." : SistemKoprusu.metin(.deneme, s, dogrulandi: nil)
                        deneniyor = false
                    }
                } label: {
                    HStack { Text("Köprüyü dene"); if deneniyor { Spacer(); ProgressView() } }
                }
                .disabled(deneniyor)
                .accessibilityIdentifier("sistem-koprusu-dene")
                Text("Kestirmeler kısa süre açılıp Asistan'a geri döner; hiçbir ayar değişmez.").font(.footnote).foregroundStyle(.secondary)
                if let sonuc { Text(sonuc).font(.footnote) }
            }
            Section("Köprüyle yapılabilenler") {
                ForEach(yetenekler, id: \.1) { Label($0.1, systemImage: $0.0) }
                Text("İnterneti kesen değişiklikler (uçak modu, Wi-Fi ya da mobil veriyi kapatma) Asistan yanıtını bitirdikten sonra uygulanır. Dış kaynaklı isteklerde (web sayfası, gelen ileti) her değişiklik önce sorulur.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sistem ayarları")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Paket içindeki imzalı dosyayı Kestirmeler'in göreceği adla geçici klasöre kopyalar.
    static func hazirla() throws -> URL {
        guard let kaynak = Bundle.main.url(forResource: "asistan-sistem-koprusu", withExtension: "shortcut") else { throw CocoaError(.fileNoSuchFile) }
        let klasor = FileManager.default.temporaryDirectory.appending(path: "SistemKoprusu", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let hedef = klasor.appending(path: SistemKoprusu.kestirmeAdi + ".shortcut")
        try Data(contentsOf: kaynak).write(to: hedef, options: .atomic)
        return hedef
    }
}
