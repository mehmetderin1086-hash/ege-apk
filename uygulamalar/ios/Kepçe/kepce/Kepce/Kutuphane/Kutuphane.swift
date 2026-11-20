import Foundation
import Observation
import Photos

nonisolated struct KutuphaneOgesi: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var baslik: String
    var yazar: String?
    var kaynak: String
    /// Belgeler dizinine göre yol (Dosyalar uygulamasında "Kepçe" altında görünür).
    var dosya: String
    var tur: IndirmeTuru
    var sure: Double?
    var boyut: Int64
    var kapak: String?
    /// Dil kodu → Belgeler'e göre .srt yolu.
    var altyazilar: [String: String] = [:]
    var etiket: String
    var tarih = Date()
    var konum: Double?
    var bolumler: [Bolum]?
    /// Oynatma listesinden indirildiyse listenin adı.
    var liste: String?

    var sesMi: Bool { tur == .ses || ["m4a", "mp3", "aac", "opus", "ogg", "wav", "flac"].contains((dosya as NSString).pathExtension.lowercased()) }
}

@Observable final class Kutuphane {
    static let shared = Kutuphane()

    private(set) var ogeler: [KutuphaneOgesi] = []
    private let dizin = PythonMotoru.destek.appending(path: "kutuphane.json")

    static var belgeler: URL { URL.documentsDirectory }
    static var kapaklar: URL {
        let url = PythonMotoru.destek.appending(path: "Kapaklar")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func klasor(_ tur: IndirmeTuru) -> URL {
        let ad = switch tur { case .video: "Videolar"; case .ses: "Sesler"; case .ham: "Özgün dosyalar" }
        let url = belgeler.appending(path: ad)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init(dosyasiz: Bool = false) {
        guard !dosyasiz else { return }
        if let veri = try? Data(contentsOf: dizin), let liste = try? JSONDecoder().decode([KutuphaneOgesi].self, from: veri) {
            // Dosyalar uygulamasından silinenleri düşür.
            ogeler = liste.filter { FileManager.default.fileExists(atPath: Self.belgeler.appending(path: $0.dosya).path) }
            if ogeler.count != liste.count { kaydet() }
        }
    }

    func url(_ oge: KutuphaneOgesi) -> URL { Self.belgeler.appending(path: oge.dosya) }
    func kapakURL(_ oge: KutuphaneOgesi) -> URL? { oge.kapak.map { Self.kapaklar.appending(path: $0) } }
    func altyaziURL(_ oge: KutuphaneOgesi, dil: String) -> URL? { oge.altyazilar[dil].map { Self.belgeler.appending(path: $0) } }

    func ekle(_ oge: KutuphaneOgesi) {
        ogeler.insert(oge, at: 0)
        kaydet()
    }

    func sil(_ oge: KutuphaneOgesi) {
        try? FileManager.default.removeItem(at: url(oge))
        if let kapak = kapakURL(oge) { try? FileManager.default.removeItem(at: kapak) }
        for yol in oge.altyazilar.values { try? FileManager.default.removeItem(at: Self.belgeler.appending(path: yol)) }
        ogeler.removeAll { $0.id == oge.id }
        kaydet()
    }

    func yenidenAdlandir(_ oge: KutuphaneOgesi, _ yeniAd: String) {
        guard let i = ogeler.firstIndex(where: { $0.id == oge.id }) else { return }
        let eski = url(oge)
        let yeni = Self.benzersiz(yeniAd, uzanti: eski.pathExtension, klasor: eski.deletingLastPathComponent(), haric: eski)
        do {
            if yeni != eski { try FileManager.default.moveItem(at: eski, to: yeni) }
            ogeler[i].baslik = yeniAd
            ogeler[i].dosya = Self.goreli(yeni)
            kaydet()
        } catch {}
    }

    func konumKaydet(_ id: UUID, _ saniye: Double) {
        guard let i = ogeler.firstIndex(where: { $0.id == id }) else { return }
        ogeler[i].konum = saniye
        kaydet()
    }

    var toplamBoyut: Int64 { ogeler.reduce(0) { $0 + $1.boyut } }

    private func kaydet() {
        guard let veri = try? JSONEncoder().encode(ogeler) else { return }
        try? veri.write(to: dizin, options: .atomic)
    }

    // MARK: Dosya adları

    static func goreli(_ url: URL) -> String {
        let taban = belgeler.standardizedFileURL.path
        let yol = url.standardizedFileURL.path
        return yol.hasPrefix(taban) ? String(yol.dropFirst(taban.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : url.lastPathComponent
    }

    nonisolated static func temizAd(_ baslik: String) -> String {
        let yasak = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let parcalar = baslik.components(separatedBy: yasak).joined(separator: " ")
        var ad = parcalar.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while ad.hasPrefix(".") { ad.removeFirst() }
        ad = String(ad.prefix(120)).trimmingCharacters(in: .whitespaces)
        return ad.isEmpty ? "Kepçe" : ad
    }

    nonisolated static func benzersiz(_ baslik: String, uzanti: String, klasor: URL, haric: URL? = nil) -> URL {
        let ad = temizAd(baslik)
        var aday = klasor.appending(path: "\(ad).\(uzanti)")
        var sayi = 2
        while FileManager.default.fileExists(atPath: aday.path), aday.standardizedFileURL != haric?.standardizedFileURL {
            aday = klasor.appending(path: "\(ad) (\(sayi)).\(uzanti)")
            sayi += 1
        }
        return aday
    }

    /// Dosyayı benzersiz bir adla taşır; aynı anda aynı adı alan başka bir iş varsa sıradaki adı dener.
    nonisolated static func tasi(_ kaynak: URL, baslik: String, uzanti: String, klasor: URL) throws -> URL {
        for _ in 0..<100 {
            let hedef = benzersiz(baslik, uzanti: uzanti, klasor: klasor)
            do {
                try FileManager.default.moveItem(at: kaynak, to: hedef)
                return hedef
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    // MARK: Fotoğraflar

    nonisolated static func fotograflaraKaydet(_ url: URL) async throws {
        let izin = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard izin == .authorized || izin == .limited else {
            throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "Fotoğraflar'a ekleme izni verilmedi (Ayarlar → Kepçe → Fotoğraflar)."])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
