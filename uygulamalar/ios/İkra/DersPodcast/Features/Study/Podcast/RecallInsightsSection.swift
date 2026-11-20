import Charts
import SwiftData
import SwiftUI

/// #27: Gelişim'de geri çağırma günlüğü: 1/7/30. gün kalıcılık eğrisi ve eminlik kalibrasyonu.
struct RecallInsightsSection: View {
    @Query(sort: \RecallAttempt.createdAt, order: .reverse) private var attempts: [RecallAttempt]

    private var samples: [RecallStats.Sample] {
        attempts.prefix(2000).map { RecallStats.Sample(isCorrect: $0.isCorrect, confidence: $0.confidence, daysSinceListen: $0.daysSinceListen, source: $0.source) }
    }

    var body: some View {
        let retention = RecallStats.retention(samples)
        let calibration = RecallStats.calibration(samples)
        VStack(alignment: .leading, spacing: 16) {
            Label("Hatırlama günlüğü", systemImage: "brain.head.profile").font(.headline)
            if attempts.isEmpty {
                Text("Quiz, deneme, Sokratik, Feynman ve yoklama sonuçların burada birikir; zamanla ne kadarının kalıcı olduğunu görürsün.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("\(attempts.count) deneme · son 7 günde \(attempts.filter { $0.createdAt > .now.addingTimeInterval(-7 * 86_400) }.count)")
                    .font(.caption).foregroundStyle(.secondary)
                chart("Kalıcılık (dinledikten sonra)", points: retention, color: .accentColor)
                if calibration.contains(where: { $0.count > 0 }) {
                    chart("Eminlik ve gerçek doğruluk", points: calibration, color: .orange)
                    if let note = RecallStats.calibrationNote(calibration) {
                        Text(note).font(.callout)
                    }
                } else {
                    Text("Sınav modunda şık seçerken \"Tahmin / Sanırım / Eminim\" dersen kalibrasyonun da görünür.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chart(_ title: String, points: [RecallStats.Point], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart(points, id: \.label) { point in
                BarMark(x: .value("Dönem", point.label), y: .value("Doğruluk", (point.accuracy ?? 0) * 100))
                    .foregroundStyle(color.opacity(point.accuracy == nil ? 0.2 : 0.85))
                    .annotation(position: .top) {
                        Text(point.accuracy.map { "%\(Int(($0 * 100).rounded()))" } ?? "–").font(.caption2.monospacedDigit())
                    }
            }
            .chartYScale(domain: 0...110)
            .chartYAxis(.hidden)
            .frame(height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(points.map { "\($0.label): " + ($0.accuracy.map { "yüzde \(Int(($0 * 100).rounded()))" } ?? "veri yok") }.joined(separator: ", "))
            Text(points.map { "\($0.label): \($0.count)" }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
