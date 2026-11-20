import Foundation
import Testing
@testable import Ikra

// Araç kutusu iyileştirmeleri: soru kronometresi turları, toplu kart içe aktarma, hedef/okuma, deneme, alışkanlık haftası, günlük;
// dalga 2: sayı hafızası, soru takibi, hızlı okuma, hesap makinesi, yazarak tekrar, devamsızlık.

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute)) ?? .distantPast
}

@Suite struct ImproveAraclarTests {
    // MARK: Soru kronometresi

    @Test func lapStats() {
        let stats = LapStats(laps: [30, 90, 120], target: 90)
        #expect(stats.count == 3)
        #expect(stats.average == 80)
        #expect(stats.fastest == 30)
        #expect(stats.slowest == 120)
        // Hedefe eşit süre aşmış sayılmaz.
        #expect(stats.overTarget == 1)
        let empty = LapStats(laps: [], target: 90)
        #expect(empty.count == 0 && empty.average == 0 && empty.fastest == 0 && empty.slowest == 0 && empty.overTarget == 0)
    }

    @Test func lapUndo() {
        let t = date(2026, 10, 6)
        var laps = [40.0, 25.0]
        let previous = LapStats.undoLast(laps: &laps, lastLapAt: t)
        #expect(previous == t.addingTimeInterval(-25))
        #expect(laps == [40])
        var none: [Double] = []
        let nothing = LapStats.undoLast(laps: &none, lastLapAt: t)
        #expect(nothing == nil)
        #expect(none.isEmpty)
        // Oturum bittiyse (son tur anı yok) tur silinmez.
        let finished = LapStats.undoLast(laps: &laps, lastLapAt: nil)
        #expect(finished == nil)
        #expect(laps == [40])
    }

    // MARK: Toplu kart içe aktarma

    @Test func cardImportAnalyze() {
        let text = [
            "#separator:tab", "#html:false", "mitoz\thücre bölünmesi\tbiyoloji etiket", "ATP: enerji - taşıyıcı", "DNA: kalıtım",
            "RNA: protein sentezi", "ayırıcısız satır", "mitoz\thücre bölünmesi",
        ].joined(separator: "\n")
        let outcome = CardImport.analyze(text, existing: [CardImport.key(front: "DNA", back: "Kalıtım")])
        #expect(outcome.cards.map(\.front) == ["mitoz", "ATP", "RNA"])
        // Etiket sütunu arka yüze yapışmaz; liste ":" ile yazıldığı için " - " ayırıcı sayılmaz.
        #expect(outcome.cards.map(\.back) == ["hücre bölünmesi", "enerji - taşıyıcı", "protein sentezi"])
        #expect(outcome.skipped == ["ayırıcısız satır"])
        // Biri destede var (DNA), biri aynı listede iki kez (mitoz).
        #expect(outcome.duplicates == 2)
    }

    @Test func cardImportSeparators() {
        #expect(CardImport.analyze("kelime=anlam").cards == [CardImport.Pair(front: "kelime", back: "anlam")])
        // Tire yalnız iki yanında boşlukla ayırıcıdır.
        let hyphen = CardImport.analyze("iyi-kötü\nsiyah - beyaz")
        #expect(hyphen.cards == [CardImport.Pair(front: "siyah", back: "beyaz")])
        #expect(hyphen.skipped == ["iyi-kötü"])
        // Çoğunluk " - " ise ":" içeren satır da " - "den bölünür.
        let dashed = CardImport.analyze("ATP - enerji: taşıyıcı\nDNA - kalıtım\nRNA - sentez")
        #expect(dashed.cards.first == CardImport.Pair(front: "ATP", back: "enerji: taşıyıcı"))
        // Eşitlikte eski öncelik sırası: ";" ":"den önce.
        #expect(CardImport.analyze("Saat 10:30 ; toplantı").cards == [CardImport.Pair(front: "Saat 10:30", back: "toplantı")])
        // Windows satır sonu ve boş satırlar.
        #expect(CardImport.analyze("a ; b\r\n\r\nc ; d\r\n").cards.map(\.front) == ["a", "c"])
        // "#" ile başlayan ama ":" içermeyen satır başlık sayılmaz.
        #expect(CardImport.analyze("#1 ; ilk soru").cards == [CardImport.Pair(front: "#1", back: "ilk soru")])
        // Yalnız bilinen Anki başlıkları atlanır; "#1: soru" sessizce kaybolmaz, kart olur.
        #expect(CardImport.analyze("#1: Fotosentez nedir?\n#tags column:3\n#Deck:Biyoloji").cards == [CardImport.Pair(front: "#1", back: "Fotosentez nedir?")])
        #expect(CardImport.isHeader("#separator:tab") && CardImport.isHeader("#notetype column:1"))
        #expect(!CardImport.isHeader("#etiket") && !CardImport.isHeader("not: #1") && !CardImport.isHeader("#:"))
        let nothing = CardImport.analyze("  \n\n")
        #expect(nothing.cards.isEmpty && nothing.skipped.isEmpty && nothing.duplicates == 0)
    }

