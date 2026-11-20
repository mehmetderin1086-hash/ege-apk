import Foundation
import Observation
import PDFKit

nonisolated struct CalismaYetenekleri: Decodable, Sendable {
    nonisolated struct Sinirlar: Decodable, Sendable {
        let file_bytes: Int64
        let storage_bytes: Int64
        let chunk_bytes: Int?
        let research_source_bytes: Int64?
    }
    let version: Int
    let modules: [String: Bool]
    let paid_enabled: Bool
    let limits: Sinirlar?
    var arastirmaKaynakSiniri: Int64 {
        guard modules["source_retrieval"] == true, let sinir = limits?.research_source_bytes, sinir > 0 else { return 200_000 }
        return min(sinir, 64 * 1024 * 1024)
    }
}

nonisolated struct CalismaGorevi: Decodable, Identifiable, Sendable {
    nonisolated struct Istek: Decodable, Sendable {
        nonisolated struct Girdi: Decodable, Sendable { let prompt: String }
        let input: Girdi
    }
    let id: String
    let kind: String
    let status: String
    let error: String
    let request: Istek
    let artifact_ids: [String]
    var etkin: Bool { status == "queued" || status == "running" }
    var surdurulebilir: Bool { status == "paused" || status == "failed" }
    var durum: String {
        ["queued": "Sırada", "running": "Çalışıyor", "paused": "Duraklatıldı", "waiting_user": "Seni bekliyor",
         "failed": "Tamamlanamadı", "completed": "Tamamlandı", "completed_with_warnings": "Eksiklerle tamamlandı", "cancelled": "İptal edildi"][status] ?? status
    }
}

nonisolated struct CalismaCiktisi: Decodable, Sendable {
    nonisolated struct Dosya: Decodable, Identifiable, Sendable { let id: String; let name: String; let size: Int }
    let id: String
    let title: String
    let content: String
    let project_id: String?
    let files: [Dosya]?
}

nonisolated struct CalismaOlayi: Decodable, Identifiable, Sendable {
    let seq: Int
    let type: String
    let message: String
    var id: Int { seq }
}

nonisolated enum CalismaHatasi: LocalizedError {
    case baglanti, sunucu(String)
    var errorDescription: String? {
        switch self {
        case .baglanti: "Çalışma sunucusu bağlantısı yok. Tuval belgelerini bu iPhone’da kullanabilirsin."
        case .sunucu(let s): s
        }
    }
}

/// Eski görev API'sini değiştirmeyen V2 istemcisi. Anahtar yalnız HTTPS isteğinin başlığındadır.
@MainActor @Observable
final class CalismaSunucusu {
    static let ortak = CalismaSunucusu()
    var bildirimGorevi: String?
    private(set) var yetenekler: CalismaYetenekleri?
    private(set) var gorevler: [CalismaGorevi] = []
    private(set) var hata: String?
    private(set) var yukleniyor = false
    @ObservationIgnored private var mutasyonNesli = 0
    @ObservationIgnored private let oturum = URLSession(configuration: .ephemeral, delegate: YuklemeYonlendirme(), delegateQueue: nil)

    nonisolated static func adres(_ base: URL, yol: String) -> URL {
        let kok = base.lastPathComponent == "v1" ? base.deletingLastPathComponent() : base
        return kok.appending(path: "v2/asistan").appending(path: yol)
    }

    nonisolated static func hataMesaji(kod: Int, yol: String, mesaj: String?) -> String {
        if kod == 404, yol == "capabilities" {
            return "Çalışma alanı sunucu güncellemesi henüz kurulmamış. Yerel Tuval kullanılabilir."
        }
        return mesaj ?? "Çalışma sunucusu HTTP \(kod) döndürdü."
    }

