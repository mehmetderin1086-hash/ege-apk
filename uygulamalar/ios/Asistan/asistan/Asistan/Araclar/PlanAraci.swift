import Foundation
import FoundationModels
import Observation

/// Hermes `todo` / OpenClaw plan özelliği: uzun işlerde asistanın tuttuğu, kullanıcıya görünen yapılacaklar listesi.
nonisolated struct PlanMaddesi: Identifiable, Equatable, Sendable {
    enum Durum: String, Sendable { case bekliyor, suruyor, bitti
        var simge: String { switch self { case .bekliyor: "○"; case .suruyor: "◐"; case .bitti: "●" } }
    }
    let id = UUID()
    var metin: String
    var durum: Durum = .bekliyor
}

@MainActor @Observable
final class PlanDefteri {
    static let ortak = PlanDefteri()
    static let enFazlaMadde = 12
    private(set) var maddeler: [PlanMaddesi] = []
    /// P3.5: planı uygulama (süzgecin `teslimler` listesinden) kurduysa o isteğin nesli; model kendisi kurduysa nil.
    private(set) var uygulamaNesli: Int?

    func olustur(_ metinler: [String], uygulamaNesli: Int? = nil) {
        maddeler = metinler.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .prefix(Self.enFazlaMadde).map { PlanMaddesi(metin: String($0.prefix(140))) }
        self.uygulamaNesli = uygulamaNesli
    }
    /// Bitmemiş maddelerin metinleri.
    var bekleyenler: [String] { maddeler.filter { if case .bitti = $0.durum { false } else { true } }.map(\.metin) }
    /// Uygulama yeni plan kurabilir mi: plan boş, hepsi bitmiş ya da önceki plan da uygulamanınsa (modelin süren planı ezilmez).
    var uygulamaPlaniKurabilir: Bool { uygulamaNesli != nil || bekleyenler.isEmpty }
    /// `sira` 1'den başlar. Geçersizse false.
    @discardableResult
    func durumVer(sira: Int, durum: PlanMaddesi.Durum) -> Bool {
        guard maddeler.indices.contains(sira - 1) else { return false }
        maddeler[sira - 1].durum = durum
        return true
    }
    func temizle() { maddeler = []; uygulamaNesli = nil }
    var metin: String {
        maddeler.isEmpty ? "Plan boş." : maddeler.enumerated().map { "\($0.offset + 1). \($0.element.durum.simge) \($0.element.metin)" }.joined(separator: "\n")
    }
}

nonisolated struct PlanAraci: Tool {
    let name = "plan"
    let description = "Çok adımlı (3+ adım) işlerde yapılacaklar listesi tutar; kullanıcı ilerlemeyi görür. 'olustur' (maddeler: adımlar), 'guncelle' (sira: 1'den başlayan numara, durum: 'bekliyor'/'suruyor'/'bitti'), 'goster', 'temizle'. Tek adımlık işlerde kullanma."

    @Generable
    struct Arguments {
        @Guide(description: "'olustur', 'guncelle', 'goster' ya da 'temizle'") var islem: String
        @Guide(description: "olustur: kısa adım metinleri (en çok 12)") var maddeler: [String]?
        @Guide(description: "guncelle: madde numarası (1'den başlar)") var sira: Int?
        @Guide(description: "guncelle: 'bekliyor', 'suruyor' ya da 'bitti'") var durum: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        await MainActor.run {
            let p = PlanDefteri.ortak
            switch a.islem.lowercased() {
            case "olustur":
                guard let m = a.maddeler, !m.isEmpty else { return "Madde verilmedi." }
                p.olustur(m); return "Plan oluşturuldu:\n" + p.metin
            case "guncelle":
                guard let s = a.sira, let d = PlanMaddesi.Durum(rawValue: (a.durum ?? "").lowercased()), p.durumVer(sira: s, durum: d) else { return "Geçersiz sıra ya da durum." }
                return p.metin
            case "temizle": p.temizle(); return "Plan temizlendi."
            default: return p.metin
            }
        }
    }
}