    @Test func cardImportKeyAndParse() {
        #expect(CardImport.key(front: " Hücre   ZARI ", back: "IŞIK") == CardImport.key(front: "hücre zarı", back: "ışık"))
        // Noktalama ve işleç farkı ayrı karttır: yalnız simgeyle ayrışan kart kopya sayılıp sessizce atlanmaz.
        #expect(CardImport.key(front: "2+2", back: "4") != CardImport.key(front: "2×2", back: "4"))
        #expect(CardImport.key(front: "|x|", back: "mutlak değer") != CardImport.key(front: "x", back: "mutlak değer"))
        #expect(CardImport.key(front: "Hücre zarı!", back: "ışık") != CardImport.key(front: "Hücre zarı", back: "ışık"))
        let symbols = CardImport.analyze("2+2 ; 4\n2×2 ; 4\n5 ; eksi beş\n2+2 ; 4", existing: [CardImport.key(front: "-5", back: "eksi beş")])
        #expect(symbols.cards.map(\.front) == ["2+2", "2×2", "5"])
        #expect(symbols.duplicates == 1)
        // Ön ve arka yer değiştirince aynı kart sayılmaz.
        #expect(CardImport.key(front: "a", back: "b c") != CardImport.key(front: "a b", back: "c"))
        // parse eski imzasıyla analyze'ın kartlarını verir.
        let cards = CardImport.parse("mitokondri ; enerji santrali\nokunamayan\nMitokondri ; enerji santrali")
        #expect(cards.count == 1 && cards.first?.front == "mitokondri" && cards.first?.back == "enerji santrali")
    }

    // MARK: Hedefler ve okuma

    @Test func goalStatus() {
        let today = date(2026, 10, 6), yesterday = date(2026, 10, 5)
        #expect(GoalMath.status(done: 5, target: 5, deadline: yesterday, today: today, calendar: utc) == .done)
        #expect(GoalMath.status(done: 7, target: 5, deadline: nil, today: today, calendar: utc) == .done)
        #expect(GoalMath.status(done: 2, target: 10, deadline: date(2026, 10, 10), today: today, calendar: utc) == .remaining(days: 4, perDay: 2))
        // Bölünmeyen eksik yukarı yuvarlanır.
        #expect(GoalMath.status(done: 1, target: 10, deadline: date(2026, 10, 10), today: today, calendar: utc) == .remaining(days: 4, perDay: 3))
        // Son gün bugün: eksiğin tamamı bugüne kalır. Saat farkı günü değiştirmez.
        #expect(GoalMath.status(done: 2, target: 10, deadline: date(2026, 10, 6, hour: 1), today: date(2026, 10, 6, hour: 23), calendar: utc) == .remaining(days: 0, perDay: 8))
        #expect(GoalMath.status(done: 2, target: 10, deadline: yesterday, today: today, calendar: utc) == .overdue(missing: 8))
        #expect(GoalMath.status(done: 2, target: 10, deadline: nil, today: today, calendar: utc) == nil)
    }

