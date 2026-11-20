import SwiftUI

struct SpiritualView: View {
    @State private var search = ""
    @State private var showKaza = false
    @AppStorage("tools.favorites") private var favoritesRaw = "tesbih,dua"
    private var favorites: Set<String> { Set(favoritesRaw.split(separator: ",").map(String.init)) }
    private let tools: [(id: String, title: String, subtitle: String, icon: String)] = [
        ("elifba", "Kur’an Öğreniyorum", "Elif Bâ, sesli dersler ve alıştırmalar", "graduationcap"),
        ("tesbih", "Zikirmatik", "Her dokunuşta bir zikir", "circle.dotted"),
        ("dua", "Dua kütüphanesi", "Günün her anına dualar", "hands.sparkles"),
        ("esma", "Esmaü’l Hüsna", "99 isim, anlam ve dinleme", "sparkles"),
        ("quran", "Kelime meal", "Kur’an’ı kelime kelime okuyun", "book.closed"),
        ("kaza", "Kaza takibi", "Namaz ve oruç kayıtlarınız", "checkmark.circle"),
        ("mosque", "Yakındaki camiler", "Harita ve yol tarifi", "building.columns"),
        ("calendar", "Vakit takvimi", "Aylık namaz vakitleri", "calendar"),
        ("settings", "Ayarlar", "Görünüm, konum ve bildirimler", "slider.horizontal.3")
    ]
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    EzanPageHeader(eyebrow: "Kendinize bir vakit ayırın", title: "Maneviyat", subtitle: "Günlük ibadetleriniz için küçük yardımcılar.")
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
                        TextField("Dua, zikir veya araç ara", text: $search).font(.subheadline)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Aramayı temizle") }
                    }.padding(16).sekineCard()
                    if search.isEmpty {
                        NavigationLink { TesbihView() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("GÜNÜN İÇİNDE BİR MOLA").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(EzanDesign.gold)
                                    Text("Zikre vakit ayırın.").font(.system(.title2, design: .serif))
                                    Label("Zikirmatiği aç", systemImage: "arrow.right").font(.caption.weight(.semibold)).padding(.top, 5)
                                }
                                Spacer()
                                Image(systemName: "circle.dotted").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(EzanDesign.gold)
                            }.foregroundStyle(.white).padding(24).background(EzanDesign.heroGradient.overlay { EzanPattern() }).clipShape(RoundedRectangle(cornerRadius: 26))
                        }.buttonStyle(EzanPressStyle())
                    }
                    EzanSectionTitle(title: search.isEmpty ? "Keşfet" : "Arama sonuçları", detail: "★ Favoriye ekle")
                    let filtered = tools.filter { search.isEmpty || ($0.title + " " + $0.subtitle).localizedStandardContains(search) }
                        .sorted { favorites.contains($0.id) && !favorites.contains($1.id) }
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                    LazyVStack(spacing: 12) {
                        ForEach(filtered, id: \.id) { item in
                            HStack(spacing: 0) {
                                NavigationLink { destination(item.id) } label: {
                                    EzanFeatureLabel(title: item.title, subtitle: item.subtitle, icon: item.icon)
                                }.buttonStyle(EzanPressStyle())
                                Button {
                                    var saved = favorites
                                    if saved.contains(item.id) { saved.remove(item.id) } else { saved.insert(item.id) }
                                    favoritesRaw = saved.sorted().joined(separator: ",")
                                } label: {
                                    Image(systemName: favorites.contains(item.id) ? "star.fill" : "star")
                                        .font(.subheadline).foregroundStyle(favorites.contains(item.id) ? Palette.gold : Palette.textSecondary)
                                        .frame(width: 44, height: 60)
                                }.accessibilityLabel("\(item.title), favori \(favorites.contains(item.id) ? "kaldır" : "ekle")")
                            }
                        }
                    }
                }.padding(20).padding(.bottom, 20)
            }.background(Palette.background).toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showKaza) { KazaView() }
                .task { if ProcessInfo.processInfo.arguments.contains("-uiTestShowKaza") { showKaza = true } }
        }
    }
    @ViewBuilder private func destination(_ id: String) -> some View {
        switch id {
        case "elifba": ElifBaView()
        case "tesbih": TesbihView()
        case "dua": DuaView()
        case "esma": EsmaulHusnaView()
        case "quran": KuranBilmekView()
        case "kaza": KazaView()
        case "mosque": NearbyMosquesView()
        case "calendar": MonthlyView()
        default: SettingsView()
        }
    }
}
