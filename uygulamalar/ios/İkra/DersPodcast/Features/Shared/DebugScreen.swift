import SwiftUI

extension View {
    /// Yalnızca Debug: `-narrow320` ile Ekran Büyütme'deki iPhone genişliği (320 nokta) taklit edilir;
    /// `-bigText` ile büyük dinamik yazı. Dar ekranda taşma denetimi için.
    @ViewBuilder
    func debugNarrowScreen() -> some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-narrow320") {
            self.frame(width: 320).frame(maxWidth: .infinity).background(Color.black)
                .dynamicTypeSize(args.contains("-bigText") ? .xxxLarge : .large)
                .environment(\.legibilityWeight, args.contains("-boldText") ? .bold : .regular)
        } else if args.contains("-boldText") {
            self.environment(\.legibilityWeight, .bold)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
