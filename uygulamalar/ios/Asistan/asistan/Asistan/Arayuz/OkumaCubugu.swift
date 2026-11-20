import SwiftUI

/// P3.12: asistan sesli okurken giriş çubuğunun üstünde tek satırlık kontrol: duraklat/devam, hız (1×/1,25×/1,5×),
/// durdur ve okunan parçanın metni. Live tam ekranı etkilenmez (yalnız SohbetEkrani gösterir).
struct OkumaCubugu: View {
    @Environment(SesOturumu.self) private var ses

    /// UI sınaması: ses çalmayan simülatörde çubuk `--okuma-cubugu-sinama` ile görünür (yalnız Debug).
    static var sinamada: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--okuma-cubugu-sinama")
        #else
        return false
        #endif
    }

    static let hizlar: [Float] = [1.0, 1.25, 1.5]

    /// 1 → "1×", 1.25 → "1,25×", 1.5 → "1,5×".
    nonisolated static func hizEtiketi(_ h: Float) -> String {
        var s = String(format: "%.2f", Double(h))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",") + "×"
    }

    var body: some View {
        let m = ses.konusmaci
        HStack(spacing: 12) {
            Button {
                m.duraklatDevam()
            } label: {
                Image(systemName: m.duraklatildi ? "play.fill" : "pause.fill")
                    .frame(width: 28, height: 28)
            }
            .accessibilityIdentifier("okuma-duraklat")
            .accessibilityLabel(m.duraklatildi ? "Okumayı sürdür" : "Okumayı duraklat")

            Text(m.simdiCalan ?? "Okunuyor…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(Self.hizlar, id: \.self) { h in
                    Button { m.hiziDegistir(h) } label: {
                        if abs(m.hiz - h) < 0.01 { Label(Self.hizEtiketi(h), systemImage: "checkmark") } else { Text(Self.hizEtiketi(h)) }
                    }
                }
            } label: {
                Text(Self.hizEtiketi(m.hiz))
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 40, minHeight: 28)
            }
            .accessibilityIdentifier("okuma-hiz")
            .accessibilityLabel("Okuma hızı \(Self.hizEtiketi(m.hiz))")

            Button {
                m.sustur()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 28, height: 28)
            }
            .accessibilityIdentifier("okuma-durdur")
            .accessibilityLabel("Okumayı durdur")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("okuma-cubugu")
    }
}
