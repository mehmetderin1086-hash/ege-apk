import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let gradient = NSGradient(colors: [NSColor(red: 0.22, green: 0.11, blue: 0.45, alpha: 1), NSColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1)])!
gradient.draw(in: NSBezierPath(ovalIn: NSRect(x: -220, y: 350, width: 1250, height: 1250)), angle: -50)
NSColor(red: 0.55, green: 0.98, blue: 0.72, alpha: 1).setFill()
for (i, height) in [210.0, 390, 590, 440, 260].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 218 + Double(i) * 122, y: (1024 - height) / 2, width: 80, height: height), xRadius: 40, yRadius: 40).fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
