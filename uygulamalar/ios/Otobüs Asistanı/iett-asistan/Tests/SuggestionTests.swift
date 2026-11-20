import Foundation
import Testing
@testable import IETTAsistan

@MainActor struct SuggestionTests {
    private let fav = Favorite(line: "500T", stopCode: 1, stopName: "4.LEVENT METRO", lat: 41, lon: 29)
    private let lines = [Hat(code: "500T", name: "TUZLA"), Hat(code: "14M", name: "X"), Hat(code: "15F", name: "Y")]

    @Test func personalSuggestionsComeFromFavoritesStopsAndLines() {
        let list = SuggestionBuilder.make(favorites: [fav], favoriteStops: [(7, "KADIKÖY ÇARŞI")], pinned: ["14M"], recent: ["500T", "15F"], hasLocation: true)
        let texts = list.map(\.text)
        #expect(texts.contains("4.LEVENT METRO durağına 500T kaç dk?") && texts.contains("KADIKÖY ÇARŞI durağından hangi hatlar geçer?"))
        #expect(texts.contains("14M sefer saatleri") && texts.contains("15F duyuru var mı?") && texts.contains("Yakınımdaki duraklar"))
        #expect(list.first?.group == SuggestionBuilder.groupStops)
        #expect(Set(texts).count == texts.count && list.count <= 18)
        // Takip ettiğin hattın durağı yıldızlı değilse o durağın "hangi hatlar" sorusu da çıkar.
        #expect(texts.contains("4.LEVENT METRO durağından hangi hatlar geçer?"))
    }
    @Test func genericExamplesAppearOnlyWithoutPersonalData() {
        let none = SuggestionBuilder.make(favorites: [], favoriteStops: [], pinned: [], recent: [], hasLocation: false)
        #expect(none.map(\.text).contains("500T nerede?") && none.allSatisfy { $0.group == SuggestionBuilder.groupGeneral })
        let some = SuggestionBuilder.make(favorites: [fav], favoriteStops: [], pinned: [], recent: [], hasLocation: false)
        #expect(!some.map(\.text).contains("14M duyuru var mı?") && !some.contains { $0.text == "Yakınımdaki duraklar" })
        #expect(SuggestionBuilder.make(favorites: [], favoriteStops: (0..<20).map { ($0, "D\($0)") }, pinned: [], recent: [], hasLocation: true).count <= 18)
    }
    @Test func everyGeneratedQuestionIsUnderstoodByTheLocalAssistant() {
        let list = SuggestionBuilder.make(favorites: [fav], favoriteStops: [(7, "KADIKÖY ÇARŞI")], pinned: ["14M"], recent: ["15F"], hasLocation: true)
        for s in list {
            let intent = LocalAssistant.parse(s.text, lines: lines)
            #expect(intent != .help && intent != .search(s.text), "\(s.text) → \(intent)")
        }
        #expect(LocalAssistant.parse("4.LEVENT METRO durağına 500T kaç dk?", lines: lines) == .eta("500T", "4 levent metro"))
        #expect(LocalAssistant.parse("KADIKÖY ÇARŞI durağından hangi hatlar geçer?", lines: lines) == .stopLines("kadikoy carsi"))
    }
    @Test func followUpsDependOnLineAndStop() {
        #expect(SuggestionBuilder.followUps(line: nil, stopName: nil).isEmpty)
        let t = SuggestionBuilder.followUps(line: "500T", stopName: "4.LEVENT METRO").map(\.text)
        #expect(t.contains("500T sefer saatleri") && t.contains("4.LEVENT METRO durağına 500T kaç dk?") && t.contains("4.LEVENT METRO durağından hangi hatlar geçer?"))
    }
    @Test func favoriteStopsPersistAndToggle() {
        let defaults = UserDefaults(suiteName: "fs-\(UUID().uuidString)")!
        SharedStore.saveFavoriteStops([3, 9], to: defaults)
        #expect(SharedStore.loadFavoriteStops(from: defaults) == [3, 9])
        #expect(SharedStore.loadFavoriteStops(from: UserDefaults(suiteName: "fs-\(UUID().uuidString)")!).isEmpty)
        let model = AppModel(); let code = 987_654_321
        model.toggleFavoriteStop(code); #expect(model.isFavoriteStop(code))
        model.toggleFavoriteStop(code); #expect(!model.isFavoriteStop(code))
    }
}
