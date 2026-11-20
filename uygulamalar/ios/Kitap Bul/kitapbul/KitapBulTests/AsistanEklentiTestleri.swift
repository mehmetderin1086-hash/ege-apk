import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct AsistanEklentiTestleri {
    private func baglam() throws -> ModelContext {
        ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
    }

    @Test func duzenlemeNiyetiOzetlenirVeUygulanir() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Eski Atlas", author: "X", category: "Diğer", quantity: 2))
        ctx.insert(kitap)
        try ctx.save()

        #expect(!BookEditIntent(bookTitle: "Eski Atlas").hasChange)
        let niyet = BookEditIntent(bookTitle: "Eski Atlas", withdraw: true, withdrawReason: "Yıpranmış",
                                   cabinet: "C", shelf: "4", readingStatus: "Okundu", category: "Coğrafya", quantity: 0)
        #expect(niyet.hasChange)
        #expect(niyet.changeLines.count == 6)

        let metin = try BookEditEngine.apply(niyet, to: kitap, context: ctx)
        #expect(kitap.isWithdrawn)
        #expect(kitap.withdrawnReason == "Yıpranmış")
        #expect(kitap.cabinet == "C" && kitap.shelf == "4")
        #expect(kitap.readingStatus == "Okundu")
        #expect(kitap.category == "Coğrafya")
        #expect(kitap.quantity == 1)   // 0 adet → en az 1
        #expect(metin.contains("Eski Atlas"))
    }

    @Test func gecersizOkumaDurumuYazilmaz() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "A", author: "", readingStatus: "Okunacak"))
        ctx.insert(kitap)
        _ = try BookEditEngine.apply(BookEditIntent(readingStatus: "Belki"), to: kitap, context: ctx)
        #expect(kitap.readingStatus == "Okunacak")
    }

    @Test func grafikTemizlenir() {
        let tek = AssistantChart(title: "x", bars: [.init(label: "Roman", value: 3)])
        #expect(tek.sanitized == nil)
        let bozuk = AssistantChart(title: "Kategoriler", bars: [
            .init(label: "Roman", value: 10), .init(label: " ", value: 2),
            .init(label: "Bilim", value: -1), .init(label: "Tarih", value: .nan), .init(label: "Şiir", value: 4)
        ])
        #expect(bozuk.sanitized?.bars.map(\.label) == ["Roman", "Şiir"])
        let cok = AssistantChart(title: nil, bars: (0..<20).map { .init(label: "\($0)", value: Double($0)) })
        #expect(cok.sanitized?.bars.count == 12)
    }

    @Test func yeniYanitAlanlariCozulur() throws {
        let json = """
        {"answer": "Tamam", "action": {"type": "addBooks", "books": [{"title": "A"}, {"title": "B", "quantity": 2}]},
         "chart": {"title": "Kategoriler", "bars": [{"label": "Roman", "value": 5}, {"label": "Şiir", "value": 2}]}}
        """
        let yanit = try JSONDecoder().decode(AssistantReply.self, from: Data(json.utf8))
        #expect(yanit.action?.books?.count == 2)
        #expect(yanit.chart?.bars.count == 2)

        let duzen = """
        {"answer": "Taşıyayım mı?", "action": {"type": "editBook", "edit": {"bookTitle": "Nutuk", "cabinet": "B", "shelf": "3"}}}
        """
        let yanit2 = try JSONDecoder().decode(AssistantReply.self, from: Data(duzen.utf8))
        #expect(yanit2.action?.edit?.cabinet == "B")
        #expect(yanit2.action?.edit?.hasChange == true)
    }

    @Test func sohbetGecmisiSaklanir() {
        let dosya = FileManager.default.temporaryDirectory.appendingPathComponent("sohbet-\(UUID()).json")
        ChatHistoryStore.fileOverride = dosya
        defer {
            ChatHistoryStore.fileOverride = nil
            try? FileManager.default.removeItem(at: dosya)
        }
        var mesajlar = (0..<120).map { ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "m\($0)") }
        mesajlar.append(ChatMessage(role: .assistant, text: "hata", isError: true))
        ChatHistoryStore.save(mesajlar)
        let geri = ChatHistoryStore.load()
        #expect(geri.count == ChatHistoryStore.maxMessages)
        #expect(geri.last?.text == "m119")
        #expect(!geri.contains { $0.text == "hata" })
        ChatHistoryStore.clear()
        #expect(ChatHistoryStore.load().isEmpty)
    }

    @Test func favoriSorularAcilipKapanir() {
        let soru = "Test favori \(UUID())"
        #expect(!FavoritePromptStore.contains(soru))
        FavoritePromptStore.toggle(soru)
        #expect(FavoritePromptStore.all().first == soru)
        FavoritePromptStore.toggle(soru)
        #expect(!FavoritePromptStore.contains(soru))
    }

    @Test func asistanDiliVarsayilanTurkce() {
        let eski = UserDefaults.standard.string(forKey: AsistanDili.key)
        defer { UserDefaults.standard.set(eski, forKey: AsistanDili.key) }
        UserDefaults.standard.removeObject(forKey: AsistanDili.key)
        #expect(AsistanDili.current == .turkce)
        UserDefaults.standard.set("en-US", forKey: AsistanDili.key)
        #expect(AsistanDili.current == .ingilizce)
        UserDefaults.standard.set("xx", forKey: AsistanDili.key)
        #expect(AsistanDili.current == .turkce)
    }

    @Test func kisayolAramasiYerVeBostaSoyler() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali", quantity: 2, shelf: "3", cabinet: "B"))
        let dusulmus = CatalogBook(book: Book(title: "Kürk Mantolu Madonna (eski)", author: "Sabahattin Ali", isWithdrawn: true))
        ctx.insert(kitap)
        ctx.insert(dusulmus)
        ctx.insert(ActiveLoan(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: "Ali", studentClass: "7-A", dueDate: .now))
        try ctx.save()

        let bulunan = try IntentVeri.bul("kurk mantolu", context: ctx)
        #expect(bulunan.map(\.title) == ["Kürk Mantolu Madonna"])
        let loans = try ctx.fetch(FetchDescriptor<ActiveLoan>())
        let durum = IntentVeri.durum(kitap, loans: loans)
        #expect(durum.contains("Dolap B"))
        #expect(durum.contains("1 nüsha verilebilir"))
        #expect(try IntentVeri.bul("   ", context: ctx).isEmpty)
    }

    @Test func bekleyenTaslakSiniriAsincaDaKimligiyleSaklanir() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pending-chat-\(UUID()).json")
        ChatHistoryStore.fileOverride = file
        defer { ChatHistoryStore.fileOverride = nil; try? FileManager.default.removeItem(at: file) }
        var draft = SesliKitapKaydi(); draft.title = "Tekrar denenecek eser"; draft.quantity = 2
        var pending = ChatMessage(role: .assistant, text: "Kısmi sonuç", isError: true)
        pending.proposedBooks = [draft]; pending.proposedOperationIDs = [UUID()]
        let messages = [pending] + (0..<120).map { ChatMessage(role: .user, text: "soru \($0)") }
        try ChatHistoryStore.saveVerified(messages)
        let restored = try ChatHistoryStore.loadVerified().map(\.message)
        #expect(restored.count == ChatHistoryStore.maxMessages + 1)
        let savedDraft = try #require(restored.first { $0.id == pending.id })
        #expect(savedDraft.proposedBooks == [draft])
        #expect(savedDraft.proposedOperationIDs == pending.proposedOperationIDs)
        #expect(savedDraft.hasPendingProposal && savedDraft.proposalNeedsReview)
    }

    @Test func oduncVeDuzenlemeTaslaklariAyniKimlikleGeriGelir() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("loan-chat-\(UUID()).json")
        ChatHistoryStore.fileOverride = file
        defer { ChatHistoryStore.fileOverride = nil; try? FileManager.default.removeItem(at: file) }
        var loan = ChatMessage(role: .assistant, text: "İadeyi onaylayın")
        loan.proposedLoan = LoanProposal(kind: "return", bookID: UUID(), bookTitle: "Eser", person: "Okur", className: "7/A", studentID: UUID(), copyID: UUID(), loanID: UUID())
        var edit = ChatMessage(role: .assistant, text: "Yer değişikliği")
        edit.proposedEdit = EditProposal(bookID: UUID(), bookTitle: "Eser", intent: BookEditIntent(cabinet: "C"))
        var choice = ChatMessage(role: .assistant, text: "Hedef seçin")
        choice.proposedTargetChoice = AssistantTargetChoice(bookIDs: [UUID(), UUID()], loan: LoanIntent(kind: "lend"), person: "Okur")
        try ChatHistoryStore.saveVerified([loan, edit, choice])
        let restored = try ChatHistoryStore.loadVerified().map(\.message)
        #expect(restored.map(\.id) == [loan.id, edit.id, choice.id])
        #expect(restored[0].proposedLoan == loan.proposedLoan)
        #expect(restored[1].proposedEdit == edit.proposedEdit)
        #expect(restored[2].proposedTargetChoice == choice.proposedTargetChoice)
        #expect(restored.allSatisfy { $0.proposalNeedsReview })
    }

    @Test func sohbetDosyasiHatalariBosGecmisGibiYutulmaz() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bad-chat-\(UUID())")
        let file = folder.appendingPathComponent("chat.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ChatHistoryStore.fileOverride = file
        defer { ChatHistoryStore.fileOverride = nil; try? FileManager.default.removeItem(at: folder) }
        try Data("bozuk JSON".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ChatHistoryStore.loadVerified() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "bozuk JSON")
        ChatHistoryStore.fileOverride = folder
        #expect(throws: (any Error).self) { try ChatHistoryStore.saveVerified([ChatMessage(role: .user, text: "soru")]) }
    }

    @Test func baskiKaydirmasiHerIkiSayfaKenarindaGuvenliPayBirakir() {
        for margin in [4.0, 10.0, 24.0, Double.nan, Double.infinity, -100] {
            for offset in [-100.0, 100.0, Double.nan, Double.infinity] {
                var profile = LibraryPrintProfile(); profile.marginMM = margin
                profile.offsetXMM = offset; profile.offsetYMM = offset
                let safe = profile.normalized
                #expect(safe.marginMM.isFinite && safe.offsetXMM.isFinite && safe.offsetYMM.isFinite)
                let minimumMargin = profile.margin - max(abs(profile.offset.width), abs(profile.offset.height))
                #expect(minimumMargin >= 2 * 72 / 25.4 - 0.0001)
                #expect(safe == safe.normalized)
            }
        }
    }

}
