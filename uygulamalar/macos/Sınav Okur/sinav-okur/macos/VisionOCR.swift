import AppKit
import Foundation
import Vision

struct MetinBlogu: Codable {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let alternatives: [OCRAdayi]
}

struct OCRAdayi: Codable {
    let metin: String
    let guven: Float
}

struct OCRSonucu: Codable {
    let width: Int
    let height: Int
    let blocks: [MetinBlogu]
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Kullanım: vision-ocr GÖRÜNTÜ [ÖZEL_KELİME ...]\n".utf8))
    exit(2)
}

let yol = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let resim = NSImage(contentsOf: yol),
    let cgResim = resim.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("Görüntü okunamadı.\n".utf8))
    exit(3)
}

let istek = VNRecognizeTextRequest()
istek.recognitionLevel = .accurate
istek.usesLanguageCorrection = true
istek.recognitionLanguages = ["tr-TR", "en-US"]
istek.customWords = [
    "Soru", "soru", "puan", "PUAN", "Biyoloji", "Fotosentez",
    "Hipofiz", "mitokondri", "kloroplast",
] + Array(CommandLine.arguments.dropFirst(2).prefix(160))

do {
    try VNImageRequestHandler(cgImage: cgResim, options: [:]).perform([istek])
    let bloklar = (istek.results ?? []).compactMap { gozlem -> MetinBlogu? in
        let adaylar = gozlem.topCandidates(3)
        guard let aday = adaylar.first else { return nil }
        let kutu = gozlem.boundingBox
        return MetinBlogu(
            text: aday.string,
            confidence: aday.confidence,
            x: kutu.origin.x,
            y: 1.0 - kutu.origin.y - kutu.height,
            width: kutu.width,
            height: kutu.height,
            alternatives: Array(adaylar.dropFirst()).map {
                OCRAdayi(metin: $0.string, guven: $0.confidence)
            }
        )
    }.sorted {
        if abs($0.y - $1.y) > 0.01 { return $0.y < $1.y }
        return $0.x < $1.x
    }
    let sonuc = OCRSonucu(
        width: cgResim.width,
        height: cgResim.height,
        blocks: bloklar
    )
    let kodlayici = JSONEncoder()
    kodlayici.outputFormatting = [.withoutEscapingSlashes]
    FileHandle.standardOutput.write(try kodlayici.encode(sonuc))
} catch {
    FileHandle.standardError.write(Data("Vision OCR hatası: \(error)\n".utf8))
    exit(4)
}
