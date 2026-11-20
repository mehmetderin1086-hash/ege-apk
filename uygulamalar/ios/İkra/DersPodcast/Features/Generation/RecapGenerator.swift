import SwiftData
import SwiftUI

/// Sınav öncesi 5 dakikalık "hızlı tekrar" sesi: bölüm özeti + kaynak notları + en çok zorlanılan kartlar
/// tek anlatıcılı kısa bir bölüm olarak mevcut üretim hattıyla üretilir.
enum RecapGenerator {
    /// Kaynak metni: özet, en zor kartlar (Bilemedim sayısına göre), açık yanlışlar, kaynak notlarının başı.
    static func sourceText(for episode: Episode, cards: [ReviewCard], mistakes: [MistakeEntry]) -> String {
        var parts: [String] = []
        if let script = episode.script {
            parts.append("KONU: \(script.title)\nÖZET: \(script.summary)")
        }
        let hard = cards.filter { $0.episodeID == episode.id }
            .sorted { ($0.lapses, -$0.ease) > ($1.lapses, -$1.ease) }.prefix(5)
        if !hard.isEmpty {
            parts.append("ÖĞRENCİNİN ZORLANDIĞI NOKTALAR (bunları özellikle netleştir):\n" + hard.map { "- \($0.front) → \($0.back)" }.joined(separator: "\n"))
        }
        let wrong = mistakes.filter { $0.episodeID == episode.id && !$0.resolved }.prefix(5)
        if !wrong.isEmpty {
            parts.append("YAPILAN YANLIŞLAR:\n" + wrong.map { "- \($0.question) Doğrusu: \($0.correctAnswer)" }.joined(separator: "\n"))
        }
        if let notes = episode.script?.sourceNotes { parts.append("KAYNAK NOTLARI:\n" + String(notes.prefix(8000))) }
        return parts.joined(separator: "\n\n")
    }

    static func settings(from base: PodcastSettings?) -> PodcastSettings {
        settings(from: base, kind: "recap", parent: nil)
    }

    /// #31 önce yoklayan tekrar: `.reusable` önce (ana bölümün serisi/türevi taşınmaz), sonra "soru → sessizlik → cevap" yapısı.
    /// `kind`: "recap" | "gap" | "weekly".
    static func settings(from base: PodcastSettings?, kind: String, parent: UUID?) -> PodcastSettings {
        var s = (base ?? PodcastSettings()).reusable
        s.durationMin = 5
        s.format = .tekAnlatici
        s.depth = .ozet
        s.focus = "Sınav öncesi hızlı tekrar"
        s.customInstructions = "Bu bir sınav öncesi hızlı tekrar. Yeni bilgi ekleme; en önemli kavramları, öğrencinin zorlandığı noktaları ve yaptığı yanlışların doğrularını kısa, akılda kalıcı cümlelerle tekrar et. Sonda 3 soruluk hızlı kendini yokla bölümü olsun."
        s.recallFirst = true
        s.thinkPauses = true
        s.directives = [recallFirstDirective]
        s.derivation = Derivation(kind: kind, parentEpisodeID: parent)
        return s
    }

    /// Sunucuya giden yönerge (≤800 karakter).
    static let recallFirstDirective = "Önce yoklayan tekrar: her ana noktayı özetlemeden önce dinleyiciye soru olarak sor, cevabı düşünmesi için düşünme payı bırak, sonra cevabı ver ve bir cümleyle neden doğru olduğunu açıkla. Pasif özet yapma; her bölüm soru → sessizlik → cevap düzeninde ilerlesin."

    @MainActor
    static func start(for episode: Episode, generator: GenerationCoordinator, context: ModelContext) async throws -> Episode {
        let cards = (try? context.fetch(FetchDescriptor<ReviewCard>())) ?? []
        let mistakes = (try? context.fetch(FetchDescriptor<MistakeEntry>())) ?? []
        let source = ImportedSource(name: "Hızlı tekrar · \(episode.title)", kind: .text(sourceText(for: episode, cards: cards, mistakes: mistakes)))
        return try await generator.start(sources: [source], settings: settings(from: episode.settings, kind: "recap", parent: episode.id), context: context)
    }
}
