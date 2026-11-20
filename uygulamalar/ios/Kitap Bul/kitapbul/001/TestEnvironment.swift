import Foundation

/// Test bayraklarının tek okunduğu yer. Release derlemesinde hepsi sabit false'tur.
nonisolated enum TestEnvironment {
#if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    /// `-ui-testing` argümanı: izole fikstür deposu ve geçici dizinler.
    static let isUITesting = arguments.contains("-ui-testing")
    /// `-ui-testing-readonly`: gerçek depoyla açılır, açılış işleri (bütünlük onarımı, çöp temizliği,
    /// bildirim, otomatik arşiv) atlanır.
    static let isReadOnlyUITesting = arguments.contains("-ui-testing-readonly")
    /// Birim test ana bilgisayarı (XCTest ortamı).
    static let isXCTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#else
    static let isUITesting = false
    static let isReadOnlyUITesting = false
    static let isXCTestHost = false
#endif
    /// Açılış yan etkilerini (bildirim, arşiv, ağ) kapatması gereken her ortam.
    static var suppressesLaunchSideEffects: Bool { isUITesting || isReadOnlyUITesting || isXCTestHost }
}
