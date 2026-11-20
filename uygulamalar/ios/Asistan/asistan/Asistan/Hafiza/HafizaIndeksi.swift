import Foundation
import SQLite3

/// Hafıza arama indeksi: ayrı bir SQLite dosyasında FTS5 (BM25 sıralı, önek eşleşmeli, Türkçe normalleştirilmiş).
/// SwiftData deposunun yanında durur; kaynak gerçek SwiftData'dır, indeks silinse bile yeniden kurulur.
nonisolated final class HafizaIndeksi: @unchecked Sendable {
    enum Tur: String, Sendable { case mesaj, olgu }

    struct Sonuc: Sendable, Equatable {
        let tur: Tur
        let kimlik: String
        let sohbet: String
        let zaman: Date
        let metin: String
        /// BM25 skoru (küçük = daha ilgili); sıralama için pozitife çevrilmiş hâli `puan`.
        let puan: Double
        /// Eşleşen bölümün FTS5 `snippet` özeti (normalleştirilmiş metinden, ~48 belirteç). `metin` yalnız ilk 1500 karakter
        /// olduğundan terim daha geride geçiyorsa geri çağırma süzgeci ve model bağlamı bunu kullanır.
        var eslesme: String = ""
    }

    /// İndekslenen (aranabilir) metnin üst sınırı: uzun yanıt/belge özeti tam aranır, tek kayıt FTS'yi şişirmez.
    static let enFazlaIndeksMetni = 32_000
    /// İndeks biçim sürümü (`PRAGMA user_version`). Eskiyse tablo bir kez boşaltılır; açılıştaki `indeksiSenkronla`
    /// bütün kayıtları yeni kuralla (tam metin) yeniden ekler. 2: 4000 → `enFazlaIndeksMetni` karakter.
    static let indeksSurumu: Int32 = 2

    static let ortak = HafizaIndeksi()
    private var db: OpaquePointer?
    private let kilit = NSLock()
    let dosya: URL?

    init(dosya: URL? = nil, bellekte: Bool = false) {
        let hedef: URL? = bellekte ? nil : (dosya ?? Self.varsayilanDosya())
        self.dosya = hedef
        if sqlite3_open_v2(hedef?.path ?? ":memory:", &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK { db = nil; return }
        exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        // kimlik/tur/sohbet/zaman indekslenmez (UNINDEXED); yalnız `metin` aranır.
        exec("CREATE VIRTUAL TABLE IF NOT EXISTS ara USING fts5(metin, tur UNINDEXED, kimlik UNINDEXED, sohbet UNINDEXED, zaman UNINDEXED, asil UNINDEXED, tokenize='unicode61 remove_diacritics 2');")
        if surumOku() < Self.indeksSurumu {
            exec("DELETE FROM ara;")
            exec("PRAGMA user_version = \(Self.indeksSurumu);")
        }
    }

    deinit { if let db { sqlite3_close(db) } }

    private func surumOku() -> Int32 {
        guard let db else { return 0 }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int(st, 0) : 0
    }

    /// Dosyadaki indeks biçim sürümü (test görünürlüğü).
    var surum: Int32 { kilit.lock(); defer { kilit.unlock() }; return surumOku() }

    private static func varsayilanDosya() -> URL {
        let k = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return k.appendingPathComponent("hafiza-arama.sqlite")
    }

    @discardableResult private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    var hazir: Bool { db != nil }

    // MARK: normalleştirme

    /// Türkçe küçültme + aksan/İ-ı katlama (indeks ve sorgu aynı kuralı kullanır).
    static func normalize(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    static let durak: Set<String> = ["ve", "ile", "bir", "bu", "su", "icin", "gibi", "ama", "veya", "mi", "mu", "ne", "de", "da", "ki", "ben", "sen", "biz", "o", "en", "cok", "daha", "var", "yok", "nasil", "neden", "hangi", "olan", "olarak", "bana", "beni", "benim", "senin", "bunu", "sunu", "onu", "peki", "evet", "hayir", "tamam", "lutfen"]

    /// Sorgudan anlamlı terimler (≥3 harf, durak sözcük değil, tekrarsız).
    static func terimler(_ sorgu: String) -> [String] {
        var g = Set<String>(), r: [String] = []
        for t in normalize(sorgu).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) where t.count >= 3 && !durak.contains(t) {
            // Türkçe ek çeşitliliği: uzun sözcüklerin kökü (ilk 5-6 harf) önek olarak aranır.
            if g.insert(t).inserted { r.append(t) }
        }
        return Array(r.prefix(8))
    }

    /// FTS5 MATCH ifadesi: her terim önek (kök*) ve VEYA ile birleşir; BM25 çok terimli eşleşmeyi öne alır.
    static func matchIfadesi(_ terimler: [String]) -> String {
        terimler.map { t -> String in
            let kok = t.count > 6 ? String(t.prefix(max(5, t.count - 3))) : t
            return "\"\(kok.replacingOccurrences(of: "\"", with: ""))\"*"
        }.joined(separator: " OR ")
    }

    // MARK: yazma

    /// `yeni`: kimliğin indekste olmadığı kesinse true (taze mesaj, senkronda eksik kayıt). `kimlik` UNINDEXED olduğu için
    /// öncesindeki DELETE tabloyu baştan sona tarar; güncellemelerde (varsayılan) eski kayıt yine silinir.
    func ekle(tur: Tur, kimlik: String, sohbet: String = "", zaman: Date = .now, metin: String, yeni: Bool = false) {
        let n = Self.normalize(String(metin.prefix(Self.enFazlaIndeksMetni)))
        guard !n.isEmpty else { return }
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return }
        if !yeni { sil(kimlikKilitsiz: kimlik) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO ara(metin, tur, kimlik, sohbet, zaman, asil) VALUES(?,?,?,?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)   // SQLITE_TRANSIENT
        sqlite3_bind_text(st, 1, n, -1, T); sqlite3_bind_text(st, 2, tur.rawValue, -1, T); sqlite3_bind_text(st, 3, kimlik, -1, T)
        sqlite3_bind_text(st, 4, sohbet, -1, T); sqlite3_bind_double(st, 5, zaman.timeIntervalSince1970); sqlite3_bind_text(st, 6, String(metin.prefix(1500)), -1, T)
        sqlite3_step(st)
    }

    private func sil(kimlikKilitsiz kimlik: String) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM ara WHERE kimlik = ?", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, kimlik, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(st)
    }

    func sil(kimlik: String) { kilit.lock(); defer { kilit.unlock() }; if db != nil { sil(kimlikKilitsiz: kimlik) } }

    func sohbetiSil(_ sohbet: String) {
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM ara WHERE sohbet = ? AND tur = 'mesaj'", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, sohbet, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(st)
    }

    func sohbetleriSil(_ sohbetler: [String]) {
        guard !sohbetler.isEmpty else { return }
        kilit.lock(); defer { kilit.unlock() }
        guard let db, sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM ara WHERE sohbet = ? AND tur = 'mesaj'", -1, &st, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil); return
        }
        defer { sqlite3_finalize(st) }
        let bagla = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for sohbet in Set(sohbetler) {
            sqlite3_reset(st); sqlite3_clear_bindings(st)
            sqlite3_bind_text(st, 1, sohbet, -1, bagla)
            guard sqlite3_step(st) == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil); return
            }
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func temizle(tur: Tur? = nil) {
        kilit.lock(); defer { kilit.unlock() }
        exec(tur.map { "DELETE FROM ara WHERE tur = '\($0.rawValue)'" } ?? "DELETE FROM ara")
    }

    // MARK: okuma

    func say(tur: Tur? = nil) -> Int {
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return 0 }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, tur.map { "SELECT count(*) FROM ara WHERE tur = '\($0.rawValue)'" } ?? "SELECT count(*) FROM ara", -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
    }

    /// İndekste olan kimlikler (eksik kayıtları tamamlamak için).
    func kimlikler(tur: Tur) -> Set<String> {
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return [] }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT kimlik FROM ara WHERE tur = ?", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, tur.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var k = Set<String>()
        while sqlite3_step(st) == SQLITE_ROW { if let c = sqlite3_column_text(st, 0) { k.insert(String(cString: c)) } }
        return k
    }

    /// BM25 sıralı arama. `haricSohbet`: bu sohbetin mesajları atlanır (mevcut konuşma zaten bağlamda).
    func ara(_ sorgu: String, tur: Tur? = nil, adet: Int = 8, haricSohbet: String? = nil) -> [Sonuc] {
        let t = Self.terimler(sorgu)
        guard !t.isEmpty else { return [] }
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return [] }
        var sql = "SELECT tur, kimlik, sohbet, zaman, asil, bm25(ara), snippet(ara, 0, '', '', '…', 48) FROM ara WHERE ara MATCH ?"
        if tur != nil { sql += " AND tur = ?" }
        if haricSohbet != nil { sql += " AND sohbet != ?" }
        sql += " ORDER BY bm25(ara) LIMIT ?"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var i: Int32 = 1
        sqlite3_bind_text(st, i, Self.matchIfadesi(t), -1, T); i += 1
        if let tur { sqlite3_bind_text(st, i, tur.rawValue, -1, T); i += 1 }
        if let haricSohbet { sqlite3_bind_text(st, i, haricSohbet, -1, T); i += 1 }
        sqlite3_bind_int(st, i, Int32(adet))
        var sonuc: [Sonuc] = []
        while sqlite3_step(st) == SQLITE_ROW {
            func s(_ c: Int32) -> String { sqlite3_column_text(st, c).map { String(cString: $0) } ?? "" }
            sonuc.append(Sonuc(tur: Tur(rawValue: s(0)) ?? .mesaj, kimlik: s(1), sohbet: s(2), zaman: Date(timeIntervalSince1970: sqlite3_column_double(st, 3)),
                               metin: s(4), puan: -sqlite3_column_double(st, 5), eslesme: s(6)))
        }
        return sonuc
    }
}
