import SwiftUI

/// Small hearts fly outward when a track is liked. Plays once per trigger change.
struct HeartBurst: View {
    let trigger: Int
    var color: Color = RitimTheme.mint
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Image(systemName: i.isMultiple(of: 2) ? "heart.fill" : "sparkle")
                    .font(.system(size: i.isMultiple(of: 2) ? 9 : 8))
                    .foregroundStyle(color)
                    .offset(x: cos(angle) * 30 * progress, y: sin(angle) * 30 * progress)
                    .scaleEffect(1 - progress * 0.5)
                    .opacity(Double(1 - progress))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            progress = 0
            withAnimation(.easeOut(duration: 0.65)) { progress = 1 }
        }
    }
}

/// Cards ease in as they scroll into view and settle back as they leave.
struct ScrollFlow: ViewModifier {
    var horizontal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.scrollTransition(axis: horizontal ? .horizontal : .vertical) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .blur(radius: phase.isIdentity ? 0 : 1.5)
            }
        }
    }
}

extension View {
    func scrollFlow(horizontal: Bool = false) -> some View { modifier(ScrollFlow(horizontal: horizontal)) }
}
