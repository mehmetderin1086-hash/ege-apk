import Foundation
import Observation
import ProxyKit

/// CLI Proxy ile aynı güvenli hesap kasası, Asistan'ın kendi işlemindeki motor.
@MainActor
@Observable
final class TelefonProxy {
    struct Model: Identifiable, Equatable {
        let id: String
        var aile: String {
            let s = id.lowercased()
            if s.contains("grok") { return "Grok" }
            if s.contains("claude") { return "Claude" }
            if s.contains("gpt") || s.contains("codex") { return "ChatGPT / Codex" }
            if s.contains("gemini") { return "Gemini" }
            return "Diğer"
        }
        /// Okunur kısa ad: "claude-opus-5-5" → "Opus 5.5", "gemini-3.8-flash" → "Gemini 3.8 Flash", Antigravity → "… · AG".
        var kisaAd: String { Self.kisaAd(id) }
        nonisolated static func kisaAd(_ id: String) -> String {
            var s = id.lowercased()
            let ag = s.hasPrefix("antigravity-")
            s = s.replacingOccurrences(of: "antigravity-", with: "").replacingOccurrences(of: "-tiered", with: "")
            var parcalar = s.split(separator: "-").map(String.init)
            if parcalar.first == "claude", parcalar.count > 1 { parcalar.removeFirst() }
            var cikti: [String] = []
            for p in parcalar {
                let sayi = p.allSatisfy { $0.isNumber || $0 == "." }
                if sayi, let son = cikti.last, son.allSatisfy({ $0.isNumber || $0 == "." }) { cikti[cikti.count - 1] = son + "." + p; continue }
                cikti.append(["gpt", "ag", "xai"].contains(p) ? p.uppercased() : (sayi ? p : p.prefix(1).uppercased() + p.dropFirst()))
            }
            let ad = cikti.joined(separator: " ")
            return ag ? ad + " · AG" : ad
        }
        var gorselUretir: Bool { id.contains("image") || id.contains("imagen") || id.contains("imagine") }
        /// 18 Eki 2026 telefonda ölçüldü: listede görünür ama sohbet isteğine 404 döner ya da "artık mevcut değil" yazar.
        static let calismayanlar = ["antigravity-gemini-2.5-pro", "gemini-3.1-pro", "gemini-4-argon", "gpt-5.5", "gemini-3.5-flash"]
        var sohbet: Bool { !gorselUretir && !Self.calismayanlar.contains(where: id.contains) && !["tts", "audio", "embedding", "whisper", "live", "transcri"].contains(where: id.lowercased().contains) }
    }
    static let ortak = TelefonProxy()
    /// Doğrudan ProxyEngine çağrıları için hesap kasası hazır. Bu durum,
    /// loopback HTTP sunucusunun hızlı uygulama yeniden başlatmalarında portu
    /// henüz bırakmamış olmasından bağımsızdır.
    private(set) var kasaHazir = false
    private(set) var hazir = false
    private(set) var durum = "CLIProxy hesaplarına bağlanıyor…"
    private(set) var hesapSayisi = 0
    private(set) var sonSinama: String?
    private(set) var sinaniyor = false
    private(set) var modeller: [Model] = []
    private(set) var yerelAnahtar = ""
    /// Gerçek iPhone CLIProxy loopback sunucusu.
    let gercekTaban = URL(string: "http://127.0.0.1:18317")!
    /// Bütün tüketiciler bunu okur. DEBUG `--sahte-model` kipinde (P3.10) yerel sahte model sunucusuna yönelir;
    /// `etkin` de denetlenir: birim testinin kendi sahte sunucusu küresel yolu değiştirmez.
    var taban: URL {
        #if DEBUG
        if SahteModelSunucusu.etkin, let s = SahteModelSunucusu.ortak.tabanURL { return s }
        // P3.10-arıza sırası: (a) ağ yok → kapalı port, (b) model arızası + geçiş hazır → geçiş sunucusu, (c) gerçek taban.
        // Geçiş hazır değilse gerçek tabana düşülür (çökme ya da nil yok); geçişi hazirla() ve SinamaEkrani başlatır.
        if !SahteModelSunucusu.etkin {
            if ArizaAnahtarlari.etkin(.agYok) { return Self.arizaKapaliTaban }
            if ArizaAnahtarlari.modelArizasiVar, let g = SahteModelSunucusu.gecis.tabanURL { return g }
        }
        #endif
        return gercekTaban
    }
    #if DEBUG
    /// P3.10-arıza 'ağ yok': dinlenmeyen yerel port (ATS NSAllowsLocalNetworking ile http geçer).
    static let arizaKapaliTaban = URL(string: "http://127.0.0.1:9")!
    #endif
    /// Canlılık yoklaması arıza yönlendirmesinden etkilenmez: geçiş/kapalı port açıkken bekçi yerel sunucuyu boşuna yeniden kurmasın.
    private var yoklamaTabani: URL {
        #if DEBUG
        if SahteModelSunucusu.etkin, let s = SahteModelSunucusu.ortak.tabanURL { return s }
        #endif
        return gercekTaban
    }
    let kasa: Vault
    let motor: ProxyEngine
    private let sunucu: LocalHTTPServer
    private var hazirlama: Task<Void, Never>?
    /// Yerel sunucunun canlılığının en son doğrulandığı an.
    private var sonKontrol = Date.distantPast

