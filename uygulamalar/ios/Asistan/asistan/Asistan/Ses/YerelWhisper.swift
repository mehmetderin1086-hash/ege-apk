import Foundation
import Observation
import UIKit
import WhisperKit

/// Telefonda çalışan Whisper (WhisperKit, Core ML). Model bir kez indirilir, ses cihazdan çıkmaz.
@MainActor
@Observable
final class YerelWhisper {
    /// `indirildi`: model diskte, belleğe yüklenmedi (açılışta kendiliğinden yüklenmez).
    nonisolated enum Durum: Equatable {
        case indirilmedi, indirildi, indiriliyor(Double), yukleniyor, hazir, hata(String)
        var hazirMi: Bool { self == .hazir }
    }

    struct Secenek: Identifiable, Hashable {
        let id: String      // WhisperKit model adı
        let ad: String
        let boyut: String
    }
    /// iPhone 15 (A16) ve üstünde desteklenen, Türkçe bilen (çok dilli) modeller.
    static let secenekler: [Secenek] = [
        Secenek(id: "openai_whisper-small", ad: "Hızlı (small)", boyut: "216 MB"),
        Secenek(id: "openai_whisper-large-v3-v20240930_turbo_632MB", ad: "Dengeli (large-v3 turbo, sıkıştırılmış)", boyut: "632 MB"),
        Secenek(id: "openai_whisper-large-v3-v20240930_626MB", ad: "En doğru (large-v3, sıkıştırılmış)", boyut: "626 MB"),
    ]
    static let varsayilanModel = "openai_whisper-small"

    private(set) var durum: Durum = .indirilmedi
    private(set) var yukluModel: String?
    private(set) var sonSure: TimeInterval?
    private var motor: WhisperKit?
    private var hazirlama: Task<Void, Never>?
    /// Her `hazirla`/`bosalt` çağrısında artar; eski (iptal edilmiş) görev durumu ve tutamağı ezmez.
    private var nesil = 0
    /// Son `hazirla` isteğinin modeli; eski görev aynı modelin sürmekte olan yüklemesinin çökme işaretini silmez.
    private var hedefModel: String?

    /// Çökme işareti: Core ML derlemesi (14 Eki, MLE5ProgramLibrary SIGSEGV) yakalanamaz; işaret yükleme
    /// öncesi yazılır, yükleme dönünce silinir. Açılışta kalmışsa önceki yükleme uygulamayı kapatmıştır.
    nonisolated static let cokmeAnahtariOnek = "whisper.yukleniyor."
    nonisolated static func cokmeAnahtari(_ model: String) -> String { cokmeAnahtariOnek + model }