    @Test func countFromText() {
        #expect(GoalMath.count(from: "183") == 183)
        #expect(GoalMath.count(from: " 1.250 ") == 1250)
        #expect(GoalMath.count(from: "") == nil)
        #expect(GoalMath.count(from: "abc") == nil)
        // Aşırı uzun giriş taşma yerine kırpılır.
        #expect(GoalMath.count(from: "123456789012345678901234567890") == 123_456_789)
    }

    @Test func readingSetPage() {
        var book = ReadingBook(totalPages: 200, currentPage: 30)
        book.setPage(47, dayKey: "2026-10-06")
        #expect(book.currentPage == 47 && book.log["2026-10-06"] == 17)
        book.setPage(500, dayKey: "2026-10-06")
        #expect(book.currentPage == 200 && book.log["2026-10-06"] == 170)
        book.setPage(40, dayKey: "2026-10-06")
        #expect(book.currentPage == 40 && book.log["2026-10-06"] == 10)
        // Ertesi gün geri alınan sayfa o günü eksiye düşürmez, dünkü kayıt da değişmez.
        book.setPage(30, dayKey: "2026-10-07")
        #expect(book.currentPage == 30 && book.log["2026-10-07"] == 0 && book.log["2026-10-06"] == 10)
        book.setPage(-5, dayKey: "2026-10-07")
        #expect(book.currentPage == 0)
    }

    // MARK: Deneme

    @Test func nextMockExam() {
        let previous = MockExam(title: "TYT 3", penalty: 3, rows: [
            .init(name: "Türkçe", correct: 30, wrong: 5, blank: 5), .init(name: "Matematik", correct: 20, wrong: 10, blank: 10),
        ])
        let next = MockExam.next(after: previous)
        #expect(next.rows.map(\.name) == ["Türkçe", "Matematik"])
        #expect(next.rows.allSatisfy { $0.correct == 0 && $0.wrong == 0 && $0.blank == 0 })
        #expect(Set(next.rows.map(\.id)).isDisjoint(with: previous.rows.map(\.id)))
        #expect(next.id != previous.id && next.penalty == 3 && next.title.isEmpty)
        let first = MockExam.next(after: nil)
        #expect(first.rows.count == 1 && first.penalty == 4 && first.title.isEmpty)
        // Satırsız (bozuk) önceki deneme: boş satırlı varsayılana dönülür.
        #expect(MockExam.next(after: MockExam(penalty: 0, rows: [])).rows.count == 1)
    }

    @Test func mockExamLessonSeries() {
        let old = MockExam(date: date(2026, 10, 1), penalty: 4, rows: [.init(name: "Matematik", correct: 20, wrong: 4), .init(name: "Türkçe", correct: 30)])
        let new = MockExam(date: date(2026, 10, 5), penalty: 4, rows: [.init(name: " matematik ", correct: 25, wrong: 8), .init(name: "Fizik", correct: 5), .init(name: "")])
        // Yalnız tek denemede geçen (Türkçe, Fizik) ve adsız satır listede yok; yazılış en yeni denemeden.
        #expect(MockExamStats.lessons([old, new]) == ["matematik"])
        #expect(MockExamStats.lessons([old]).isEmpty)
        let lesson = MockExamStats.series([new, old], lesson: "Matematik")
        #expect(lesson.map { $0.date } == [old.date, new.date])
        #expect(lesson.map { $0.net } == [19, 23])
        let total = MockExamStats.series([new, old], lesson: nil)
        #expect(total.map { $0.net } == [old.net, new.net])
        #expect(total.map { $0.net } == [49, 28])
        #expect(MockExamStats.series([old, new], lesson: "Kimya").isEmpty)
        // Aynı denemede dersin iki satırı (ör. iki test) toplanır ve ders bir kez sayılır.
        let split = MockExam(date: date(2026, 10, 6), penalty: 0, rows: [.init(name: "Fizik", correct: 3), .init(name: "fizik", correct: 4)])
        #expect(MockExamStats.lessons([split]).isEmpty)
        #expect(MockExamStats.series([split], lesson: "Fizik").map { $0.net } == [7])
    }

