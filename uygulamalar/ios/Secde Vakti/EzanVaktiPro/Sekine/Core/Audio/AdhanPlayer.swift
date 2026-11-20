import Foundation
import AVFoundation
import UserNotifications
import CryptoKit
import SwiftUI

extension Notification.Name {
    static let triggerFullScreenVakitAlarm = Notification.Name("ezanvaktipro.triggerFullScreenVakitAlarm")
}

/// Uygulama-içi Tam Ezan, Kur'an Tilaveti, Türkçe Sesli Meal/Hadis (TTS) ve 7/24 Kur'an Radyosu Motoru.
@MainActor
final class AdhanPlayer: NSObject, ObservableObject {
    static let shared = AdhanPlayer()

    enum PlaybackMode: String {
        case none = "Hazır"
        case adhanMekke = "Mekke Ezanı Okunuyor"
        case adhanMedine = "Medine Ezanı Okunuyor"
        case quranRecitation = "Kur'an-ı Kerim Tilaveti"
        case turkishSpeech = "Sesli Meal & Hadis-i Şerif"
        case fullVakitCombo = "Vaktin Ayeti, Meal & Hadis Paketi"
        case quranRadio = "7/24 Canlı Kur'an Radyosu"
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var mode: PlaybackMode = .none
    @Published private(set) var activeTitle: String = ""
    @Published private(set) var activeSubtitle: String = ""
    @Published var selectedReciterIdentifier: String = "ar.alafasy"

    private var audioPlayer: AVAudioPlayer?
    private var streamPlayer: AVPlayer?
    private var streamEndObserver: NSObjectProtocol?
    @Published private(set) var isPreparing = false
    @Published private(set) var isPaused = false
    @Published var speechError: String?
    private var speechTask: Task<Void, Never>?
    private var speechGeneration = UUID()
    private var studioQueue: [URL] = []
    var studioRate: Float {
        let value = UserDefaults.standard.double(forKey: "studio.rate")
        return value == 0 ? 1 : Float(min(1.3, max(0.75, value)))
    }
    private var pendingComboPacket: VakitSpiritualPacket?
    private var pendingIkraTurkishURL: URL?
    private var pendingIkraFallbackText: String?
    private var pendingIkraTurkishArtist: String?
    private var pendingPlaybackRate: Float = 1.0
    private var recitationQueue: [URL] = []

    override init() {
        super.init()

    }

    private func activateAudioSession() {
        QFSyncPlayer.shared.stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AdhanPlayer session error:", error)
        }
    }

    /// Bundle'daki tam ezan dosyasını çalar (Mekke veya Medine makamı).
    func play(resource: String = "ezan-full", extensions: [String] = ["mp3", "m4a", "caf"]) {
        stop()
        guard let url = Self.url(resource: resource, extensions: extensions) else { return }
        do {
            activateAudioSession()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
            self.isPlaying = true
            self.mode = resource.contains("medine") ? .adhanMedine : .adhanMekke
            self.activeTitle = resource.contains("medine") ? "Medine-i Münevvere Ezanı" : "Mekke-i Mükerreme Ezanı"
            self.activeSubtitle = "Tam Ezan Tilaveti"
        } catch {
            isPlaying = false
            mode = .none
        }
    }

    /// Belirli bir ayetin Arapça tilavetini (önce yerel bundle, yoksa Islamic Network CDN) çalar.
    func playAyahRecitation(globalAyahNumber: Int, title: String = "Vaktin Ayet-i Kerimesi") {
        stop()
        activateAudioSession()
        self.mode = .quranRecitation
        self.activeTitle = title
        self.activeSubtitle = "Hafız Mishary Rashid Alafasy"
        self.isPlaying = true

        // Yerel önbellek kontrolü
        if globalAyahNumber == 1, let localURL = Self.url(resource: "besmele", extensions: ["mp3"]),
           let p = try? AVAudioPlayer(contentsOf: localURL) {
            p.delegate = self
            p.play()
            self.audioPlayer = p
            return
        }
        if globalAyahNumber == 262, let localURL = Self.url(resource: "ayetel_kursi", extensions: ["mp3"]),
           let p = try? AVAudioPlayer(contentsOf: localURL) {
            p.delegate = self
            p.play()
            self.audioPlayer = p
            return
        }

        let urlStr = "https://cdn.islamic.network/quran/audio/128/\(selectedReciterIdentifier)/\(globalAyahNumber).mp3"
        guard let url = URL(string: urlStr) else {
            self.isPlaying = false
            self.mode = .none
            return
        }
        playStream(url: url)
    }

