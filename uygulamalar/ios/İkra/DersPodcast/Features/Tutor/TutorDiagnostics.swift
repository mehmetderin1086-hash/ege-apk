#if DEBUG
import Foundation

/// Yalnız açık test argümanıyla çalışır; gerçek hesap yolu üzerinden uçtan uca sınama.
enum TutorDiagnostics {
    static func run() async {
        var checks: [[String: Any]] = []
        for (mode, prompt) in [
            (TutorMode.solve, "2x + 3 = 11 denklemini kısa adımlarla çöz."),
            (.socratic, "2x + 3 = 11. İlk adımda ne yapmalıyım? Son cevabı henüz söyleme."),
            (.writtenExam, #"Tam 3 kısa açık uçlu toplama sorusu üret. Yalnız {"questions":["...","...","..."]} JSON'u döndür."#),
            (.cardDeck, #"Toplama hakkında tam 5 kart üret. Yalnız {"cards":[{"front":"soru","back":"cevap"}]} JSON'u döndür."#)
        ] {
            let start = Date()
            do {
                let result = try await TutorEngine.reply(mode: mode, subject: "Matematik", level: "Ortaokul",
                                                        messages: [.init(role: "user", text: prompt)])
                if mode == .writtenExam { _ = try TutorWrittenLogic.questions(from: result, count: 3) }
                if mode == .cardDeck { _ = try TutorCardParser.parse(result, expectedCount: 5) }
                checks.append(["mode": mode.rawValue, "ok": true, "seconds": Date().timeIntervalSince(start), "response": result])
            } catch {
                checks.append(["mode": mode.rawValue, "ok": false, "seconds": Date().timeIntervalSince(start), "error": error.localizedDescription])
            }
            if let data = try? JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL.documentsDirectory.appending(path: "tutor-diagnostics.json"), options: .atomic)
            }
        }
    }
}
#endif
