import SwiftUI
import AVFoundation

struct QFTimingRow: Decodable {
    let surah: Int
    let ayah: Int
    let segments: [[Int]]
    var key: String { "\(surah):\(ayah)" }
    /// Source word indices are zero-based, with an exclusive upper bound.
    func positions(at milliseconds: Int, wordCount: Int) -> Set<Int> {
        guard let maximum = segments.filter({ $0.count == 4 }).map({ $0[1] }).max(), maximum == wordCount else { return [] }
        guard let segment = segments.first(where: {
            $0.count == 4 && $0[0] >= 0 && $0[1] > $0[0] && $0[1] <= wordCount && $0[2] <= milliseconds && milliseconds < $0[3]
        }) else { return [] }
        return Set((segment[0] + 1)...segment[1])
    }
    func startTime(position: Int) -> Double? {
        segments.first { $0.count == 4 && $0[0] < position && position <= $0[1] }.map { Double($0[2]) / 1000 }
    }
}

struct QFSyncReciter: Identifiable {
    let id: String
    let name: String
    static let all: [QFSyncReciter] = [
        .init(id: "Alafasy_128kbps", name: "Mişârî Râşid el-Afâsî"),
        .init(id: "Husary_64kbps", name: "Mahmud Halil el-Husarî"),
        .init(id: "Minshawy_Murattal_128kbps", name: "Muhammed Sıddîk el-Minşâvî")
    ]
}

