import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var pool: DailyQuestionPool
    @AppStorage(ArenaPreferences.Key.haptics) private var haptics = true
    @AppStorage(ArenaPreferences.Key.speechRate) private var speechRate = 1.0
    @AppStorage(ArenaPreferences.Key.voiceAutoStart) private var autoStart = true
    @AppStorage(ArenaPreferences.Key.voiceAutoStop) private var autoStop = true
    @AppStorage(ArenaPreferences.Key.voiceSilence) private var silence = 1.2
    @AppStorage(ArenaPreferences.Key.voiceMaxSeconds) private var maxSeconds = 12
    @AppStorage(ArenaPreferences.Key.voiceAutoSubmit) private var autoSubmit = false
    @AppStorage(ArenaPreferences.Key.liveReviewSeconds) private var reviewSeconds = 3
    @AppStorage(ArenaPreferences.Key.liveExplanation) private var liveExplanation = true
    @AppStorage("quizLiveEngine") private var liveEngine = QuizLiveEngine.chained.rawValue
    @State private var cacheBytes = 0
    @State private var confirmProgress = false
    @State private var confirmPreferences = false
    @State private var notice = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ses efektleri",isOn:$game.soundEnabled).accessibilityIdentifier("soundEffects")
                    Toggle("Türkçe sesli uyarılar",isOn:$game.voiceEnabled).accessibilityIdentifier("voiceAlerts")
                    Toggle("Titreşim",isOn:$haptics).accessibilityIdentifier("hapticsEnabled")
                    Picker("iPhone konuşma hızı",selection:$speechRate) {
                        Text("Yavaş").tag(0.8); Text("Biraz yavaş").tag(0.9); Text("Normal").tag(1.0); Text("Hızlı").tag(1.15)
                    }.accessibilityIdentifier("speechRate")
                    Button { game.notify(.stage,"Ses denemesi. Yeni etap başlıyor.") } label: { Label("Sesi dene",systemImage:"speaker.wave.2.fill") }.accessibilityIdentifier("testGameSound")
                } header: { Text("Ses ve uyarılar") } footer: {
                    Text("Konuşma hızı iPhone sesine uygulanır; Azure ve Chirp kendi hızında okur. Sessiz mod ve cihaz ses seviyesi geçerlidir. VoiceOver açıkken konuşmalı uyarılar okunmaz.")
                }
                Section("Soru sesi") { QuestionVoiceSettings().padding(.vertical,6) }
                Section {
                    WhisperModelRow(voice:game.voiceAnswer)
                    Toggle("Pencere açılınca dinlemeye başla",isOn:$autoStart).accessibilityIdentifier("voiceAutoStart")
                    Toggle("Susunca kaydı bitir",isOn:$autoStop).accessibilityIdentifier("voiceAutoStop")
                    Picker("Sessizlik süresi",selection:$silence) {
                        Text("Kısa · 0,8 sn").tag(0.8); Text("Normal · 1,2 sn").tag(1.2); Text("Uzun · 2 sn").tag(2.0)
                    }.disabled(!autoStop).accessibilityIdentifier("voiceSilence")
                    Picker("En uzun kayıt",selection:$maxSeconds) { ForEach(ArenaPreferences.maxSecondsChoices,id:\.self) { Text("\($0) saniye").tag($0) } }.accessibilityIdentifier("voiceMaxSeconds")
                    Toggle("Kesin yanıtı onaysız gönder",isOn:$autoSubmit).accessibilityIdentifier("voiceAutoSubmit")
                } header: { Text("Sesli yanıt · cihazda Whisper") } footer: {
                    Text("Onaysız gönderimde yanıt 2 saniyelik geri sayımla gider; Vazgeç ile durdurup düzenleyebilirsin. Söyleme alıştırması her zaman elle kaydedilir. \"Bence C şıkkı\", \"ikinci seçenek\" veya seçeneğin adı anlaşılır.")
                }
                Section {
                    Picker("Canlı ses motoru",selection:$liveEngine) { ForEach(QuizLiveEngine.allCases) { Text($0.title).tag($0.rawValue) } }.accessibilityIdentifier("liveEngine")
                    Picker("Göndermeden önce bekle",selection:$reviewSeconds) {
                        Text("Beklemeden").tag(0); ForEach(ArenaPreferences.reviewChoices.dropFirst(),id:\.self) { Text("\($0) saniye").tag($0) }
                    }.accessibilityIdentifier("liveReviewSeconds")
                    Toggle("Açıklamayı sesli oku",isOn:$liveExplanation).accessibilityIdentifier("liveExplanation")
                } header: { Text("Canlı sesli tur") } footer: {
                    Text(liveEngine == QuizLiveEngine.chained.rawValue ? "Sıralı yol: seçtiğin soru sesi + cihazda Whisper; mikrofon kaydı gönderilmez. Sessizlik ve kayıt süresi yukarıdaki sesli yanıt ayarlarından gelir." : "Canlı API seçiliyken mikrofon sesi sağlayıcıya gider; bağlantı kurulamazsa sıralı yol kullanılır. Komutlar: tekrar oku, dur, geç, atla.")
                }
                Section {
                    Toggle("Otomatik soru üretimi",isOn:$pool.enabled).accessibilityIdentifier("settingsAutomaticPool")
                    LabeledContent("Havuzdaki soru",value:"\(pool.snapshot.total)")
                    LabeledContent("Bugün eklenen",value:"\(pool.snapshot.today)/450")
                } header: { Text("Soru havuzu") } footer: { Text("Kapatınca günlük üretim durur; mevcut sorular silinmez.") }
                Section {
                    LabeledContent("Soru sesi önbelleği",value:ByteCountFormatter.string(fromByteCount:Int64(cacheBytes),countStyle:.file))
                    Button("Ses önbelleğini temizle") { QuestionVoiceAPI.clearCache(); cacheBytes = QuestionVoiceAPI.cacheBytes(); notice = "Ses önbelleği temizlendi." }.accessibilityIdentifier("clearVoiceCache")
                    Button("İlerlemeyi sıfırla",role:.destructive) { confirmProgress = true }.accessibilityIdentifier("resetProgress")
                    Button("Ayarları varsayılana döndür") { confirmPreferences = true }.accessibilityIdentifier("resetPreferences")
                    if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(gold).accessibilityIdentifier("settingsNotice") }
                } header: { Text("Veri") } footer: {
                    Text("İlerleme sıfırlama XP, tur geçmişi, istatistik ve tekrar defterini siler; soru havuzu, paketler ve kaydettiğin bilgi kartları kalır.")
                }
                Section("Hakkında") {
                    LabeledContent("Sürüm",value:Self.version)
                    NavigationLink("Gizlilik") { InfoTextView(title:"Gizlilik",text:Self.privacy) }
                    NavigationLink("Üçüncü taraf lisansları") { InfoTextView(title:"Lisanslar",text:Self.notices) }
                }
            }
            .scrollContentBackground(.hidden).background(ArenaBackdrop())
            .navigationTitle("Ayarlar")
            .onAppear { cacheBytes = QuestionVoiceAPI.cacheBytes(); notice = "" }
            .confirmationDialog("İlerleme sıfırlansın mı?",isPresented:$confirmProgress,titleVisibility:.visible) {
                Button("İlerlemeyi sıfırla",role:.destructive) { game.resetProgress(); notice = "İlerleme sıfırlandı." }
                Button("Vazgeç",role:.cancel) {}
            } message: { Text("XP, seviye, tur geçmişi ve tekrar defteri silinir. Bu işlem geri alınamaz.") }
            .confirmationDialog("Ayarlar varsayılana dönsün mü?",isPresented:$confirmPreferences,titleVisibility:.visible) {
                Button("Varsayılana döndür") { game.resetPreferences(); notice = "Ayarlar varsayılana döndü." }
                Button("Vazgeç",role:.cancel) {}
            } message: { Text("Ses, titreşim, sesli yanıt ve canlı tur ayarları sıfırlanır. Model, hesap ve ses API bağlantıları değişmez.") }
        }.tint(aqua)
    }
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
    static var notices: String {
        Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt").flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? "Lisans dosyası bulunamadı."
    }
    static let privacy = """
    Bilgi Arenası reklam ve izleme içermez. İlerleme, ayarlar ve soru havuzu yalnız bu iPhone'da saklanır.

    Sesli yanıt: Mikrofon kaydı cihazdaki Whisper modeliyle yazıya çevrilir ve ardından silinir. Sıralı sesli yolda ses hiçbir sunucuya gönderilmez.

    Canlı API (ChatGPT Realtime / Gemini Live) seçersen mikrofon sesi seçtiğin sağlayıcıya gider.

    Soru sesi: Azure, Chirp veya Proxy sesi seçiliyse okunacak metin ilgili sağlayıcıya gönderilir; iPhone sesi cihazda çalışır.

    Yapay zekâ soruları: Konu ve ayarlar, CLI Proxy hesaplarınla doğrudan model sağlayıcısına gönderilir. VPS kullanılmaz.
    """
}

