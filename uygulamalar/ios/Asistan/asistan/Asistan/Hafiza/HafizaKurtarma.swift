import Foundation
import SQLite3

/// Hafıza deposunun (SwiftData `Asistan.store`) kurtarma, günlük yedek ve geri yükleme işleri.
///
/// Klasörler deponun yanında açılır (`depo.deletingLastPathComponent()`): App Group kabı seçilmiş olsa da taşıma
/// aynı birimde kalır. `Kurtarma/<yyyy-MM-dd_HH-mm-ss>/` açılamayan deponun taşınan ya da kopyalanan hâlini,
/// `Yedekler/Asistan-yyyy-MM-dd.store` günlük tutarlı tek dosyalık kopyaları (son 7) tutar. Geri yükleme çalışan
/// uygulamada yapılamaz (ModelContainer değişmez): `Yedekler/geri-yukle.json` işareti yazılır, bir sonraki açılışta uygulanır.
/// Kural: dosyalar yalnız gerçekten bozuksa (`Tani.bozuk`) yerinden taşınır; erişilemeyen (kilitli telefon) depoya
/// dokunulmaz, sağlam ama şeması açılmayan depo kopyalanır. Tanı günlüğüne yalnız hata türü ve klasör adı yazılır.
nonisolated enum HafizaKurtarma {
    /// Kap açılamadığında dosyanın durumu.
    nonisolated enum Tani: String, Equatable, Sendable {
        /// Telefon kilitli (veri koruması) ya da geçici G/Ç/kilit hatası: dosyalara dokunulmaz.
        case erisilemez
        /// SQLite dosyası bozuk (NOTADB/CORRUPT ya da `quick_check` ≠ ok): kenara taşınır, boş depo açılır.
        case bozuk
        /// Dosya sağlam ama kap açılmıyor (şema/geçiş hatası): kopyalanır, kap bellekte açılır.
        case semaUyumsuz
        /// Ne olduğu anlaşılamadı (dosya yok vb.): dosya varsa kopyalanır, kap bellekte açılır.
        case bilinmeyen
    }

    nonisolated struct Yedek: Identifiable, Equatable, Sendable {
        let url: URL
        let tarih: Date
        let boyut: Int
        var id: String { url.lastPathComponent }
    }

    nonisolated struct KurtarmaKopyasi: Identifiable, Equatable, Sendable {
        let url: URL
        let tarih: Date
        /// `neden.txt`'nin ilk satırı: "bozuk", "sema-uyumsuz", "bilinmeyen", "geri-yukleme-oncesi".
        let neden: String
        let boyut: Int
        /// İçinde geri yüklenebilir `Asistan.store` var mı.
        let depoVar: Bool
        var id: String { url.lastPathComponent }
    }

    nonisolated enum GeriYuklemeHatasi: Error, LocalizedError, Equatable {
        case kaynakYok, kaynakDisarida
        var errorDescription: String? {
            switch self {
            case .kaynakYok: return "Yedek dosyası bulunamadı."
            case .kaynakDisarida: return "Yalnız Yedekler ya da Kurtarma klasöründeki kopyalar geri yüklenebilir."
            }
        }
    }

    nonisolated struct Isaret: Codable, Equatable, Sendable {
        /// Deponun klasörüne göre göreli yol ("Yedekler/Asistan-2026-10-20.store", "Kurtarma/<tarih>/Asistan.store").
        /// Mutlak yol saklanmaz: uygulama güncellenince kap yolu değişebilir.
        let kaynak: String
        let zaman: Date
    }

    static let yedekOneki = "Asistan-"
    static let yedekUzantisi = ".store"
    static let isaretAdi = "geri-yukle.json"

    static func yedekKlasoru(_ store: URL) -> URL { store.deletingLastPathComponent().appending(path: "Yedekler", directoryHint: .isDirectory) }
    static func kurtarmaKlasoru(_ store: URL) -> URL { store.deletingLastPathComponent().appending(path: "Kurtarma", directoryHint: .isDirectory) }

    /// Deponun üç dosyası: ana dosya, -wal, -shm (var olup olmadıklarına bakılmaz).
    static func dosyalar(_ store: URL) -> [URL] {
        [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
    }

    static func depoVar(_ store: URL) -> Bool {
        dosyalar(store).contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Tanı

    /// Kap açılamayınca dosyaya salt okunur SQLite bağlantısıyla bakar. `hata` kap kurucusunun hatası (izin hatası ise
    /// dosya hiç açılmadan `.erisilemez`).
    static func tani(store: URL, hata: (any Error)? = nil) -> Tani {
        if let hata, izinHatasi(hata) { return .erisilemez }
        guard FileManager.default.fileExists(atPath: store.path) else { return .bilinmeyen }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let acilis = sqlite3_open_v2(store.path, &db, SQLITE_OPEN_READONLY, nil)
        guard acilis == SQLITE_OK else { return sinifla(acilis) ?? .bilinmeyen }
        sqlite3_busy_timeout(db, 1500)
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let hazirlik = sqlite3_prepare_v2(db, "PRAGMA quick_check(1)", -1, &st, nil)
        guard hazirlik == SQLITE_OK else { return sinifla(hazirlik) ?? .bilinmeyen }
        let adim = sqlite3_step(st)
        if adim == SQLITE_ROW {
            let sonuc = sqlite3_column_text(st, 0).map { String(cString: $0) }
            return sonuc == "ok" ? .semaUyumsuz : .bozuk
        }
        return sinifla(adim) ?? .bilinmeyen
    }

    /// SQLite sonuç kodunu tanıya çevirir (genişletilmiş kodun alt baytı birincil koddur).
    static func sinifla(_ kod: Int32) -> Tani? {
        switch kod & 0xFF {
        case SQLITE_NOTADB, SQLITE_CORRUPT: return .bozuk
        case SQLITE_CANTOPEN, SQLITE_PERM, SQLITE_AUTH, SQLITE_IOERR, SQLITE_BUSY, SQLITE_LOCKED, SQLITE_NOMEM, SQLITE_READONLY: return .erisilemez
        default: return nil
        }
    }

    /// Veri koruması / izin hatası (NSCocoaErrorDomain 257/513, POSIX EPERM/EACCES), alt hatalarda da aranır.
    static func izinHatasi(_ e: any Error) -> Bool {
        let n = e as NSError
        if n.domain == NSCocoaErrorDomain, n.code == NSFileReadNoPermissionError || n.code == NSFileWriteNoPermissionError { return true }
        if n.domain == NSPOSIXErrorDomain, n.code == Int(EPERM) || n.code == Int(EACCES) { return true }
        if let alt = n.userInfo[NSUnderlyingErrorKey] as? NSError, izinHatasi(alt) { return true }
        return n.underlyingErrors.contains { ($0 as NSError) !== n && izinHatasi($0) }
    }

    // MARK: Kurtarma klasörü

    /// Depo dosyalarını `Kurtarma/<tarih>/`'e TAŞIR (yalnız bozuk depo ve geri yükleme öncesi). Yarım kalan taşıma geri alınır.
    @discardableResult
    static func karantinaya(_ store: URL, neden: String, zaman: Date = .now) throws -> URL {
        try ayir(store, neden: neden, zaman: zaman, tasi: true)
    }

    /// Depo dosyalarını `Kurtarma/<tarih>/`'e KOPYALAR; asıl dosyalar yerinde kalır.
    @discardableResult
    static func kopyala(_ store: URL, neden: String, zaman: Date = .now) throws -> URL {
        try ayir(store, neden: neden, zaman: zaman, tasi: false)
    }

    /// Aynı nedenle alınmış son kopya bugünkü dosyalarla aynı boyuttaysa yeniden kopyalamaz (her açılışta Kurtarma şişmesin).
    @discardableResult
    static func kopyalaGerekirse(_ store: URL, neden: String, zaman: Date = .now) -> URL? {
        guard depoVar(store) else { return nil }
        let boyutlar = dosyalar(store).map { boyut($0) }
        if let son = kurtarmaKopyalari(store: store).first(where: { $0.neden == neden }),
           dosyalar(son.url.appending(path: store.lastPathComponent)).map({ boyut($0) }) == boyutlar { return nil }
        return try? kopyala(store, neden: neden, zaman: zaman)
    }

    private static func ayir(_ store: URL, neden: String, zaman: Date, tasi: Bool) throws -> URL {
        let fm = FileManager.default
        let kok = kurtarmaKlasoru(store)
        let ad = damga(zaman)
        var hedef = kok.appending(path: ad, directoryHint: .isDirectory)
        var sira = 2
        while fm.fileExists(atPath: hedef.path) { hedef = kok.appending(path: "\(ad)-\(sira)", directoryHint: .isDirectory); sira += 1 }
        try fm.createDirectory(at: hedef, withIntermediateDirectories: true)
        var yapilan: [(kaynak: URL, varis: URL)] = []
        do {
            for kaynak in dosyalar(store) where fm.fileExists(atPath: kaynak.path) {
                let varis = hedef.appending(path: kaynak.lastPathComponent)
                if tasi { try fm.moveItem(at: kaynak, to: varis) } else { try fm.copyItem(at: kaynak, to: varis) }
                yapilan.append((kaynak, varis))
            }
        } catch {
            // Yarım taşıma bırakılmaz: taşınanlar yerine döner (yarım depo açılıp boş sanılmasın). Hepsi dönmezse klasör kalır.
            var hepsiDondu = true
            if tasi { for y in yapilan.reversed() where (try? fm.moveItem(at: y.varis, to: y.kaynak)) == nil { hepsiDondu = false } }
            if hepsiDondu { try? fm.removeItem(at: hedef) }
            TaniGunlugu.yaz("HAFIZA KURTARMA BAŞARISIZ: \(neden) · \((error as NSError).domain) \((error as NSError).code)")
            throw error
        }
        try? Data("\(neden)\n\(zaman.ISO8601Format())\n".utf8).write(to: hedef.appending(path: "neden.txt"))
        TaniGunlugu.yaz("HAFIZA KURTARMA: \(neden) → Kurtarma/\(hedef.lastPathComponent) (\(tasi ? "taşındı" : "kopyalandı"))")
        return hedef
    }

    /// Kurtarma klasörleri, en yenisi önce.
    static func kurtarmaKopyalari(store: URL) -> [KurtarmaKopyasi] {
        let fm = FileManager.default
        let kok = kurtarmaKlasoru(store)
        guard let icerik = try? fm.contentsOfDirectory(at: kok, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey]) else { return [] }
        let liste = icerik.compactMap { url -> KurtarmaKopyasi? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let nedenMetni = (try? String(contentsOf: url.appending(path: "neden.txt"), encoding: .utf8)) ?? ""
            let neden = nedenMetni.split(separator: "\n").first.map(String.init) ?? "bilinmeyen"
            let tarih = damgaCoz(String(url.lastPathComponent.prefix(19)))
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let depo = url.appending(path: store.lastPathComponent)
            return KurtarmaKopyasi(url: url, tarih: tarih, neden: neden, boyut: dosyalar(depo).map { boyut($0) }.reduce(0, +),
                                   depoVar: fm.fileExists(atPath: depo.path))
        }
        return liste.sorted { ($0.tarih, $0.id) > ($1.tarih, $1.id) }
    }

    /// Tek kurtarma klasörünü siler; yalnız `Kurtarma/` altındaki doğrudan klasörleri kabul eder.
    static func kurtarmaSil(_ klasor: URL, store: URL) throws {
        let kok = kurtarmaKlasoru(store).resolvingSymlinksInPath().standardizedFileURL.path
        let yol = klasor.resolvingSymlinksInPath().standardizedFileURL
        let ust = yol.deletingLastPathComponent().path
        func kirp(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
        guard kirp(ust) == kirp(kok), yol.lastPathComponent != "..", !yol.lastPathComponent.isEmpty else { throw GeriYuklemeHatasi.kaynakDisarida }
        try FileManager.default.removeItem(at: klasor)
    }

    // MARK: Günlük yedek

    /// Günde bir tutarlı tek dosyalık kopya (`VACUUM INTO`, salt okunur bağlantı: açık WAL'li depoda da tutarlı anlık görüntü).
    /// `zorla` ("Şimdi yedekle") bugünün yedeğini yenisiyle değiştirir. Bugünün yedeği varsa (zorla değilken), depo yoksa ya da yazılamazsa (disk dolu) nil; hata tanı günlüğüne yazılır, uygulama sürer.
    /// Yedekler iCloud/bilgisayar yedeğinin dışında tutulur (asıl depo zaten yedekleniyor; yer kaplamasın).
    @discardableResult
    static func gunlukYedek(store: URL, klasor: URL, simdi: Date = .now, tut: Int = 7, zorla: Bool = false) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: store.path) else { return nil }
        let ad = yedekOneki + gun(simdi) + yedekUzantisi
        let hedef = klasor.appending(path: ad)
        let vardi = fm.fileExists(atPath: hedef.path)
        guard zorla || !vardi else { return nil }
        do { try fm.createDirectory(at: klasor, withIntermediateDirectories: true) }
        catch { TaniGunlugu.yaz("HAFIZA YEDEĞİ: klasör açılamadı · \((error as NSError).code)"); return nil }
        yedektenDisla(klasor)
        let gecici = klasor.appending(path: ".\(ad).gecici")
        try? fm.removeItem(at: gecici)
        if let kod = vakumla(store, gecici) {
            try? fm.removeItem(at: gecici)
            TaniGunlugu.yaz("HAFIZA YEDEĞİ ATLANDI: sqlite \(kod)")
            return nil
        }
        do { if vardi { _ = try fm.replaceItemAt(hedef, withItemAt: gecici) } else { try fm.moveItem(at: gecici, to: hedef) } }
        catch { try? fm.removeItem(at: gecici); TaniGunlugu.yaz("HAFIZA YEDEĞİ ATLANDI: ad verilemedi · \((error as NSError).code)"); return nil }
        yedektenDisla(hedef)
        budama(klasor: klasor, tut: tut)
        return hedef
    }

    /// `VACUUM INTO`; başarıda nil, hatada SQLite sonuç kodu.
    private static func vakumla(_ kaynak: URL, _ hedef: URL) -> Int32? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let acilis = sqlite3_open_v2(kaynak.path, &db, SQLITE_OPEN_READONLY, nil)
        guard acilis == SQLITE_OK else { return acilis }
        sqlite3_busy_timeout(db, 3000)
        let yol = hedef.path.replacingOccurrences(of: "'", with: "''")
        let kod = sqlite3_exec(db, "VACUUM INTO '\(yol)'", nil, nil, nil)
        return kod == SQLITE_OK ? nil : kod
    }

    /// En eski fazlalık yedekleri siler (ad tarih sıralıdır).
    private static func budama(klasor: URL, tut: Int) {
        let hepsi = yedekler(klasor: klasor)   // en yenisi önce
        for y in hepsi.dropFirst(max(tut, 1)) { try? FileManager.default.removeItem(at: y.url) }
    }

    /// Yedekler, en yenisi önce.
    static func yedekler(klasor: URL) -> [Yedek] {
        guard let icerik = try? FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }
        let liste = icerik.compactMap { url -> Yedek? in
            let ad = url.lastPathComponent
            guard ad.hasPrefix(yedekOneki), ad.hasSuffix(yedekUzantisi) else { return nil }
            let gunMetni = String(ad.dropFirst(yedekOneki.count).dropLast(yedekUzantisi.count))
            let degerler = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let tarih = gunCoz(gunMetni) ?? degerler?.contentModificationDate else { return nil }
            return Yedek(url: url, tarih: tarih, boyut: degerler?.fileSize ?? 0)
        }
        return liste.sorted { ($0.tarih, $0.id) > ($1.tarih, $1.id) }
    }

    // MARK: Geri yükleme

    /// Geri yükleme isteği: işaret yazılır, bir sonraki açılışta `bekleyenGeriYuklemeyiUygula` uygular.
    /// Kaynak `Yedekler/*.store` ya da `Kurtarma/<tarih>/Asistan.store` olmalı.
    static func geriYuklemeIste(_ kaynak: URL, store: URL, zaman: Date = .now) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: kaynak.path) else { throw GeriYuklemeHatasi.kaynakYok }
        guard let goreli = goreliYol(kaynak, store: store) else { throw GeriYuklemeHatasi.kaynakDisarida }
        let klasor = yedekKlasoru(store)
        try fm.createDirectory(at: klasor, withIntermediateDirectories: true)
        let veri = try JSONEncoder().encode(Isaret(kaynak: goreli, zaman: zaman))
        try veri.write(to: klasor.appending(path: isaretAdi), options: .atomic)
    }

    /// Bekleyen geri yükleme isteğini iptal eder.
    static func geriYuklemeIptal(store: URL) {
        try? FileManager.default.removeItem(at: yedekKlasoru(store).appending(path: isaretAdi))
    }

    static func bekleyenIstek(store: URL) -> Isaret? {
        guard let veri = try? Data(contentsOf: yedekKlasoru(store).appending(path: isaretAdi)) else { return nil }
        return try? JSONDecoder().decode(Isaret.self, from: veri)
    }

    /// İşaret varsa: mevcut dosyalar `Kurtarma/`'ya taşınır, kaynak (ve varsa -wal/-shm) depo adına kopyalanır, işaret silinir.
    /// Uygulandıysa true. İşaret okunamıyorsa (telefon kilitli) dokunulmaz; sonraki açılışta yeniden denenir.
    /// Arama indeksi (`indeksiSenkronla`) kimlik farkıyla kendini yeni depoya uydurur; ayrı bayrak gerekmez.
    @discardableResult
    static func bekleyenGeriYuklemeyiUygula(store: URL) -> Bool {
        let fm = FileManager.default
        let isaretURL = yedekKlasoru(store).appending(path: isaretAdi)
        guard let veri = try? Data(contentsOf: isaretURL) else { return false }
        guard let isaret = try? JSONDecoder().decode(Isaret.self, from: veri),
              !isaret.kaynak.contains(".."), !isaret.kaynak.hasPrefix("/") else {
            try? fm.removeItem(at: isaretURL); TaniGunlugu.yaz("HAFIZA GERİ YÜKLEME: işaret çözülemedi, silindi"); return false
        }
        let kaynak = store.deletingLastPathComponent().appending(path: isaret.kaynak)
        guard fm.fileExists(atPath: kaynak.path) else {
            try? fm.removeItem(at: isaretURL); TaniGunlugu.yaz("HAFIZA GERİ YÜKLEME: kaynak yok, istek bırakıldı"); return false
        }
        // Kaynak bir kurtarma kopyası olabilir: karantina her zaman yeni bir klasör açar, kaynağın klasörüne dokunmaz.
        var karantina: URL?
        if depoVar(store) {
            do { karantina = try karantinaya(store, neden: "geri-yukleme-oncesi") }
            catch { return false }   // işaret kalır; bir sonraki açılış yeniden dener
        }
        do {
            for (k, h) in zip(dosyalar(kaynak), dosyalar(store)) where fm.fileExists(atPath: k.path) { try fm.copyItem(at: k, to: h) }
        } catch {
            // Yarım kopya bırakılmaz; önceki depo yerine döner.
            for h in dosyalar(store) { try? fm.removeItem(at: h) }
            if let karantina {
                var hepsi = true
                for h in dosyalar(store) {
                    let v = karantina.appending(path: h.lastPathComponent)
                    if fm.fileExists(atPath: v.path), (try? fm.moveItem(at: v, to: h)) == nil { hepsi = false }
                }
                if hepsi { try? fm.removeItem(at: karantina) }
            }
            try? fm.removeItem(at: isaretURL)
            TaniGunlugu.yaz("HAFIZA GERİ YÜKLEME BAŞARISIZ: kopyalanamadı · \((error as NSError).code)")
            return false
        }
        try? fm.removeItem(at: isaretURL)
        TaniGunlugu.yaz("HAFIZA GERİ YÜKLENDİ: \(isaret.kaynak.split(separator: "/").first ?? "")")
        return true
    }

    /// Kaynağın depo klasörüne göre göreli yolu; yalnız Yedekler/ ya da Kurtarma/ altındaysa.
    static func goreliYol(_ kaynak: URL, store: URL) -> String? {
        let kok = store.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let yol = kaynak.resolvingSymlinksInPath().standardizedFileURL.path
        let onek = kok.hasSuffix("/") ? kok : kok + "/"
        guard yol.hasPrefix(onek) else { return nil }
        let goreli = String(yol.dropFirst(onek.count))
        guard goreli.hasPrefix("Yedekler/") || goreli.hasPrefix("Kurtarma/"), !goreli.contains("..") else { return nil }
        return goreli
    }

    // MARK: Yardımcılar

    static func boyut(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 }

    private static func yedektenDisla(_ url: URL) {
        var u = url
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        try? u.setResourceValues(d)
    }

    private static func bicimci(_ kalip: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current
        f.dateFormat = kalip
        return f
    }
    static func gun(_ d: Date) -> String { bicimci("yyyy-MM-dd").string(from: d) }
    static func gunCoz(_ s: String) -> Date? { bicimci("yyyy-MM-dd").date(from: s) }
    static func damga(_ d: Date) -> String { bicimci("yyyy-MM-dd_HH-mm-ss").string(from: d) }
    static func damgaCoz(_ s: String) -> Date? { bicimci("yyyy-MM-dd_HH-mm-ss").date(from: s) }
}
