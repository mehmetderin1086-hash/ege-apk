import Foundation
import SwiftUI

nonisolated enum HomePrimaryTask: String, CaseIterable, Identifiable, Hashable, Sendable {
    case lend, returnLoan, addBook
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lend: "Ödünç ver"
        case .returnLoan: "İade al"
        case .addBook: "Kitap ekle"
        }
    }
    var icon: String {
        switch self {
        case .lend: "person.crop.rectangle.badge.plus"
        case .returnLoan: "arrow.uturn.left"
        case .addBook: "plus.viewfinder"
        }
    }
}

/// JSON'da görünen adlar değil sabit kimlikler saklanır; Türkçe başlık değişebilir.
nonisolated enum HomeQuickAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case barcode, cover, voice, loan, serial, manual, assistant, management
    var id: String { rawValue }
    var title: String {
        switch self {
        case .barcode: "Barkod"
        case .cover: "Kapak"
        case .voice: "Sesle"
        case .loan: "Ödünç"
        case .serial: "Seri"
        case .manual: "Elle"
        case .assistant: "Asistan"
        case .management: "Yönetim"
        }
    }
    var icon: String {
        switch self {
        case .barcode: "barcode.viewfinder"
        case .cover: "text.viewfinder"
        case .voice: "mic.fill"
        case .loan: "person.crop.rectangle.badge.plus"
        case .serial: "barcode"
        case .manual: "square.and.pencil"
        case .assistant: "waveform.and.mic"
        case .management: "square.grid.2x2"
        }
    }
    /// VoiceOver ipucu. Başlıklar kısa kalır (kimlik ve kayıtlı tercih sözleşmesi); işi ipucu anlatır.
    var ipucu: String {
        switch self {
        case .barcode: "Barkodla kitap ekler"
        case .cover: "Canlı Kapak ile kitap ekler"
        case .voice: "Sesle kitap ekler"
        case .loan: "Öğrenci kartı ve kitap barkoduyla ödünç verir"
        case .serial: "Seri taramayla kitapları art arda ekler"
        case .manual: "Kitap bilgilerini elle yazarak ekler"
        case .assistant: "Asistanı açar ve dinlemeye başlar"
        case .management: "Yönetim sekmesine geçer"
        }
    }
}

/// Tercih yalnız ek kısayolları taşır; üç ana görev hiçbir tercihle silinemez/sıralanamaz.
nonisolated struct HomeQuickActionPreferences: Equatable, Sendable {
    static let key = "homeQuickActionsV1"
    /// Test fixtures never read or write the user's production preference.
    static let uiTestKey = "ui-testing.homeQuickActionsV1"
    static var storageKey: String {
        TestEnvironment.isUITesting ? uiTestKey : key
    }
    static let primaryTasks: [HomePrimaryTask] = [.lend, .returnLoan, .addBook]
    /// Ödünç açma eski callback'i seçilebilir; ana Ödünç ver düğmesi zaten sabittir.
    static let defaults = Self(actions: [.barcode, .cover, .voice, .serial, .manual, .assistant, .management])
    static var defaultRaw: String { defaults.encoded }
    private(set) var actions: [HomeQuickAction]

    init(actions: [HomeQuickAction]) {
        var seen = Set<HomeQuickAction>()
        self.actions = actions.filter { seen.insert($0).inserted }
    }

    static func load(_ raw: String) -> Self {
        guard raw.utf8.count <= 16_384, let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return defaults }
        if ids.isEmpty { return Self(actions: []) } // Kullanıcının bilinçli boş seçimi korunur.
        let valid = ids.compactMap(HomeQuickAction.init(rawValue:))
        guard !valid.isEmpty else { return defaults }
        return Self(actions: valid)
    }

    var encoded: String {
        // Bu veri yalnız sekiz bilinen enum ID'sidir; kullanıcı/anahtar bilgisi içermez.
        let data = (try? JSONEncoder().encode(actions.map(\.rawValue))) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    var available: [HomeQuickAction] { HomeQuickAction.allCases.filter { !actions.contains($0) } }
    func visibleActions(simpleMode: Bool) -> [HomeQuickAction] {
        simpleMode ? Array(actions.prefix(3)) : actions
    }
    mutating func add(_ action: HomeQuickAction) { if !actions.contains(action) { actions.append(action) } }
    mutating func remove(_ action: HomeQuickAction) { actions.removeAll { $0 == action } }
    mutating func move(_ action: HomeQuickAction, by step: Int) {
        guard step == -1 || step == 1, let index = actions.firstIndex(of: action),
              actions.indices.contains(index + step) else { return }
        actions.swapAt(index, index + step)
    }
}