    /// Herhangi bir uzak ses URL'sini (ayet, kelime veya sûre MP3) çalar.
    func playRemoteAudio(urlString: String, title: String) {
        stop()
        activateAudioSession()
        guard let url = URL(string: urlString) else { return }
        self.mode = .quranRecitation
        self.activeTitle = title
        self.activeSubtitle = "Kur'an Bilmek Sesli Okuma"
        self.isPlaying = true
        playStream(url: url, rate: 1.0)
    }

    /// Yerel (indirilen/yerleşik) veya uzak MP3 dosyasını hız kontrolüyle çalar.
    func playLocalOrRemoteFile(url: URL, title: String, subtitle: String, rate: Float = 1.0) {
        stop()
        activateAudioSession()
        self.mode = .quranRecitation
        self.activeTitle = title
        self.activeSubtitle = subtitle
        self.isPlaying = true
        self.pendingPlaybackRate = rate

        if url.isFileURL, let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
            return
        }
        playStream(url: url, rate: rate)
    }

    /// İkra Modu: 1. Arapça Hafız Tilaveti -> 2. Ünlü Sanatçıdan Stüdyo Türkçe Sesli Meal MP3!
    func playSequentialIkraPair(
        arabicURL: URL,
        turkishMealURL: URL?,
        fallbackTurkishText: String?,
        title: String,
        arabicReciterName: String,
        turkishArtistName: String,
        rate: Float = 1.0
    ) {
        stop()
        activateAudioSession()
        self.mode = .fullVakitCombo
        self.activeTitle = title
        self.activeSubtitle = "1/2 · Arapça Tilavet: \(arabicReciterName)"
        self.isPlaying = true
        self.pendingIkraTurkishURL = turkishMealURL
        self.pendingIkraFallbackText = fallbackTurkishText
        self.pendingIkraTurkishArtist = turkishArtistName
        self.pendingPlaybackRate = rate
        playStream(url: arabicURL, rate: rate)
    }

    /// Canlı Diyanet Kur'an Radyo / Türkçe Meal Radyosu / Haremeyn Radyosu oynatır.
    func playLiveRadioStation(url: URL, title: String, subtitle: String) {
        stop()
        activateAudioSession()
        self.mode = .quranRadio
        self.activeTitle = title
        self.activeSubtitle = subtitle
        self.isPlaying = true
        playStream(url: url, rate: 1.0)
    }

    /// Neural studio narration; Arabic recitation continues to use human recordings.
    func speakText(_ text: String, language: String = "tr-TR") {
        speakStudio(text, language: language, title: language.hasPrefix("ar") ? "Arapça Kelime Telaffuzu" : "Sesli Kelime Manası")
    }

    func speakTurkish(text: String, title: String = "Sesli Meal & Hadis") {
        speakStudio(text, language: "tr-TR", title: title)
    }

    private func speakStudio(_ text: String, language: String, title: String) {
        QFSyncPlayer.shared.stop()
        stop()
        let chunks = StudioSpeech.chunks(text)
        guard !chunks.isEmpty else { return }
        let selected = UserDefaults.standard.string(forKey: "studio.voice") ?? "aydin"
        let voice = language.hasPrefix("ar") ? "arabic" : (selected == "elif" ? "elif" : "aydin")
        let generation = speechGeneration
        activeTitle = title
        activeSubtitle = "Stüdyo sesi hazırlanıyor…"
        mode = .turkishSpeech
        isPreparing = true
        speechError = nil
        speechTask = Task { [weak self] in
            do {
                var urls: [URL] = []
                for (index, chunk) in chunks.enumerated() {
                    let url = try await StudioSpeech.shared.audio(text: chunk, voice: voice)
                    try Task.checkCancellation()
                    guard let self, self.speechGeneration == generation else { return }
                    urls.append(url)
                    self.activeSubtitle = "Stüdyo sesi hazırlanıyor · \(index + 1)/\(chunks.count)"
                }
                guard let self, self.speechGeneration == generation else { return }
                self.studioQueue = urls
                self.isPreparing = false
                self.activeSubtitle = voice == "arabic" ? "Arapça · Yapay zekâ seslendirmesi" : "\(voice == "elif" ? "Elif" : "Aydın") HD · Stüdyo seslendirme"
                self.playNextStudioSegment()
            } catch {
                guard let self, self.speechGeneration == generation, !Task.isCancelled else { return }
                self.stop()
                self.speechError = "Stüdyo sesi hazırlanamadı. İnternet bağlantınızı kontrol edip yeniden deneyin. Daha önce dinlenen sesler çevrimdışı kullanılabilir."
            }
        }
    }

    private func playNextStudioSegment() {
        guard !studioQueue.isEmpty else { stop(); return }
        do {
            activateAudioSession()
            let player = try AVAudioPlayer(contentsOf: studioQueue.removeFirst())
            player.delegate = self
            player.enableRate = true
            player.rate = studioRate
            guard player.prepareToPlay(), player.play() else { throw URLError(.cannotDecodeContentData) }
            audioPlayer = player
            isPlaying = true
            isPaused = false
        } catch {
            stop()
            speechError = "Ses dosyası oynatılamadı. Lütfen yeniden deneyin."
        }
    }

    func toggleStudioPause() {
        guard mode == .turkishSpeech, let player = audioPlayer else { return }
        if isPaused { player.rate = studioRate; player.play() } else { player.pause() }
        isPaused.toggle()
    }

    /// Tam Vakit Paketi: Önce Arapça Ayet Tilaveti -> Ardından Türkçe Sesli Meal + Hadis + Dua!
    func playFullVakitPacket(_ packet: VakitSpiritualPacket) {
        stop()
        activateAudioSession()
        self.pendingComboPacket = packet
        self.mode = .fullVakitCombo
        self.activeTitle = packet.badgeTitle
        self.activeSubtitle = "1/2 · Arapça Kur'an Tilaveti"
        self.isPlaying = true

        if packet.globalAyahNumber == 262,
           let localURL = Self.url(resource: "ayetel_kursi", extensions: ["mp3"]),
           let p = try? AVAudioPlayer(contentsOf: localURL) {
            p.delegate = self
            p.play()
            self.audioPlayer = p
            return
        }
        if packet.globalAyahNumber == 1,
           let localURL = Self.url(resource: "besmele", extensions: ["mp3"]),
           let p = try? AVAudioPlayer(contentsOf: localURL) {
            p.delegate = self
            p.play()
            self.audioPlayer = p
            return
        }

        let urlStr = "https://cdn.islamic.network/quran/audio/128/\(selectedReciterIdentifier)/\(packet.globalAyahNumber).mp3"
        if let url = URL(string: urlStr) {
            playStream(url: url)
        } else {
            continueComboWithTurkishSpeech(packet)
        }
    }

    private func continueComboWithTurkishSpeech(_ packet: VakitSpiritualPacket) {
        self.activeSubtitle = "2/2 · Türkçe Meal, Hadis & Dua"
        let fullText = """
        \(packet.badgeTitle).
        Vaktin Ayeti Kerimesi, \(packet.verseSource):
        \(packet.turkishVerse)
        Vaktin Hadisi Şerifi, \(packet.hadithSource):
        \(packet.hadithTurkish)
        Vaktin Duası:
        \(packet.duaTurkish)
        """
        speakTurkish(text: fullText, title: packet.badgeTitle)
    }

    /// 7/24 Canlı Kur'an Radyosu çalar.
    func toggleQuranRadio() {
        if isPlaying && mode == .quranRadio {
            stop()
            return
        }
        stop()
        activateAudioSession()
        guard let url = URL(string: "https://eustr76.mediatriple.net/videoonlylive/mtikoimxnztxlive/broadcast_5e3c14192aa92.smil/playlist.m3u8") else { return }
        self.mode = .quranRadio
        self.activeTitle = "Diyanet Kur’an Radyo"
        self.activeSubtitle = "Diyanet · Canlı yayın"
        self.isPlaying = true
        playStream(url: url)
    }

    func playRecitationSequence(urls: [URL], title: String, subtitle: String, rate: Float = 1) {
        stop()
        guard let first = urls.first else { return }
        activateAudioSession()
        recitationQueue = Array(urls.dropFirst())
        pendingPlaybackRate = rate
        activeTitle = title
        activeSubtitle = subtitle
        mode = .quranRecitation
        isPlaying = true
        playStream(url: first, rate: rate)
    }

    private func playStream(url: URL, rate: Float = 1.0) {
        if let obs = streamEndObserver {
            NotificationCenter.default.removeObserver(obs)
            streamEndObserver = nil
        }
        let generation = speechGeneration
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.streamPlayer = player
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.speechGeneration == generation else { return }
                if !self.recitationQueue.isEmpty {
                    let next = self.recitationQueue.removeFirst()
                    self.playStream(url: next, rate: self.pendingPlaybackRate)
                } else if let combo = self.pendingComboPacket {
                    self.pendingComboPacket = nil
                    self.continueComboWithTurkishSpeech(combo)
                } else if let trURL = self.pendingIkraTurkishURL {
                    let artist = self.pendingIkraTurkishArtist ?? "Türkçe Sesli Meal"
                    let r = self.pendingPlaybackRate
                    self.pendingIkraTurkishURL = nil
                    self.pendingIkraTurkishArtist = nil
                    self.pendingIkraFallbackText = nil
                    self.activeSubtitle = "2/2 · Türkçe Meal: \(artist)"
                    if trURL.isFileURL, let p = try? AVAudioPlayer(contentsOf: trURL) {
                        p.delegate = self
                        p.enableRate = true
                        p.rate = r
                        p.play()
                        self.audioPlayer = p
                    } else {
                        self.playStream(url: trURL, rate: r)
                    }
                } else if let fbText = self.pendingIkraFallbackText {
                    self.pendingIkraFallbackText = nil
                    self.speakTurkish(text: fbText, title: self.activeTitle)
                } else {
                    self.stop()
                }
            }
        }
        player.play()
        if rate != 1.0 {
            player.rate = rate
        }
    }

    func stop() {
        speechGeneration = UUID()
        speechTask?.cancel()
        speechTask = nil
        studioQueue.removeAll()
        isPreparing = false
        isPaused = false
        recitationQueue.removeAll()
        pendingComboPacket = nil
        pendingIkraTurkishURL = nil
        pendingIkraFallbackText = nil
        pendingIkraTurkishArtist = nil
        if let obs = streamEndObserver {
            NotificationCenter.default.removeObserver(obs)
            streamEndObserver = nil
        }
        audioPlayer?.stop()
        audioPlayer = nil
        streamPlayer?.pause()
        streamPlayer = nil
        isPlaying = false
        mode = .none
        activeTitle = ""
        activeSubtitle = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ezan ses dosyası bundle'da mevcut mu?
    static var isAvailable: Bool {
        url(resource: "ezan-full", extensions: ["mp3", "m4a", "caf"]) != nil
    }

    private static func url(resource: String, extensions: [String]) -> URL? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: resource, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// Kullanıcının iPhone'unda anında test edebilmesi için 3 saniye sonraya gerçek Videolu & Ezan Sesli Vakit Bildirimi gönderir!
    func scheduleInstantRichVideoNotification(for prayer: Prayer) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let packet = VakitSpiritualDatabase.packet(for: prayer)
        let content = UNMutableNotificationContent()
        content.title = "🕌 \(packet.badgeTitle)"
        content.subtitle = "📖 \(packet.verseSource) · Sesli Video Ayet & Hadis"
        content.body = "Ayet: “\(packet.turkishVerse)”\nHadis: “\(packet.hadithTurkish)” (\(packet.hadithSource))"
        content.sound = NotificationSound.ezan.unSound(silent: false)
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["vakitPrayer": prayer.rawValue]

        // Gerçek MP4 Video Ayet & Hadis eklentisi (UNNotificationAttachment)
        if let bundleVideoURL = Bundle.main.url(forResource: packet.videoFileName, withExtension: "mp4") {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("notif_\(packet.videoFileName)_\(UUID().uuidString).mp4")
            try? FileManager.default.copyItem(at: bundleVideoURL, to: tempURL)
            if let attachment = try? UNNotificationAttachment(identifier: "vakit-video", url: tempURL, options: nil) {
                content.attachments = [attachment]
            }
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: "instant.vakit.video.\(UUID().uuidString)", content: content, trigger: trigger)
        do {
            try await center.add(req)
            return true
        } catch {
            return false
        }
    }
}

