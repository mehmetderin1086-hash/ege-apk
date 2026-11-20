import Foundation
import Testing
@testable import _01

struct ArchiveRetentionTestleri {
    @Test func dailyAndWeeklySnapshotsKeepNewestWeekAndPreserveAllMode() throws {
        let first = try #require(ArchiveRetention.archiveDate("KitapArsivi-2026-08-01.zip"))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        let files = (0..<40).map { day in
            let date = first.addingTimeInterval(Double(day) * 86_400)
            return ArchiveRetentionFile(url: URL(fileURLWithPath: "/tmp/KitapArsivi-\(formatter.string(from: date)).zip"),
                date: date, bytes: 100, modifiedAt: date)
        }
        let removals = ArchiveRetention.removals(from: files, policy: .short)
        let kept = files.filter { !removals.contains($0) }
        #expect(kept.count > 7 && kept.count < 15)
        #expect(files.suffix(7).allSatisfy { kept.contains($0) })
        #expect(kept.contains(files[29])) // Sunday 30 August: newest file of its older ISO week.
        #expect(ArchiveRetention.removals(from: files, policy: .all).isEmpty)
        #expect(ArchiveRetention.archiveDate("KitapArsivi-2026-02-31.zip") == nil)
        #expect(ArchiveRetention.archiveDate("benim-yedegim.zip") == nil)
    }

    @MainActor @Test func changedArchiveRefusesDeletionAndUnrelatedFilesSurvive() throws {
        let oldRole = UserDefaults.standard.object(forKey: "roleLockEnabled")
        UserDefaults.standard.set(false, forKey: "roleLockEnabled")
        defer { UserDefaults.standard.set(oldRole, forKey: "roleLockEnabled") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appendingPathComponent("KitapArsivi-2026-09-01.zip")
        let unrelated = root.appendingPathComponent("baska-okul.zip")
        try Data([1]).write(to: owned); try Data([2]).write(to: unrelated)
        let initial = try ArchiveRetention.files(in: root)
        #expect(initial.count == 1)
        try Data([1, 2, 3]).write(to: owned)
        #expect(throws: FullArchive.ValidationError.self) { try ArchiveRetention.removeVerified(initial, in: root) }
        #expect(FileManager.default.fileExists(atPath: owned.path))
        try ArchiveRetention.removeVerified(ArchiveRetention.files(in: root), in: root)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(try Data(contentsOf: unrelated) == Data([2]))
    }
}
