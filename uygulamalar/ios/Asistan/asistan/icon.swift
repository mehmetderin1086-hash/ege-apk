import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Asistan simgesi: sıcak turuncu gradyan, beyaz konuşma balonu, içinde ses dalgası. Dış varlık gerektirmez.
// Kullanım: swift icon.swift <çıktı.png>
let s = 1024
let renk = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: renk, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: renk, components: [r, g, b, a])! }
// Zemin: kil turuncusu → derin mercan (çapraz).
let zemin = CGGradient(colorsSpace: renk, colors: [rgb(0.94, 0.58, 0.42), rgb(0.85, 0.47, 0.34), rgb(0.68, 0.32, 0.23)] as CFArray, locations: [0, 0.55, 1])!
c.drawLinearGradient(zemin, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
// Sol üstte yumuşak ışık.
let isik = CGGradient(colorsSpace: renk, colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
c.drawRadialGradient(isik, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 420, options: [])
// Konuşma balonu + sol alt kuyruk.
let balon = CGMutablePath()
balon.addRoundedRect(in: CGRect(x: 172, y: 262, width: 680, height: 520), cornerWidth: 230, cornerHeight: 230)
balon.move(to: CGPoint(x: 300, y: 330)); balon.addLine(to: CGPoint(x: 200, y: 165)); balon.addLine(to: CGPoint(x: 440, y: 285)); balon.closeSubpath()
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0, 0, 0, 0.22))
c.setFillColor(rgb(0.99, 0.98, 0.96)); c.addPath(balon); c.fillPath()
c.restoreGState()
// Ses dalgası çubukları.
c.setFillColor(rgb(0.85, 0.47, 0.34))
let boylar: [CGFloat] = [110, 210, 320, 210, 260, 150]
let g: CGFloat = 52, ara: CGFloat = 34
let toplam = CGFloat(boylar.count) * g + CGFloat(boylar.count - 1) * ara
for (i, h) in boylar.enumerated() {
    let x = 512 - toplam / 2 + CGFloat(i) * (g + ara)
    c.addPath(CGPath(roundedRect: CGRect(x: x, y: 522 - h / 2, width: g, height: h), cornerWidth: g / 2, cornerHeight: g / 2, transform: nil))
}
c.fillPath()
let resim = c.makeImage()!
let hedef = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(hedef, resim, nil)
guard CGImageDestinationFinalize(hedef) else { fatalError("PNG yazılamadı") }
