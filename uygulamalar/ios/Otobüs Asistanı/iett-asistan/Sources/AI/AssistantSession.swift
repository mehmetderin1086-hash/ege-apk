import Foundation
import Observation

struct AssistantReply {
    var text: String
    var actions: [AssistantAction]
    var followUps: [Suggestion]
}

/// Yazılı ve sesli asistanın ortak oturumu: aynı sohbet belleği (son hat/durak), aynı cevap hattı (Apple Intelligence → yerel kurallar).
@MainActor @Observable final class AssistantSession {
    let model: AppModel
    private(set) var lastLine: String?
    private(set) var lastStop: String?
    @ObservationIgnored private var ai: AnyObject?
    init(model: AppModel) { self.model = model }

    func reset() { lastLine = nil; lastStop = nil }

    func reply(to question: String) async -> AssistantReply {
        if let rail = await railReply(question) { return rail }
        let brain = TransitBrain(model: model), local = LocalAssistant(brain: brain)
        let intent = LocalAssistant.parse(question, lines: model.lines, context: lastLine)
        var generated: String?
        if #available(iOS 26.0, *), AIAssistant.isAvailable {
            if ai == nil { ai = AIAssistant(brain: brain) }
            generated = try? await (ai as? AIAssistant)?.respond(question)
        }
        let answer: String
        if let generated { answer = generated } else { answer = await local.answer(question, context: lastLine) }
        switch intent { case .status(let c), .schedule(let c), .eta(let c, _), .notices(let c?): lastLine = c; default: break }
        switch intent {
        case .eta(_, let query), .stopLines(let query): lastStop = model.searchStops(query, near: model.location?.coordinate, limit: 1).first?.name
        default: break
        }
        let followUps = SuggestionBuilder.followUps(line: lastLine, stopName: lastStop).filter { $0.text != question }
        return AssistantReply(text: answer, actions: local.actions(for: intent), followUps: followUps)
    }

    /// Aynı yol hem yazılı hem sesli oturumda kullanılır; canlı konum veya sefer saati uydurulmaz.
    private func railReply(_ question: String) async -> AssistantReply? {
        let text = fold(question)
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let line = words.first { word in
            let prefixes = ["m", "t", "f", "tf"]
            return prefixes.contains { prefix in word.hasPrefix(prefix) && word.dropFirst(prefix.count).contains(where: \.isNumber) && word.dropFirst(prefix.count).allSatisfy { $0.isNumber || $0 == "a" || $0 == "b" } }
        }?.uppercased()
        guard line != nil || ["metro", "tramvay", "funikuler", "teleferik", "rayli sistem"].contains(where: text.contains) else { return nil }
        let action = AssistantAction.open(.railStations, "İstasyonları aç", "tram.fill")
        if ["kac dakika", "kac dk", "ne zaman gelecek", "sefer saat", "ilk sefer", "son sefer"].contains(where: text.contains) {
            return AssistantReply(text: "Raylı sistem için canlı varış ve güncel sefer saatini doğrulayamıyorum. İstasyonları açabilir veya toplu taşıma rotasını Harita'da arayabilirsin.", actions: [action], followUps: [])
        }
        if ["duyuru", "aksama", "ariza", "calisiyor", "kapali"].contains(where: text.contains) {
            do {
                let all = try await RailStationStore.shared.serviceStatuses()
                let matches = all.filter { line == nil || fold($0.LineName) == fold(line!) }
                let answer = matches.isEmpty ? "Metro İstanbul servisi\(line.map { " \($0) için" } ?? "") şu anda işletme duyurusu bildirmiyor." : matches.prefix(5).map { "\($0.LineName): \($0.Description)" }.joined(separator: "\n")
                return AssistantReply(text: answer + "\nKaynak: Metro İstanbul; duyuruların güncelleme zamanını istasyon ekranında görebilirsin.", actions: [action], followUps: [])
            } catch {
                return AssistantReply(text: "Metro İstanbul işletme duyurularına şu anda ulaşılamıyor.", actions: [action], followUps: [])
            }
        }
        let snapshot: RailStationStore.Snapshot
        if let cached = await RailStationStore.shared.cached() { snapshot = cached }
        else if let fetched = try? await RailStationStore.shared.refresh() { snapshot = fetched }
        else { return AssistantReply(text: "İstasyon verisi alınamadı; internet bağlantını kontrol edip tekrar dene.", actions: [action], followUps: []) }
        var stations = snapshot.stations.filter { station in
            if let line { return fold(station.LineName) == fold(line) }
            return fold(station.Description).count > 2 && text.contains(fold(station.Description))
        }
        if line == nil && stations.isEmpty && text.contains("yakin"), let here = model.location?.coordinate {
            stations = snapshot.stations.filter { $0.coordinate != nil }.sorted { here.distance(to: $0.coordinate!) < here.distance(to: $1.coordinate!) }
        }
        let answer: String
        if stations.isEmpty { answer = "Eşleşen istasyon bulunamadı. İstasyon adı veya hat kodunu söyleyebilirsin." }
        else if let line { answer = "\(line): Metro İstanbul verisinde \(stations.count) istasyon kaydı var. " + stations.prefix(8).map(\.Description).joined(separator: ", ") + (stations.count > 8 ? " ve diğerleri." : ".") }
        else { answer = stations.prefix(5).map { "\($0.Description) · \($0.LineName)" }.joined(separator: "\n") }
        return AssistantReply(text: answer + "\nİstasyon verisi: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)); canlı araç konumu değildir.", actions: [action], followUps: [])
    }
}