actor QFSyncLibrary {
    static let shared = QFSyncLibrary()
    private var tables: [String: [String: QFTimingRow]] = [:]
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("QFSyncAudio-v1", isDirectory: true)
    func timing(reciter: String, verseKey: String) throws -> QFTimingRow? {
        if tables[reciter] == nil {
            guard QFSyncReciter.all.contains(where: { $0.id == reciter }),
                  let url = Bundle.main.url(forResource: reciter, withExtension: "json", subdirectory: "QuranTiming") else { throw URLError(.fileDoesNotExist) }
            let rows = try JSONDecoder().decode([QFTimingRow].self, from: Data(contentsOf: url))
            tables[reciter] = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return tables[reciter]?[verseKey]
    }
    func audio(reciter: String, surah: Int, ayah: Int) async throws -> URL {
        guard QFSyncReciter.all.contains(where: { $0.id == reciter }), (1...114).contains(surah), (1...286).contains(ayah) else { throw URLError(.badURL) }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let filename = String(format: "%03d%03d.mp3", surah, ayah)
        let file = cache.appendingPathComponent(reciter + "-" + filename)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let url = URL(string: "https://everyayah.com/data/\(reciter)/\(filename)")!
        var request = URLRequest(url: url); request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000,
              data.starts(with: [0x49, 0x44, 0x33]) || data.first == 0xff else { throw URLError(.cannotDecodeContentData) }
        try data.write(to: file, options: .atomic)
        trim(excluding: file)
        return file
    }
    private func trim(excluding keep: URL) {
        let entries = ((try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []).compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > 200 * 1024 * 1024 && entry.0 != keep {
            try? FileManager.default.removeItem(at: entry.0); total -= entry.1
        }
    }
}

@MainActor final class QFSyncPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = QFSyncPlayer()
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var verseKey: String?
    @Published private(set) var positions: Set<Int> = []
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var status = "Tilavetle eşzamanlı kelime takibi"
    @Published var errorMessage: String?
    @Published var autoScroll = true
    @Published private(set) var reciter = UserDefaults.standard.string(forKey: "kb.sync.reciter") ?? "Alafasy_128kbps"
    @Published private(set) var rate: Float = 1
    @Published var repeats = 1 { didSet { remainingRepeats = max(1, repeats) } }
    private var remainingRepeats = 1
    private var queue: [KBVerse] = []
    private var index = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var prefetch: Task<Void, Never>?
    private var generation = UUID()
    private var timing: QFTimingRow?
    private var interruption: NSObjectProtocol?
    var focusedWordID: String? {
        guard let verseKey, let first = positions.min() else { return nil }
        return Self.wordID(verseKey: verseKey, position: first)
    }
    nonisolated static func wordID(verseKey: String, position: Int) -> String { "sync-word-\(verseKey)-\(position)" }
    override init() {
        super.init()
        if !QFSyncReciter.all.contains(where: { $0.id == reciter }) { reciter = "Alafasy_128kbps" }
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }
    func setReciter(_ id: String) {
        guard QFSyncReciter.all.contains(where: { $0.id == id }) else { return }
        stop(); reciter = id; UserDefaults.standard.set(id, forKey: "kb.sync.reciter")
    }
    func setRate(_ value: Float) { rate = min(1.25, max(0.5, value)); player?.rate = rate }
    func start(verses: [KBVerse], from key: String? = nil) {
        stop()
        guard !verses.isEmpty else { return }
        AdhanPlayer.shared.stop()
        KuranBilmekStore.shared.stopWordAudio()
        queue = verses
        let bookmark = key ?? UserDefaults.standard.string(forKey: "kb.sync.lastVerse")
        index = queue.firstIndex { $0.verse_key == bookmark } ?? 0
        isActive = true; errorMessage = nil; remainingRepeats = max(1, repeats)
        loadCurrent()
    }
    func pause() { if isLoading { stop(); return }; player?.pause(); isPlaying = false }
    func resume() {
        guard let player, isActive, !isLoading else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate; isPlaying = player.play()
    }
    func skip(_ delta: Int) {
        guard isActive, queue.indices.contains(index + delta) else { return }
        index += delta; remainingRepeats = max(1, repeats); loadCurrent()
    }
    func seek(verse key: String, position: Int) {
        guard isActive, let target = queue.firstIndex(where: { $0.verse_key == key }) else { return }
        if target == index, let player, let seconds = timing?.startTime(position: position) {
            player.currentTime = min(seconds, player.duration); tick()
        } else {
            index = target; remainingRepeats = max(1, repeats); loadCurrent(position: position)
        }
    }
    func seek(seconds: Double) { guard let player else { return }; player.currentTime = min(max(0, seconds), player.duration); tick() }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        prefetch?.cancel(); prefetch = nil
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        isActive = false; isPlaying = false; isLoading = false
        positions = []; verseKey = nil; timing = nil; queue = []
        elapsed = 0; duration = 0
        status = "Tilavetle eşzamanlı kelime takibi"
    }
    private func loadCurrent(position: Int? = nil) {
        generation = UUID(); task?.cancel(); timer?.invalidate(); timer = nil
        player?.stop(); player = nil; timing = nil
        positions = []; elapsed = 0; duration = 0
        guard queue.indices.contains(index) else { stop(); return }
        let verse = queue[index], id = generation, chosenReciter = reciter
        verseKey = verse.verse_key; isLoading = true; isPlaying = false
        status = "\(verse.verse_key) · Tilavet hazırlanıyor…"
        task = Task { [weak self] in
            do {
                let timing = try await QFSyncLibrary.shared.timing(reciter: chosenReciter, verseKey: verse.verse_key)
                let url = try await QFSyncLibrary.shared.audio(reciter: chosenReciter, surah: verse.surahId, ayah: verse.verse_number)
                try Task.checkCancellation()
                guard let self, self.generation == id else { return }
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self; player.enableRate = true; player.rate = self.rate
                // A timing file must fit this exact recording; never stretch or guess its offsets.
                let end = timing?.segments.filter { $0.count == 4 }.map { $0[3] }.max() ?? 0
                let words = timing?.segments.filter { $0.count == 4 }.map { $0[1] }.max() ?? 0
                self.timing = end <= Int(player.duration * 1000) + 100 && words == verse.actualWords.count ? timing : nil
                if let position, let start = self.timing?.startTime(position: position) { player.currentTime = start }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                guard player.prepareToPlay(), player.play() else { throw URLError(.cannotDecodeContentData) }
                self.player = player; self.duration = player.duration
                self.isLoading = false; self.isPlaying = true
                self.status = self.timing == nil ? "\(verse.verse_key) · Bu ayette kelime zamanlaması yok" : "\(verse.verse_key) · Sesle eşzamanlı takip"
                UserDefaults.standard.set(verse.verse_key, forKey: "kb.sync.lastVerse")
                self.timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                RunLoop.main.add(self.timer!, forMode: .common)
                self.tick()
                self.prefetch?.cancel()
                if self.queue.indices.contains(self.index + 1) {
                    let next = self.queue[self.index + 1]
                    self.prefetch = Task {
                        _ = try? await QFSyncLibrary.shared.audio(reciter: chosenReciter, surah: next.surahId, ayah: next.verse_number)
                    }
                }
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.stop()
                self.errorMessage = "Tilavet yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin. İndirilen ayetler önbellekten dinlenebilir."
            }
        }
    }
    private func tick() {
        guard let player, queue.indices.contains(index) else { return }
        elapsed = player.currentTime
        let next = timing?.positions(at: Int(player.currentTime * 1000), wordCount: queue[index].actualWords.count) ?? []
        if next != positions { positions = next }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            if !flag { self.stop(); self.errorMessage = "Tilavet oynatma tamamlanamadı."; return }
            if self.remainingRepeats > 1 {
                self.remainingRepeats -= 1; player.currentTime = 0; player.play(); self.tick()
            } else if self.queue.indices.contains(self.index + 1) {
                self.index += 1; self.remainingRepeats = max(1, self.repeats); self.loadCurrent()
            } else { self.stop(); self.status = "Görüntülenen ayetlerin tilaveti tamamlandı" }
        }
    }
}

