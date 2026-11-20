import Foundation
import NaturalLanguage

/// Türkçe cümle gömlemesi (Apple NLContextualEmbedding, 512 boyut, cihaz içi). Varlık yoksa indirmeyi ister; yoksa nil döner.
nonisolated final class Gomlemci: Sendable {
    static let paylasilan = Gomlemci()
    nonisolated(unsafe) private let gomleme: NLContextualEmbedding?  // sınıf kendi içinde seri kullanır
    private let kilit = NSLock()
    nonisolated(unsafe) private var yuklendi = false

    init() { gomleme = NLContextualEmbedding(language: .turkish) }

    var hazir: Bool { gomleme?.hasAvailableAssets ?? false }

    /// Varlıkları indirir (Wi-Fi'de bir kez). Başarısızsa sessizce false.
    func hazirla() async -> Bool {
        guard let g = gomleme else { return false }
        if g.hasAvailableAssets { return true }
        let sonuc = try? await g.requestAssets()
        return sonuc == .available
    }

    /// Ortalama havuzlanmış, birim uzunluklu vektör.
    func vektor(_ metin: String) -> [Float]? {
        guard let g = gomleme, g.hasAvailableAssets else { return nil }
        return kilit.withLock {
            if !yuklendi { yuklendi = (try? g.load()) != nil }
            guard yuklendi, let r = try? g.embeddingResult(for: metin, language: .turkish) else { return nil }
            return Self.havuzla(r, boyut: g.dimension)
        }
    }

    private static func havuzla(_ r: NLContextualEmbeddingResult, boyut: Int) -> [Float]? {
        do {
        var toplam = [Double](repeating: 0, count: boyut)
        var n = 0
        r.enumerateTokenVectors(in: r.string.startIndex..<r.string.endIndex) { v, _ in
            for i in 0..<min(v.count, toplam.count) { toplam[i] += v[i] }
            n += 1
            return true
        }
        guard n > 0 else { return nil }
        return Self.birim(toplam.map { Float($0 / Double(n)) })
        }
    }

    static func birim(_ v: [Float]) -> [Float] {
        let norm = (v.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }

    static func kosinus(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    static func veri(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func vektor(_ d: Data) -> [Float] {
        d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
