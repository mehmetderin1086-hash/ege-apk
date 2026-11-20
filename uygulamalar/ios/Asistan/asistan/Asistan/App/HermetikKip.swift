import SwiftUI
import UIKit

/// P3.10 hermetik UI testi bayrakları (`--sahte-model`, `--animasyonsuz`). Release derlemede hepsi kapalıdır;
/// SahteModelSunucusu'na yalnız `#if DEBUG` içinden başvurulur.
nonisolated enum HermetikKip {
    /// `--sahte-model`: istekler yerel sahte model sunucusuna gider (TelefonProxy, Gizli).
    static var sahteModel: Bool {
        #if DEBUG
        SahteModelSunucusu.etkin
        #else
        false
        #endif
    }

    /// `--animasyonsuz`: UIKit ve SwiftUI animasyonları kapanır (UI testleri sabit beklemesiz, hızlı ve kararlı).
    static let animasyonsuz: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--animasyonsuz")
        #else
        false
        #endif
    }()
}

extension HermetikKip {
    /// Uygulama açılışında bir kez (AsistanApp.init).
    @MainActor static func uygula() {
        if animasyonsuz { UIView.setAnimationsEnabled(false) }
    }
}

extension View {
    /// Kök görünüme: `--animasyonsuz` kipinde her işlemin animasyonu kapatılır; öbür durumlarda etkisizdir.
    func hermetikAnimasyon() -> some View {
        transaction { islem in
            if HermetikKip.animasyonsuz { islem.disablesAnimations = true; islem.animation = nil }
        }
    }
}
