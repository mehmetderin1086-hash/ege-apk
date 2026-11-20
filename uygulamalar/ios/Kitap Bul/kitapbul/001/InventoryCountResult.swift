import Foundation
import Observation

nonisolated struct InventoryCountEntry: Identifiable {
    let book: InventoryExpectedItem
    let expected: Int
    let scanned: Int
    let identifiedCopies: Int
    let manualCopies: Int
    let isbnCopies: Int
    var id: UUID { book.id }
    var statusTitle: String {
        if scanned < expected { return "Eksik \(expected - scanned)" }
        if scanned > expected { return "Fazla \(scanned - expected)" }
        return scanned > 0 ? "Adet eşleşti" : "Rafta beklenmiyor"
    }
    func confidenceNote(hasSnapshot: Bool) -> String {
        if !hasSnapshot { return "Başlangıç listesi sabitlenmemiş; sonuç kesin değildir." }
        if (book.unresolvedLoans ?? 0) > 0 { return "Ödünç nüsha kimliği belirsiz; adet eşleşse de doğrulanmalıdır." }
        if isbnCopies > 0 { return "ISBN ile \(isbnCopies) nüsha sayıldı; aynı nüshanın tekrar okutulması ayırt edilemez." }
        if manualCopies > 0 { return "Elle \(manualCopies) nüsha sayıldı; demirbaş kimliği doğrulanmadı." }
        return "\(identifiedCopies) benzersiz demirbaşla doğrulandı."
    }
}

/// Ekran ve sayım tutanağı aynı ISBN havuzunu tüketir; aynı adedi iki esere yazmaz.
nonisolated enum InventoryCountResult {
    static func entries(expected: [InventoryExpectedItem], scanned: [String: Int]) -> [InventoryCountEntry] {
        let ordered = expected.sorted { $0.id.uuidString < $1.id.uuidString }
        let groups = Dictionary(grouping: ordered.filter { !ISBNFormatter.normalize($0.isbn ?? "").isEmpty }, by: { ISBNFormatter.normalize($0.isbn ?? "") })
        var pooled = scanned.mapValues { max(0, $0) }
        return ordered.map { book in
            let capacity = max(0, book.stock.available + book.stock.reserved)
            // Demirbaş, aynı fiziksel nüshayı ikinci kez saymaz; bozuk eski adet de 1 ile sınırlanır.
            let identified = book.copies.reduce(0) { $0 + min(1, max(0, scanned["copy:" + $1.id.uuidString] ?? 0)) }
            let manual = max(0, scanned["book:" + book.id.uuidString] ?? 0)
            let isbn = ISBNFormatter.normalize(book.isbn ?? "")
            let remaining = isbn.isEmpty ? 0 : pooled[isbn, default: 0]
            let last = groups[isbn]?.last?.id == book.id
            let share = last ? remaining : min(max(0, capacity - identified - manual), remaining)
            if !isbn.isEmpty { pooled[isbn] = max(0, remaining - share) }
            return InventoryCountEntry(book: book, expected: capacity, scanned: identified + manual + share,
                                       identifiedCopies: identified, manualCopies: manual, isbnCopies: share)
        }
    }
    static func search(_ entries: [InventoryCountEntry], query: String) -> [InventoryCountEntry] {
        let normalized = CatalogMatcher.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = normalized.isEmpty ? entries : entries.filter {
            let values = [$0.book.title, $0.book.author, $0.book.isbn ?? ""] + $0.book.copies.map(\.accessionCode)
            return values.contains { CatalogMatcher.normalize($0).contains(normalized) }
        }
        return filtered.sorted { $0.book.title.localizedStandardCompare($1.book.title) == .orderedAscending }
    }
}

// MARK: - Okutma sonucu