extension AdhanPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audioPlayer === player else { return }
            if !flag {
                self.stop()
                self.speechError = "Ses oynatma tamamlanamadı."
            } else if !self.studioQueue.isEmpty {
                self.playNextStudioSegment()
            } else if let combo = self.pendingComboPacket {
                self.pendingComboPacket = nil
                self.continueComboWithTurkishSpeech(combo)
            } else {
                self.stop()
            }
        }
    }
}

/// Disk cache is keyed by voice, content and synthesis version; never stores API credentials.
actor StudioSpeech {
    static let shared = StudioSpeech()
    static let endpoint = URL(string: "https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/secde-studio/speech")!
    private let directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StudioSpeech-v1", isDirectory: true)

    nonisolated static func chunks(_ text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        var result: [String] = []
        var current = ""
        for word in words {
            if current.count + word.count + 1 > 900, !current.isEmpty { result.append(current); current = "" }
            // Also bound individual long tokens to keep the server contract valid.
            var remainder = String(word)
            while remainder.count > 900 {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(remainder.prefix(900)))
                remainder = String(remainder.dropFirst(900))
            }
            current += (current.isEmpty ? "" : " ") + remainder
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    func audio(text: String, voice: String) async throws -> URL {
        let hash = SHA256.hash(data: Data(("v1|" + voice + "|" + text).utf8)).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(hash + ".mp3")
        if let data = try? Data(contentsOf: file), Self.validAudio(data) { return file }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "voice": voice])
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (http.statusCode == 429 || http.statusCode == 503), attempt < 2 {
                let delay = min(30, max(2, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            guard http.statusCode == 200, Self.validAudio(data) else { throw URLError(.cannotDecodeContentData) }
            try Task.checkCancellation()
            try data.write(to: file, options: .atomic)
            trimCache(excluding: file)
            return file
        }
        throw URLError(.badServerResponse)
    }

    private static func validAudio(_ data: Data) -> Bool {
        data.count > 1000 && (data.starts(with: [0x49, 0x44, 0x33]) || data.first == 0xff)
    }

    func clearCache() { try? FileManager.default.removeItem(at: directory) }

    private func trimCache(excluding file: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 < $1.1 }
        var total = entries.reduce(0) { $0 + $1.2 }
        for entry in entries where total > 150 * 1024 * 1024 && entry.0 != file {
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.2
        }
    }
}

