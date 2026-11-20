import Foundation
import Testing
@testable import KagitKit

/// URLSession isteklerini ağa çıkmadan yanıtlayan saplama.
final class SunucuSaplamasi: URLProtocol, @unchecked Sendable {
    struct Yanit {
        var durum = 200
        var govde = Data()
        var hata: URLError?
    }
    nonisolated(unsafe) static var isleyici: (@Sendable (URLRequest, Data?) -> Yanit)?
    nonisolated(unsafe) static var istekler: [(yontem: String, yol: String, sorgu: String?, baslik: [String: String], govde: Data?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var govde = request.httpBody
        if govde == nil, let akis = request.httpBodyStream {
            akis.open()
            var d = Data()
            var tampon = [UInt8](repeating: 0, count: 65536)
            while akis.hasBytesAvailable {
                let n = akis.read(&tampon, maxLength: tampon.count)
                if n <= 0 { break }
                d.append(tampon, count: n)
            }
            akis.close()
            govde = d
        }
        Self.istekler.append((request.httpMethod ?? "GET", request.url?.path ?? "", request.url?.query,
                              request.allHTTPHeaderFields ?? [:], govde))
        let y = Self.isleyici?(request, govde) ?? Yanit(durum: 500)
        if let hata = y.hata {
            client?.urlProtocol(self, didFailWithError: hata)
            return
        }
        let yanit = HTTPURLResponse(url: request.url!, statusCode: y.durum, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: yanit, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: y.govde)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func istemci(anahtar: String? = "gizli-anahtar") -> PDFStudioIstemcisi {
        let ayar = URLSessionConfiguration.ephemeral
        ayar.protocolClasses = [SunucuSaplamasi.self]
        return PDFStudioIstemcisi(taban: URL(string: "https://ornek.test/dersdas/claude/v1/pdf")!, anahtar: anahtar,
                                  oturum: URLSession(configuration: ayar), zamanAsimi: 5)
    }

    static func sifirla(_ i: @escaping @Sendable (URLRequest, Data?) -> Yanit) {
        istekler = []
        isleyici = i
    }
}

private func json(_ s: String) -> Data { Data(s.utf8) }

@Suite(.serialized) struct ModulASunucuTestleri {

    @Test func saglikImzasi() async throws {
        SunucuSaplamasi.sifirla { _, _ in .init(govde: json(#"{"status":"ok","app":"pdf-studio","version":"1.0.0"}"#)) }
        let s = SunucuSaplamasi.istemci()
        #expect(try await s.saglik() == "1.0.0")
        let i = SunucuSaplamasi.istekler[0]
        #expect(i.yol == "/dersdas/claude/v1/pdf/health")
        #expect(i.baslik["X-Personal-Token"] == "gizli-anahtar")

        SunucuSaplamasi.sifirla { _, _ in .init(govde: json(#"{"app":"baska"}"#)) }
        await #expect(throws: KagitHata.self) { try await SunucuSaplamasi.istemci().saglik() }
    }

    @Test func anahtarsizIstekBaslikEklemez() async throws {
        SunucuSaplamasi.sifirla { _, _ in .init(govde: json(#"{"app":"pdf-studio"}"#)) }
        _ = try await SunucuSaplamasi.istemci(anahtar: nil).saglik()
        #expect(SunucuSaplamasi.istekler[0].baslik["X-Personal-Token"] == nil)
    }

    @Test func officedenPDFTamAkis() async throws {
        let docx = Ornek.gecici("Ders Notu.docx")
        try Data("sahte docx".utf8).write(to: docx)
        let pdfVerisi = Ornek.pdf([["Dönüştürüldü"]])
        SunucuSaplamasi.sifirla { istek, govde in
            let yol = istek.url!.path
            switch (istek.httpMethod ?? "GET", yol) {
            case ("POST", let y) where y.hasSuffix("/api/upload"):
                #expect(istek.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                let metin = String(decoding: govde ?? Data(), as: UTF8.self)
                #expect(metin.contains("name=\"files\"; filename=\"Ders Notu.docx\""))
                #expect(metin.contains("sahte docx"))
                return .init(govde: json(#"{"session_id":"S1","files":[{"file_id":"F1","name":"Ders Notu.docx","size":10,"kind":"office","pages":null}]}"#))
            case ("POST", let y) where y.hasSuffix("/api/convert/word-to-pdf"):
                let g = (try? JSONSerialization.jsonObject(with: govde ?? Data())) as? [String: String]
                #expect(g?["session"] == "S1" && g?["file_id"] == "F1")
                return .init(govde: json(#"{"session_id":"S1","message":"ok","outputs":[{"file_id":"O1","name":"Ders Notu.pdf","size":1,"kind":"pdf","download_url":"/api/download/S1/O1"}]}"#))
            case ("GET", let y) where y.hasSuffix("/api/download/S1/O1"):
                return .init(govde: pdfVerisi)
            case ("DELETE", let y) where y.hasSuffix("/api/session"):
                #expect(istek.url?.query == "session=S1")
                return .init(govde: json("{}"))
            default: return .init(durum: 404, govde: json(#"{"detail":"yok"}"#))
            }
        }
        let cikti = try await SunucuSaplamasi.istemci().officedenPDF(docx)
        #expect(cikti.lastPathComponent == "Ders Notu.pdf")
        #expect(try Belge.ac(cikti).page(at: 0)?.string?.contains("Dönüştürüldü") == true)
        let yollar = SunucuSaplamasi.istekler.map { "\($0.yontem) \($0.yol.replacingOccurrences(of: "/dersdas/claude/v1/pdf", with: ""))" }
        #expect(yollar == ["POST /api/upload", "POST /api/convert/word-to-pdf", "GET /api/download/S1/O1", "DELETE /api/session"])
        // Her istekte anahtar var
        #expect(SunucuSaplamasi.istekler.allSatisfy { $0.baslik["X-Personal-Token"] == "gizli-anahtar" })
    }

    @Test func pdftenWordParolaGonderir() async throws {
        let pdf = try ornekDosya(1)
        SunucuSaplamasi.sifirla { istek, govde in
            let y = istek.url!.path
            if y.hasSuffix("/api/upload") {
                return .init(govde: json(#"{"session_id":"S2","files":[{"file_id":"F2","name":"ornek.pdf","size":10,"kind":"pdf","pages":1}]}"#))
            }
            if y.hasSuffix("/api/convert/pdf-to-word") {
                let g = (try? JSONSerialization.jsonObject(with: govde ?? Data())) as? [String: String]
                #expect(g?["password"] == "p4ss")
                return .init(govde: json(#"{"session_id":"S2","message":"ok","outputs":[{"file_id":"O2","name":"ornek.docx","size":1,"kind":"office","download_url":"x"}]}"#))
            }
            if y.contains("/api/download/") { return .init(govde: Data("docx".utf8)) }
            return .init(govde: json("{}"))
        }
        let d = try await SunucuSaplamasi.istemci().pdftenWord(pdf, parola: "p4ss")
        #expect(d.lastPathComponent == "ornek.docx")
        #expect(try Data(contentsOf: d) == Data("docx".utf8))
    }

    @Test func hataIletileriTurkce() async throws {
        let pdf = try ornekDosya(1)
        for (durum, parca) in [(401, "anahtar"), (403, "anahtar"), (413, "büyük"), (502, "yanıt vermiyor"), (400, "Tablo yok")] {
            SunucuSaplamasi.sifirla { _, _ in .init(durum: durum, govde: json(#"{"detail":"Tablo yok"}"#)) }
            do {
                _ = try await SunucuSaplamasi.istemci().pdftenExcel(pdf)
                Issue.record("hata bekleniyordu (\(durum))")
            } catch let h as KagitHata {
                guard case .sunucu(let m) = h else { Issue.record("sunucu hatası değil"); continue }
                #expect(m.localizedCaseInsensitiveContains(parca), "\(durum): \(m)")
            }
        }
    }

    @Test func zamanAsimiVeBaglantiHatalari() async throws {
        let pdf = try ornekDosya(1)
        for (kod, parca) in [(URLError.Code.timedOut, "zamanında"), (.notConnectedToInternet, "İnternet"), (.cannotFindHost, "ulaşılamadı")] {
            SunucuSaplamasi.sifirla { _, _ in .init(hata: URLError(kod)) }
            do {
                _ = try await SunucuSaplamasi.istemci().officedenPDF(pdf)
                Issue.record("hata bekleniyordu")
            } catch let h as KagitHata {
                guard case .sunucu(let m) = h else { Issue.record("sunucu hatası değil"); continue }
                #expect(m.contains(parca), "\(m)")
            }
        }
    }

    @Test func hataSonrasiOturumSilinir() async throws {
        let pdf = try ornekDosya(1)
        SunucuSaplamasi.sifirla { istek, _ in
            let y = istek.url!.path
            if y.hasSuffix("/api/upload") { return .init(govde: json(#"{"session_id":"S3","files":[{"file_id":"F3","name":"a.pdf","size":1,"kind":"pdf","pages":1}]}"#)) }
            if y.contains("/convert/") { return .init(durum: 400, govde: json(#"{"detail":"Dönüştürme başarısız"}"#)) }
            return .init(govde: json("{}"))
        }
        await #expect(throws: KagitHata.sunucu("Dönüştürme başarısız")) { try await SunucuSaplamasi.istemci().pdftenWord(pdf) }
        #expect(SunucuSaplamasi.istekler.last?.yontem == "DELETE")
    }

    @Test func bosYuklemeGirdisi() async {
        await #expect(throws: KagitHata.bosGirdi) { try await SunucuSaplamasi.istemci().yukle([]) }
    }

    /// Gerçek sunucu: KAGIT_CANLI=1 ve KAGIT_ANAHTAR tanımlıysa çalışır.
    @Test func canliSunucu() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KAGIT_CANLI"] == "1", let anahtar = env["KAGIT_ANAHTAR"] else { return }
        let taban = URL(string: env["KAGIT_SUNUCU"] ?? "https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/dersdas/claude/v1/pdf")!
        let s = PDFStudioIstemcisi(taban: taban, anahtar: anahtar, zamanAsimi: 120)
        _ = try await s.saglik()
        // PDF → Word
        let docx = try await s.pdftenWord(try yapiliPDF())
        let z = ZipOkuyucu.ac(try Data(contentsOf: docx))
        #expect(z["word/document.xml"] != nil)
        // Word → PDF (yerel DOCX üreticimizle)
        let pdf = try await s.officedenPDF(docx)
        let b = try Belge.ac(pdf)
        #expect(b.pageCount >= 1)
        #expect(b.string?.contains("Hücre") == true)
    }
}
