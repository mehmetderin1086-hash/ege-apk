import Foundation
import Observation
import SwiftUI
import ProxyKit

/// Uygulamanın tek durum kaynağı: kasa, motor, sunucu ve kullanım kaydı.
@MainActor @Observable
final class AppModel {
    let vault: Vault
    let log: UsageLog
    let engine: ProxyEngine
    let server: LocalHTTPServer
    let keepAlive = KeepAlive()

    var state = ProxyState()
    var records: [UsageRecord] = []
    var serverState: LocalHTTPServer.State = .stopped
    var banner: String?
    var bannerIsError = false
    var lastSync: Date?
    var syncing = false
    var remoteModels: [String] = []

    var port: Int { didSet { UserDefaults.standard.set(port, forKey: "port") } }
    var lanAccess: Bool { didSet { UserDefaults.standard.set(lanAccess, forKey: "lan"); restartIfRunning() } }
    var autoStart: Bool { didSet { UserDefaults.standard.set(autoStart, forKey: "autoStart") } }
    var keepAwakeInBackground: Bool {
        didSet { UserDefaults.standard.set(keepAwakeInBackground, forKey: "keepAlive"); updateKeepAlive() }
    }

    private var launched = false

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["port": 8317, "lan": false, "autoStart": true, "keepAlive": false])
        port = d.integer(forKey: "port")
        lanAccess = d.bool(forKey: "lan")
        autoStart = d.bool(forKey: "autoStart")
        keepAwakeInBackground = d.bool(forKey: "keepAlive")

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // İkra aynı kasayı okur (ortak Keychain grubu); eski tekil kayıt ilk okumada buraya taşınır.
        vault = Vault(store: KeychainSecretStore(accessGroup: KeychainSecretStore.sharedGroup))
        log = UsageLog(file: support.appendingPathComponent("kullanim.json"))
        engine = ProxyEngine(vault: vault, log: log)
        server = LocalHTTPServer(engine: engine)
    }

    // MARK: yaşam döngüsü

    func launch() async {
        guard !launched else { return }
        launched = true
        await vault.observe { s in Task { @MainActor [weak self] in self?.state = s } }
        await log.observe { r in Task { @MainActor [weak self] in self?.records = r } }
        server.onStateChange = { s in Task { @MainActor [weak self] in self?.serverState = s; self?.retryIfAddressInUse(s) } }
        state = await vault.state
        if let locked = await vault.lockedReason { show(locked, error: true) }
        await importPendingBundle()
        if autoStart { startServer() }
        updateKeepAlive()
        if ProcessInfo.processInfo.arguments.contains("--sahiplik-sunucu") {
            // Bakım: döndüren sağlayıcılarda (Claude, ChatGPT) yenilemeyi yeniden sunucuya ver, güncel belirteci hemen çek.
            update { s in
                for i in s.oauth.indices where s.oauth[i].provider.rotatesRefreshToken && s.oauth[i].refreshOwner == .telefon {
                    s.oauth[i].refreshOwner = .sunucu
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
            await syncNow(silent: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--oz-sinama") {
            await SelfTest.run(self)
        }
        await syncNow(silent: true)
    }

    func scenePhaseChanged(_ p: ScenePhase) {
        guard p == .active else { return }
        // Arka planda askıya alınınca dinleyici düşebilir; ön plana dönünce yeniden kur.
        if autoStart, case .failed = serverState { startServer() }
        if autoStart, serverState == .stopped { startServer() }
        Task { await importPendingBundle() }
    }

    // MARK: sunucu

    func startServer() {
        do { try server.start(port: UInt16(clamping: port), lan: lanAccess) }
        catch { serverState = .failed(error.localizedDescription) }
    }

    func stopServer() { server.stop() }

    private var portRetries = 0

    /// Eski dinleyici (askıya alınan ya da yeniden başlatılan süreç) portu henüz bırakmadıysa "Address already in use" (NWError 48)
    /// gelir; birkaç saniye arayla kendiliğinden yeniden dener.
    private func retryIfAddressInUse(_ s: LocalHTTPServer.State) {
        switch s {
        case .running: portRetries = 0
        case .failed(let msg):
            guard autoStart, portRetries < 8, msg.contains("48") || msg.localizedCaseInsensitiveContains("in use") else { return }
            portRetries += 1
            let wait = min(2 * portRetries, 10)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, case .failed = self.serverState else { return }
                self.startServer()
            }
        default: break
        }
    }

    private func restartIfRunning() {
        if case .running = serverState { startServer() }
    }

    private func updateKeepAlive() {
        if keepAwakeInBackground { keepAlive.start() } else { keepAlive.stop() }
    }

    var isRunning: Bool { if case .running = serverState { true } else { false } }

    var localBase: String { "http://127.0.0.1:\(port)/v1" }
    var lanBase: String? { NetworkInfo.wifiAddress().map { "http://\($0):\(port)/v1" } }

    // MARK: içe aktarma

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Mac'ten (devicectl / Finder dosya paylaşımı) Belgeler'e konan paketi alır ve dosyayı siler.
    func importPendingBundle() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.documents, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" && f.lastPathComponent.hasPrefix("telefon-paketi") {
            do {
                try await importBundle(Data(contentsOf: f))
            } catch {
                show("Paket içe aktarılamadı: \(error.localizedDescription)", error: true)
            }
            try? fm.removeItem(at: f)   // sır içeren dosya diskte kalmasın
        }
    }

    func importBundle(_ data: Data) async throws {
        let b = try BundleImporter.decode(data)
        let box = SummaryBox()
        try await vault.update { s in box.value = BundleImporter.apply(b, to: &s) }
        show("Sunucudan taşındı: \(box.value?.text ?? "")")
        await syncNow(silent: true)
    }

    // MARK: işlemler

    func syncNow(silent: Bool = false) async {
        guard !state.remote.syncToken.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await engine.tokens.syncFromServer(force: true)
            lastSync = Date()
            if !silent { show("Erişim belirteçleri sunucudan güncellendi") }
        } catch {
            if !silent { show("Eşitleme başarısız: \(error.localizedDescription)", error: true) }
        }
    }

    func refresh(_ a: OAuthAccount) async {
        do {
            _ = try await engine.tokens.fresh(a, force: true)
            show("\(a.label) güncellendi")
        } catch {
            show("\(a.label): \(error.localizedDescription)", error: true)
        }
    }

    func update(_ body: @escaping @Sendable (inout ProxyState) -> Void) {
        Task {
            do { try await vault.update(body) } catch { show(error.localizedDescription, error: true) }
        }
    }

    func setOwner(_ a: OAuthAccount, _ owner: RefreshOwner) {
        let id = a.qualifiedId
        Task { try? await vault.updateAccount(id) { $0.refreshOwner = owner } }
    }

    func addAccount(_ a: OAuthAccount) async {
        do {
            try await vault.update { s in
                s.oauth.removeAll { $0.provider == a.provider && $0.id == a.id }
                s.oauth.append(a)
            }
            show("\(a.provider.title) hesabı eklendi: \(a.label)")
        } catch { show(error.localizedDescription, error: true) }
    }

    func removeAccount(_ a: OAuthAccount) {
        let id = a.qualifiedId
        update { s in s.oauth.removeAll { $0.qualifiedId == id } }
    }

    func regenerateLocalKey() { update { $0.localKey = ProxyState.newLocalKey() } }

    func resetAll() async {
        try? await vault.reset()
        await log.clear()
        show("Bütün veriler silindi")
    }

    func loadRemoteModels() async {
        let r = await engine.handle(ProxyRequest(method: "GET", path: "/v1/models", headers: ["authorization": "Bearer \(state.localKey)"]))
        var d = Data()
        do { for try await c in r.body { d.append(c) } } catch {}
        remoteModels = (try? JSON.parse(d))?["data"]?.array?.compactMap { $0["id"]?.string } ?? []
    }

    func show(_ text: String, error: Bool = false) {
        banner = text
        bannerIsError = error
        let current = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(error ? 6 : 3.5))
            if self.banner == current { self.banner = nil }
        }
    }
}

final class SummaryBox: @unchecked Sendable { var value: ImportSummary? }
