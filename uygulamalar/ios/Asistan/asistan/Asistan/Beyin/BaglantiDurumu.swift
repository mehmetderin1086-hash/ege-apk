import Foundation
import Observation
import UIKit

/// P3.7: üç bağlantı halkası gerçekten yoklanır: telefondaki CLIProxy (loopback), VPS vekili ve internet.
/// Öne gelişte ve ağ yolu değişince (2 sn sıçrama önleme) yoklanır; bir halka yoksa uygulama öndeyken 30 sn'de bir
/// yeniden denenir. VPS erişilemezken zincir .vekil adımını atlar (yalnız tek seçenekse kalır).
/// VPS'te ayrı sağlık ucu yok: var olan `<vekilTaban>/v1/models`'e kısa GET (401 dahil her HTTP yanıtı 'erişilebilir').
/// İnternet: Apple'ın captive.apple.com sayfası (okul ağının oturum açma sayfasını da yakalar). Hiçbir anahtar loglanmaz.
@MainActor @Observable
final class BaglantiDurumu {
    nonisolated enum Halka: String, CaseIterable, Sendable {
        case yerelVekil, vps, internet
        var ad: String {
            switch self {
            case .yerelVekil: "Telefondaki CLIProxy"
            case .vps: "Sunucu (VPS)"
            case .internet: "İnternet"
            }
        }
        var simge: String {
            switch self {
            case .yerelVekil: "iphone"
            case .vps: "server.rack"
            case .internet: "globe"
            }
        }
    }

    nonisolated enum Hal: Equatable, Sendable {
        case bilinmiyor, iyi, yok(String), yapilandirilmamis
        var metin: String {
            switch self {
            case .bilinmiyor: "Henüz yoklanmadı"
            case .iyi: "Erişilebilir"
            case .yok(let n): "Erişilemiyor: \(n)"
            case .yapilandirilmamis: "Yapılandırılmamış"
            }
        }
        var yokMu: Bool { if case .yok = self { true } else { false } }
    }

    static let ortak = BaglantiDurumu()

    private(set) var haller: [Halka: Hal] = [:]
    private(set) var sonYoklama: Date?
    private(set) var yoklaniyor = false

    @ObservationIgnored private var baslatildi = false
    @ObservationIgnored private var onde = true
    @ObservationIgnored private var gozlemciler: [any NSObjectProtocol] = []
    @ObservationIgnored private var sicrama: Task<Void, Never>?
    @ObservationIgnored private var nabiz: Task<Void, Never>?

    /// VPS halkası açıkça 'yok' değilse (bilinmiyor/yapılandırılmamış dahil) vekil adımı denenebilir.
    var vpsKullanilabilir: Bool { !(haller[.vps]?.yokMu ?? false) }

