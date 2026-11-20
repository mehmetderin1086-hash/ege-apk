import Foundation

nonisolated enum ArchiveRetentionPolicy: String, CaseIterable, Identifiable, Sendable {
    case short, long, all
    var id: Self { self }
    var title: String {
        switch self {
        case .short: "7 günlük + 4 haftalık"
        case .long: "30 günlük + 12 haftalık"
        case .all: "Tüm arşivleri koru"
        }
    }
    var daily: Int { self == .short ? 7 : 30 }
    var weekly: Int { self == .short ? 4 : 12 }
}

nonisolated struct ArchiveRetentionFile: Identifiable, Sendable, Equatable {
    var url: URL
    var date: Date
    var bytes: Int64
    var modifiedAt: Date
    var id: URL { url }
}

/// Saklama planı yalnız uygulamanın adlandırdığı günlük ZIP'leri kapsar.
/// Yeni arşiv oluşturulması eski dosyaları silmez; görevli kesin listeyi onaylar.
nonisolated enum ArchiveRetention {
    static let preferenceKey = "autoArchiveRetentionPolicy"
    static func archiveDate(_ name: String) -> Date? {
        guard name.hasPrefix("KitapArsivi-"), name.hasSuffix(".zip"), name.count == 26 else { return nil }
        let text = String(name.dropFirst(12).dropLast(4))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    static func files(in directory: URL) throws -> [ArchiveRetentionFile] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        return try urls.compactMap { url in
            guard let date = archiveDate(url.lastPathComponent) else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = values.fileSize, let modified = values.contentModificationDate else { return nil }
            return ArchiveRetentionFile(url: url, date: date, bytes: Int64(bytes), modifiedAt: modified)
        }.sorted { $0.date > $1.date }
    }
    static func removals(from files: [ArchiveRetentionFile], policy: ArchiveRetentionPolicy) -> [ArchiveRetentionFile] {
        guard policy != .all else { return [] }
        let sorted = files.sorted { $0.date > $1.date }
        var kept = Set(sorted.prefix(policy.daily).map(\.url))
        var weeks = Set<String>()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for file in sorted {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: file.date)
            let key = "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
            if weeks.contains(key) { continue }
            guard weeks.count < policy.weekly else { break }
            weeks.insert(key); kept.insert(file.url)
        }
        return sorted.filter { !kept.contains($0.url) }
    }
    /// Yöneticinin açtığı 'otomatik uygula' tercihi için: günlük arşivden hemen sonra çalışır.
    /// Dosya listesi yeniden okunur; yalnız uygulamanın adlandırdığı, düz, bu klasördeki ZIP'ler silinir
    /// ve en yeni arşiv hiçbir koşulda silinmez.
    static func applyAutomatically(in directory: URL, policy: ArchiveRetentionPolicy) throws -> [URL] {
        let current = try files(in: directory)
        guard let newest = current.first else { return [] }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let plan = removals(from: current, policy: policy).filter {
            $0.url != newest.url && $0.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == root
        }
        var removed: [URL] = []
        for file in plan {
            try FileManager.default.removeItem(at: file.url)
            removed.append(file.url)
        }
        return removed
    }

    @MainActor static func removeVerified(_ selected: [ArchiveRetentionFile], in directory: URL) throws {
        try SchoolLibraryService.requireAdmin()
        let current = try files(in: directory)
        let byURL = Dictionary(uniqueKeysWithValues: current.map { ($0.url.standardizedFileURL, $0) })
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard Set(selected.map(\.url)).count == selected.count, selected.allSatisfy({ file in
            file.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == root
                && byURL[file.url.standardizedFileURL] == file
        }) else {
            throw FullArchive.ValidationError(message: "Arşiv listesi değişti. Güncel silme listesini yeniden inceleyin.")
        }
        for file in selected { try FileManager.default.removeItem(at: file.url) }
    }
}
