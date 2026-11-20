import Foundation
import SwiftUI
import SwiftData

/// Başarı bildirimi kapansa veya uygulama yeniden açılsa da geri dönüş ZIP'i
/// Management'tan bulunur. Dizindeki rapor ve ZIP yeniden doğrulanır.
nonisolated enum ArchiveSwitchBackupStore {
    struct Entry: Identifiable, Sendable {
        let id: String
        let date: Date
        let state: String
        let backupURL: URL
        let reportURL: URL
        let scopeReport: String
        let books: Int
        let copies: Int
        let loans: Int
        let students: Int
        let members: Int
        let events: Int
    }
    struct Listing: Sendable { var entries: [Entry] = []; var failures: [String] = [] }

    /// ZIP'in boyutu ve değişiklik zamanı (nanosaniye). Aynıysa önceki doğrulamanın özeti geçerlidir.
    nonisolated struct SummarySeal: Codable, Equatable, Sendable {
        let size: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        static func capture(_ url: URL) throws -> SummarySeal {
            guard let seal = try ArchiveBackgroundWork.FileSeal.capture(url) else { throw CocoaError(.fileReadNoSuchFile) }
            return SummarySeal(size: seal.size, modifiedSeconds: seal.modifiedSeconds, modifiedNanoseconds: seal.modifiedNanoseconds)
        }
    }

    /// Klasörde 'ozet.json' olarak saklanan doğrulanmış özet.
    nonisolated struct Summary: Codable, Sendable {
        static let fileName = "ozet.json"
        let seal: SummarySeal
        let scope: [String: Int]
        let books: Int, copies: Int, loans: Int, students: Int, members: Int, events: Int
        static func load(in folder: URL) -> Summary? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
            return try? JSONDecoder().decode(Summary.self, from: data)
        }
        /// Önbellek yazılamazsa sorun değildir; liste yine doğrulanmış sonuçla döner.
        func save(in folder: URL) {
            guard let data = try? JSONEncoder().encode(self) else { return }
            try? data.write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
        }
    }

    static func listing(root override: URL? = nil) throws -> Listing {
        guard let root = override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ArchiveRestoreBackups", isDirectory: true) else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: root.path) else { return Listing() }
        let safeRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var result = Listing()
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]) {
            let name = folder.lastPathComponent
            guard name.hasPrefix("switch-"), UUID(uuidString: String(name.dropFirst(7))) != nil else { continue }
            do {
                let resource = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
                guard resource.isDirectory == true, resource.isSymbolicLink != true,
                      folder.resolvingSymlinksInPath().deletingLastPathComponent().pathComponents == safeRoot.pathComponents else { throw CocoaError(.fileReadCorruptFile) }
                let zip = folder.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
                let report = folder.appendingPathComponent("Katalog-Gecisi-Kapsam.txt")
                for file in [zip, report] {
                    guard file.resolvingSymlinksInPath().deletingLastPathComponent().pathComponents == folder.resolvingSymlinksInPath().pathComponents,
                          (try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).isRegularFile == true,
                          (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                }
                let text = try String(contentsOf: report, encoding: .utf8)
                guard let first = text.split(separator: "\n").first,
                      let prefix = ["Ayrı katalog açma: ", "Mevcut kataloğa ekleme: "].first(where: { first.hasPrefix($0) }) else { throw CocoaError(.fileReadCorruptFile) }
                let state = String(first.dropFirst(prefix.count))
                guard ["dogrulandi", "geri_alindi", "geri_alma_bekliyor", "hazir"].contains(state) else { throw CocoaError(.fileReadCorruptFile) }
                // Özet önbelleği: ZIP'in boyut/değişiklik mührü aynıysa tam çözme atlanır; her 'Yenile'de
                // onlarca MB yeniden okunmaz. Mühür değişirse (ya da özet yoksa) ZIP tam doğrulanıp özet yenilenir.
                let seal = try SummarySeal.capture(zip)
                let summary: Summary
                if let cached = Summary.load(in: folder), cached.seal == seal { summary = cached }
                else {
                    let contents = try FullArchive.readValidated(from: zip)
                    summary = Summary(seal: seal, scope: expectedScope(contents), books: contents.books.count,
                                      copies: contents.copies.count, loans: contents.activeLoans.count,
                                      students: contents.students.count, members: contents.members.count,
                                      events: contents.loanEvents.count)
                    summary.save(in: folder)
                }
                let before = summary.scope
                let pattern = #"^(.+): önce ([0-9]+), seçilen arşiv ([0-9]+), yeni katalog ([0-9]+)$"#
                let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                var reported: [String: Int] = [:]
                for match in matches {
                    guard let titleRange = Range(match.range(at: 1), in: text), let countRange = Range(match.range(at: 2), in: text),
                          let count = Int(text[countRange]), reported[String(text[titleRange])] == nil else { throw CocoaError(.fileReadCorruptFile) }
                    reported[String(text[titleRange])] = count
                }
                guard reported == before else {
                    throw FullArchive.ValidationError(message: "Geçiş raporu ile işlem öncesi tam yedek kapsamı aynı değil.")
                }
                result.entries.append(Entry(id: name, date: resource.creationDate ?? .distantPast, state: state,
                                            backupURL: zip, reportURL: report, scopeReport: text, books: summary.books,
                                            copies: summary.copies, loans: summary.loans, students: summary.students,
                                            members: summary.members, events: summary.events))
            } catch {
                result.failures.append("\(name): yedek veya geçiş kapsam raporu doğrulanamadı. \(error.localizedDescription)")
            }
        }
        result.entries.sort { $0.date > $1.date }
        return result
    }

    /// Kalıcı raporun v1 kapsam adları. ZIP okuma/özet çıkarma ana UI iş parçacığından
    /// bağımsızdır; ModelContext, global defter veya tercihlere erişmez.
    private static func expectedScope(_ contents: ArchiveContents) -> [String: Int] {
        ["Eser": contents.books.count, "Kapak": contents.books.filter { $0.coverData != nil }.count,
         "Fiziksel nüsha": contents.copies.count, "Açık ödünç": contents.activeLoans.count,
         "Rezervasyon": contents.reservations.count, "Geçmiş hareketi": contents.loanEvents.count,
         "Öğrenci": contents.students.count, "Üye": contents.members.count, "Mezun": contents.graduatedStudents.count,
         "Tarama oturumu": contents.scanSessions.count, "Tarama makbuzu": contents.scanReceipts.count,
         "Birleştirme geri alma": contents.mergeUndoRecords.count]
    }
}

