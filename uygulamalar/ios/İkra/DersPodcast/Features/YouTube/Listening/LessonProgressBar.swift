import SwiftUI

/// Ders ilerleme çubuğu: sürüklenerek konum seçilir, altında geri sarma ısı şeridi (turuncu = çok geri sarılan yer),
/// A–B döngü aralığı yeşil bantla gösterilir. Konum her 0,1–0,2 sn değiştiği için ayrı görünüm.
struct LessonProgressBar: View {
    var player: VideoPlayerModel
    /// Dersin geri sarma anları (`VideoLesson.rewindTimes`).
    var rewindTimes: [Double]

    @State private var dragTime: Double?
    @State private var buckets: [Double] = []

    private static let bucketCount = 60

    var body: some View {
        let duration = max(player.duration, 0)
        let shown = min(max(dragTime ?? player.currentTime, 0), max(duration, 0.001))
        let fraction = duration > 0 ? shown / duration : 0
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width
                let handleX = width * CGFloat(fraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                    if let loop = player.loop, duration > 0 {
                        Capsule().fill(Color.green.opacity(0.45))
                            .frame(width: max(3, width * (loop.end - loop.start) / duration), height: 6)
                            .offset(x: width * loop.start / duration)
                    }
                    Capsule().fill(Color.accentColor).frame(width: width * fraction, height: 6)
                    Circle().fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 1)
                        .offset(x: min(max(width * fraction - 8, 0), max(width - 16, 0)))
                }
                .frame(maxHeight: .infinity)
                // Sürüklerken hedef an: tutamacın üstünde, uçlarda çubuğun içinde kalır (parmak çubuğu örter, süre etiketi
                // ancak bırakınca değişir). Koşulsuz çizilir ki hizalama kılavuzları doğrudan kabarcığa ait olsun.
                .overlay(alignment: .topLeading) {
                    Text(dragTime.map { ScrubPreview.label(target: $0, current: player.currentTime) } ?? "")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .opacity(dragTime == nil ? 0 : 1)
                        .alignmentGuide(.leading) { size in -min(max(handleX - size.width / 2, 0), max(width - size.width, 0)) }
                        .alignmentGuide(.top) { size in size.height + 6 }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        dragTime = min(max(value.location.x / max(width, 1), 0), 1) * duration
                    }
                    .onEnded { value in
                        guard duration > 0 else { dragTime = nil; return }
                        player.scrub(to: min(max(value.location.x / max(width, 1), 0), 1) * duration)
                        dragTime = nil
                    })
            }
            // Görsel kalınlık 6 pt kalır; dokunma alanı çubuğun üstüne ve altına taşar.
            .frame(height: 36)
            if buckets.contains(where: { $0 > 0 }) {
                HeatStrip(buckets: buckets)
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: rewindTimes, initial: true) { _, _ in recompute() }
        .onChange(of: player.duration) { _, _ in recompute() }
        #if DEBUG
        // Simülatörde sürükleme kabarcığını göstermek için: -scrubDemo=0…1 (çubuk üzerindeki oran; ilk dokunuşta kalkar).
        .task(id: player.duration) {
            guard dragTime == nil, player.duration > 0, let part = DebugArg.value("scrubDemo").flatMap({ Double($0) }) else { return }
            dragTime = min(max(part, 0), 1) * player.duration
        }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Konum")
        .accessibilityValue("\(TranscriptFormat.timestamp(shown)) / \(TranscriptFormat.timestamp(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(10)
            case .decrement: player.skip(-10)
            @unknown default: break
            }
        }
    }

    private func recompute() {
        buckets = RewindHeat.buckets(times: rewindTimes, duration: player.duration, count: Self.bucketCount)
    }
}

/// Geri sarma yoğunluğu: kova başına bir hücre, yoğunluk turuncunun koyuluğu.
private struct HeatStrip: View {
    var buckets: [Double]

    var body: some View {
        Canvas { context, size in
            guard !buckets.isEmpty else { return }
            let cell = size.width / CGFloat(buckets.count)
            for (i, level) in buckets.enumerated() where level > 0 {
                let rect = CGRect(x: CGFloat(i) * cell, y: 0, width: cell + 0.5, height: size.height)
                context.fill(Path(rect), with: .color(.orange.opacity(0.25 + 0.75 * level)))
            }
        }
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .clipShape(Capsule())
    }
}
