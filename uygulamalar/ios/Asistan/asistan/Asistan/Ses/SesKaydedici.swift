import Foundation
import AVFoundation
import Observation

/// Toplantı kaydı (P4.6): uzun süreli, yalnız bu telefonda saklanan ses kaydı. AAC (m4a), 16 kHz mono, orta kalite
/// (~3 saatlik kayıt ~80 MB'ı geçmez); dosyalar Application Support/Toplantilar/<yyyy-MM-dd-HHmm>.m4a, iCloud yedeği dışında.
///
/// Tek örnek (`ortak`): kayıt ekranı kapansa da kaydedici yaşar; AVAudioRecorder serbest kalırsa m4a yarım kalır.
/// Arka planda sürmesi `UIBackgroundModes: audio` ile olur (kayıt öndeyken başlamalı).
/// Çağıran (KayitEkrani) başlamadan önce SesOturumu'nun dinlemesini kapatır (eller serbest / uyandırma mikrofonu tutar).
@MainActor @Observable
final class SesKaydedici {
    static let ortak = SesKaydedici()

    enum Durum: Equatable { case bos, kayitta, duraklatildi, bitti(URL) }
    private(set) var durum: Durum = .bos
    /// Kaydedilen süre (duraklatmalar hariç), saniye.
    private(set) var sure: TimeInterval = 0
    /// 0…1 giriş seviyesi (ortalama güç, −50 dB taban).
    private(set) var seviye: Float = 0
    var hata: String?

    nonisolated static let enUzunSure: TimeInterval = 3 * 3600
    nonisolated static let enAzBosAlan: Int64 = 500_000_000

    @ObservationIgnored private var kaydedici: AVAudioRecorder?
    @ObservationIgnored private var olcum: Task<Void, Never>?
    @ObservationIgnored private var kesintiGozlemi: (any NSObjectProtocol)?
    @ObservationIgnored private var oturumNesli = 0
    /// Arama gibi bir kesintide kayıt sürüyordu (kesinti bitince ve sistem izin verirse kendiliğinden sürer).
    @ObservationIgnored private var kesintideDurdu = false
    @ObservationIgnored private var surdurmeSuruyor = false
    /// Kayıt bitince ses oturumunun bırakılıp bırakılmayacağına SesOturumu karar verir (SesOturumu.init bağlar).
    @ObservationIgnored var oturumuBirakIstegi: (() -> Void)?

    var suruyor: Bool { durum == .kayitta || durum == .duraklatildi }

    // MARK: Saf yardımcılar

    nonisolated static var klasor: URL {
        URL.applicationSupportDirectory.appending(path: "Toplantilar", directoryHint: .isDirectory)
    }

    /// Kayda başlamak için boş alan yeterli mi: en az 500 MB ya da (daha büyükse) `sureSaat` boyunca 64 kbps'nin iki katı.
    nonisolated static func yeterliAlanVar(bos: Int64, sureSaat: Double = 3) -> Bool {
        let tahmin = Int64(sureSaat * 3600 * 8000) * 2
        return bos >= max(enAzBosAlan, tahmin)
    }

