import Foundation

/// Test örneğinin ömrüne bağlı temizlik. Swift Testing her test için suit (struct) örneğini yeniden kurar ve test bitince
/// serbest bırakır; suit bir `let temizlik = TestTemizligi()` alanı tutarsa kayıtlı UserDefaults alanları ve geçici
/// dosya/klasörler o anda (deinit) silinir. Test başına `defer` yazmak gerekmez.
nonisolated final class TestTemizligi: @unchecked Sendable {
    private let kilit = NSLock()
    private var isler: [@Sendable () -> Void] = []

    /// Bu suit örneğinin ömrü boyunca yaşayan, sonra silinen UserDefaults alanı.
    func suit(_ onek: String) -> UserDefaults {
        let ad = "\(onek).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ad)!
        kaydet { UserDefaults(suiteName: ad)?.removePersistentDomain(forName: ad) }
        return d
    }

    /// Geçici dosya ya da klasörü (varsa) sonunda silinmek üzere kaydeder; aynı URL'i döndürür.
    @discardableResult
    func gecici(_ url: URL) -> URL {
        kaydet { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func kaydet(_ is_: @escaping @Sendable () -> Void) {
        kilit.lock(); defer { kilit.unlock() }
        isler.append(is_)
    }

    deinit { for is_ in isler.reversed() { is_() } }
}
