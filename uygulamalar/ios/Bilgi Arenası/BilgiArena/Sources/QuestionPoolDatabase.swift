import Foundation
import SQLite3

struct PoolCell: Hashable {
    let topic: Topic
    let difficulty: Difficulty
    var key: String { topic.rawValue + "|" + difficulty.rawValue }
}
struct PoolSnapshot {
    var total = 0
    var today = 0
    var counts: [PoolCell: Int] = [:]
    var categoryTotals: [Topic: Int] = [:]
    var visualCounts: [QuestionVisualKind:Int] = [:]
    var activityCounts: [ActivityKind:Int] = [:]
}
enum DailyPoolPlan {
    static let categories: [Topic] = [.science,.history,.geography,.art,.sport,.culture,.cinema,.language,.exam]
    static let perCategory = 50
    static var target: Int { categories.count * perCategory }
    static func day(_ date: Date) -> String {
        let c = Calendar(identifier:.gregorian).dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year ?? 0,c.month ?? 0,c.day ?? 0)
    }
    static func quota(_ cell: PoolCell, day: String) -> Int {
        let rotation = day.utf8.reduce(0) { $0+Int($1) } % 3
        let index = Difficulty.allCases.firstIndex(of:cell.difficulty) ?? 0
        return (index+rotation)%3 == 2 ? 16 : 17
    }
    static func next(counts: [PoolCell:Int], day: String) -> PoolCell? {
        let cells = categories.flatMap { t in Difficulty.allCases.map { PoolCell(topic:t,difficulty:$0) } }
        return cells.filter { counts[$0,default:0] < quota($0,day:day) }.min {
            let left = counts[$0,default:0], right = counts[$1,default:0]
            return left == right ? cells.firstIndex(of:$0)! < cells.firstIndex(of:$1)! : left < right
        }
    }
}

