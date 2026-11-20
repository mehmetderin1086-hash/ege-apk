import Foundation
import Testing
@testable import Ikra

// Araç kutusu (Çalış sekmesi ek araçları): saf mantık ve dosya deposu.

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

@Suite struct ToolboxTests {
    @Test func netCalculation() {
        #expect(ExamMath.net(correct: 30, wrong: 8, penalty: 4) == 28)
        #expect(ExamMath.net(correct: 30, wrong: 9, penalty: 3) == 27)
        #expect(ExamMath.net(correct: 30, wrong: 9, penalty: 0) == 30)
        let exam = MockExam(penalty: 4, rows: [.init(name: "Türkçe", correct: 30, wrong: 4), .init(name: "Mat", correct: 20, wrong: 2)])
        #expect(exam.net == 48.5)
    }

    @Test func gradeAverageAndNeeded() {
        #expect(GradeMath.average([]) == nil)
        #expect(GradeMath.average([(60, 40), (80, 60)]) == 72)
        // Vize 50 (%40) → 70 ortalama için finalden (%60) 83,33 gerekir.
        let needed = GradeMath.needed([(50, 40)], target: 70)
        #expect(abs((needed ?? 0) - 83.3333) < 0.001)
        #expect(GradeMath.needed([(50, 40), (90, 60)], target: 70) == nil)
        #expect((GradeMath.needed([(100, 80)], target: 60) ?? 1) < 0)
    }

    @Test func streaks() {
        let days: Set = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-09-20", "2026-09-28", "2026-09-29", "2026-09-30"]
        #expect(Streak.current(days: days, today: day(2026, 10, 3), calendar: utc) == 6)
        // Bugün işaretli değilse dünden sayılır; iki gün boşsa seri biter.
        #expect(Streak.current(days: days, today: day(2026, 10, 4), calendar: utc) == 6)
        #expect(Streak.current(days: days, today: day(2026, 10, 5), calendar: utc) == 0)
        #expect(Streak.best(days: days, calendar: utc) == 6)
        #expect(Streak.best(days: [], calendar: utc) == 0)
        // Ay ve yıl sınırı.
        #expect(Streak.best(days: ["2025-12-31", "2026-01-01", "2026-01-02"], calendar: utc) == 3)
    }

    @Test func dayKeyRoundTrip() {
        let key = DayKey.key(day(2026, 3, 7), calendar: utc)
        #expect(key == "2026-03-07")
        #expect(DayKey.date(key, calendar: utc).map { DayKey.key($0, calendar: utc) } == key)
        #expect(DayKey.date("bozuk") == nil)
    }

    @Test func revisionSchedule() {
        let start = day(2026, 10, 1)
        // Her tekrar zamanında yapılırsa: 1, 3, 7, 14, 30. günler.
        var anchor = start
        var offsets: [Int] = []
        for step in 0..<5 {
            let due = RevisionPlan.nextDue(anchor: anchor, doneSteps: step, calendar: utc)!
            offsets.append(utc.dateComponents([.day], from: utc.startOfDay(for: start), to: due).day!)
            anchor = due
        }
        #expect(offsets == [1, 3, 7, 14, 30])
        #expect(RevisionPlan.nextDue(anchor: start, doneSteps: 5, calendar: utc) == nil)
        let due = RevisionPlan.nextDue(anchor: start, doneSteps: 0, calendar: utc)
        #expect(!RevisionPlan.isDue(due, today: day(2026, 10, 1), calendar: utc))
        #expect(RevisionPlan.isDue(due, today: day(2026, 10, 2), calendar: utc))
        #expect(RevisionPlan.isDue(due, today: day(2026, 10, 9), calendar: utc))
        #expect(!RevisionPlan.isDue(nil))
    }

