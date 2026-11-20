import KagitKit
import SwiftUI

/// Öğretmen verileri: sınıflar, okul başlığı şablonu, hazır yorumlar, son notlandırılanlar.
@Observable
final class OgretmenDeposu {
    static let paylasilan = OgretmenDeposu()

    private let sinifDeposu = SinifDeposu()
    private let d = UserDefaults.standard

    var siniflar: [Sinif] { didSet { try? sinifDeposu.kaydet(siniflar) } }
    var baslik: OkulBasligi { didSet { d.set(try? JSONEncoder().encode(baslik), forKey: "ogretmen.baslik") } }
    var yorumlar: [String] { didSet { d.set(yorumlar, forKey: "ogretmen.yorumlar") } }
    /// Kitaplık yolları, en yeni başta.
    var sonNotlandirilan: [String] { didSet { d.set(sonNotlandirilan, forKey: "ogretmen.son") } }

    init() {
        siniflar = sinifDeposu.yukle()
        if let v = d.data(forKey: "ogretmen.baslik"), let b = try? JSONDecoder().decode(OkulBasligi.self, from: v) {
            baslik = b
        } else {
            baslik = OkulBasligi(egitimYili: OkulBasligi.varsayilanYil())
        }
        yorumlar = d.stringArray(forKey: "ogretmen.yorumlar") ?? HazirYorumlar.varsayilan
        sonNotlandirilan = d.stringArray(forKey: "ogretmen.son") ?? []
    }

    func notlandirildi(_ oge: KitaplikOgesi) {
        sonNotlandirilan.removeAll { $0 == oge.yol }
        sonNotlandirilan.insert(oge.yol, at: 0)
        if sonNotlandirilan.count > 12 { sonNotlandirilan.removeLast() }
    }

    func yolDegisti(_ eski: String, _ yeni: String) {
        if let i = sonNotlandirilan.firstIndex(of: eski) { sonNotlandirilan[i] = yeni }
    }
}

/// Düz metin bölümlü, kısa satır içi alan.
struct BaslikAlani: View {
    let ad: String
    @Binding var metin: String
    var body: some View {
        LabeledContent(ad) {
            TextField(ad, text: $metin).multilineTextAlignment(.trailing)
        }
    }
}
