import KagitKit
import SwiftUI
import UIKit

/// İşaretle kipindeki araçlar.
enum IsaretAraci: String, CaseIterable, Identifiable {
    case sec, vurgu, altCizgi, ustuCizili, dalgali, kalem, fosforlu, silgi, metinKutusu
    case dikdortgen, daire, cizgi, ok, not, damga, gorsel

    var id: String { rawValue }

    var ad: String {
        switch self {
        case .sec: "Seç"
        case .vurgu: "Vurgu"
        case .altCizgi: "Alt çizgi"
        case .ustuCizili: "Üstü çizili"
        case .dalgali: "Dalgalı"
        case .kalem: "Kalem"
        case .fosforlu: "Fosforlu"
        case .silgi: "Silgi"
        case .metinKutusu: "Metin"
        case .dikdortgen: "Dikdörtgen"
        case .daire: "Daire"
        case .cizgi: "Çizgi"
        case .ok: "Ok"
        case .not: "Not"
        case .damga: "Damga"
        case .gorsel: "Görsel"
        }
    }

    var simge: String {
        switch self {
        case .sec: "cursorarrow"
        case .vurgu: "highlighter"
        case .altCizgi: "underline"
        case .ustuCizili: "strikethrough"
        case .dalgali: "scribble.variable"
        case .kalem: "pencil.tip"
        case .fosforlu: "paintbrush.pointed"
        case .silgi: "eraser"
        case .metinKutusu: "textformat"
        case .dikdortgen: "rectangle"
        case .daire: "circle"
        case .cizgi: "line.diagonal"
        case .ok: "arrow.up.right"
        case .not: "note.text"
        case .damga: "seal"
        case .gorsel: "photo"
        }
    }

    var metinIsareti: AciklamaFabrikasi.MetinIsareti? {
        switch self {
        case .vurgu: .vurgu
        case .altCizgi: .altCizgi
        case .ustuCizili: .ustuCizili
        case .dalgali: .dalgali
        default: nil
        }
    }

    var sekil: AciklamaFabrikasi.SekilTuru? {
        switch self {
        case .dikdortgen: .dikdortgen
        case .daire: .daire
        case .cizgi: .cizgi
        case .ok: .ok
        default: nil
        }
    }

    var kalemMi: Bool { self == .kalem || self == .fosforlu }

    /// Aracın renk/kalınlık paletinde göstereceği ayarlar.
    var kalinlikVar: Bool { kalemMi || sekil != nil }
    var opaklikVar: Bool { metinIsareti == .vurgu || kalemMi || sekil != nil }
    var metinAyariVar: Bool { self == .metinKutusu }
    var renkVar: Bool { self != .sec && self != .silgi && self != .damga && self != .gorsel }
}

/// Renk, kalınlık ve metin ayarları. Son kullanılan renkler kalıcıdır.
@Observable
final class IsaretAyarlari {
    static let hazirRenkler: [RGBA] = [
        RGBA(1, 0.92, 0.1), RGBA(1, 0.55, 0.1), RGBA.kirmizi, RGBA(0.95, 0.3, 0.6),
        RGBA(0.55, 0.3, 0.85), RGBA.mavi, RGBA(0.1, 0.7, 0.8), RGBA.yesil, RGBA.siyah, RGBA(0.5, 0.5, 0.5),
    ]

    var renk: RGBA = RGBA(1, 0.92, 0.1)
    var kalinlik: Double = 3
    var opaklik: Double = 0.4
    var dolgu = false
    var punto: Double = 16
    var kalin = false
    var hiza: Hiza = .sol
    var yalnizPencil = false
    private(set) var sonKullanilan: [RGBA]

    enum Hiza: String, CaseIterable, Identifiable {
        case sol, orta, sag
        var id: String { rawValue }
        var ad: String { switch self { case .sol: "Sol"; case .orta: "Orta"; case .sag: "Sağ" } }
        var nsHiza: NSTextAlignment { switch self { case .sol: .left; case .orta: .center; case .sag: .right } }
    }

    init() {
        if let veri = UserDefaults.standard.data(forKey: "isaret.sonRenkler"),
           let liste = try? JSONDecoder().decode([RGBA].self, from: veri) {
            sonKullanilan = liste
        } else {
            sonKullanilan = []
        }
    }

    /// Araç değişince makul varsayılanlar.
    func varsayilanlar(_ a: IsaretAraci) {
        switch a {
        case .vurgu: opaklik = 0.4
        case .fosforlu: opaklik = 0.35; kalinlik = max(kalinlik, 12)
        case .kalem: opaklik = 1; kalinlik = min(kalinlik, 6)
        case .dikdortgen, .daire, .cizgi, .ok: opaklik = 1
        default: break
        }
    }

    /// Çizimde kullanılacak renk (opaklık dahil).
    func etkinRenk(_ a: IsaretAraci) -> RGBA {
        a.opaklikVar ? renk.opaklikla(opaklik) : renk.opaklikla(1)
    }

    func renkSec(_ r: RGBA) {
        renk = r.opaklikla(1)
        var liste = sonKullanilan.filter { !($0.r == r.r && $0.g == r.g && $0.b == r.b) }
        liste.insert(r.opaklikla(1), at: 0)
        sonKullanilan = Array(liste.prefix(8))
        if let veri = try? JSONEncoder().encode(sonKullanilan) {
            UserDefaults.standard.set(veri, forKey: "isaret.sonRenkler")
        }
    }
}

extension RGBA {
    var swiftUIRengi: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ renk: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(renk).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
}
