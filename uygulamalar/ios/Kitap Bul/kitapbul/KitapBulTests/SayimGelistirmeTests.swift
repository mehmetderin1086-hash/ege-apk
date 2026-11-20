import Testing
import Foundation
import SwiftData
import PDFKit
@testable import _01

/// Sayım ve raporlar paketi: iki dosyalı oturum, okutma sonuçları, tutanak, alan bakımı fişleri, rapor hazırlama.
@MainActor
@Suite(.serialized)
struct SayimGelistirmeTests {
    // MARK: Yardımcılar

    private func isolated(_ work: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sayim-gelistirme-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldInventory = InventorySessionStore.directoryOverride, oldActions = InventoryActionStore.directoryOverride
        let oldFields = FieldMaintenanceStore.directoryOverride, oldSupport = ArchiveSettings.directoryOverride
        InventorySessionStore.directoryOverride = directory; InventoryActionStore.directoryOverride = directory
        FieldMaintenanceStore.directoryOverride = directory; ArchiveSettings.directoryOverride = directory
        defer {
            InventorySessionStore.directoryOverride = oldInventory; InventoryActionStore.directoryOverride = oldActions
            FieldMaintenanceStore.directoryOverride = oldFields; ArchiveSettings.directoryOverride = oldSupport
            try? FileManager.default.removeItem(at: directory)
        }
        try work(directory)
    }

    private func isbn13(_ n: Int) -> String {
        let body = "978" + String(format: "%09d", n)
        let sum = body.compactMap(\.wholeNumberValue).enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        return body + String((10 - sum % 10) % 10)
    }

    private func item(_ title: String, isbn: String?, quantity: Int = 1, id: UUID = UUID(),
                      copies: [InventoryCopySnapshot] = [], location: String? = nil) -> InventoryExpectedItem {
        var stock = LibraryStock(); stock.total = quantity; stock.available = quantity
        return InventoryExpectedItem(id: id, title: title, author: "Y", isbn: isbn, quantity: quantity, location: location, stock: stock, copies: copies)
    }

    private static var tutulanKaplar: [ModelContainer] = []

    private func newContext() throws -> (ModelContainer, ModelContext) {
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        // mainContext kabı zayıf tutar; kap test boyunca yaşamalı (yoksa SwiftData askıda kalır).
        Self.tutulanKaplar.append(container)
        let context = container.mainContext
        context.autosaveEnabled = false
        return (container, context)
    }

    // MARK: İki dosyalı oturum

    @Test func beklentiBirKezYazilirOkutmaJsonlaTekSatirEklenir() throws {
        try isolated { directory in
            let katalog = (0..<400).map { item("Kitap \($0)", isbn: isbn13($0)) }
            let durum = SayimDurumu(); durum.operatorName = "Görevli"
            #expect(durum.baslat(expected: katalog, catalog: katalog))
            let beklenti = directory.appendingPathComponent(InventorySessionStore.expectationFileName)
            let okutmalar = directory.appendingPathComponent(InventorySessionStore.scansFileName)
            let beklentiVeri = try Data(contentsOf: beklenti)
            #expect(beklentiVeri.count > 40_000)
            #expect(!FileManager.default.fileExists(atPath: okutmalar.path))

            #expect(durum.record(isbn13(3), baslat: { true }) == .sayildi)
            #expect(durum.flush())
            let bir = try Data(contentsOf: okutmalar)
            #expect(bir.filter { $0 == 0x0A }.count == 1)
            #expect(bir.count < 600)
            #expect(durum.record(isbn13(4), baslat: { true }) == .sayildi)
            #expect(durum.flush())
            #expect(try Data(contentsOf: beklenti) == beklentiVeri)
            #expect(try Data(contentsOf: okutmalar).filter { $0 == 0x0A }.count == 2)

            let acilan = try InventorySessionStore.openSession()
            #expect(!acilan.migrated && !acilan.tailDropped)
            #expect(acilan.session.expected?.count == 400)
            #expect(acilan.session.scanned == [isbn13(3): 1, isbn13(4): 1])
        }
    }

    @Test func beklentiMuhruBozulmaVeKesilmeyiYakalar() throws {
        try isolated { directory in
            let katalog = [item("Kitap", isbn: isbn13(1))]
            let durum = SayimDurumu(); durum.operatorName = "G"
            #expect(durum.baslat(expected: katalog, catalog: katalog))
            let url = directory.appendingPathComponent(InventorySessionStore.expectationFileName)
            let saglam = try Data(contentsOf: url)
            #expect(try InventorySeal.unseal(saglam).count > 0)
            var bozuk = saglam
            bozuk[bozuk.count / 2] = bozuk[bozuk.count / 2] == 0x41 ? 0x42 : 0x41
            #expect(throws: (any Error).self) { try InventorySeal.unseal(bozuk) }
            #expect(throws: (any Error).self) { try InventorySeal.unseal(saglam.dropLast(5)) }
            // Bozuk beklenti sessizce üzerine yazılmaz
            try bozuk.write(to: url)
            let yeni = SayimDurumu(); yeni.operatorName = "G"
            #expect(!yeni.baslat(expected: katalog, catalog: katalog))
            #expect(try Data(contentsOf: url) == bozuk)
        }
    }

