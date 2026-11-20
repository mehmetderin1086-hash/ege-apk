import Foundation

/// VPS'teki PDF Studio'nun (FastAPI) dönüşüm uçlarını kullanan istemci.
///
/// Akış: yükle → dönüştür → indir (→ oturumu sil). Taban adres `…/pdf` biçimindedir;
/// istek yolları `<taban>/api/...`, sağlık ucu `<taban>/health`.
public struct PDFStudioIstemcisi: Sendable {
    public let taban: URL
    public let anahtar: String?
    public let zamanAsimi: TimeInterval
    private let oturum: URLSession

    public init(taban: URL, anahtar: String?, oturum: URLSession = .shared, zamanAsimi: TimeInterval = 240) {
        self.taban = taban
        self.anahtar = anahtar
        self.oturum = oturum
        self.zamanAsimi = zamanAsimi
    }

    // MARK: Veri türleri

    public struct YuklenenDosya: Decodable, Sendable, Equatable {
        public let fileId: String
        public let name: String
        public let size: Int
        public let kind: String
        public let pages: Int?
        enum CodingKeys: String, CodingKey { case fileId = "file_id", name, size, kind, pages }
    }

    struct YuklemeYaniti: Decodable {
        let sessionId: String
        let files: [YuklenenDosya]
        enum CodingKeys: String, CodingKey { case sessionId = "session_id", files }
    }

    public struct Cikti: Decodable, Sendable, Equatable {
        public let fileId: String
        public let name: String
        public let size: Int
        public let kind: String
        public let downloadUrl: String
        enum CodingKeys: String, CodingKey { case fileId = "file_id", name, size, kind, downloadUrl = "download_url" }
    }

    public struct Sonuc: Decodable, Sendable {
        public let sessionId: String
        public let message: String
        public let outputs: [Cikti]
        enum CodingKeys: String, CodingKey { case sessionId = "session_id", message, outputs }
    }

    struct DosyaGovdesi: Encodable, Sendable {
        let session: String
        let fileId: String
        let password: String?
        enum CodingKeys: String, CodingKey { case session, fileId = "file_id", password }
    }

    // MARK: İstek yardımcıları

    func adres(_ yol: String, sorgu: [String: String] = [:]) throws -> URL {
        var metin = taban.absoluteString
        while metin.hasSuffix("/") { metin.removeLast() }
        guard var bilesen = URLComponents(string: metin + "/" + yol) else { throw KagitHata.sunucu("Sunucu adresi geçersiz.") }
        if !sorgu.isEmpty { bilesen.queryItems = sorgu.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = bilesen.url else { throw KagitHata.sunucu("Sunucu adresi geçersiz.") }
        return url
    }

    func istek(_ yol: String, yontem: String = "GET", sorgu: [String: String] = [:], zamanAsimi: TimeInterval? = nil) throws -> URLRequest {
        var r = URLRequest(url: try adres(yol, sorgu: sorgu), timeoutInterval: zamanAsimi ?? self.zamanAsimi)
        r.httpMethod = yontem
        if let anahtar, !anahtar.isEmpty { r.setValue(anahtar, forHTTPHeaderField: "X-Personal-Token") }
        return r
    }

    /// Ağ ve HTTP hatalarını Türkçe `KagitHata.sunucu`'ya çevirir.
    func hataCevir(_ hata: Error) -> Error {
        if hata is CancellationError || (hata as? KagitHata) != nil { return hata }
        if let u = hata as? URLError {
            switch u.code {
            case .cancelled: return CancellationError()
            case .timedOut: return KagitHata.sunucu("Sunucu zamanında yanıt vermedi. Dosya büyükse daha sonra yeniden deneyin.")
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return KagitHata.sunucu("İnternet bağlantısı yok.")
            case .networkConnectionLost: return KagitHata.sunucu("Bağlantı yarıda kesildi.")
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                return KagitHata.sunucu("Sunucuya ulaşılamadı. Adresi kontrol edin.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                return KagitHata.sunucu("Güvenli bağlantı kurulamadı (sertifika).")
            default: return KagitHata.sunucu(u.localizedDescription)
            }
        }
        return KagitHata.sunucu(hata.localizedDescription)
    }

    func durumuDenetle(_ yanit: URLResponse, veri: Data?) throws {
        guard let http = yanit as? HTTPURLResponse else { throw KagitHata.sunucu("Sunucudan geçersiz yanıt geldi.") }
        guard !(200..<300).contains(http.statusCode) else { return }
        var detay: String?
        if let veri, let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] {
            detay = j["detail"] as? String
        }
        switch http.statusCode {
        case 401, 403: throw KagitHata.sunucu("Erişim anahtarı reddedildi. Ayarlar'dan sunucu anahtarını kontrol edin.")
        case 404: throw KagitHata.sunucu(detay ?? "Sunucuda kaynak bulunamadı (oturum süresi dolmuş olabilir).")
        case 413: throw KagitHata.sunucu("Dosya sunucu için çok büyük.")
        case 502, 503, 504: throw KagitHata.sunucu("PDF Studio şu an yanıt vermiyor (\(http.statusCode)). Biraz sonra yeniden deneyin.")
        default: throw KagitHata.sunucu(detay ?? "İşlem başarısız (HTTP \(http.statusCode)).")
        }
    }

    // MARK: Uçlar

    /// `/health` imzasını denetler. Başarılıysa sürümü (varsa) döndürür.
    @discardableResult
    public func saglik() async throws -> String {
        do {
            let (veri, yanit) = try await oturum.data(for: try istek("health", zamanAsimi: 15))
            try durumuDenetle(yanit, veri: veri)
            guard let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any], j["app"] as? String == "pdf-studio" else {
                throw KagitHata.sunucu("Bu adreste PDF Studio bulunamadı.")
            }
            return j["version"] as? String ?? ""
        } catch {
            throw hataCevir(error)
        }
    }

