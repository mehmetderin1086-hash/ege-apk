import AVFoundation
import Foundation

// MARK: - Donanım soyutlaması

/// Gerçek `AVAudioSession` işleri ana iş parçacığını bekletmesin diye arka planda çağrılır;
/// testler sahte donanım verir.
nonisolated protocol SesDonanimi: Sendable {
    /// Kategoriyi (`.playAndRecord` + `.voiceChat`) uygular ve oturumu açar.
    func etkinlestir() throws
    /// Oturumu diğer uygulamalara bildirerek kapatır.
    func kapat()
    /// Rota değişiminden sonra kategoriyi (`.defaultToSpeaker` dahil) yeniden uygular.
    func yenidenUygula() throws
}

nonisolated struct GercekSesDonanimi: SesDonanimi {
    private func kategori(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
    }

    func etkinlestir() throws {
        let session = AVAudioSession.sharedInstance()
        try kategori(session)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func kapat() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func yenidenUygula() throws {
        try kategori(AVAudioSession.sharedInstance())
    }
}

/// Mikrofonu sahiplenen nesne (konuşma tanıma). Koordinatör çalmaya geçmeden önce onu durdurur.
@MainActor
protocol SesKaydedici: AnyObject {
    /// Motor ve tanıma tamamen kapanınca döner.
    func stopAndWait() async
}

// MARK: - Koordinatör

/// Uygulamadaki TEK ses oturumu sahibi. Mikrofon (konuşma tanıma) ve hoparlör (sesli yanıt)
/// birbirinin oturumunu ezmesin diye açılış/kapanış sıralıdır:
/// - `beginRecording()` hoparlör çalarken bitene kadar bekler,
/// - `beginPlayback()` önce mikrofonu kapatır ve kapanışı bekler,
/// - kategori her zaman `.playAndRecord` + `.voiceChat` (kategori değiştirip oturum yarışı yok),
/// - çağrı/Siri kesintisinde dinleme durur, bitince (`shouldResume`) kayıtlı geri çağrı çalışır,
/// - rota değişince (kulaklık çıkması) `.defaultToSpeaker` yeniden uygulanır.
@MainActor
final class SesOturumu {
    static let shared = SesOturumu()

    enum Kullanim: Equatable, Sendable { case bos, kayit, oynatma }

    struct Hata: LocalizedError {
        let neden: String
        var errorDescription: String? { neden }
    }

    private(set) var kullanim: Kullanim = .bos
    /// Geçerli sahibin kimliği: geç gelen eski `release` yeni oturumu kapatmasın.
    private var sahip: UUID?
    private let donanim: any SesDonanimi
    private var zincir: Task<Void, Never>?
    private var gozlemciler: [NSObjectProtocol] = []

    weak var kaydedici: (any SesKaydedici)?
    /// Kesinti başladı: dinleme durdurulmuştur.
    var onInterruptionBegan: (() -> Void)?
    /// Kesinti bitti ve sistem devam etmeyi önerdi (örn. sürekli modda yeniden dinle).
    var onInterruptionResume: (() -> Void)?
    private(set) var yenidenUygulamaSayisi = 0

    /// Çalma bitene kadar `beginRecording` en çok bu kadar bekler.
    var oynatmaBeklemeSuresi: Duration = .seconds(15)

    init(donanim: any SesDonanimi = GercekSesDonanimi(), center: NotificationCenter = .default, gozlemle: Bool = true) {
        self.donanim = donanim
        guard gozlemle else { return }
        // iOS 27: eski interruptionNotification yerine "oturum pasifleşti" + "devam önerisi" bildirimleri
        gozlemciler.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            // Kendi kapatmamız (source == .app) kesinti değildir
            let bySystem = context?.source == .system
            MainActor.assumeIsolated { self?.handleSessionInactive(bySystem: bySystem) }
        })
        gozlemciler.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            let shouldResume = context?.recommendation == .shouldResume
            MainActor.assumeIsolated { self?.handleResumptionRecommendation(shouldResume: shouldResume) }
        })
        gozlemciler.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.handleRouteChange(info) }
        })
    }

    // MARK: Açılış / kapanış

    /// Mikrofon için oturumu açar. Hoparlör çalıyorsa çalma bitene (ya da zaman aşımına) kadar bekler.
    @discardableResult
    func beginRecording() async throws -> UUID {
        try await sirali { [self] in
            let bekleme = ContinuousClock.now + oynatmaBeklemeSuresi
            while kullanim == .oynatma, ContinuousClock.now < bekleme {
                try await Task.sleep(for: .milliseconds(20))
            }
            return try await ac(.kayit)
        }
    }

    /// Hoparlör için oturumu açar. Önce mikrofon kapanır; dönüşte mikrofonun kapalı olduğu garantidir.
    @discardableResult
    func beginPlayback() async throws -> UUID {
        try await sirali { [self] in
            if kullanim == .kayit { await kaydedici?.stopAndWait() }
            return try await ac(.oynatma)
        }
    }

    /// Sahibin kimliğiyle bırakır; kimlik güncel sahibe ait değilse hiçbir şey yapmaz.
    func release(_ kimlik: UUID) async {
        guard sahip == kimlik else { return }
        sahip = nil
        kullanim = .bos
        let donanim = donanim
        await Task.detached(priority: .userInitiated) { donanim.kapat() }.value
    }

    private func ac(_ yeni: Kullanim) async throws -> UUID {
        let donanim = donanim
        do {
            try await Task.detached(priority: .userInitiated) { try donanim.etkinlestir() }.value
        } catch {
            throw Hata(neden: "Ses oturumu açılamadı: \(error.localizedDescription)")
        }
        let kimlik = UUID()
        sahip = kimlik
        kullanim = yeni
        return kimlik
    }

    /// İşleri geliş sırasıyla, biri bitmeden öbürü başlamadan çalıştırır.
    private func sirali<T: Sendable>(_ is_: @escaping @MainActor () async throws -> T) async throws -> T {
        let onceki = zincir
        let gorev = Task { @MainActor () async throws -> T in
            await onceki?.value
            return try await is_()
        }
        zincir = Task { _ = try? await gorev.value }
        return try await gorev.value
    }

    // MARK: Kesinti ve rota

    /// Sistem oturumu pasifleştirdi (çağrı, Siri, başka uygulama). Dinleme durur, oynatma sahipliği düşer.
    func handleSessionInactive(bySystem: Bool) {
        guard bySystem else { return }
        let bosalt = kullanim != .bos
        sahip = nil
        kullanim = .bos
        if bosalt { Task { await kaydedici?.stopAndWait() } }
        onInterruptionBegan?()
    }

    /// Sistem devam etmeyi önerdi: yalnız "devam et" önerisinde kayıtlı geri çağrı çalışır.
    func handleResumptionRecommendation(shouldResume: Bool) {
        if shouldResume { onInterruptionResume?() }
    }

    func handleRouteChange(_ info: [AnyHashable: Any]?) {
        guard kullanim != .bos,
              let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        // .categoryChange dinlenmez: yenidenUygula kendisi bu bildirimi üretir (sonsuz döngü)
        case .oldDeviceUnavailable, .newDeviceAvailable:
            yenidenUygulamaSayisi += 1
            let donanim = donanim
            Task.detached(priority: .userInitiated) { try? donanim.yenidenUygula() }
        default:
            break
        }
    }
}
