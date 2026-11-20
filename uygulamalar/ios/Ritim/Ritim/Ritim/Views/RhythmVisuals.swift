import SwiftUI
import AVFoundation

/// Loudness envelope of a file (≈20 values/s, 0…1), computed once off the main thread.
/// It lets the visuals follow the real rhythm without tapping the live audio graph.
actor RhythmAnalyzer {
    static let shared = RhythmAnalyzer()
    static let rate = 20.0
    private var cache: [URL: [Float]] = [:]

    func envelope(for url: URL) async -> [Float] {
        if let cached = cache[url] { return cached }
        let values = await Self.read(url)
        if cache.count > 8 { cache.removeAll() }
        cache[url] = values
        return values
    }

    private static func read(_ url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let sampleRate = 11_025.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        let window = Int(sampleRate / rate)
        let limit = Int(rate) * 60 * 30
        var values: [Float] = []
        var sum: Float = 0, count = 0
        while values.count < limit, !Task.isCancelled, let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            samples.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for sample in samples {
                let value = Float(sample) / 32768
                sum += value * value
                count += 1
                if count == window { values.append((sum / Float(window)).squareRoot()); sum = 0; count = 0 }
            }
        }
        guard values.count > 4 else { return [] }
        let reference = max(values.sorted()[Int(Double(values.count - 1) * 0.95)], 0.001)
        return values.map { min(1, ($0 / reference)).squareRoot() }
    }
}

/// Envelope level at a playback time, linearly interpolated.
func rhythmLevel(_ envelope: [Float], at seconds: Double) -> Double {
    guard !envelope.isEmpty, seconds >= 0 else { return 0 }
    let position = seconds * RhythmAnalyzer.rate
    let index = Int(position)
    guard index < envelope.count - 1 else { return Double(envelope.last ?? 0) }
    let fraction = Float(position - Double(index))
    return Double(envelope[index] * (1 - fraction) + envelope[index + 1] * fraction)
}

/// Deterministic generated artwork: soft colour blobs placed by a stable per-track seed.
struct GenerativeCoverBackdrop: View {
    let seed: UInt64
    let palette: [Color]
    var animated = false
    var level: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private func unit(_ salt: UInt64) -> Double {
        var x = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((x ^ (x >> 31)) % 10_000) / 10_000
    }

    var body: some View {
        let moves = animated && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !moves)) { timeline in
            let t = moves ? timeline.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: [palette[0], palette[1]], startPoint: .topLeading, endPoint: .bottomTrailing)
                    ForEach(0..<5, id: \.self) { i in
                        let s = UInt64(i + 1) * 17
                        let phase = unit(s + 3) * 6.28 + t * (0.15 + unit(s + 4) * 0.2)
                        let size = w * (0.45 + unit(s + 5) * 0.55) * (1 + level * 0.18)
                        Circle()
                            .fill(palette[(i + 1) % palette.count].opacity(0.35 + unit(s + 6) * 0.3))
                            .frame(width: size, height: size)
                            .blur(radius: w * 0.07)
                            .position(x: w * (0.15 + unit(s + 1) * 0.7) + cos(phase) * w * 0.06,
                                      y: h * (0.15 + unit(s + 2) * 0.7) + sin(phase) * h * 0.06)
                    }
                    // Concentric rings, one per beat-ish step; their count and spacing come from the seed.
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(.white.opacity(0.10 + level * 0.12), lineWidth: w * 0.012)
                            .frame(width: w * (0.35 + Double(i) * 0.25 + unit(UInt64(i) + 40) * 0.1))
                            .position(x: w * (0.3 + unit(41) * 0.4), y: h * (0.3 + unit(42) * 0.4))
                    }
                }.frame(width: w, height: h).clipped()
            }
        }
    }
}

/// Bars that scroll with the track's real loudness; the playhead is read straight from the player.
struct RhythmVisualizer: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var library: LibraryStore
    let track: MediaTrack
    var color: Color = RitimTheme.mint
    @State private var envelope: [Float] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let moves = playback.isPlaying && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moves)) { _ in
            Canvas { context, size in
                let now = playback.player.currentTime().seconds
                let bars = 40
                let gap = size.width / CGFloat(bars)
                for i in 0..<bars {
                    // Right edge is "now"; the left shows the last ~2 seconds.
                    let level = envelope.isEmpty ? 0.08 : rhythmLevel(envelope, at: now - Double(bars - 1 - i) * 0.05)
                    let height = max(3, size.height * CGFloat(0.12 + level * 0.88))
                    let rect = CGRect(x: CGFloat(i) * gap + gap * 0.2, y: (size.height - height) / 2, width: gap * 0.6, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: gap * 0.3),
                                 with: .color(color.opacity(0.35 + 0.65 * Double(i) / Double(bars))))
                }
            }
        }
        .frame(height: 36)
        .task(id: track.id) {
            envelope = []
            envelope = await RhythmAnalyzer.shared.envelope(for: library.url(for: track))
        }
        .accessibilityHidden(true)
    }
}

/// Current loudness (0…1) for pulsing the cover; zero when paused or motion is off.
struct RhythmPulse<Content: View>: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var library: LibraryStore
    let track: MediaTrack
    @ViewBuilder let content: (Double) -> Content
    @State private var envelope: [Float] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let moves = playback.isPlaying && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moves)) { _ in
            content(moves ? rhythmLevel(envelope, at: playback.player.currentTime().seconds) : 0)
        }
        .task(id: track.id) {
            envelope = []
            envelope = await RhythmAnalyzer.shared.envelope(for: library.url(for: track))
        }
    }
}