/// Tek bir okutmanın sonucu. Tarayıcı titreşimi, sonuç şeridi ve VoiceOver duyurusu buna göre belirlenir.
nonisolated enum SayimSonucu: Equatable, Sendable {
    case sayildi
    case baskaRaf
    case kayitsiz
    case reddedildi(String)
    case kaydedilemedi

    var baslik: String {
        switch self {
        case .sayildi: "Sayıldı"
        case .baskaRaf: "Başka raf"
        case .kayitsiz: "Kayıtsız"
        case .reddedildi: "Reddedildi"
        case .kaydedilemedi: "Kaydedilemedi"
        }
    }
    /// Sayım adedine eklendi mi (tutanakta yer alır).
    var sayilirMi: Bool {
        switch self {
        case .sayildi, .baskaRaf, .kayitsiz: true
        case .reddedildi, .kaydedilemedi: false
        }
    }
    /// Titreşim sınıfı: başarı, uyarı (liste dışı) veya hata.
    var titresim: SayimTitresimi {
        switch self {
        case .sayildi: .basari
        case .baskaRaf, .kayitsiz: .uyari
        case .reddedildi, .kaydedilemedi: .hata
        }
    }
}

nonisolated enum SayimTitresimi: Equatable, Sendable { case basari, uyari, hata }

extension SayimSonucu {
    /// Tarayıcının titreşimi: sayıldı hafif, liste dışı çift, red ve kayıt hatası sert.
    nonisolated var tarayiciGeriBildirimi: ScanFeedback {
        switch titresim { case .basari: .success; case .uyari: .warning; case .hata: .error }
    }
}

/// Sonuç şeridinde görünen son okutmalar (yalnız bellekte).
struct SayimOkutmaKaydi: Identifiable, Equatable {
    let id = UUID()
    let baslik: String
    let sonuc: SayimSonucu
    let mesaj: String
    let saat: Date
}

/// Geri alınabilir bir okutma: sayaç anahtarı ve (varsa) eklenen gözlem.
nonisolated struct InventoryUndoRecord: Equatable {
    var key: String
    var unknown: Bool
    var observationID: UUID?
}

// MARK: - İlerleme

