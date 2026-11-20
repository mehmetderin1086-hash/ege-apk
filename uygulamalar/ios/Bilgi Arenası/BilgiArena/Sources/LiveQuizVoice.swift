import Foundation
import AVFoundation

struct QuizSpeechSegment: Equatable {
    let text: String
    var language = "tr-TR"
}
enum QuizNarration {
    static func question(_ q: Question, number: Int) -> [QuizSpeechSegment] {
        var result = [QuizSpeechSegment(text:"Soru \(number).")]
        if let a = q.activity, a.kind == .listening { result += split(a.transcript ?? "",language:a.language ?? "tr-TR") }
        result += split(q.text)
        if let visual = q.visual { result += split(visual.title+". "+visual.summary+". "+visual.accessibleData) }
        if let a = q.activity, a.kind == .pronunciation { result += split(a.transcript ?? "",language:a.language ?? "en-US") }
        else if let a = q.activity, a.kind == .ordering {
            result += split("Öğelerin numaralarını doğru sırayla söyle. "+(a.items ?? []).enumerated().map { "\($0.offset+1). \($0.element)." }.joined(separator:" "))
        } else if let a = q.activity, a.kind == .matching {
            result += split("Soldaki öğeler. "+(a.left ?? []).enumerated().map { "\($0.offset+1). \($0.element)." }.joined(separator:" "))
            result += split("Sağdaki karşılıklar. "+(a.right ?? []).enumerated().map { "\($0.offset+1). \($0.element)." }.joined(separator:" ")+". Soldaki sıraya göre dört sağ numara söyle.")
        } else { result += split(q.options.enumerated().map { "\(String(UnicodeScalar(65+$0.offset)!)) şıkkı. \($0.element)." }.joined(separator:" ")) }
        result.append(.init(text:"Şimdi seni dinliyorum.")); return coalesced(result)
    }
    static func feedback(_ q: Question, correct: Bool, last: Bool, explain: Bool = true) -> [QuizSpeechSegment] {
        var result: [QuizSpeechSegment] = []
        if let a = q.activity, a.kind == .pronunciation {
            result += split(correct ? "Söylediğin ifade hedefle eşleşti." : "Anlaşılan kelimeler hedefle eşleşmedi. Hedef ifade:")
            if !correct { result += split(a.transcript ?? "",language:a.language ?? "en-US") }
        } else { result += split(correct ? "Doğru cevap." : "Doğru yanıt: "+q.correctAnswerText+".") }
        result += split((explain ? q.explanation : "")+(last ? " Tur tamamlandı." : " Sıradaki soruya geçiyoruz."))
        return coalesced(result)
    }
    static func coalesced(_ segments: [QuizSpeechSegment]) -> [QuizSpeechSegment] {
        var result: [QuizSpeechSegment] = []
        for segment in segments {
            if let last = result.last, last.language == segment.language, last.text.count+segment.text.count+1 <= 1000 {
                result[result.count-1] = .init(text:last.text+" "+segment.text,language:segment.language)
            } else { result.append(segment) }
        }
        return result
    }
    static func split(_ text: String, language: String = "tr-TR") -> [QuizSpeechSegment] {
        var result: [QuizSpeechSegment] = [], current = ""
        for word in text.split(whereSeparator:\.isWhitespace) {
            if current.count+word.count+1 > 1000, !current.isEmpty { result.append(.init(text:current,language:language)); current = "" }
            if word.count > 1000 { for start in stride(from:0,to:word.count,by:1000) { let chars = Array(word); result.append(.init(text:String(chars[start..<min(start+1000,chars.count)]),language:language)) } }
            else { current += (current.isEmpty ? "" : " ")+word }
        }
        if !current.isEmpty { result.append(.init(text:current,language:language)) }; return result
    }
}
enum QuizLiveEngine: String, CaseIterable, Identifiable {
    case chained, openAI, gemini
    var id: String { rawValue }
    var title: String { switch self { case .chained:return "Asistan · Sıralı sesli"; case .openAI:return "ChatGPT Realtime"; case .gemini:return "Gemini Live" } }
}
enum QuizHearingPhase { case opening, recording, transcribing }
@MainActor protocol QuizLiveVoice: AnyObject {
    var route: String { get }
    var level: Double { get }
    var hearingPhase: QuizHearingPhase { get }
    func prepare() async throws
    func speak(_ segments: [QuizSpeechSegment]) async throws
    func hear(language: String) async throws -> String
    func finishHearing()
    func stop()
}
extension QuizLiveVoice { var hearingPhase: QuizHearingPhase { .recording } }
@MainActor final class ChainedQuizVoice: QuizLiveVoice {
    let voice: VoiceAnswerStore
    let speaker = QuestionSpeaker()
    var localOnly = false
    var route: String { localOnly ? "iPhone sesi + cihazda Whisper" : "Seçtiğin soru sesi + cihazda Whisper" }
    var level: Double { voice.level }
    var hearingPhase: QuizHearingPhase {
        switch voice.phase { case .recording:return .recording; case .transcribing:return .transcribing; default:return .opening }
    }
    init(voice: VoiceAnswerStore) { self.voice = voice }
    func prepare() async throws {
        voice.prepare()
        while voice.phase == .preparing { try Task.checkCancellation(); try await Task.sleep(for:.milliseconds(100)) }
        guard voice.ready else { throw QuizError(voice.error ?? "Whisper hazırlanamadı.") }
    }
    func speak(_ segments: [QuizSpeechSegment]) async throws {
        for segment in segments {
            try Task.checkCancellation()
            var completed = false
            let choice: QuestionVoiceChoice? = localOnly ? .init(engine:.apple,voice:"",model:"") : nil
            speaker.speakText(segment.text,language:segment.language,choice:choice) { completed = $0 }
            while speaker.playing { try Task.checkCancellation(); try await Task.sleep(for:.milliseconds(100)) }
            guard completed else { throw QuizError(speaker.error ?? "Soru sesi tamamlanamadı.") }
        }
    }
    func hear(language: String) async throws -> String {
        voice.record(language:language,automaticStop:true)
        while voice.phase != .idle { try Task.checkCancellation(); try await Task.sleep(for:.milliseconds(100)) }
        if let error = voice.error { throw QuizError(error) }
        return voice.transcript
    }
    func finishHearing() { voice.finishRecording() }
    func stop() { speaker.cancel(); voice.cancel() }
}
