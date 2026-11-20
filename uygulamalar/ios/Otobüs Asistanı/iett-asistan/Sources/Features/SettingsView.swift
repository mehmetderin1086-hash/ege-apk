import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = 0          // 0 sistem, 1 açık, 2 koyu
    @AppStorage("speak") private var speak = false
    @AppStorage("alerts.paused") private var paused = false
    @AppStorage("alerts.noticesImportantOnly") private var noticesImportant = true
    @State private var permission = "…"
    @AppStorage("voice.engine") private var engineRaw = VoiceEngine.auto.rawValue
    @AppStorage("voice.chirp") private var chirpVoice = "Kore"
    @AppStorage("voice.azure") private var azureVoice = "tr-TR-EmelNeural"
    @AppStorage("voice.azureRegion") private var azureRegion = "westeurope"
    @AppStorage("voice.rate") private var rate = 1.0
    @State private var azureKey = VoiceConfig.azureKey ?? ""
    @State private var testing = false
    @State private var testResult = ""
    @State private var used = 0
    @State private var wait: TimeInterval = 0
    /// İBB'ye gönderilecek hazır talep metni.
    static let requestText = """
    Sayın İBB Büyük Veri ve İş Zekâsı Müdürlüğü / İETT,

    İETT "Sefer Gerçekleşme" web servisini (api.ibb.gov.tr/iett/FiloDurum/SeferGerceklesme.asmx, GetHatOtoKonum_json) kişisel, kâr amacı gütmeyen bir mobil uygulamada, yolcuların otobüsün durağa kaç dakikada geleceğini görmesi için kullanıyorum. Servis dokümanında saatte 100 istek sınırı belirtilmiş; bu sınır birden fazla hattı canlı izlemeye yetmiyor.

    Talebim: bu sınırın artırılması, bir API anahtarı / kurumsal erişim tanımlanması ya da araç konumlarının toplu (ör. GTFS-realtime) akışla paylaşılması. Uygulama önbellek ve kota sayacı kullanarak servise gereksiz yük bindirmemektedir.

    Uygun gördüğünüz yöntemi bildirirseniz memnun olurum.
    Saygılarımla
    """

    private func refreshPermission() async {
        switch await Notifier.status() { case .authorized, .provisional, .ephemeral: permission = "Açık"; case .denied: permission = "Kapalı"; default: permission = "Sorulmadı" }
        model.plannedAlertCount = await Notifier.pendingPlannedCount()
    }

    private func test() async {
        testing = true; testResult = ""
        let player = VoicePlayer.shared
        await player.speak("Merhaba, ben otobüs asistanınım. Beş yüz T hattı dört dakika sonra durakta.")
        testResult = "Çalan motor: \(player.lastEngine.isEmpty ? "Cihaz sesi" : player.lastEngine)" + (player.lastError.map { " · uyarı: \($0)" } ?? "")
        testing = false
    }

    var body: some View {
        List {
            Section("Görünüm") {
                Picker("Tema", selection: $appearance) { Text("Sistem").tag(0); Text("Açık").tag(1); Text("Koyu").tag(2) }.pickerStyle(.segmented)
                Toggle("Asistan yanıtlarını sesli oku", isOn: $speak)
            }
            Section {
                Toggle("Tüm bildirimleri duraklat", isOn: $paused).onChange(of: paused) { Task { await model.rescheduleAlerts() } }
                Toggle("Duyurularda yalnız önemlileri bildir", isOn: $noticesImportant)
                LabeledContent("İzin") { Text(permission).foregroundStyle(permission == "Açık" ? .green : .orange) }
                LabeledContent("Zamanlanmış bildirim", value: "\(model.plannedAlertCount)")
                if permission != "Açık" { Button("İzin ver / Ayarları aç") { Task { if await Notifier.status() == .notDetermined { await Notifier.authorize() } else if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }; await refreshPermission() } } }
                Button { Task { await Notifier.post(id: "test|\(UUID())", title: "🔴 500T · İptal / ertelendi", body: "Örnek: Maç nedeniyle seferler ertelenmiştir.", important: true, delay: 3) } } label: { Label("Test bildirimi (3 sn)", systemImage: "bell.badge") }
            } header: { Text("Bildirimler") } footer: { Text("Her favori için gün, saat ve tür ayarı Takip sekmesinde karta uzun basıp “Bildirim ayarları” ile yapılır. Canlı yaklaşma ve gecikme uyarıları uygulama çalışırken veya iOS arka planda yenilemeye izin verdiğinde kontrol edilir; uygulama sonlandırıldığında ya da iOS yenileme sağlamadığında garanti edilmez. Önceden zamanlanmış bildirimler ayrı çalışır.") }
            Section {
                Picker("Motor", selection: $engineRaw) { ForEach(VoiceEngine.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Chirp sesi", selection: $chirpVoice) { ForEach(VoiceConfig.chirpVoices, id: \.self) { Text($0).tag($0) } }
                Picker("Azure sesi", selection: $azureVoice) { ForEach(VoiceConfig.azureVoices, id: \.0) { Text($0.1).tag($0.0) } }
                VStack(alignment: .leading) { Text("Konuşma hızı \(String(format: "%.2f", rate))×").font(.subheadline); Slider(value: $rate, in: 0.8...1.25, step: 0.05) }
                LabeledContent("Chirp (sunucu)") { Text(VoiceConfig.serverConfigured ? "Hazır" : "Ayarlı değil").foregroundStyle(VoiceConfig.serverConfigured ? .green : .orange) }
                LabeledContent("Azure") { Text(VoiceConfig.azureConfigured ? "Anahtar var" : "Anahtar yok").foregroundStyle(VoiceConfig.azureConfigured ? .green : .orange) }
                SecureField("Azure Speech anahtarı", text: $azureKey).textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { VoiceConfig.azureKey = azureKey }
                TextField("Azure bölgesi (örn. westeurope)", text: $azureRegion).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { VoiceConfig.azureKey = azureKey; Task { await test() } } label: { Label(testing ? "Deneniyor…" : "Sesi dene", systemImage: "play.circle") }.disabled(testing)
                if !testResult.isEmpty { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Sesli asistan") } footer: { Text("Otomatik: Azure anahtarı varsa Azure, yoksa Chirp, o da olmazsa cihaz sesi. Azure anahtarı yalnızca bu cihazın Anahtar Zinciri'nde saklanır.") }
            Section {
                LabeledContent("Kullanılan", value: "\(used)/\(FleetBudget.hourlyLimit) istek (son 1 saat)")
                ProgressView(value: Double(used), total: Double(FleetBudget.hourlyLimit)).tint(used > 70 ? .orange : .green)
                if wait > 0 { Label("Kota doldu; yaklaşık \(Int((wait / 60).rounded(.up))) dk sonra açılır.", systemImage: "hourglass").font(.footnote).foregroundStyle(.orange) }
            } header: { Text("Canlı konum kotası") } footer: { Text("İBB canlı konum servisi saatte 100 isteğe izin verir. Uygulama 90'ın altında kalır; hat sayısı arttıkça yenileme aralığı uzar.") }
            Section {
                Text("Kota İBB tarafından sabitlenmiştir; uygulamadan artırılamaz. Yalnızca İBB'ye resmî talepte bulunulabilir.").font(.footnote).foregroundStyle(.secondary)
                ShareLink(item: Self.requestText) { Label("Kota talebi metnini paylaş / kopyala", systemImage: "square.and.arrow.up") }
                Link(destination: URL(string: "https://data.ibb.gov.tr/dataset/sefer-gerceklesme-web-servisi")!) { Label("Veri setinin sayfası (İBB Açık Veri Portalı)", systemImage: "safari") }
            } header: { Text("Daha fazla kota") } footer: { Text("Talep metnini portaldaki iletişim/veri talebi bölümünden ya da İBB Büyük Veri ve İş Zekâsı Müdürlüğü'ne gönderebilirsin.") }
            Section("Veri") {
                LabeledContent("Hat", value: "\(model.lines.count)")
                LabeledContent("Durak", value: "\(model.stops.count)")
                LabeledContent("Güzergâh veritabanı", value: model.routeIndexReady ? "Hazır" : (model.syncTotal > 0 ? "\(model.syncDone)/\(model.syncTotal)" : "Bekliyor"))
                LabeledContent("Takip / not", value: "\(model.favorites.count) / \(model.notes.count)")
            }
            Section("Hakkında") {
                LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("İETT verileri: İBB Açık Veri Portalı. İETT süreleri tahmindir. Diğer toplu taşıma rotaları Apple Harita'da, Apple'ın kapsadığı yerlerde gösterilir.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).background { AuroraBackground() }
        .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
        .task { used = await FleetBudget.shared.used; wait = await FleetBudget.shared.waitSeconds(); await refreshPermission() }
    }
}
