import AVFoundation
import Observation
import SwiftData
import SwiftUI
import UserNotifications

/// Odak (Pomodoro) zamanlayıcısı. Ekran kapansa da bitiş zamanına göre çalışır; biten aşamada bildirim.
/// Süren aşama `store`'a yazılır: uygulama kapanıp açılınca süresi dolmamış oturum kaldığı yerden sürer.
@Observable
final class FocusTimer {
    static let shared = FocusTimer(store: .standard)

    enum Phase: String { case idle, focus, shortBreak, longBreak }
    struct Preset: Identifiable, Hashable { var id: String { name }; var name: String; var focus: Int; var brk: Int }
    static let presets = [Preset(name: "25 / 5", focus: 25, brk: 5), Preset(name: "50 / 10", focus: 50, brk: 10), Preset(name: "90 / 15", focus: 90, brk: 15)]

    /// Süren aşamanın kalıcı kaydı.
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var phase: String
        var startedAt: Date
        var endsAt: Date
        var presetName: String
        var focus: Int
        var brk: Int
        var courseID: UUID?
        var episodeID: UUID?
        var completedFocus: Int
    }

    static let storeKey = "focusTimer.activeSnapshot"
    /// Uygulama askıdayken bitişi bundan eski kalan oturumda "Süre doldu" ekranı beklenmez; kaydı kendiliğinden yazılır
    /// ve uzun mola sırası baştan başlar.
    nonisolated static let staleAfter: TimeInterval = 12 * 3600

    private(set) var phase = Phase.idle
    private(set) var endsAt: Date?
    private(set) var startedAt: Date?
    private(set) var completedFocus = 0
    var preset = Preset(name: "25 / 5", focus: 25, brk: 5) { didSet { persist() } }
    var courseID: UUID? { didSet { persist() } }
    var episodeID: UUID? { didSet { persist() } }
    /// Arka plan sesi yalnızca odak sırasında çalar.
    var ambient = Ambient.off { didSet { if phase == .focus, remaining > 0 { noise.set(ambient) } } }

    private let noise = NoiseEngine()
    private let store: UserDefaults?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    /// Uygulama kapalıyken süresi dolmuş oturum: `reconcile` kaydını yazana kadar bekler.
    @ObservationIgnored private var stale: Snapshot?

    /// `store` nil ise (testler) hiçbir şey kalıcı yazılmaz.
    init(store: UserDefaults? = nil, now: Date = .now) {
        self.store = store
        restore(now: now)
    }

    var remaining: TimeInterval { max(0, (endsAt ?? .now).timeIntervalSinceNow) }
    var isRunning: Bool { phase != .idle }

    func start(_ p: Phase = .focus) {
        let minutes = Self.minutes(for: p, preset: preset)
        let breakMinutes = Self.minutes(for: completedFocus % 4 == 3 ? .longBreak : .shortBreak, preset: preset)
        // Yalnız Debug: `-focusSeconds=20` ile her aşama 20 sn sürer (süre dolma ve yeniden açılış akışını denemek için).
        let length = DebugArg.value("focusSeconds").flatMap { Double($0) }.map { max(1, $0) } ?? Double(minutes) * 60
        let ends = Date.now.addingTimeInterval(length)
        phase = p
        startedAt = .now
        endsAt = ends
        persist()
        scheduleNotification(ending: p, breakMinutes: breakMinutes, endsAt: ends)
        scheduleEnd(at: ends)
        if p == .focus { noise.set(ambient) } else { noise.set(.off) }
    }

    /// Aşama bittiğinde (ya da kullanıcı bitirdiğinde) oturumu kaydeder ve sonraki aşamaya hazırlar.
    func finish(context: ModelContext, completed: Bool) {
        guard let snapshot else { return }
        if phase == .focus {
            Self.write(snapshot, completed: completed, now: .now, context: context)
            if completed { completedFocus += 1 }
        }
        stop()
    }

    func stop() {
        phase = .idle
        endsAt = nil
        startedAt = nil
        endTask?.cancel()
        endTask = nil
        store?.removeObject(forKey: Self.storeKey)
        noise.set(.off)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus-phase"])
    }

    /// Sıradaki aşama: 4 odaktan sonra uzun mola.
    var nextPhase: Phase { phase == .focus ? (completedFocus % 4 == 3 ? .longBreak : .shortBreak) : .focus }

    /// Uygulama kapalıyken süresi dolan oturum (`stale`) tamamlanmış sayılıp kendiliğinden yazılır; zamanlayıcı boşta kalır.
    /// Uygulama açıkken (ya da askıdayken) dolan sürede "Süre doldu" ekranı kalır, kaydı düğmeler yazar; bitiş
    /// `staleAfter`'dan eskiyse o da kendiliğinden yazılır.
    func reconcile(context: ModelContext, now: Date = .now) {
        if let old = stale {
            stale = nil
            Self.write(old, completed: true, now: now, context: context)
            // Bu arada yeni oturum başladıysa anahtar ve sayaç onundur.
            if !isRunning {
                store?.removeObject(forKey: Self.storeKey)
                // Kısa bir kapanış uzun mola sırasını bozmasın; çok eski oturumdan sonra sıra baştan başlar.
                if !Self.isStale(old, now: now) { completedFocus = old.completedFocus + (old.phase == Phase.focus.rawValue ? 1 : 0) }
            }
        }
        if let snapshot, Self.isStale(snapshot, now: now) {
            finish(context: context, completed: true)
            completedFocus = 0
        }
    }

    /// Zamanlayıcıyı (ve ses motorunu) boşuna kurmadan: yalnız kayıtlı bir oturum varsa `reconcile` çağırır.
    static func reconcileSaved(context: ModelContext) {
        guard UserDefaults.standard.data(forKey: storeKey) != nil else { return }
        shared.reconcile(context: context)
    }

    // MARK: - Saf yardımcılar

    static func minutes(for phase: Phase, preset: Preset) -> Int {
        switch phase {
        case .focus: preset.focus
        case .longBreak: preset.brk * 3
        case .shortBreak, .idle: preset.brk
        }
    }

    /// Kaydedilen aşamada çalışılan süre (aşamanın uzunluğunu aşmaz: uygulama kapalıyken geçen saatler sayılmaz)
    /// ve sürenin dolup dolmadığı.
    nonisolated static func recovered(_ s: Snapshot, now: Date) -> (seconds: Double, completed: Bool) {
        let length = max(0, s.endsAt.timeIntervalSince(s.startedAt))
        return (min(max(0, now.timeIntervalSince(s.startedAt)), length), now >= s.endsAt)
    }

    nonisolated static func isStale(_ s: Snapshot, now: Date) -> Bool { now.timeIntervalSince(s.endsAt) > staleAfter }

    /// Aşama bitince gösterilecek bildirim. Mola süresi düzenden gelir (5, 10, 15; uzun molada üç katı).
    static func notificationText(ending phase: Phase, breakMinutes: Int) -> (title: String, body: String) {
        switch phase {
        case .focus: ("Odak bitti — mola zamanı", "Kalk, su iç, \(breakMinutes) dakika uzaklaş.")
        case .idle, .shortBreak, .longBreak: ("Mola bitti — devam", "Yeni bir odak oturumu başlat.")
        }
    }

    // MARK: - Kalıcılık

    private var snapshot: Snapshot? {
        guard phase != .idle, let startedAt, let endsAt else { return nil }
        return Snapshot(phase: phase.rawValue, startedAt: startedAt, endsAt: endsAt, presetName: preset.name, focus: preset.focus,
                        brk: preset.brk, courseID: courseID, episodeID: episodeID, completedFocus: completedFocus)
    }

    /// Yalnız süren aşamayı yazar; anahtarı `stop` siler.
    private func persist() {
        guard let store, let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        store.set(data, forKey: Self.storeKey)
    }

    private func restore(now: Date) {
        guard let data = store?.data(forKey: Self.storeKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data),
              let saved = Phase(rawValue: s.phase), saved != .idle else { return }
        // Uygulama kapalıyken süresi dolmuş oturum çalışıyor gibi geri gelmez (video dersi kancası açılışta kendiliğinden
        // mola/odak başlatmasın, "Odakla izle" eski oturuma bağlanmasın): kaydını `reconcile` yazar.
        if s.endsAt <= now { stale = s; return }
        preset = Preset(name: s.presetName, focus: s.focus, brk: s.brk)
        courseID = s.courseID
        episodeID = s.episodeID
        completedFocus = s.completedFocus
        startedAt = s.startedAt
        endsAt = s.endsAt
        phase = saved   // en son: yukarıdaki `didSet`'ler yarım durumu geri yazmasın
        scheduleEnd(at: s.endsAt)
    }

    private static func write(_ s: Snapshot, completed: Bool, now: Date, context: ModelContext) {
        guard s.phase == Phase.focus.rawValue else { return }
        context.insert(StudySession(startedAt: s.startedAt, seconds: recovered(s, now: now).seconds, courseID: s.courseID,
                                    episodeID: s.episodeID, kind: "focus", completed: completed))
        try? context.save()
    }

    /// Süre dolunca ortam sesi kendiliğinden susar (kullanıcı ekrana dönmese de).
    private func scheduleEnd(at ends: Date) {
        endTask?.cancel()
        endTask = nil
        let wait = ends.timeIntervalSinceNow
        guard wait > 0 else { return }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.endsAt == ends else { return }
            self.noise.set(.off)
        }
    }

    private func scheduleNotification(ending phase: Phase, breakMinutes: Int, endsAt token: Date) {
        let text = Self.notificationText(ending: phase, breakMinutes: breakMinutes)
        Task {
            let center = UNUserNotificationCenter.current()
            _ = await NotificationGate.request(center, options: [.alert, .sound])
            // İzin beklenirken oturum bitirildiyse ya da yeni aşama başladıysa bu bildirim eskidir.
            guard self.endsAt == token else { return }
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.userInfo = ["route": "focus"]
            try? await center.add(UNNotificationRequest(identifier: "focus-phase", content: content,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, token.timeIntervalSinceNow), repeats: false)))
            // Ekleme sürerken durdurulduysa geride bildirim kalmasın.
            if self.endsAt == nil { center.removePendingNotificationRequests(withIdentifiers: ["focus-phase"]) }
        }
    }
}

