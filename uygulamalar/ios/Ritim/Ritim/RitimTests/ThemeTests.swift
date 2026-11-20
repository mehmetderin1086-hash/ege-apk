import XCTest
import SwiftUI
@testable import Ritim

@MainActor
final class ThemeTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ThemeStore.key)
        RitimTheme.style = ThemeStyle.all[0]
        super.tearDown()
    }

    func testSelectingAThemePersistsAndSwitchesEveryColourSource() {
        let store = ThemeStore()
        XCTAssertEqual(store.selectedID, "nane")
        store.lastTab = "İndir"
        store.select("rengarenk", reopenSettings: true)
        XCTAssertEqual(store.selectedID, "rengarenk")
        XCTAssertEqual(store.version, 1, "Kök görünüm yeniden kurulmalı")
        XCTAssertEqual(store.resume?.tab, "İndir")
        XCTAssertEqual(store.resume?.settings, true)
        XCTAssertEqual(RitimTheme.style.id, "rengarenk")
        XCTAssertEqual(RitimTheme.palettes.count, 6)
        XCTAssertEqual(UserDefaults.standard.string(forKey: ThemeStore.key), "rengarenk")
        XCTAssertEqual(ThemeStore().selectedID, "rengarenk", "Yeniden açılışta tema korunmalı")

        store.select("rengarenk", reopenSettings: true)
        XCTAssertEqual(store.version, 1, "Aynı tema seçilince yeniden kurulmamalı")
        UserDefaults.standard.set("silinmis-tema", forKey: ThemeStore.key)
        XCTAssertEqual(ThemeStore().selectedID, "nane", "Bilinmeyen tema varsayılana düşmeli")
    }

    func testEveryThemeHasDistinctAccentAndUsablePalettes() {
        XCTAssertEqual(Set(ThemeStyle.all.map(\.id)).count, ThemeStyle.all.count)
        XCTAssertGreaterThanOrEqual(ThemeStyle.all.count, 6)
        for style in ThemeStyle.all {
            XCTAssertGreaterThanOrEqual(style.palettes.count, 5, style.name)
            XCTAssertTrue(style.palettes.allSatisfy { $0.count >= 2 }, style.name)
        }
    }
}
