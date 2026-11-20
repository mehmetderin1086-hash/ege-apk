import CoreGraphics
import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
typealias DamgaYolu = UIBezierPath
typealias DamgaRengi = UIColor
typealias DamgaYazisi = UIFont
extension UIBezierPath { func cizgi(_ p: CGPoint) { addLine(to: p) } }
#elseif canImport(AppKit)
import AppKit
typealias DamgaYolu = NSBezierPath
typealias DamgaRengi = NSColor
typealias DamgaYazisi = NSFont
extension NSBezierPath { func cizgi(_ p: CGPoint) { line(to: p) } }
#endif

/// Öğretmenin sınav kâğıdına koyduğu ✓ ✗ ½ ? damgaları, puan etiketleri ve yorumlar (PDF açıklaması olarak).
public enum OgretmenDamga {

    public enum Tur: String, CaseIterable, Sendable, Identifiable {
        case dogru, yanlis, yarim, soru
        public var id: String { rawValue }
        public var ad: String {
            switch self {
            case .dogru: "Doğru"
            case .yanlis: "Yanlış"
            case .yarim: "Yarım"
            case .soru: "Soru"
            }
        }
    }

    static let yesil = DamgaRengi(red: 0.10, green: 0.60, blue: 0.22, alpha: 1)
    static let kirmizi = DamgaRengi(red: 0.86, green: 0.12, blue: 0.12, alpha: 1)
    static let turuncu = DamgaRengi(red: 0.90, green: 0.50, blue: 0.05, alpha: 1)

    /// Merkezi `merkez` olan (sayfa koordinatı) damga.
    public static func damga(_ tur: Tur, merkez: CGPoint, boyut: CGFloat = 30) -> PDFAnnotation {
        let kutu = CGRect(x: merkez.x - boyut / 2, y: merkez.y - boyut / 2, width: boyut, height: boyut)
        switch tur {
        case .dogru, .yanlis:
            let a = PDFAnnotation(bounds: kutu, forType: .ink, withProperties: nil)
            let yol = DamgaYolu()
            let s = boyut
            if tur == .dogru {
                yol.move(to: CGPoint(x: 0.10 * s, y: 0.50 * s))
                yol.cizgi(CGPoint(x: 0.36 * s, y: 0.18 * s))
                yol.cizgi(CGPoint(x: 0.92 * s, y: 0.88 * s))
            } else {
                yol.move(to: CGPoint(x: 0.12 * s, y: 0.12 * s))
                yol.cizgi(CGPoint(x: 0.88 * s, y: 0.88 * s))
                yol.move(to: CGPoint(x: 0.12 * s, y: 0.88 * s))
                yol.cizgi(CGPoint(x: 0.88 * s, y: 0.12 * s))
            }
            a.add(yol)
            a.color = tur == .dogru ? yesil : kirmizi
            let c = PDFBorder()
            c.lineWidth = max(boyut * 0.11, 2)
            a.border = c
            a.userName = Isaret.damga(tur.rawValue)
            return a
        case .yarim:
            return metin("½", kutu: kutu, renk: turuncu, punto: boyut * 0.95, isaret: Isaret.damga(tur.rawValue))
        case .soru:
            return metin("?", kutu: kutu, renk: turuncu, punto: boyut * 0.95, isaret: Isaret.damga(tur.rawValue))
        }
    }

    /// Puan etiketi: “+5”, “-2”. `Isaret.puan` işaretiyle toplamlara girer.
    public static func puanEtiketi(_ deger: Double, merkez: CGPoint) -> PDFAnnotation {
        let yazi = (deger >= 0 ? "+" : "-") + BicimYardimci.sayi(abs(deger))
        let w = CGFloat(yazi.count) * 13 + 14
        let kutu = CGRect(x: merkez.x - w / 2, y: merkez.y - 14, width: w, height: 28)
        return metin(yazi, kutu: kutu, renk: kirmizi, punto: 20, isaret: Isaret.puan(deger))
    }

    /// Hazır yorum (“Aferin!”, “Tekrar et”…).
    public static func yorum(_ yazi: String, merkez: CGPoint) -> PDFAnnotation {
        let w = max(CGFloat(yazi.count) * 8.6 + 14, 50)
        let kutu = CGRect(x: merkez.x - w / 2, y: merkez.y - 11, width: w, height: 22)
        return metin(yazi, kutu: kutu, renk: kirmizi, punto: 14, isaret: OgretmenIsaret.yorum)
    }

    /// Kâğıdın sağ üst köşesine “Toplam: 85”.
    public static func toplamEtiketi(_ toplam: Double, sayfa: PDFPage) -> PDFAnnotation {
        let sinir = sayfa.bounds(for: .cropBox)
        let yazi = "Toplam: \(BicimYardimci.sayi(toplam))"
        let w = CGFloat(yazi.count) * 12 + 20
        let kutu = CGRect(x: sinir.maxX - w - 24, y: sinir.maxY - 48, width: w, height: 32)
        let a = metin(yazi, kutu: kutu, renk: kirmizi, punto: 20, isaret: OgretmenIsaret.toplam)
        a.border = {
            let b = PDFBorder(); b.lineWidth = 1.5; return b
        }()
        return a
    }

    /// Sayfadaki mevcut “Toplam” kutusu.
    public static func toplamKutusu(_ sayfa: PDFPage) -> PDFAnnotation? {
        sayfa.annotations.first { $0.userName == OgretmenIsaret.toplam }
    }

    static func metin(_ yazi: String, kutu: CGRect, renk: DamgaRengi, punto: CGFloat, isaret: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: kutu, forType: .freeText, withProperties: nil)
        a.contents = yazi
        a.font = DamgaYazisi.boldSystemFont(ofSize: punto)
        a.fontColor = renk
        a.color = DamgaRengi.clear
        a.alignment = .center
        let c = PDFBorder()
        c.lineWidth = 0
        a.border = c
        a.userName = isaret
        return a
    }
}
