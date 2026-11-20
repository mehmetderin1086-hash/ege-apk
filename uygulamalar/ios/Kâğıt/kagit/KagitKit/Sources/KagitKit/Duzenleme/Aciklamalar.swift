import CoreGraphics
import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
public typealias PlatformRengi = UIColor
public typealias PlatformYolu = UIBezierPath
public typealias PlatformYaziTipi = UIFont
#else
import AppKit
public typealias PlatformRengi = NSColor
public typealias PlatformYolu = NSBezierPath
public typealias PlatformYaziTipi = NSFont
#endif

extension RGBA {
    public var platformRengi: PlatformRengi { PlatformRengi(red: r, green: g, blue: b, alpha: a) }
    public func opaklikla(_ a: Double) -> RGBA { RGBA(r, g, b, a) }
}

/// PDFKit açıklamalarını (işaretler, şekiller, metin kutusu, mürekkep, not, bağlantı) üreten yardımcılar.
/// Hepsi sayfa koordinatında (sol alt köşe 0,0) çalışır ve `PDFPage.addAnnotation` ile eklenmeye hazır döner.
public enum AciklamaFabrikasi {

    public enum MetinIsareti: String, CaseIterable, Sendable {
        case vurgu, altCizgi, ustuCizili, dalgali
    }

    public enum SekilTuru: String, CaseIterable, Sendable {
        case dikdortgen, daire, cizgi, ok
    }

