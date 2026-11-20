import SwiftUI

/// #47: bölümün üretim süresi ve tahmini maliyeti.
struct GenerationStatsCard: View {
    let episode: Episode

    var body: some View {
        if let stats = episode.generationStats {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    // Eski bölümlerin kaydında artık bulunmayan bir motor adı olabilir.
                    row("Ses motoru", SpeechEngine(rawValue: stats.engine)?.title ?? (stats.engine == "gemini" ? "Önceki ses motoru (kaldırıldı)" : stats.engine))
                    if let model = stats.scriptModel { row("Senaryo modeli", model) }
                    if let s = stats.scriptSeconds { row("Senaryo", Self.duration(s)) }
                    if let s = stats.voiceSeconds { row("Seslendirme", Self.duration(s)) }
                    if let s = stats.mixSeconds { row("Birleştirme", Self.duration(s)) }
                    row("Metin", "\(stats.characters.formatted()) karakter · \(stats.scenes) sahne")
                    if stats.retakes > 0 { row("Yeniden üretilen sahne", "\(stats.retakes)") }
                    row("Tahmini maliyet", Self.cost(stats.estimatedCostUSD))
                }
                .font(.subheadline)
            } label: {
                Label("Üretim karnesi", systemImage: "gauge.with.dots.needle.33percent")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(.secondary).font(.caption)
                Text(value)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "1 dk 20 sn", "45 sn", "1 sa 5 dk"
    nonisolated static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) sn" }
        if total < 3600 {
            let s = total % 60
            return s == 0 ? "\(total / 60) dk" : "\(total / 60) dk \(s) sn"
        }
        let m = (total % 3600) / 60
        return m == 0 ? "\(total / 3600) sa" : "\(total / 3600) sa \(m) dk"
    }

    nonisolated static func cost(_ usd: Double) -> String {
        guard usd > 0.00005 else { return "Ücretsiz" }
        return "≈ " + usd.formatted(.number.precision(.fractionLength(usd < 0.1 ? 3 : 2)).locale(Locale(identifier: "tr_TR"))) + " $"
    }
}
