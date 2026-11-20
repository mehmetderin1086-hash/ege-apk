import KagitKit
import PencilKit
import SwiftUI
import UIKit

/// Kayıtlı imza ya da baş harf.
struct KayitliImza: Codable, Identifiable, Hashable {
    var id = UUID()
    var ad: String
    var basHarf: Bool
    var tarih = Date()
}

/// İmzalar Application Support/Imzalar altında saklanır: `<id>.drawing` (PKDrawing) ve `<id>.png` (saydam), `liste.json`.
@Observable
final class ImzaDeposu {
    static let paylasilan = ImzaDeposu()

    private(set) var imzalar: [KayitliImza] = []

    private let klasor: URL = {
        let k = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imzalar", isDirectory: true)
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k
    }()

    private var listeURL: URL { klasor.appendingPathComponent("liste.json") }

    init() {
        if let veri = try? Data(contentsOf: listeURL), let l = try? JSONDecoder().decode([KayitliImza].self, from: veri) {
            imzalar = l
        }
    }

    var tamImzalar: [KayitliImza] { imzalar.filter { !$0.basHarf } }
    var basHarfler: [KayitliImza] { imzalar.filter(\.basHarf) }

    func ekle(_ cizim: PKDrawing, ad: String, basHarf: Bool) throws {
        guard !cizim.strokes.isEmpty else { throw KagitHata.bosGirdi }
        let imza = KayitliImza(ad: ad.isEmpty ? (basHarf ? "Baş harf" : "İmza") : ad, basHarf: basHarf)
        let kutu = cizim.bounds.insetBy(dx: -6, dy: -6)
        var png: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            png = cizim.image(from: kutu, scale: 3).pngData()
        }
        guard let png else { throw KagitHata.kaydedilemedi("imza görüntüsü") }
        try png.write(to: pngURL(imza), options: .atomic)
        try cizim.dataRepresentation().write(to: cizimURL(imza), options: .atomic)
        imzalar.insert(imza, at: 0)
        kaydet()
    }

    func sil(_ i: KayitliImza) {
        try? FileManager.default.removeItem(at: pngURL(i))
        try? FileManager.default.removeItem(at: cizimURL(i))
        imzalar.removeAll { $0.id == i.id }
        kaydet()
    }

    func adDegistir(_ i: KayitliImza, _ ad: String) {
        guard let k = imzalar.firstIndex(where: { $0.id == i.id }) else { return }
        imzalar[k].ad = ad
        kaydet()
    }

    func png(_ i: KayitliImza) -> Data? { try? Data(contentsOf: pngURL(i)) }

    func damga(_ i: KayitliImza) -> DamgaTanimi? {
        guard let p = png(i) else { return nil }
        return DamgaTanimi(tur: .gorsel, metin: i.ad, gorselVeri: p)
    }

    private func pngURL(_ i: KayitliImza) -> URL { klasor.appendingPathComponent("\(i.id.uuidString).png") }
    private func cizimURL(_ i: KayitliImza) -> URL { klasor.appendingPathComponent("\(i.id.uuidString).drawing") }

    private func kaydet() {
        if let veri = try? JSONEncoder().encode(imzalar) { try? veri.write(to: listeURL, options: .atomic) }
    }
}

/// Kullanıcının özel metin damgaları (UserDefaults).
@Observable
final class DamgaDeposu {
    static let paylasilan = DamgaDeposu()

    private(set) var ozel: [DamgaTanimi]

    init() {
        if let v = UserDefaults.standard.data(forKey: "damga.ozel"), let l = try? JSONDecoder().decode([DamgaTanimi].self, from: v) {
            ozel = l
        } else {
            ozel = []
        }
    }

    func ekle(_ d: DamgaTanimi) {
        ozel.append(d)
        kaydet()
    }

    func sil(_ d: DamgaTanimi) {
        ozel.removeAll { $0.id == d.id }
        kaydet()
    }

    private func kaydet() {
        if let v = try? JSONEncoder().encode(ozel) { UserDefaults.standard.set(v, forKey: "damga.ozel") }
    }
}
