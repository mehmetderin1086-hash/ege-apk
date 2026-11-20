import SwiftUI
import UserNotifications
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PrayerTimeStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var iap: Store
    @EnvironmentObject private var location: LocationManager

    @EnvironmentObject private var directory: DiyanetDirectory
    @State private var showSearch = false
    @State private var showSoundLibrary = false
    @State private var showPaywall = false
    @State private var currentIcon = AppIconOption.current
    @State private var isResolvingLocation = false
    @State private var locationError: String?
    @State private var purchasingProductID: String?
    @State private var updateInfo: AppUpdateChecker.UpdateInfo?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    updateAvailableSection
                    premiumSection
                    locationSection
                    StudioVoiceSettings().id("studio")
                    notificationSection
                    perPrayerSoundSection
                    extraRemindersSection.id("reminders")
                    appearanceSection.id("appearance")
                    appIconSection
                    widgetSection
                    donateSection.id("donate")
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .navigationTitle("Ayarlar")
                .sheet(isPresented: $showSearch) {
                    LocationSearchSheet { place in
                        settings.location = place
                        if iap.isPremium { settings.addSavedLocation(place) }
                        Task { await store.refresh(location: place, settings: settings) }
                    }
                }
                .sheet(isPresented: $showSoundLibrary) {
                    NotificationSoundLibrary(selected: settings.notificationSound) { sound in
                        settings.notificationSound = sound.rawValue
                        reschedule()
                    }
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
                .task {
                    await notifications.refreshStatus()
                    await maybeCheckForUpdate()
                    #if DEBUG
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-uiTestShowPaywall") { showPaywall = true }
                    if let i = args.firstIndex(of: "-uiTestScrollTo"), i + 1 < args.count {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        withAnimation { proxy.scrollTo(args[i + 1], anchor: .top) }
                    }
                    #endif
                }
            }
        }
    }

    // MARK: Premium
    @ViewBuilder private var premiumSection: some View {
        Section {
            if iap.isPremium {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium aktif").foregroundStyle(Palette.textPrimary)
                        Text("Desteğiniz için teşekkürler.")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.accent)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Secde Vakti Premium").foregroundStyle(Palette.textPrimary)
                            Text("Uygulamanın geliştirilmesine tek seferlik destek.")
                                .font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "star.circle.fill").foregroundStyle(Palette.gold)
                    }
                }
            }
        }
    }

    // MARK: Destekle
    @ViewBuilder private var donateSection: some View {
        if !iap.tipProducts.isEmpty {
            Section {
                ForEach(iap.tipProducts, id: \.id) { product in
                    Button {
                        guard purchasingProductID == nil else { return }
                        purchasingProductID = product.id
                        Task {
                            defer { purchasingProductID = nil }
                            _ = await iap.purchase(product)
                        }
                    } label: {
                        HStack {
                            Text(product.displayName).foregroundStyle(Palette.textPrimary)
                            Spacer()
                            if purchasingProductID == product.id {
                                ProgressView()
                            } else {
                                Text(product.displayPrice).foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    .disabled(purchasingProductID != nil)
                }
            } header: {
                Text("Destekle")
            } footer: {
                Text("Uygulamayı reklamsız ve gizli tutmamıza destek olabilirsiniz. Bağış hiçbir özelliği kilitlemez.")
            }
        }
    }

    // MARK: Konum
    private var locationSection: some View {
        Section {
            HStack {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Palette.accent)
                Text(settings.location?.name ?? "Seçilmedi")
                Spacer()
                Button("Değiştir") { showSearch = true }
            }

            Button {
                useCurrentLocation()
            } label: {
                HStack {
                    if isResolvingLocation {
                        ProgressView()
                    } else {
                        Label("Konumumu Kullan", systemImage: "location.fill")
                    }
                }
            }
            .disabled(isResolvingLocation)

            if let locationError {
                Text(locationError).font(.footnote).foregroundStyle(Palette.textSecondary)
            }

            // Premium: kayıtlı konumlar arasında hızlı geçiş.
            if iap.isPremium {
                ForEach(settings.savedLocations) { loc in
                    Button {
                        settings.location = loc
                        Task { await store.refresh(location: loc, settings: settings) }
                    } label: {
                        HStack {
                            Image(systemName: settings.location?.id == loc.id
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Palette.accent)
                            Text(loc.name).foregroundStyle(Palette.textPrimary)
                        }
                    }
                }
                .onDelete { settings.savedLocations.remove(atOffsets: $0) }
            } else if settings.location != nil {
                Button {
                    showPaywall = true
                } label: {
                    Label("Kayıtlı konumlar (Premium)", systemImage: "bookmark.fill")
                        .foregroundStyle(Palette.gold)
                }
            }
        } header: {
            Text("Konum")
        } footer: {
            if iap.isPremium {
                Text("Değiştir'den eklediğiniz konumlar burada kaydedilir; dokunarak hızlıca geçiş yapabilirsiniz.")
            }
        }
    }

    // MARK: Bildirimler
    private var notificationSection: some View {
        Section {
            if notifications.authorizationStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Bildirim izni kapalı — açmak için dokunun",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            ForEach(Prayer.ordered.filter(\.isNotifiable)) { prayer in
                Toggle(isOn: Binding(
                    get: { settings.isNotificationEnabled(for: prayer) },
                    set: { settings.setNotification($0, for: prayer); reschedule() }
                )) {
                    Label(prayer.displayName, systemImage: prayer.systemImage)
                }
            }

            Picker("Bildirim Sesi", selection: Binding(
                get: { settings.notificationSound },
                set: { newValue in
                    // Premium ses ve kullanıcı premium değilse → paywall, seçimi uygulama.
                    if let sound = NotificationSound(rawValue: newValue),
                       sound.isPremiumSound, !iap.isPremium {
                        showPaywall = true
                        return
                    }
                    settings.notificationSound = newValue
                    reschedule()
                }
            )) {
                ForEach(NotificationSound.allCases.filter(\.isAvailable)) { sound in
                    Text(sound.displayName + (sound.isPremiumSound && !iap.isPremium ? " 🔒" : ""))
                        .tag(sound.rawValue)
                }
            }

            Button { showSoundLibrary = true } label: {
                Label("Ses arşivi · dinle ve seç", systemImage: "waveform.circle")
            }

            Toggle("Sessiz Bildirim", isOn: Binding(
                get: { settings.silentNotifications },
                set: { settings.silentNotifications = $0; reschedule() }
            ))

            Toggle("Odak modunda da uyar", isOn: Binding(
                get: { settings.breakThroughFocus },
                set: { settings.breakThroughFocus = $0; reschedule() }
            ))

            Picker("Önceden Hatırlat", selection: Binding(
                get: { settings.preReminderMinutes },
                set: { settings.preReminderMinutes = $0; reschedule() }
            )) {
                Text("Kapalı").tag(0)
                Text("5 dakika önce").tag(5)
                Text("10 dakika önce").tag(10)
                Text("15 dakika önce").tag(15)
                Text("30 dakika önce").tag(30)
            }
        } header: {
            Text("Bildirimler")
        } footer: {
            Text("Sesler internet olmadan çalışır. Her vakit için aşağıdan ayrı ses seçebilirsiniz. iOS özel bildirim seslerini 30 saniyeden kısa kayıtlarla çalar. Sesli uyarılar cihazınızın bildirim, sessiz mod ve Odak izinlerine bağlıdır.")
        }
    }

    // MARK: Vakit-başına Ses (premium)
    @ViewBuilder private var perPrayerSoundSection: some View {
        if iap.isPremium {
            Section {
                ForEach(Prayer.ordered.filter(\.isNotifiable)) { prayer in
                    Picker(prayer.displayName, selection: Binding(
                        get: { settings.perPrayerSounds[prayer]?.rawValue ?? "" },
                        set: { newVal in
                            if newVal.isEmpty { settings.perPrayerSounds[prayer] = nil }
                            else { settings.perPrayerSounds[prayer] = NotificationSound(rawValue: newVal) }
                            reschedule()
                        }
                    )) {
                        Text("Genel").tag("")
                        ForEach(NotificationSound.allCases.filter(\.isAvailable)) { s in
                            Text(s.displayName).tag(s.rawValue)
                        }
                    }
                }
            } header: {
                Text("Vakit-başına Ses")
            } footer: {
                Text("Her vakit için ayrı bildirim sesi seçebilirsiniz. 'Genel' seçiliyken yukarıdaki Bildirim Sesi kullanılır.")
            }
        } else {
            Section {
                Button { showPaywall = true } label: {
                    Label("Vakit-başına özel ses (Premium)", systemImage: "bell.badge.fill")
                        .foregroundStyle(Palette.gold)
                }
            }
        }
    }

    // MARK: Ek Hatırlatmalar
    private var extraRemindersSection: some View {
        Section {
            Toggle("Ramazan iftar sayacı (kilit ekranı)", isOn: Binding(
                get: { settings.iftarLiveActivity },
                set: { settings.iftarLiveActivity = $0; NotificationCenter.default.post(name: .iftarLiveActivityPreferenceChanged, object: nil) }
            ))
            Toggle("Ramazan: sahur hatırlatması ve iftar bildirimi", isOn: Binding(
                get: { settings.ramadanReminders },
                set: { settings.ramadanReminders = $0; reschedule() }
            ))
            if settings.ramadanReminders {
                Picker("Sahur hatırlatması", selection: Binding(
                    get: { settings.sahurLeadMinutes },
                    set: { settings.sahurLeadMinutes = $0; reschedule() }
                )) {
                    Text("Kapalı").tag(0)
                    ForEach([30, 45, 60, 90], id: \.self) { Text("İmsaktan \($0) dk önce").tag($0) }
                }
                Text("Ramazan günlerinde sahur için hatırlatma ve Akşam vaktinde iftar bildirimi gönderilir. Ramazan ayı Diyanet takvimine göre otomatik algılanır.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Toggle("Cuma hatırlatması", isOn: Binding(
                get: { settings.fridayReminder },
                set: { settings.fridayReminder = $0; reschedule() }
            ))
            if settings.fridayReminder {
                hourPicker("Cuma saati", selection: Binding(
                    get: { settings.fridayReminderHour },
                    set: { settings.fridayReminderHour = $0; reschedule() }
                ))
                Text("Her Cuma bu saatte \"Cuma Mübarek Olsun\" hatırlatma bildirimi gönderilir.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }

            Toggle("Kandil & bayram tebrikleri", isOn: Binding(
                get: { settings.specialDayGreetings },
                set: { settings.specialDayGreetings = $0; reschedule() }
            ))

            Toggle("Günlük ayet/dua", isOn: Binding(
                get: { settings.dailyVerse },
                set: { settings.dailyVerse = $0; reschedule() }
            ))
            if settings.dailyVerse {
                hourPicker("Ayet/dua saati", selection: Binding(
                    get: { settings.dailyVerseHour },
                    set: { settings.dailyVerseHour = $0; reschedule() }
                ))
                Text("Her gün bu saatte günün ayeti veya duası bildirim olarak gönderilir.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text("Ek Hatırlatmalar")
        } footer: {
            Text("Cuma hatırlatması, kandil-bayram tebrikleri ve günlük ayet/dua bildirimleri. İstemediğinizi buradan kapatabilirsiniz.")
        }
    }

    private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24, id: \.self) { h in
                Text(String(format: "%02d:00", h)).tag(h)
            }
        }
    }

    // MARK: Uygulama İkonu
    @ViewBuilder private var appIconSection: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        setAppIcon(option)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName).foregroundStyle(Palette.textPrimary)
                                if let sub = option.subtitle {
                                    Text(sub).font(.footnote).foregroundStyle(Palette.textSecondary)
                                }
                            }
                            Spacer()
                            if currentIcon == option {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Uygulama İkonu")
            }
        }
    }

    private func setAppIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons,
              option != currentIcon else { return }
        UIApplication.shared.setAlternateIconName(option.alternateName) { _ in }
        currentIcon = option
    }

    // MARK: Widget
    private var widgetSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ana ekran widget'ı")
                        .foregroundStyle(Palette.textPrimary)
                    Text("Sonraki vakti ve geri sayımı uygulamayı açmadan görün.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            } icon: {
                Image(systemName: "apps.iphone")
                    .foregroundStyle(Palette.accent)
            }
        } header: {
            Text("Widget")
        } footer: {
            Text("Eklemek için: ana ekranda boş bir alana basılı tutun → sol üstteki **+** → **Sekine** → widget'ı seçip ekleyin.")
        }
    }

    // MARK: Görünüm
    private var appearanceSection: some View {
        Section("Görünüm") {
            Picker("Tema", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
            }
            NavigationLink {
                SecdeThemeGallery()
            } label: {
                Label("Tema galerisi · 12 görünüm", systemImage: "paintpalette.fill")
            }
            Picker("Yazı Boyutu", selection: $settings.fontScale) {
                ForEach(FontScale.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: Güncelleme
    @ViewBuilder
    private var updateAvailableSection: some View {
        if let updateInfo {
            Section {
                Link(destination: updateInfo.appStoreURL) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Palette.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Yeni sürüm mevcut")
                                .foregroundStyle(Palette.textPrimary)
                            Text("v\(updateInfo.latestVersion) — güncellemek için dokunun")
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Hakkında
    private var aboutSection: some View {
        Section {
            LabeledContent("Sürüm", value: Self.appVersion)
            HStack {
                Image(systemName: "lock.shield.fill").foregroundStyle(Palette.accent)
                Text("Reklamsız · Kimlik bilgisi toplanmaz, takip yok")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let source = store.schedule?.source {
                LabeledContent("Vakit kaynağı", value: Self.sourceLabel(source))
            }
            Link(destination: Self.appStoreURL(action: "write-review")) {
                Label("Bizi Değerlendirin", systemImage: "star.fill")
            }
            ShareLink(
                item: Self.appStoreURL(),
                message: Text("Secde Vakti ile namaz vakitlerini takip ediyorum, sen de dene:")
            ) {
                Label("Uygulamayı Paylaş", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Hakkında")
        }
    }

    private func reschedule() {
        Task { await store.rescheduleNotifications(settings: settings) }
    }

    private func useCurrentLocation() {
        locationError = nil
        location.requestPermission()
        isResolvingLocation = true
        Task {
            defer { isResolvingLocation = false }
            do {
                let result = try await location.resolveAndMatchDiyanetLocation(directory: directory)
                settings.location = result.location
                await store.refresh(location: result.location, settings: settings)
                if !result.matched {
                    locationError = "İlçeniz otomatik bulunamadı; yaklaşık vakit gösterilecek. İsterseniz 'Değiştir' ile ilçenizi seçin."
                }
            } catch {
                locationError = "Konum alınamadı. Ayarlar'dan konum iznini açın veya 'Değiştir' ile şehir arayın."
            }
        }
    }

    /// En fazla 24 saatte bir kontrol eder; sonucu cache'ler ki Ayarlar açılır açılmaz
    /// önceki bilinen durum anında görünsün, arkada tazelensin.
    private func maybeCheckForUpdate() async {
        let defaults = UserDefaults.standard
        let lastCheckedKey = "updateCheck.lastCheckedAt"
        let cachedVersionKey = "updateCheck.latestKnownVersion"

        if let cached = defaults.string(forKey: cachedVersionKey),
           AppUpdateChecker.isNewer(cached, than: AppUpdateChecker.currentInstalledVersion) {
            updateInfo = .init(latestVersion: cached, appStoreURL: Self.appStoreURL())
        }

        if let lastCheckedAt = defaults.object(forKey: lastCheckedKey) as? Date,
           Date().timeIntervalSince(lastCheckedAt) < 24 * 60 * 60 {
            return
        }

        defaults.set(Date(), forKey: lastCheckedKey)
        do {
            let result = try await AppUpdateChecker().checkForUpdate()
            if let result {
                defaults.set(result.latestVersion, forKey: cachedVersionKey)
            } else {
                defaults.removeObject(forKey: cachedVersionKey)
            }
            updateInfo = result
        } catch {
            // Ağ hatasında sessizce vazgeç — önceki cache'lenmiş durum korunur.
        }
    }

    static func sourceLabel(_ source: String) -> String {
        switch source {
        case "diyanet": return "Diyanet (resmi)"
        case "aladhan-13": return "Diyanet yöntemi (yaklaşık)"
        default: return "Yaklaşık (çevrimdışı)"
        }
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    static func appStoreURL(action: String? = nil) -> URL {
        var string = "https://apps.apple.com/app/id6796900944"
        if let action { string += "?action=\(action)" }
        return URL(string: string)!
    }
}


private struct NotificationSoundLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @State var selected: String
    let onSelect: (NotificationSound) -> Void
    @State private var preview: AVAudioPlayer?
    @State private var errorMessage: String?
    private let categories = ["Ezanlar", "Besmele ve kısa tilavetler", "Türkçe sesli hatırlatmalar", "Kısa uyarılar"]

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(NotificationSound.allCases.filter { $0.isAvailable && $0.category == category }) { sound in
                            HStack(spacing: 14) {
                                Button { play(sound) } label: {
                                    Image(systemName: "play.circle.fill").font(.title).frame(width: 44, height: 44)
                                }.buttonStyle(.borderless)
                                    .disabled(sound.fileName == nil)
                                    .accessibilityLabel("\(sound.displayName) önizle")
                                Button {
                                    selected = sound.rawValue
                                    onSelect(sound)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(sound.displayName).font(.headline)
                                            Text(sound.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selected == sound.rawValue { Image(systemName: "checkmark.circle.fill") }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Bildirim sesleri")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Durdur") { preview?.stop() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } }
            }
            .onDisappear { preview?.stop() }
        }
    }
    private func play(_ sound: NotificationSound) {
        guard let file = sound.fileName,
              let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "caf") else { return }
        do {
            preview?.stop()
            AdhanPlayer.shared.stop()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            preview = try AVAudioPlayer(contentsOf: url)
            guard preview?.play() == true else { throw URLError(.cannotDecodeContentData) }
            errorMessage = nil
        } catch { errorMessage = "Ses önizlemesi başlatılamadı. Tekrar deneyin." }
    }
}


struct SecdeThemeGallery: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    private var darkPreview: Bool { settings.theme == .dark || (settings.theme == .system && scheme == .dark) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Secde Vakti’ni kendine göre düzenle.")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Picker("Ekran görünümü", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    Text("CANLI TEMA ÖNİZLEMESİ").font(.caption.weight(.bold)).tracking(1.5)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(settings.colorTheme.displayName).font(.title.bold())
                            Text("Huzurlu bir vakit").font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(EzanDesign.gold)
                    }
                    Text("02 : 15 : 00").font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    Text("Örnek kart · gerçek vakit bilgisi değildir").font(.caption)
                }
                .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(EzanDesign.heroGradient)
                .overlay { EzanPattern() }
                .clipShape(RoundedRectangle(cornerRadius: EzanDesign.cardRadius))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(ColorTheme.allCases) { theme in
                        Button { settings.colorTheme = theme } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(colors: [Palette.swatch(theme.hero.1), Palette.swatch(theme.hero.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 74)
                                    .overlay(alignment: .leading) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "moon.stars.fill")
                                            VStack(alignment: .leading, spacing: 6) {
                                                Capsule().frame(width: 42, height: 5)
                                                Capsule().frame(width: 65, height: 4).opacity(0.55)
                                            }
                                        }.foregroundStyle(Palette.swatch(theme.gold.1)).padding(12)
                                    }
                                HStack {
                                    Text(theme.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                    if settings.colorTheme == theme { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                                }
                                HStack(spacing: 6) {
                                    ForEach([theme.accent.0, theme.gold.0, theme.background.0], id: \.self) { color in
                                        Circle().fill(Palette.swatch(color)).frame(width: 16, height: 16)
                                            .overlay(Circle().stroke(.gray.opacity(0.3)))
                                    }
                                }
                            }
                            .padding(12)
                            .foregroundStyle(darkPreview ? Color.white : Color.black)
                            .background(Palette.swatch(darkPreview ? theme.background.1 : theme.background.0))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(settings.colorTheme == theme ? Palette.accent : Palette.separator, lineWidth: settings.colorTheme == theme ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel("\(theme.displayName) teması")
                            .accessibilityValue(settings.colorTheme == theme ? "Seçili" : "")
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ayrıntılar").font(.headline)
                    Toggle("Geometrik desenler", isOn: $settings.patternEnabled)
                    Toggle("Daha belirgin yazı kontrastı", isOn: $settings.highContrast)
                    Picker("Kart biçimi", selection: $settings.cardStyle) {
                        Text("Yumuşak").tag("soft")
                        Text("Çerçeveli").tag("outlined")
                        Text("Köşeli").tag("compact")
                    }.pickerStyle(.segmented)
                    Text("Seçimleriniz otomatik kaydedilir. Sistem görünümü, iPhone’un açık/koyu ayarını izler.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                    Button("Varsayılan görünüme dön") {
                        settings.theme = .system
                        settings.colorTheme = .zumrut
                        settings.patternEnabled = true
                        settings.highContrast = false
                        settings.cardStyle = "soft"
                    }
                }.padding(18).sekineCard()
            }.padding(18)
        }
        .background(Palette.background)
        .navigationTitle("Tema galerisi")
        .navigationBarTitleDisplayMode(.inline)
    }
}