    /// "2026-10-20-1405.m4a" (POSIX takvim; saat dilimi yerel).
    nonisolated static func dosyaAdi(_ tarih: Date, saatDilimi: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = saatDilimi
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: tarih) + ".m4a"
    }

    /// dB (−160…0) → 0…1; −50 dB ve altı 0.
    nonisolated static func seviyeOrani(db: Float) -> Float {
        guard db.isFinite else { return 0 }
        return max(0, min(1, (db + 50) / 50))
    }

    /// Kaydın döküm dosyası: aynı ad, .txt uzantısı.
    nonisolated static func dokumYolu(_ ses: URL) -> URL { ses.deletingPathExtension().appendingPathExtension("txt") }

    /// Kayıtlar, yeniden eskiye.
    nonisolated static func kayitlar(_ k: URL = klasor) -> [URL] {
        let fm = FileManager.default
        let l = (try? fm.contentsOfDirectory(at: k, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return l.filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Kaydı ve dökümünü siler (süren kaydın dosyası silinmez).
    func sil(_ ses: URL) {
        if case .bitti(let u) = durum, u == ses { durum = .bos }
        guard !suruyor || kaydedici?.url != ses else { return }
        try? FileManager.default.removeItem(at: ses)
        try? FileManager.default.removeItem(at: Self.dokumYolu(ses))
    }

    // MARK: Kayıt

    /// Kaydı başlatır; başlamazsa `hata` dolar ve false döner.
    @discardableResult
    func basla() async -> Bool {
        guard !suruyor else { return true }
        hata = nil
        if AVAudioApplication.shared.recordPermission == .undetermined { await IzinIstegi.mikrofon() }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            hata = "Mikrofon izni yok. Ayarlar > Asistan > Mikrofon'dan izin verebilirsin."
            return false
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.klasor, withIntermediateDirectories: true)
            var k = Self.klasor
            var d = URLResourceValues(); d.isExcludedFromBackup = true
            try? k.setResourceValues(d)
        } catch {
            hata = "Kayıt klasörü oluşturulamadı."
            return false
        }
        let bos = (try? Self.klasor.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard Self.yeterliAlanVar(bos: bos) else {
            hata = "Telefonda yeterli boş alan yok (en az 500 MB gerekir)."
            return false
        }
        let ad = Self.dosyaAdi(.now)
        var hedef = Self.klasor.appending(path: ad)
        var n = 2
        while fm.fileExists(atPath: hedef.path) {
            hedef = Self.klasor.appending(path: ad.replacingOccurrences(of: ".m4a", with: "_\(n).m4a"))
            n += 1
        }
        do {
            oturumNesli = SesOturumuKapisi.istek.artir()   // bekleyen 'oturumu bırak' istekleri kaydı kesmesin
            try await Self.oturumuHazirla()
            let ayar: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let r = try AVAudioRecorder(url: hedef, settings: ayar)
            r.isMeteringEnabled = true
            guard r.prepareToRecord(), r.record() else {
                try? fm.removeItem(at: hedef)
                hata = "Kayıt başlatılamadı."
                let n = oturumNesli
                Task { await SesOturumuKapisi.ortak.birak(nesil: n) }
                return false
            }
            kaydedici = r
        } catch {
            hata = "Kayıt başlatılamadı: \(error.localizedDescription)"
            return false
        }
        sure = 0; seviye = 0
        durum = .kayitta
        kesintiyiGozle()
        olcumuBaslat()
        TaniGunlugu.yaz("TOPLANTI KAYDI başladı")
        return true
    }

    func duraklat() {
        guard durum == .kayitta, let r = kaydedici else { return }
        r.pause()
        sure = max(sure, r.currentTime)
        kesintideDurdu = false
        durum = .duraklatildi
        seviye = 0
    }

    func surdur() {
        guard durum == .duraklatildi, kaydedici != nil, !surdurmeSuruyor else { return }
        surdurmeSuruyor = true
        oturumNesli = SesOturumuKapisi.istek.artir()   // bekleyen 'oturumu bırak' istekleri sürdürmeyi kesmesin
        // setActive yüzlerce ms sürebilir: ana aktör tutulmaz (sürdürme durumu etkinleşince yazılır).
        Task { [weak self] in
            try? await Self.oturumuEtkinlestir()
            guard let self else { return }
            surdurmeSuruyor = false
            guard durum == .duraklatildi, let r = kaydedici else { return }
            guard r.record() else { hata = "Kayıt sürdürülemedi."; return }
            durum = .kayitta
        }
    }

    /// Kaydı kapatır; dosya `.bitti(url)` ile döner.
    @discardableResult
    func bitir() -> URL? {
        guard suruyor, let r = kaydedici else { return nil }
        sure = max(sure, r.currentTime)
        r.stop()
        kaydedici = nil
        olcum?.cancel(); olcum = nil
        if let g = kesintiGozlemi { NotificationCenter.default.removeObserver(g) }
        kesintiGozlemi = nil
        seviye = 0
        durum = .bitti(r.url)
        // Kayıt sürerken başka bir bileşen oturumu yeniden etkinleştirmiş olabilir (nesil artar); bırakma kararını
        // SesOturumu güncel duruma göre verir (dinleyici/konuşma sürüyorsa bırakılmaz). Kanca yoksa güncel nesille bırakılır.
        if let istek = oturumuBirakIstegi { istek() }
        else { let n = SesOturumuKapisi.istek.deger; Task { await SesOturumuKapisi.ortak.birak(nesil: n) } }
        TaniGunlugu.yaz("TOPLANTI KAYDI bitti: \(Int(sure)) sn")
        return r.url
    }

    /// Yeni kayıt için hazır duruma döner (biten kaydın dosyası yerinde kalır).
    func sifirla() {
        guard !suruyor else { return }
        durum = .bos; sure = 0; seviye = 0; hata = nil
    }

    // MARK: İç işler

    /// Kayıt oturumu: playAndRecord, dahili mikrofon (toplantıda telefon masada durur). Bluetooth HFP verilmez:
    /// kutudaki kulaklık girişi sıfırlıyordu (SesOturumuKapisi notu).
    @concurrent nonisolated static func oturumuHazirla() async throws {
        let o = AVAudioSession.sharedInstance()
        try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        if let dahili = o.availableInputs?.first(where: { $0.portType == .builtInMic }) { try? o.setPreferredInput(dahili) }
        try o.setActive(true)
    }

    @concurrent nonisolated static func oturumuEtkinlestir() async throws {
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func olcumuBaslat() {
        olcum?.cancel()
        olcum = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let r = self.kaydedici else { return }
                if self.durum == .kayitta {
                    r.updateMeters()
                    self.seviye = Self.seviyeOrani(db: r.averagePower(forChannel: 0))
                    self.sure = max(self.sure, r.currentTime)
                    if self.sure >= Self.enUzunSure { self.bitir(); return }
                }
            }
        }
    }

    /// Arama gelince sistem kaydı duraklatır; durum ekranda görünsün, kesinti bitince (izin varsa) kayıt sürsün.
    /// Kapanış bildirimi gönderen iş parçacığında çağrılır: @Sendable, ana aktöre yalnız sayılar taşınır.
    private func kesintiyiGozle() {
        if let g = kesintiGozlemi { NotificationCenter.default.removeObserver(g) }
        kesintiGozlemi = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { @Sendable b in
            let tur = (b.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let secenek = (b.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in SesKaydedici.ortak.kesinti(tur: tur, secenek: secenek) }
        }
    }

    private func kesinti(tur: UInt, secenek: UInt) {
        if tur == AVAudioSession.InterruptionType.began.rawValue {
            guard durum == .kayitta else { return }
            duraklat()
            kesintideDurdu = true
        } else if tur == AVAudioSession.InterruptionType.ended.rawValue {
            guard durum == .duraklatildi, kesintideDurdu else { return }
            kesintideDurdu = false
            if AVAudioSession.InterruptionOptions(rawValue: secenek).contains(.shouldResume) { surdur() }
        }
    }
}
