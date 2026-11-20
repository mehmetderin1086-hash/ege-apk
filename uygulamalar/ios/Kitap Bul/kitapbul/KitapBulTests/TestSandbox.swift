import Foundation
import Testing
@testable import _01

/// Geçici dizin + izole UserDefaults paketi. `StoreLocations.current` ve eski `directoryOverride`
/// alanları çıkışta (hata olsa da) önceki değerine döner; iç içe çağrıda dıştaki değer korunur.
@MainActor
struct TestSandbox {
    let root: URL
    let suiteName: String
    let locations: StoreLocations
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private static func make() throws -> (URL, String) {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-" + id, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, "kitapbul.test." + id)
    }

    /// Askıya alma noktası olmadığından MainActor üzerinde bölünmez: paralel koşan başka testler araya giremez.
    /// Bütün depo yollarını (çöp, otomatik arşiv, kademe kuralı, sayım dahil) geçici dizine çevirir.
    @discardableResult
    static func runSync<T>(_ body: (TestSandbox) throws -> T) throws -> T {
        let (root, suite) = try make()
        let restore = StoreLocations.install(.isolated(root: root, defaultsSuite: suite))
        defer {
            restore()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return try body(TestSandbox(root: root, suiteName: suite, locations: StoreLocations.current))
    }

    /// Asenkron gövde araya girilebilir; bu yüzden yalnız tek bir suite'e özel klasörleri bağlar.
    @discardableResult
    static func run<T>(_ body: (TestSandbox) async throws -> T) async throws -> T {
        let (root, suite) = try make()
        let restore = StoreLocations.install(.isolated(root: root, defaultsSuite: suite), includeSharedStores: false)
        defer {
            restore()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return try await body(TestSandbox(root: root, suiteName: suite, locations: StoreLocations.current))
    }
}