/// Arka plan sesi: dosya yok, cihazda üretilir (beyaz gürültü, "yağmur" = kahverengi gürültü, "kafe" = bantlı gürültü).
enum Ambient: String, CaseIterable, Identifiable {
    case off, white, rain, cafe
    var id: String { rawValue }
    var title: String {
        switch self { case .off: "Sessiz"; case .white: "Beyaz gürültü"; case .rain: "Yağmur"; case .cafe: "Kafe" }
    }
}

/// Podcast ile karışabilir (ambient kanalı ayrı AVAudioEngine; oturum .playback/mixWithOthers).
final class NoiseEngine {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var current = Ambient.off
    private let state = NoiseState()

    func set(_ ambient: Ambient) {
        // Motor başka bir ses oturumu değişikliğiyle durmuş olabilir: aynı seçimde de yeniden başlat.
        guard ambient != current || (ambient != .off && !engine.isRunning) else { return }
        current = ambient
        state.mode = ambient
        if ambient == .off { engine.stop(); return }
        if node == nil {
            let format = engine.outputNode.outputFormat(forBus: 0)
            let source = Self.makeSource(state: state, format: format)
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.25
            node = source
        }
        // Oturum kategorisine dokunulmaz (oynatıcının .playback ayarı ve kilit ekranı kontrolleri korunur).
        try? engine.start()
    }

