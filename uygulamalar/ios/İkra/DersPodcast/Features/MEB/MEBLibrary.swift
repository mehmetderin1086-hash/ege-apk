import Foundation
import UIKit

/// İndirilebilir bir MEB belgesi: ders kitabı, etkinlik kitabı ya da öğretim programı.
nonisolated struct MEBFile: Identifiable, Hashable, Sendable {
    /// Dosya adı olarak da kullanılır ("kitap-36", "program-21").
    var id: String
    var title: String
    var url: URL
    /// Bilinmiyorsa 0.
    var bytes: Int

    init?(book: MEBCatalog.Book, catalog: MEBCatalog = .shared) {
        guard let url = catalog.url(book.pdf) else { return nil }
        id = "kitap-\(book.id)"; title = book.title; self.url = url; bytes = book.bytes
    }
    init?(program course: MEBCatalog.Course, catalog: MEBCatalog = .shared) {
        guard let url = catalog.url(course.program) else { return nil }
        id = "program-\(course.id)"; title = course.shortName + " öğretim programı"; self.url = url; bytes = 0
    }
    static func size(_ bytes: Int) -> String { bytes <= 0 ? "" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

/// İndirilen MEB belgeleri: `Application Support/MEB/` altında durur, iCloud yedeğine girmez (yeniden indirilebilir).
@MainActor @Observable final class MEBLibrary {
    static let shared = MEBLibrary()
    /// İndirilmekte olan belgeler ve ilerlemeleri (0…1).
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var stored: Set<String> = []
    private(set) var openedAt: [String: Double]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var observers: [String: NSKeyValueObservation] = [:]
    /// Yarıda kesilen indirmenin devam verisi: yeniden denenince kaldığı yerden sürer.
    @ObservationIgnored private var resume: [String: Data] = [:]

    nonisolated static var root: URL { URL.applicationSupportDirectory.appending(path: "MEB", directoryHint: .isDirectory) }
    nonisolated static func location(_ id: String) -> URL { root.appending(path: id + ".pdf") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openedAt = defaults.dictionary(forKey: "meb.openedAt") as? [String: Double] ?? [:]
        reload()
    }

    /// Başarılı açılış kaydı; indirme veya bir kitabı listede görmek okuma sayılmaz.
    func recordOpened(key: String, at date: Date = .now) {
        openedAt[key] = date.timeIntervalSince1970
        defaults.set(openedAt, forKey: "meb.openedAt")
    }

    var recentFile: MEBFile? { Self.mostRecent(in: downloaded, openedAt: openedAt) }

    nonisolated static func mostRecent(in files: [MEBFile], openedAt: [String: Double]) -> MEBFile? {
        files.filter { openedAt[$0.id] != nil }.max { (openedAt[$0.id] ?? 0) < (openedAt[$1.id] ?? 0) }
    }

    func reload() {
        // Klasör başka yoldan (bilgisayardan kopyalama) oluşmuş olabilir; yedeğe girmemesi her açılışta sağlanır.
        var folder = Self.root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        stored = Set(files.filter { $0.pathExtension == "pdf" }.map { $0.deletingPathExtension().lastPathComponent })
    }
    func has(_ file: MEBFile) -> Bool { stored.contains(file.id) }
    /// İndirilmiş belgeler, katalog sırasıyla (kitaplar, sonra programlar).
    var downloaded: [MEBFile] {
        let catalog = MEBCatalog.shared
        return (catalog.books.compactMap { MEBFile(book: $0) } + catalog.courses.compactMap { MEBFile(program: $0) }).filter { stored.contains($0.id) }
    }
    func location(_ file: MEBFile) -> URL { Self.location(file.id) }
    var usedBytes: Int {
        stored.reduce(0) { $0 + ((try? Self.location($1).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func download(_ file: MEBFile) {
        guard tasks[file.id] == nil, !has(file) else { return }
        errors[file.id] = nil; progress[file.id] = 0
        var request = URLRequest(url: file.url, timeoutInterval: 60)
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        let id = file.id
        let done: @Sendable (URL?, URLResponse?, Error?) -> Void = { temporary, response, error in
            // Geçici dosya bu blok bitince silinir; taşıma burada yapılır.
            let outcome = Self.store(temporary: temporary, response: response, error: error, id: id)
            let partial = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            Task { @MainActor in MEBLibrary.shared.finish(id, problem: outcome, partial: partial) }
        }
        let task = resume.removeValue(forKey: id).map { URLSession.shared.downloadTask(withResumeData: $0, completionHandler: done) } ?? URLSession.shared.downloadTask(with: request, completionHandler: done)
        observers[id] = task.progress.observe(\.fractionCompleted) { value, _ in
            let fraction = value.fractionCompleted
            Task { @MainActor in if MEBLibrary.shared.progress[id] != nil { MEBLibrary.shared.progress[id] = fraction } }
        }
        tasks[id] = task
        // Büyük kitap inerken ekran kendiliğinden kilitlenip indirmeyi kesmesin.
        UIApplication.shared.isIdleTimerDisabled = true
        task.resume()
    }
    /// Verilen belgelerden henüz inmemiş olanların indirmesini başlatır.
    func download(all files: [MEBFile]) { for file in files { download(file) } }
    /// İnmemiş ve şu an inmeyen belgeler ile toplam boyutları.
    func missing(_ files: [MEBFile]) -> (files: [MEBFile], bytes: Int) {
        let left = files.filter { !has($0) && progress[$0.id] == nil }
        return (left, left.reduce(0) { $0 + $1.bytes })
    }
    func cancel(_ file: MEBFile) { tasks[file.id]?.cancel() }
    func delete(_ file: MEBFile) {
        cancel(file)
        try? FileManager.default.removeItem(at: location(file))
        stored.remove(file.id); errors[file.id] = nil; resume[file.id] = nil
    }

    private func finish(_ id: String, problem: String?, partial: Data?) {
        tasks[id] = nil; observers[id] = nil; progress[id] = nil
        if tasks.isEmpty { UIApplication.shared.isIdleTimerDisabled = false }
        // Kullanıcı durdurduysa (boş ileti) devam verisi tutulmaz; bağlantı koptuysa tutulur.
        if let problem { if !problem.isEmpty { errors[id] = problem; resume[id] = partial } } else { stored.insert(id) }
    }

    /// İndirilen dosyayı doğrular ve yerine taşır. Sorun yoksa `nil`, kullanıcı iptal ettiyse boş metin, değilse hata iletisi döner.
    nonisolated private static func store(temporary: URL?, response: URLResponse?, error: Error?, id: String) -> String? {
        if let error { return (error as? URLError)?.code == .cancelled ? "" : "İndirme yarıda kaldı: \(error.localizedDescription) Yeniden dokununca kaldığı yerden sürer." }
        guard let temporary, let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "Belge sunucudan alınamadı. Daha sonra yeniden dene." }
        guard isPDF(temporary) else { return "İnen dosya PDF değil; MEB sitesindeki bağlantı değişmiş olabilir." }
        do {
            var folder = root
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            let target = location(id)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temporary, to: target)
            return nil
        } catch { return "Dosya kaydedilemedi: \(error.localizedDescription)" }
    }
    /// PDF dosyaları "%PDF" ile başlar (hata sayfası indirildiyse kaydedilmez).
    nonisolated static func isPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 5)).flatMap { String(data: $0, encoding: .ascii) }?.hasPrefix("%PDF") == true
    }
}

/// Katalog başlığı ve ders adı aranır; bu arama PDF sayfalarının metnini aramaz.
nonisolated enum MEBBookQuery {
    static func results(catalog: MEBCatalog, query: String, grade: Int = 0, course: Int = 0,
                        downloadedOnly: Bool = false, stored: Set<String> = []) -> [MEBCatalog.Book] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let courseNames = Dictionary(uniqueKeysWithValues: catalog.courses.map { ($0.id, $0.shortName) })
        return catalog.books.filter { book in
            (grade == 0 || book.grade == grade) && (course == 0 || book.course == course)
                && (!downloadedOnly || stored.contains("kitap-\(book.id)"))
                && (text.isEmpty || book.title.localizedStandardContains(text)
                    || (courseNames[book.course]?.localizedStandardContains(text) ?? false))
        }.sorted { ($0.grade, $0.course, $0.kind == "ders" ? 0 : 1, $0.title) < ($1.grade, $1.course, $1.kind == "ders" ? 0 : 1, $1.title) }
    }
}
