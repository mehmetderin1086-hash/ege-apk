import SwiftUI

/// Geçen süre gösterimi: "3,4 sn", "27 sn", "1 dk 5 sn".
nonisolated enum SureBicimi {
    static func metin(_ s: TimeInterval) -> String {
        let t = max(0, s)
        if t < 10 { return String(format: "%.1f", t).replacingOccurrences(of: ".", with: ",") + " sn" }
        if t < 60 { return "\(Int(t.rounded(.down))) sn" }
        return "\(Int(t) / 60) dk \(Int(t) % 60) sn"
    }
    /// " · model · düşünme: orta" (boş parçalar atlanır).
    static func ek(_ a: String?) -> String { a.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? "" }
    static func ayrinti(model: String?, caba: String?) -> String {
        [model, caba.map { "düşünme: \($0.lowercased())" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Canlı sayaç (`baslangic`'tan beri) ya da, süre biliniyorsa, sabit etiket.
struct SureEtiketi: View {
    var baslangic: Date?
    var sabit: TimeInterval?
    /// Süreden sonra küçük harfle eklenen model/düşünme bilgisi.
    var ayrinti: String? = nil
    var body: some View {
        Group {
            if let sabit { Text(SureBicimi.metin(sabit) + SureBicimi.ek(ayrinti)) }
            else if let baslangic {
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in Text(SureBicimi.metin(ctx.date.timeIntervalSince(baslangic)) + SureBicimi.ek(ayrinti)).monospacedDigit() }
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}
