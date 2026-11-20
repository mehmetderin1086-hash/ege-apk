import SwiftData
import SwiftUI

/// Ayarlar'ın sayfaları; modül içindeki ayar düğmesi ve Ana Sayfa doğrudan bir sayfaya gidebilir (`AppState.settingsRoute`).
enum SettingsPage: Hashable {
    case appearance, audio, connection, models, storage, about
    case module(AppState.MainTab)

    var title: String {
        switch self {
        case .appearance: "Görme kolaylığı ve görünüm"
        case .audio: "Ses ve dinleme"
        case .connection: "Bağlantı ve hesaplar"
        case .models: "Modeller ve kullanım"
        case .storage: "Depolama ve yedekleme"
        case .about: "İkra hakkında"
        case .module(let tab): tab.title
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "eye.fill"
        case .audio: "speaker.wave.2.fill"
        case .connection: "network"
        case .models: "cpu.fill"
        case .storage: "externaldrive.fill"
        case .about: "info.circle.fill"
        case .module(let tab): tab.symbol
        }
    }

    /// Satır simgesinin zemini ve üstündeki simge rengi (yalnız mavi–sarı tonları, en az 4.5:1 kontrast).
    var tile: (fill: AnyShapeStyle, foreground: Color) {
        switch self {
        case .appearance: (AnyShapeStyle(Theme.warmGradient), Theme.navy)
        case .audio: (AnyShapeStyle(Theme.gradient), .white)
        case .connection: (AnyShapeStyle(Theme.blue), .white)
        case .models: (AnyShapeStyle(Theme.navy), Theme.yellow)
        case .storage: (AnyShapeStyle(Theme.amber), Theme.navy)
        case .about: (AnyShapeStyle(Theme.sky), Theme.navy)
        case .module(let tab): (AnyShapeStyle(tab.gradient), tab.onColor)
        }
    }

    /// Kendi ayarı olan modüller (Plan, Sınav Oku ve Görseller'in ayrı ayarı yok).
    static let modulePages: [SettingsPage] = [.module(.library), .module(.questions), .module(.topics), .module(.study)]
}

struct SettingsView: View {
    @AppStorage(VisionPrefs.textSizeKey) private var textSize = 1
    @AppStorage(VisionPrefs.boldKey) private var boldText = true
    @AppStorage(VisionPrefs.contrastKey) private var highContrast = true
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var episodes: [Episode]
    /// Modül olarak açıldığında kapatılacak sayfa yoktur: "Bitti" yalnız sayfa olarak açılınca gösterilir.
    var showsDone = true
    @State private var path: [SettingsPage] = []
    @State private var confirmDeleteAll = false
    // Gövdede hesaplanmazlar (dosya taraması, bölüm ayarları, sistem ses listesi): görevlerde ölçülür, hazır olana dek "…".
    @State private var storageText = "…"
    @State private var cost: (total: Double, lines: [(String, Double)])?
    /// Kaldırılan cihaz içi ses motorlarından (Supertonic, Piper) kalan indirilmiş model var mı.
    @State private var hasOfflineModels = false
    @AppStorage("autoVerify") private var autoVerify = true
    @AppStorage(SoundDesign.key) private var soundDesign = true
    @AppStorage(QualityMode.key) private var maxQuality = true
    @AppStorage(WeeklyRecap.enabledKey) private var autoRecap = false
    @State private var backup: BackupDocument?
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupMessage: String?
    @State private var showMacBackup = false
    @State private var showQuota = false
    @State private var claudeKey = ""
    @State private var claudeStored = ClaudeKey.stored