/// Etkin olmayan (artık işaretçinin göstermediği) kurtarma depoları. Eski kataloglar burada birikir ve
/// telefonun alanını doldurur; silme yalnız doğrulanmış tam ZIP o depoyu kapsıyorsa ve yönetici onayıyla yapılır.
nonisolated enum InactiveStoreCatalog {
    nonisolated struct Item: Identifiable, Sendable, Equatable {
        let url: URL
        let bytes: Int64
        let modified: Date
        var id: URL { url }
    }

    /// `root` altındaki `.store` dosyaları (ve `-wal`, `-shm`, `.<ad>_SUPPORT` yan dosyaları). Etkin depo hariçtir.
    static func list(root: URL, activePath: String?) throws -> [Item] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let active = activePath.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys).compactMap { url in
            guard url.pathExtension == "store",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  url.standardizedFileURL.resolvingSymlinksInPath().path != active else { return nil }
            let parts = companionURLs(of: url)
            var bytes: Int64 = 0, modified = Date.distantPast
            for part in parts {
                let (size, date) = measure(part)
                bytes += size; modified = max(modified, date)
            }
            return Item(url: url, bytes: bytes, modified: modified)
        }.sorted { $0.modified > $1.modified }
    }

    /// Silme güvenli mi? Doğrulanmış en yeni tam ZIP, deponun son değişikliğinden sonra alınmış olmalı.
    static func isCovered(_ item: Item, verifiedBackupDates: [Date]) -> Bool {
        guard let newest = verifiedBackupDates.max() else { return false }
        return newest >= item.modified
    }

    /// Yalnız `root` içindeki depo ve yan dosyalarını siler; kök dışına çıkan her yolu reddeder.
    static func delete(_ item: Item, root: URL, activePath: String?) throws {
        let safeRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let target = item.url.standardizedFileURL.resolvingSymlinksInPath()
        guard target.deletingLastPathComponent() == safeRoot, target.pathExtension == "store" else {
            throw FullArchive.ValidationError(message: "Depo, kurtarma klasörünün dışında; silinmedi.")
        }
        if let activePath, URL(fileURLWithPath: activePath).standardizedFileURL.resolvingSymlinksInPath() == target {
            throw FullArchive.ValidationError(message: "Bu depo şu anda kullanılıyor; silinmedi.")
        }
        for part in companionURLs(of: item.url) where FileManager.default.fileExists(atPath: part.path) {
            try FileManager.default.removeItem(at: part)
        }
    }

    private static func companionURLs(of store: URL) -> [URL] {
        let support = store.deletingLastPathComponent()
            .appendingPathComponent("." + store.deletingPathExtension().lastPathComponent + "_SUPPORT", isDirectory: true)
        return [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm"), support]
    }

    private static func measure(_ url: URL) -> (Int64, Date) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return (0, .distantPast) }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: keys)
            return (Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }
        var total: Int64 = 0, newest = Date.distantPast
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let file as URL in walker {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                total += Int64(values.fileSize ?? 0)
                newest = max(newest, values.contentModificationDate ?? .distantPast)
            }
        }
        return (total, newest)
    }
}

/// Tanılama ekranına gömülen 'Etkin olmayan depolar' bölümü.
struct InactiveStoresSection: View {
    @State private var items: [InactiveStoreCatalog.Item] = []
    @State private var backupDates: [Date] = []
    @State private var candidate: InactiveStoreCatalog.Item?
    @State private var message: String?

