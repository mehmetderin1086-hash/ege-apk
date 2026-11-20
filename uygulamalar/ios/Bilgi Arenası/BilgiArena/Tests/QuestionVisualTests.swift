import XCTest
import UIKit
import SQLite3
@testable import BilgiArena

final class QuestionVisualTests: XCTestCase {
    func testVisualSeedsRoundTripAndShuffleRetainAllFiveKinds() throws {
        let qs = VisualQuestionSeeds.questions
        XCTAssertEqual(qs.count,12)
        XCTAssertEqual(Set(qs.compactMap { $0.visual?.kind }),Set(QuestionVisualKind.allCases))
        XCTAssertTrue(qs.allSatisfy(\.isWellFormed))
        let data = try JSONEncoder().encode(["questions":qs])
        XCTAssertEqual(try Question.decode(String(decoding:data,as:UTF8.self),expectedCount:12),qs)
        for q in qs {
            let reordered = q.rearranged(correctPosition:3)
            XCTAssertEqual(reordered.visual,q.visual); XCTAssertEqual(reordered.options[3],q.options[q.answer])
        }
    }
    func testLegacyQuestionsAndDraftsDecodeWithoutVisualOrFormat() throws {
        let q = Seed.questions.first { $0.visual == nil }!
        let data = try JSONEncoder().encode(q)
        var row = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        row.removeValue(forKey:"visual")
        let decoded = try JSONDecoder().decode(Question.self,from:JSONSerialization.data(withJSONObject:row))
        XCTAssertNil(decoded.visual); XCTAssertTrue(decoded.isWellFormed)
        let draft = GenerationDraft(id:UUID(),topic:.science,detail:"",difficulty:.easy,count:10,models:["model"],questions:[q])
        var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(draft)) as! [String:Any]
        object.removeValue(forKey:"format")
        let old = try JSONDecoder().decode(GenerationDraft.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(old.effectiveFormat,.mixed)
    }
    func testInvalidVisualDataIsRejectedInsteadOfSilentlyBecomingText() throws {
        var table = VisualQuestionSeeds.questions[2].visual!
        table.rows = [["K"]]; XCTAssertFalse(table.isValid)
        var chart = VisualQuestionSeeds.questions[3].visual!
        chart.values = [.nan,1,2]; XCTAssertFalse(chart.isValid)
        chart.values = [1,2]; XCTAssertFalse(chart.isValid)
        XCTAssertFalse(VisualElement(shape:.rectangle,x:98,y:50,width:30,height:20).isValid)
        XCTAssertFalse(VisualElement(shape:.arrow,x:50,y:50,endX:50,endY:50).isValid)
        var image = VisualQuestionSeeds.questions[1].visual!
        image.imageID = "https://example.com/image.png"; XCTAssertFalse(image.isValid)
        let data = try JSONEncoder().encode(VisualQuestionSeeds.questions[2])
        var row = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        row["visual"] = ["kind":"table","title":"Bozuk tablo","summary":"Bu tabloda eksik sütun bulunuyor.","columns":["A","B"],"rows":[["1"]]]
        let content = String(decoding:try JSONSerialization.data(withJSONObject:["questions":[row]]),as:UTF8.self)
        XCTAssertTrue(GeneratedQuestionParser.parse(content,topic:.science,difficulty:.easy,excluding:[],limit:1).questions.isEmpty)
        XCTAssertThrowsError(try Question.decode(content,expectedCount:1))
        row.removeValue(forKey:"visual")
        let missing = String(decoding:try JSONSerialization.data(withJSONObject:["questions":[row]]),as:UTF8.self)
        XCTAssertTrue(GeneratedQuestionParser.parse(missing,topic:.science,difficulty:.easy,excluding:[],limit:1).questions.isEmpty)
    }
    func testVisualTimingAndBundledPhotos() {
        let visual = VisualQuestionSeeds.questions[0], text = Seed.questions.first { $0.visual == nil }!
        var classic = Round(questions:[visual,text],source:"test")
        XCTAssertEqual(classic.remaining,25)
        classic.answer(visual.answer); classic.next(); XCTAssertEqual(classic.remaining,10)
        XCTAssertEqual(Round(questions:[visual],source:"test",mode:.sprint).remaining,15)
        XCTAssertEqual(Round(questions:[visual],source:"test",mode:.training).remaining,0)
        for photo in QuestionPhotoCatalog.items { XCTAssertNotNil(UIImage(named:photo.asset),photo.asset) }
    }
    func testOldPoolMigrationPreservesExistingRowsAndIndexesVisualContent() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("pool.sqlite")
        var old: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&old),SQLITE_OK)
        let sql = "CREATE TABLE questions(fingerprint TEXT PRIMARY KEY,payload BLOB NOT NULL,category TEXT NOT NULL,difficulty TEXT NOT NULL,day TEXT,created REAL NOT NULL,lastPlayed REAL,hidden INTEGER NOT NULL DEFAULT 0)"
        XCTAssertEqual(sqlite3_exec(old,sql,nil,nil,nil),SQLITE_OK)
        let q = Seed.questions.first { $0.visual == nil }!
        let data = try JSONEncoder().encode(q)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(old,"INSERT INTO questions(fingerprint,payload,category,difficulty,created) VALUES(?,?,?,?,0)",-1,&statement,nil)
        let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        _ = QuestionSimilarity.fingerprint(q.text).withCString { sqlite3_bind_text(statement,1,$0,-1,transient) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement,2,$0.baseAddress,Int32(data.count),transient) }
        _ = q.category.rawValue.withCString { sqlite3_bind_text(statement,3,$0,-1,transient) }
        _ = q.difficulty.rawValue.withCString { sqlite3_bind_text(statement,4,$0,-1,transient) }
        XCTAssertEqual(sqlite3_step(statement),SQLITE_DONE); sqlite3_finalize(statement); sqlite3_close(old)
        let database = try QuestionPoolDatabase(url:url)
        try await database.insert(VisualQuestionSeeds.questions,day:"2026-10-29")
        let snapshot = try await database.snapshot(day:"2026-10-29")
        XCTAssertEqual(snapshot.total,13); XCTAssertEqual(snapshot.today,12); XCTAssertEqual(snapshot.visualCounts.values.reduce(0,+),12)
        let visuals = try await database.sample(topic:.mixed,difficulty:nil,limit:30,format:.visual)
        XCTAssertEqual(visuals.count,12); XCTAssertTrue(visuals.allSatisfy { $0.visual != nil })
        let texts = try await database.search(text:"",topic:.mixed,difficulty:nil,format:.text)
        XCTAssertEqual(texts.map(\.text),[q.text])
    }
}

extension GenerationRecoveryTests {
    func testVisualOnlyGenerationRejectsTextThenSavesARealVisual() async throws {
        var visual = VisualQuestionSeeds.questions[2]
        visual.optionExplanations = ["35 ile 20'nin farkı 15'tir.","20 fark değil, K'nin sıcaklığıdır.","35 fark değil, L'nin sıcaklığıdır.","5 bu çıkarma işleminin sonucu değildir."]
        let transport = ScriptedQuestionTransport([try json([question(1)]),try json([visual])])
        let result = try await AIService(gateway:gateway(transport)).questions(topic:.science,detail:"",difficulty:.easy,count:1,models:["model-a"],excluding:[],format:.visual,progress:{ _,_,_ in })
        XCTAssertEqual(result.count,1); XCTAssertEqual(result[0].visual,visual.visual)
        let calls = await transport.count(); XCTAssertEqual(calls,2)
    }
}
