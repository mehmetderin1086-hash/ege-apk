import Foundation
import Testing
@testable import Ikra

/// Asistan eylemleri (18 Eki 2026): ekler modüle `assistantHandoff` ile gider, podcast ekleri `incomingFiles` yolundan; eksiz import yok sayılır.
@MainActor
struct AssistantActionsTests {
    private func file(_ name: String) -> AssistantAttachment { AssistantAttachment(url: URL(filePath: "/tmp/" + name), name: name, kind: AssistantAttachment.kind(of: name)) }

    @Test func attachmentsAreRoutedToModules() {
        let app = AppState()
        let photo = file("IMG_1.jpg"), pdf = file("deneme.pdf"), doc = file("not.docx")
        #expect(photo.kind == .image && pdf.kind == .pdf && doc.kind == .document && photo.request.kind == "image")
        #expect(AssistantActions.perform(.init(type: "import", target: "questions", text: nil), attachments: [photo, pdf], app: app))
        #expect(app.selectedTab == .questions && app.assistantHandoff?.module == .questions && app.assistantHandoff?.files.count == 2)
        #expect(AssistantActions.perform(.init(type: "import", target: "podcast", text: nil), attachments: [doc], app: app))
        #expect(app.selectedTab == .library && app.incomingFiles == [doc.url])
        #expect(AssistantActions.perform(.init(type: "import", target: "topics", text: "Fotosentez"), attachments: [pdf], app: app))
        #expect(app.assistantHandoff?.module == .topics && app.assistantHandoff?.text == "Fotosentez" && app.selectedTab == .topics)
        #expect(AssistantActions.perform(.init(type: "import", target: "visuals", text: nil), attachments: [photo], app: app) && app.selectedTab == .visuals)
        // Eksiz import ve bilinmeyen hedef hiçbir şey yapmaz.
        app.selectedTab = .home
        #expect(!AssistantActions.perform(.init(type: "import", target: "questions", text: nil), attachments: [], app: app) && app.selectedTab == .home)
        #expect(!AssistantActions.perform(.init(type: "import", target: "exams", text: nil), attachments: [photo], app: app) && app.selectedTab == .home)
    }

    @Test func plainActionsStillWork() {
        let app = AppState()
        AssistantActions.perform(.init(type: "topicVideo", target: "Mitoz", text: nil), attachments: [], app: app)
        #expect(app.selectedTab == .topics && app.assistantHandoff?.text == "Mitoz" && app.assistantHandoff?.files.isEmpty == true)
        AssistantActions.perform(.init(type: "play", target: "hücre", text: nil), attachments: [], app: app)
        #expect(app.pendingRoute == "play:hücre")
        AssistantActions.perform(.init(type: "scan", target: nil, text: nil), attachments: [], app: app)
        #expect(app.selectedTab == .questions && app.assistantHandoff?.text == "scan")
        AssistantActions.perform(.init(type: "open", target: "study", text: nil), attachments: [], app: app)
        #expect(app.selectedTab == .study)
        AssistantActions.perform(.init(type: "settings", target: "audio", text: nil), attachments: [], app: app)
        #expect(app.settingsRoute == .audio)
        AssistantActions.perform(.init(type: "bilinmeyen", target: "x", text: nil), attachments: [], app: app)
        #expect(app.selectedTab == .study)
    }

    @Test func playMatchesEpisodeTitlesWithTurkishFolding() {
        let titles = ["Hücre Zarı ve Taşıma", "Fotosentez", "DNA ve Genetik Kod"]
        #expect(AssistantActions.match("hücre", titles: titles) == 0)
        #expect(AssistantActions.match("HÜCRE ZARI", titles: titles) == 0)
        #expect(AssistantActions.match("genetik", titles: titles) == 2)
        #expect(AssistantActions.match("fotosentez bölümü", titles: titles) == 1)
        #expect(AssistantActions.match("mayoz", titles: titles) == nil && AssistantActions.match("  ", titles: titles) == nil)
    }
}