    /// Satır kutularından vurgu / alt çizgi / üstü çizili açıklaması. Dalgalı alt çizgi PDFKit'te
    /// olmadığından zikzak bir mürekkep açıklaması olarak döner (kaydedilir ve görünür).
    public static func metinIsareti(_ tur: MetinIsareti, satirlar: [CGRect], renk: RGBA) -> PDFAnnotation? {
        let kutular = satirlar.filter { !$0.isNull && !$0.isEmpty }
        guard !kutular.isEmpty else { return nil }
        if tur == .dalgali { return dalgaliAltCizgi(kutular, renk: renk) }
        let birlesik = kutular.reduce(CGRect.null) { $0.union($1) }
        let altTur: PDFAnnotationSubtype = switch tur {
        case .vurgu: .highlight
        case .altCizgi: .underline
        default: .strikeOut
        }
        let a = PDFAnnotation(bounds: birlesik, forType: altTur, withProperties: nil)
        a.color = tur == .vurgu ? renk.platformRengi : renk.opaklikla(1).platformRengi
        // Dört nokta: sol üst, sağ üst, sol alt, sağ alt (açıklama kutusuna göre).
        a.quadrilateralPoints = kutular.flatMap { k -> [NSValue] in
            let x0 = k.minX - birlesik.minX, x1 = k.maxX - birlesik.minX
            let y0 = k.minY - birlesik.minY, y1 = k.maxY - birlesik.minY
            return [CGPoint(x: x0, y: y1), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0)]
                .map { nokta($0) }
        }
        return a
    }

    private static func nokta(_ p: CGPoint) -> NSValue {
        #if canImport(UIKit)
        NSValue(cgPoint: p)
        #else
        NSValue(point: p)
        #endif
    }

    static func dalgaliAltCizgi(_ kutular: [CGRect], renk: RGBA) -> PDFAnnotation? {
        let yollar: [[CGPoint]] = kutular.map { k in
            let adim: CGFloat = 3, genlik: CGFloat = 1.6
            var noktalar: [CGPoint] = []
            var x = k.minX, yukari = false
            while x <= k.maxX {
                noktalar.append(CGPoint(x: x, y: k.minY + (yukari ? genlik : 0)))
                yukari.toggle()
                x += adim
            }
            return noktalar
        }
        return murekkep(yollar: yollar, renk: renk.opaklikla(1), kalinlik: 0.9)
    }

    /// Dikdörtgen, daire, çizgi, ok. `a` ve `b` sürüklemenin iki ucudur.
    public static func sekil(_ tur: SekilTuru, a: CGPoint, b: CGPoint, renk: RGBA, kalinlik: CGFloat,
                             dolgu: RGBA? = nil) -> PDFAnnotation {
        let pay = max(kalinlik, 1) + 2
        switch tur {
        case .dikdortgen, .daire:
            let kutu = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -0, dy: -0)
            let s = PDFAnnotation(bounds: kutu.standardized, forType: tur == .daire ? .circle : .square, withProperties: nil)
            s.color = renk.platformRengi
            if let dolgu { s.interiorColor = dolgu.platformRengi }
            let kenar = PDFBorder()
            kenar.lineWidth = kalinlik
            s.border = kenar
            return s
        case .cizgi, .ok:
            let birlesik = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -pay, dy: -pay)
            let c = PDFAnnotation(bounds: birlesik, forType: .line, withProperties: nil)
            c.startPoint = CGPoint(x: a.x - birlesik.minX, y: a.y - birlesik.minY)
            c.endPoint = CGPoint(x: b.x - birlesik.minX, y: b.y - birlesik.minY)
            c.endLineStyle = tur == .ok ? .closedArrow : .none
            c.startLineStyle = .none
            c.color = renk.platformRengi
            let kenar = PDFBorder()
            kenar.lineWidth = kalinlik
            c.border = kenar
            return c
        }
    }

    /// Serbest metin kutusu.
    public static func metinKutusu(_ kutu: CGRect, metin: String, punto: CGFloat, renk: RGBA, kalin: Bool = false,
                                   hiza: NSTextAlignment = .left) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: kutu, forType: .freeText, withProperties: nil)
        a.contents = metin
        a.font = kalin ? PlatformYaziTipi.boldSystemFont(ofSize: punto) : PlatformYaziTipi.systemFont(ofSize: punto)
        a.fontColor = renk.platformRengi
        a.color = .clear
        a.alignment = hiza
        let kenar = PDFBorder()
        kenar.lineWidth = 0
        a.border = kenar
        return a
    }

    /// Metne göre kutu boyutu (tek/çok satır, en çok `enGenislik`).
    public static func metinKutusuBoyutu(_ metin: String, punto: CGFloat, enGenislik: CGFloat = 280) -> CGSize {
        let tek = PDFCizim.genislik(metin, punto: punto) + 12
        let g = min(max(tek, 40), enGenislik)
        let y = PDFCizim.paragrafYuksekligi(metin, genislik: g - 8, punto: punto) + 8
        return CGSize(width: g, height: max(y, punto * 1.5))
    }

    /// Yapışkan not.
    public static func not(_ nokta: CGPoint, metin: String, renk: RGBA = RGBA(1, 0.85, 0.2)) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: nokta.x, y: nokta.y - 24, width: 24, height: 24), forType: .text, withProperties: nil)
        a.contents = metin
        a.color = renk.platformRengi
        a.iconType = .note
        return a
    }

    /// Çizgilerden (sayfa koordinatında noktalar) mürekkep açıklaması.
    public static func murekkep(yollar: [[CGPoint]], renk: RGBA, kalinlik: CGFloat) -> PDFAnnotation? {
        let tum = yollar.flatMap { $0 }
        guard let ilk = tum.first else { return nil }
        var kutu = CGRect(origin: ilk, size: .zero)
        for p in tum { kutu = kutu.union(CGRect(origin: p, size: .zero)) }
        kutu = kutu.insetBy(dx: -(kalinlik / 2 + 1), dy: -(kalinlik / 2 + 1))
        let a = PDFAnnotation(bounds: kutu, forType: .ink, withProperties: nil)
        a.color = renk.platformRengi
        let kenar = PDFBorder()
        kenar.lineWidth = kalinlik
        a.border = kenar
        for yol in yollar where !yol.isEmpty {
            let b = PlatformYolu()
            let goreli = yol.map { CGPoint(x: $0.x - kutu.minX, y: $0.y - kutu.minY) }
            b.move(to: goreli[0])
            if goreli.count == 1 {
                #if canImport(UIKit)
                b.addLine(to: CGPoint(x: goreli[0].x + 0.1, y: goreli[0].y))
                #else
                b.line(to: CGPoint(x: goreli[0].x + 0.1, y: goreli[0].y))
                #endif
            }
            for p in goreli.dropFirst() {
                #if canImport(UIKit)
                b.addLine(to: p)
                #else
                b.line(to: p)
                #endif
            }
            a.add(b)
        }
        return a
    }

    /// Çok noktalı bir çizgiyi seyreltir (Douglas-Peucker benzeri basit mesafe süzgeci).
    public static func seyrelt(_ noktalar: [CGPoint], aralik: CGFloat = 0.6) -> [CGPoint] {
        guard noktalar.count > 2 else { return noktalar }
        var sonuc = [noktalar[0]]
        for p in noktalar.dropFirst().dropLast() {
            if let s = sonuc.last, hypot(p.x - s.x, p.y - s.y) >= aralik { sonuc.append(p) }
        }
        sonuc.append(noktalar[noktalar.count - 1])
        return sonuc
    }

    /// Bağlantı: dış URL ya da belge içi sayfa.
    public static func baglanti(kutu: CGRect, url: URL) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: kutu, forType: .link, withProperties: nil)
        a.action = PDFActionURL(url: url)
        a.border = sifirKenar()
        return a
    }

    public static func baglanti(kutu: CGRect, hedef: PDFPage, nokta: CGPoint? = nil) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: kutu, forType: .link, withProperties: nil)
        let b = hedef.bounds(for: .cropBox)
        a.action = PDFActionGoTo(destination: PDFDestination(page: hedef, at: nokta ?? CGPoint(x: b.minX, y: b.maxY)))
        a.border = sifirKenar()
        return a
    }

    private static func sifirKenar() -> PDFBorder {
        let k = PDFBorder()
        k.lineWidth = 0
        return k
    }

    /// Bir açıklamanın kopyası (aynı sayfada `kayma` kadar kaydırılmış).
    public static func kopyala(_ a: PDFAnnotation, kayma: CGPoint = CGPoint(x: 14, y: -14)) -> PDFAnnotation? {
        let k: PDFAnnotation
        if let d = a as? KagitDamgasi {
            k = KagitDamgasi(bounds: a.bounds.offsetBy(dx: kayma.x, dy: kayma.y), tanim: d.tanim)
        } else if let c = a.copy() as? PDFAnnotation {
            c.bounds = a.bounds.offsetBy(dx: kayma.x, dy: kayma.y)
            k = c
        } else {
            return nil
        }
        return k
    }

    /// İnsan okunur ad (açıklamalar listesi için).
    public static func ad(_ a: PDFAnnotation) -> String {
        if a is KagitDamgasi { return "Damga" }
        switch a.type ?? "" {
        case "Highlight": return "Vurgu"
        case "Underline": return "Alt çizgi"
        case "StrikeOut": return "Üstü çizili"
        case "Ink": return "Çizim"
        case "Square": return "Dikdörtgen"
        case "Circle": return "Daire"
        case "Line": return a.endLineStyle == .none ? "Çizgi" : "Ok"
        case "FreeText": return "Metin kutusu"
        case "Text": return "Not"
        case "Stamp": return "Damga"
        case "Link": return "Bağlantı"
        case "Widget": return "Form alanı"
        default: return a.type ?? "Açıklama"
        }
    }

    /// Kâğıt'ın silinip düzenlenebilen açıklamaları (form alanları ve açılır pencereler hariç).
    public static func duzenlenebilir(_ a: PDFAnnotation) -> Bool {
        let t = a.type ?? ""
        return t != "Widget" && t != "Popup"
    }
}
