import Foundation

/// Uygulama ile paylaşım uzantısının ortak (App Group) klasörü.
enum OrtakKlasor {
    static let grup = "group.com.mehmetderin.kagit"

    /// Paylaşım uzantısının dosya bıraktığı klasör.
    static var gelenler: URL? {
        guard let kap = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) else { return nil }
        let u = kap.appendingPathComponent("Gelenler", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