    var body: some View {
        Section {
            if items.isEmpty { Text("Etkin olmayan depo yok.").foregroundStyle(KitapTema.ikincilMetin) }
            ForEach(items) { item in
                let covered = InactiveStoreCatalog.isCovered(item, verifiedBackupDates: backupDates)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Depo \(String(item.url.deletingPathExtension().lastPathComponent.prefix(8)))…").font(.headline)
                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) · son değişiklik \(item.modified.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(KitapTema.ikincilMetin)
                    if !covered {
                        Label("Doğrulanmış tam yedek bu depoyu kapsamıyor; silinemez.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                    }
                    Button("Sil", systemImage: "trash", role: .destructive) { candidate = item }
                        .disabled(!covered).frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
            }
            if let message { Label(message, systemImage: "info.circle").font(.footnote) }
        } header: {
            Text("Etkin olmayan depolar")
        } footer: {
            Text("Eski katalog geçişlerinden kalan depolar yer kaplar. Yalnız, doğrulanmış tam geçiş yedeği o depodan sonra alınmışsa silinebilir.")
        }
        .task { await reload() }
        .confirmationDialog("Bu depo kalıcı silinsin mi? Geri alınamaz.", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }), titleVisibility: .visible) {
            Button("Depoyu Sil", role: .destructive) {
                guard let item = candidate else { return }
                candidate = nil
                do {
                    try SchoolLibraryService.requireAdmin()
                    let root = try ArchiveSwitchJournal.recoveredStoreRoot()
                    try InactiveStoreCatalog.delete(item, root: root, activePath: UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey))
                    message = "Depo silindi."
                    Task { await reload() }
                } catch { message = error.localizedDescription }
            }
            Button("Vazgeç", role: .cancel) { candidate = nil }
        }
    }

    private func reload() async {
        do {
            let recovered = try ArchiveSwitchJournal.recoveredStoreRoot()
            let backups = try ArchiveSwitchJournal.backupRoot()
            let active = UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey)
            let result = try await Task.detached(priority: .utility) {
                let list = try InactiveStoreCatalog.list(root: recovered, activePath: active)
                let dates = list.isEmpty ? [] : try ArchiveSwitchBackupStore.listing(root: backups).entries.map(\.date)
                return (list, dates)
            }.value
            items = result.0; backupDates = result.1
        } catch { message = error.localizedDescription }
    }
}

struct ArchiveSwitchBackupHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let context: ModelContext
    @State private var entries: [ArchiveSwitchBackupStore.Entry] = []
    @State private var failures: [String] = []
    @State private var error: String?
    @State private var preparing = false
    @State private var preview: ArchiveSwitchCoordinator.Preparation?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Cihazda saklanan katalog geçişi yedekleri her açılışta yeniden doğrulanır. Önceki kataloğu aynı güvenli prova ve geri yükleme yoluyla açabilirsiniz.")
                }
                if loading { ProgressView("Tam yedekler doğrulanıyor…") }
                if preparing { ProgressView("Önizleme arka planda hazırlanıyor…") }
                if !loading && entries.isEmpty { Text("Doğrulanmış katalog geçişi yedeği bulunamadı.") }
                ForEach(entries) { entry in
                    Section(entry.date.formatted(date: .abbreviated, time: .shortened)) {
                        Text("\(entry.books) eser · \(entry.copies) nüsha · \(entry.loans) açık ödünç").font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.students) öğrenci · \(entry.members) üye · \(entry.events) geçmiş hareketi").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        if entry.state != "dogrulandi" { Text("Geçiş tamamlanmadı; işlem öncesi tam ZIP doğrulandı. Durum: \(entry.state)").font(.footnote).fixedSize(horizontal: false, vertical: true) }
                        ShareLink(item: entry.backupURL) { Label("Önceki tam yedeği paylaş", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                        ShareLink(item: entry.reportURL) { Label("Kapsam raporunu paylaş", systemImage: "doc.text") }.frame(minHeight: 44)
                        Button {
                            guard !preparing else { return }; preparing = true
                            Task { @MainActor in
                                defer { preparing = false }
                                do { preview = try await ArchiveSwitchCoordinator.prepareAsync(from: entry.backupURL, context: context); self.error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: { Label("Önceki kataloğu açma önizlemesi", systemImage: "arrow.uturn.backward").fixedSize(horizontal: false, vertical: true) }
                            .frame(minHeight: 44).accessibilityIdentifier("archive.switch.backup.preview").disabled(preparing)
                    }
                }
                if let error { Section("Önizleme hazırlanamadı") { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
                if !failures.isEmpty {
                    Section("Doğrulama gerektiren dosyalar") {
                        ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in Text(failure).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            .navigationTitle("Katalog geçişi yedekleri")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Yenile", systemImage: "arrow.clockwise") { refresh() }.disabled(loading) }
            }
            .task { refresh() }
            .sheet(item: $preview) { preparation in ArchiveSwitchReviewView(preparation: preparation, context: context) }
        }
    }
    private func refresh() {
        loading = true
        Task { @MainActor in
            await Task.yield()
            defer { loading = false }
            do {
                let root = try ArchiveSwitchJournal.backupRoot()
                let result = try await Task.detached(priority: .utility) { try ArchiveSwitchBackupStore.listing(root: root) }.value
                entries = result.entries; failures = result.failures; error = nil
            }
            catch { self.error = error.localizedDescription }
        }
    }
}
