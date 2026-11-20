import Foundation
import CoreGraphics
import Observation
import UIKit

/// Çevrimdışıyken yazılmış, bağlantı gelince gidecek mesaj (kalıcı kayıt).
nonisolated struct BekleyenGonderi: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var metin: String
    /// Kuyruk klasöründeki JPEG adları ("<id>-<n>.jpg"), sırası korunur.
    var gorselAdlari: [String]
    var belge: String?
    var canliSes: Bool
    /// İstek dış bir kaynaktan geldi (asistan:// bağlantısı vb.); gönderimde onay kapısına taşınır.
    var disKaynak: Bool
    let zaman: Date
    /// Askıdaki öğe kendiliğinden gönderilmez (yeni sohbet açıldı ya da 24 saatten eski); şeritten "Gönder" ile gider.
    var askida: Bool
}

/// Çevrimdışı gönderim kuyruğu: Application Support/Kuyruk/kuyruk.json + görseller.
/// Uygulama kapanıp açılsa da kaybolmaz; öğe yalnız gönderim kabul edilince (ya da kullanıcı silince) silinir.
@MainActor @Observable
final class CevrimdisiKuyruk {
    static let ortak = CevrimdisiKuyruk(klasor: CevrimdisiKuyruk.varsayilanKlasor())

    /// Birim/arayüz testi ya da sınama açılışı: kullanıcının gerçek kuyruğuna dokunulmaz, kendiliğinden gönderim yapılmaz.
    nonisolated static let yalitilmis: Bool = {
        let e = ProcessInfo.processInfo.environment
        if e["XCTestConfigurationFilePath"] != nil || e["ASISTAN_TEST"] == "1" { return true }
        return ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--asistan-") }
    }()
    /// Bu süreden eski öğeler açılışta askıya alınır (bayat istek kendiliğinden gitmesin).
    nonisolated static let eskimeSuresi: TimeInterval = 86_400

    nonisolated static func varsayilanKlasor() -> URL {
        if yalitilmis { return geciciKlasor() }
        let destek = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return destek.appending(path: "Kuyruk", directoryHint: .isDirectory)
    }

    nonisolated static func geciciKlasor() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "kuyruk-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    let klasor: URL
    private(set) var ogeler: [BekleyenGonderi] = []
    var dosya: URL { klasor.appending(path: "kuyruk.json") }

    init(klasor: URL, simdi: Date = .now) {
        self.klasor = klasor
        yukle(simdi: simdi)
    }

    /// Kendiliğinden gönderilecek ilk öğe (askıdakiler atlanır).
    var siradaki: BekleyenGonderi? { ogeler.first { !$0.askida } }
    var askidakiSayisi: Int { ogeler.filter(\.askida).count }

    // MARK: Değişiklikler

    @discardableResult
    func ekle(metin: String, gorseller: [CGImage], belge: String?, canliSes: Bool, disKaynak: Bool, zaman: Date = .now) -> BekleyenGonderi {
        let id = UUID()
        klasoruHazirla()
        var adlar: [String] = []
        for (i, g) in gorseller.enumerated() {
            let ui = UIImage(cgImage: g)
            let kucuk = ui.kucultulmus(2048).map { UIImage(cgImage: $0) } ?? ui
            guard let veri = kucuk.jpegData(compressionQuality: 0.8) else { continue }
            let ad = "\(id.uuidString)-\(i).jpg"
            do {
                try veri.write(to: klasor.appending(path: ad), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                adlar.append(ad)
            } catch {
                TaniGunlugu.yaz("KUYRUK görsel yazılamadı: \(error.localizedDescription)")
            }
        }
        let o = BekleyenGonderi(id: id, metin: metin, gorselAdlari: adlar, belge: belge, canliSes: canliSes, disKaynak: disKaynak, zaman: zaman, askida: false)
        ogeler.append(o)
        kaydet()
        return o
    }

    /// Öğeyi ve görsellerini siler.
    func sil(_ id: UUID) {
        guard let i = ogeler.firstIndex(where: { $0.id == id }) else { return }
        let o = ogeler.remove(at: i)
        gorselleriSil(o)
        kaydet()
    }

    func hepsiniSil() {
        let eski = ogeler
        ogeler = []
        for o in eski { gorselleriSil(o) }
        kaydet()
    }

    /// Bütün öğeleri askıya alır (yeni sohbet: önceki sohbetin mesajları kendiliğinden yeni sohbete gitmez).
    func askiyaAl() {
        guard ogeler.contains(where: { !$0.askida }) else { return }
        for i in ogeler.indices { ogeler[i].askida = true }
        kaydet()
    }

    /// Tek öğeyi askıya alır (gönderilemeyen öğe kendiliğinden yeniden denenmesin).
    func askiyaAl(_ id: UUID) {
        guard let i = ogeler.firstIndex(where: { $0.id == id }), !ogeler[i].askida else { return }
        ogeler[i].askida = true
        kaydet()
    }

    func askidanCikar(_ id: UUID) {
        guard let i = ogeler.firstIndex(where: { $0.id == id }), ogeler[i].askida else { return }
        ogeler[i].askida = false
        kaydet()
    }

    /// Öğenin görselleri (okunamayan dosya atlanır).
    func gorseller(_ o: BekleyenGonderi) -> [CGImage] {
        o.gorselAdlari.compactMap { UIImage(contentsOfFile: klasor.appending(path: $0).path)?.cgImage }
    }

    // MARK: Disk

    private func klasoruHazirla() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: klasor.path) else { return }
        try? fm.createDirectory(at: klasor, withIntermediateDirectories: true)
        var url = klasor
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        try? url.setResourceValues(d)
    }

    private func gorselleriSil(_ o: BekleyenGonderi) {
        for ad in o.gorselAdlari { try? FileManager.default.removeItem(at: klasor.appending(path: ad)) }
    }

    nonisolated static func kodlayici() -> JSONEncoder {
        // Tarih varsayılan (Double) biçimde: ISO 8601 saniye altını atar, yeniden açılan öğe birebir eşit kalmaz.
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return e
    }

    nonisolated static func cozucu() -> JSONDecoder { JSONDecoder() }

    private func kaydet() {
        klasoruHazirla()
        do {
            let veri = try Self.kodlayici().encode(ogeler)
            try veri.write(to: dosya, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            TaniGunlugu.yaz("KUYRUK kaydedilemedi: \(error.localizedDescription)")
        }
    }

    /// Açılış: çözülemeyen dosya sessizce silinmez, "kuyruk.bozuk-<tarih>.json" adıyla saklanır; eski öğeler askıya alınır.
    private func yukle(simdi: Date) {
        guard let veri = try? Data(contentsOf: dosya) else { ogeler = []; return }
        do {
            var liste = try Self.cozucu().decode([BekleyenGonderi].self, from: veri)
            var degisti = false
            for i in liste.indices where !liste[i].askida && simdi.timeIntervalSince(liste[i].zaman) > Self.eskimeSuresi {
                liste[i].askida = true; degisti = true
            }
            ogeler = liste
            if degisti { kaydet() }
        } catch {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
            let yedek = klasor.appending(path: "kuyruk.bozuk-\(f.string(from: simdi)).json")
            try? FileManager.default.removeItem(at: yedek)
            do { try FileManager.default.moveItem(at: dosya, to: yedek) } catch { TaniGunlugu.yaz("KUYRUK bozuk dosya taşınamadı: \(error.localizedDescription)") }
            TaniGunlugu.yaz("KUYRUK çözülemedi, yedeklendi: \(yedek.lastPathComponent)")
            ogeler = []
        }
    }
}
