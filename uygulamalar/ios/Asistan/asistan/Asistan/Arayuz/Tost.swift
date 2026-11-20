import SwiftUI
import Observation

/// Kısa bildirim (tost): "Kopyalandı", "Beceri kaydedildi" gibi geçici, işlem onayı niteliğinde satırlar.
nonisolated struct TostMesaji: Identifiable, Equatable, Sendable {
    let id = UUID()
    let metin: String
    let simge: String
}

/// Ekranda tek tost görünür; yenisi eskisinin yerini alır. Süre metin uzunluğuyla büyür (2–6 sn).
/// VoiceOver açıkken metin duyurulur (görsel tost ekran okuyucuya ulaşmaz).
@MainActor @Observable
final class TostDefteri {
    static let ortak = TostDefteri()

    private(set) var gorunen: TostMesaji?
    /// Her gösterim artırır: eski tostun gecikmeli kapanışı yenisini silmesin.
    @ObservationIgnored private var nesil = 0
    @ObservationIgnored private var bekleme: Task<Void, Never>?

    init() {}

    func goster(_ metin: String, simge: String = "checkmark.circle") {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        nesil += 1
        let bu = nesil
        gorunen = TostMesaji(metin: t, simge: simge)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: t)
        }
        bekleme?.cancel()
        bekleme = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sure(t)))
            guard let self, !Task.isCancelled, self.nesil == bu else { return }
            self.gorunen = nil
        }
    }

    func kapat() {
        nesil += 1
        bekleme?.cancel()
        bekleme = nil
        gorunen = nil
    }

    /// Görünme süresi (sn): kısa metinde 2, her 40 karakterde +1, en çok 6.
    nonisolated static func sure(_ metin: String) -> Double {
        min(6, 2 + Double(metin.count) / 40)
    }
}

/// Ekranın altında beliren tost katmanı; dokununca kapanır. Hareketi Azalt açıkken yalnız saydamlık geçişi.
struct TostKatmani: View {
    @Environment(\.accessibilityReduceMotion) private var azHareket
    @Environment(\.colorScheme) private var sema
    private var defter: TostDefteri { TostDefteri.ortak }

    var body: some View {
        ZStack {
            if let t = defter.gorunen {
                Label(t.metin, systemImage: t.simge)
                    .font(.footnote.weight(.medium)).fontDesign(.default)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .foregroundStyle(SohbetRenk.metin(sema == .dark))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .temaDugmesi(Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .contentShape(Capsule())
                    .onTapGesture { defter.kapat() }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Kapatmak için dokun")
                    .accessibilityAction { defter.kapat() }
                    .accessibilityIdentifier("tost")
                    .id(t.id)
                    .transition(azHareket ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(azHareket ? .easeInOut(duration: 0.15) : .spring(duration: 0.3), value: defter.gorunen?.id)
    }
}
