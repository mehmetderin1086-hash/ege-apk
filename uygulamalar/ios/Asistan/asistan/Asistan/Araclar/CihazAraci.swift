import Foundation
import FoundationModels
import AVFoundation
import UIKit

/// Cihaz denetimi: el feneri, ekran parlaklığı, pil ve depolama durumu; sistem ayarları (Wi-Fi, Bluetooth, uçak modu,
/// mobil veri, düşük güç, dönme kilidi, erişim noktası, Night Shift, True Tone, Rahatsız Etme, görünüm, ses düzeyi,
/// ekran kilidi) `SistemKoprusu` kestirmesiyle.
nonisolated struct CihazAraci: Tool {
    let name = "cihaz"
    let description = "Telefon ayarları. 'fener' (deger ac/kapat), 'parlaklik' (0-100), 'pil', 'depolama'. Sistem ayarları (deger ac/kapat): 'wifi', 'bluetooth', 'ucak' (uçak modu), 'mobilveri', 'dusukguc', 'donmekilidi', 'hotspot', 'gecevardiyasi', 'truetone', 'bildirimseslendir', 'odak' (Rahatsız Etme); 'gorunum' (deger 'karanlik' ya da 'aydinlik'; iOS'taki 'Açık' tema = aydinlik, 'Koyu' = karanlik), 'ses' (medya ses düzeyi: 0-100 ya da göreli 'artir'/'azalt'; zil/sessiz modu değiştirmez), 'kilitle' (ekranı kilitler, deger boş). Birden çok ayar için aracı ayar başına bir kez çağır. Uçak modu, Wi-Fi/mobil veri kapatma ve ekran kilidi yanıt bittikten sonra uygulanır."

    @Generable
    struct Arguments {
        @Guide(description: "'fener', 'parlaklik', 'pil', 'depolama', 'wifi', 'bluetooth', 'ucak', 'mobilveri', 'dusukguc', 'donmekilidi', 'hotspot', 'gecevardiyasi', 'truetone', 'bildirimseslendir', 'odak', 'gorunum', 'ses', 'kilitle'") var islem: String
        @Guide(description: "fener ve sistem anahtarları: 'ac'/'kapat'; parlaklik: 0-100; ses: 0-100, 'artir' ya da 'azalt'; gorunum: 'karanlik'/'aydinlik'; diğerlerinde boş") var deger: String?
    }

    /// Dış kaynaklı turda sistem ayarı değiştirilmeden önce sorulur; kullanıcının kendi komutunda soru yok.
    var onay: OnayKapisi? = nil

    func call(arguments a: Arguments) async throws -> String {
        switch a.islem.lowercased() {
        case "fener":
            guard let c = AVCaptureDevice.default(for: .video), c.hasTorch else { return "Bu cihazda el feneri yok." }
            let ac = (a.deger ?? "ac").lowercased().hasPrefix("a")
            try c.lockForConfiguration()
            c.torchMode = ac ? .on : .off
            c.unlockForConfiguration()
            return ac ? "El feneri açıldı." : "El feneri kapatıldı."
        case "parlaklik", "parlaklık":
            guard let d = a.deger.flatMap({ Double($0.filter { $0.isNumber || $0 == "." }) }) else { return "Parlaklık için 0-100 arası değer ver." }
            let oran = min(max(d, 0), 100) / 100
            await MainActor.run { UIScreen.main.brightness = CGFloat(oran) }
            return "Parlaklık %\(Int(oran * 100)) yapıldı."
        case "pil":
            return await MainActor.run {
                let d = UIDevice.current
                d.isBatteryMonitoringEnabled = true
                let yuzde = Int((d.batteryLevel * 100).rounded())
                let durum: String = switch d.batteryState {
                    case .charging: "şarj oluyor"
                    case .full: "dolu"
                    case .unplugged: "fişte değil"
                    default: "bilinmiyor"
                }
                return yuzde < 0 ? "Pil düzeyi okunamadı." : "Pil %\(yuzde), \(durum)."
            }
        case "depolama":
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let v = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            let bos = Double(v.volumeAvailableCapacityForImportantUsage ?? 0) / 1e9
            let toplam = Double(v.volumeTotalCapacity ?? 0) / 1e9
            return String(format: "Boş alan %.1f GB (toplam %.0f GB).", bos, toplam)
        default:
            let mevcut = await MainActor.run { Double(AVAudioSession.sharedInstance().outputVolume) }
            guard let k = SistemKomutu.coz(ayar: a.islem, deger: a.deger, mevcutSes: mevcut) else {
                return "Bilinmeyen işlem ya da değer: \(a.islem) \(a.deger ?? ""). Anahtarlar için deger 'ac'/'kapat', ses için 0-100 ya da 'artir'/'azalt', görünüm için 'karanlik'/'aydinlik'."
            }
            return try await Self.sistem(k, onay: onay)
        }
    }

    /// `yerel`: modelsiz yerel komut yolu; metin doğrudan kullanıcıya gösterilir (modele yönerge içermez).
    @MainActor
    static func sistem(_ k: SistemKomutu, onay: OnayKapisi?, yerel: Bool = false) async throws -> String {
        let kopru = SistemKoprusu.ortak
        guard kopru.kuruldu else {
            kopru.ekranAcik = true
            return "Bu ayarı değiştirmek için bir kez Asistan Sistem Köprüsü kestirmesini eklemek gerekiyor (iOS sistem ayarlarını yalnız Kestirmeler'e açıyor). Kurulum ekranını açtım: Köprüyü paylaş → Kestirmeler → Kestirme Ekle, sonra Dene'ye dokun. Ayar henüz değişmedi."
        }
        if let onay, !(await onay.disKaynaktaIste(baslik: "\(k.istek) — onaylıyor musun?", ayrinti: "Asistan Sistem Köprüsü")) {
            return "Kullanıcı onaylamadı; ayar değişmedi."
        }
        try Task.checkCancellation()
        if k.yanittanSonra {
            kopru.ertele(k)
            guard k.agiKeser else { return yerel ? "\(k.gelecek)." : "\(k.gelecek) — bu yanıt bittikten hemen sonra. Yanıtında bunu kısaca söyle." }
            if yerel { return "\(k.gelecek). İnternet kesilince bulut model ve bulut ses çalışmaz; bu sırada yalnız telefon içi komutlar yanıtlanır." }
            return "\(k.gelecek) — bu yanıt bittikten hemen sonra (internet kesilince bulut model ve bulut ses çalışmaz). Yanıtında bunu kısaca söyle."
        }
        let s = await kopru.calistir(k)
        let d = s == .tamam ? await kopru.dogrula(k) : nil
        return SistemKoprusu.metin(k, s, dogrulandi: d)
    }
}
