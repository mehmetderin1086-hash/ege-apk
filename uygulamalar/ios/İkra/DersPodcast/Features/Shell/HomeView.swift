import SwiftData
import SwiftUI

/// Ana Sayfa (17 Eki 2026): tam ekran tek sesli asistan (kullanıcı kararı: "Anasayfada tek sesli asistan olsun tam ekran").
/// Modüller Menü çubuğundan açılır; selamlama, hızlı işlemler ve modül satırları Ana Sayfa'dan kaldırıldı (kod `legacyBody` altında duruyor).
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var episodes: [Episode]
    @Query private var days: [ListeningDay]
    @AppStorage(StudyPlan.dailyGoalKey) private var dailyGoal = 0
    @State private var assistant = AssistantSession()
    @State private var showTutor = false
    @State private var showContinue = false

    var body: some View {
        NavigationStack {
            AssistantCard(session: assistant, context: assistantContext, fullScreen: true)
                .background(Theme.canvas)
                .navigationTitle("İkra")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Öğren", systemImage: "graduationcap.fill") { showTutor = true }
                            .accessibilityIdentifier("home.tutor")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Devam", systemImage: "arrow.right.circle") { showContinue = true }
                            .accessibilityIdentifier("home.continue")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { app.selectedTab = .settings } label: {
                            Label("Ayarlar", systemImage: "gearshape.fill").labelStyle(.titleAndIcon).font(.headline.weight(.bold))
                        }
                    }
                }
                .sheet(isPresented: $showTutor) { TutorHub() }
                .sheet(isPresented: $showContinue) { LearningContinueView() }
        }
    }

    /// Önceki Ana Sayfa (selamlama + hızlı işlemler + modüller); istenirse geri alınır.
    @ViewBuilder private var legacyBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    AssistantCard(session: assistant, context: assistantContext)
                    quickActions
                    if let goal = weeklyGoal { goalCard(goal) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Modüller").font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                        ForEach(AppState.MainTab.modules, id: \.self) { tab in
                            Button { app.selectedTab = tab } label: { ModuleRow(tab: tab, badge: badge(for: tab)) }
                                .buttonStyle(PressableCardStyle(reduceMotion: reduceMotion))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("İkra")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.selectedTab = .settings } label: {
                        Label("Ayarlar", systemImage: "gearshape.fill").labelStyle(.titleAndIcon).font(.headline.weight(.bold))
                    }
                }
            }
        }
    }

    // MARK: - Selamlama

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "Günaydın"
        case 11..<17: "İyi günler"
        case 17..<22: "İyi akşamlar"
        default: "İyi geceler"
        }
    }

    private var streak: Int { StatsView.streak(days) }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "tr_TR"))))
                .font(.headline).foregroundStyle(Theme.yellow)
            Text(greetingText).font(.system(.largeTitle, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let plan = StudyPlan.current, plan.daysLeft > 0 {
                Label("\(plan.examName) · \(plan.daysLeft) gün kaldı", systemImage: "calendar")
                    .font(.headline).foregroundStyle(.white)
            }
            if streak > 0 {
                Label("\(streak) gündür çalışıyorsun", systemImage: "flame.fill")
                    .font(.headline).foregroundStyle(.white)
            }
            // Bağlantı sorunu yalnız varsa görünür; dokununca Ayarlar › Bağlantı açılır.
            if app.server == nil {
                Button { app.settingsRoute = .connection } label: {
                    Label(app.needsToken ? "Erişim anahtarı gerekli · düzelt" : "Sunucuya bağlanılamadı · düzelt",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(Theme.navy)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Asistana giden kısa durum özeti: tarih, modül sayıları, sınav hedefi (gerçek veriler).
    private func assistantContext() -> String {
        var lines = ["Tarih: " + Date.now.formatted(.dateTime.day().month(.wide).year().weekday(.wide).hour().minute().locale(Locale(identifier: "tr_TR"))),
                     "Açık ekran: Ana Sayfa",
                     "Podcast bölümü: \(episodes.count)",
                     "Kayıtlı soru: \(QuestionStore.shared.entries.count)",
                     "Konu videosu: \(TopicVideoMaker.shared.videos.count)",
                     "Sınav: \(ExamStore.shared.exams.count)",
                     "Bu hafta çalışma: \(weekMinutes) dk",
                     "Sunucu: " + (app.server != nil ? "bağlı" : "bağlı değil")]
        if let plan = StudyPlan.current { lines.append("Sınav hedefi: \(plan.examName), \(plan.daysLeft) gün kaldı") }
        if streak > 0 { lines.append("Seri: \(streak) gün") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Hızlı işlemler

    private var quickActions: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            // Yalnız modül satırlarında olmayan doğrudan eylemler (modüle gitmek aşağıdaki satırlarla).
            BigActionButton(title: "Podcast üret", symbol: "mic.fill", style: .yellow) { app.pendingRoute = "new" }
            BigActionButton(title: "Bugünün tekrarı", symbol: "rectangle.stack.fill", style: .blue) { app.pendingRoute = "review" }
            BigActionButton(title: "Son bölümü dinle", symbol: "play.fill", style: .outline) { app.pendingRoute = "playLatest" }
        }
    }

    /// Haftalık dinleme hedefi: Koç'un günlük hedefi (yoksa çalışma planının günlük dakikası) × 7.
    private var weeklyGoal: (done: Int, target: Int)? {
        let daily = dailyGoal > 0 ? dailyGoal : (StudyPlan.current?.dailyMinutes ?? 0)
        guard daily > 0 else { return nil }
        return (weekMinutes, daily * 7)
    }

    private var weekMinutes: Int {
        StudyProgress.weekMinutes(Dictionary(days.map { ($0.day, $0.seconds) }, uniquingKeysWith: +))
    }

    private func goalCard(_ goal: (done: Int, target: Int)) -> some View {
        let ratio = min(1, Double(goal.done) / Double(max(goal.target, 1)))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Haftalık hedef", systemImage: "target").font(.headline.weight(.heavy))
                Spacer()
                Text("\(goal.done) / \(goal.target) dk").font(.headline.weight(.heavy))
            }
            ProgressView(value: ratio).tint(Theme.amber).scaleEffect(y: 2.2)
            Text(ratio >= 1 ? "Hedef tamam, harika gidiyorsun!" : "Son 7 günde dinlediğin süre · %\(Int(ratio * 100))")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.75))
        }
        .padding(16)
        .okuSurface()
        .accessibilityElement(children: .combine)
    }

    /// Satır rozeti: modülün gerçek durumu. Bilinmiyorsa (veri henüz yüklenmedi ya da boş) rozet yok.
    private func badge(for tab: AppState.MainTab) -> String? {
        func count(_ n: Int, _ unit: String) -> String? { n > 0 ? "\(n) \(unit)" : nil }
        switch tab {
        case .library: return count(episodes.count, "bölüm")
        case .questions: return count(QuestionStore.shared.entries.count, "soru")
        case .topics: return count(TopicVideoMaker.shared.videos.count, "video")
        case .study: return weekMinutes > 0 ? "\(weekMinutes) dk" : nil
        case .courses:
            guard let plan = StudyPlan.current, plan.daysLeft > 0 else { return nil }
            return "\(plan.daysLeft) gün"
        case .exams: return count(ExamStore.shared.exams.count, "sınav")
        case .visuals: return count(QSVisualLibrary.shared.items.count, "görsel")
        case .home, .settings: return nil
        }
    }
}