    /// Render bloğu ses iş parçacığında çağrılır: MainActor'dan bağımsız (nonisolated) kurulmalı.
    nonisolated private static func makeSource(state: NoiseState, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = state.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
    }
}

/// Gürültü üreteci (ses iş parçacığında çalışır; kilit yok, tek yazar).
nonisolated final class NoiseState: @unchecked Sendable {
    var mode = Ambient.off
    private var brown: Float = 0
    private var band: Float = 0
    private var rng = SystemRandomNumberGenerator()

    func next() -> Float {
        let white = Float.random(in: -1...1, using: &rng)
        switch mode {
        case .white: return white * 0.5
        case .rain:   // kahverengi gürültü: yumuşak, yağmur/ırmak hissi
            brown = (brown + 0.02 * white) / 1.02
            return brown * 3.5
        case .cafe:   // orta bant: uğultu
            band = band * 0.97 + white * 0.03
            return (band * 6 + white * 0.08)
        case .off: return 0
        }
    }
}

struct FocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query private var sessions: [StudySession]
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = FocusTimer.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 8) {
                        Text(timer.phase == .idle ? "Hazır" : timer.phase == .focus ? "Odak" : "Mola")
                            .font(.headline).foregroundStyle(.secondary)
                        Text(timeString(timer.isRunning ? timer.remaining : Double(timer.preset.focus) * 60))
                            .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                        if timer.isRunning, timer.remaining == 0 {
                            Text("Süre doldu").font(.subheadline).foregroundStyle(.green)
                        }
                    }
                }
                .padding(.top, 20)

                if !timer.isRunning {
                    Picker("Düzen", selection: $timer.preset) {
                        ForEach(FocusTimer.presets) { Text($0.name).tag($0) }
                    }
                    .modifier(AccessiblePickerStyle())
                    if !courses.isEmpty {
                        Picker("Ders", selection: $timer.courseID) {
                            Text("Ders seçilmedi").tag(UUID?.none)
                            ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                // Açılır menü: segmentli seçicide "Beyaz gürültü" dar ekranda kesiliyordu.
                HStack {
                    Label("Arka plan sesi", systemImage: "speaker.wave.2").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("Arka plan sesi", selection: $timer.ambient) {
                        ForEach(Ambient.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 14) {
                    if timer.isRunning {
                        Button("Bitir", role: .destructive) { timer.finish(context: context, completed: timer.remaining == 0) }
                            .buttonStyle(.bordered)
                        Button(timer.remaining == 0 ? (timer.nextPhase == .focus ? "Odağa başla" : "Molaya geç") : "Atla") {
                            let next = timer.nextPhase
                            timer.finish(context: context, completed: timer.remaining == 0)
                            timer.start(next)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Odağa başla") {
                            timer.episodeID = player.episode?.id
                            timer.start(.focus)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                }

                VStack(spacing: 4) {
                    let today = Calendar.current.startOfDay(for: .now)
                    let focused = sessions.filter { $0.kind == "focus" && $0.startedAt >= today }
                    Text("Bugün \(focused.count) oturum · \(Int(focused.reduce(0) { $0 + $1.seconds } / 60)) dakika")
                        .font(.footnote).foregroundStyle(.secondary)
                    if player.episode != nil {
                        Text("Podcast çalmaya devam eder; odak sesi üstüne karışır.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Odak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onAppear { timer.reconcile(context: context) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { timer.reconcile(context: context) } }
            .debugNarrowScreen()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
