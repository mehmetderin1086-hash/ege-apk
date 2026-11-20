import Foundation
import Darwin

/// P3.9: soğuk açılış ölçümü. Süreç başlangıcından (çekirdeğin kaydettiği `p_starttime`) aşamalara geçen süre
/// SaglikMerkezi'ne `acilis_<aşama>` olarak yazılır (Sağlık → 'Açılış'), tani.log'a 'AÇILIŞ <aşama> N ms' düşer.
/// Aşamalar: 'init' (AsistanApp.init sonu), 'ilk_kare' (WindowGroup `.task` ilk satırı), 'proxy_hazir' (iPhone CLIProxy hazır).
/// Her aşama süreç başına bir kez kaydedilir; test barındırıcısında (XCTest) hiç kaydedilmez.
nonisolated enum AcilisOlcer {
    /// Sürecin başladığı an; sysctl okunamazsa ilk erişim anı (ölçüm o zaman yalnız alt sınır olur).
    static let surecBaslangici: Date = cekirdektenBaslangic() ?? Date()

    /// `kinfo_proc.kp_proc.p_starttime` (yalnız kendi sürecimiz; ayrıcalık gerekmez).
    static func cekirdektenBaslangic() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var bilgi = kinfo_proc()
        var boyut = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &bilgi, &boyut, nil, 0) == 0, boyut > 0 else { return nil }
        // C'deki `p_starttime` bir makrodur (`p_un.__p_starttime`); Swift'e yalnız birlik alanı gelir.
        let t = bilgi.kp_proc.p_un.__p_starttime
        guard t.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }

    @MainActor private static var kaydedilenler: Set<String> = []
    @MainActor private static let testte = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Aşamayı bir kez kaydeder; ölçülen süre döner (ikinci çağrıda ya da testte nil).
    @MainActor @discardableResult
    static func isaretle(_ asama: String, simdi: Date = Date()) -> TimeInterval? {
        guard !testte, kaydedilenler.insert(asama).inserted else { return nil }
        let sure = max(0, simdi.timeIntervalSince(surecBaslangici))
        SaglikMerkezi.ortak.kaydet("acilis_" + asama, sure: sure)
        TaniGunlugu.yaz("AÇILIŞ \(asama) \(Int((sure * 1000).rounded())) ms")
        return sure
    }
}
