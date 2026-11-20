import Testing
@testable import Ikra

/// Modül kabı (17 Eki 2026): modül kimlikleri ve açılış ekranı.
@MainActor struct ModuleShellTests {
    @Test func everyModuleHasItsOwnTitleAndSymbol() {
        let modules = AppState.MainTab.modules
        #expect(modules.count == 7 && Set(modules).count == 7)
        #expect(!modules.contains(.home) && !modules.contains(.settings))
        #expect(Set(modules.map(\.title)).count == modules.count)
        #expect(Set(modules.map(\.symbol)).count == modules.count)
    }

    @Test func yellowModulesUseNavyTextAndBlueModulesUseWhite() {
        for tab in AppState.MainTab.allCases {
            #expect(tab.onColor == (tab.isLight ? Theme.navy : .white))
        }
        #expect(AppState.MainTab.questions.isLight && !AppState.MainTab.library.isLight)
    }

    @Test func appOpensOnTheHomeScreen() {
        #expect(AppState().selectedTab == .home)
    }

    @Test func textSizeLevelsOnlyRaiseTheMinimum() {
        #expect(VisionPrefs.range(0).lowerBound == .xSmall)
        #expect(VisionPrefs.range(1).lowerBound == .xLarge)
        #expect(VisionPrefs.range(2).lowerBound == .xxxLarge)
        #expect((0...2).allSatisfy { VisionPrefs.range($0).upperBound == .accessibility5 })
    }
}
