import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.42, green: 0.30, blue: 0.95)
private let warm = Color(red: 0.97, green: 0.42, blue: 0.45)

struct GenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GenerationActivityAttributes.self) { context in
            // Kilit ekranı / bildirim
            HStack(spacing: 14) {
                Image(systemName: context.state.finished ? "checkmark.circle.fill" : "waveform")
                    .font(.title)
                    .foregroundStyle(context.state.finished ? .green : accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Text(statusText(context.state)).font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: fraction(context.state))
                        .tint(accent)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
            // #46: dokununca üretim ekranı (kocum://generation/<UUID>).
            .widgetURL(link(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.finished ? "checkmark.circle.fill" : "waveform")
                        .font(.title2)
                        .foregroundStyle(context.state.finished ? .green : accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentText(context.state)).font(.title3.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.subheadline.bold()).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: fraction(context.state)).tint(accent)
                        Text(statusText(context.state)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.finished ? "checkmark" : "waveform")
                    .foregroundStyle(context.state.finished ? .green : warm)
            } compactTrailing: {
                Text(percentText(context.state)).font(.caption2.monospacedDigit().bold())
            } minimal: {
                Image(systemName: context.state.finished ? "checkmark" : "waveform")
                    .foregroundStyle(warm)
            }
            .widgetURL(link(context.attributes))
        }
    }

    private func link(_ attributes: GenerationActivityAttributes) -> URL? {
        UUID(uuidString: attributes.episodeID).map { AppLink.generation($0).url }
    }

    private func fraction(_ s: GenerationActivityAttributes.ContentState) -> Double {
        if s.finished { return 1 }
        if let overall = s.fraction { return min(max(overall, 0), 1) }
        return Double(s.done) / Double(max(s.total, 1))
    }

    private func percentText(_ s: GenerationActivityAttributes.ContentState) -> String {
        "%\(Int((fraction(s) * 100).rounded()))"
    }

    private func statusText(_ s: GenerationActivityAttributes.ContentState) -> String {
        if s.finished { return "Bölüm hazır, dinlemeye başlayabilirsin" }
        if let detail = s.detail, !detail.isEmpty { return detail }
        return "\(s.phase) · \(s.done)/\(s.total) sahne"
    }
}