nonisolated struct SayimIlerleme: Equatable {
    struct KonumSatiri: Equatable, Identifiable {
        var id: String { ad }
        let ad: String
        let beklenen: Int
        let okutulan: Int
    }
    let okutulan: Int
    let beklenen: Int
    let sonOkutma: Date?
    let dakikadaOkutma: Int?
    let gecenSure: TimeInterval?
    let konumlar: [KonumSatiri]

    var yuzde: Int { beklenen > 0 ? min(999, Int((Double(okutulan) / Double(beklenen) * 100).rounded())) : 0 }
    var oran: Double { beklenen > 0 ? min(1, Double(okutulan) / Double(beklenen)) : 0 }

    static func hesapla(entries: [InventoryCountEntry], observations: [InventoryObservation], startedAt: Date?) -> SayimIlerleme {
        let beklenen = entries.reduce(0) { $0 + $1.expected }
        let okutulan = entries.reduce(0) { $0 + min($1.scanned, $1.expected) }
        let zamanlar = observations.map(\.observedAt).sorted()
        var hiz: Int?
        if zamanlar.count >= 2, let ilk = zamanlar.first, let son = zamanlar.last, son.timeIntervalSince(ilk) >= 1 {
            hiz = Int((Double(zamanlar.count - 1) / (son.timeIntervalSince(ilk) / 60)).rounded())
        }
        var gecen: TimeInterval?
        if let son = zamanlar.last, let baslangic = startedAt { gecen = max(0, son.timeIntervalSince(baslangic)) }
        var gruplar: [String: (Int, Int)] = [:]
        for entry in entries where entry.expected > 0 || entry.scanned > 0 {
            let ad = konumAdi(entry.book)
            let onceki = gruplar[ad] ?? (0, 0)
            gruplar[ad] = (onceki.0 + entry.expected, onceki.1 + min(entry.scanned, entry.expected))
        }
        let konumlar = gruplar.map { KonumSatiri(ad: $0.key, beklenen: $0.value.0, okutulan: $0.value.1) }
            .sorted { $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
        return SayimIlerleme(okutulan: okutulan, beklenen: beklenen, sonOkutma: zamanlar.last, dakikadaOkutma: hiz,
                             gecenSure: gecen, konumlar: konumlar)
    }

    private static func konumAdi(_ book: InventoryExpectedItem) -> String {
        if let konum = book.location, !konum.isEmpty { return konum }
        if let konum = book.copies.compactMap(\.location).first(where: { !$0.isEmpty }) { return konum }
        return "Konum belirtilmedi"
    }

    /// "1 sa 12 dk" / "45 dk" / "20 sn"
    static func sureMetni(_ saniye: TimeInterval) -> String {
        let toplam = Int(saniye.rounded())
        if toplam >= 3600 { return "\(toplam / 3600) sa \((toplam % 3600) / 60) dk" }
        if toplam >= 60 { return "\(toplam / 60) dk" }
        return "\(toplam) sn"
    }
}

// MARK: - Sayım durumu

/// Sayım ekranının tek durum nesnesi: oturum bir kez yüklenir, türetilmiş listeler yalnız girdi değişince
/// bir kez hesaplanır (eskiden her `body` çiziminde onlarca kez hesaplanıyordu).
@MainActor @Observable
final class SayimDurumu {
    var sessionName = "Raf sayımı"
    var operatorName = ""
    var method = "ISBN nüsha sayımı"
    var selectedLocation = "Tümü"
    var bildirim: String?

    private(set) var startedAt = Date.now
    private(set) var expectedSnapshot: [InventoryExpectedItem]?
    private(set) var catalogSnapshot: [InventoryExpectedItem]?
    private(set) var scannedCounts: [String: Int] = [:]
    private(set) var unknownCounts: [String: Int] = [:]
    private(set) var observations: [InventoryObservation] = []
    private(set) var onizleme: [InventoryExpectedItem] = []
    private(set) var sonOkutmalar: [SayimOkutmaKaydi] = []
    private(set) var yuklendi = false
    private(set) var yuklemeHatasi: String?
    private(set) var sonOkutmaKurtarilamadi = false

    // Türetilmiş (yalnız `yenidenHesapla` yazar)
    private(set) var countEntries: [InventoryCountEntry] = []
    private(set) var countedEntries: [InventoryCountEntry] = []
    private(set) var missingEntries: [InventoryCountEntry] = []
    private(set) var surplusEntries: [InventoryCountEntry] = []
    private(set) var matchedTotal = 0
    private(set) var expectedTotal = 0
    private(set) var scannedTotal = 0
    private(set) var identityUncertainBooks: [InventoryExpectedItem] = []
    private(set) var barcodelessBooks: [InventoryExpectedItem] = []
    private(set) var otherLocationBooks: [InventoryExpectedItem] = []
    /// `InventorySnapshot.statusCategories` sırasıyla: ödünçte, kayıp, onarımda, düşülmüş
    private(set) var statusBooks: [[InventoryExpectedItem]] = [[], [], [], []]
    private(set) var ilerleme = SayimIlerleme(okutulan: 0, beklenen: 0, sonOkutma: nil, dakikadaOkutma: nil, gecenSure: nil, konumlar: [])
    /// Sınama için: türetilmiş listelerin kaç kez baştan hesaplandığı.
    private(set) var hesaplamaSayisi = 0

    @ObservationIgnored let journal = InventoryJournal()
    @ObservationIgnored private var undoStack: [InventoryUndoRecord] = []
    @ObservationIgnored private var entriesByID: [UUID: InventoryCountEntry] = [:]
    @ObservationIgnored private var copiesByCode: [String: [InventoryCopySnapshot]] = [:]
    @ObservationIgnored private var catalogByISBN: [String: [InventoryExpectedItem]] = [:]
    @ObservationIgnored private var expectedCopyIDs = Set<UUID>()
    @ObservationIgnored private var expectedISBNs = Set<String>()
    @ObservationIgnored private var titles: [UUID: String] = [:]
    @ObservationIgnored private var onizlemeImzasi: Int?
    @ObservationIgnored private var baslatmaHatasiDepolama = false

    init() {}

    var expectedBooks: [InventoryExpectedItem] { expectedSnapshot ?? onizleme }
    var hasSnapshot: Bool { expectedSnapshot != nil }
    var geriAlinabilir: Bool { !undoStack.isEmpty }
    func scannedCount(_ book: InventoryExpectedItem) -> Int { entriesByID[book.id]?.scanned ?? 0 }
    func expectedCount(_ book: InventoryExpectedItem) -> Int { book.stock.available + book.stock.reserved }

    var sessionValue: InventorySession {
        InventorySession(scanned: scannedCounts, unknown: unknownCounts, location: selectedLocation, startedAt: startedAt,
                         expected: expectedSnapshot, name: sessionName, operatorName: operatorName, method: method,
                         observations: observations, catalogSnapshot: catalogSnapshot)
    }
    private func expectation() -> InventoryExpectation {
        InventoryExpectation(location: selectedLocation, startedAt: startedAt, name: sessionName, operatorName: operatorName,
                             method: method, expected: expectedSnapshot, catalogSnapshot: catalogSnapshot)
    }

    // MARK: Yükleme

    /// Oturumu diskten bir kez okur (eski tek dosya biçimi varsa göç ettirir).
    func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        do { uygula(try InventorySessionStore.openSession()) }
        catch {
            yuklemeHatasi = error.localizedDescription
            bildirim = "Kayıtlı sayım okunamadı; dosya korunuyor. " + error.localizedDescription
        }
    }

    func uygula(_ acilan: InventoryOpenResult) {
        let session = acilan.session
        selectedLocation = session.location
        startedAt = session.startedAt ?? .now
        expectedSnapshot = session.expected
        catalogSnapshot = session.catalogSnapshot
        sessionName = session.name ?? "Raf sayımı"
        operatorName = session.operatorName ?? ""
        method = session.method ?? "ISBN nüsha sayımı"
        scannedCounts = session.scanned
        unknownCounts = session.unknown
        observations = session.observations ?? []
        undoStack = acilan.undo
        sonOkutmaKurtarilamadi = acilan.tailDropped
        yuklendi = true
        indeksleriYenile()
        yenidenHesapla()
        if acilan.tailDropped { bildirim = "Son okutma kurtarılamadı; öncesi korundu. Gerekirse son kitabı yeniden okutun." }
        else if expectedSnapshot == nil && scannedTotal > 0 {
            bildirim = "Eski sayımın başlangıç beklentisi kayıtlı değil. Listeyi sabitlemeden sonuç kesinleşmez; gerekirse yeni sayım başlatın."
        }
    }

    // MARK: Önizleme ve başlatma

    /// Beklenen liste sabitlenmeden önce gösterilen önizleme; yalnız kapsam veya katalog değişince yeniden hesaplanır.
    func onizlemeyiYenile(books: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], reservations: [Reservation]) {
        guard expectedSnapshot == nil else { return }
        var hasher = Hasher()
        hasher.combine(selectedLocation); hasher.combine(books.count); hasher.combine(loans.count)
        hasher.combine(copies.count); hasher.combine(reservations.count)
        let imza = hasher.finalize()
        guard imza != onizlemeImzasi else { return }
        onizlemeImzasi = imza
        onizleme = InventorySnapshot.capture(books: books, loans: loans, copies: copies, reservations: reservations, location: selectedLocation)
        indeksleriYenile()
        yenidenHesapla()
    }

    func begin(books: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], reservations: [Reservation]) -> Bool {
        guard expectedSnapshot == nil else { return true }
        guard baslatilabilir() else { return false }
        let tum = InventorySnapshot.capture(books: books, loans: loans, copies: copies, reservations: reservations, location: "Tümü")
        let kapsam = selectedLocation == "Tümü" ? tum : InventorySnapshot.capture(
            books: books, loans: loans, copies: copies, reservations: reservations, location: selectedLocation)
        return baslat(expected: kapsam, catalog: tum)
    }

    private func baslatilabilir() -> Bool {
        baslatmaHatasiDepolama = false
        if let yuklemeHatasi {
            baslatmaHatasiDepolama = true
            bildirim = "Sayım başlatılamadı; kayıtlı dosya okunamadığı için korunuyor. " + yuklemeHatasi
            return false
        }
        guard !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bildirim = "Sayım adı ve sayan görevliyi yazın."; return false
        }
        return true
    }

    /// Anlık görüntüler hazırken oturumu başlatır ve beklentiyi mühürlü dosyaya yazar.
    func baslat(expected: [InventoryExpectedItem], catalog: [InventoryExpectedItem], at date: Date = .now) -> Bool {
        guard expectedSnapshot == nil else { return true }
        guard baslatilabilir() else { return false }
        let oncekiTarih = startedAt
        startedAt = date; expectedSnapshot = expected; catalogSnapshot = catalog
        do { try InventorySessionStore.writeExpectation(expectation()) }
        catch {
            expectedSnapshot = nil; catalogSnapshot = nil; startedAt = oncekiTarih
            baslatmaHatasiDepolama = true
            bildirim = "Sayım başlatılamadı: " + error.localizedDescription
            return false
        }
        indeksleriYenile()
        yenidenHesapla()
        return true
    }

    // MARK: Okutma

    /// Bir barkodu işler. `baslat`: ilk okutmada beklenen listeyi sabitleyen kapanış.
    @discardableResult
    func record(_ code: String, baslat: () -> Bool) -> SayimSonucu {
        if expectedSnapshot == nil, !baslat() {
            return bitir(baslatmaHatasiDepolama ? .kaydedilemedi : .reddedildi(bildirim ?? "Sayım başlatılamadı."), baslik: code,
                         mesaj: bildirim ?? "Sayım başlatılamadı.", kaydet: nil)
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let eslesenNushalar = copiesByCode[normalized] ?? []
        if eslesenNushalar.count == 1, let copy = eslesenNushalar.first {
            let key = "copy:" + copy.id.uuidString
            let baslik = titles[copy.bookID] ?? normalized
            if scannedCounts[key] != nil {
                let mesaj = "Bu demirbaş zaten sayıldı: \(normalized)"
                return bitir(.reddedildi(mesaj), baslik: baslik, mesaj: mesaj, kaydet: nil)
            }
            let disarida = !expectedCopyIDs.contains(copy.id)
            let gozlem = InventoryObservation(bookID: copy.bookID, copyID: copy.id, operatorName: operatorName,
                                              method: "Demirbaş", observedLocation: selectedLocation, outsideScope: disarida)
            let mesaj = disarida ? "Başka konumdaki demirbaş bulundu: \(normalized)" : "Demirbaş sayıldı: \(normalized)"
            return bitir(disarida ? .baskaRaf : .sayildi, baslik: baslik, mesaj: mesaj,
                         kaydet: .sayac(key: key, gozlem: gozlem))
        }
        if eslesenNushalar.count > 1 {
            let mesaj = "Demirbaş kodu mükerrer; sayım yapılmadı."
            return bitir(.reddedildi(mesaj), baslik: normalized, mesaj: mesaj, kaydet: nil)
        }
        guard method != "Benzersiz demirbaş" else {
            let mesaj = "Bu barkod benzersiz demirbaşla eşleşmedi; ISBN adedi artırılmadı."
            return bitir(.reddedildi(mesaj), baslik: normalized, mesaj: mesaj, kaydet: nil)
        }
        let isbn = ISBNFormatter.repair(code)
        guard !isbn.isEmpty else {
            return bitir(.kayitsiz, baslik: code, mesaj: "Katalogda bulunamadı: \(code)", kaydet: .kayitsiz(key: code))
        }
        let eslesenler = catalogByISBN[isbn] ?? []
        let katalogda = expectedISBNs.contains(isbn)
        if !katalogda, eslesenler.count == 1, let book = eslesenler.first {
            let gozlem = InventoryObservation(bookID: book.id, operatorName: operatorName, method: "ISBN",
                                              observedLocation: selectedLocation, outsideScope: true)
            return bitir(.baskaRaf, baslik: book.title, mesaj: "Katalogda kayıtlı, başka rafta bulunan kitap: \(book.title)",
                         kaydet: .sayac(key: "outside:" + book.id.uuidString, gozlem: gozlem))
        }
        if !katalogda, eslesenler.count > 1 {
            let mesaj = "ISBN farklı kayıtlarda var. Doğru nüshanın demirbaşını okutun; yanlış yere taşınmadı."
            return bitir(.reddedildi(mesaj), baslik: isbn, mesaj: mesaj, kaydet: nil)
        }
        if katalogda {
            var gozlem: InventoryObservation?
            var baslik = isbn
            if eslesenler.count == 1, let book = eslesenler.first {
                gozlem = InventoryObservation(bookID: book.id, operatorName: operatorName, method: "ISBN",
                                              observedLocation: selectedLocation, outsideScope: false)
                baslik = book.title
            }
            return bitir(.sayildi, baslik: baslik, mesaj: "Sayıldı: \(baslik)", kaydet: .sayac(key: isbn, gozlem: gozlem))
        }
        return bitir(.kayitsiz, baslik: isbn, mesaj: "Katalogda bulunamadı: \(isbn)", kaydet: .kayitsiz(key: isbn))
    }

    /// Barkodsuz kitabı elle sayar.
    @discardableResult
    func elleSay(_ book: InventoryExpectedItem, baslat: () -> Bool) -> SayimSonucu {
        if expectedSnapshot == nil, !baslat() {
            return bitir(baslatmaHatasiDepolama ? .kaydedilemedi : .reddedildi(bildirim ?? "Sayım başlatılamadı."), baslik: book.title,
                         mesaj: bildirim ?? "Sayım başlatılamadı.", kaydet: nil)
        }
        let gozlem = InventoryObservation(bookID: book.id, operatorName: operatorName, method: "Elle",
                                          observedLocation: selectedLocation, outsideScope: false)
        return bitir(.sayildi, baslik: book.title, mesaj: "Elle sayıldı: \(book.title)",
                     kaydet: .sayac(key: "book:" + book.id.uuidString, gozlem: gozlem))
    }

    private enum Kayit {
        case sayac(key: String, gozlem: InventoryObservation?)
        case kayitsiz(key: String)
    }

    private func bitir(_ sonuc: SayimSonucu, baslik: String, mesaj: String, kaydet: Kayit?) -> SayimSonucu {
        var sonuc = sonuc
        var mesaj = mesaj
        if let kaydet {
            let satir: InventoryLog.Line
            switch kaydet {
            case .sayac(let key, let gozlem):
                scannedCounts[key, default: 0] += 1
                if let gozlem { observations.append(gozlem) }
                undoStack.append(.init(key: key, unknown: false, observationID: gozlem?.id))
                satir = .init(t: .scan, key: key, obs: gozlem)
            case .kayitsiz(let key):
                unknownCounts[key, default: 0] += 1
                undoStack.append(.init(key: key, unknown: true, observationID: nil))
                satir = .init(t: .unknown, key: key)
            }
            journal.append(satir)
            if journal.lastError != nil {
                sonuc = .kaydedilemedi
                mesaj = "Okutma diske yazılamadı; sayım korunuyor, yeniden denenecek. " + (journal.lastError ?? "")
            }
            yenidenHesapla()
        }
        bildirim = mesaj
        sonOkutmalar.append(SayimOkutmaKaydi(baslik: baslik, sonuc: sonuc, mesaj: mesaj, saat: .now))
        if sonOkutmalar.count > 20 { sonOkutmalar.removeFirst(sonOkutmalar.count - 20) }
        return sonuc
    }

    /// Son okutmayı geri alır: sayacı ve (varsa) gözlemi düşürür; günlüğe "undo" satırı eklenir.
    @discardableResult
    func geriAl() -> Bool {
        guard let kayit = undoStack.popLast() else { return false }
        if kayit.unknown { InventoryLog.decrement(&unknownCounts, key: kayit.key) }
        else { InventoryLog.decrement(&scannedCounts, key: kayit.key) }
        if let id = kayit.observationID, let index = observations.lastIndex(where: { $0.id == id }) { observations.remove(at: index) }
        journal.append(.init(t: .undo))
        if let son = sonOkutmalar.lastIndex(where: { $0.sonuc.sayilirMi }) { sonOkutmalar.remove(at: son) }
        bildirim = "Son okutma geri alındı."
        yenidenHesapla()
        return true
    }

    // MARK: Kalıcılık

    /// Bekleyen okutmaları diske yazar (uygulama arka plana giderken ve ekran kapanırken).
    @discardableResult
    func flush() -> Bool {
        let tamam = journal.flush()
        if !tamam { bildirim = "Sayım oturumu kaydedilemedi; yeniden deneyin. " + (journal.lastError ?? "") }
        return tamam
    }

    /// Beklentiyi yeniden yazar ve okutma günlüğünü tek satıra sıkıştırır.
    func yenidenKaydet() {
        guard journal.flush() else { bildirim = "Sayım oturumu kaydedilemedi; yeniden deneyin. " + (journal.lastError ?? ""); return }
        do {
            try InventorySessionStore.saveFull(sessionValue)
            undoStack.removeAll()
            bildirim = "Sayım oturumu kaydedildi."
        } catch { bildirim = "Sayım oturumu kaydedilemedi; yeniden deneyin. " + error.localizedDescription }
    }

    /// Eski ayraçlı konum seçimini bugünkü biçime taşır (beklenti yeniden yazılır).
    func konumuGuncelle(_ yeni: String) {
        guard yeni != selectedLocation else { return }
        selectedLocation = yeni
        if expectedSnapshot != nil { yenidenKaydet() }
        onizlemeImzasi = nil
    }

    func sifirla() throws {
        try InventorySessionStore.clearVerified()
        journal.discardPending()
        scannedCounts.removeAll(); unknownCounts.removeAll(); expectedSnapshot = nil; catalogSnapshot = nil
        observations = []; startedAt = .now; undoStack.removeAll(); sonOkutmalar.removeAll()
        sonOkutmaKurtarilamadi = false; onizlemeImzasi = nil
        indeksleriYenile()
        yenidenHesapla()
    }

    // MARK: Türetilmiş değerler

    private func indeksleriYenile() {
        let katalog = catalogSnapshot ?? expectedBooks
        var kodlar: [String: [InventoryCopySnapshot]] = [:]
        var isbnler: [String: [InventoryExpectedItem]] = [:]
        var basliklar: [UUID: String] = [:]
        for book in katalog {
            basliklar[book.id] = book.title
            for copy in book.copies where !copy.accessionCode.isEmpty { kodlar[copy.accessionCode, default: []].append(copy) }
            let isbn = ISBNFormatter.normalize(book.isbn ?? "")
            if !isbn.isEmpty { isbnler[isbn, default: []].append(book) }
        }
        copiesByCode = kodlar; catalogByISBN = isbnler; titles = basliklar
        let beklenen = expectedBooks
        expectedCopyIDs = Set(beklenen.flatMap(\.copies).map(\.id))
        expectedISBNs = Set(beklenen.compactMap { book -> String? in
            let isbn = ISBNFormatter.normalize(book.isbn ?? ""); return isbn.isEmpty ? nil : isbn
        })
    }

    private func yenidenHesapla() {
        hesaplamaSayisi += 1
        let beklenen = expectedBooks
        let girdiler = InventoryCountResult.entries(expected: beklenen, scanned: scannedCounts)
        countEntries = girdiler
        entriesByID = Dictionary(girdiler.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        countedEntries = girdiler.filter { $0.scanned > 0 }
        missingEntries = girdiler.filter { $0.scanned < $0.expected }
        surplusEntries = girdiler.filter { $0.scanned > $0.expected }
        matchedTotal = girdiler.reduce(0) { $0 + $1.scanned }
        expectedTotal = beklenen.reduce(0) { $0 + $1.stock.available + $1.stock.reserved }
        scannedTotal = scannedCounts.values.reduce(0, +) + unknownCounts.values.reduce(0, +)
        identityUncertainBooks = beklenen.filter { ($0.unresolvedLoans ?? 0) > 0 }
        barcodelessBooks = beklenen.filter { ISBNFormatter.normalize($0.isbn ?? "").isEmpty }
        statusBooks = InventorySnapshot.statusCategories.map { _, keyPath in beklenen.filter { $0.stock[keyPath: keyPath] > 0 } }
        let disarida = Set(observations.filter(\.outsideScope).map(\.bookID))
        otherLocationBooks = (catalogSnapshot ?? []).filter { disarida.contains($0.id) }
        ilerleme = SayimIlerleme.hesapla(entries: girdiler, observations: observations, startedAt: expectedSnapshot == nil ? nil : startedAt)
    }

    var unmatchedTotal: Int { max(0, scannedTotal - matchedTotal) }

    func outsidePlaces(for book: InventoryExpectedItem) -> String {
        let ids = Set(observations.filter { $0.bookID == book.id && $0.outsideScope }.compactMap(\.copyID))
        let places = Set(book.copies.filter { ids.contains($0.id) }.compactMap(\.location))
        return places.isEmpty ? (book.location ?? "Belirtilmedi") : places.sorted().joined(separator: ", ")
    }
}
