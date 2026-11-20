import Foundation

struct QuestionImportReport: Equatable {
    var inserted = 0
    var duplicates = 0
    var invalid = 0
    var importBatchID: String? = nil
    var message: String { "\(inserted) yeni soru eklendi · \(duplicates) tekrar atlandı · \(invalid) geçersiz soru atlandı" }
}
struct QuestionImportPreview { let questions: [Question]; let invalid: Int; let fileCount: Int }
enum QuestionTransfer {
    static let maximumBytes = 100_000_000
    static let maximumQuestions = 100_000
    static func decode(_ data: Data) throws -> (questions:[Question], invalid:Int) {
        guard data.count <= maximumBytes else { throw QuizError("İçe aktarım dosyası en fazla 100 MB olabilir.") }
        let raw = try JSONSerialization.jsonObject(with:data)
        let rows: [Any]
        if let object = raw as? [String:Any] {
            if let version = object["schemaVersion"] as? Int, version != 1 { throw QuizError("Bu paket sürümü desteklenmiyor.") }
            if let values = object["questions"] as? [Any] { rows = values }
            else if object["text"] != nil { rows = [object] }
            else { throw QuizError("JSON içinde questions dizisi bulunamadı.") }
        } else if let values = raw as? [Any] { rows = values }
        else { throw QuizError("Geçerli bir soru JSON dosyası seç.") }
        guard (1...maximumQuestions).contains(rows.count) else { throw QuizError("Bir dosyada 1 ile 100.000 arasında soru bulunabilir.") }
        var questions: [Question] = [], invalid = 0
        for value in rows {
            guard let row = value as? [String:Any], JSONSerialization.isValidJSONObject(row),
                  let data = try? JSONSerialization.data(withJSONObject:row) else { invalid += 1; continue }
            if let q = try? JSONDecoder().decode(Question.self,from:data), q.isWellFormed { questions.append(q); continue }
            // External authors can omit compatibility choices on structured activities.
            if let topic = (row["category"] as? String).flatMap(Topic.init(rawValue:)),
               let difficulty = (row["difficulty"] as? String).flatMap(Difficulty.init(rawValue:)) {
                let result = GeneratedQuestionParser.parse(String(decoding:data,as:UTF8.self),topic:topic,difficulty:difficulty,excluding:[],limit:1)
                if let q = result.questions.first { questions.append(q); continue }
            }
            invalid += 1
        }
        return (questions,invalid)
    }
    static func importFile(_ url: URL, database: QuestionPoolDatabase, progress: @escaping @Sendable (Int,Int) async -> Void = { _,_ in }) async throws -> QuestionImportReport {
        let attributes = try url.resourceValues(forKeys:[.fileSizeKey])
        guard (attributes.fileSize ?? 0) <= maximumBytes else { throw QuizError("İçe aktarım dosyası en fazla 100 MB olabilir.") }
        let parsed = try await Task.detached { try decode(Data(contentsOf:url,options:.mappedIfSafe)) }.value
        guard !parsed.questions.isEmpty else { throw QuizError("Geçerli soru bulunamadı.") }
        return try await store(.init(questions:parsed.questions,invalid:parsed.invalid,fileCount:1),database:database,progress:progress)
    }
    static func previewFiles(_ urls: [URL]) async throws -> QuestionImportPreview {
        try await Task.detached {
            var questions: [Question] = [], invalid = 0, bytes = 0
            for url in urls {
                try Task.checkCancellation()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                bytes += size
                guard bytes <= maximumBytes else { throw QuizError("Seçilen dosyaların toplamı en fazla 100 MB olabilir.") }
                let parsed = try decode(Data(contentsOf:url,options:.mappedIfSafe))
                questions += parsed.questions; invalid += parsed.invalid
                guard questions.count+invalid <= maximumQuestions else { throw QuizError("Tek aktarımda en fazla 100.000 soru seçebilirsin.") }
            }
            return QuestionImportPreview(questions:questions,invalid:invalid,fileCount:urls.count)
        }.value
    }
    static func store(_ preview: QuestionImportPreview,database: QuestionPoolDatabase,progress: @escaping @Sendable (Int,Int) async -> Void = { _,_ in }) async throws -> QuestionImportReport {
        let run = UUID().uuidString
        var report = QuestionImportReport(invalid:preview.invalid)
        for offset in stride(from:0,to:preview.questions.count,by:100) {
            try Task.checkCancellation()
            let batch = Array(preview.questions[offset..<min(offset+100,preview.questions.count)])
            let count = try await database.insert(batch,importBatchID:run)
            report.inserted += count; report.duplicates += batch.count-count
            await progress(min(offset+100,preview.questions.count),preview.questions.count)
        }
        report.importBatchID = report.inserted > 0 ? run : nil
        return report
    }
    static func temporaryURL(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BilgiArenaExports")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder.appendingPathComponent(prefix+"-"+UUID().uuidString+".json")
    }
    static func exportQuestions(_ questions: [Question], to url: URL) throws {
        struct Envelope: Encodable { let schemaVersion = 1; let questions: [Question] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(Envelope(questions:questions)).write(to:url,options:[.atomic,.completeFileProtection])
    }
    static var guide: String {
        """
        Bilgi Arenası JSON v1. Kök: {"schemaVersion":1,"questions":[...]}. Her soru text, category (Türkçe kategori adı), difficulty (Kolay/Orta/Zor), explanation içerir. Çoktan seçmelide options dört farklı metin ve answer 0-3 doğru indeksidir; optionExplanations isteğe bağlı dört gerekçedir. activity veya visual alanı isteğe bağlıdır; ikisi aynı soruda kullanılamaz. Örnekler aşağıdadır. Görsel imageID kataloğu: violin, bicycle, leaf. URL/ses dosyası/base64 içermez. İçe aktarım sınırı 100 MB ve 100.000 soru; geçersiz ve tekrarlanan kayıtlar sayılarak atlanır. Gizli sorular dışa aktarımda isteğe bağlıdır. Dosya hesap anahtarı, oyuncu geçmişi veya mikrofon kaydı içermez.
        """
    }
}
