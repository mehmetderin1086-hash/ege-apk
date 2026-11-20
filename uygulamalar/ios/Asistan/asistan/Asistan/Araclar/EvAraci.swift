import Foundation
import FoundationModels
import HomeKit

/// HomeKit: aksesuarları listeler, ada göre açar/kapatır, parlaklık ayarlar.
nonisolated struct EvAraci: Tool {
    let name = "ev"
    let description = "HomeKit ev aksesuarlarını listeler ('listele'), ada göre açar/kapatır ('ac'/'kapat' + ad) ya da parlaklık ayarlar ('parlaklik' + ad + deger 0-100)."

    @Generable
    struct Arguments {
        @Guide(description: "'listele', 'ac', 'kapat', 'parlaklik'") var islem: String
        @Guide(description: "Aksesuar ya da oda adının bir parçası") var ad: String?
        @Guide(description: "parlaklik: 0-100") var deger: Int?
    }

    /// Dış kaynaklı ya da güvenilmeyen içerik okunmuş turda aygıt komutu sorulur (kullanıcının kendi komutunda soru yok).
    var onay: OnayKapisi? = nil

    func call(arguments a: Arguments) async throws -> String {
        let ev = await EvYoneticisi.paylasilan.ev()
        guard let ev else { return "HomeKit'te tanımlı ev bulunamadı (ya da izin yok)." }
        let aks = ev.accessories
        switch a.islem.lowercased() {
        case "listele":
            if aks.isEmpty { return "Evde aksesuar yok." }
            return aks.prefix(30).map { "• \($0.name) (\($0.room?.name ?? "oda yok"))" + ($0.isReachable ? "" : " — erişilemiyor") }.joined(separator: "\n")
        case "ac", "aç", "kapat":
            guard let ad = a.ad, !ad.isEmpty else { return "Hangi aksesuar? Ad gerekli." }
            let hedefler = Self.esle(aks, ad)
            guard !hedefler.isEmpty else { return "'\(ad)' ile eşleşen aksesuar yok." }
            let acik = a.islem.lowercased() != "kapat"
            if let onay {
                let adlar = hedefler.map(\.name).joined(separator: ", ")
                guard await onay.disKaynaktaIste(baslik: acik ? "Aksesuar açılsın mı?" : "Aksesuar kapatılsın mı?", ayrinti: String(adlar.prefix(300))) else {
                    return "Kullanıcı onaylamadı; aksesuar komutu gönderilmedi."
                }
            }
            var yapildi = 0, basarisiz = 0
            for h in hedefler {
                for c in Self.karakteristikler(h, HMCharacteristicTypePowerState) {
                    do { try await c.writeValue(acik); yapildi += 1 }
                    catch { basarisiz += 1 }
                }
            }
            guard yapildi > 0 else { return basarisiz > 0 ? "Aksesuar komutu gönderilemedi; HomeKit erişimini ve bağlantıyı kontrol et." : "Eşleşen aksesuarlarda güç anahtarı yok." }
            let ek = basarisiz > 0 ? " \(basarisiz) aygıt komutu başarısız oldu." : ""
            return "\(hedefler.map(\.name).joined(separator: ", ")) \(acik ? "açıldı" : "kapatıldı").\(ek)"
        case "parlaklik", "parlaklık":
            guard let ad = a.ad, let d = a.deger else { return "Aksesuar adı ve 0-100 değer gerekli." }
            let hedefler = Self.esle(aks, ad)
            if let onay, !hedefler.isEmpty {
                let adlar = hedefler.map(\.name).joined(separator: ", ")
                guard await onay.disKaynaktaIste(baslik: "Parlaklık %\(min(max(d, 0), 100)) yapılsın mı?", ayrinti: String(adlar.prefix(300))) else {
                    return "Kullanıcı onaylamadı; parlaklık değiştirilmedi."
                }
            }
            var yapildi = 0, basarisiz = 0
            for h in hedefler {
                for c in Self.karakteristikler(h, HMCharacteristicTypeBrightness) {
                    do { try await c.writeValue(min(max(d, 0), 100)); yapildi += 1 }
                    catch { basarisiz += 1 }
                }
            }
            guard yapildi > 0 else { return basarisiz > 0 ? "Parlaklık komutu gönderilemedi; HomeKit erişimini ve bağlantıyı kontrol et." : "Parlaklık ayarlanabilir aksesuar bulunamadı." }
            return "Parlaklık %\(min(max(d, 0), 100)) yapıldı." + (basarisiz > 0 ? " \(basarisiz) aygıt komutu başarısız oldu." : "")
        default:
            return "Bilinmeyen işlem: \(a.islem)."
        }
    }

    static func esle(_ aks: [HMAccessory], _ ad: String) -> [HMAccessory] {
        aks.filter { $0.name.localizedCaseInsensitiveContains(ad) || ($0.room?.name.localizedCaseInsensitiveContains(ad) ?? false) }
    }
    static func karakteristikler(_ a: HMAccessory, _ tur: String) -> [HMCharacteristic] {
        a.services.flatMap(\.characteristics).filter { $0.characteristicType == tur }
    }
}

/// HMHomeManager evleri eşzamansız yükler; ilk eve kadar bekler.
@MainActor
final class EvYoneticisi: NSObject, HMHomeManagerDelegate {
    static let paylasilan = EvYoneticisi()
    private lazy var yonetici: HMHomeManager = { let y = HMHomeManager(); y.delegate = self; return y }()
    private var bekleyenler: [CheckedContinuation<HMHome?, Never>] = []

    func ev() async -> HMHome? {
        let y = yonetici
        if let e = y.primaryHome ?? y.homes.first { return e }
        return await withCheckedContinuation { c in
            bekleyenler.append(c)
            Task { try? await Task.sleep(for: .seconds(6)); self.bitir() }
        }
    }
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { Task { @MainActor in self.bitir() } }
    private func bitir() {
        let e = yonetici.primaryHome ?? yonetici.homes.first
        let l = bekleyenler; bekleyenler = []
        l.forEach { $0.resume(returning: e) }
    }
}