extension HomeQuickAction {
    @MainActor var tint: Color {
        switch self {
        case .barcode: KitapTema.ana
        case .cover: KitapTema.foto
        case .voice: KitapTema.amazon
        case .loan: KitapTema.toplu
        case .serial, .management: KitapTema.dosya
        case .manual: .gray
        case .assistant: KitapTema.vurgu
        }
    }
}

/// Açık Kaydet/Vazgeç işlemi; seçimler kayıt yapılıncaya kadar yalnız yerel taslaktır.
struct HomeQuickActionsConfiguration: View {
    @Binding private var rawPreferences: String
    @State private var draft: HomeQuickActionPreferences
    @State private var previous: HomeQuickActionPreferences?
    @State private var showingDiscard = false
    @Environment(\.dismiss) private var dismiss
    private let initial: HomeQuickActionPreferences

    init(rawPreferences: Binding<String>) {
        _rawPreferences = rawPreferences
        let loaded = HomeQuickActionPreferences.load(rawPreferences.wrappedValue)
        _draft = State(initialValue: loaded)
        initial = loaded
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeQuickActionPreferences.primaryTasks) { task in
                        Label(task.title, systemImage: task.icon)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                } header: { Text("Her zaman ilk sırada") }
                footer: { Text("Ödünç ver, iade al ve kitap ekle görevleri sabittir.") }

                Section {
                    if draft.actions.isEmpty {
                        Text("Ek kısayol seçilmedi. Aşağıdan istediğinizi ekleyin.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(draft.actions) { action in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(action.title, systemImage: action.icon).font(.headline)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { orderButtons(action) }
                                VStack(alignment: .leading, spacing: 8) { orderButtons(action) }
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("home.configure.selected.\(action.rawValue)")
                    }
                } header: { Text("Seçili ek kısayollar") }
                footer: { Text("Sade modda seçili ilk üç ek kısayol görünür. Tam düzende bütün seçimleriniz korunur.") }

                if !draft.available.isEmpty {
                    Section {
                        ForEach(draft.available) { action in
                            Button { change { $0.add(action) } } label: {
                                Label("\(action.title) ekle", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("home.configure.add.\(action.rawValue)")
                        }
                    } header: { Text("Ekleyebileceğiniz kısayollar") }
                }

                Section {
                    Button("Son düzenlemeyi geri al", systemImage: "arrow.uturn.backward") {
                        if let previous { draft = previous; self.previous = nil }
                    }.disabled(previous == nil).frame(minHeight: 44)
                    Button("Varsayılana dön", systemImage: "arrow.counterclockwise") {
                        change { $0 = .defaults }
                    }.frame(minHeight: 44)
                }
            }
            .buttonStyle(.bordered)
            .navigationTitle("Hızlı işlemleri düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if draft != initial { showingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() } }
            }
            .interactiveDismissDisabled(draft != initial)
            .confirmationDialog("Düzenleme kaydedilmedi", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Düzenlemeye dön", role: .cancel) { }
                Button("Kaydet") { save() }
                Button("Kaydetmeden kapat", role: .destructive) { dismiss() }
            }
        }
    }

    @ViewBuilder private func orderButtons(_ action: HomeQuickAction) -> some View {
        Button("Yukarı", systemImage: "arrow.up") { change { $0.move(action, by: -1) } }
            .disabled(draft.actions.first == action)
            .frame(minHeight: 44)
            .accessibilityLabel("\(action.title) kısayolunu yukarı taşı")
        Button("Aşağı", systemImage: "arrow.down") { change { $0.move(action, by: 1) } }
            .disabled(draft.actions.last == action)
            .frame(minHeight: 44)
            .accessibilityLabel("\(action.title) kısayolunu aşağı taşı")
        Button("Kaldır", systemImage: "minus.circle") { change { $0.remove(action) } }
            .frame(minHeight: 44)
            .accessibilityLabel("\(action.title) kısayolunu kaldır")
    }

    private func change(_ mutation: (inout HomeQuickActionPreferences) -> Void) {
        let before = draft
        mutation(&draft)
        if before != draft { previous = before }
    }
    private func save() { rawPreferences = draft.encoded; dismiss() }
}
