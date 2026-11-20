import Foundation
import WidgetKit

/// P4.2: uygulama ile widget/kontrol uzantısının (AsistanKontrol) paylaştığı ayarlar (App Group).
/// Bu dosya iki hedefe derlenir. Okuma/yazma suite enjekte edilerek yapılır: testler ve önizleme kendi suite'ini verir,
/// gerçek App Group değerine dokunmaz (`Ayarlar(ortak:)` yalnız uygulamanın gerçek yolunda `suite` alır).
nonisolated enum OrtakAyarlar {
    static let grup = "group.com.mehmetderin.asistan"
    /// App Group suite'i; yetki yoksa (yanlış imza) nil.
    static var suite: UserDefaults? { UserDefaults(suiteName: grup) }
    /// Uygulamanın yerel anahtarıyla aynı ad: göçte karışıklık olmasın.
    static let heyAnahtari = "ayar.heyAsistan"
    /// Hey Asistan kontrolünün türü (`AsistanHeyKontrol`); ayar değişince bu tür yenilenir.
    static let heyKontrolTuru = "com.mehmetderin.asistan.hey-kontrol"

    /// Ortak alandaki Hey Asistan değeri; hiç yazılmamışsa nil (çağıran yerel değere/varsayılana düşer).
    static func heyAsistan(_ d: UserDefaults) -> Bool? { d.object(forKey: heyAnahtari) as? Bool }
    static func heyAsistanYaz(_ deger: Bool, _ d: UserDefaults) { d.set(deger, forKey: heyAnahtari) }

    /// Kolaylık: gerçek App Group değeri (yalnız kontrol uzantısı ve kontrol intent'i kullanır).
    static var heyAsistan: Bool? {
        get { suite.flatMap { heyAsistan($0) } }
        set {
            guard let d = suite else { return }
            if let v = newValue { heyAsistanYaz(v, d) } else { d.removeObject(forKey: heyAnahtari) }
        }
    }

    /// Kontrol Merkezi'ndeki Hey Asistan anahtarı yeni değeri göstersin.
    @MainActor static func heyKontrolunuYenile() {
        ControlCenter.shared.reloadControls(ofKind: heyKontrolTuru)
    }
}
