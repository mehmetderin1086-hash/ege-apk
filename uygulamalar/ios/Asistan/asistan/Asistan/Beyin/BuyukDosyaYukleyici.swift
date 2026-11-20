import Foundation
import CryptoKit
import Observation
import UIKit

nonisolated struct KasaDosyasi: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let size: Int64
    let sha256: String

    func kaynakOlabilir(tur: String, arastirmaSiniri: Int64 = 200_000) -> Bool {
        guard size > 0 else { return false }
        let uzanti = (name as NSString).pathExtension.lowercased()
        if tur == "analysis" { return ["csv", "json", "xlsx"].contains(uzanti) && size <= 25 * 1024 * 1024 }
        let sinir = tur == "research" ? min(max(arastirmaSiniri, 0), 64 * 1024 * 1024) : 200_000
        return ["txt", "md", "csv", "json"].contains(uzanti) && size <= sinir
    }

    static func kaynakUyarisi(_ dosyalar: [Self], tur: String, arastirmaSiniri: Int64) -> String? {
        if dosyalar.count > 8 { return "Bir çalışmaya en fazla 8 kaynak eklenebilir." }
        if let d = dosyalar.first(where: { !$0.kaynakOlabilir(tur: tur, arastirmaSiniri: arastirmaSiniri) }) {
            return "\(d.name) seçili çalışma türü veya boyut sınırı için uygun değil. Kaynağı kaldır veya çalışma türünü değiştir."
        }
        if tur == "research", dosyalar.reduce(Int64(0), { $0 + $1.size }) > 128 * 1024 * 1024 {
            return "Araştırma kaynakları toplamda 128 MB’ı aşamaz. Kaynak sayısını azalt."
        }
        return nil
    }
}

nonisolated struct YuklemeKaydi: Codable, Identifiable, Sendable {
    let id: String
    let ad: String
    let boyut: Int64
    let sha256: String
    let sunucu: String
    var ofset: Int64
}

nonisolated struct YuklemeDurumu: Decodable, Sendable {
    let id: String
    let name: String
    let size: Int64
    let sha256: String
    let offset: Int64
    let status: String
    let chunk_bytes: Int
}

nonisolated enum YuklemeHatasi: LocalizedError {
    case http(Int, String)
    var errorDescription: String? { if case .http(_, let s) = self { s } else { "Yükleme tamamlanamadı." } }
    var yenidenDenenebilir: Bool { if case .http(let k, _) = self { k == 409 || k == 429 || (500...504).contains(k) } else { false } }
}

/// Kişisel token yönlendirmeyle başka bir sunucuya taşınmaz.
nonisolated final class YuklemeYonlendirme: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Yalnız tek parça bellektedir. Kalıcı kayıtta anahtar ve dosya içeriği tutulmaz;
/// uygulama yeniden açılınca aynı dosya seçilip SHA-256 doğrulanarak sürdürülür.
@MainActor @Observable
final class BuyukDosyaYukleyici {
    static let ortak = BuyukDosyaYukleyici()
    nonisolated static let enFazla: Int64 = 10 * 1024 * 1024 * 1024
    nonisolated static let parcaBoyutu = 8 * 1024 * 1024
    private(set) var bekleyenler: [YuklemeKaydi] = []
    private(set) var dosyalar: [KasaDosyasi] = []
    private(set) var etkin = false
    private(set) var etkinID: String?
    private(set) var asama = ""
    private(set) var aktarilan: Int64 = 0
    private(set) var toplam: Int64 = 0
    private(set) var saniyede: Double = 0
    private(set) var hata: String?
    @ObservationIgnored private var gorev: Task<Void, Never>?
    @ObservationIgnored private let ayarlar: UserDefaults
    @ObservationIgnored private let oturum: URLSession
    @ObservationIgnored private var gozlemci: NSObjectProtocol?
    @ObservationIgnored private var kayitOkunamadi = false
    private static let kayitAnahtari = "asistan.buyukYuklemeler.v1"