/// One transaction commits each valid batch. A unique key prevents duplicates across days.
actor QuestionPoolDatabase {
    private let db: OpaquePointer
    init(url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path,&handle,SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }; throw QuizError("Soru havuzu açılamadı.")
        }
        db = handle
        sqlite3_busy_timeout(handle,4000)
        let schema = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS questions (
          fingerprint TEXT PRIMARY KEY, payload BLOB NOT NULL, category TEXT NOT NULL,
          difficulty TEXT NOT NULL, day TEXT, created REAL NOT NULL, lastPlayed REAL, hidden INTEGER NOT NULL DEFAULT 0, visualKind TEXT, activityKind TEXT, noveltyText TEXT, exam TEXT, lesson TEXT, importBatchID TEXT);
        CREATE INDEX IF NOT EXISTS daily_cells ON questions(day,category,difficulty);
        CREATE INDEX IF NOT EXISTS library_filter ON questions(hidden,category,difficulty);
        """
        guard sqlite3_exec(handle,schema,nil,nil,nil) == SQLITE_OK else { sqlite3_close(handle); throw QuizError("Soru havuzu hazırlanamadı.") }
        var columns: OpaquePointer?
        sqlite3_prepare_v2(handle,"PRAGMA table_info(questions)",-1,&columns,nil)
        var names: Set<String> = []
        if let columns {
            while sqlite3_step(columns) == SQLITE_ROW {
                if let name = sqlite3_column_text(columns,1) { names.insert(String(cString:name)) }
            }
            sqlite3_finalize(columns)
        }
        for name in ["visualKind","activityKind","noveltyText","exam","lesson","importBatchID"] where !names.contains(name) {
            if sqlite3_exec(handle,"ALTER TABLE questions ADD COLUMN \(name) TEXT",nil,nil,nil) != SQLITE_OK {
                sqlite3_close(handle); throw QuizError("Soru türleri güncellenemedi; önceki kayıtlar korunuyor.")
            }
        }
        guard sqlite3_exec(handle,"CREATE UNIQUE INDEX IF NOT EXISTS new_question_identity ON questions(noveltyText) WHERE noveltyText IS NOT NULL",nil,nil,nil) == SQLITE_OK else { sqlite3_close(handle); throw QuizError("Yeni soru dizini hazırlanamadı.") }
        guard sqlite3_exec(handle,"CREATE TABLE IF NOT EXISTS import_runs(id TEXT PRIMARY KEY,created REAL NOT NULL); CREATE INDEX IF NOT EXISTS study_filter ON questions(exam,lesson,difficulty); CREATE INDEX IF NOT EXISTS import_batch ON questions(importBatchID)",nil,nil,nil) == SQLITE_OK else { sqlite3_close(handle); throw QuizError("Aktarım dizini hazırlanamadı.") }
    }
    deinit { sqlite3_close(db) }
    func novelCandidates(_ candidates: [Question]) throws -> [Question] {
        var seen: [String:Set<String>] = [:]
        for topic in Set(candidates.map(\.category)) {
            let s = try statement("SELECT noveltyText FROM questions WHERE category=? AND noveltyText IS NOT NULL ORDER BY created DESC LIMIT 2000")
            bind(topic.rawValue,to:s,at:1)
            while sqlite3_step(s) == SQLITE_ROW { if let raw = sqlite3_column_text(s,0) { let key = String(cString:raw); seen[key.filter(\.isNumber),default:[]].insert(key) } }
            sqlite3_finalize(s)
        }
        var accepted: [Question] = []
        for q in candidates where q.isWellFormed {
            let signature = QuestionSimilarity.fingerprint(q.uniquenessText)
            let digits = signature.filter(\.isNumber)
            guard !QuestionSimilarity.isDuplicate(signature,against:seen[digits,default:[]]) else { continue }
            accepted.append(q); seen[digits,default:[]].insert(signature)
        }
        return accepted
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var value: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&value,nil) == SQLITE_OK, let value else { throw QuizError("Soru havuzu sorgulanamadı.") }
        return value
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement,index,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
    }
    @discardableResult func insert(_ questions: [Question], day: String? = nil, importBatchID: String? = nil) throws -> Int { try insertUnique(questions,day:day,importBatchID:importBatchID).count }
    func insertUnique(_ questions: [Question], day: String? = nil, importBatchID: String? = nil) throws -> [Question] {
        guard sqlite3_exec(db,"BEGIN IMMEDIATE",nil,nil,nil) == SQLITE_OK else { throw QuizError("Havuz kaydı başlatılamadı.") }
        do {
            let s = try statement("INSERT OR IGNORE INTO questions(fingerprint,payload,category,difficulty,day,created,visualKind,activityKind,noveltyText,exam,lesson,importBatchID) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)")
            defer { sqlite3_finalize(s) }
            var inserted: [Question] = []
            for q in try novelCandidates(questions) {
                try Task.checkCancellation()
                sqlite3_reset(s); sqlite3_clear_bindings(s)
                bind(q.poolKey,to:s,at:1)
                let data = try JSONEncoder().encode(q)
                _ = data.withUnsafeBytes { sqlite3_bind_blob(s,2,$0.baseAddress,Int32(data.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
                bind(q.category.rawValue,to:s,at:3); bind(q.difficulty.rawValue,to:s,at:4)
                if let day { bind(day,to:s,at:5) } else { sqlite3_bind_null(s,5) }
                sqlite3_bind_double(s,6,Date().timeIntervalSince1970)
                if let kind = q.visual?.kind { bind(kind.rawValue,to:s,at:7) } else { sqlite3_bind_null(s,7) }
                if let kind = q.activity?.kind { bind(kind.rawValue,to:s,at:8) } else { sqlite3_bind_null(s,8) }
                bind(QuestionSimilarity.fingerprint(q.uniquenessText),to:s,at:9)
                if let study = q.study { bind(study.exam,to:s,at:10); if let lesson = study.lesson { bind(lesson,to:s,at:11) } } else { sqlite3_bind_null(s,10); sqlite3_bind_null(s,11) }
                if let importBatchID { bind(importBatchID,to:s,at:12) } else { sqlite3_bind_null(s,12) }
                guard sqlite3_step(s) == SQLITE_DONE else { throw QuizError("Sorular kaydedilemedi; önceki havuz korunuyor.") }
                if sqlite3_changes(db) > 0 { inserted.append(q) }
            }
            if let importBatchID, !inserted.isEmpty {
                let run = try statement("INSERT OR IGNORE INTO import_runs(id,created) VALUES(?,?)")
                bind(importBatchID,to:run,at:1); sqlite3_bind_double(run,2,Date().timeIntervalSince1970)
                let status = sqlite3_step(run); sqlite3_finalize(run)
                guard status == SQLITE_DONE else { throw QuizError("Aktarım geri alma kaydı yazılamadı.") }
            }
            guard sqlite3_exec(db,"COMMIT",nil,nil,nil) == SQLITE_OK else { throw QuizError("Soru havuzu kaydı tamamlanamadı.") }
            return inserted
        } catch { sqlite3_exec(db,"ROLLBACK",nil,nil,nil); throw error }
    }
    func snapshot(day: String) throws -> PoolSnapshot {
        var result = PoolSnapshot()
        let visuals = try statement("SELECT visualKind,COUNT(*) FROM questions WHERE hidden=0 AND visualKind IS NOT NULL GROUP BY visualKind")
        defer { sqlite3_finalize(visuals) }
        while sqlite3_step(visuals) == SQLITE_ROW {
            if let raw = sqlite3_column_text(visuals,0), let kind = QuestionVisualKind(rawValue:String(cString:raw)) { result.visualCounts[kind] = Int(sqlite3_column_int(visuals,1)) }
        }
        let activities = try statement("SELECT activityKind,COUNT(*) FROM questions WHERE hidden=0 AND activityKind IS NOT NULL GROUP BY activityKind")
        defer { sqlite3_finalize(activities) }
        while sqlite3_step(activities) == SQLITE_ROW {
            if let raw = sqlite3_column_text(activities,0), let kind = ActivityKind(rawValue:String(cString:raw)) { result.activityCounts[kind] = Int(sqlite3_column_int(activities,1)) }
        }
        let all = try statement("SELECT category,COUNT(*) FROM questions WHERE hidden=0 GROUP BY category")
        defer { sqlite3_finalize(all) }
        while sqlite3_step(all) == SQLITE_ROW {
            if let raw = sqlite3_column_text(all,0), let topic = Topic(rawValue:String(cString:raw)) {
                let count = Int(sqlite3_column_int(all,1)); result.total += count; result.categoryTotals[topic] = count
            }
        }
        let s = try statement("SELECT category,difficulty,COUNT(*) FROM questions WHERE day=? GROUP BY category,difficulty")
        defer { sqlite3_finalize(s) }; bind(day,to:s,at:1)
        while sqlite3_step(s) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(s,0), let d = sqlite3_column_text(s,1), let topic = Topic(rawValue:String(cString:raw)), let difficulty = Difficulty(rawValue:String(cString:d)) else { continue }
            let count = Int(sqlite3_column_int(s,2)); result.counts[PoolCell(topic:topic,difficulty:difficulty)] = count; result.today += count
        }
        return result
    }
    func texts(topic: Topic, limit: Int = 700) throws -> [String] {
        let s = try statement("SELECT payload FROM questions WHERE category=? ORDER BY created DESC LIMIT ?")
        defer { sqlite3_finalize(s) }; bind(topic.rawValue,to:s,at:1); sqlite3_bind_int(s,2,Int32(limit))
        return decodeRows(s).map(\.uniquenessText)
    }
    func dayQuestions(_ day: String) throws -> [Question] {
        let s = try statement("SELECT payload FROM questions WHERE day=? ORDER BY created")
        defer { sqlite3_finalize(s) }; bind(day,to:s,at:1)
        return decodeRows(s)
    }
    func sample(topic: Topic, difficulty: Difficulty?, limit: Int, excluded: Set<String> = [], format: QuestionFormat = .mixed, study: StudyLesson? = nil) throws -> [Question] {
        let s = try statement("SELECT fingerprint,payload FROM questions WHERE hidden=0 AND (?='' OR category=?) AND (?='' OR difficulty=?) AND (?='' OR (?='visual' AND visualKind IS NOT NULL) OR (?='text' AND visualKind IS NULL AND activityKind IS NULL) OR activityKind=?) AND (?='' OR exam=?) AND (?='' OR lesson=?) ORDER BY lastPlayed IS NOT NULL, lastPlayed ASC, RANDOM()")
        defer { sqlite3_finalize(s) }
        bind(topic == .mixed ? "" : topic.rawValue,to:s,at:1); bind(topic.rawValue,to:s,at:2)
        bind(difficulty?.rawValue ?? "",to:s,at:3); bind(difficulty?.rawValue ?? "",to:s,at:4)
        for index in Int32(5)...Int32(8) { bind(format.databaseFilter,to:s,at:index) }
        for index in Int32(9)...Int32(10) { bind(study?.exam ?? "",to:s,at:index) }
        for index in Int32(11)...Int32(12) { bind(study?.lesson ?? "",to:s,at:index) }
        var values: [Question] = []
        while values.count < limit, sqlite3_step(s) == SQLITE_ROW {
            guard let key = sqlite3_column_text(s,0), !excluded.contains(String(cString:key)), let q = decode(s,column:1) else { continue }
            values.append(q.rearranged())
        }
        return values
    }
    func search(text: String, topic: Topic, difficulty: Difficulty?, limit: Int = 100, format: QuestionFormat = .mixed, study: StudyLesson? = nil) throws -> [Question] {
        let s = try statement("SELECT payload FROM questions WHERE hidden=0 AND (?='' OR category=?) AND (?='' OR difficulty=?) AND (?='' OR (?='visual' AND visualKind IS NOT NULL) OR (?='text' AND visualKind IS NULL AND activityKind IS NULL) OR activityKind=?) AND (?='' OR exam=?) AND (?='' OR lesson=?) ORDER BY created DESC")
        defer { sqlite3_finalize(s) }
        bind(topic == .mixed ? "" : topic.rawValue,to:s,at:1); bind(topic.rawValue,to:s,at:2)
        bind(difficulty?.rawValue ?? "",to:s,at:3); bind(difficulty?.rawValue ?? "",to:s,at:4)
        for index in Int32(5)...Int32(8) { bind(format.databaseFilter,to:s,at:index) }
        for index in Int32(9)...Int32(10) { bind(study?.exam ?? "",to:s,at:index) }
        for index in Int32(11)...Int32(12) { bind(study?.lesson ?? "",to:s,at:index) }
        let needle = QuestionSimilarity.fingerprint(text)
        var result: [Question] = []
        while result.count < limit, sqlite3_step(s) == SQLITE_ROW {
            guard let q = decode(s), needle.isEmpty || QuestionSimilarity.fingerprint(q.text+" "+q.explanation).contains(needle) else { continue }
            result.append(q)
        }
        return result
    }
    func exportFile(text: String = "", topic: Topic = .mixed, difficulty: Difficulty? = nil, format: QuestionFormat = .mixed, includeHidden: Bool = false, study: StudyLesson? = nil, to url: URL) throws -> Int {
        let s = try statement("SELECT payload FROM questions WHERE (?=1 OR hidden=0) AND (?='' OR category=?) AND (?='' OR difficulty=?) ORDER BY created,fingerprint")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s,1,includeHidden ? 1 : 0); bind(topic == .mixed ? "" : topic.rawValue,to:s,at:2); bind(topic.rawValue,to:s,at:3)
        bind(difficulty?.rawValue ?? "",to:s,at:4); bind(difficulty?.rawValue ?? "",to:s,at:5)
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw QuizError("Paylaşım dosyası oluşturulamadı.") }
        let file = try FileHandle(forWritingTo:url)
        defer { try? file.close() }
        var count = 0
        let needle = QuestionSimilarity.fingerprint(text)
        do {
            try file.write(contentsOf:Data("{\"schemaVersion\":1,\"questions\":[".utf8))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            while sqlite3_step(s) == SQLITE_ROW {
                try Task.checkCancellation()
                guard let q = decode(s), q.isWellFormed, format.accepts(q), study == nil || study!.matches(q.study), needle.isEmpty || QuestionSimilarity.fingerprint(q.text+" "+q.explanation).contains(needle) else { continue }
                if count > 0 { try file.write(contentsOf:Data(",".utf8)) }
                try file.write(contentsOf:encoder.encode(q)); count += 1
            }
            try file.write(contentsOf:Data("]}".utf8)); try file.synchronize()
            return count
        } catch { try? file.close(); try? FileManager.default.removeItem(at:url); throw error }
    }
    func lastImport() throws -> (id:String,count:Int)? {
        let s = try statement("SELECT r.id,COUNT(q.fingerprint) FROM import_runs r JOIN questions q ON q.importBatchID=r.id GROUP BY r.id ORDER BY r.created DESC LIMIT 1")
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW, let raw = sqlite3_column_text(s,0) else { return nil }
        return (String(cString:raw),Int(sqlite3_column_int(s,1)))
    }
    @discardableResult func undoImport(_ id: String) throws -> Int {
        let s = try statement("DELETE FROM questions WHERE importBatchID=?")
        defer { sqlite3_finalize(s) }; bind(id,to:s,at:1)
        guard sqlite3_step(s) == SQLITE_DONE else { throw QuizError("Aktarım geri alınamadı.") }
        return Int(sqlite3_changes(db))
    }
    func markPlayed(_ question: Question) throws {
        let s = try statement("UPDATE questions SET lastPlayed=? WHERE fingerprint=?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_double(s,1,Date().timeIntervalSince1970); bind(question.poolKey,to:s,at:2)
        guard sqlite3_step(s) == SQLITE_DONE else { throw QuizError("Soru geçmişi havuza yazılamadı.") }
    }
    func hide(_ key: String, hidden: Bool) throws {
        let s = try statement("UPDATE questions SET hidden=? WHERE fingerprint=?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s,1,hidden ? 1 : 0); bind(key,to:s,at:2)
        guard sqlite3_step(s) == SQLITE_DONE else { throw QuizError("Soru havuzu güncellenemedi.") }
    }
    private func decode(_ s: OpaquePointer, column: Int32 = 0) -> Question? {
        guard let raw = sqlite3_column_blob(s,column) else { return nil }
        return try? JSONDecoder().decode(Question.self,from:Data(bytes:raw,count:Int(sqlite3_column_bytes(s,column))))
    }
    private func decodeRows(_ s: OpaquePointer) -> [Question] {
        var result: [Question] = []
        while sqlite3_step(s) == SQLITE_ROW { if let q = decode(s) { result.append(q) } }
        return result
    }
}
