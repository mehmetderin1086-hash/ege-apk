import AppKit
import Foundation

let kaynaklar = Bundle.main.resourceURL
let baslatici = kaynaklar?.appendingPathComponent("launcher.sh")

guard let baslatici, FileManager.default.isExecutableFile(atPath: baslatici.path) else {
    let uyari = NSAlert()
    uyari.messageText = "Sınav Okur başlatılamadı"
    uyari.informativeText = "Uygulama paketindeki başlatıcı dosyası bulunamadı."
    uyari.alertStyle = .critical
    uyari.runModal()
    exit(1)
}

let islem = Process()
islem.executableURL = URL(fileURLWithPath: "/bin/zsh")
islem.arguments = [baslatici.path]
islem.standardOutput = FileHandle.nullDevice
islem.standardError = FileHandle.nullDevice

do {
    try islem.run()
    islem.waitUntilExit()
    exit(islem.terminationStatus)
} catch {
    let uyari = NSAlert()
    uyari.messageText = "Sınav Okur başlatılamadı"
    uyari.informativeText = error.localizedDescription
    uyari.alertStyle = .critical
    uyari.runModal()
    exit(1)
}
