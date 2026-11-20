import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Asistana eklenen dosya (18 Eki 2026): telefona kopyalanmış hâli ve modele bildirilen türü.
nonisolated struct AssistantAttachment: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case image, pdf, document }
    let id = UUID()
    var url: URL
    var name: String
    var kind: Kind

    /// Dosya adından tür: resim uzantıları → image, pdf → pdf, kalanı (txt, docx…) → document.
    static func kind(of name: String) -> Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif": .image
        case "pdf": .pdf
        default: .document
        }
    }
    /// Asistan ekleri bu klasörde tutulur (Application Support/AssistantFiles); modül kendi kopyasını alır.
    static var directory: URL { URL.applicationSupportDirectory.appending(path: "AssistantFiles", directoryHint: .isDirectory) }
    /// Seçicinin verdiği dosyayı (güvenlik kapsamlı olabilir) klasöre kopyalar.
    static func store(_ source: URL) throws -> AssistantAttachment {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let name = source.lastPathComponent
        let target = directory.appending(path: UUID().uuidString + "-" + name)
        try FileManager.default.copyItem(at: source, to: target)
        return AssistantAttachment(url: target, name: name, kind: kind(of: name))
    }
    /// Fotoğraf verisini JPEG olarak klasöre yazar.
    static func store(imageData: Data, name: String) throws -> AssistantAttachment {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: UUID().uuidString + "-" + name)
        try imageData.write(to: target)
        return AssistantAttachment(url: target, name: name, kind: .image)
    }
    /// Bir günden eski ekler silinir (modüller kendi kopyasını almıştır).
    static func sweep(now: Date = .now) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items {
            let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(date) > 86_400 { try? FileManager.default.removeItem(at: item) }
        }
    }
    var request: AssistantRequest.Attachment { .init(name: name, kind: kind.rawValue) }
}

/// Asistanın seçtiği eylemi uygulamaya uygular (kapalı liste; bilinmeyen eylem yok sayılır). Ekler ilgili modüle
/// `AppState.assistantHandoff` ile verilir; podcast ekleri var olan "Ders Podcast'te Aç" yolunu (`incomingFiles`) kullanır.
@MainActor
enum AssistantActions {
    static let settingsPages: [String: SettingsPage] = ["appearance": .appearance, "audio": .audio, "connection": .connection, "models": .models, "storage": .storage]

    /// Döndürdüğü değer: eylem ekleri tüketti mi (asistan ek listesini boşaltır).
    @discardableResult
    static func perform(_ action: AssistantResponse.Action, attachments: [AssistantAttachment], app: AppState, defaults: UserDefaults = .standard) -> Bool {
        let target = action.target ?? ""
        let files = attachments.map(\.url)
        switch action.type {
        case "open":
            if let tab = AppState.MainTab(rawValue: target) { app.selectedTab = tab }
        case "route":
            app.pendingRoute = target
        case "settings":
            if let page = settingsPages[target] { app.settingsRoute = page }
        case "textSize":
            if let level = Int(target), (0...2).contains(level) { defaults.set(level, forKey: VisionPrefs.textSizeKey) }
        case "import":
            guard !files.isEmpty else { return false }
            switch target {
            case "podcast":
                app.incomingFiles = files
                app.selectedTab = .library
            case "questions":
                app.assistantHandoff = AssistantHandoff(module: .questions, files: files, text: action.text ?? "")
                app.selectedTab = .questions
            case "visuals":
                app.assistantHandoff = AssistantHandoff(module: .visuals, files: files, text: action.text ?? "")
                app.selectedTab = .visuals
            case "topics":
                app.assistantHandoff = AssistantHandoff(module: .topics, files: files, text: action.text ?? "")
                app.selectedTab = .topics
            default: return false
            }
            return true
        case "topicVideo":
            guard !target.isEmpty else { return false }
            app.assistantHandoff = AssistantHandoff(module: .topics, files: files, text: target)
            app.selectedTab = .topics
            return !files.isEmpty
        case "play":
            guard !target.isEmpty else { return false }
            app.pendingRoute = "play:" + target
        case "scan":
            app.assistantHandoff = AssistantHandoff(module: .questions, text: "scan")
            app.selectedTab = .questions
        default: break
        }
        return false
    }

    /// "play:<ad>" rotası: adı en iyi uyan hazır bölüm (Türkçe harf katlamalı, parça eşleşmesi).
    nonisolated static func match(_ query: String, titles: [String]) -> Int? {
        let folded = TurkishFold.fold(query.trimmingCharacters(in: .whitespaces))
        guard !folded.isEmpty else { return nil }
        let words = folded.split(separator: " ").map(String.init)
        var best: (index: Int, score: Int)?
        for (index, title) in titles.enumerated() {
            let t = TurkishFold.fold(title)
            let score = t.contains(folded) ? 1000 : words.filter { t.contains($0) }.count
            if score > 0, score > (best?.score ?? 0) { best = (index, score) }
        }
        return best?.index
    }
}
