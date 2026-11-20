import Foundation
import Testing
@testable import Ikra

// Podcast: tek dokunuşla başlatma — belgeye göre süre ve okul yazılısı yönergesi.

@Suite @MainActor struct PodcastAutoTests {
    @Test func durationGrowsWithTheDocument() {
        #expect(PodcastAuto.duration(characters: 0) == 5)
        #expect(PodcastAuto.duration(characters: 2_999) == 5 && PodcastAuto.duration(characters: 3_000) == 10)
        #expect(PodcastAuto.duration(characters: 17_999) == 15 && PodcastAuto.duration(characters: 29_999) == 20)
        #expect(PodcastAuto.duration(characters: 54_999) == 30 && PodcastAuto.duration(characters: 89_999) == 45)
        #expect(PodcastAuto.duration(characters: 500_000) == 60)
        // Seçilen her süre uygulamanın sunduğu sürelerden biridir.
        for size in stride(from: 0, through: 200_000, by: 1_500) { #expect(PodcastSettings.durations.contains(PodcastAuto.duration(characters: size))) }
    }

    @Test func sourceLengthIsEstimatedPerKind() {
        let note = ImportedSource(name: "Not", kind: .text(String(repeating: "a", count: 4_000)))
        var book = ImportedSource(name: "Kitap", kind: .pdf(URL(fileURLWithPath: "/tmp/yok.pdf"), pageCount: 40))
        let photo = ImportedSource(name: "Foto", kind: .image(Data()))
        #expect(PodcastAuto.characters([note]) == 4_000 && PodcastAuto.duration([note]) == 10)
        #expect(PodcastAuto.characters([book]) == 72_000 && PodcastAuto.duration([book]) == 45)
        // Yalnız seçilen sayfalar sayılır.
        book.pageRange = 5...9
        #expect(PodcastAuto.characters([book]) == 9_000 && PodcastAuto.duration([book]) == 15)
        #expect(PodcastAuto.characters([photo, photo]) == 2_400 && PodcastAuto.duration([photo, photo]) == 5)
        #expect(PodcastAuto.characters([]) == 0)
    }

    @Test func schoolDirectiveIsAddedOnceAndFitsTheServerLimit() {
        #expect(PodcastAuto.schoolDirective.count <= ServerSettings.maxDirectiveLength)
        let settings = PodcastSettings()
        let on = NewPodcastView.effective(settings, compare: false, sourceNames: ["Not"], narrateFigures: false, bilingual: false, schoolExam: true)
        #expect(on.directives == [PodcastAuto.schoolDirective])
        // Aynı ayar yeniden geçirilince yönerge çoğalmaz; kapalıyken eklenmez.
        let twice = NewPodcastView.effective(on, compare: false, sourceNames: ["Not"], narrateFigures: false, bilingual: false, schoolExam: true)
        #expect(twice.directives == [PodcastAuto.schoolDirective])
        let off = NewPodcastView.effective(settings, compare: false, sourceNames: ["Not"], narrateFigures: false, bilingual: false, schoolExam: false)
        #expect(off.directives.isEmpty)
        // Bütün uygulama yönergeleri birlikte sunucunun sayı sınırını aşmaz.
        let all = NewPodcastView.effective(settings, compare: true, sourceNames: ["A", "B"], narrateFigures: true, bilingual: true, schoolExam: true)
        #expect(all.directives.count <= ServerSettings.maxDirectives && all.directives.first == PodcastAuto.schoolDirective)
    }
}