    init(ayarlar: UserDefaults = .standard) {
        self.ayarlar = ayarlar
        oturum = URLSession(configuration: .ephemeral, delegate: YuklemeYonlendirme(), delegateQueue: nil)
        if let veri = ayarlar.data(forKey: Self.kayitAnahtari) {
            do { bekleyenler = try JSONDecoder().decode([YuklemeKaydi].self, from: veri) }
            catch { kayitOkunamadi = true; hata = "Yarım yükleme kayıtları okunamadı. Mevcut kayıtlar korunuyor." }
        }
        gozlemci = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.duraklat() }
        }
    }

    private func baglanti() throws -> (URL, String, String) {
        guard let taban = Gizli.vekilTaban, taban.scheme == "https", let token = Gizli.vekilToken else { throw CalismaHatasi.baglanti }
        let kok = CalismaSunucusu.adres(taban, yol: "")
        let kimlik = Self.ozet(Data((kok.absoluteString + "\n" + token).utf8))
        return (kok, token, kimlik)
    }

    private func kaydet() throws {
        guard !kayitOkunamadi else { throw CalismaHatasi.sunucu("Yarım yükleme kayıtları okunamadı. Mevcut kayıtlar korunuyor.") }
        ayarlar.set(try JSONEncoder().encode(bekleyenler), forKey: Self.kayitAnahtari)
    }

    private func istek<T: Decodable & Sendable>(_ tip: T.Type, kok: URL, token: String, yol: String,
        yontem: String = "GET", veri: Data? = nil, basliklar: [String: String] = [:], sure: Double = 120) async throws -> T {
        var r = URLRequest(url: kok.appending(path: yol), timeoutInterval: sure)
        r.httpMethod = yontem; r.httpBody = veri
        r.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (ad, deger) in basliklar { r.setValue(deger, forHTTPHeaderField: ad) }
        let (sonuc, yanit) = try await oturum.data(for: r)
        try Task.checkCancellation()
        let kod = (yanit as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(kod) else {
            let json = (try? JSONSerialization.jsonObject(with: sonuc)) as? [String: Any]
            throw YuklemeHatasi.http(kod, json?["message"] as? String ?? "Dosya sunucusu HTTP \(kod) döndürdü.")
        }
        return try JSONDecoder().decode(tip, from: sonuc)
    }

    func yenile() async {
        guard !etkin else { return }
        do {
            let (kok, token, sunucu) = try baglanti()
            async let gelen = istek([KasaDosyasi].self, kok: kok, token: token, yol: "files")
            async let yarim = istek([YuklemeDurumu].self, kok: kok, token: token, yol: "uploads")
            let (dosyalar, oturumlar) = try await (gelen, yarim)
            guard !etkin, try baglanti().2 == sunucu else { return }
            self.dosyalar = dosyalar
            for o in oturumlar {
                bekleyenler.removeAll { $0.id == o.id }
                bekleyenler.append(YuklemeKaydi(id: o.id, ad: o.name, boyut: o.size, sha256: o.sha256, sunucu: sunucu, ofset: o.offset))
            }
            // Başka cihazda tamamlanan veya iptal edilen yüklemeler yerel sırayı kilitlemez.
            let bilinen = Set(oturumlar.map(\.id))
            bekleyenler.removeAll { $0.sunucu == sunucu && !bilinen.contains($0.id) }
            try kaydet()
        } catch { if !Task.isCancelled { hata = error.localizedDescription } }
    }

    func baslat(_ yol: URL) {
        guard !etkin else { return }
        guard !kayitOkunamadi else { hata = "Yarım yükleme kayıtları okunamadı. Mevcut kayıtlar korunuyor."; return }
        etkin = true; etkinID = nil; hata = nil; aktarilan = 0; toplam = 0; saniyede = 0
        asama = "Dosya doğrulanıyor…"
        gorev = Task {
            do { try await yukle(yol); asama = "Yüklendi ve doğrulandı." }
            catch {
                if Task.isCancelled { asama = "Duraklatıldı. Aynı dosyayı seçerek devam edebilirsin." }
                else { hata = error.localizedDescription; asama = "Yükleme durdu; kaydedilmiş parçalar korundu." }
            }
            etkin = false; etkinID = nil; gorev = nil
            if !Task.isCancelled { await yenile() }
        }
    }

    func duraklat() { gorev?.cancel() }

    private func yukle(_ yol: URL) async throws {
        let erisim = yol.startAccessingSecurityScopedResource()
        defer { if erisim { yol.stopAccessingSecurityScopedResource() } }
        let (kok, token, sunucu) = try baglanti()
        let yetenekler = try await istek(CalismaYetenekleri.self, kok: kok, token: token, yol: "capabilities")
        guard yetenekler.modules["resumable_uploads"] == true else { throw CalismaHatasi.sunucu("Büyük dosya yükleme sunucuya henüz kurulmamış.") }
        let sinir = min(Self.enFazla, yetenekler.limits?.file_bytes ?? Self.enFazla)
        let bilgi = try await Self.dosyaOzeti(yol, sinir: sinir)
        try Task.checkCancellation()
        toplam = bilgi.boyut
        let yarim = try await istek([YuklemeDurumu].self, kok: kok, token: token, yol: "uploads")
        for o in yarim where !bekleyenler.contains(where: { $0.id == o.id && $0.sunucu == sunucu }) {
            bekleyenler.removeAll { $0.id == o.id }
            bekleyenler.append(YuklemeKaydi(id: o.id, ad: o.name, boyut: o.size, sha256: o.sha256, sunucu: sunucu, ofset: o.offset))
        }
        var kayit: YuklemeKaydi
        if let eski = bekleyenler.first(where: { $0.sunucu == sunucu && $0.sha256 == bilgi.ozet && $0.boyut == bilgi.boyut && $0.ad == yol.lastPathComponent }) { kayit = eski }
        else {
            kayit = YuklemeKaydi(id: UUID().uuidString.lowercased(), ad: yol.lastPathComponent, boyut: bilgi.boyut, sha256: bilgi.ozet, sunucu: sunucu, ofset: 0)
            bekleyenler.append(kayit); try kaydet()
        }
        etkinID = kayit.id
        let girdi = try JSONSerialization.data(withJSONObject: ["name": kayit.ad, "size": kayit.boyut, "sha256": kayit.sha256])
        var durum = try await istek(YuklemeDurumu.self, kok: kok, token: token, yol: "uploads", yontem: "POST", veri: girdi, basliklar: ["Idempotency-Key": kayit.id])
        try Self.durumDogrula(durum, kayit: kayit)
        aktarilan = durum.offset
        let baslangic = ContinuousClock.now, ilkOfset = durum.offset
        var deneme = 0
        while durum.offset < kayit.boyut {
            try Task.checkCancellation()
            asama = "\(kayit.ad) yükleniyor…"
            let parca = try await Self.parcaOku(yol, ofset: durum.offset, boyut: min(durum.chunk_bytes, Self.parcaBoyutu), beklenenBoyut: kayit.boyut)
            do {
                durum = try await istek(YuklemeDurumu.self, kok: kok, token: token, yol: "uploads/\(kayit.id)", yontem: "PUT", veri: parca,
                    basliklar: ["Content-Type": "application/octet-stream", "Upload-Offset": String(durum.offset), "X-Chunk-SHA256": Self.ozet(parca)])
                deneme = 0
            } catch {
                try Task.checkCancellation()
                let agHatasi = error as? URLError
                guard deneme < 3, (agHatasi != nil || (error as? YuklemeHatasi)?.yenidenDenenebilir == true) else { throw error }
                deneme += 1; asama = "Bağlantı yeniden deneniyor (\(deneme)/3)…"
                try await Task.sleep(for: .seconds(1 << deneme))
                durum = try await istek(YuklemeDurumu.self, kok: kok, token: token, yol: "uploads/\(kayit.id)")
            }
            try Self.durumDogrula(durum, kayit: kayit)
            aktarilan = durum.offset
            let sure = baslangic.duration(to: .now).components
            saniyede = Double(aktarilan - ilkOfset) / max(0.1, Double(sure.seconds) + Double(sure.attoseconds) / 1e18)
            if let i = bekleyenler.firstIndex(where: { $0.id == kayit.id }) { bekleyenler[i].ofset = durum.offset; try kaydet() }
        }
        asama = "Sunucu dosyanın bütünlüğünü doğruluyor…"
        let sonuc = try await istek(KasaDosyasi.self, kok: kok, token: token, yol: "uploads/\(kayit.id)/complete", yontem: "POST", veri: Data("{}".utf8), sure: 1800)
        guard sonuc.size == kayit.boyut, sonuc.sha256 == kayit.sha256 else { throw CalismaHatasi.sunucu("Dosya bütünlüğü doğrulanamadı.") }
        bekleyenler.removeAll { $0.id == kayit.id }; try kaydet()
    }

    func iptal(_ kayit: YuklemeKaydi) async {
        guard !etkin else { return }
        do {
            let (kok, token, sunucu) = try baglanti()
            guard kayit.sunucu == sunucu else { throw CalismaHatasi.sunucu("Bu yükleme başka bir sunucu bağlantısına ait.") }
            nonisolated struct Sonuc: Decodable, Sendable { let cancelled: Bool }
            do { _ = try await istek(Sonuc.self, kok: kok, token: token, yol: "uploads/\(kayit.id)", yontem: "DELETE") }
            catch YuklemeHatasi.http(404, _) { /* Başlatma isteği sunucuya ulaşmamış olabilir. */ }
            bekleyenler.removeAll { $0.id == kayit.id }; try kaydet(); hata = nil
        } catch { hata = error.localizedDescription }
    }

    func sil(_ dosya: KasaDosyasi) async {
        do {
            let (kok, token, _) = try baglanti()
            nonisolated struct Sonuc: Decodable, Sendable { let deleted: Bool }
            _ = try await istek(Sonuc.self, kok: kok, token: token, yol: "files/\(dosya.id)", yontem: "DELETE")
            dosyalar.removeAll { $0.id == dosya.id }; hata = nil
        } catch { hata = error.localizedDescription }
    }

    func indir(_ dosya: KasaDosyasi) async throws -> URL {
        let (kok, token, _) = try baglanti()
        let bos = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let bos, bos < dosya.size + 512 * 1024 * 1024 { throw CalismaHatasi.sunucu("Bu dosyayı indirmek için iPhone’da yeterli boş alan yok.") }
        var r = URLRequest(url: kok.appending(path: "files/\(dosya.id)"), timeoutInterval: 1800)
        r.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        let (gecici, cevap) = try await oturum.download(for: r)
        defer { try? FileManager.default.removeItem(at: gecici) }
        guard (cevap as? HTTPURLResponse)?.statusCode == 200 else { throw CalismaHatasi.sunucu("Dosya indirilemedi.") }
        let bilgi = try await Self.dosyaOzeti(gecici, sinir: Self.enFazla)
        guard bilgi.boyut == dosya.size, bilgi.ozet == dosya.sha256 else { throw CalismaHatasi.sunucu("İndirilen dosya doğrulanamadı.") }
        guard dosya.name == URL(fileURLWithPath: dosya.name).lastPathComponent else { throw CalismaHatasi.sunucu("Geçersiz dosya adı.") }
        let klasor = FileManager.default.temporaryDirectory.appending(path: "kasa-\(dosya.id)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let hedef = klasor.appending(path: dosya.name)
        if FileManager.default.fileExists(atPath: hedef.path) { try FileManager.default.removeItem(at: hedef) }
        try FileManager.default.moveItem(at: gecici, to: hedef)
        return hedef
    }

    nonisolated static func ozet(_ veri: Data) -> String { SHA256.hash(data: veri).map { String(format: "%02x", $0) }.joined() }

    nonisolated static func durumDogrula(_ durum: YuklemeDurumu, kayit: YuklemeKaydi) throws {
        guard durum.id == kayit.id, durum.sha256 == kayit.sha256, durum.size == kayit.boyut,
              durum.name == kayit.ad, (0...kayit.boyut).contains(durum.offset),
              (1...parcaBoyutu).contains(durum.chunk_bytes), ["uploading", "completed"].contains(durum.status) else {
            throw CalismaHatasi.sunucu("Sunucunun yükleme kaydı dosyayla uyuşmuyor.")
        }
    }

    @concurrent nonisolated static func dosyaOzeti(_ yol: URL, sinir: Int64 = enFazla) async throws -> (boyut: Int64, ozet: String) {
        let deger = try yol.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard deger.isRegularFile == true, let boyut = deger.fileSize, boyut > 0, Int64(boyut) <= sinir else {
            throw CalismaHatasi.sunucu("Boş dosya veya klasör yüklenemez. Dosya sınırı: \(ByteCountFormatter.string(fromByteCount: sinir, countStyle: .binary)).")
        }
        let f = try FileHandle(forReadingFrom: yol); defer { try? f.close() }
        var h = SHA256(), okunan: Int64 = 0
        while let veri = try f.read(upToCount: parcaBoyutu), !veri.isEmpty {
            try Task.checkCancellation(); h.update(data: veri); okunan += Int64(veri.count)
            guard okunan <= sinir else { throw CalismaHatasi.sunucu("Dosya okunurken boyutu değişti.") }
        }
        guard okunan == Int64(boyut) else { throw CalismaHatasi.sunucu("Dosya okunurken değişti. Yeniden seçin.") }
        return (okunan, h.finalize().map { String(format: "%02x", $0) }.joined())
    }

    @concurrent nonisolated static func parcaOku(_ yol: URL, ofset: Int64, boyut: Int, beklenenBoyut: Int64) async throws -> Data {
        try Task.checkCancellation()
        guard ofset >= 0, ofset < beklenenBoyut, (1...parcaBoyutu).contains(boyut),
              Int64(try yol.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == beklenenBoyut else { throw CalismaHatasi.sunucu("Dosya boyutu değişti veya konumu geçersiz.") }
        let f = try FileHandle(forReadingFrom: yol); defer { try? f.close() }
        try f.seek(toOffset: UInt64(ofset))
        let beklenen = Int(min(Int64(boyut), beklenenBoyut - ofset))
        guard let parca = try f.read(upToCount: beklenen), parca.count == beklenen else { throw CalismaHatasi.sunucu("Dosya parçası okunamadı.") }
        return parca
    }
}
