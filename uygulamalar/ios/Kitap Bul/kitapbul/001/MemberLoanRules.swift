import SwiftUI

nonisolated struct MemberLoanRule: Codable, Equatable, Identifiable, Sendable {
    var kind: MemberKind
    var durationDays: Int = 15
    /// 0 = sınırsız; ayarlanmadığında genel kural geçerlidir.
    var maximumLoans: Int = 3
    var id: MemberKind { kind }
}

enum MemberLoanRuleStore {
    static let key = "memberLoanRules"
    static func all(defaults: UserDefaults = .standard) throws -> [MemberLoanRule] {
        guard defaults.object(forKey: key) != nil else { return [] }
        guard let data = defaults.data(forKey: key) else {
            throw FullArchive.ValidationError(message: "Üye süre/kota ayarı bozuk; genel kurala sessizce dönülmedi.")
        }
        let list = try JSONDecoder().decode([MemberLoanRule].self, from: data)
        try validate(list); return list
    }
    static func rule(for kind: MemberKind?, defaults: UserDefaults = .standard) throws -> MemberLoanRule? {
        let list = try all(defaults: defaults)
        return list.first { $0.kind == kind }
    }
    static func save(_ list: [MemberLoanRule], defaults: UserDefaults = .standard) throws {
        try SchoolLibraryService.requireAdmin()
        try validate(list); defaults.set(try JSONEncoder().encode(list), forKey: key)
    }
    nonisolated static func validate(_ list: [MemberLoanRule]) throws {
        guard Set(list.map(\.kind)).count == list.count,
              list.allSatisfy({ (1...365).contains($0.durationDays) && (0...99).contains($0.maximumLoans) }) else {
            throw FullArchive.ValidationError(message: "Üye kuralı yineleniyor veya süre/kota geçersiz. Önce kuralları düzeltin.")
        }
    }
}

struct MemberLoanRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [MemberLoanRule] = []
    @State private var saved: [MemberLoanRule] = []
    @State private var error: String?
    @State private var discard = false
    var body: some View {
        Form {
            Section {
                Text("Yalnız eklediğiniz üye türleri için özel kural uygulanır. Diğer üyeler genel süre ve kotayı kullanır; türü belirtilmemiş eski kayıtlar kendiliğinden sınıflandırılmaz.")
            }
            ForEach($rules) { $rule in
                Section(rule.kind.title) {
                    Stepper("Süre: \(rule.durationDays) gün", value: $rule.durationDays, in: 1...365)
                    Stepper(rule.maximumLoans == 0 ? "Kota: sınırsız" : "Kota: \(rule.maximumLoans) kitap", value: $rule.maximumLoans, in: 0...99)
                    Button("Genel Kurala Dön", role: .destructive) { rules.removeAll { $0.kind == rule.kind } }
                }
            }
            Section {
                ForEach(MemberKind.allCases.filter { kind in !rules.contains(where: { $0.kind == kind }) }) { kind in
                    Button("\(kind.title) İçin Özel Kural Ekle") { rules.append(MemberLoanRule(kind: kind)) }
                }
                if let error {
                    // Hata yalnız renkle değil, uyarı ikonuyla ayrışır
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(RenkliIkonEtiketi(renk: KitapTema.vurgu))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Üye Kuralları")
        .navigationBarBackButtonHidden(rules != saved)
        .toolbar {
            if rules != saved { ToolbarItem(placement: .cancellationAction) { Button("Geri") { discard = true } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") {
                    Task {
                        do {
                            try await YetkiKapisi.yoneticiyleCalistir(neden: "Üye kurallarını kaydetmek için kimliğinizi doğrulayın") { try MemberLoanRuleStore.save(rules) }
                            saved = rules; error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(rules == saved)
            }
        }
        .confirmationDialog("Değişiklikler kaydedilmedi", isPresented: $discard, titleVisibility: .visible) {
            Button("Kaydetmeden Kapat", role: .destructive) { dismiss() }
            Button("Düzenlemeye Dön", role: .cancel) { }
        }
        .onAppear {
            do { rules = try MemberLoanRuleStore.all(); saved = rules }
            catch { self.error = error.localizedDescription }
        }
    }
}