    /// Tek seferlik; testte/sınamada (`CevrimdisiKuyruk.yalitilmis`: XCTest, ASISTAN_TEST=1, --asistan-*) hiçbir şey yapmaz.
    func baslat() {
        guard !baslatildi, !CevrimdisiKuyruk.yalitilmis else { return }
        baslatildi = true
        let nc = NotificationCenter.default
        // Gözlemci kapanışları @Sendable; iş ana aktörde yürür.
        gozlemciler.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { @Sendable _ in
            Task { @MainActor in BaglantiDurumu.ortak.onPlan(true) }
        })
        gozlemciler.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { @Sendable _ in
            Task { @MainActor in BaglantiDurumu.ortak.onPlan(false) }
        })
        gozlemciler.append(nc.addObserver(forName: .agYoluDegisti, object: nil, queue: .main) { @Sendable _ in
            Task { @MainActor in BaglantiDurumu.ortak.zamanla(gecikme: 2) }
        })
        // İlk yoklama: TelefonProxy açılışta hazırlanırken biraz bekle.
        zamanla(gecikme: 3)
        nabziAyarla()
    }

    private func onPlan(_ on: Bool) {
        onde = on
        if on { zamanla(gecikme: 1) }
        nabziAyarla()
    }

    /// Ağ hatası görüldü (zincir): en çok 5 sn'de bir yeniden yokla. Başlatılmadıysa (test) hiçbir şey yapmaz.
    func agHatasiGoruldu() {
        guard baslatildi else { return }
        if let s = sonYoklama, Date().timeIntervalSince(s) < 5 { return }
        zamanla(gecikme: 0)
    }

    private func zamanla(gecikme: Double) {
        sicrama?.cancel()
        sicrama = Task { [weak self] in
            if gecikme > 0 { try? await Task.sleep(for: .seconds(gecikme)) }
            guard !Task.isCancelled else { return }
            await self?.yokla()
        }
    }

    private func nabziAyarla() {
        nabiz?.cancel(); nabiz = nil
        guard onde, baslatildi else { return }
        nabiz = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                if self.onde, self.haller.values.contains(where: \.yokMu) { await self.yokla() }
            }
        }
    }

    /// Üç halka paralel yoklanır (her biri en çok ~3 sn).
    func yokla() async {
        guard !yoklaniyor else { return }
        yoklaniyor = true
        defer { yoklaniyor = false }
        let taban = Gizli.vekilTaban, token = Gizli.vekilToken
        async let yerel = yerelYokla()
        async let vps = Self.vpsYokla(taban: taban, token: token)
        async let internet = Self.internetYokla()
        let yeni: [Halka: Hal] = [.yerelVekil: await yerel, .vps: await vps, .internet: await internet]
        for h in Halka.allCases where haller[h] != yeni[h] {
            TaniGunlugu.yaz("BAĞLANTI \(h.rawValue): \((haller[h] ?? .bilinmiyor).metin) → \((yeni[h] ?? .bilinmiyor).metin)")
        }
        haller = yeni
        sonYoklama = Date()
        if yeni[.yerelVekil]?.yokMu == true { Task { await TelefonProxy.ortak.zorlaDogrula() } }
    }

    private func yerelYokla() async -> Hal {
        guard TelefonProxy.ortak.hazir else { return .yapilandirilmamis }
        return await TelefonProxy.ortak.sunucuCanliMi() ? .iyi : .yok("yanıt yok")
    }

    private nonisolated static func oturum() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 4
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }

    /// 401/404 dahil her HTTP yanıtı sunucuya ulaşıldığını gösterir.
    @concurrent nonisolated static func vpsYokla(taban: URL?, token: String?) async -> Hal {
        guard let taban, let token, !token.isEmpty else { return .yapilandirilmamis }
        var r = URLRequest(url: taban.appending(path: "v1/models"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let o = oturum()
        defer { o.invalidateAndCancel() }
        do {
            let (_, yanit) = try await o.data(for: r)
            return yanit is HTTPURLResponse ? .iyi : .yok("yanıt yok")
        } catch let e as URLError {
            return .yok(neden(e.code))
        } catch {
            return .yok("yanıt yok")
        }
    }

    @concurrent nonisolated static func internetYokla() async -> Hal {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return .bilinmiyor }
        let r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        let o = oturum()
        defer { o.invalidateAndCancel() }
        do {
            let (veri, _) = try await o.data(for: r)
            return internetSonucu(govde: String(decoding: veri, as: UTF8.self))
        } catch let e as URLError {
            return .yok(neden(e.code))
        } catch {
            return .yok("yanıt yok")
        }
    }

    /// Apple sayfası 'Success' döndürür; başka gövde araya giren bir oturum açma sayfasıdır.
    nonisolated static func internetSonucu(govde: String) -> Hal {
        govde.contains("Success") ? .iyi : .yok("oturum açma sayfası")
    }

    /// Kısa, anahtarsız neden. Oturum açma sayfası HTTPS isteğine çoğunlukla TLS hatasıyla döner.
    nonisolated static func neden(_ kod: URLError.Code) -> String {
        switch kod {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            "oturum açma sayfası olabilir"
        case .timedOut: "zaman aşımı"
        case .notConnectedToInternet, .dataNotAllowed: "bağlantı yok"
        case .cannotFindHost, .dnsLookupFailed: "ad çözülemedi"
        case .cannotConnectToHost: "bağlantı reddedildi"
        case .networkConnectionLost: "bağlantı koptu"
        default: "hata \(kod.rawValue)"
        }
    }

    /// Sohbet şeridi metni (saf). En önemli tek sorun; sorun yoksa nil.
    nonisolated static func ozet(_ h: [Halka: Hal], cevrimici: Bool) -> String? {
        if cevrimici, h[.internet]?.yokMu == true {
            return "Ağa bağlı ama internete çıkılamıyor (okul ağı oturum açma sayfası olabilir)"
        }
        if h[.vps]?.yokMu == true, h[.internet] == .iyi { return "Sunucuya (VPS) ulaşılamıyor; telefon yolu kullanılıyor" }
        if h[.yerelVekil]?.yokMu == true { return "Telefondaki CLIProxy yanıt vermiyor; yeniden kuruluyor" }
        return nil
    }

    /// Model hapına eklenecek kısa ek (saf): 'İnternet yok' önce gelir (VPS de ulaşılmaz olur).
    nonisolated static func hapEki(_ h: [Halka: Hal]) -> String? {
        if h[.internet]?.yokMu == true { return "İnternet yok" }
        if h[.vps]?.yokMu == true { return "VPS yok" }
        return nil
    }

    #if DEBUG
    /// Test/önizleme: durumu elle yaz (ağa çıkmaz).
    func durumYaz(_ h: [Halka: Hal]) { haller = h; sonYoklama = Date() }
    #endif
}