// MARK: - Ortak parçalar

/// Büyük eylem düğmesi: sarı (lacivert yazı), mavi (beyaz yazı) ya da çerçeveli.
struct BigActionButton: View {
    enum Style { case yellow, blue, outline }
    let title: String
    let symbol: String
    let style: Style
    let action: () -> Void
    @AppStorage(VisionPrefs.contrastKey) private var highContrast = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title3.weight(.bold)).accessibilityHidden(true)
                // Dar sütunda kelime ortadan bölünmesin: iki satıra kadar sarar, gerekirse biraz küçülür.
                Text(title).font(.headline.weight(.heavy)).multilineTextAlignment(.leading)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .foregroundStyle(style == .yellow ? Theme.navy : style == .blue ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                switch style {
                case .yellow: RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.warmGradient)
                case .blue: RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gradient)
                case .outline:
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.blue.opacity(highContrast ? 0.7 : 0.35), lineWidth: 2) }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableCardStyle(reduceMotion: false))
    }
}

/// Dolgulu simge karosu: modül renginde zemin, üstünde kontrastlı (beyaz ya da lacivert) simge.
struct ModuleIconTile: View {
    let symbol: String
    let fill: AnyShapeStyle
    let foreground: Color
    var size: CGFloat = 44

    init(symbol: String, fill: AnyShapeStyle, foreground: Color, size: CGFloat = 44) {
        self.symbol = symbol; self.fill = fill; self.foreground = foreground; self.size = size
    }

