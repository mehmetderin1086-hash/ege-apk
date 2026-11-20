import Compression
import Foundation

/// .docx (ZIP içinde word/document.xml) dosyasından düz metin çıkarır.
nonisolated enum DocxTextExtractor {
    enum DocxError: LocalizedError {
        case notZip, missingDocument, unsupportedCompression, corrupt, tooLarge
        var errorDescription: String? {
            switch self {
            case .tooLarge: "Word dosyası çok büyük. Belgeyi bölerek veya PDF olarak eklemeyi dene."
            case .notZip, .corrupt: "Word dosyası okunamadı. Dosya bozuk olabilir."
            case .missingDocument: "Bu dosyada Word metni bulunamadı."
            case .unsupportedCompression: "Bu Word dosyasının sıkıştırma biçimi desteklenmiyor."
            }
        }
    }

    static func extractText(from data: Data) throws -> String {
        let xml = try ZipReader.entry(named: "word/document.xml", in: data)
        return DocumentXMLParser.text(from: xml)
    }
}

nonisolated enum ZipReader {
    static func entry(named name: String, in data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { throw DocxTextExtractor.DocxError.notZip }

        // End of central directory kaydını sondan geriye doğru ara.
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if bytes.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw DocxTextExtractor.DocxError.notZip }

        let entryCount = Int(bytes.u16(eocd + 10))
        var offset = Int(bytes.u32(eocd + 16))

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, bytes.u32(offset) == 0x0201_4B50 else { throw DocxTextExtractor.DocxError.corrupt }
            let method = bytes.u16(offset + 10)
            let compressedSize = Int(bytes.u32(offset + 20))
            let uncompressedSize = Int(bytes.u32(offset + 24))
            let nameLength = Int(bytes.u16(offset + 28))
            let extraLength = Int(bytes.u16(offset + 30))
            let commentLength = Int(bytes.u16(offset + 32))
            let localOffset = Int(bytes.u32(offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw DocxTextExtractor.DocxError.corrupt }
            let entryName = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)

            if entryName == name {
                guard localOffset + 30 <= bytes.count, bytes.u32(localOffset) == 0x0403_4B50 else { throw DocxTextExtractor.DocxError.corrupt }
                let start = localOffset + 30 + Int(bytes.u16(localOffset + 26)) + Int(bytes.u16(localOffset + 28))
                guard start + compressedSize <= bytes.count else { throw DocxTextExtractor.DocxError.corrupt }
                let payload = Array(bytes[start..<(start + compressedSize)])
                switch method {
                case 0: return Data(payload)
                case 8: return try inflate(payload, expectedSize: uncompressedSize)
                default: throw DocxTextExtractor.DocxError.unsupportedCompression
                }
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        throw DocxTextExtractor.DocxError.missingDocument
    }

    /// Ham DEFLATE açma (Apple'ın COMPRESSION_ZLIB'i başlıksız ham deflate'tir).
    static let maxInflatedSize = 64 * 1024 * 1024

    private static func inflate(_ input: [UInt8], expectedSize: Int) throws -> Data {
        // Dosyadaki boyut alanına güvenme (ZIP64/bozuk dosyada 0xFFFFFFFF olabilir); üst sınır uygula.
        // +1 bayt: tampon tam dolarsa çıktının kırpıldığını anlayabilmek için.
        let capacity = min(max(expectedSize, input.count * 4, 1024), maxInflatedSize) + 1
        var output = [UInt8](repeating: 0, count: capacity)
        let written = output.withUnsafeMutableBufferPointer { dst in
            input.withUnsafeBufferPointer { src in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw DocxTextExtractor.DocxError.corrupt }
        guard written < capacity else { throw DocxTextExtractor.DocxError.tooLarge }
        return Data(output[0..<written])
    }
}

/// word/document.xml → paragraflar. <w:t> metinleri, <w:tab/> sekme, <w:br/> satır sonu, </w:p> paragraf sonu.
nonisolated final class DocumentXMLParser: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var current = ""
    private var inText = false

    static func text(from xml: Data) -> String {
        let delegate = DocumentXMLParser()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.parse()
        if !delegate.current.isEmpty { delegate.paragraphs.append(delegate.current) }
        return delegate.paragraphs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "w:t": inText = true
        case "w:tab": current += "\t"
        case "w:br", "w:cr": current += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:p":
            paragraphs.append(current)
            current = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }
}

nonisolated private extension [UInt8] {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}
