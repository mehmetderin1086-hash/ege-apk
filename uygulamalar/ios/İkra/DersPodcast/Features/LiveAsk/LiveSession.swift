import AVFoundation
import Foundation
import Observation

/// Sesli soru-cevap oturumu (sıra tabanlı). Soru iPhone'un konuşma tanımasıyla yazıya dökülür, cevabı sunucuda Claude yazar
/// (`/v1/voice-ask`), cevap cihaz sesiyle okunur; sonra yeniden dinlenir. Ses sunucuya gitmez. (Gemini Live 11 Eki 2026'da kaldırıldı.)
@Observable
final class LiveSession {
    enum State: Equatable {
        case idle, connecting, listening, answering
        case ended(String?)
    }

    private(set) var state: State = .idle
    private(set) var userText = ""
    private(set) var answerText = ""
    private(set) var remainingSeconds = 0
    private(set) var level: Float = 0
    /// #30: tamamlanan her soru-cevap (soru, cevap); görünüm kaydeder. Cevabın yazısı gelince çağrılır (okuma bitmeden).
    @ObservationIgnored var onExchange: ((String, String) -> Void)?

    /// Oturumun üst sınırı (sn): mikrofon unutulup açık kalmasın.
    nonisolated static let maxSessionSeconds = 600
    /// Konuşma bittikten sonra sorunun kendiliğinden gönderilmesi için beklenen sessizlik (sn).
    nonisolated static let silenceSeconds = 1.8

    /// Her oturum kendi kaydedicisini kullanır: önceki oturumun süren kapanışı (son sözcüklerin toplanması) yenisini engellemesin.
    private var recorder = SpeechRecorder()
    private var request: VoiceAskRequest?
    /// Bu oturumda konuşulanlar: sonraki soruya bağlam olarak gider.
    private var asked: [LiveQA] = []
    private var loop: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var newTurn = true
    private var waitingForAnswer = false
    private var submitRequested = false
    /// Art arda, başlar başlamaz duran dinlemeler (ör. Dikte kapalı): üçüncüsünde oturum bitirilir, sonsuz döngüye girilmez.
    private var quickStops = 0
    /// #30: her `start` yeni bir kuşak açar. Önceki oturumun geç gelen yanıtı ya da zamanlayıcısı yeni oturumu etkilemez.
    @ObservationIgnored private var generation = 0

    func start(_ request: VoiceAskRequest) async {
        guard state == .idle || isEnded else { return }
        generation += 1
        let gen = generation
        state = .connecting
        userText = ""
        answerText = ""
        newTurn = true
        asked = []
        quickStops = 0
        recorder = SpeechRecorder()
        self.request = request

        if let message = await SpeechRecorder.requestPermissions() {
            guard generation == gen else { return }
            state = .ended(message)
            return
        }
        // Kullanıcı beklerken "Bitir"e bastıysa (ya da mod değiştiyse) hiçbir şey açma.
        guard isCurrent(gen), state == .connecting, !Task.isCancelled else { return }
        remainingSeconds = Self.maxSessionSeconds
        startTimer(gen)
        loop = Task { [weak self] in await self?.run(gen, opening: Self.openingTurn(mode: request.mode)) }
    }

    /// `gen` hâlâ süren oturum mu (bitmiş ya da yenisiyle değişmiş değil).
    private func isCurrent(_ gen: Int) -> Bool { generation == gen && !isEnded }

    /// Sessizlik beklenmeden soruyu gönderir ("Soruyu gönder").
    func submitQuestion() async {
        guard state == .listening, !waitingForAnswer else { return }
        submitRequested = true
    }

    var isWaitingForAnswer: Bool { waitingForAnswer }
    /// Sürmekte olan (henüz kaydedilmemiş) soru-cevap var mı.
    var isTurnOpen: Bool { !newTurn && (!userText.isEmpty || !answerText.isEmpty) }

    func stop() {
        guard !isEnded else { return }
        finish(nil)
    }

    var isEnded: Bool { if case .ended = state { true } else { false } }

    // MARK: - Döngü

    private func run(_ gen: Int, opening: String?) async {
        // "Bana anlat": ilk sözü yapay zekâ alır (kendini tanıtıp konuyu anlatmanı ister).
        if let opening {
            guard await answer(to: opening, shown: "", gen: gen) else { return }
        }
        while isCurrent(gen), !Task.isCancelled {
            guard let question = await listen(gen) else { return }
            if question.isEmpty { continue }   // hiçbir şey söylenmedi: yeniden dinle
            guard await answer(to: question, shown: question, gen: gen) else { return }
        }
    }