    private func istek<T: Decodable & Sendable>(_ tur: T.Type, yol: String, yontem: String = "GET", govde: Data? = nil, anahtar: UUID? = nil, dosyaAdi: String? = nil) async throws -> T {
        guard let taban = Gizli.vekilTaban, taban.scheme == "https", let token = Gizli.vekilToken else { throw CalismaHatasi.baglanti }
        var r = URLRequest(url: Self.adres(taban, yol: yol), timeoutInterval: 30)
        r.httpMethod = yontem; r.httpBody = govde
        r.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        r.setValue(dosyaAdi == nil ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let anahtar { r.setValue(anahtar.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let dosyaAdi { r.setValue(dosyaAdi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), forHTTPHeaderField: "X-Filename") }
        let (veri, cevap) = try await oturum.data(for: r)
        try Task.checkCancellation()
        let kod = (cevap as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(kod) else {
            let json = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any]
            throw CalismaHatasi.sunucu(Self.hataMesaji(kod: kod, yol: yol, mesaj: json?["message"] as? String))
        }
        return try JSONDecoder().decode(tur, from: veri)
    }

    func yenile() async {
        guard !yukleniyor else { return }
        yukleniyor = true; defer { yukleniyor = false }
        let nesil = mutasyonNesli
        do {
            async let yetenek = istek(CalismaYetenekleri.self, yol: "capabilities")
            async let liste = istek([CalismaGorevi].self, yol: "jobs")
            let (y, g) = try await (yetenek, liste)
            guard nesil == mutasyonNesli else { return }
            yetenekler = y; gorevler = g; hata = nil
        } catch { if !Task.isCancelled, nesil == mutasyonNesli { hata = error.localizedDescription; yetenekler = nil } }
    }

    func baslat(tur: String, metin: String, dosyalar: [String], anahtar: UUID) async throws -> CalismaGorevi {
        var nesne: [String: Any] = ["kind": tur, "input": ["prompt": metin, "file_ids": dosyalar], "limits": ["allow_paid": false, "max_duration_seconds": 600]]
        if let id = ProjeDeposu.ortak.aktifKimlik { nesne["project_id"] = id.uuidString.lowercased() }
        let g = try await istek(CalismaGorevi.self, yol: "jobs", yontem: "POST", govde: JSONSerialization.data(withJSONObject: nesne), anahtar: anahtar)
        mutasyonNesli += 1; gorevler.removeAll { $0.id == g.id }; gorevler.insert(g, at: 0); return g
    }

    func yukle(_ yol: URL) async throws -> KasaDosyasi {
        nonisolated struct Sonuc: Decodable, Sendable { let id: String }
        let erisim = yol.startAccessingSecurityScopedResource(); defer { if erisim { yol.stopAccessingSecurityScopedResource() } }
        let (yuklenecek, dosyaAdi) = try await Self.kaynakHazirla(yol)
        let id = try await istek(Sonuc.self, yol: "files", yontem: "POST", govde: yuklenecek, dosyaAdi: dosyaAdi).id
        return KasaDosyasi(id: id, name: dosyaAdi, size: Int64(yuklenecek.count), sha256: "")
    }

    @concurrent nonisolated static func kaynakHazirla(_ yol: URL) async throws -> (Data, String) {
        try Task.checkCancellation()
        guard (try yol.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25 * 1024 * 1024 else {
            throw CalismaHatasi.sunucu("Doğrudan işlenecek kaynak en fazla 25 MB olabilir. Daha büyük dosyayı Dosya kasası üzerinden yükleyebilirsin.")
        }
        let veri = try Data(contentsOf: yol)
        var yuklenecek = veri, dosyaAdi = yol.lastPathComponent
        if yol.pathExtension.lowercased() == "pdf" {
            yuklenecek = Data(try Self.pdfMetni(veri, ocr: true).utf8)
            dosyaAdi += ".txt"
        }
        try Task.checkCancellation()
        return (yuklenecek, dosyaAdi)
    }

    /// PDF'i iPhone'da sayfa numaralarını koruyarak metne çevirir. `ocr` açıksa metin katmanı olmayan sayfalar `PdfOcr` ile okunur.
    nonisolated static func pdfMetni(_ veri: Data, ocr: Bool = false) throws -> String {
        guard let pdf = PDFDocument(data: veri), pdf.pageCount > 0 else {
            throw CalismaHatasi.sunucu("PDF açılamadı veya geçerli sayfası yok.")
        }
        guard pdf.pageCount <= 200 else { throw CalismaHatasi.sunucu("PDF en çok 200 sayfa olabilir.") }
        var parcalar: [(Int, String)] = [], bosSayfalar: [Int] = [], toplam = 0
        for i in 0..<pdf.pageCount {
            try Task.checkCancellation()
            let metin = pdf.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if metin.isEmpty { bosSayfalar.append(i); continue }
            toplam += metin.count
            guard toplam <= 120_000 else { throw CalismaHatasi.sunucu("PDF metni 120.000 karakter sınırını aşıyor.") }
            parcalar.append((i, "[Sayfa \(i + 1)]\n\(metin)"))
        }
        var ocrNotu: String?
        var ocrOkunan = 0
        if ocr, !bosSayfalar.isEmpty {
            let sonuc = try PdfOcr.oku(pdf, sayfalar: bosSayfalar)
            for s in sonuc.metinliSayfalar {
                toplam += s.metin.count
                guard toplam <= 120_000 else { throw CalismaHatasi.sunucu("PDF metni 120.000 karakter sınırını aşıyor.") }
                parcalar.append((s.indeks, "[Sayfa \(s.indeks + 1)]\n\(s.metin)"))
            }
            ocrOkunan = sonuc.metinliSayfalar.count
            ocrNotu = PdfOcr.not(sonuc)
        }
        guard !parcalar.isEmpty else {
            throw CalismaHatasi.sunucu(ocr ? "PDF'de seçilebilir metin yok ve OCR da metin bulamadı." : "PDF'de seçilebilir metin bulunamadı. Taranmış sayfalar için OCR gerekir.")
        }
        var sayfalar = parcalar.sorted { $0.0 < $1.0 }.map(\.1)
        if let ocrNotu { sayfalar.append(ocrNotu) }
        let okunamayan = bosSayfalar.count - ocrOkunan
        if okunamayan > 0 {
            sayfalar.append(ocr ? "[Not: \(okunamayan) sayfada metin okunamadı (OCR de sonuç vermedi veya atlandı).]"
                                : "[Not: \(okunamayan) sayfada seçilebilir metin bulunamadı; bu sayfalara OCR uygulanmadı.]")
        }
        return sayfalar.joined(separator: "\n\n")
    }

    func islem(_ g: CalismaGorevi, devam: Bool) async throws {
        guard UUID(uuidString: g.id) != nil else { throw CalismaHatasi.baglanti }
        let yeni = try await istek(CalismaGorevi.self, yol: "jobs/\(g.id)/\(devam ? "resume" : "cancel")", yontem: "POST", govde: Data("{}".utf8))
        mutasyonNesli += 1; gorevler.removeAll { $0.id == yeni.id }; gorevler.insert(yeni, at: 0)
        await yenile()
    }

    func olaylar(_ id: String) async throws -> [CalismaOlayi] {
        guard UUID(uuidString: id) != nil else { throw CalismaHatasi.baglanti }
        return try await istek([CalismaOlayi].self, yol: "jobs/\(id)/events")
    }

    func cikti(_ id: String) async throws -> CalismaCiktisi {
        guard UUID(uuidString: id) != nil else { throw CalismaHatasi.baglanti }
        return try await istek(CalismaCiktisi.self, yol: "artifacts/\(id)")
    }

    func dosyaIndir(_ d: CalismaCiktisi.Dosya) async throws -> URL {
        guard UUID(uuidString: d.id) != nil, let taban = Gizli.vekilTaban, taban.scheme == "https", let token = Gizli.vekilToken,
              (1...50 * 1024 * 1024).contains(d.size) else { throw CalismaHatasi.baglanti }
        var r = URLRequest(url: Self.adres(taban, yol: "files/\(d.id)"), timeoutInterval: 30)
        r.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        let (gecici, cevap) = try await oturum.download(for: r)
        defer { try? FileManager.default.removeItem(at: gecici) }
        guard (cevap as? HTTPURLResponse)?.statusCode == 200,
              (try gecici.resourceValues(forKeys: [.fileSizeKey]).fileSize) == d.size else { throw CalismaHatasi.sunucu("Çıktı dosyası indirilemedi.") }
        let uzanti = (d.name as NSString).pathExtension.lowercased()
        guard ["png", "csv", "xlsx", "json", "txt", "md", "wav", "mp3"].contains(uzanti) else { throw CalismaHatasi.sunucu("Bu dosya türü desteklenmiyor.") }
        let hedef = FileManager.default.temporaryDirectory.appending(path: "\(d.id).\(uzanti)")
        try await Self.dosyaTasi(gecici, hedef: hedef)
        return hedef
    }

    @concurrent nonisolated static func dosyaTasi(_ gecici: URL, hedef: URL) async throws {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: hedef.path) {
            _ = try FileManager.default.replaceItemAt(hedef, withItemAt: gecici)
        } else { try FileManager.default.moveItem(at: gecici, to: hedef) }
    }
}
