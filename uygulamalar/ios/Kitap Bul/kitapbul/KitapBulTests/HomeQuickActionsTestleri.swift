import Testing
@testable import _01

struct HomeQuickActionsTestleri {
    @Test func bozukTercihTekrarlariVeSabitGorevler() {
        #expect(HomeQuickActionPreferences.load("bozuk JSON") == .defaults)
        #expect(HomeQuickActionPreferences.load("[\"management\",\"barcode\",\"management\",\"eski\",\"barcode\"]").actions == [.management, .barcode])
        #expect(HomeQuickActionPreferences.load("[]").actions.isEmpty)
        #expect(HomeQuickActionPreferences.load("[\"bilinmeyen\"]") == .defaults)
        var selected = HomeQuickActionPreferences(actions: [.management, .barcode])
        selected.move(.barcode, by: -1)
        #expect(selected.actions == [.barcode, .management])
        selected.remove(.barcode)
        selected.add(.management)
        #expect(selected.actions == [.management])
        #expect(HomeQuickActionPreferences.load(selected.encoded) == selected)
        #expect(HomeQuickActionPreferences.primaryTasks == [.lend, .returnLoan, .addBook])
        let full = HomeQuickActionPreferences(actions: [.management, .voice, .barcode, .cover, .assistant])
        #expect(full.visibleActions(simpleMode: true) == [.management, .voice, .barcode])
        #expect(full.visibleActions(simpleMode: false) == [.management, .voice, .barcode, .cover, .assistant])
        #expect(HomeQuickActionPreferences.load(full.encoded) == full)
    }
}
