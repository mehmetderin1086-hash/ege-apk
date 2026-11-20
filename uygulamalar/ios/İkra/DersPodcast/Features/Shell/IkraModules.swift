import SwiftUI

/// Modül kimliği (17 Eki 2026 arayüz yenilemesi): her modülün adı, simgesi, açıklaması ve kendi rengi.
/// Ana Sayfa kartları, alt çubuk ve Ayarlar'daki modül bölümleri bu tek tablodan beslenir.
extension AppState.MainTab {
    /// Ana Sayfa ızgarasındaki sırayla yedi modül.
    static let modules: [AppState.MainTab] = [.library, .questions, .topics, .study, .courses, .exams, .visuals]

    var title: String {
        switch self {
        case .home: "Ana Sayfa"
        case .library: "Kitaplık"
        case .questions: "Soru Çöz"
        case .topics: "Video"
        case .study: "Çalış"
        case .courses: "Plan"
        case .exams: "Sınav Oku"
        case .visuals: "Görseller"
        case .settings: "Ayarlar"
        }
    }

    /// Kartta başlığın altında görünen kısa açıklama.
    var subtitle: String {
        switch self {
        case .home: "Bütün modüller"
        case .library: "Kitaplar, podcast'ler, belgeler"
        case .questions: "Fotoğraf çek, adım adım çözüm"
        case .topics: "Konu anlatım videoları"
        case .study: "Tekrar, quiz, odak, yanlışlar"
        case .courses: "Dersler ve çalışma planı"
        case .exams: "El yazısı sınavı puanla"
        case .visuals: "Şekil ve resim kütüphanesi"
        case .settings: "Bütün ayarlar tek yerde"
        }
    }

    /// Kartın altındaki modül rengindeki eylem bağlantısı.
    var cta: String {
        switch self {
        case .home: "Aç"
        case .library: "Kitaplığı aç"
        case .questions: "Kamerayı aç"
        case .topics: "Videoları izle"
        case .study: "Çalışmaya başla"
        case .courses: "Planı gör"
        case .exams: "Kâğıt oku"
        case .visuals: "Kütüphaneyi aç"
        case .settings: "Ayarları aç"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .library: "books.vertical.fill"
        case .questions: "camera.viewfinder"
        case .topics: "play.rectangle.fill"
        case .study: "square.stack.fill"
        case .courses: "calendar"
        case .exams: "checkmark.rectangle.stack.fill"
        case .visuals: "photo.stack.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Modülün ana rengi: simge karosu, rozet ve vurgu. Yalnız mavi ve sarı tonları; modüller ayrıca simge ve adla ayrılır
    /// (renk tek başına bilgi taşımaz). Koyu modda mavi tonlar açılır, sarılar olduğu gibi kalır.
    var color: Color {
        let (r, g, b) = colorStops.0
        let light = isLight
        return Color(uiColor: UIColor { traits in
            let k = traits.userInterfaceStyle == .dark && !light ? 0.35 : 0
            return UIColor(red: r + (1 - r) * k, green: g + (1 - g) * k, blue: b + (1 - b) * k, alpha: 1)
        })
    }

    /// Sarı modüller açık renklidir: üstlerine lacivert yazılır; mavilerin üstüne beyaz.
    var isLight: Bool { [.questions, .courses, .visuals].contains(self) }

    /// Modül renginin üstündeki yazı/simge rengi (en az 4.5:1 kontrast).
    var onColor: Color { isLight ? Theme.navy : .white }

    var gradient: LinearGradient {
        let (a, b) = colorStops
        return LinearGradient(colors: [Color(red: a.0, green: a.1, blue: a.2), Color(red: b.0, green: b.1, blue: b.2)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var colorStops: ((Double, Double, Double), (Double, Double, Double)) {
        switch self {
        case .home: ((0.039, 0.122, 0.290), (0.082, 0.329, 0.800))     // lacivert → mavi
        case .library: ((0.082, 0.329, 0.800), (0.165, 0.443, 0.910))  // kraliyet mavisi
        case .questions: ((1.000, 0.835, 0.290), (0.980, 0.729, 0.090)) // sarı
        case .topics: ((0.055, 0.180, 0.450), (0.110, 0.290, 0.640))   // lacivert
        case .study: ((0.090, 0.478, 0.890), (0.235, 0.557, 0.965))    // gök mavisi
        case .courses: ((0.961, 0.651, 0.000), (0.990, 0.760, 0.180))  // kehribar
        case .exams: ((0.180, 0.250, 0.700), (0.260, 0.350, 0.820))    // çivit mavisi
        case .visuals: ((1.000, 0.760, 0.150), (1.000, 0.860, 0.400))  // altın sarısı
        case .settings: ((0.200, 0.280, 0.420), (0.300, 0.380, 0.520)) // arduvaz mavisi
        }
    }
}

/// Canlı tutulan modüllerde sekme yaşam döngüsü yerine geçer: modül ekrandayken `true`.
/// Görünmeyen modülde onAppear/onDisappear tetiklenmediği için yoklama gibi işler buna bakar.
extension EnvironmentValues {
    @Entry var isModuleActive = true
}

/// `onDisappear`'ın canlı modül karşılığı: sayfa kapanınca da, modül alt çubukla arka plana alınınca da çalışır.
/// Eski TabView'da sekme değişince görünen sayfanın onDisappear'ı tetiklenirdi; ses durdurma ve kaydetme buna dayanıyor.
private struct LeaveModifier: ViewModifier {
    @Environment(\.isModuleActive) private var moduleActive
    let action: () -> Void
    func body(content: Content) -> some View {
        content
            .onDisappear(perform: action)
            .onChange(of: moduleActive) { _, active in if !active { action() } }
    }
}

extension View {
    func onLeave(perform action: @escaping () -> Void) -> some View { modifier(LeaveModifier(action: action)) }
}

/// Her modülün sağ üstteki tek "İşlemler" menüsü (dağınık düğmeler yerine): modülün araçları, en altta o modülün ayarları.
/// Ayarlar her zaman merkezi Ayarlar sayfasında açılır; modülün kendi ayar sayfası yoksa genel Ayarlar gelir.
struct ModuleMenu<Content: View>: View {
    @Environment(AppState.self) private var app
    let module: AppState.MainTab
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
            Divider()
            Button(module.title + " ayarları", systemImage: "gearshape") {
                if SettingsPage.modulePages.contains(.module(module)) { app.settingsRoute = .module(module) } else { app.selectedTab = .settings }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3.weight(.semibold))
        }
        .accessibilityLabel(module.title + " işlemleri ve ayarları")
    }
}

/// Modül ekranlarının sol üstündeki Ana Sayfa düğmesi (alt çubuk kaldırıldı, 17 Eki 2026): modüller arası geçiş Ana Sayfa'dan.
struct HomeButton: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Button { app.selectedTab = .home } label: {
            Label("Ana Sayfa", systemImage: "house.fill").labelStyle(.titleAndIcon).font(.headline.weight(.bold))
        }
        .accessibilityHint("Bütün modüllerin listesine döner")
    }
}
