// macOS Vision OCR yardımcı programı.
//
// PyObjC'nin bazı macOS/Python birleşimlerinde performRequests_error_ çağrısı
// hata nesnesi vermeden false dönebiliyor. Bu küçük yerel yardımcı aynı Vision
// isteğini Swift üzerinden çalıştırır ve normalize kutuları JSON olarak basar.

import Foundation
import Vision

struct OCRAdayi: Codable {
    let metin: String
    let guven: Float
}

struct OCRSatiri: Codable {
    let metin: String
    let kutu: [Double]
    let guven: Float
    let adaylar: [OCRAdayi]
}

func hata(_ mesaj: String, kod: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((mesaj + "\n").utf8))
    exit(kod)
}

@main
struct VisionOCR {
    static func main() async {
        guard (2...3).contains(CommandLine.arguments.count) else {
            hata("kullanım: vision_ocr <görsel> [dil-düzeltme:0|1]")
        }

        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        var istek = RecognizeTextRequest()
        istek.recognitionLevel = .accurate
        istek.recognitionLanguages = [Locale.Language(identifier: "tr-TR"),
                                      Locale.Language(identifier: "en-US")]
        istek.usesLanguageCorrection = CommandLine.arguments.count < 3
            || CommandLine.arguments[2] != "0"

        let gozlemler: [RecognizedTextObservation]
        do {
            gozlemler = try await istek.perform(on: url)
        } catch {
            hata("Vision OCR başarısız: \(error.localizedDescription)")
        }

        let satirlar: [OCRSatiri] = gozlemler.compactMap { gozlem in
            let enIyi = gozlem.topCandidates(3)
            guard let aday = enIyi.first else { return nil }
            let metin = aday.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metin.isEmpty else { return nil }
            let noktalar = [gozlem.topLeft, gozlem.topRight,
                            gozlem.bottomRight, gozlem.bottomLeft]
            let xs = noktalar.map(\.x)
            let ys = noktalar.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            return OCRSatiri(
                metin: metin,
                kutu: [Double(minX), Double(1.0 - maxY),
                       Double(maxX), Double(1.0 - minY)],
                guven: aday.confidence,
                adaylar: enIyi.map { OCRAdayi(metin: $0.string,
                                              guven: $0.confidence) }
            )
        }

        do {
            let veri = try JSONEncoder().encode(satirlar)
            FileHandle.standardOutput.write(veri)
        } catch {
            hata("OCR sonucu JSON'a çevrilemedi: \(error.localizedDescription)")
        }
    }
}