    // MARK: Alışkanlık haftası

    @Test func habitWeekDays() {
        let week = HabitWeek.days(ending: date(2026, 10, 6, hour: 15, minute: 30), calendar: utc)
        #expect(week.count == 7)
        #expect(week.allSatisfy { utc.startOfDay(for: $0) == $0 })
        #expect(week.last == date(2026, 10, 6, hour: 0))
        #expect(week.map { DayKey.key($0, calendar: utc) } == ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"])
        // Gün içinde saat değişse de aynı dizi: liste kimlikleri sabit.
        #expect(HabitWeek.days(ending: date(2026, 10, 6, hour: 23, minute: 59), calendar: utc) == week)
    }

    @Test func habitWeekLabels() {
        #expect(HabitWeek.label(date(2026, 10, 5), calendar: utc) == "Pt")
        #expect(HabitWeek.label(date(2026, 10, 10), calendar: utc) == "Ct")
        #expect(HabitWeek.label(date(2026, 10, 11), calendar: utc) == "Pz")
        let labels = HabitWeek.days(ending: date(2026, 10, 6), calendar: utc).map { HabitWeek.label($0, calendar: utc) }
        #expect(labels == ["Ça", "Pe", "Cu", "Ct", "Pz", "Pt", "Sa"])
        #expect(Set(labels).count == 7)
    }

    // MARK: Öğrenme günlüğü

    @Test func journalCarryOver() {
        let entries = [
            JournalEntry(day: "2026-10-05", tomorrow: "Limit tekrarı"), JournalEntry(day: "2026-10-04", tomorrow: "Türev"),
            JournalEntry(day: "2026-10-06", tomorrow: "Bugünün notu"),
        ]
        #expect(JournalLogic.carryOver(entries, todayKey: "2026-10-06")?.tomorrow == "Limit tekrarı")
        // En yeni önceki girdinin notu boşsa daha eskiye bakılmaz.
        let blank = [JournalEntry(day: "2026-10-05", tomorrow: "  \n"), JournalEntry(day: "2026-10-04", tomorrow: "Türev")]
        #expect(JournalLogic.carryOver(blank, todayKey: "2026-10-06") == nil)
        #expect(JournalLogic.carryOver([JournalEntry(day: "2026-10-06", tomorrow: "Yarın")], todayKey: "2026-10-06") == nil)
        #expect(JournalLogic.carryOver([], todayKey: "2026-10-06") == nil)
        #expect(JournalLogic.isYesterday("2026-10-05", todayKey: "2026-10-06", calendar: utc))
        #expect(!JournalLogic.isYesterday("2026-10-04", todayKey: "2026-10-06", calendar: utc))
        #expect(JournalLogic.isYesterday("2026-09-30", todayKey: "2026-10-01", calendar: utc))
        #expect(!JournalLogic.isYesterday("2026-10-05", todayKey: "bozuk", calendar: utc))
    }

    @Test func journalHasContent() {
        #expect(!JournalLogic.hasContent(JournalEntry()))
        #expect(!JournalLogic.hasContent(JournalEntry(learned: "  ", hard: "\n")))
        #expect(JournalLogic.hasContent(JournalEntry(mood: 5)))
        #expect(JournalLogic.hasContent(JournalEntry(hard: "Türev")))
        #expect(JournalLogic.hasContent(JournalEntry(tomorrow: "Limit")))
    }

    @Test func journalNeedsSave() {
        let stored = JournalEntry(day: "2026-10-06", learned: "Limit")
        // Kaydı olmayan günün boş taslağı dosyaya yazılmaz; ruh hali ya da metin varsa yazılır.
        #expect(!JournalLogic.needsSave(JournalEntry(day: "2026-10-06"), stored: nil))
        #expect(JournalLogic.needsSave(JournalEntry(day: "2026-10-06", mood: 5), stored: nil))
        #expect(!JournalLogic.needsSave(stored, stored: stored))
        // Var olan kaydı bilerek boşaltmak da kaydedilir (eski metin geri gelmesin).
        var cleared = stored
        cleared.learned = ""
        #expect(JournalLogic.needsSave(cleared, stored: stored))
    }