    @Test func bozukSonSatirAtilirVeKurtarilamadiBayragiDoner() throws {
        try isolated { directory in
            let katalog = (0..<10).map { item("Kitap \($0)", isbn: isbn13($0)) }
            let durum = SayimDurumu(); durum.operatorName = "G"
            #expect(durum.baslat(expected: katalog, catalog: katalog))
            durum.record(isbn13(1), baslat: { true }); durum.record(isbn13(2), baslat: { true })
            #expect(durum.flush())
            let okutmalar = directory.appendingPathComponent(InventorySessionStore.scansFileName)
            let handle = try FileHandle(forWritingTo: okutmalar)
            try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"t\":\"scan\",\"key\":\"9786".utf8)); try handle.close()

            let acilan = try InventorySessionStore.openSession()
            #expect(acilan.tailDropped)
            #expect(acilan.session.scanned.values.reduce(0, +) == 2)
            let yeni = SayimDurumu(); yeni.uygula(acilan)
            #expect(yeni.sonOkutmaKurtarilamadi)
            #expect(yeni.bildirim?.contains("kurtarılamadı") == true)
            // Kesilen kuyruğun üstüne yeni satır temiz eklenir
            yeni.record(isbn13(5), baslat: { true })
            #expect(yeni.flush())
            let tekrar = try InventorySessionStore.openSession()
            #expect(!tekrar.tailDropped)
            #expect(tekrar.session.scanned.values.reduce(0, +) == 3)
        }
    }

    @Test func ortadakiBozukSatirOturumuAcmazVeDosyayiKorur() throws {
        try isolated { directory in
            let katalog = [item("Kitap", isbn: isbn13(1))]
            let durum = SayimDurumu(); durum.operatorName = "G"
            #expect(durum.baslat(expected: katalog, catalog: katalog))
            let okutmalar = directory.appendingPathComponent(InventorySessionStore.scansFileName)
            let iyi = try InventoryLog.encode(.init(t: .scan, key: isbn13(1)))
            var veri = iyi; veri.append(Data("bozuk satır\n".utf8)); veri.append(iyi)
            try veri.write(to: okutmalar)
            #expect(throws: (any Error).self) { try InventorySessionStore.openSession() }
            #expect(try Data(contentsOf: okutmalar) == veri)
        }
    }

    @Test func eskiTekDosyaOturumuOkunurVeBirKezGocEder() throws {
        try isolated { directory in
            let katalog = [item("Kitap", isbn: isbn13(1), quantity: 2)]
            let gozlem = InventoryObservation(bookID: katalog[0].id, operatorName: "G", method: "ISBN", observedLocation: "Salon", outsideScope: false)
            let eski = InventorySession(scanned: [isbn13(1): 2], unknown: ["kayıtsız": 1], location: "Salon",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000), expected: katalog, name: "Eski sayım",
                operatorName: "G", method: "ISBN nüsha sayımı", observations: [gozlem], catalogSnapshot: katalog)
            try InventorySessionStore.saveVerified(eski)
            let eskiURL = directory.appendingPathComponent(InventorySessionStore.legacyFileName)
            #expect(FileManager.default.fileExists(atPath: eskiURL.path))
            // Göçten önce de okunabilir
            #expect(try InventorySessionStore.loadVerified().name == "Eski sayım")

            let acilan = try InventorySessionStore.openSession()
            #expect(acilan.migrated)
            #expect(acilan.session.scanned == [isbn13(1): 2] && acilan.session.unknown == ["kayıtsız": 1])
            #expect(acilan.session.location == "Salon" && acilan.session.name == "Eski sayım")
            #expect(acilan.session.observations?.count == 1 && acilan.session.expected?.count == 1)
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(InventorySessionStore.expectationFileName).path))
            #expect(!FileManager.default.fileExists(atPath: eskiURL.path))
            #expect(FileManager.default.fileExists(atPath: eskiURL.appendingPathExtension("eski").path))

            let ikinci = try InventorySessionStore.openSession()
            #expect(!ikinci.migrated)
            #expect(ikinci.session.scanned == [isbn13(1): 2] && ikinci.session.unknown == ["kayıtsız": 1])
            #expect(try InventorySessionStore.loadVerified().scanned == [isbn13(1): 2])

            try InventorySessionStore.clearVerified()
            #expect(try InventorySessionStore.openSession().session.scanned.isEmpty)
        }
    }

    // MARK: Okutma sonuçları

    @Test func okutmaSonucuBesDaliVeGeriAlSayaciDusurur() throws {
        try isolated { _ in
            let kitapA = UUID()
            let kopya = InventoryCopySnapshot(id: UUID(), bookID: kitapA, accessionCode: "D-1")
            let a = item("A", isbn: isbn13(1), id: kitapA, copies: [kopya])
            let b = item("B", isbn: isbn13(2))
            let durum = SayimDurumu(); durum.operatorName = "G"
            #expect(durum.baslat(expected: [a], catalog: [a, b]))

            #expect(durum.record("D-1", baslat: { true }) == .sayildi)
            #expect(durum.record("D-1", baslat: { true }) == .reddedildi("Bu demirbaş zaten sayıldı: D-1"))
            #expect(durum.record(isbn13(2), baslat: { true }) == .baskaRaf)
            #expect(durum.record(isbn13(9), baslat: { true }) == .kayitsiz)
            #expect(durum.record("ACE", baslat: { true }) == .kayitsiz)
            #expect(durum.scannedCounts["copy:" + kopya.id.uuidString] == 1)
            #expect(durum.unknownCounts[isbn13(9)] == 1 && durum.unknownCounts["ACE"] == 1)
            #expect(durum.sonOkutmalar.count == 5)

            // Geri al: kayıtsız barkod, sonra liste dışı kitap düşer; gözlem de silinir
            let gozlemSayisi = durum.observations.count
            #expect(durum.geriAl())
            #expect(durum.unknownCounts["ACE"] == nil)
            #expect(durum.geriAl() && durum.geriAl())
            #expect(durum.unknownCounts.isEmpty && durum.scannedCounts["outside:" + b.id.uuidString] == nil)
            #expect(durum.observations.count == gozlemSayisi - 1)
            #expect(durum.flush())
            let acilan = try InventorySessionStore.openSession()
            #expect(acilan.session.scanned == ["copy:" + kopya.id.uuidString: 1] && acilan.session.unknown.isEmpty)
            #expect(acilan.session.observations?.count == 1)
        }
    }

    @Test func benzersizDemirbasKipindeEslesmeyenBarkodReddedilir() throws {
        try isolated { _ in
            let a = item("A", isbn: isbn13(1))
            let durum = SayimDurumu(); durum.operatorName = "G"; durum.method = "Benzersiz demirbaş"
            #expect(durum.baslat(expected: [a], catalog: [a]))
            let sonuc = durum.record(isbn13(1), baslat: { true })
            guard case .reddedildi = sonuc else { Issue.record("Reddedilmeliydi: \(sonuc)"); return }
            #expect(durum.scannedCounts.isEmpty)
        }
    }

    @Test func kaydedilemeyenOkutmaKaydedilemediDoner() throws {
        try isolated { directory in
            let a = item("A", isbn: isbn13(1))
            // Başlatma yazılamıyor: üst yol bir dosya
            let dosya = directory.appendingPathComponent("dosya"); try Data("x".utf8).write(to: dosya)
            let saglam = directory
            InventorySessionStore.directoryOverride = dosya.appendingPathComponent("alt")
            let yeni = SayimDurumu(); yeni.operatorName = "G"
            #expect(yeni.record(isbn13(1), baslat: { yeni.baslat(expected: [a], catalog: [a]) }) == .kaydedilemedi)
            #expect(!yeni.hasSnapshot)

            // Okutma günlüğü yazılamıyor: ilk satır bellekte kalır, sonraki okutma kaydedilemedi döner
            InventorySessionStore.directoryOverride = saglam
            let durum = SayimDurumu(); durum.operatorName = "G"
            #expect(durum.baslat(expected: [a], catalog: [a]))
            #expect(durum.record(isbn13(1), baslat: { true }) == .sayildi)
            InventorySessionStore.directoryOverride = dosya.appendingPathComponent("alt")
            #expect(!durum.flush())
            #expect(durum.record(isbn13(1), baslat: { true }) == .kaydedilemedi)
            // Dizin düzelince bekleyen iki satır birlikte yazılır
            InventorySessionStore.directoryOverride = saglam
            #expect(durum.flush())
            #expect(try InventorySessionStore.openSession().session.scanned == [isbn13(1): 2])
        }
    }

    @Test func sayimDurumuAyniGirdideYenidenHesaplanmaz() throws {
        let katalog = (0..<50).map { item("Kitap \($0)", isbn: isbn13($0)) }
        let durum = SayimDurumu()
        durum.uygula(InventoryOpenResult(session: InventorySession(expected: katalog, name: "S", operatorName: "G"),
                                         undo: [], tailDropped: false, migrated: false))
        let once = durum.hesaplamaSayisi
        for _ in 0..<20 {
            _ = (durum.countEntries.count, durum.missingEntries.count, durum.surplusEntries.count, durum.expectedTotal,
                 durum.matchedTotal, durum.barcodelessBooks.count, durum.statusBooks.count)
        }
        #expect(durum.hesaplamaSayisi == once)
        #expect(durum.expectedTotal == 50 && durum.missingEntries.count == 50)

        // Önizleme: aynı kapsam ve kaynak sayısıyla ikinci çağrı yeniden hesaplamaz
        let onizleme = SayimDurumu()
        onizleme.onizlemeyiYenile(books: [], loans: [], copies: [], reservations: [])
        let ilk = onizleme.hesaplamaSayisi
        onizleme.onizlemeyiYenile(books: [], loans: [], copies: [], reservations: [])
        #expect(onizleme.hesaplamaSayisi == ilk)
    }

    @Test func ilerlemeYuzdeHizVeSureHesaplar() {
        let kitap = item("Kitap", isbn: isbn13(1), quantity: 4, location: "Dolap A · Raf 1")
        let girdi = InventoryCountEntry(book: kitap, expected: 4, scanned: 2, identifiedCopies: 0, manualCopies: 0, isbnCopies: 2)
        let baslangic = Date(timeIntervalSince1970: 1_700_000_000)
        let gozlemler = (0..<3).map {
            var gozlem = InventoryObservation(bookID: kitap.id, operatorName: "G", method: "ISBN", observedLocation: "Tümü", outsideScope: false)
            gozlem.observedAt = baslangic.addingTimeInterval(Double($0) * 30)
            return gozlem
        }
        let ilerleme = SayimIlerleme.hesapla(entries: [girdi], observations: gozlemler, startedAt: baslangic)
        #expect(ilerleme.okutulan == 2 && ilerleme.beklenen == 4 && ilerleme.yuzde == 50)
        #expect(ilerleme.dakikadaOkutma == 2)
        #expect(ilerleme.konumlar == [.init(ad: "Dolap A · Raf 1", beklenen: 4, okutulan: 2)])
        #expect(SayimIlerleme.sureMetni(4320) == "1 sa 12 dk" && SayimIlerleme.sureMetni(45 * 60) == "45 dk")
    }

    // MARK: Eser yeri

    @Test func eserYeriGenelKonumDolapRafVeBosDurumlari() {
        let salon = CatalogBook(book: Book(title: "Salon", author: "Y", location: "Salon", quantity: 2))
        let dolap = CatalogBook(book: Book(title: "Dolap", author: "Y", quantity: 3, shelf: "1", cabinet: "A"))
        let yersiz = CatalogBook(book: Book(title: "Yersiz", author: "Y", quantity: 1))
        #expect(InventorySnapshot.eserYeri(salon) == "Salon")
        #expect(InventorySnapshot.eserYeri(dolap) == "Dolap A · Raf 1")
        #expect(InventorySnapshot.eserYeri(yersiz) == "")

        let kapsam = InventorySnapshot.capture(books: [salon, dolap, yersiz], loans: [], copies: [], reservations: [], location: "Dolap A · Raf 1")
        #expect(kapsam.map(\.title) == ["Dolap"])
        #expect(kapsam.first?.stock.total == 3 && kapsam.first?.stock.available == 3)
        let hepsi = InventorySnapshot.capture(books: [salon, dolap, yersiz], loans: [], copies: [], reservations: [], location: "Tümü")
        #expect(hepsi.count == 3)
    }

    // MARK: Tutanak

    private func tutanakGirdisi() -> SayimTutanakGirdisi {
        let kitap = item("=1+1", isbn: isbn13(1), quantity: 2)
        let girdi = InventoryCountEntry(book: kitap, expected: 2, scanned: 1, identifiedCopies: 0, manualCopies: 0, isbnCopies: 1)
        return SayimTutanakGirdisi(
            oturum: "Ekim sayımı", gorevli: "Şule", yontem: "ISBN nüsha sayımı", kapsam: "Tümü",
            baslangic: Date(timeIntervalSince1970: 1_700_000_000), uretim: Date(timeIntervalSince1970: 1_700_003_600),
            beklenenToplam: 2, okutulanToplam: 1, listeDisiToplam: 1, sabitlendi: true,
            durumKitaplari: [[], [], [], []], belirsiz: [], baskaRaf: [], sayilan: [girdi], eksik: [girdi], fazla: [],
            kayitsiz: [("978;123", 1)], barkodsuz: [], okul: "Örnek Okul", komisyon: ["Ayşe Yılmaz"], sonrasi: [])
    }

    @Test func tutanakCSVFormulKorumasiliVeNoktaliVirgullBarkodGuvenli() {
        let girdi = tutanakGirdisi()
        let csv = String(decoding: SayimTutanagi.uret(girdi, bicim: .csv), as: UTF8.self)
        #expect(csv.contains("\"'=1+1\""))
        #expect(csv.contains("\"978;123\""))
        #expect(csv.contains("\r\n"))
        #expect(csv.hasPrefix("\u{FEFF}"))
    }

    @Test func tutanakCSVXLSXVePDFAyniSatirlariVerir() throws {
        let girdi = tutanakGirdisi()
        let tablolar = SayimTutanagi.tablolar(girdi)
        #expect(tablolar.count == 8)
        #expect(tablolar.map(\.sayfa.name).prefix(4) == ["Özet", "Sayılan", "Eksik", "Fazla"])
        let toplamSatir = tablolar.reduce(0) { $0 + $1.sayfa.rows.count }
        // Her tablonun veri satırı PDF bölümüyle aynı
        for tablo in tablolar { #expect(tablo.satirSayisi == tablo.pdf.count || tablo.sayfa.name == "Özet") }
        #expect(tablolar[0].pdf.count == tablolar[0].satirSayisi)

        let csv = String(decoding: SayimTutanagi.uret(girdi, bicim: .csv), as: UTF8.self)
        #expect(csv.components(separatedBy: "\r\n").count == toplamSatir + tablolar.count + (tablolar.count - 1))

        let girdiler = ZIPReader.entries(in: SayimTutanagi.uret(girdi, bicim: .excel))
        let sayfalar = girdiler.filter { $0.name.hasPrefix("xl/worksheets/sheet") }
        #expect(sayfalar.count == tablolar.count)
        let xmlSatir = sayfalar.reduce(0) { $0 + String(decoding: $1.data, as: UTF8.self).components(separatedBy: "<row ").count - 1 }
        #expect(xmlSatir == toplamSatir)
        let ozet = String(decoding: try #require(girdiler.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        #expect(ozet.contains("t=\"n\"><v>2</v>"))
        #expect(ozet.contains("s=\"1\" t=\"n\""))
        #expect(girdiler.contains { $0.name == "xl/styles.xml" })
        let kitapSayfasi = String(decoding: try #require(girdiler.first { $0.name == "xl/worksheets/sheet2.xml" }).data, as: UTF8.self)
        #expect(kitapSayfasi.contains("=1+1") && kitapSayfasi.contains("t=\"inlineStr\""))

        let pdf = try #require(PDFDocument(data: SayimTutanagi.uret(girdi, bicim: .pdf)))
        #expect(pdf.pageCount >= 1)
        #expect(pdf.string?.contains("Beklenen") == true)
    }

    @Test func excelCokSayfaliVeTekSayfaliCiktiyiKorur() throws {
        let tek = ZIPReader.entries(in: ReportTableExporter.excel([["Bölüm", "Değer"], ["A", "1"]]))
        #expect(tek.contains { $0.name == "xl/worksheets/sheet1.xml" } && !tek.contains { $0.name == "xl/styles.xml" })
        let metin = String(decoding: try #require(tek.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        #expect(metin.contains("t=\"inlineStr\"") && !metin.contains("t=\"n\""))
        let calisma = String(decoding: try #require(tek.first { $0.name == "xl/workbook.xml" }).data, as: UTF8.self)
        #expect(calisma.contains("Dönem Raporu"))

        let cok = ZIPReader.entries(in: ReportTableExporter.excel(sheets: [
            .init(name: "Aynı", rows: [[.text("a"), .number(3.5)]]), .init(name: "aynı", rows: [[.int(7)]])]))
        let kitap = String(decoding: try #require(cok.first { $0.name == "xl/workbook.xml" }).data, as: UTF8.self)
        #expect(kitap.contains("name=\"Aynı\"") && kitap.contains("name=\"aynı 2\""))
        #expect(String(decoding: try #require(cok.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self).contains("<v>3.5</v>"))
    }

    // MARK: Alan bakımı fişleri

    @Test func uyusmayanFisIncelenecekOlurDigerFisIslenirVeKararVerilir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let bir = CatalogBook(book: Book(title: "Bir", author: "Y", publisher: "Eski"))
            let iki = CatalogBook(book: Book(title: "İki", author: "Y", publisher: "Eski2"))
            context.insert(bir); context.insert(iki); try context.save()
            let uygun = FieldMaintenanceReceipt(field: .publisher, changes: [
                .init(bookID: bir.id, title: bir.title, before: "Eski", after: "Yeni", beforeEvidence: nil, afterEvidence: nil)])
            let uyusmayan = FieldMaintenanceReceipt(field: .publisher, changes: [
                .init(bookID: iki.id, title: iki.title, before: "Başka", after: "Yeni", beforeEvidence: nil, afterEvidence: nil)])
            try FieldMaintenanceStore.replaceVerified([uygun, uyusmayan])

            let sonuc = try FieldMaintenanceService.reconcile(context: context)
            #expect(sonuc.first { $0.id == uygun.id }?.state == .cancelled)
            let incelenecek = try #require(sonuc.first { $0.id == uyusmayan.id })
            #expect(incelenecek.state == .needsReview && incelenecek.reviewOrigin == .prepared)
            #expect(try FieldMaintenanceService.pendingReviews(context: context).map(\.id) == [uyusmayan.id])
            // Kitap kayıtlarına dokunulmaz
            #expect(bir.publisher == "Eski" && iki.publisher == "Eski2")

            let karar = try FieldMaintenanceService.resolveReview(receiptID: uyusmayan.id, applied: false, context: context)
            #expect(karar.state == .cancelled && karar.reviewOrigin == nil)
            #expect(try FieldMaintenanceService.pendingReviews(context: context).isEmpty)
        }
    }

    @Test func needsReviewArsivBirlesiminde_korunur() throws {
        var inceleme = FieldMaintenanceReceipt(field: .author, changes: [
            .init(bookID: UUID(), title: "Kitap", before: "A", after: "B", beforeEvidence: nil, afterEvidence: nil)])
        inceleme.state = .needsReview; inceleme.reviewOrigin = .prepared
        var bekleyen = inceleme; bekleyen.state = .prepared; bekleyen.reviewOrigin = nil
        var sonuclanan = inceleme; sonuclanan.state = .committed; sonuclanan.reviewOrigin = nil

        let incelemeVeri = try FieldMaintenanceStore.encode([inceleme])
        let birlesim = try FieldMaintenanceStore.validate(FieldMaintenanceStore.merge(existing: incelemeVeri, incoming: FieldMaintenanceStore.encode([bekleyen])))
        #expect(birlesim.first?.state == .needsReview)
        let ters = try FieldMaintenanceStore.validate(FieldMaintenanceStore.merge(existing: FieldMaintenanceStore.encode([bekleyen]), incoming: incelemeVeri))
        #expect(ters.first?.state == .needsReview)
        let cozulmus = try FieldMaintenanceStore.validate(FieldMaintenanceStore.merge(existing: incelemeVeri, incoming: FieldMaintenanceStore.encode([sonuclanan])))
        #expect(cozulmus.first?.state == .committed)
        // Başka içerikli aynı kimlik hâlâ çakışmadır
        let farkli = FieldMaintenanceReceipt(id: inceleme.id, createdAt: inceleme.createdAt, field: .author, changes: [
            .init(bookID: UUID(), title: "Başka", before: "A", after: "C", beforeEvidence: nil, afterEvidence: nil)], state: .prepared)
        #expect(throws: FullArchive.ValidationError.self) { try FieldMaintenanceStore.merge(existing: incelemeVeri, incoming: FieldMaintenanceStore.encode([farkli])) }
    }

    // MARK: Rapor grafikleri ve hazırlama

    private func olay(_ tarih: Date, kind: LoanEvent.Kind = .lent) -> LoanEvent {
        LoanEvent(bookID: UUID(), bookTitle: "K", person: "P", kind: kind, date: tarih)
    }

    @Test func aylikSayilarSecilenAralikKadarCubukCizerVeToplamEslesir() throws {
        var takvim = Calendar(identifier: .gregorian); takvim.timeZone = TimeZone(identifier: "UTC")!
        let simdi = try #require(takvim.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let baslangic = try #require(takvim.date(from: DateComponents(year: 2024, month: 7, day: 1)))
        let olaylar = try (0..<24).map { try olay(#require(takvim.date(byAdding: .month, value: -$0, to: simdi))) }
        let aylar = RaporMotoru.aylikSayilar(events: olaylar, eklenmeTarihleri: [], baslangic: baslangic, now: simdi, takvim: takvim)
        #expect(aylar.count == 24)
        #expect(aylar.reduce(0) { $0 + $1.verilen } == olaylar.filter { $0.kind == .lent }.count)
        #expect(aylar.allSatisfy { $0.ayAdedi == 1 && $0.verilen == 1 })

        // 36 aydan uzun aralık çeyrek çeyrek gruplanır ve hareket kaybolmaz
        let uzunBaslangic = try #require(takvim.date(from: DateComponents(year: 2022, month: 2, day: 1)))
        let uzun = try (0..<52).map { try olay(#require(takvim.date(byAdding: .month, value: -$0, to: simdi))) }
        let ceyrekler = RaporMotoru.aylikSayilar(events: uzun, eklenmeTarihleri: [], baslangic: uzunBaslangic, now: simdi, takvim: takvim)
        #expect(ceyrekler.allSatisfy { $0.ayAdedi == 3 })
        #expect(ceyrekler.reduce(0) { $0 + $1.verilen } == uzun.filter { $0.date >= uzunBaslangic }.count)
        #expect(takvim.component(.month, from: ceyrekler[0].ay) % 3 == 1)
    }

    @Test func iptalEdilenRaporHazirlamaDosyaYazmazVeHataVerir() async {
        let gorev = Task { try await RaporHazirlayici.uret(title: "T", subtitle: "S", sections: [], table: [["A"]], signatures: []) }
        gorev.cancel()
        await #expect(throws: CancellationError.self) { try await gorev.value }
    }

    @Test func raporHazirlamaUcDosyayiPaylasimKlasorunePaketler() async throws {
        let paket = try await RaporHazirlayici.uret(title: "RAPOR", subtitle: "Alt", sections: [.init(title: "Bölüm", rows: [("A", "1")])],
                                                    table: [["Bölüm", "Gösterge", "Değer"], ["Bölüm", "A", "1"]], signatures: ["Müdür"])
        defer { GeciciDosya.sil([paket.pdf, paket.csv, paket.excel]) }
        for url in [paket.pdf, paket.csv, paket.excel] {
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url.path.contains("/Paylasim/"))
        }
        #expect(PDFDocument(url: paket.pdf)?.pageCount ?? 0 >= 1)
    }

    @Test func paylasimDosyalariTokenKlasorundeYazilirVeTemizlenir() throws {
        let bir = try #require(GeciciDosya.yaz(Data("a".utf8), ad: "Ogrenci/Raporu.csv"))
        let iki = try #require(KitapCSV.dosya("ad;yazar", ad: "KitapListesi"))
        let uc = try #require(KitapCSV.dosya("ad;yazar", ad: "KitapListesi"))
        defer { GeciciDosya.sil([bir, iki, uc]) }
        #expect(bir.lastPathComponent == "Ogrenci-Raporu.csv")
        #expect(iki.lastPathComponent == "KitapListesi.csv" && uc.lastPathComponent == "KitapListesi.csv")
        #expect(iki.deletingLastPathComponent() != uc.deletingLastPathComponent())
        #expect(iki.path.contains("/Paylasim/"))
        GeciciDosya.sil([bir])
        #expect(!FileManager.default.fileExists(atPath: bir.path))
        #expect(!FileManager.default.fileExists(atPath: bir.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: iki.path))
    }

    // MARK: Konum taşıma ve sayım sonrası işlemler

    private func tasimaOturumu(book: CatalogBook, one: BookCopy, two: BookCopy) -> InventorySession {
        let full = InventorySnapshot.capture(books: [book], loans: [], copies: [one, two], reservations: [], location: "Tümü")
        let atA = InventorySnapshot.capture(books: [book], loans: [], copies: [one, two], reservations: [], location: one.effectivePlace(for: book))
        return InventorySession(scanned: ["copy:" + two.id.uuidString: 1], location: one.effectivePlace(for: book), expected: atA,
            name: "Denetim", operatorName: "Görevli", method: "Benzersiz demirbaş",
            observations: [.init(bookID: book.id, copyID: two.id, operatorName: "Görevli", method: "Demirbaş", observedLocation: "Dolap A · Raf 1", outsideScope: true)],
            catalogSnapshot: full)
    }

    @Test func konumTasimaOncesiSonrasiGosterirBosAlanDevralmaSecilebilirFisleGeriAlinir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "Dolap A · Raf 1", quantity: 2, shelf: "1", cabinet: "A"))
            let one = BookCopy(bookID: book.id, accessionCode: "D-1")
            let two = BookCopy(bookID: book.id, accessionCode: "D-2", cabinet: "B", shelf: "2")
            context.insert(book); context.insert(one); context.insert(two); try context.save()
            let oturum = tasimaOturumu(book: book, one: one, two: two)

            let devralan = try InventoryMoveService.preview(session: oturum, location: "Dolap C", cabinet: "C", shelf: "", context: context)
            let aday = try #require(devralan.candidates.first)
            #expect(aday.beforePlace == "Dolap B · Raf 2" && aday.afterPlace == "Dolap C · Raf 1")
            let bosaltan = try InventoryMoveService.preview(session: oturum, location: "Dolap C", cabinet: "C", shelf: "", context: context, inheritEmpty: false)
            #expect(bosaltan.candidates.first?.afterPlace == "Dolap C")

            let fis = try InventoryMoveService.applyWithReceipt(devralan, selectedIDs: [two.id], context: context)
            #expect(fis.state == .committed && fis.kind == .move)
            #expect(two.cabinet == "C" && two.shelf == nil)
            #expect(try InventoryActionService.latestUndoable(context: context)?.id == fis.id)

            // Fiş günlükten okunur ve geri alma önceki değerleri döndürür
            let okunan = try InventoryActionStore.allVerified()
            #expect(okunan.map(\.id) == [fis.id] && okunan.first?.state == .committed)
            try InventoryActionService.undo(receiptID: fis.id, context: context)
            #expect(two.cabinet == "B" && two.shelf == "2")
            #expect(try InventoryActionStore.allVerified().first?.state == .undone)
        }
    }

    @Test func geriAlmaSonradanDegisenKaydiEzmez() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "Dolap A · Raf 1", quantity: 2, shelf: "1", cabinet: "A"))
            let one = BookCopy(bookID: book.id, accessionCode: "D-1")
            let two = BookCopy(bookID: book.id, accessionCode: "D-2", cabinet: "B", shelf: "2")
            context.insert(book); context.insert(one); context.insert(two); try context.save()
            let oturum = tasimaOturumu(book: book, one: one, two: two)
            let onizleme = try InventoryMoveService.preview(session: oturum, location: "Dolap C", cabinet: "C", shelf: "3", context: context)
            let fis = try InventoryMoveService.applyWithReceipt(onizleme, selectedIDs: [two.id], context: context)
            two.shelf = "9"; try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try InventoryActionService.undo(receiptID: fis.id, context: context) }
            #expect(two.cabinet == "C" && two.shelf == "9")
        }
    }

    @Test func eksikNushalarKayipIsaretlenirOdunctekineDokunulmazGeriAlinir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            let c1 = BookCopy(bookID: book.id, accessionCode: "D-1"), c2 = BookCopy(bookID: book.id, accessionCode: "D-2")
            let c3 = BookCopy(bookID: book.id, accessionCode: "D-3")
            context.insert(book); context.insert(c1); context.insert(c2); context.insert(c3)
            let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: "Eser", studentName: "A", studentClass: "5-A", dueDate: .now.addingTimeInterval(86_400))
            loan.copyID = c3.id
            context.insert(loan); try context.save()
            let snapshot = InventorySnapshot.capture(books: [book], loans: [loan], copies: [c1, c2, c3], reservations: [], location: "Tümü")
            let sayilan = ["copy:" + c1.id.uuidString: 1]
            let girdi = try #require(InventoryCountResult.entries(expected: snapshot, scanned: sayilan).first)
            #expect(girdi.expected == 2 && girdi.scanned == 1)

            let fis = try InventoryActionService.markLost(entries: [girdi], scanned: sayilan, context: context)
            #expect(fis.kind == .markLost && fis.changes.count == 1)
            #expect(c2.status == "Kayıp" && c1.status == "Rafta" && c3.status == "Rafta")

            try InventoryActionService.undo(receiptID: fis.id, context: context)
            #expect(c2.status == "Rafta")
        }
    }

    @Test func nushasizEserdeKayipAdediNotaYazilirFazlaOkutmaYeniNushaAcarVeGeriAlinir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let nushasiz = CatalogBook(book: Book(title: "Adetli", author: "Y", quantity: 3))
            let fazla = CatalogBook(book: Book(title: "Fazla", author: "Y", quantity: 1))
            let kopya = BookCopy(bookID: fazla.id, accessionCode: "F-1")
            context.insert(nushasiz); context.insert(fazla); context.insert(kopya); try context.save()
            let snapshot = InventorySnapshot.capture(books: [nushasiz], loans: [], copies: [], reservations: [], location: "Tümü")
            let girdi = try #require(InventoryCountResult.entries(expected: snapshot, scanned: [:]).first)
            let kayip = try InventoryActionService.markLost(entries: [girdi], scanned: [:], context: context)
            #expect(nushasiz.notes.contains("3 nüsha kayıp adayı"))
            try InventoryActionService.undo(receiptID: kayip.id, context: context)
            #expect(nushasiz.notes.isEmpty)

            let yeni = try InventoryActionService.createSurplusCopy(book: fazla.id, scope: "Dolap A · Raf 2", context: context)
            let kopyalar = try context.fetch(FetchDescriptor<BookCopy>()).filter { $0.bookID == fazla.id }
            #expect(kopyalar.count == 2 && fazla.quantity == 2)
            let olusan = try #require(kopyalar.first { $0.id != kopya.id })
            #expect(olusan.cabinet == "A" && olusan.shelf == "2" && olusan.accessionCode.isEmpty)
            try InventoryActionService.undo(receiptID: yeni.id, context: context)
            #expect(try context.fetch(FetchDescriptor<BookCopy>()).filter { $0.bookID == fazla.id }.count == 1 && fazla.quantity == 1)
        }
    }

    @Test func yarimKalanSayimFisiVerininDurumunaGoreUzlasir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1))
            let copy = BookCopy(bookID: book.id, accessionCode: "D-1")
            context.insert(book); context.insert(copy); try context.save()
            let degisim = InventoryActionChange(bookID: book.id, copyID: copy.id, title: book.title,
                assignments: [.init(key: "copy.status", before: "Rafta", after: "Kayıp")])
            let fis = InventoryActionReceipt(kind: .markLost, title: "Deneme", changes: [degisim])
            try InventoryActionStore.replaceVerified([fis])
            #expect(try InventoryActionService.reconcile(context: context).first?.state == .cancelled)

            try InventoryActionStore.replaceVerified([fis])
            copy.status = "Kayıp"; try context.save()
            #expect(try InventoryActionService.reconcile(context: context).first?.state == .committed)

            try InventoryActionStore.replaceVerified([fis])
            copy.status = "Onarımda"; try context.save()
            #expect(try InventoryActionService.reconcile(context: context).first?.state == .needsReview)
        }
    }

    @Test func kimliksizOduncluEserdeKayipIsaretlemeAtlanir() throws {
        try isolated { _ in
            let (_, context) = try newContext()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 2))
            let c1 = BookCopy(bookID: book.id, accessionCode: "D-1"), c2 = BookCopy(bookID: book.id, accessionCode: "D-2")
            context.insert(book); context.insert(c1); context.insert(c2)
            let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: "Eser", studentName: "A", studentClass: "5-A", dueDate: .now.addingTimeInterval(86_400))
            context.insert(loan); try context.save()
            let snapshot = InventorySnapshot.capture(books: [book], loans: [loan], copies: [c1, c2], reservations: [], location: "Tümü")
            let girdi = try #require(InventoryCountResult.entries(expected: snapshot, scanned: [:]).first)
            #expect(girdi.expected == 1)
            #expect(try InventoryActionService.kimliksizOduncluEserler(entries: [girdi], context: context) == [book.id])
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try InventoryActionService.markLost(entries: [girdi], scanned: [:], context: context)
            }
            #expect(c1.status == "Rafta" && c2.status == "Rafta")
        }
    }
}
