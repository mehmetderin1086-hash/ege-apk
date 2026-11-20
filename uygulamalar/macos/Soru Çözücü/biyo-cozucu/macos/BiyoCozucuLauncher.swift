import AppKit
import Foundation

// Uygulama paketinin çalıştırılabiliri: tek işi paketteki `launcher.sh`'i
// çalıştırmak. Finder bir kabuk betiğini doğrudan uygulama olarak açamıyor;
// bu ince sarmalayıcı ikonu, adı ve imzayı taşıyan gerçek uygulamayı sağlıyor.

let kaynaklar = Bundle.main.resourceURL
let baslatici = kaynaklar?.appendingPathComponent("launcher.sh")

func hataGoster(_ ayrinti: String) -> Never {
    let uyari = NSAlert()
    uyari.messageText = "Soru çözücü başlatılamadı"
    uyari.informativeText = ayrinti
    uyari.alertStyle = .critical
    uyari.runModal()
    exit(1)
}

guard let baslatici, FileManager.default.isExecutableFile(atPath: baslatici.path) else {
    hataGoster("Uygulama paketindeki başlatıcı dosyası bulunamadı.")
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
    hataGoster(error.localizedDescription)
}
