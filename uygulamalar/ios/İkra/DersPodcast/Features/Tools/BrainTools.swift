import SwiftUI
import UIKit

// MARK: - Zihinden işlem

struct MentalMathView: View {
    @AppStorage("tools.math.level") private var level = 1
    @AppStorage("tools.math.best1") private var best1 = 0
    @AppStorage("tools.math.best2") private var best2 = 0
    @AppStorage("tools.math.best3") private var best3 = 0
    @State private var problem: MentalMath.Problem?
    @State private var typed = ""
    @State private var score = 0
    @State private var endsAt: Date?
    @State private var lastScore: Int?
    @State private var newRecord = false
    @State private var rng = SystemRandomNumberGenerator()
    @FocusState private var focused: Bool

    private var best: Int { level <= 1 ? best1 : level == 2 ? best2 : best3 }

    var body: some View {
        ToolScaffold(title: "Zihinden işlem") {
            ScrollView {
                VStack(spacing: 18) {
                    if let problem, let endsAt {
                        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                            let left = max(0, endsAt.timeIntervalSince(timeline.date))
                            ProgressView(value: left, total: 60)
                                .onChange(of: left <= 0) { _, over in if over { finish() } }
                            Text("\(Int(left.rounded(.up))) sn · \(score) doğru").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(problem.text).font(.system(size: 52, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        TextField("Cevap", text: $typed)
                            .keyboardType(.numberPad).focused($focused)
                            .font(.system(size: 36, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .onAppear { focused = true }
                            .onChange(of: typed) { _, value in
                                // Doğru cevap yazılır yazılmaz sıradaki soruya geçilir.
                                if Int(value) == problem.answer { score += 1; next() }
                            }
                        Button("Geç") { next() }.buttonStyle(.bordered)
                    } else {
                        Text("60 saniyede kaç işlem? Doğru cevabı yazdığın an sıradaki soru gelir.").foregroundStyle(.secondary)
                        Picker("Seviye", selection: $level) {
                            Text("Kolay").tag(1)
                            Text("Orta").tag(2)
                            Text("Zor").tag(3)
                        }
                        .modifier(AccessiblePickerStyle())
                        // Önceki seviyenin sonucu yeni seviyenin rekoruyla yan yana kalmasın.
                        .onChange(of: level) { lastScore = nil; newRecord = false }
                        if let lastScore { Text("Bu tur: \(lastScore) doğru").font(.title2.bold()) }
                        if newRecord { RecordLabel() }
                        Text("Bu seviyede en iyi: \(best)").foregroundStyle(.secondary)
                        Button("Başla") { score = 0; newRecord = false; endsAt = Date.now.addingTimeInterval(60); next(); focused = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(20)
            }
        }
    }

    private func next() {
        typed = ""
        problem = MentalMath.problem(level: level, using: &rng)
    }

    private func finish() {
        guard endsAt != nil else { return }
        lastScore = score
        // İlk tur rekor sayılmaz: kırılacak eski bir rekor olmalı.
        newRecord = best > 0 && score > best
        if score > best {
            switch level {
            case ...1: best1 = score
            case 2: best2 = score
            default: best3 = score
            }
        }
        problem = nil; endsAt = nil; focused = false
    }
}

/// Kırılan rekorun etiketi (yalnız renkle değil, simge ve metinle).
private struct RecordLabel: View {
    var body: some View {
        Label("Yeni rekor!", systemImage: "trophy.fill").font(.headline).foregroundStyle(.orange)
    }
}

// MARK: - Hızlı okuma (RSVP)

struct SpeedReadView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tools.rsvp.wpm") private var wpm = 250
    /// Dosyadaki metinde kalınan kelime.
    @AppStorage("tools.rsvp.index") private var savedIndex = 0
    @State private var text = ""
    @State private var words: [String] = []
    /// Dosyadaki (son okunan) metnin kelimeleri: "kaldığın yerden devam" için.
    @State private var savedWords: [String] = []
    /// Ekrandaki metin dosyadakiyle aynı mı (konum yalnız o zaman kaydedilir).
    @State private var tracksFile = false
    @State private var index = 0
    @State private var playing = false
    @State private var runner: Task<Void, Never>?

    private static let sample = "Hızlı okumada göz satır boyunca gezinmez; kelimeler tek tek, aynı noktada belirir. Kırmızı harfe bak, içinden seslendirmemeye çalış. Hızı yavaş yavaş artır: anlamadığın yerde dur, geri sar ve yeniden oku. Düzenli çalışmayla dakikada okuduğun kelime sayısı belirgin biçimde artar."

    /// Son okunan metin: sayfa kapansa da kalınan yerden sürdürülebilsin.
    private static var fileURL: URL { JSONStoreLocation.defaultDirectory.appending(path: "speedread.txt") }

    var body: some View {
        ToolScaffold(title: "Hızlı okuma") {
            ScrollView {
                VStack(spacing: 16) {
                    if words.isEmpty {
                        let hasText = text.contains { !$0.isWhitespace }
                        Text("Metni yapıştır; kelimeler tek tek gösterilir. Göz hareketi azalır, okuma hızlanır.").foregroundStyle(.secondary)
                        if let resume = SpeedReading.resumeIndex(saved: savedIndex, count: savedWords.count) {
                            Button("Kaldığın yerden devam et (%\(SpeedReading.percent(index: resume, count: savedWords.count)))", systemImage: "play.fill") {
                                words = savedWords; index = resume; tracksFile = true; play()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        TextEditor(text: $text).frame(minHeight: 160).padding(6)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        Button("Panodan yapıştır", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? text }.buttonStyle(.bordered)
                        Button("Örnek metin") { text = Self.sample }.buttonStyle(.bordered)
                        Button("Okumaya başla") { start() }
                            .buttonStyle(PrimaryButtonStyle(enabled: hasText)).disabled(!hasText)
                    } else {
                        let word = index < words.count ? words[index] : "Bitti"
                        let finished = index >= words.count
                        pivotText(word).frame(maxWidth: .infinity).frame(height: 130)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                        ProgressView(value: Double(min(index, words.count)), total: Double(words.count))
                        Text("\(min(index + 1, words.count)) / \(words.count) kelime · yaklaşık \((Double(words.count - index) / Double(wpm) * 60).clockText) kaldı")
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Geri", systemImage: "gobackward.10") { index = max(0, index - 10) }.buttonStyle(.bordered)
                            Button(playing ? "Duraklat" : finished ? "Baştan oku" : "Devam",
                                   systemImage: playing ? "pause.fill" : finished ? "arrow.counterclockwise" : "play.fill") { playing ? pause() : play() }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Yeni metin") { pause(); words = [] }.buttonStyle(.bordered)
                    }
                    Stepper("Hız: \(wpm) kelime/dk", value: $wpm, in: 100...900, step: 25)
                }
                .padding(20)
            }
            .onAppear { loadSaved() }
            .onDisappear { pause() }
            // Bildirim merkezi, arama ya da arka plan: kelimeler bakılmadan akmasın.
            .onChange(of: scenePhase) { _, phase in if phase != .active, playing { pause() } }
            // Okurken aşağı çekmek sayfayı kapatmasın ("Kapat" yine çalışır).
            .interactiveDismissDisabled(playing)
        }
    }

    /// Odak harfi kırmızı ve her kelimede aynı yatay konumda; kelimenin üç parçası aynı boyda.
    private func pivotText(_ word: String) -> some View {
        GeometryReader { geo in
            let chars = Array(word), p = min(SpeedReading.pivot(word), max(0, chars.count - 1))
            let size = SpeedReading.fontSize(for: word, width: max(0, geo.size.width - 16))
            HStack(spacing: 0) {
                Text(String(chars.prefix(p))).frame(width: SpeedReading.prefixWidth(), alignment: .trailing)
                Text(chars.isEmpty ? "" : String(chars[p])).foregroundStyle(.red)
                Text(String(chars.dropFirst(p + 1))).frame(maxWidth: .infinity, alignment: .leading)
            }
            // Boy önceden hesaplanır; ölçek yalnız güvenlik payı (her parçaya ayrı uygulandığı için kelimeyi bozar).
            .font(.system(size: size, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func loadSaved() {
        // Yalnız Debug: `-rsvpWord=<kelime>` tek kelimeyi duraklatılmış gösterir (uzun kelime hizası); diske yazılmaz.
        if words.isEmpty, let word = DebugArg.value("rsvpWord"), !word.isEmpty { words = [word]; index = 0; tracksFile = false; return }
        guard savedWords.isEmpty, let saved = try? String(contentsOf: Self.fileURL, encoding: .utf8) else { return }
        savedWords = SpeedReading.words(saved)
    }

    private func start() {
        let fresh = SpeedReading.words(text)
        guard !fresh.isEmpty else { return }
        try? FileManager.default.createDirectory(at: JSONStoreLocation.defaultDirectory, withIntermediateDirectories: true)
        // Dosya yazılamazsa okuma yine başlar; yalnız konum kaydedilmez (eski metnin konumu bozulmasın).
        tracksFile = (try? text.write(to: Self.fileURL, atomically: true, encoding: .utf8)) != nil
        if tracksFile { savedWords = fresh; savedIndex = 0 }
        words = fresh; index = 0
        play()
    }

    private func play() {
        if index >= words.count { index = 0 }
        playing = true
        UIApplication.shared.isIdleTimerDisabled = true
        runner?.cancel()
        runner = Task {
            while !Task.isCancelled, index < words.count {
                try? await Task.sleep(for: .seconds(SpeedReading.seconds(for: words[index], wpm: wpm)))
                if Task.isCancelled { return }
                index += 1
            }
            // Metin bitti: konum sona yazılır, "kaldığın yerden devam" artık önerilmez.
            if !Task.isCancelled { pause() }
        }
    }

    private func pause() {
        runner?.cancel()
        playing = false
        UIApplication.shared.isIdleTimerDisabled = false
        if tracksFile, !words.isEmpty { savedIndex = index }
    }
}

// MARK: - Schulte tablosu

struct SchulteView: View {
    @AppStorage("tools.schulte.size") private var size = 4
    @AppStorage("tools.schulte.best3") private var best3 = 0.0
    @AppStorage("tools.schulte.best4") private var best4 = 0.0
    @AppStorage("tools.schulte.best5") private var best5 = 0.0
    @State private var numbers: [Int] = []
    @State private var next = 1
    @State private var startedAt: Date?
    @State private var result: Double?
    @State private var newRecord = false
    @State private var wrong: Int?

    private var best: Double { size == 3 ? best3 : size == 4 ? best4 : best5 }

    var body: some View {
        ToolScaffold(title: "Schulte tablosu") {
            ScrollView {
                VStack(spacing: 16) {
                    if numbers.isEmpty {
                        Text("Gözünü ortadaki kareden ayırmadan sayıları 1'den başlayarak sırayla bul. Dikkat ve çevresel görüşü geliştirir.").foregroundStyle(.secondary)
                        Picker("Boyut", selection: $size) {
                            Text("3×3").tag(3)
                            Text("4×4").tag(4)
                            Text("5×5").tag(5)
                        }
                        .modifier(AccessiblePickerStyle())
                        // Süre, oynanan boyuta aittir: boyut değişince başka boyutun rekoruyla yan yana kalmasın.
                        .onChange(of: size) { result = nil; newRecord = false }
                        if let result { Text("Süre: \(Schulte.timeText(result)) sn").font(.title2.bold()) }
                        if newRecord { RecordLabel() }
                        if best > 0 { Text("En iyi: \(Schulte.timeText(best)) sn").foregroundStyle(.secondary) }
                        Button("Başla") { numbers = Array(1...(size * size)).shuffled(); next = 1; startedAt = .now; result = nil; newRecord = false }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Text("Sıradaki: \(next)").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: size), spacing: 6) {
                            ForEach(numbers, id: \.self) { n in
                                Button { tap(n) } label: {
                                    Text("\(n)").font(.system(.title2, design: .rounded).bold()).minimumScaleFactor(0.5)
                                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                        .background(wrong == n ? Color.red.opacity(0.35) : n < next ? Color.green.opacity(0.2) : Color.gray.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Vazgeç") { numbers = [] }.buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
        }
    }

    private func tap(_ n: Int) {
        guard n == next else {
            wrong = n
            Task { try? await Task.sleep(for: .milliseconds(300)); wrong = nil }
            return
        }
        next += 1
        guard next > size * size else { return }
        let seconds = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        result = seconds
        // İlk tur rekor sayılmaz: kırılacak eski bir süre olmalı.
        newRecord = best > 0 && seconds < best
        if best == 0 || seconds < best {
            switch size {
            case 3: best3 = seconds
            case 4: best4 = seconds
            default: best5 = seconds
            }
        }
        numbers = []
    }
}

// MARK: - Sayı hafızası

struct DigitSpanView: View {
    @AppStorage("tools.digits.best") private var best = 0
    @State private var sequence: [Int] = []
    @State private var showing: Int?
    @State private var typed = ""
    @State private var length = 4
    @State private var passed = 0
    @State private var lives = 2
    @State private var phase = Phase.idle
    @State private var lastCorrect = false
    /// Gösterim ve "doğru" beklemesi: sayfa kapanınca iptal edilir.
    @State private var runner: Task<Void, Never>?
    @State private var rng = SystemRandomNumberGenerator()
    @FocusState private var focused: Bool

    enum Phase { case idle, showing, answering, feedback, over }

    var body: some View {
        ToolScaffold(title: "Sayı hafızası") {
            ScrollView {
                VStack(spacing: 18) {
                    switch phase {
                    case .idle, .over:
                        Text("Rakamlar tek tek gösterilir; bitince aynı sırayla yaz. Her doğruda dizi bir uzar, iki hatada oyun biter.").foregroundStyle(.secondary)
                        if phase == .over { Text(passed > 0 ? "Ulaştığın uzunluk: \(passed)" : "Bu sefer olmadı; tekrar dene.").font(.title2.bold()) }
                        Text("En iyi: \(best) rakam").foregroundStyle(.secondary)
                        Button("Başla") { length = 4; passed = 0; lives = 2; round() }.buttonStyle(PrimaryButtonStyle())
                    case .showing:
                        Text("\(length) rakam · ezberle").font(.subheadline).foregroundStyle(.secondary)
                        Text(showing.map(String.init) ?? " ").font(.system(size: 96, weight: .bold, design: .rounded)).frame(height: 130)
                    case .answering:
                        Text("Diziyi yaz").font(.headline)
                        TextField("Rakamlar", text: $typed)
                            .keyboardType(.numberPad).focused($focused)
                            .font(.system(size: 32, weight: .semibold, design: .monospaced)).multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .onAppear { focused = true }
                        Button("Kontrol et") { check() }.buttonStyle(PrimaryButtonStyle(enabled: !typed.isEmpty)).disabled(typed.isEmpty)
                        Text("Kalan hak: \(lives)").font(.footnote).foregroundStyle(.secondary)
                    case .feedback:
                        feedback
                    }
                }
                .padding(20)
            }
            .onAppear { openDebugFeedback() }
            .onDisappear { runner?.cancel() }
        }
    }

    @ViewBuilder private var feedback: some View {
        if lastCorrect {
            Label("Doğru!", systemImage: "checkmark.circle.fill").font(.title.bold()).foregroundStyle(.green)
            Text("Sıradaki: \(length) rakam").foregroundStyle(.secondary)
        } else {
            Label("Yanlış", systemImage: "xmark.circle.fill").font(.title.bold()).foregroundStyle(.red)
            digitLine("Doğrusu", sequence)
            digitLine("Senin yazdığın", typed.compactMap { $0.wholeNumberValue })
            if let at = DigitSpan.firstMismatch(typed: typed, expected: sequence) {
                Text("İlk fark: \(at + 1). rakam").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Kalan hak: \(lives)").font(.footnote).foregroundStyle(.secondary)
            Button(lives > 0 ? "Devam" : "Sonucu gör") { if lives > 0 { round() } else { phase = .over } }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func digitLine(_ title: String, _ digits: [Int]) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(digits.map { "\($0)" }.joined(separator: " "))
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func round() {
        sequence = DigitSpan.sequence(length: length, using: &rng)
        typed = ""
        phase = .showing
        runner?.cancel()
        runner = Task {
            for digit in sequence {
                showing = digit
                try? await Task.sleep(for: .milliseconds(800))
                showing = nil
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            phase = .answering
            focused = true
        }
    }

    private func check() {
        focused = false
        lastCorrect = DigitSpan.firstMismatch(typed: typed, expected: sequence) == nil
        if lastCorrect {
            best = max(best, length)
            passed = length
            length += 1
        } else {
            lives -= 1
        }
        phase = .feedback
        guard lastCorrect else { return }
        // Doğruda kısa bir onaydan sonra sıradaki dizi kendiliğinden gelir; yanlışta "Devam" beklenir.
        runner?.cancel()
        runner = Task {
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { return }
            round()
        }
    }

    /// Yalnız Debug: `-digitFeedback=wrong|right` geri bildirim ekranını doğrudan açar.
    private func openDebugFeedback() {
        guard phase == .idle, let demo = DebugArg.value("digitFeedback") else { return }
        lastCorrect = demo == "right"
        sequence = [4, 7, 1, 9]
        typed = lastCorrect ? "4719" : "4791"
        if lastCorrect { length = 5 } else { lives = 1 }
        phase = .feedback
    }
}

// MARK: - Nefes egzersizi

struct BreathingView: View {
    @State private var pattern = Pattern.box
    @State private var label = "Hazır"
    @State private var scale = 0.5
    @State private var cycles = 0
    @State private var runner: Task<Void, Never>?

    enum Pattern: String, CaseIterable, Identifiable {
        case box = "Kutu 4-4-4-4", relax = "4-7-8", calm = "Sakin 4-6"
        var id: String { rawValue }

        /// (ad, saniye, hedef ölçek)
        var steps: [(String, Double, Double)] {
            switch self {
            case .box: [("Nefes al", 4, 1), ("Tut", 4, 1), ("Nefes ver", 4, 0.5), ("Bekle", 4, 0.5)]
            case .relax: [("Nefes al", 4, 1), ("Tut", 7, 1), ("Nefes ver", 8, 0.5)]
            case .calm: [("Nefes al", 4, 1), ("Nefes ver", 6, 0.5)]
            }
        }
    }

    var body: some View {
        ToolScaffold(title: "Nefes egzersizi") {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Sınav öncesi ya da odaklanamadığında 2–3 dakika yeter.").foregroundStyle(.secondary)
                    ZStack {
                        Circle().fill(Theme.gradient).opacity(0.25)
                        Circle().fill(Theme.gradient).scaleEffect(scale)
                        Text(label).font(.title2.bold()).foregroundStyle(.white).shadow(radius: 4)
                    }
                    .frame(width: 230, height: 230)
                    Text("\(cycles) tur").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if runner == nil {
                        Picker("Düzen", selection: $pattern) { ForEach(Pattern.allCases) { Text($0.rawValue).tag($0) } }
                        Button("Başla") { start() }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Bitir") { stop() }.buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .onDisappear { stop() }
        }
    }

    private func start() {
        cycles = 0
        UIApplication.shared.isIdleTimerDisabled = true
        let steps = pattern.steps
        runner = Task {
            let haptic = UIImpactFeedbackGenerator(style: .soft)
            while !Task.isCancelled {
                for (name, seconds, target) in steps {
                    label = name
                    haptic.impactOccurred()
                    withAnimation(.easeInOut(duration: seconds)) { scale = target }
                    try? await Task.sleep(for: .seconds(seconds))
                    if Task.isCancelled { return }
                }
                cycles += 1
            }
        }
    }

    private func stop() {
        runner?.cancel()
        runner = nil
        UIApplication.shared.isIdleTimerDisabled = false
        label = "Hazır"
        withAnimation(.easeOut(duration: 0.4)) { scale = 0.5 }
    }
}
