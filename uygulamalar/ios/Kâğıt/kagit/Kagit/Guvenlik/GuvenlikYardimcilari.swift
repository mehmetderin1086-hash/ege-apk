import Foundation

/// Ağır eşzamanlı işi ana iş parçacığından çıkarır (KagitKit'in eşzamanlı işlevleri bunu kendisi yapar).
func arkaplandaCalistir<T: Sendable>(_ is_: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated, operation: is_).value
}

extension URL {
    /// "Rapor.pdf" → "Rapor"
    var adSiz: String { deletingPathExtension().lastPathComponent }
}