    /// Loopback sunucusu bağlantı kabul ediyor mu? Herhangi bir HTTP yanıtı (401/404 dahil) canlı sayılır.
    func sunucuCanliMi() async -> Bool {
        var r = URLRequest(url: yoklamaTabani.appending(path: "v1/models"), timeoutInterval: 1.5)
        r.setValue("Bearer \(yerelAnahtar)", forHTTPHeaderField: "Authorization")
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }
        do { _ = try await oturum.data(for: r); sonKontrol = Date(); return true } catch { return false }
    }

    private var bekci: Task<Void, Never>?
    /// Son `bekciAyarla` isteği (P3.9: güç politikası değişince aynı durumla yeniden kurulur; scenePhase yakalanmaz).
    private var bekciAktif = false
    /// Uygulama öndeyken yerel sunucuyu yoklar (olağan 15 sn; P3.9 termal/Düşük Güç'te `GucPolitikasi` aralığı uzatır);
    /// ölüyse yeniden kurar (iOS soketi sessizce kapatabilir).
    func bekciAyarla(aktif: Bool) {
        bekciAktif = aktif
        bekci?.cancel(); bekci = nil
        guard aktif else { return }
        bekci = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: GucPolitikasi.ortak.karar.bekciAraligi)
                guard let self, !Task.isCancelled else { return }
                if self.hazir, !(await self.sunucuCanliMi()) {
                    TaniGunlugu.yaz("BEKÇİ: yerel sunucu ölü, yeniden kuruluyor")
                    await self.zorlaDogrula()
                }
            }
        }
    }

    /// P3.9: güç politikası değişti; bekçi son istenen durumla (öndeyse yeni aralıkla) yeniden kurulur.
    func bekciYenile() {
        guard bekciAktif else { return }
        bekciAyarla(aktif: true)
    }

    /// Uygulama öne dönünce ya da bağlantı reddedilince: canlılığı hemen yeniden doğrula, gerekirse sunucuyu yeniden kur.
    func zorlaDogrula() async {
        sonKontrol = .distantPast
        await hazirla()
    }

    #if DEBUG
    /// Test: iOS'un soketi kapatmasını taklit eder (durum "hazır" kalır).
    func sunucuyuOldurTest() { sunucu.stop() }
    #endif

    init() {
        kasa = Vault(store: KeychainSecretStore(accessGroup: KeychainSecretStore.sharedGroup))
        motor = ProxyEngine(vault: kasa)
        sunucu = LocalHTTPServer(engine: motor)
        // P3.9: açılışta model listesi önbellekten dolu başlar (yarış ve vites ilk istekte bağlı modelleri bilir);
        // ağdan yenileme yalnız önbellek bayatsa ya da hesap sayısı değiştiyse yapılır (`sinaGerekirse`).
        if Self.onbellekKullanilir, let veri = UserDefaults.standard.data(forKey: Self.modelOnbellekAnahtari),
           let k = try? JSONDecoder().decode(ModelOnbellegi.self, from: veri), !k.ids.isEmpty {
            modeller = k.ids.map { Model(id: $0) }
            modelZamani = Date(timeIntervalSince1970: k.zaman)
            onbellekHesapSayisi = k.hesapSayisi
        }
    }

    // MARK: P3.9 model listesi önbelleği

    nonisolated struct ModelOnbellegi: Codable, Sendable {
        let ids: [String]
        let zaman: Double
        let hesapSayisi: Int
    }
    nonisolated static let modelOnbellekAnahtari = "telefonProxy.modeller.v1"
    /// Önbellek bu süreden eskiyse (ya da hesap sayısı değiştiyse) açılışta yeniden sınanır.
    nonisolated static let modelOnbellekOmru: TimeInterval = 6 * 3600
    /// Model listesinin en son ağdan alındığı an (önbellekten geldiyse kayıt zamanı).
    private(set) var modelZamani: Date?
    private var onbellekHesapSayisi: Int?
    /// Testte, sınamada ve hermetik (sahte model) kipte önbellek okunmaz/yazılmaz: liste her zaman o sürecin sunucusundan gelir.
    private static var onbellekKullanilir: Bool {
        #if DEBUG
        if SahteModelSunucusu.etkin { return false }
        #endif
        return !CevrimdisiKuyruk.yalitilmis
    }

    /// Saf karar: liste taze mi? Zaman yoksa, gelecekteyse, `enEski`'den eskiyse ya da hesap sayısı değiştiyse false.
    nonisolated static func onbellekTaze(zaman: Date?, hesapSayisi: Int?, mevcutHesap: Int, simdi: Date, enEski: TimeInterval) -> Bool {
        guard let zaman, let hesapSayisi, hesapSayisi == mevcutHesap else { return false }
        let yas = simdi.timeIntervalSince(zaman)
        return yas >= 0 && yas < enEski
    }

    /// Önbellek tazeyse ağa gitmez (durum satırına önbellek yaşı yazılır); değilse `sina()`.
    func sinaGerekirse(enEski: TimeInterval = TelefonProxy.modelOnbellekOmru) async {
        await hazirla()
        if hazir, !modeller.isEmpty,
           Self.onbellekTaze(zaman: modelZamani, hesapSayisi: onbellekHesapSayisi, mevcutHesap: hesapSayisi, simdi: .now, enEski: enEski),
           let modelZamani {
            let dk = max(0, Int(Date().timeIntervalSince(modelZamani) / 60))
            sonSinama = "Önbellek: \(modeller.count) model · \(dk) dk önce"
            return
        }
        await sina()
    }

    private func onbellegeYaz() {
        let simdi = Date()
        modelZamani = simdi; onbellekHesapSayisi = hesapSayisi
        guard Self.onbellekKullanilir else { return }
        let k = ModelOnbellegi(ids: modeller.map(\.id), zaman: simdi.timeIntervalSince1970, hesapSayisi: hesapSayisi)
        if let veri = try? JSONEncoder().encode(k) { UserDefaults.standard.set(veri, forKey: Self.modelOnbellekAnahtari) }
    }

    /// Sağlayıcının tüm bağlı hesapları gerçek 429 yanıtıyla bekletilmişse bunu yönlendiriciye aktar.
    /// Kalan kullanım yüzdesi burada bilinmez; uydurma bir kota değeri üretilmez.
    func kotaBeklemeleri() async -> [String: TimeInterval] {
        #if DEBUG
        if SahteModelSunucusu.etkin { return [:] }
        #endif
        let hesaplar = await kasa.state.oauth.filter(\.enabled)
        var sonuc: [String: TimeInterval] = [:]
        // Antigravity'deki Gemini erişimi de Gemini ailesinin yedeğidir.
        // Sağlayıcının gerçek soğuma bilgisini bu aileye aktarınca otomatik
        // vites kota bittiğinde aynı hesabı tekrar tekrar denemez.
        for (aile, saglayici) in [("claude", OAuthProviderKind.claude),
                                  ("gpt", .codex),
                                  ("gemini", .gemini),
                                  ("gemini", .antigravity)] {
            let adaylar = hesaplar.filter { $0.provider == saglayici }
            guard !adaylar.isEmpty else { continue }
            var sureler: [TimeInterval] = []
            for hesap in adaylar { sureler.append(await motor.tokens.cooldownRemaining(hesap.qualifiedId)) }
            if let enErken = sureler.min(), enErken > 0 { sonuc[aile] = enErken }
        }
        return sonuc
    }

    func hazirla() async {
        #if DEBUG
        // P3.10 hermetik kip: kasa, Keychain ve ProxyKit sunucusu hiç başlamaz; istekler yerel sahte sunucuya gider.
        if SahteModelSunucusu.etkin {
            // Dinleyici askıdan dönüşte düşmüşse (tabanURL nil) yeniden kurulur.
            if !hazir || SahteModelSunucusu.ortak.tabanURL == nil {
                do {
                    _ = try await SahteModelSunucusu.ortak.baslat(senaryo: .ortamdan(ProcessInfo.processInfo.environment))
                    yerelAnahtar = "sahte"; kasaHazir = true; hazir = true; hesapSayisi = 1; sonKontrol = Date()
                    durum = "Sahte model"
                } catch {
                    durum = "Sahte model sunucusu başlatılamadı."
                }
            }
            return
        }
        // P3.10-arıza: anahtarlar UserDefaults'ta 30 dk kalıcı; yeniden açılışta model arızası açıksa geçiş sunucusu burada kurulur.
        if ArizaAnahtarlari.modelArizasiVar, SahteModelSunucusu.gecis.tabanURL == nil {
            _ = try? await SahteModelSunucusu.gecis.baslatGecis(hedef: gercekTaban)
        }
        #endif
        // Aynı işlem içindeki çalışan motoru her konuşma turunda yeniden
        // Keychain/port hazırlığından geçirme. ProxyEngine hesap tazeliğini
        // istek sırasında kendi denetler; bu kapı yalnız ilk kuruluma aittir.
        if hazir && kasaHazir {
            // iOS arka plandaki uygulamanın dinleyen soketini sessizce kapatabilir; "çalışıyor" durumu yanıltıcıdır.
            if Date().timeIntervalSince(sonKontrol) < 5 { return }
            if await sunucuCanliMi() { return }
            TaniGunlugu.yaz("YEREL SUNUCU ÖLÜ: yeniden başlatılıyor")
            sunucu.stop(); hazir = false
            try? await Task.sleep(for: .milliseconds(200))   // port serbest kalsın
        }
        if let hazirlama { await hazirlama.value; return }
        let is_ = Task { await self.baslat() }
        hazirlama = is_
        await is_.value
        hazirlama = nil
    }

    private func baslat() async {
        kasaHazir = false
        let durum = await kasa.reload()
        if let hata = await kasa.lockedReason {
            self.durum = hata; hazir = false; return
        }
        hesapSayisi = durum.oauth.filter(\.enabled).count + durum.apiProviders.filter(\.enabled).count
        guard durum.hasUsableAccounts || durum.remote.isUsable else {
            self.durum = "CLI Proxy uygulamasında hesabını bağla, sonra buraya dön."
            hazir = false
            return
        }
        yerelAnahtar = durum.localKey
        OpenAIAnahtari.kasaAnahtari = OpenAIAnahtari.kasadanSec(durum.apiProviders.map { ($0.baseURL, $0.enabled, $0.apiKey) })
        kasaHazir = !yerelAnahtar.isEmpty
        do {
            if case .running = sunucu.state {} else {
                // Önceki dinleyici portu henüz bırakmamış olabilir: kısa aralıkla 3 kez dene.
                var sonHata: Error?
                for _ in 0..<3 {
                    do { try sunucu.start(port: 18317, lan: false); sonHata = nil; break }
                    catch { sonHata = error; sunucu.stop(); try await Task.sleep(for: .milliseconds(250)) }
                }
                if let sonHata { throw sonHata }
            }
            for _ in 0..<60 {
                try Task.checkCancellation()
                switch sunucu.state {
                case .running:
                    hazir = true
                    sonKontrol = Date()
                    self.durum = "iPhone CLIProxy · \(hesapSayisi) bağlı hesap"
                    return
                case .failed: throw URLError(.cannotConnectToHost)
                default: try await Task.sleep(for: .milliseconds(50))
                }
            }
            throw URLError(.timedOut)
        } catch {
            hazir = false
            self.durum = "Telefon bağlantısı başlatılamadı. Yeniden bağlanmayı dene."
        }
    }

    func sina() async {
        guard !sinaniyor else { return }
        sinaniyor = true
        defer { sinaniyor = false }
        await hazirla()
        guard hazir else { sonSinama = durum; return }
        var istek = URLRequest(url: taban.appending(path: "v1/models"))
        istek.setValue("Bearer \(yerelAnahtar)", forHTTPHeaderField: "Authorization")
        istek.timeoutInterval = 25
        do {
            let (veri, yanit) = try await URLSession.shared.data(for: istek)
            guard (yanit as? HTTPURLResponse)?.statusCode == 200,
                  let nesne = try JSONSerialization.jsonObject(with: veri) as? [String: Any],
                  let modeller = nesne["data"] as? [[String: Any]], !modeller.isEmpty else { throw URLError(.badServerResponse) }
            sonSinama = "Bağlantı başarılı · \(modeller.count) model. Yanıt üretimi sohbet sırasında doğrulanır."
            self.modeller = Array(Set(modeller.compactMap { $0["id"] as? String })).sorted().map { Model(id: $0) }
            onbellegeYaz()
            TaniGunlugu.yaz("MODELLER \(self.modeller.map(\.id).joined(separator: ","))")
        } catch {
            sonSinama = "Bağlantı sınaması başarısız. CLI Proxy hesap durumunu ve interneti kontrol et."
        }
    }
}