    /// Dosyaları yeni (ya da verilen) oturuma yükler.
    public func yukle(_ dosyalar: [URL], oturumId: String? = nil) async throws -> (oturumId: String, dosyalar: [YuklenenDosya]) {
        guard !dosyalar.isEmpty else { throw KagitHata.bosGirdi }
        let sinir = "KagitSinir-\(UUID().uuidString)"
        let govde = Gecici.klasor().appendingPathComponent("yukleme.bin")
        FileManager.default.createFile(atPath: govde.path, contents: nil)
        do {
            let h = try FileHandle(forWritingTo: govde)
            if let oturumId {
                try h.write(contentsOf: Data("--\(sinir)\r\nContent-Disposition: form-data; name=\"session_id\"\r\n\r\n\(oturumId)\r\n".utf8))
            }
            for u in dosyalar {
                let erisim = u.startAccessingSecurityScopedResource()
                defer { if erisim { u.stopAccessingSecurityScopedResource() } }
                let ad = u.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
                try h.write(contentsOf: Data("--\(sinir)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(ad)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                // Parça parça kopyala (büyük dosyada bellek şişmesin)
                let okuyucu = try FileHandle(forReadingFrom: u)
                defer { try? okuyucu.close() }
                while let parca = try okuyucu.read(upToCount: 1 << 20), !parca.isEmpty { try h.write(contentsOf: parca) }
                try h.write(contentsOf: Data("\r\n".utf8))
            }
            try h.write(contentsOf: Data("--\(sinir)--\r\n".utf8))
            try h.close()
        } catch {
            throw KagitHata.sunucu("Dosya gönderime hazırlanamadı: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: govde.deletingLastPathComponent()) }
        var r = try istek("api/upload", yontem: "POST")
        r.setValue("multipart/form-data; boundary=\(sinir)", forHTTPHeaderField: "Content-Type")
        do {
            let (veri, yanit) = try await oturum.upload(for: r, fromFile: govde)
            try durumuDenetle(yanit, veri: veri)
            let y = try JSONDecoder().decode(YuklemeYaniti.self, from: veri)
            return (y.sessionId, y.files)
        } catch {
            throw hataCevir(error)
        }
    }

    /// Dönüştürme ucunu çağırır (ör. "api/convert/pdf-to-word").
    public func donustur(uc: String, oturumId: String, dosyaId: String, parola: String? = nil) async throws -> Sonuc {
        var r = try istek(uc, yontem: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(DosyaGovdesi(session: oturumId, fileId: dosyaId, password: parola))
        do {
            let (veri, yanit) = try await oturum.data(for: r)
            try durumuDenetle(yanit, veri: veri)
            let s = try JSONDecoder().decode(Sonuc.self, from: veri)
            guard !s.outputs.isEmpty else { throw KagitHata.sunucu("Sunucu çıktı üretmedi.") }
            return s
        } catch {
            throw hataCevir(error)
        }
    }

    /// Çıktıyı indirip geçici dosyaya yazar.
    public func indir(_ cikti: Cikti, oturumId: String) async throws -> URL {
        let r = try istek("api/download/\(oturumId)/\(cikti.fileId)")
        do {
            let (gecici, yanit) = try await oturum.download(for: r)
            let kucuk = try? Data(contentsOf: gecici, options: .mappedIfSafe).prefix(2048)
            try durumuDenetle(yanit, veri: kucuk.map { Data($0) })
            let hedef = Gecici.dosya(cikti.name)
            try FileManager.default.moveItem(at: gecici, to: hedef)
            return hedef
        } catch {
            throw hataCevir(error)
        }
    }

    /// Sunucudaki geçici dosyaları siler (hata yutulur).
    public func oturumuSil(_ oturumId: String) async {
        guard let r = try? istek("api/session", yontem: "DELETE", sorgu: ["session": oturumId], zamanAsimi: 20) else { return }
        _ = try? await oturum.data(for: r)
    }

    // MARK: Üst düzey dönüşümler

    private func tekDosyaDonustur(_ dosya: URL, uc: String, parola: String? = nil) async throws -> URL {
        let (oturumId, yuklenen) = try await yukle([dosya])
        guard let ilk = yuklenen.first else { throw KagitHata.sunucu("Yükleme doğrulanamadı.") }
        do {
            let sonuc = try await donustur(uc: uc, oturumId: oturumId, dosyaId: ilk.fileId, parola: parola)
            let cikti = sonuc.outputs.first!
            let yol = try await indir(cikti, oturumId: oturumId)
            await oturumuSil(oturumId)
            return yol
        } catch {
            await oturumuSil(oturumId)
            throw error
        }
    }

    /// DOCX/DOC/XLSX/PPTX/ODT… → PDF (LibreOffice).
    public func officedenPDF(_ dosya: URL) async throws -> URL {
        try await tekDosyaDonustur(dosya, uc: "api/convert/word-to-pdf")
    }

    public func pdftenWord(_ pdf: URL, parola: String? = nil) async throws -> URL {
        try await tekDosyaDonustur(pdf, uc: "api/convert/pdf-to-word", parola: parola)
    }

    public func pdftenExcel(_ pdf: URL, parola: String? = nil) async throws -> URL {
        try await tekDosyaDonustur(pdf, uc: "api/convert/pdf-to-excel", parola: parola)
    }
}