struct StudioVoiceSettings: View {
    @AppStorage("studio.voice") private var voice = "aydin"
    @AppStorage("studio.rate") private var rate = 1.0
    @ObservedObject private var player = AdhanPlayer.shared
    @State private var cacheCleared = false
    var body: some View {
        Section {
            Picker("Anlatıcı", selection: $voice) {
                Text("Aydın · Erkek · HD").tag("aydin")
                Text("Elif · Kadın · HD").tag("elif")
            }
            HStack {
                Text("Okuma hızı")
                Slider(value: $rate, in: 0.75...1.3, step: 0.05)
                Text(String(format: "%.2f×", rate)).monospacedDigit()
            }
            Button {
                player.speakTurkish(text: "Secde Vakti. Kalbiniz huzurla, gününüz dua ile dolsun.", title: "Stüdyo Ses Denemesi")
            } label: { Label("Sesi dinle", systemImage: "speaker.wave.2.fill") }
            if player.isPreparing { ProgressView(player.activeSubtitle) }
            if player.mode == .turkishSpeech && (player.isPlaying || player.isPreparing) {
                HStack {
                    if player.isPlaying {
                        Button(player.isPaused ? "Devam et" : "Duraklat") { player.toggleStudioPause() }
                    }
                    Spacer()
                    Button("Durdur") { player.stop() }
                }.buttonStyle(.borderless)
            }
            Button(cacheCleared ? "Ses önbelleği temizlendi" : "İndirilen anlatımları temizle") {
                player.stop()
                Task { await StudioSpeech.shared.clearCache(); cacheCleared = true }
            }
        } header: { Text("Stüdyo Seslendirme") } footer: {
            Text("Dua, hadis ve açıklamalar yapay zekâ destekli HD seslerle okunur. İlk dinleme internet gerektirir; saklanan sesler çevrimdışı çalar. Kur’an tilavetleri ve kayıtlı mealler kendi okuyucularının sesini kullanır.")
        }
    }
}