struct QFSyncControls: View {
    let verses: [KBVerse]
    @ObservedObject private var sync = QFSyncPlayer.shared
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Okla tilavet takibi").font(.subheadline.weight(.semibold))
                    Text(sync.status).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                if sync.isLoading { ProgressView() }
                if sync.isActive {
                    Button { sync.isPlaying ? sync.pause() : sync.resume() } label: { Image(systemName: sync.isPlaying ? "pause.fill" : "play.fill") }
                        .accessibilityLabel(sync.isPlaying ? "Takibi duraklat" : "Takibe devam et").disabled(sync.isLoading)
                    Button { sync.stop() } label: { Image(systemName: "stop.fill") }.accessibilityLabel("Takibi durdur")
                } else {
                    Button("Okla dinle") { sync.start(verses: verses) }.disabled(verses.isEmpty).accessibilityIdentifier("syncStart")
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "slider.horizontal.3") }.accessibilityLabel("Takip ayarları")
            }.buttonStyle(.borderless)
            if sync.isActive {
                HStack {
                    Button { sync.skip(-1) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Önceki ayet")
                    Slider(value: Binding(get: { sync.elapsed }, set: { sync.seek(seconds: $0) }), in: 0...max(1, sync.duration)).disabled(sync.isLoading)
                        .accessibilityLabel("Ayet içindeki ses konumu")
                    Button { sync.skip(1) } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Sonraki ayet")
                }
            }
            if expanded {
                Picker("Okuyucu", selection: Binding(get: { sync.reciter }, set: { sync.setReciter($0) })) {
                    ForEach(QFSyncReciter.all) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                HStack {
                    Picker("Hız", selection: Binding(get: { sync.rate }, set: { sync.setRate($0) })) {
                        Text("0,5×").tag(Float(0.5)); Text("0,75×").tag(Float(0.75)); Text("1×").tag(Float(1)); Text("1,25×").tag(Float(1.25))
                    }
                    Picker("Ayet tekrarı", selection: $sync.repeats) { Text("1 kez").tag(1); Text("3 kez").tag(3); Text("5 kez").tag(5) }
                }
                Toggle("Okunan kelimeye otomatik kaydır", isOn: $sync.autoScroll).font(.caption)
                Text("Takip açıkken kelimeye dokunarak o noktaya geçebilirsin. Ok yalnızca zamanlaması bulunan kelime veya kelime grubunda görünür. İlk dinleme internet gerektirir.").font(.caption).foregroundStyle(Palette.textSecondary)
                Link("Zamanlama: quran-align · cpfair · CC BY 4.0", destination: URL(string: "https://github.com/cpfair/quran-align")!).font(.caption2)
            }
        }.padding(12).background(Palette.cardActive)
            .alert("Tilavet takibi", isPresented: Binding(get: { sync.errorMessage != nil }, set: { if !$0 { sync.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) { sync.errorMessage = nil }
            } message: { Text(sync.errorMessage ?? "") }
    }
}
