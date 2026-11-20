import Foundation
import Observation
import SwiftUI

// Araç kutusu (Çalış sekmesi): veriler Application Support/Tools/<ad>.json dosyalarında tutulur.
// SwiftData şemasına dokunmaz; göç gerektirmez.

nonisolated enum DayKey {
    /// yyyy-MM-dd (yerel saat); `ListeningDay.key` ile aynı biçim.
    static func key(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "2026-10-06" → "6 Eki Sal"; çözülemeyen anahtar olduğu gibi döner.
    static func shortLabel(_ key: String, calendar: Calendar = .current) -> String {
        guard let day = Self.date(key, calendar: calendar) else { return key }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).weekday(.abbreviated).locale(Locale(identifier: "tr_TR"))
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }
}

@Observable
final class JSONStore<Item: Codable & Identifiable> {
    private var storage: [Item]
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var restoreObserver: (any NSObjectProtocol)?

    /// Her değişiklikte dosyaya yazılır.
    var items: [Item] {
        get { storage }
        set { storage = newValue; save() }
    }

    init(_ name: String, directory: URL? = nil) {
        let dir = directory ?? JSONStoreLocation.defaultDirectory
        url = dir.appending(path: "\(name).json")
        if let data = try? Data(contentsOf: url) {
            if let decoded = Self.decode(data) {
                storage = decoded
            } else {
                // Okunamayan dosya ezilmesin: kenara alınır, depo boş başlar.
                storage = []
                try? FileManager.default.moveItem(at: url, to: dir.appending(path: "\(name).bozuk-\(Int(Date.now.timeIntervalSince1970)).json"))
            }
        } else {
            storage = []
        }
        // Geri yükleme dosyaya kayıt ekleyince açık ekranın deposu eski listesini üzerine yazmasın.
        restoreObserver = NotificationCenter.default.addObserver(forName: JSONStoreLocation.restored, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    isolated deinit {
        if let restoreObserver { NotificationCenter.default.removeObserver(restoreObserver) }
    }

    private static func decode(_ data: Data) -> [Item]? { try? JSONDecoder().decode([Item].self, from: data) }

    /// Dosya dışarıdan değiştiyse (yedekten geri yükleme) liste dosyadan yeniden okunur.
    /// Dosya yoksa ya da çözülemiyorsa bellekteki liste kalır; dosyaya dokunulmaz.
    func reload() {
        guard let data = try? Data(contentsOf: url), let decoded = Self.decode(data) else { return }
        storage = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(storage) { try? data.write(to: url, options: .atomic) }
    }
}

nonisolated enum JSONStoreLocation {
    static var defaultDirectory: URL { URL.applicationSupportDirectory.appending(path: "Tools", directoryHint: .isDirectory) }

    /// Geri yükleme araç kutusu dosyalarına yazınca yayımlanır; açık `JSONStore`lar listesini dosyadan yeniden okur.
    static let restored = Notification.Name("dersdas.tools.restored")

    /// Yedekten geri yükleme: yalnız cihazda olmayan dosyalar kopyalanır (mevcut veri ezilmez). Dönen değer kopyalanan dosya sayısı.
    @discardableResult
    static func restore(from source: URL, to target: URL = defaultDirectory) -> Int {
        let fm = FileManager.default
        var copied = 0
        for file in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        where ["json", "drawing"].contains(file.pathExtension.lowercased()) {
            let destination = target.appending(path: file.lastPathComponent)
            guard !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            if (try? fm.copyItem(at: file, to: destination)) != nil { copied += 1 }
        }
        return copied
    }
}

// MARK: - Modeller

nonisolated struct MockExam: Codable, Identifiable, Hashable, Sendable {
    struct Row: Codable, Identifiable, Hashable, Sendable {
        var id = UUID()
        var name = ""
        var correct = 0
        var wrong = 0
        var blank = 0
    }
    var id = UUID()
    var title = ""
    var date = Date.now
    /// Kaç yanlış bir doğruyu götürür (0 = götürmez).
    var penalty = 4
    var rows: [Row] = [Row()]

    var net: Double { rows.reduce(0) { $0 + ExamMath.net(correct: $1.correct, wrong: $1.wrong, penalty: penalty) } }
}

nonisolated extension MockExam {
    /// Yeni deneme taslağı: önceki denemenin ders adları ve ceza kuralıyla, sayılar ve başlık boş; önceki yoksa tek boş satır.
    static func next(after previous: MockExam?) -> MockExam {
        guard let previous, !previous.rows.isEmpty else { return MockExam() }
        return MockExam(penalty: previous.penalty, rows: previous.rows.map { Row(name: $0.name) })
    }
}

nonisolated struct GradeCourse: Codable, Identifiable, Hashable, Sendable {
    struct Entry: Codable, Identifiable, Hashable, Sendable {
        var id = UUID()
        var title = ""
        var score = 0.0
        /// Yüzde ağırlık (0–100).
        var weight = 0.0
    }
    var id = UUID()
    var name = ""
    var target = 70.0
    var entries: [Entry] = []

    var pairs: [(score: Double, weight: Double)] { entries.map { ($0.score, $0.weight) } }
}

nonisolated struct AbsenceCourse: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var limit = 10
    /// Devamsızlık günleri (yyyy-MM-dd); aynı gün birden çok kez olabilir (ders saati).
    var days: [String] = []
}

nonisolated struct Countdown: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var date = Date.now
}

