import BackgroundTasks
import Foundation
import Photos
import SQLite3
import Synchronization
import UIKit
import Vision

/// P4.4: fotoğraflardaki yazının (OCR) arama indeksi. Ayrı SQLite dosyası (Application Support/foto-metin.sqlite), FTS5
/// (HafizaIndeksi'nin normalleştirme ve MATCH kuralları). Hafıza deposuna ve iCloud'a hiçbir şey yazılmaz.
/// Doldurma yalnız `Ayarlar.fotoMetinIndeksi` açıkken, telefon şarjdayken arka planda (BGProcessingTask) yapılır:
/// yalnız telefonda yerel duran küçük resimler okunur (`isNetworkAccessAllowed = false`), iCloud'dan özgün indirilmez.
/// OCR metni yalnız kaynak veridir; fotoğraflar aracı alıntıları '[yalnız kaynak veri]' notuyla verir.
nonisolated final class FotoIndeksi: @unchecked Sendable {
    struct Bulgu: Sendable, Equatable {
        let kimlik: String
        let tarih: Date
        let alinti: String
    }

    static let ortak = FotoIndeksi()
    static let gorevKimligi = "com.mehmetderin.asistan.fotoindeks"
    /// `Ayarlar.fotoMetinIndeksi` ile aynı anahtar (arka plan görevi Ayarlar'a erişmeden okur).
    static let acikAnahtari = "ayar.fotoMetinIndeksiV1"
    /// Bundan kısa metin indekse girmez (yine de işlendi sayılır, bir daha okunmaz).
    static let enAzMetin = 8
    /// Bir arka plan turunda okunan en çok fotoğraf.
    static let turBasina = 300
    /// Saklanan özgün metnin (alıntı kaynağı) üst sınırı.
    static let enFazlaAsil = 2000

    private var db: OpaquePointer?
    private let kilit = NSLock()
    let dosya: URL?

    init(dosya: URL? = nil, bellekte: Bool = false) {
        let hedef: URL? = bellekte ? nil : (dosya ?? Self.varsayilanDosya())
        self.dosya = hedef
        if sqlite3_open_v2(hedef?.path ?? ":memory:", &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK { db = nil; return }
        exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        // `metin` normalleştirilmiş (aranan), `asil` özgün metin (alıntı); kimlik = PHAsset.localIdentifier.
        exec("CREATE VIRTUAL TABLE IF NOT EXISTS foto_metin USING fts5(metin, kimlik UNINDEXED, tarih UNINDEXED, asil UNINDEXED, tokenize='unicode61 remove_diacritics 2');")
        exec("CREATE TABLE IF NOT EXISTS islenen(kimlik TEXT PRIMARY KEY, degisim REAL);")
    }

    deinit { if let db { sqlite3_close(db) } }

    private static func varsayilanDosya() -> URL {
        let k = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        var u = k.appendingPathComponent("foto-metin.sqlite")
        // Galeri metni yeniden üretilebilir: iCloud/bilgisayar yedeğine girmez.
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        try? u.setResourceValues(d)
        return u
    }

    @discardableResult private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }
    private static let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)   // SQLITE_TRANSIENT

    var hazir: Bool { db != nil }

    // MARK: yazma

    /// Fotoğrafın metnini yazar (önceki kaydı değiştirir) ve işlendi olarak işaretler. Metin `enAzMetin`'den kısaysa
    /// yalnız işaretlenir. `degisim` verilmezse `tarih` kullanılır.
    func ekle(kimlik: String, tarih: Date, metin: String, degisim: Date? = nil) {
        let temiz = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = HafizaIndeksi.normalize(String(temiz.prefix(HafizaIndeksi.enFazlaIndeksMetni)))
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return }
        sil(kimlikKilitsiz: kimlik)
        if temiz.count >= Self.enAzMetin {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO foto_metin(metin, kimlik, tarih, asil) VALUES(?,?,?,?)", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, n, -1, Self.T); sqlite3_bind_text(st, 2, kimlik, -1, Self.T)
                sqlite3_bind_double(st, 3, tarih.timeIntervalSince1970); sqlite3_bind_text(st, 4, String(temiz.prefix(Self.enFazlaAsil)), -1, Self.T)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO islenen(kimlik, degisim) VALUES(?,?)", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, kimlik, -1, Self.T); sqlite3_bind_double(st, 2, (degisim ?? tarih).timeIntervalSince1970)
        sqlite3_step(st)
    }

    private func sil(kimlikKilitsiz kimlik: String) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM foto_metin WHERE kimlik = ?", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, kimlik, -1, Self.T)
        sqlite3_step(st)
    }

    func temizle() {
        kilit.lock(); defer { kilit.unlock() }
        exec("DELETE FROM foto_metin; DELETE FROM islenen;")
    }

    // MARK: okuma

    /// Fotoğraf bu değişim tarihiyle (ya da daha yenisiyle) işlendi mi? Değişmiş fotoğraf yeniden okunur.
    func islendi(kimlik: String, degisim: Date) -> Bool {
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return false }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT degisim FROM islenen WHERE kimlik = ?", -1, &st, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, kimlik, -1, Self.T)
        guard sqlite3_step(st) == SQLITE_ROW else { return false }
        return sqlite3_column_double(st, 0) + 0.5 >= degisim.timeIntervalSince1970
    }

    /// Metni olan (aranabilir) fotoğraf sayısı.
    func sayi() -> Int { say("SELECT count(*) FROM foto_metin") }
    /// Okunmuş (metni olsun olmasın) fotoğraf sayısı.
    func islenenSayisi() -> Int { say("SELECT count(*) FROM islenen") }

    private func say(_ sql: String) -> Int {
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return 0 }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
    }

    /// BM25 sıralı arama (Türkçe aksan/büyük harf duyarsız, önek eşleşmeli). Alıntı özgün metinden, ilk terimin çevresinden.
    func ara(_ sorgu: String, adet: Int = 10) -> [Bulgu] {
        let t = HafizaIndeksi.terimler(sorgu)
        guard !t.isEmpty else { return [] }
        kilit.lock(); defer { kilit.unlock() }
        guard let db else { return [] }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT kimlik, tarih, asil FROM foto_metin WHERE foto_metin MATCH ? ORDER BY bm25(foto_metin) LIMIT ?", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, HafizaIndeksi.matchIfadesi(t), -1, Self.T)
        sqlite3_bind_int(st, 2, Int32(max(1, adet)))
        let kokler = t.map { $0.count > 6 ? String($0.prefix(max(5, $0.count - 3))) : $0 }
        var sonuc: [Bulgu] = []
        while sqlite3_step(st) == SQLITE_ROW {
            func s(_ c: Int32) -> String { sqlite3_column_text(st, c).map { String(cString: $0) } ?? "" }
            let asil = s(2)
            let n = GecmisArama.normalize(asil)
            let alinti = kokler.first(where: { n.contains($0) }).map { GecmisArama.kesit(asil, terim: $0, uzunluk: 160) } ?? String(asil.prefix(160))
            sonuc.append(Bulgu(kimlik: s(0), tarih: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)), alinti: alinti))
        }
        return sonuc
    }

    // MARK: arka plan görevi

    /// Info.plist `BGTaskSchedulerPermittedIdentifiers` bu kimliği içermiyorsa kayıt ve planlama hiç yapılmaz
    /// (izinsiz kimliği kaydetmek ya da kayıtsız görevi göndermek çöker).
    static var kimlikIzinli: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.contains(gorevKimligi) == true
    }

    private static let kayitli = Mutex(false)

    /// Uygulama açılırken bir kez çağrılır (yeniden kaydolmak çöker; ikinci çağrı yok sayılır).
    @MainActor
    static func kaydol() {
        guard kimlikIzinli, !OnayKapisi.testte else { return }
        let ilk = kayitli.withLock { k in
            if k { return false }
            k = true
            return true
        }
        guard ilk else { return }
        // Sistem bu kapanışı arka plan kuyruğunda çağırır: @Sendable olmazsa MainActor denetimi çöker.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: gorevKimligi, using: nil) { @Sendable gorev in
            nonisolated(unsafe) let gorev = gorev
            let is_ = Task.detached(priority: .background) {
                let tamam = await FotoIndeksi.ortak.calistir()
                gorev.setTaskCompleted(success: tamam)
                // Okunacak fotoğraf kaldıysa ya da yenileri gelirse bir sonraki şarj fırsatında sürer.
                FotoIndeksi.planla(acik: UserDefaults.standard.bool(forKey: FotoIndeksi.acikAnahtari))
            }
            gorev.expirationHandler = { is_.cancel() }
        }
    }

    /// Açıksa şarjda ve ağsız çalışan işleme görevini ister; kapalıysa bekleyeni iptal eder.
    static func planla(acik: Bool) {
        guard kimlikIzinli, kayitli.withLock({ $0 }) else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: gorevKimligi)
        guard acik else { return }
        let istek = BGProcessingTaskRequest(identifier: gorevKimligi)
        istek.requiresExternalPower = true
        istek.requiresNetworkConnectivity = false
        istek.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(istek)
    }

    /// Bir tur: işlenmemiş ya da değişmiş en çok `enFazla` fotoğrafın yazısını okur. Ana iş parçacığında çalışmaz.
    /// İzin yoksa ya da ayar kapalıysa hiçbir şey yapmadan döner. İptalde (süre doldu) false.
    @concurrent
    func calistir(enFazla: Int = FotoIndeksi.turBasina, ayarDenetle: Bool = true) async -> Bool {
        let izin = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard izin == .authorized || izin == .limited else { return true }
        if ayarDenetle, !UserDefaults.standard.bool(forKey: Self.acikAnahtari) { return true }
        let secenek = PHFetchOptions()
        secenek.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let hepsi = PHAsset.fetchAssets(with: .image, options: secenek)
        var adaylar: [PHAsset] = []
        var i = 0
        while i < hepsi.count, adaylar.count < enFazla {
            if Task.isCancelled { return false }
            let a = hepsi.object(at: i)
            let degisim = a.modificationDate ?? a.creationDate ?? .distantPast
            if !islendi(kimlik: a.localIdentifier, degisim: degisim) { adaylar.append(a) }
            i += 1
        }
        var okunan = 0
        for a in adaylar {
            if Task.isCancelled { return false }
            let metin = autoreleasepool { Self.metinOku(a) }
            // Küçük resim telefonda yoksa (yalnız iCloud'da) işaretlenmez: ileride yerel olursa yeniden denenir.
            guard let metin else { continue }
            let tarih = a.creationDate ?? .now
            ekle(kimlik: a.localIdentifier, tarih: tarih, metin: metin, degisim: a.modificationDate ?? tarih)
            okunan += 1
        }
        TaniGunlugu.yaz("FOTO İNDEKSİ: \(okunan)/\(adaylar.count) fotoğraf okundu")
        return true
    }

    /// Yerel küçük resmi (1024 px, ağsız, eşzamanlı) Vision ile okur. Resim alınamazsa nil; yazı yoksa "".
    static func metinOku(_ a: PHAsset) -> String? {
        let ayar = PHImageRequestOptions()
        ayar.deliveryMode = .highQualityFormat
        ayar.isSynchronous = true
        ayar.isNetworkAccessAllowed = false
        ayar.resizeMode = .fast
        nonisolated final class Kutu: @unchecked Sendable { var resim: UIImage? }
        let kutu = Kutu()
        PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 1024, height: 1024), contentMode: .aspectFit, options: ayar) { r, _ in
            kutu.resim = r
        }
        guard let cg = kutu.resim?.cgImage else { return nil }
        let istek = VNRecognizeTextRequest()
        istek.recognitionLevel = .accurate
        istek.usesLanguageCorrection = true
        if let diller = try? istek.supportedRecognitionLanguages() { istek.recognitionLanguages = ["tr-TR", "en-US"].filter(diller.contains) }
        guard (try? VNImageRequestHandler(cgImage: cg).perform([istek])) != nil else { return "" }
        return (istek.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