    nonisolated static func oncekiYuklemeCokmus(_ model: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: cokmeAnahtari(model)) != nil
    }

    /// İşaret yükleme başlangıcının zaman damgasıdır (saniye). Sistem sonlandırması ya da kullanıcının uygulamayı kapatması
    /// çökme sayılmasın diye normal kapanışta (arka plana geçiş, willTerminate) `cokmeIsaretleriniTemizle` ile silinir.
    nonisolated static func cokmeIsaretiYaz(_ model: String, defaults: UserDefaults = .standard) {
        defaults.set(Date().timeIntervalSince1970, forKey: cokmeAnahtari(model))
    }

    /// Bütün modellerin çökme işaretini siler (sistemin kuyruğundan da güvenle çağrılabilir).
    nonisolated static func cokmeIsaretleriniTemizle(defaults: UserDefaults = .standard) {
        for anahtar in defaults.dictionaryRepresentation().keys where anahtar.hasPrefix(cokmeAnahtariOnek) {
            defaults.removeObject(forKey: anahtar)
        }
    }

    private static var kapanisGozlemcileriKuruldu = false

    /// Süreç başına bir kez: uygulama arka plana geçerken ya da sonlanırken sürmekte olan yüklemenin işareti silinir.
    /// Kapanış sistem kuyruğunda çağrılabilir: @Sendable, ana aktöre hiçbir şey taşımaz.
    init() {
        guard !Self.kapanisGozlemcileriKuruldu else { return }
        Self.kapanisGozlemcileriKuruldu = true
        for ad in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: ad, object: nil, queue: nil) { @Sendable _ in
                YerelWhisper.cokmeIsaretleriniTemizle()
            }
        }
    }

    /// Sesli kip açılırken model arka planda yüklensin mi: yalnız yerel Whisper seçiliyken, model diskteyse,
    /// önceki yükleme çökmemişse ve ne yükleniyor/hazır/hatalı ne de indiriliyorsa. İndirilmemiş modeli kendiliğinden indirmez.
    nonisolated static func sesliAcilistaYuklenir(kullan: Bool, durum: Durum, indirilmis: Bool, cokmus: Bool) -> Bool {
        kullan && indirilmis && !cokmus && [Durum.indirildi, .indirilmedi].contains(durum)
    }

    static let cokmeHataMetni = "Önceki yükleme uygulamayı kapattı (Core ML). 'Modeli yükle' ile yeniden dene ya da daha küçük model seç."

    /// Görünen durumu diskteki modele ve çökme işaretine göre günceller. Sürmekte olan indirme/yükleme ve
    /// aynı modelin hazır hâli korunur.
    func durumuTazele(model: String, defaults: UserDefaults = .standard) {
        if case .indiriliyor = durum { return }
        if durum == .yukleniyor { return }
        if durum == .hazir, yukluModel == model { return }
        if Self.oncekiYuklemeCokmus(model, defaults: defaults) {
            durum = .hata(Self.cokmeHataMetni)
        } else {
            durum = Self.indirilmis(model) ? .indirildi : .indirilmedi
        }
    }

    static var indirmeKoku: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "WhisperModelleri")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Model diskte var mı (indirme gerekmeden).
    static func indirilmis(_ model: String) -> Bool {
        guard let e = FileManager.default.enumerator(at: indirmeKoku, includingPropertiesForKeys: nil) else { return false }
        for case let u as URL in e where u.lastPathComponent == model && u.hasDirectoryPath {
            return (try? FileManager.default.contentsOfDirectory(atPath: u.path))?.contains { $0.hasSuffix(".mlmodelc") } ?? false
        }
        return false
    }

    var hazir: Bool { durum == .hazir && motor != nil }

    /// Hesap birimi seçimi: varsayılan WhisperKit (ANE ağırlıklı). `ASISTAN_YEREL_HESAP=cpu` tanılama için CPU/GPU'ya alır.
    nonisolated static var hesapBirimleri: ModelComputeOptions? {
        switch ProcessInfo.processInfo.environment["ASISTAN_YEREL_HESAP"] {
        case "cpu": ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        case "gpu": ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        default: nil
        }
    }

    /// İndirilmiş modeli siler (bozuk indirme şüphesinde).
    static func sil(_ model: String) {
        guard let e = FileManager.default.enumerator(at: indirmeKoku, includingPropertiesForKeys: nil) else { return }
        for case let u as URL in e where u.lastPathComponent == model { try? FileManager.default.removeItem(at: u) }
    }

    /// Modeli (gerekirse indirip) belleğe yükler. Tekrar çağrılması zararsız.
    /// `elle == false` iken önceki yükleme çökmüşse (işaret kalmış) yükleme yapılmaz, durum `.hata` gösterilir;
    /// yalnız Ayarlar > Ses düğmesi (`elle: true`) işareti silip yeniden dener.
    func hazirla(model: String, elle: Bool = false) {
        if yukluModel == model, hazir { return }
        if !elle, Self.oncekiYuklemeCokmus(model) { durumuTazele(model: model); return }
        if elle { UserDefaults.standard.removeObject(forKey: Self.cokmeAnahtari(model)) }
        hazirlama?.cancel()
        nesil += 1
        let n = nesil
        hedefModel = model
        motor = nil
        durum = Self.indirilmis(model) ? .yukleniyor : .indiriliyor(0)
        let ilerleme: @Sendable (Double) -> Void = { [weak self] oran in
            Task { @MainActor in
                guard let self, case .indiriliyor = self.durum else { return }
                self.durum = .indiriliyor(oran)
            }
        }
        hazirlama = Task {
            do {
                var yol: URL?
                if !Self.indirilmis(model) {
                    yol = try await WhisperKit.download(variant: model, downloadBase: Self.indirmeKoku) { p in ilerleme(p.fractionCompleted) }
                }
                guard !Task.isCancelled, n == nesil else { _ = hazirlamaBitti(model: model, nesil: n); return }
                durum = .yukleniyor
                let ayar = WhisperKitConfig(model: model, downloadBase: Self.indirmeKoku, modelFolder: yol?.path,
                                            computeOptions: Self.hesapBirimleri, verbose: false, logLevel: .error,
                                            prewarm: true, load: true, download: true)
                // SIGSEGV yakalanamaz: işaret yüklemeden HEMEN önce diske düşmeli.
                Self.cokmeIsaretiYaz(model)
                UserDefaults.standard.synchronize()
                let m = try await WhisperKit(ayar)
                guard hazirlamaBitti(model: model, nesil: n), !Task.isCancelled else { return }
                motor = m
                yukluModel = model
                durum = .hazir
            } catch {
                guard hazirlamaBitti(model: model, nesil: n) else { return }
                durum = .hata("Whisper hazırlanamadı: \(error.localizedDescription)")
            }
        }
    }

    /// Hazırlama görevinin her çıkışı: yükleme döndüğü için çökme işareti silinir (aynı modelin daha yeni
    /// bir yüklemesi sürüyorsa onun işaretine dokunulmaz). Görev hâlâ son istekse tutamak bırakılır ve true döner.
    private func hazirlamaBitti(model: String, nesil n: Int) -> Bool {
        if n == nesil || hedefModel != model { UserDefaults.standard.removeObject(forKey: Self.cokmeAnahtari(model)) }
        guard n == nesil else { return false }
        hazirlama = nil
        return true
    }

    func bosalt() {
        let m = yukluModel ?? hedefModel
        nesil += 1; hedefModel = nil
        hazirlama?.cancel(); hazirlama = nil
        motor = nil; yukluModel = nil
        durum = .indirilmedi
        if let m { durumuTazele(model: m) }
    }

    /// Mono örnekleri (herhangi bir örnekleme oranı) Türkçe metne çevirir; Whisper 16 kHz ister.
    func cozumle(_ ornekler: [Float], oran: Double = 16000) async throws -> String {
        guard let motor else { throw NSError(domain: "YerelWhisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model hazır değil"]) }
        let ornekler = SesTamponu.yenidenOrnekle(ornekler, kaynakOran: oran, hedefOran: 16000)
        let t0 = Date()
        let secenekler = DecodingOptions(task: .transcribe, language: "tr", temperature: 0, usePrefillPrompt: true,
                                         detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true,
                                         suppressBlank: true, noSpeechThreshold: 0.6)
        let sonuc = try await motor.transcribe(audioArray: ornekler, decodeOptions: secenekler)
        sonSure = Date().timeIntervalSince(t0)
        return Self.temizle(sonuc.map(\.text).joined(separator: " "))
    }

    /// Whisper'ın sessizlikte ürettiği klişe uydurmaları eler.
    static let uydurmalar = ["altyazı", "abone ol", "izlediğiniz için teşekkür", "subtitles", "amara.org", "teşekkürler."]
    static func temizle(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "<\\|[a-z_0-9.]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let k = t.lowercased(with: Locale(identifier: "tr_TR"))  // "İ" → "i" (yerelsiz lowercased "i̇" üretir)
        if uydurmalar.contains(where: { k.contains($0) }) && t.count < 60 { return "" }
        return t
    }
}