    // MARK: Depo biçimi

    /// Bu dalgada depolanan alan eklenmedi; eski dosyalar aynen çözülmeli.
    @Test func storedFilesStillDecode() throws {
        let id = "8B0E1A52-6C1B-4A0E-9C8F-0D5B7A6E4F21", row = "1F2E3D4C-5B6A-4798-8A9B-0C1D2E3F4A5B"
        let exams = try JSONDecoder().decode([MockExam].self, from: Data("""
        [{"id":"\(id)","title":"TYT 1","date":781000000,"penalty":4,"rows":[{"id":"\(row)","name":"Türkçe","correct":30,"wrong":4,"blank":6}]}]
        """.utf8))
        #expect(exams.first?.net == 29 && exams.first?.rows.first?.blank == 6)
        let books = try JSONDecoder().decode([ReadingBook].self, from: Data("""
        [{"id":"\(id)","title":"Suç ve Ceza","totalPages":687,"currentPage":120,"log":{"2026-10-05":20}}]
        """.utf8))
        #expect(books.first?.totalPages == 687 && books.first?.log["2026-10-05"] == 20)
        let goals = try JSONDecoder().decode([StudyGoal].self, from: Data("""
        [{"id":"\(id)","title":"Paragraf","target":300,"done":40},{"id":"\(row)","title":"Deneme","target":5,"done":5,"deadline":781000000}]
        """.utf8))
        #expect(goals.map(\.target) == [300, 5] && goals.first?.deadline == nil && goals.last?.deadline != nil)
        let habits = try JSONDecoder().decode([Habit].self, from: Data("""
        [{"id":"\(id)","name":"Kitap","days":["2026-10-05","2026-10-06"]}]
        """.utf8))
        #expect(habits.first?.days.count == 2)
        let journal = try JSONDecoder().decode([JournalEntry].self, from: Data("""
        [{"id":"\(id)","day":"2026-10-05","mood":4,"learned":"Limit","hard":"","tomorrow":"Türev"}]
        """.utf8))
        #expect(journal.first?.tomorrow == "Türev" && journal.first?.mood == 4)
        let logs = try JSONDecoder().decode([QuestionLog].self, from: Data("""
        [{"id":"\(id)","day":"2026-10-05","course":"","solved":40,"wrong":6}]
        """.utf8))
        #expect(logs.first?.solved == 40 && logs.first?.wrong == 6)
    }

