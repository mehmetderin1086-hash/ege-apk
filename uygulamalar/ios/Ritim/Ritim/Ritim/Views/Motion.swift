import SwiftUI

/// Every continuous animation in Ritim goes through this gate: it runs only while the
/// scene is active, the view is on screen and Reduce Motion is off. Background audio
/// must never pay for UI frames (see the 1.7.1 CPU-limit crash).
struct MotionGate {
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    var allowed: Bool { !reduceMotion && scenePhase == .active }
}

/// Slowly drifting, blurred colour fields behind the player and hero cards.
struct AnimatedBackdrop: View {
    let colors: [Color]
    var active = true
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var animates: Bool { active && visible && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { timeline in
            let t = animates ? timeline.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { index, color in
                        let speed = 0.11 + Double(index) * 0.05
                        let x = sin(t * speed + Double(index) * 2.1) * size.width * 0.28
                        let y = cos(t * speed * 0.8 + Double(index) * 1.3) * size.height * 0.18
                        Circle().fill(color.opacity(0.55 * intensity))
                            .frame(width: size.width * (0.85 - Double(index) * 0.12))
                            .position(x: size.width * [0.25, 0.8, 0.5][index] + x, y: size.height * [0.15, 0.3, 0.6][index] + y)
                    }
                }.blur(radius: 60).drawingGroup()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

/// System-driven wave symbol: no per-frame SwiftUI redraw, so no list flicker.
struct LiveWaveSymbol: View {
    let isPlaying: Bool
    var color: Color = RitimTheme.mint
    var size: CGFloat = 15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Image(systemName: "waveform")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color.opacity(isPlaying ? 1 : 0.55))
            .font(.system(size: size, weight: .semibold))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing,
                          options: .repeating.speed(0.6),
                          isActive: isPlaying && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed)
            .accessibilityHidden(true)
    }
}

/// Three dots that rise in turn while the model is thinking.
struct TypingDots: View {
    var color: Color = RitimTheme.lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animates = MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = animates ? (sin(t * 6 - Double(index) * 0.9) + 1) / 2 : 0.5
                    Circle().fill(color).frame(width: 7, height: 7)
                        .offset(y: -4 * wave).opacity(0.45 + 0.55 * wave)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// A moving highlight for placeholders while AI content is loading.
struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let animates = active && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        content.overlay {
            if animates {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.13), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: -geometry.size.width * 0.6 + geometry.size.width * 1.6 * phase)
                    }
                }.allowsHitTesting(false).mask(content)
            }
        }
    }
}

/// A slowly turning gradient outline that marks AI-made content.
struct AIGlowBorder: ViewModifier {
    var radius: CGFloat
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let animates = active && MotionGate(reduceMotion: reduceMotion, scenePhase: scenePhase).allowed
        content.overlay {
            TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { timeline in
                let angle = animates ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360 : 30
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AngularGradient(colors: [RitimTheme.lavender.opacity(0.7), RitimTheme.mint.opacity(0.55),
                                                           .clear, RitimTheme.lavender.opacity(0.7)],
                                                  center: .center, angle: .degrees(angle)), lineWidth: 1.2)
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// Fades and lifts content in, one card after another.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85).delay(Double(min(index, 8)) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
    func aiGlow(radius: CGFloat, active: Bool = true) -> some View { modifier(AIGlowBorder(radius: radius, active: active)) }
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// Overlapping covers for an AI mix.
struct CoverStack: View {
    let tracks: [MediaTrack]
    var size: CGFloat = 54

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(tracks.prefix(3).enumerated().reversed()), id: \.element.id) { index, track in
                CoverArt(track: track, radius: size * 0.2)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 2, y: 3)
                    .rotationEffect(.degrees(Double(index) * 6))
                    .offset(x: CGFloat(index) * size * 0.34)
            }
        }
        .frame(width: size * (1 + 0.34 * CGFloat(max(0, min(tracks.count, 3) - 1))), height: size, alignment: .leading)
        .accessibilityHidden(true)
    }
}
