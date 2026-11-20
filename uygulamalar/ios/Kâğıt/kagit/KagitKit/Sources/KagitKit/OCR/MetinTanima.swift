import CoreGraphics
import Foundation
import PDFKit
import Vision

/// OCR ile tanınan bir satır. `kutu` görüntüye göre normalize (0...1, sol alt köken).
public struct OCRSatiri: Sendable, Hashable {
    public let metin: String
    public let kutu: CGRect
    public let guven: Float
}

/// Vision ile cihaz içi metin tanıma (Türkçe + İngilizce).
public enum MetinTanima {
    public static let varsayilanDiller = ["tr-TR", "en-US"]

    /// Görüntüdeki metin satırları (yukarıdan aşağıya sıralı).
    public static func tani(_ goruntu: CGImage, diller: [String] = varsayilanDiller, hizli: Bool = false) async throws -> [OCRSatiri] {
        var istek = RecognizeTextRequest()
        istek.recognitionLevel = hizli ? .fast : .accurate
        istek.recognitionLanguages = diller.map { Locale.Language(identifier: $0) }
        istek.usesLanguageCorrection = true
        let gozlemler = try await istek.perform(on: goruntu)
        return gozlemler.compactMap { g -> OCRSatiri? in
            guard let aday = g.topCandidates(1).first else { return nil }
            let b = g.boundingBox
            return OCRSatiri(metin: TurkceMetin.ocrDuzelt(aday.string),
                             kutu: CGRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height),
                             guven: aday.confidence)
        }
        .sorted { abs($0.kutu.midY - $1.kutu.midY) > 0.008 ? $0.kutu.midY > $1.kutu.midY : $0.kutu.minX < $1.kutu.minX }
    }

    /// PDF sayfasını görüntüye çevirip tanır. `bolge` sayfa koordinatında (verilmezse tüm sayfa).
    public static func tani(sayfa: PDFPage, dpi: CGFloat = 200, diller: [String] = varsayilanDiller) async throws -> [OCRSatiri] {
        guard let g = PDFCizim.goruntu(sayfa, dpi: dpi) else { return [] }
        return try await tani(g, diller: diller)
    }

    /// Satırları düz metne birleştirir.
    public static func metin(_ satirlar: [OCRSatiri]) -> String {
        satirlar.map(\.metin).joined(separator: "\n")
    }
}