    @Test func mentalMathProblemsAreConsistent() {
        var rng = SeededRNG(state: 42)
        for level in 1...3 {
            for _ in 0..<300 {
                let p = MentalMath.problem(level: level, using: &rng)
                #expect(p.answer >= 0)
                let parts = p.text.split(separator: " ")
                let a = Int(parts[0])!, b = Int(parts[2])!
                switch parts[1] {
                case "+": #expect(a + b == p.answer)
                case "−": #expect(a - b == p.answer)
                case "×": #expect(a * b == p.answer)
                case "÷": #expect(b != 0 && a / b == p.answer && a % b == 0)
                default: Issue.record("Bilinmeyen işlem: \(p.text)")
                }
                if level == 1 { #expect(parts[1] == "+" || parts[1] == "−") }
            }
        }
    }

    @Test func answerMatching() {
        #expect(AnswerMatch.normalize("  Hücre  ZARI!  ") == "hücre zarı")
        #expect(AnswerMatch.normalize("IŞIK") == "ışık")
        #expect(AnswerMatch.verdict(typed: "Mitokondri.", expected: "mitokondri") == .exact)
        #expect(AnswerMatch.verdict(typed: "mitokondiri", expected: "mitokondri") == .close)
        #expect(AnswerMatch.verdict(typed: "ribozom", expected: "mitokondri") == .wrong)
        #expect(AnswerMatch.verdict(typed: "", expected: "mitokondri") == .wrong)
        #expect(AnswerMatch.verdict(typed: "enerji üretir", expected: "Hücrede enerji üretir (ATP sentezi)") == .close)
        #expect(AnswerMatch.similarity("", "") == 1)
        #expect(AnswerMatch.similarity("abc", "") == 0)
    }

    @Test func calculator() {
        #expect(Calculator.evaluate("2+3×4") == 14)
        #expect(Calculator.evaluate("(2+3)×4") == 20)
        #expect(Calculator.evaluate("10 − 4 − 3") == 3)
        #expect(Calculator.evaluate("2^3^2") == 512)
        #expect(Calculator.evaluate("-2^2") == -4)
        #expect(Calculator.evaluate("1,5×2") == 3)
        #expect(Calculator.evaluate("√16+5!") == 124)
        #expect(Calculator.evaluate("50%") == 0.5)
        #expect(abs((Calculator.evaluate("sin(30)") ?? 0) - 0.5) < 1e-12)
        #expect(abs((Calculator.evaluate("sin(π÷2)", degrees: false) ?? 0) - 1) < 1e-12)
        #expect(abs((Calculator.evaluate("ln(e)") ?? 0) - 1) < 1e-12)
        #expect(Calculator.evaluate("log(1000)") == 3)
        for bad in ["", "2+", "1÷0", "(2+3", "2)", "abc(2)", "√(0-4)", "ln(0)", "2..3", "sin"] {
            #expect(Calculator.evaluate(bad) == nil, "\(bad)")
        }
        #expect(Calculator.format(0.1 + 0.2) == "0,3")
        #expect(Calculator.format(14) == "14")
        // Üstel gösterim yok: sonuç yeniden ifadeye yazılıp okunabilmeli.
        #expect(Calculator.format(1e10) == "10000000000")
        #expect(Calculator.format(1e-5) == "0,00001")
        #expect(Calculator.format(-5) == "-5")
        #expect(Calculator.format(1e20) == "100000000000000000000")
        for value in [1e10, 1e-5, 123.456, -0.25, 1e20] {
            #expect(Calculator.evaluate(Calculator.format(value)) == value, "\(value)")
        }
        #expect(Calculator.evaluate("(-5)^2") == 25)
        // Derece modunda 90'ın katları: gürültü yerine 0, tan(90) tanımsız.
        #expect(Calculator.format(Calculator.evaluate("sin(180)") ?? 1) == "0")
        #expect(Calculator.format(Calculator.evaluate("cos(90)") ?? 1) == "0")
        #expect(Calculator.evaluate("tan(90)") == nil)
        #expect(abs((Calculator.evaluate("tan(45)") ?? 0) - 1) < 1e-12)
    }

    @Test func speedReading() {
        #expect(SpeedReading.words("  Bir  iki\nüç. ") == ["Bir", "iki", "üç."])
        #expect(SpeedReading.pivot("a") == 0)
        #expect(SpeedReading.pivot("kitap") == 1)
        #expect(SpeedReading.pivot("mitokondri") == 3)
        #expect(SpeedReading.seconds(for: "ev", wpm: 300) == 0.2)
        #expect(SpeedReading.seconds(for: "ev.", wpm: 300) > SpeedReading.seconds(for: "ev,", wpm: 300))
        #expect(SpeedReading.seconds(for: "ev,", wpm: 300) > 0.2)
    }

    @Test func cardImport() {
        let text = "mitokondri ; enerji santrali\nDNA\tkalıtım maddesi\n\nboş satır yok\nH2O = su\nribozom - protein sentezi\n ; yalnız arka\nSaat: 10:30"
        let cards = CardImport.parse(text)
        #expect(cards.map(\.front) == ["mitokondri", "DNA", "H2O", "ribozom", "Saat"])
        #expect(cards.map(\.back) == ["enerji santrali", "kalıtım maddesi", "su", "protein sentezi", "10:30"])
    }

    @Test func heatMap() {
        #expect([0, 5, 20, 60, 200].map { HeatMap.level(minutes: $0) } == [0, 1, 2, 3, 4])
        // 2026-10-05 Pazartesi: son sütunda yalnız ilk gün dolu.
        let grid = HeatMap.grid(weeks: 4, today: day(2026, 10, 5), calendar: utc)
        #expect(grid.count == 4 && grid.allSatisfy { $0.count == 7 })
        #expect(grid[3].compactMap { $0 }.count == 1)
        #expect(grid[0][0].map { DayKey.key($0, calendar: utc) } == "2026-09-14")
        #expect(grid[2][6].map { DayKey.key($0, calendar: utc) } == "2026-10-04")
    }

    @Test func badges() {
        let none = Badges.all(BadgeStats())
        #expect(none.count == 30 && none.allSatisfy { !$0.earned })
        #expect(Set(none.map(\.id)).count == 30)
        let some = Badges.all(BadgeStats(focusMinutes: 700, bestStreak: 3, episodes: 2, videoLessons: 1))
        #expect(some.filter(\.earned).map(\.id).sorted() == ["episodes-0", "focus-0", "focus-1", "streak-0"])
        #expect(some.first { $0.id == "focus-2" }?.progress == 700.0 / 3000)
    }

    @Test func digitSpan() {
        var rng = SeededRNG(state: 7)
        for length in 1...12 {
            let digits = DigitSpan.sequence(length: length, using: &rng)
            #expect(digits.count == length && digits.allSatisfy { (0...9).contains($0) })
            #expect(zip(digits, digits.dropFirst()).allSatisfy { $0 != $1 })
        }
    }

    @Test func periodicTable() {
        let all = ChemElement.all
        #expect(all.count == 118)
        #expect(Set(all.map(\.symbol)).count == 118 && Set(all.map(\.name)).count == 118)
        func element(_ symbol: String) -> ChemElement { all.first { $0.symbol == symbol }! }
        #expect(element("Fe").number == 26 && element("Fe").group == 8 && element("Fe").period == 4)
        #expect(element("Au").number == 79 && element("Au").group == 11 && element("Au").period == 6)
        #expect(element("He").group == 18 && element("B").group == 13 && element("Og").group == 18 && element("Rf").group == 4)
        #expect(element("U").group == nil && element("U").category == .actinide)
        #expect(element("Cl").category == .halogen && element("Na").category == .alkali && element("Ne").category == .nobleGas)
        // Tabloda her (periyot, grup) hücresinde en çok bir element.
        let cells = all.compactMap { e in e.group.map { "\(e.period)-\($0)" } }
        #expect(Set(cells).count == cells.count && cells.count == 118 - 30)
        #expect(all.allSatisfy { Double($0.mass) != nil })
    }

    @Test @MainActor func jsonStorePersists() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "toolbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStore<Habit>("habits", directory: dir)
        #expect(store.items.isEmpty)
        store.items.append(Habit(name: "Kitap", days: ["2026-10-05"]))
        store.items[0].days.insert("2026-10-06")
        let reloaded = JSONStore<Habit>("habits", directory: dir)
        #expect(reloaded.items.count == 1 && reloaded.items[0].name == "Kitap" && reloaded.items[0].days.count == 2)
        // Bozuk dosya çökertmez: boş başlar.
        try Data("bozuk".utf8).write(to: dir.appending(path: "goals.json"))
        let broken = JSONStore<StudyGoal>("goals", directory: dir)
        #expect(broken.items.isEmpty)
        // Okunamayan dosya ezilmez: kenara alınır; yeni kayıt temiz dosyaya yazılır.
        broken.items.append(StudyGoal(title: "Yeni"))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = try #require(names.first { $0.hasPrefix("goals.bozuk-") })
        #expect(try Data(contentsOf: dir.appending(path: aside)) == Data("bozuk".utf8))
        #expect(JSONStore<StudyGoal>("goals", directory: dir).items.map(\.title) == ["Yeni"])
    }