    /// Kullanıcıyı dinler; söz bitince (sessizlik ya da "Soruyu gönder") yazıya dökülmüş metni döndürür. Oturum bittiyse nil.
    private func listen(_ gen: Int) async -> String? {
        submitRequested = false
        waitingForAnswer = false
        let recorder = recorder   // bu oturumun kaydedicisi: yeni oturum kendi kaydedicisini kurar
        let began = Date.now
        await recorder.start()
        guard isCurrent(gen) else { recorder.cancel(); return nil }
        guard recorder.isRecording else {
            finish(recorder.error ?? "Mikrofon başlatılamadı. Yeniden dene.")
            return nil
        }
        state = .listening
        var last = "", lastChange = Date.now
        while isCurrent(gen), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            guard isCurrent(gen) else { break }
            // Değer değişmediyse atama yapma: @Observable eşit atamada da gözlemcileri uyarır.
            if recorder.level != level { level = recorder.level }
            let text = recorder.transcript
            if text != last {
                last = text
                lastChange = .now
                if newTurn, !text.isEmpty { answerText = ""; newTurn = false }
                if !newTurn { userText = text }
            }
            // Tanıyıcı durduysa: söz varsa o ana kadarki metin gönderilir. Söz yoksa (uzun sessizlikte tanıyıcı kendiliğinden kapanır)
            // dinleme yeniden açılır; hemen duran dinleme üst üste gelirse sorun kalıcıdır, oturum bitirilir.
            if recorder.error != nil {
                if !text.isEmpty { break }
                recorder.cancel()
                quickStops = Date.now.timeIntervalSince(began) < 5 ? quickStops + 1 : 0
                if quickStops >= 3 { finish("Konuşma tanıma başlatılamadı. Ayarlar → Genel → Klavye → Dikte’nin açık olduğunu kontrol et."); return nil }
                return ""
            }
            if submitRequested || (!text.isEmpty && Date.now.timeIntervalSince(lastChange) >= Self.silenceSeconds) { break }
        }
        guard isCurrent(gen) else { recorder.cancel(); return nil }
        waitingForAnswer = true
        let final = (await recorder.stop()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCurrent(gen) else { return nil }
        if level != 0 { level = 0 }
        if final.isEmpty { waitingForAnswer = false } else { newTurn = false; userText = final; quickStops = 0 }
        return final
    }

    /// Soruyu sunucuya gönderir, cevabı yazar ve cihaz sesiyle okur. Oturum sürüyorsa true.
    private func answer(to question: String, shown: String, gen: Int) async -> Bool {
        guard var request else { return false }
        waitingForAnswer = true
        if state == .connecting { state = .listening }   // açılış turunda: "hazırlanıyor" yazısı görünsün
        request.question = String(question.prefix(2000))
        request.history = Array(((request.history ?? []) + asked).suffix(6))
        do {
            let reply = try await APIClient.shared.voiceAsk(request)
            guard isCurrent(gen) else { return false }
            let text = reply.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { finish("Cevap alınamadı. Yeniden dene."); return false }
            userText = shown
            answerText = text
            asked.append(LiveQA(q: String(shown.prefix(500)), a: String(text.prefix(1500))))
            // Cevabın yazısı tamam: kayıt şimdi yapılır; okuma yarıda kesilse de soru-cevap kaybolmaz.
            onExchange?(shown, text)
            newTurn = true
            waitingForAnswer = false
            state = .answering
            await SpeechOut.shared.speak(text)
            return isCurrent(gen)
        } catch {
            guard isCurrent(gen) else { return false }
            finish(error.localizedDescription)
            return false
        }
    }

    private func startTimer(_ gen: Int) {
        let deadline = Date.now.addingTimeInterval(Double(remainingSeconds))
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                // İptal uykuyu hemen bitirir: eski zamanlayıcı yeni oturumun durumunu yoklamasın.
                guard !Task.isCancelled, let self, isCurrent(gen) else { return }
                let remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                if remaining != remainingSeconds { remainingSeconds = remaining }
                if remaining == 0 {
                    finish("Soru süresi doldu.")
                    return
                }
            }
        }
    }

    private func finish(_ message: String?) {
        waitingForAnswer = false
        submitRequested = false
        timerTask?.cancel()
        loop?.cancel()
        recorder.cancel()
        SpeechOut.shared.stop()
        state = .ended(message)
        level = 0
    }
}

extension LiveSession {
    /// "Bana anlat" kipinde oturumu yapay zekânın başlatması için gönderilen ilk söz; soru kipinde yoktur.
    nonisolated static func openingTurn(mode: String?) -> String? { mode == "teach" ? "Başla" : nil }
}
