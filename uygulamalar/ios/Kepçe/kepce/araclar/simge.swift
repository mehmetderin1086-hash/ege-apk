import AppKit
// Kepçe uygulama simgesi: sıcak kırmızı-turuncu degrade, ortada kalın aşağı ok ve kepçe çanağı.
let boyut = 1024.0
let resim = NSImage(size: NSSize(width: boyut, height: boyut))
resim.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let renkler = [NSColor(red: 1.0, green: 0.42, blue: 0.24, alpha: 1).cgColor, NSColor(red: 0.85, green: 0.12, blue: 0.25, alpha: 1).cgColor] as CFArray
let degrade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: renkler, locations: [0, 1])!
ctx.drawLinearGradient(degrade, start: CGPoint(x: 0, y: boyut), end: CGPoint(x: boyut, y: 0), options: [])
// Kepçe çanağı (yarım daire) + sap
ctx.setFillColor(NSColor.white.cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)
let canak = CGMutablePath()
canak.move(to: CGPoint(x: 262, y: 400))
canak.addArc(center: CGPoint(x: 512, y: 400), radius: 250, startAngle: .pi, endAngle: 0, clockwise: false)
canak.closeSubpath()
ctx.addPath(canak)
ctx.fillPath()
// Ok: çanağın üstünde beyaz, çanağın içinde turuncu.
func ok() {
    ctx.fill(CGRect(x: 462, y: 500, width: 100, height: 320))
    let bas = CGMutablePath()
    bas.move(to: CGPoint(x: 352, y: 530))
    bas.addLine(to: CGPoint(x: 672, y: 530))
    bas.addLine(to: CGPoint(x: 512, y: 320))
    bas.closeSubpath()
    ctx.addPath(bas)
    ctx.fillPath()
}
ctx.saveGState()
ctx.addPath(canak); ctx.clip()
ctx.setFillColor(NSColor(red: 0.95, green: 0.30, blue: 0.24, alpha: 1).cgColor)
ok()
ctx.restoreGState()
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: 400, width: boyut, height: boyut))
ctx.setFillColor(NSColor.white.cgColor)
ok()
ctx.restoreGState()
resim.unlockFocus()
let tif = resim.tiffRepresentation!
let rep = NSBitmapImageRep(data: tif)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