    var body: some View {
        NavigationStack(path: $path) {
            // Ana Sayfa düzeni (17 Eki 2026): lacivert kart, büyük bölüm başlıkları, büyük satırlar.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Genel")
                        row(.appearance, "Yazı boyutu, kalın yazı, yüksek kontrast")
                        row(.audio, "Sesler, iPhone ses modelleri, podcast akışı")
                        row(.connection, app.server != nil ? "Bağlı · sunucu, CLI Proxy, Claude anahtarı" : "Bağlantı yok · sunucu ve hesaplar")
                        row(.models, "Adım adım model seçimi, kaynaklar, kullanım")
                        row(.storage, "\(episodes.count) bölüm · \(storageText)")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Modüller", detail: "Plan, Sınav Oku ve Görseller ortak ses, model ve bağlantı ayarlarını kullanır.")
                        row(.module(.library), "Podcast üretimi, kalite, akış, haftalık özet")
                        row(.module(.questions), "Çözüm modu, paralel modeller, yanlış hafızası, yedek")
                        row(.module(.topics), "Video çıktısı, kaynak resimleri, yazı–ses eşleme")
                        row(.module(.study), "Dinlerken öğren, eller serbest, yoklamalar")
                    }
                    row(.about, "Sürüm ve gizlilik")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsPage.self) { page in destination(page) }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
                }
            }
            .confirmationDialog("Tüm bölümler silinsin mi?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Hepsini sil", role: .destructive) { Task { await deleteAll() } }
            } message: {
                Text("Ses dosyaları, transkriptler ve quizler bu cihazdan kalıcı olarak silinir.")
            }
            .onChange(of: app.settingsRoute, initial: true) { _, route in
                guard let route else { return }
                path = [route]
                app.settingsRoute = nil
            }
            .task {
                #if DEBUG
                let pages: [String: SettingsPage] = ["appearance": .appearance, "audio": .audio, "connection": .connection, "models": .models,
                                                     "storage": .storage, "library": .module(.library), "questions": .module(.questions),
                                                     "topics": .module(.topics), "study": .module(.study)]
                if let raw = DebugArg.value("settingsPage"), let page = pages[raw] { path = [page] }
                #endif
                await app.refreshStatus()
            }
            .task(id: librarySignature) {
                cost = CostEstimate.monthly(episodes)
                let text = await StorageReport.episodesText()
                // İmza değişip görev iptal edildiyse eski ölçüm yenisinin üstüne yazılmasın.
                if !Task.isCancelled { storageText = text }
            }
            // İndirilen ses iPhone Ayarlar'dan dönünce görünsün.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                hasOfflineModels = OfflineModelCatalog.engines.contains { OfflineModelCatalog.ready($0) }
            }
            .fileExporter(isPresented: $exportingBackup, document: backup, contentType: .folder,
                          defaultFilename: backup?.wrapper.preferredFilename ?? "DersPodcast-yedek") { result in
                if case .failure(let error) = result { backupMessage = error.localizedDescription } else { backupMessage = "Yedek kaydedildi." }
                backup = nil
            }
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.folder]) { result in
                switch result {
                case let .success(url):
                    do { backupMessage = "\(try Backup.restore(from: url, context: context)) bölüm geri yüklendi." }
                    catch let warning as Backup.RestoreWarning { backupMessage = warning.localizedDescription }
                    catch { backupMessage = "Geri yüklenemedi: \(error.localizedDescription)" }
                case let .failure(error): backupMessage = error.localizedDescription
                }
            }
            .alert(backupMessage ?? "", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            }
            .sheet(isPresented: $showMacBackup) { MacBackupView() }
            .sheet(isPresented: $showQuota) { QSQuotaSheet() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ayarlar").font(.headline).foregroundStyle(Theme.yellow)
            Text("Bütün ayarlar tek yerde").font(.system(.title, design: .rounded, weight: .heavy)).foregroundStyle(.white)
            Text("Görme kolaylığı, ses, bağlantı ve her modülün ayarları burada.").font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            Label(app.server != nil ? "Sunucuya bağlı" : "Bağlantı yok", systemImage: app.server != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.heavy)).foregroundStyle(Theme.navy)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.yellow, in: Capsule())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(_ page: SettingsPage, _ detail: String) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                ModuleIconTile(symbol: page.symbol, fill: page.tile.fill, foreground: page.tile.foreground, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(.headline.weight(.heavy)).foregroundStyle(.primary)
                    Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(.primary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .okuSurface()
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableCardStyle(reduceMotion: false))
    }

    @ViewBuilder private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .appearance: settingsPage(page) { appearanceSettings }
        case .audio: settingsPage(page) { audioSettings }
        case .connection: settingsPage(page) { connectionSettings }
        case .models: settingsPage(page) { modelSettings }
        case .storage: settingsPage(page) { dataSettings }
        case .about: settingsPage(page) { aboutSettings }
        case .module(.library): settingsPage(page) { libraryModuleSettings }
        case .module(.questions):
            QSSettingsForm(store: QuestionStore.shared, restore: { app.questionRestoreRequested += 1; app.selectedTab = .questions })
                .scrollContentBackground(.hidden).background(Theme.canvas)
                .navigationTitle("Soru Çöz").navigationBarTitleDisplayMode(.inline)
                // Soru Çöz hiç açılmadıysa model listesi ve sunucu yetenekleri henüz yüklenmemiştir.
                .task {
                    if QuestionStore.shared.catalog == nil { await QuestionStore.shared.refreshCatalog(quiet: true) }
                    if QuestionStore.shared.capabilities == nil { await QuestionStore.shared.refreshCapabilities() }
                }
        case .module(.topics): settingsPage(page) { VideoOutputSettings() }
        case .module(.study):
            LearningSettingsForm()
                .scrollContentBackground(.hidden).background(Theme.canvas)
                .navigationTitle("Çalış").navigationBarTitleDisplayMode(.inline)
        case .module: ContentUnavailableView("Bu modülün ayrı ayarı yok", systemImage: "slider.horizontal.3")
        }
    }

    private func settingsPage<Content: View>(_ page: SettingsPage, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var appearanceSettings: some View {
        Section {
            Picker("Yazı boyutu", selection: $textSize) {
                Text("iPhone").tag(0)
                Text("Büyük").tag(1)
                Text("Çok büyük").tag(2)
            }
            .pickerStyle(.segmented)
            Text("Örnek: Mitoz bölünmede kromozomlar ekvatorda dizilir.").font(.body)
                .padding(.vertical, 4)
            Toggle("Kalın yazı", isOn: $boldText)
            Toggle("Yüksek kontrast (kalın kenarlıklar)", isOn: $highContrast)
        } header: { Text("Görme kolaylığı") } footer: {
            Text("Büyük ve çok büyük, bütün ekranlarda yazının en küçük boyutunu yükseltir; iPhone'da daha büyük yazı seçiliyse o geçerli kalır. Renkler mavi ve sarı tonlarındadır; bu ikili renk körlüğünde de ayırt edilir ve her bilgi ayrıca simge ve yazıyla verilir.")
        }
        Section {
            Label("iPhone yazı boyutunu izler", systemImage: "textformat.size")
            Label("VoiceOver ile kullanılabilir kontroller", systemImage: "speaker.wave.2")
            Label("Hareketi azalt ve koyu görünüm desteği", systemImage: "circle.lefthalf.filled")
            Button("iPhone uygulama ayarlarını aç", systemImage: "arrow.up.forward.app") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.frame(minHeight: 44)
        } header: { Text("Sistem tercihleri") } footer: {
            Text("Yazı boyutu, kalın metin, kontrast ve hareket tercihleri iPhone ayarlarından alınır. Uygulama ayarlarında izinleri düzenleyebilirsin.")
        }
    }

    @ViewBuilder private var audioSettings: some View {
        // Tek ses ayarı (17 Eki 2026): bütün modüller bu iki sesi kullanır.
        VoiceSettingsSection()
        Section("iPhone ses modelleri") {
            NavigationLink { OfflineSpeechModelsView() } label: {
                OkuRouteLabel(title: "Çevrimdışı ses modelleri", detail: hasOfflineModels ? "İndirilmiş Supertonic ve Piper modelleri" : "Supertonic ve Piper modellerini indir (telefonda üretilen sesler)", symbol: "arrow.down.circle", showsChevron: false)
            }.listRowInsets(EdgeInsets())
            // Madde 50: sunucu hizalaması yokken kullanılan cihaz içi kelime hizalayıcısı (isteğe bağlı model indirmesi).
            NavigationLink { DeviceAlignerView() } label: {
                OkuRouteLabel(title: "Telefonda yazı–ses eşleme", detail: "Videolarda kelime kelime altyazı için", symbol: "text.word.spacing", showsChevron: false)
            }.listRowInsets(EdgeInsets())
        }
        Section {
            Toggle("Ses tasarımı", isOn: $soundDesign)
        } footer: { Text("Jingle, geçiş zili ve ses eşitleme.") }
        FeedSettingsSection()
        Section("iPhone ses kalitesi") {
            Text("Daha doğal konuşma için iPhone Ayarlar → Erişilebilirlik → Oku ve Seslendir → Sesler → Türkçe bölümünden geliştirilmiş bir ses indir. İndirilen en kaliteli ses otomatik seçilir.")
                .font(.subheadline)
            Text("Çıktı: 48 kHz · 128 kb/sn AAC.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var connectionSettings: some View {
        Section("Sunucu") {
            NavigationLink { ServerSetupView(isInitialSetup: false) } label: {
                OkuRouteLabel(title: "Sunucu adresi ve erişim anahtarı", detail: Config.apiBaseURL.host() ?? "Adres ayarla", symbol: "network", showsChevron: false)
            }.listRowInsets(EdgeInsets())
            Label(app.server != nil ? "Sunucuya bağlı" : "Bağlantı yok", systemImage: app.server != nil ? "checkmark.circle" : "exclamationmark.circle")
            if let error = app.serverError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            Button("Bağlantıyı yenile", systemImage: "arrow.clockwise") { Task { await app.refreshStatus() } }
                .frame(minHeight: 44)
        }
        PhoneProxySection()
        Section {
            SecureField(claudeStored ? "Claude API anahtarı (kayıtlı)" : "Claude API anahtarı", text: $claudeKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Anahtarı kaydet") { ClaudeKey.set(claudeKey); claudeKey = ""; claudeStored = ClaudeKey.stored }.disabled(claudeKey.trimmingCharacters(in: .whitespaces).isEmpty)
            if claudeStored { Button("Kayıtlı anahtarı sil", role: .destructive) { ClaudeKey.set(nil); claudeStored = ClaudeKey.stored } }
        } header: { Text("Claude API anahtarı (yedek)") } footer: {
            Text("Soru çözümü, anlatım ve podcast önce sunucu vekilindeki hesaplardan (Claude, Antigravity, ChatGPT Plus, Gemini) geçer; hiçbiri yanıt veremezse bu anahtarla doğrudan Claude çağrılır. Anahtar yalnız bu cihazın Keychain'inde durur.")
        }
    }

    @ViewBuilder private var modelSettings: some View {
        Section {
            QSModelPlanLink(catalog: nil)
        } header: { Text("Modeller") } footer: {
            Text("Soru çözümü, video, podcast senaryosu, çalışma araçları, koç ve slaytların her adımı için model seçebilirsin. İstekler önce sunucudaki vekil hesaplarından (Claude, Antigravity, ChatGPT, Gemini) gider, API anahtarları yedektir. Seçim, yeni podcast ekranındaki senaryo modelinin önüne geçer.")
        }
        Section {
            // Kaynak deposu (14 Eki 2026): yüklenen PDF, fotoğraf, ses ve metinler sunucuda indekslenir; yerel modeller soruyu çözerken
            // en yakın parçaları bağlam olarak alır. MEB ders kitapları da aynı depodadır.
            NavigationLink { KaynaklarView() } label: { Label("Kaynaklar (ders kitapları, notlar)", systemImage: "books.vertical") }
            QSDersLocalToggle()
        } header: { Text("Yerel modeller ve kaynaklar") } footer: {
            Text("Yüklediğin her kaynak sunucudaki depoya girer; yerel modeller (matematikte Qwen, altı derste Gemma) soruyu çözerken bu depodan en yakın parçaları okur.")
        }
        Section("Belge okuma · OCR") {
            LabeledContent("Model", value: "Modeller → Soru ve belge okuma")
            Text("PDF ve fotoğraflar uygulama içi motorda okunur (vekildeki hesaplar, yedekte API anahtarı); yalnız metinden oluşan PDF sayfalarının metni doğrudan alınır.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
            if let today = app.server?.today, let limits = app.server?.limits {
                LabeledContent("Podcast", value: "\(today.podcasts) / \(limits.podcasts)")
                LabeledContent("Sesli soru", value: "\(today.questions) / \(limits.questions)")
                LabeledContent("Quiz ve kart", value: "\(today.study) / \(limits.study)")
                if let used = today.tools, let limit = limits.tools { LabeledContent("Yardımcı araçlar", value: "\(used) / \(limit)") }
            }
            Button("Soru Çöz kotası ve kalan haklar", systemImage: "gauge.with.dots.needle.33percent") { showQuota = true }
        } header: { Text("Bugünkü kullanım") } footer: {
            Text("Kullanım sınırları beklenmedik maliyetleri önlemek içindir; sunucu yapılandırmasından değiştirilebilir.")
        }
        Section {
            if let cost {
                ForEach(cost.lines, id: \.0) { line in
                    LabeledContent(line.0, value: line.0.hasSuffix("(dk)") ? "\(Int(line.1))" : String(format: "$%.2f", line.1))
                }
                LabeledContent("Toplam (tahmini)", value: String(format: "$%.2f", cost.total)).bold()
            } else { LabeledContent("Toplam (tahmini)", value: "…") }
        } header: { Text("Bu ay · tahmini maliyet") } footer: {
            Text("Google liste fiyatlarına göre kaba tahmin. Apple, Edge ve Hugging Face sesleri ücretsizdir; proxy üzerinden yazılan senaryolar abonelikten karşılanır.")
        }
    }

    @ViewBuilder private var libraryModuleSettings: some View {
        Section {
            Toggle(isOn: Binding(get: { maxQuality }, set: { maxQuality = $0; QualityMode.set($0); soundDesign = SoundDesign.isEnabled; autoVerify = true })) {
                Text("Maksimum kalite")
            }
        } header: { Text("Podcast üretimi") } footer: {
            Text("Derinlemesine anlatım, içerik eklentileri ve ses tasarımı. Bölüm hazır olunca quiz, kartlar, kavram haritası, slaytlar ve doğrulama hazırlanır. Daha fazla Claude kullanımı demektir.")
        }
        Section {
            Toggle("Senaryoyu belgeyle doğrula", isOn: $autoVerify)
        } footer: { Text("Kaynakta bulunmayan veya çelişen cümleler transkriptte uyarıyla işaretlenir.") }
        Section {
            Toggle("Ses tasarımı", isOn: $soundDesign)
        } footer: { Text("Jingle, geçiş zili ve ses eşitleme.") }
        Section {
            Toggle("Her pazar otomatik oluştur", isOn: $autoRecap)
        } header: { Text("Haftalık özet") } footer: {
            Text("Bu hafta dinlediğin bölümlerin 10 dakikalık, bağlantıları kuran bir tekrar bölümü.")
        }
        FeedSettingsSection()
    }

    @ViewBuilder private var dataSettings: some View {
        Section("Cihazda") {
            LabeledContent("Podcast bölümü", value: "\(episodes.count)")
            LabeledContent("Kapladığı alan", value: storageText)
        }
        Section {
            Button("Kütüphaneyi yedekle", systemImage: "externaldrive.badge.plus") {
                do {
                    backup = BackupDocument(wrapper: try Backup.make(context: context))
                    exportingBackup = true
                } catch { backupMessage = error.localizedDescription }
            }.frame(minHeight: 44)
            Button("Yedekten geri yükle", systemImage: "arrow.down.doc") { importingBackup = true }
                .frame(minHeight: 44)
            Button("Sunucu yedeği", systemImage: "externaldrive.badge.timemachine") { showMacBackup = true }
                .frame(minHeight: 44)
        } header: { Text("Yedekleme") } footer: {
            Text("Bölümler, sesler, notlar, tekrar kartları ve belgeler Dosyalar, iCloud Drive ya da Mac’e kaydedilir. Geri yüklemede mevcut kayıtlar korunur. Soru arşivinin yedeği Ayarlar › Soru Çöz'dedir.")
        }
        Section {
            Button("Tüm podcast bölümlerini sil", role: .destructive) { confirmDeleteAll = true }
                .frame(minHeight: 44)
        } header: { Text("Kütüphaneyi yönet") } footer: {
            Text("Silmeden önce onay istenir. Bölümlerin ses dosyaları, transkriptleri ve quizleri silinir.")
        }
    }

    @ViewBuilder private var aboutSettings: some View {
        Section("İkra") {
            LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            Text("Kitapların, soruların, videoların ve çalışma araçların tek yerde.").font(.subheadline)
        }
        Section("Bilgilerin") {
            Text("Sunucu erişim anahtarı bu cihazın Keychain’inde saklanır. Sunucu adresi ve anahtarını Bağlantı ve hesaplar bölümünden yönetebilirsin.")
                .font(.subheadline)
            Text("Podcast üretimi için eklediğin kaynaklar seçilen sunucuya iletilir. İndirilmiş kitaplar bağlantı olmadan açılır.")
                .font(.subheadline)
        }
    }

    /// Alan ve maliyet yeniden ölçülsün mü: bölüm eklendi, silindi ya da üretimi bitti (konum kaydı gibi değişimler tetiklemez).
    private var librarySignature: String { "\(episodes.count)|\(episodes.filter { $0.status == .ready }.count)" }

    private func deleteAll() async {
        player.close()
        for episode in episodes { await generator.delete(episode, context: context) }
        EpisodeFiles.removeAll()
        storageText = await StorageReport.episodesText()
    }
}

/// Video çıktısı varsayılanları: Soru Çöz anlatımları ve konu videoları aynı tercih anahtarlarını kullanır
/// (stüdyodaki seçiciler de bunları değiştirir; burada yapılan seçim bir sonraki dışa aktarımda geçerlidir).
private struct VideoOutputSettings: View {
    @AppStorage("qs.board.theme") private var theme = QSBoardTheme.dark.rawValue
    @AppStorage("qs.board.format") private var format = QSBoardFormat.landscape.rawValue
    @AppStorage("qs.board.videoSubtitles") private var subtitles = true
    @AppStorage("qs.board.sketch") private var sketch = true
    @AppStorage(QSGlyphPen.key) private var glyphPen = true
    @AppStorage(QSVectorUnderlay.key) private var vectorUnderlay = false
    @AppStorage("qs.board.resolution") private var resolution = QSVideoResolution.p1080.rawValue
    @AppStorage("qs.board.share") private var share = QSSharePreset.quality.rawValue
    @AppStorage("qs.board.smooth") private var smooth = false
    @AppStorage("qs.board.laser") private var laser = true
    @AppStorage("qs.board.cover") private var coverCards = true
    @AppStorage("qs.board.music") private var music = false
    @AppStorage("topic.sourceFigures") private var sourceFigures = true
    /// Eski "Küçük dosya (720p)" anahtarı: stüdyo ilk açılışta bunu çözünürlüğe taşır; burada seçilen değer ezilmesin diye önce taşınır.
    @AppStorage("qs.board.compact") private var compact = false

    var body: some View {
        Section {
            Picker("Çözünürlük", selection: $resolution) { ForEach(QSVideoResolution.allCases) { Text($0.title).tag($0.rawValue) } }
            Toggle("60 kare/sn (daha akıcı)", isOn: $smooth)
            Toggle("Kapak ve kapanış kartı", isOn: $coverCards)
            Toggle("Fon müziği (kısık)", isOn: $music)
        } header: { Text("Bütün videolar") } footer: {
            Text("Soru Çöz anlatımları ve konu videoları bu tercihlerle dışa aktarılır.")
        }
        .onAppear {
            if compact, resolution == QSVideoResolution.p1080.rawValue { resolution = QSVideoResolution.p720.rawValue }
            compact = false
        }
        Section {
            Picker("Biçim", selection: $format) { ForEach(QSBoardFormat.allCases) { Text($0.title).tag($0.rawValue) } }
            Picker("Tema", selection: $theme) { ForEach(QSBoardTheme.allCases) { Text($0.title).tag($0.rawValue) } }
            Picker("Paylaşım boyutu", selection: $share) { ForEach(QSSharePreset.allCases) { Text($0.title).tag($0.rawValue) } }
            Toggle("Altyazı gömülsün", isOn: $subtitles)
            Toggle("Elle çizilmiş görünüm", isOn: $sketch)
            Toggle("El yazısı harf harf yazılsın", isOn: $glyphPen)
            Toggle("Şekli temiz çizgiye çevir (deneysel)", isOn: $vectorUnderlay)
            Toggle("Lazer işaretçi", isOn: $laser)
        } header: { Text("Soru Çöz anlatımları") } footer: {
            Text("Anlatım stüdyosundaki seçeneklerle aynıdır; birinde yapılan değişiklik ötekine de yansır. Konu videoları her zaman yatay defter temasında ve altyazılı hazırlanır.")
        }
        Section {
            Toggle("Kaynaktaki resimleri kes, videoda orijinal hâliyle kullan", isOn: $sourceFigures)
        } header: { Text("Konu videoları") }
    }
}

/// Sunucu adresi ve kişisel erişim anahtarı. İlk açılışta ve Ayarlar'dan kullanılır.
struct ServerSetupView: View {
    var isInitialSetup: Bool
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var address = Config.apiBaseURL.absoluteString
    @State private var token = PersonalToken.current ?? ""
    @State private var testing = false
    @State private var result: String?
    @State private var success = false

    var body: some View {
        Form {
            if isInitialSetup {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("Artwork")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        Text("İkra").font(.title.bold())
                        Text("İkra sunucusuna bağlanmak için erişim anahtarını gir. Adres hazır gelir; kendi sunucunu kurmadıysan değiştirmen gerekmez.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section {
                TextField(Config.defaultAPIBaseURL.absoluteString, text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Sunucu adresi")
            } footer: {
                Text("Podcast ve quiz istekleri bu adresteki sunucuya gider; adres hazır gelir. Yalnız sunucu başka bir adrese taşındıysa ya da kendi sunucunu kullanıyorsan değiştir. Boş bırakırsan uygulamayla gelen varsayılan adrese dönülür: \(Config.defaultAPIBaseURL.absoluteString)")
            }

            Section {
                SecureField("Erişim anahtarı", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Panodan yapıştır", systemImage: "doc.on.clipboard") {
                    if let pasted = UIPasteboard.general.string { token = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            } header: {
                Text("Erişim anahtarı")
            } footer: {
                Text("Anahtar yalnızca bu cihazın Keychain'inde saklanır. Sunucunu senden başkasının kullanmasını engeller.")
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(isInitialSetup ? "Bağlan" : "Kaydet ve dene")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || testing)

                if let result {
                    Label(result, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(success ? .green : .red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle(isInitialSetup ? "" : "Sunucu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() async {
        testing = true
        defer { testing = false }
        success = await app.connect(address: address, token: token)
        result = success ? "Bağlantı başarılı." : (app.serverError ?? "Bağlanılamadı.")
        if success, !isInitialSetup { dismiss() }
    }
}


/// Telefondaki CLI Proxy hesapları (17 Eki 2026): açıkken vekile giden model istekleri telefondaki hesaplarla karşılanır.
private struct PhoneProxySection: View {
    @AppStorage(PhoneProxy.enabledKey) private var enabled = true
    @State private var summary = PhoneProxy.summary()

    var body: some View {
        Section {
            Toggle("Telefondaki CLI Proxy hesaplarını kullan", isOn: $enabled)
            Label(summary.text, systemImage: summary.usable ? "checkmark.circle" : "exclamationmark.circle")
                .font(.footnote).foregroundStyle(summary.usable ? Color.primary : Color.secondary)
        } header: { Text("CLI Proxy") } footer: {
            Text("Claude, ChatGPT, Antigravity (Claude Opus/Sonnet 5.5, Gemini Flash) ve Gemini istekleri sunucuya uğramadan bu telefondaki hesaplardan gider. Hesaplar CLI Proxy uygulamasında yönetilir; o uygulamanın açık olması gerekmez. Gemini 4 Argon, Gemini 3.1 Pro, görsel üretim ve yerel modeller sunucudan çalışır; telefondaki yol hata verirse istek sunucuya düşer.")
        }
        .onAppear { summary = PhoneProxy.summary() }
    }
}