    init(tab: AppState.MainTab, size: CGFloat = 44) {
        self.init(symbol: tab.symbol, fill: AnyShapeStyle(tab.gradient), foreground: tab.onColor, size: size)
    }

    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Modül satırı: büyük simge karosu, kalın ad, açıklama, gerçek veriden rozet ve ok.
struct ModuleRow: View {
    let tab: AppState.MainTab
    var badge: String?

    var body: some View {
        HStack(spacing: 14) {
            ModuleIconTile(tab: tab, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title).font(.title3.weight(.heavy)).foregroundStyle(.primary)
                Text(tab.subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72))
                if let badge {
                    Text(badge).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.navy)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.yellow, in: Capsule())
                        .padding(.top, 3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(.primary.opacity(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .okuSurface()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([tab.title, badge, tab.subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

struct PressableCardStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Bütün ekranlarda Ana Sayfa düzeni (17 Eki 2026)

/// Modül ekranlarının başındaki lacivert kart: sarı üst satır (modül adı), büyük beyaz başlık, açıklama ve isteğe bağlı içerik
/// (durum satırları, sarı uyarı düğmesi gibi). Ana Sayfa'daki selamlama kartıyla aynı görünüm.
struct ScreenHero<Extra: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow).font(.headline).foregroundStyle(Theme.yellow)
                Spacer(minLength: 8)
                if let symbol { Image(systemName: symbol).font(.title2.weight(.bold)).foregroundStyle(Theme.yellow).accessibilityHidden(true) }
            }
            Text(title).font(.system(.title, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.headline.weight(.medium)).foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            extra
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension ScreenHero where Extra == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

/// Bölüm başlığı: Ana Sayfa'daki "Modüller" gibi büyük ve kalın; isteğe bağlı açıklama.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72)) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Büyük satır: Ana Sayfa'daki modül satırının genel hâli. Dolgulu simge karosu, kalın başlık, açıklama,
/// isteğe bağlı sarı rozet ve ok. `tone`: mavi (beyaz simge), sarı (lacivert simge) ya da lacivert (sarı simge).
struct BigRow: View {
    enum Tone { case blue, yellow, navy, sky }
    let title: String
    var detail: String? = nil
    let symbol: String
    var tone: Tone = .blue
    var badge: String? = nil
    var showsChevron = true

    private var tile: (AnyShapeStyle, Color) {
        switch tone {
        case .blue: (AnyShapeStyle(Theme.gradient), .white)
        case .yellow: (AnyShapeStyle(Theme.warmGradient), Theme.navy)
        case .navy: (AnyShapeStyle(Theme.navy), Theme.yellow)
        case .sky: (AnyShapeStyle(Theme.sky), Theme.navy)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ModuleIconTile(symbol: symbol, fill: tile.0, foreground: tile.1, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline.weight(.heavy)).foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72))
                }
                if let badge {
                    Text(badge).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.navy)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.yellow, in: Capsule())
                        .padding(.top, 3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(.primary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .okuSurface()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
