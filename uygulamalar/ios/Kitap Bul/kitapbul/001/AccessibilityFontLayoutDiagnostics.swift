import SwiftUI

// Diagnostic source only. This is not an accessibility fix or a release feature.
// Public geometry observation does not replace Text, hide elements, override fonts,
// resize a view, change safe areas, or change an accessibility audit result.
#if DEBUG
nonisolated private struct FontLayoutSample: Equatable, Sendable {
    let category: String
    let scheme: String
    let frame: CGRect
}

@MainActor
private enum FontLayoutDiagnosticLog {
    private static var last: [String: FontLayoutSample] = [:]
    private static var counts: [String: Int] = [:]

    static func record(id: String, sample: FontLayoutSample) {
        guard last[id] != sample, counts[id, default: 0] < 150 else { return }
        last[id] = sample
        counts[id, default: 0] += 1
        let object: [String: Any] = [
            "id": id, "category": sample.category, "scheme": sample.scheme,
            "frame": [sample.frame.minX, sample.frame.minY, sample.frame.width, sample.frame.height]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else { return }
        print("FONTLAYOUT|" + encoded)
    }
}

private struct AccessibilityFontLayoutDiagnostic: ViewModifier {
    let id: String?
    @Environment(\.dynamicTypeSize) private var category
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let categoryDescription = String(describing: category)
        let schemeDescription = scheme == .dark ? "dark" : "light"
        if let id, ProcessInfo.processInfo.arguments.contains("-a11y-font-diagnostics") {
            content.onGeometryChange(for: FontLayoutSample.self) { geometry in
                FontLayoutSample(category: categoryDescription,
                    scheme: schemeDescription, frame: geometry.frame(in: .global))
            } action: { sample in
                FontLayoutDiagnosticLog.record(id: id, sample: sample)
            }
        } else {
            content
        }
    }
}
#endif

extension View {
    func accessibilityFontLayoutDiagnostic(_ id: String?) -> some View {
#if DEBUG
        modifier(AccessibilityFontLayoutDiagnostic(id: id))
#else
        self
#endif
    }
}