struct WhisperModelRow: View {
    @ObservedObject var voice: VoiceAnswerStore
    @State private var downloaded = LocalAnswerWhisper.downloaded
    @State private var bytes = 0
    @State private var confirmDelete = false
    @State private var deleting = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Label("Whisper modeli",systemImage:"waveform.and.mic")
                Spacer()
                Text(voice.ready ? "Hazır" : downloaded ? "İndirildi" : "İndirilmedi").font(.subheadline.bold()).foregroundStyle(voice.ready || downloaded ? aqua : gold).accessibilityIdentifier("whisperStatus")
            }
            if downloaded { Text("Telefonda \(ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file)) yer kaplıyor. Çözümleme çevrimdışı.").font(.caption).foregroundStyle(.secondary) }
            else { Text("İlk hazırlamada yaklaşık 470 MB indirilir; sonra çevrimdışı çalışır. Wi-Fi önerilir.").font(.caption).foregroundStyle(.secondary) }
            if voice.phase == .preparing { ProgressView(value:voice.progress) { Text("Hazırlanıyor… \(Int(voice.progress*100))%").font(.caption) } }
            if let error = voice.error { Text(error).font(.caption).foregroundStyle(gold) }
            HStack {
                if !voice.ready { Button(downloaded ? "Modeli yükle" : "Modeli indir ve hazırla") { voice.prepare() }.disabled(voice.phase != .idle || deleting).accessibilityIdentifier("settingsPrepareWhisper") }
                Spacer()
                if downloaded { Button("Sil",role:.destructive) { confirmDelete = true }.disabled(voice.phase != .idle || deleting).accessibilityIdentifier("deleteWhisper") }
            }.buttonStyle(.borderless).font(.subheadline.bold())
        }
        .onAppear(perform:refresh)
        .onChange(of:voice.ready) { _,_ in refresh() }
        .confirmationDialog("Whisper modeli silinsin mi?",isPresented:$confirmDelete,titleVisibility:.visible) {
            Button("Modeli sil",role:.destructive) { deleting = true; Task { await voice.deleteModel(); deleting = false; refresh() } }
            Button("Vazgeç",role:.cancel) {}
        } message: { Text("Sesli yanıt için model yeniden indirilmelidir.") }
    }
    private func refresh() { downloaded = LocalAnswerWhisper.downloaded; bytes = downloaded ? LocalAnswerWhisper.downloadedBytes : 0 }
}

struct InfoTextView: View {
    let title: String
    let text: String
    var body: some View {
        ScrollView { Text(text).font(.footnote).frame(maxWidth:.infinity,alignment:.leading).padding(20).textSelection(.enabled) }
            .background(ArenaBackdrop()).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