nonisolated struct QuestionLog: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var day = DayKey.key()
    var course = ""
    var solved = 0
    var wrong = 0
}

nonisolated struct Habit: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var days: Set<String> = []
}

nonisolated struct StudyGoal: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var target = 5
    var done = 0
    var deadline: Date?
}

nonisolated struct TodoItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var urgent = false
    var important = true
    var done = false
    var createdAt = Date.now
}

nonisolated struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var day = DayKey.key()
    /// 1 (kötü) … 5 (harika)
    var mood = 3
    var learned = ""
    var hard = ""
    var tomorrow = ""
}

nonisolated struct RevisionTopic: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var course = ""
    /// Son çalışma/tekrar günü; sıradaki tekrar buna göre hesaplanır.
    var anchor = Date.now
    var doneSteps = 0

    var nextDue: Date? { RevisionPlan.nextDue(anchor: anchor, doneSteps: doneSteps) }
}

nonisolated struct ReadingBook: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var totalPages = 200
    var currentPage = 0
    /// Gün → o gün okunan sayfa.
    var log: [String: Int] = [:]
}

nonisolated extension ReadingBook {
    /// Kalınan sayfayı ayarlar (0…totalPages). O günün okuma kaydı fark kadar değişir; geri alınan sayfa günü eksiye düşürmez.
    mutating func setPage(_ page: Int, dayKey: String = DayKey.key()) {
        let next = max(0, min(totalPages, page))
        log[dayKey] = max(0, (log[dayKey] ?? 0) + next - currentPage)
        currentPage = next
    }
}

nonisolated struct OwnQuote: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text = ""
}

// MARK: - Ortak görünüm iskeleti

/// Araç ekranlarının ortak çerçevesi: başlık + "Kapat".
struct ToolScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
                .debugNarrowScreen()
        }
    }
}

/// Sayı alanı: etiket üstte, dar ekranda taşmaz.
/// 0 boş gösterilir (yer tutucu): alana dokunup yazılan rakam eski "0"ın yanına eklenmez.
struct NumberField: View {
    var label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: Binding<Int?>(get: { value == 0 ? nil : value }, set: { value = max(0, $0 ?? 0) }), format: .number, prompt: Text("0"))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
        }
    }
}

extension Double {
    /// 12.5 → "12,5"; 12.0 → "12"
    var shortText: String {
        let rounded = (self * 100).rounded() / 100
        return rounded.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR")))
    }
}