    /// Geri yükleme açık deponun dosyasına kayıt ekleyince depo listesini yeniden okur; sonraki değişiklik eklenenleri ezmez.
    @Test @MainActor func jsonStoreReloadsAfterRestore() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "araclar-geri-yukleme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "todos.json"), restored = Notification.Name("dersdas.tools.restored")
        let store = JSONStore<TodoItem>("todos", directory: dir)
        store.items.append(TodoItem(title: "Cihazdaki"))
        try JSONEncoder().encode(store.items + [TodoItem(title: "Yedekteki")]).write(to: file, options: .atomic)
        #expect(store.items.map(\.title) == ["Cihazdaki"])
        NotificationCenter.default.post(name: restored, object: nil)
        #expect(store.items.map(\.title) == ["Cihazdaki", "Yedekteki"])
        store.items[0].done = true
        let saved = JSONStore<TodoItem>("todos", directory: dir).items
        #expect(saved.map(\.title) == ["Cihazdaki", "Yedekteki"] && saved.first?.done == true)
        // Çözülemeyen ya da eksik dosyada bellekteki liste kalır; dosya kenara alınmaz.
        try Data("bozuk".utf8).write(to: file)
        NotificationCenter.default.post(name: restored, object: nil)
        #expect(store.items.count == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!names.contains { $0.contains(".bozuk-") })
        try FileManager.default.removeItem(at: file)
        store.reload()
        #expect(store.items.count == 2)
        #expect(JSONStoreLocation.restored == restored)
    }

    // MARK: Dalga 2 — sayı hafızası ve Schulte

    @Test func digitSpanFirstMismatch() {
        #expect(DigitSpan.firstMismatch(typed: "4719", expected: [4, 7, 1, 9]) == nil)
        #expect(DigitSpan.firstMismatch(typed: "4791", expected: [4, 7, 1, 9]) == 2)
        // Eksik ve fazla rakam da farktır.
        #expect(DigitSpan.firstMismatch(typed: "47", expected: [4, 7, 1, 9]) == 2)
        #expect(DigitSpan.firstMismatch(typed: "47195", expected: [4, 7, 1, 9]) == 4)
        #expect(DigitSpan.firstMismatch(typed: "", expected: [4, 7, 1, 9]) == 0)
        #expect(DigitSpan.firstMismatch(typed: "", expected: []) == nil)
    }

    @Test func schulteTimeText() {
        #expect(Schulte.timeText(12.34) == "12,3")
        #expect(Schulte.timeText(9) == "9,0")
        #expect(Schulte.timeText(59.96) == "60,0")
    }

    // MARK: Dalga 2 — soru takibi

    @Test func questionsByCourse() {
        let logs = [
            QuestionLog(course: "Biyoloji", solved: 40, wrong: 10), QuestionLog(course: "biyoloji ", solved: 20, wrong: 0),
            QuestionLog(course: "", solved: 30, wrong: 6), QuestionLog(course: "Kimya", solved: 10, wrong: 5),
        ]
        #expect(QuestionStats.byCourse(logs) == [
            .init(course: "Biyoloji", solved: 60, wrong: 10, accuracy: 83), .init(course: "Derssiz", solved: 30, wrong: 6, accuracy: 80),
            .init(course: "Kimya", solved: 10, wrong: 5, accuracy: 50),
        ])
        #expect(QuestionStats.byCourse([]).isEmpty)
        // "Derssiz" adlı ders adsız kayıtlarla birleşir: satır kimlikleri benzersiz kalır.
        let merged = QuestionStats.byCourse([QuestionLog(course: "derssiz", solved: 5), QuestionLog(course: "", solved: 5), QuestionLog(course: "Fizik", solved: 5)])
        #expect(merged.map { $0.course } == ["Derssiz", "Fizik"] && merged.first?.solved == 10)
        #expect(Set(merged.map { $0.id }).count == merged.count)
        // Eşitlikte ilk girilen ders önce.
        #expect(QuestionStats.byCourse([QuestionLog(course: "Tarih", solved: 5), QuestionLog(course: "Coğrafya", solved: 5)]).map { $0.course } == ["Tarih", "Coğrafya"])
    }

    @Test func questionDayTotals() {
        let logs = [
            QuestionLog(day: "2026-10-06", solved: 12), QuestionLog(day: "2026-10-06", solved: 8), QuestionLog(day: "2026-10-05", solved: 30),
            QuestionLog(day: "2026-09-21", solved: 99), QuestionLog(day: "2026-09-23", solved: 7),
        ]
        let days = QuestionStats.dayTotals(logs, days: 14, today: date(2026, 10, 6, hour: 22), calendar: utc)
        #expect(days.count == 14 && Set(days.map { $0.id }).count == 14)
        #expect(days.first?.key == "2026-09-23" && days.first?.solved == 7)
        // Aynı günün iki kaydı tek öğede toplanır.
        #expect(days.last?.key == "2026-10-06" && days.last?.solved == 20)
        #expect(days.last?.date == date(2026, 10, 6, hour: 0))
        // 15 gün önceki kayıt (21 Eylül) sayılmaz.
        #expect(days.reduce(0) { $0 + $1.solved } == 57)
        #expect(QuestionStats.dayTotals(logs, days: 0, today: date(2026, 10, 6), calendar: utc).isEmpty)
    }

    @Test func dayKeyShortLabel() {
        // 5 Ekim 2026 Pazartesi.
        let label = DayKey.shortLabel("2026-10-05", calendar: utc)
        #expect(label.contains("5") && label.contains("Eki") && label.contains("Pzt"), "\(label)")
        #expect(DayKey.shortLabel("bozuk", calendar: utc) == "bozuk")
    }

    // MARK: Dalga 2 — hızlı okuma

    @Test func speedReadFontSize() {
        #expect(SpeedReading.fontSize(for: "ev", width: 264) == 34)
        #expect(SpeedReading.fontSize(for: "mitokondri", width: 264) == 34)
        let long = "öğrenebileceğimizden"
        #expect(long.count == 20 && SpeedReading.pivot(long) == 4)
        // Odak harfi + son ek (16 harf), ön ekten kalan genişliğe tek boyda sığar.
        let size = SpeedReading.fontSize(for: long, width: 264)
        #expect(size >= 12 && size < 34)
        #expect(16 * size * 0.62 <= 264 - SpeedReading.prefixWidth() + 0.01)
        #expect(SpeedReading.fontSize(for: String(repeating: "a", count: 60), width: 264) == 12)
        // Genişlik ön eke bile yetmiyorsa alt sınır.
        #expect(SpeedReading.fontSize(for: long, width: 40) == 12)
        #expect(SpeedReading.fontSize(for: "", width: 264) == 34)
    }

    @Test func speedReadResume() {
        #expect(SpeedReading.resumeIndex(saved: 40, count: 100) == 40)
        // Sonuna gelinmiş ya da boş metinde devam önerilmez.
        #expect(SpeedReading.resumeIndex(saved: 100, count: 100) == nil)
        #expect(SpeedReading.resumeIndex(saved: 0, count: 0) == nil)
        #expect(SpeedReading.resumeIndex(saved: -3, count: 10) == 0)
        #expect(SpeedReading.percent(index: 43, count: 100) == 43)
        #expect(SpeedReading.percent(index: 1, count: 3) == 33)
        #expect(SpeedReading.percent(index: 5, count: 0) == 0)
        #expect(SpeedReading.percent(index: 500, count: 100) == 100)
    }

    // MARK: Dalga 2 — hesap makinesi

    @Test func calculatorImplicitMultiplication() {
        #expect(abs((Calculator.evaluate("2π") ?? 0) - 2 * Double.pi) < 1e-12)
        #expect(Calculator.evaluate("3(4+5)") == 27)
        #expect(Calculator.evaluate("(2)(3)") == 6)
        #expect(Calculator.evaluate("2√9") == 6)
        #expect(abs((Calculator.evaluate("2sin(30)") ?? 0) - 1) < 1e-12)
        #expect(abs((Calculator.evaluate("2^2π") ?? 0) - 4 * Double.pi) < 1e-12)
        // Üs, örtük çarpmadan önce; bölme ve örtük çarpma soldan sağa.
        #expect(Calculator.evaluate("2(3)^2") == 18)
        #expect(Calculator.evaluate("6÷2(3)") == 9)
        #expect(Calculator.evaluate("2+3(4)") == 14)
        #expect(Calculator.evaluate("(-5)2") == -10)
        for bad in ["", "2+", "1÷0", "(2+3", "2)", "abc(2)", "√(0-4)", "ln(0)", "2..3", "sin", "2x", "3()", "2(", ")("] {
            #expect(Calculator.evaluate(bad) == nil, "\(bad)")
        }
        #expect(Calculator.openParens("((2+3)") == 1)
        #expect(Calculator.openParens("2)") == 0)
        #expect(Calculator.openParens("") == 0 && Calculator.openParens("sin(30)") == 0)
    }

    @Test func calculatorScientificNotation() {
        // Sayıya bitişik "e" + rakam 10 üssüdür; Euler sabitiyle çarpma (3×e×8 = 65,24) değil.
        #expect(Calculator.evaluate("3e8") == 3e8)
        #expect(Calculator.evaluate("6,02e23") == 6.02e23)
        #expect(Calculator.evaluate("3E8") == 3e8)
        #expect(Calculator.evaluate("2e3+1") == 2001)
        // İşaretli üs "2×e − 3" ile karışır: sessiz yanlış sonuç yerine geçersiz.
        for bad in ["1e-3", "2e+1", "2e−3", "2e3.5"] {
            #expect(Calculator.evaluate(bad) == nil, "\(bad)")
        }
        // Ardından rakam gelmeyen "e" yine Euler sabitidir.
        #expect(abs((Calculator.evaluate("2e") ?? 0) - 2 * M_E) < 1e-12)
        #expect(abs((Calculator.evaluate("2×e−3") ?? 0) - (2 * M_E - 3)) < 1e-12)
        #expect(abs((Calculator.evaluate("2e^2") ?? 0) - 2 * M_E * M_E) < 1e-9)
        #expect(abs((Calculator.evaluate("2e(3)") ?? 0) - 6 * M_E) < 1e-9)
        #expect(abs((Calculator.evaluate("ln(e)") ?? 0) - 1) < 1e-12)
    }

    // MARK: Dalga 2 — yazarak tekrar

    @Test func reviewRound() {
        let a = UUID(), b = UUID(), c = UUID()
        var round = ReviewRound(ids: [a, b, c])
        #expect(!round.isFinished && round.current == a)
        round.record(correct: false)
        round.record(correct: true)
        round.record(correct: false)
        #expect(round.isFinished && round.current == nil)
        #expect(round.correct == 1 && round.missed == [a, c])
        // Biten turda fazladan kayıt sayaçları bozmaz.
        round.record(correct: true)
        #expect(round.index == 3 && round.correct == 1)
        let retry = round.retry()
        #expect(retry.ids == [a, c] && retry.index == 0 && retry.correct == 0 && retry.missed.isEmpty)
        #expect(ReviewRound<UUID>(ids: []).isFinished)
    }

    // MARK: Dalga 2 — devamsızlık

    @Test func absenceLevelsAndSummary() {
        #expect(AbsenceMath.level(count: 3, limit: 10) == .ok)
        #expect(AbsenceMath.level(count: 8, limit: 10) == .warning)
        #expect(AbsenceMath.level(count: 9, limit: 10) == .warning)
        #expect(AbsenceMath.level(count: 10, limit: 10) == .atLimit)
        #expect(AbsenceMath.level(count: 12, limit: 10) == .exceeded)
        #expect(AbsenceMath.summary(count: 3, limit: 10) == "3 devamsızlık · 7 hak kaldı")
        #expect(AbsenceMath.summary(count: 10, limit: 10) == "10/10 · hakkın bitti")
        // Sınır aşılınca sayı da aşım da görünür kalır.
        let over = AbsenceMath.summary(count: 12, limit: 10)
        #expect(over.contains("12/10") && over.contains("2 aşıldı"))
    }

    @Test func absenceDays() throws {
        let days = ["2026-10-01", "2026-10-06", "2026-10-01"]
        #expect(AbsenceMath.grouped(days) == [.init(day: "2026-10-06", count: 1), .init(day: "2026-10-01", count: 2)])
        #expect(AbsenceMath.grouped([]).isEmpty)
        // Aynı günün yalnız bir kaydı silinir; listede olmayan gün diziyi değiştirmez.
        #expect(AbsenceMath.removingOne("2026-10-01", from: days) == ["2026-10-01", "2026-10-06"])
        #expect(AbsenceMath.removingOne("2026-09-01", from: days) == days)
        // Bu dalgada depolanan alan eklenmedi: eski dosya aynen çözülür.
        let stored = try JSONDecoder().decode([AbsenceCourse].self, from: Data("""
        [{"id":"8B0E1A52-6C1B-4A0E-9C8F-0D5B7A6E4F21","name":"Fizik","limit":10,"days":["2026-10-01","2026-10-06","2026-10-01"]}]
        """.utf8))
        #expect(stored.first?.days == days && stored.first?.limit == 10)
    }
}
