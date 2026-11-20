#if DEBUG
import Foundation
import SwiftData

/// Yalnız açık test argümanı ile devreye girer; kullanıcının deposu/JSON dosyaları açılmaz.
@MainActor
enum LibraryUITestFixture {
    static func makeContainer() throws -> ModelContainer {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-home-actions-reset") {
            UserDefaults.standard.removeObject(forKey: HomeQuickActionPreferences.uiTestKey)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-navigation") {
            UserDefaults.standard.removeObject(forKey: "kitaplarSearch")
            UserDefaults.standard.removeObject(forKey: "kitaplarScrollAnchor")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UI-Fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Bütün yan dosya depoları (öğrenci, üye, geçmiş, sayım, tarama, çöp, otomatik arşiv) tek çağrıyla geçici dizinde.
        // Süreç ömrü boyunca kalır; geri alma kapanışı bilerek kullanılmaz.
        _ = StoreLocations.install(.isolated(root: directory))
        try ArchiveSwitchUITestFixture.configure(directory: directory)
        let store = try KitapVeritabani.makeContainer(inMemory: true)
        let context = store.mainContext
        let available = CatalogBook(book: Book(title: "Deneme Kitabı", author: "Deneme Yazarı", isbn: "9786053607021", quantity: 3,
                                               shelf: "2", cabinet: "3"))
        let overdue = CatalogBook(book: Book(title: "Geciken Kitap", author: "Deneme Yazarı", quantity: 2))
        let today = CatalogBook(book: Book(title: "Bugün İade", author: "Deneme Yazarı", quantity: 2))
        [available, overdue, today].forEach(context.insert)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-scroll-catalog") {
            for index in 1...60 {
                let id = UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", index))!
                context.insert(CatalogBook(book: Book(id: id, title: String(format: "Kaydırma Kitabı %02d", index), author: "Deneme Yazarı", quantity: 1)))
            }
        }
        let student = Student(name: "Deneme Öğrencisi", number: "101", className: "7/A")
        try StudentStore.replaceAllVerified([student])
        let late = ActiveLoan(bookID: overdue.id, bookTitleSnapshot: overdue.title, studentName: student.name,
                              studentClass: student.className, dueDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!)
        late.studentID = student.id
        let due = ActiveLoan(bookID: today.id, bookTitleSnapshot: today.title, studentName: "Bugünün Okuru",
                             studentClass: "8/A", dueDate: Calendar.current.startOfDay(for: .now))
        context.insert(late); context.insert(due)
        try context.save()
        try ArchiveSwitchUITestFixture.seed(context: context)
        return store
    }
}
#endif