    @Test func toolsRestoreDoesNotOverwrite() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "toolbox-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appending(path: "yedek"), target = base.appending(path: "cihaz")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("yedek-a".utf8).write(to: source.appending(path: "habits.json"))
        try Data("yedek-b".utf8).write(to: source.appending(path: "goals.json"))
        try Data("çizim".utf8).write(to: source.appending(path: "whiteboard.drawing"))
        try Data("başka".utf8).write(to: source.appending(path: "notlar.txt"))
        try Data("cihaz-a".utf8).write(to: target.appending(path: "habits.json"))
        #expect(JSONStoreLocation.restore(from: source, to: target) == 2)
        #expect(try Data(contentsOf: target.appending(path: "habits.json")) == Data("cihaz-a".utf8))
        #expect(try Data(contentsOf: target.appending(path: "goals.json")) == Data("yedek-b".utf8))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "whiteboard.drawing").path))
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "notlar.txt").path))
        // Yedekte Tools klasörü yoksa (eski yedek) sessizce 0.
        #expect(JSONStoreLocation.restore(from: base.appending(path: "yok"), to: target) == 0)
    }

    @Test func backupCoversToolbox() {
        #expect(BackupManifest.preferencePrefixes.contains("tools."))
        #expect(MacBackup.safeRelativePath("Tools/habits.json") == "Tools/habits.json")
        #expect(MacBackup.safeRelativePath("Tools/../habits.json") == nil)
    }

    @Test func revisionTopicRoundTrips() throws {
        let data = try JSONEncoder().encode([RevisionTopic(title: "Hücre", course: "Biyoloji", anchor: day(2026, 10, 1), doneSteps: 2)])
        let back = try JSONDecoder().decode([RevisionTopic].self, from: data)
        #expect(back.first?.title == "Hücre" && back.first?.doneSteps == 2)
    }
}
