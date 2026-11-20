import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Live kamera ajanı (madde 15): arka kamerayı açar, son kareyi küçültülmüş tutar; Live her turda bu kareyi modele verir.
/// Görüntü geri çağrısı kendi kuyruğunda çalışır: sınıf ana aktöre bağlı değildir (Swift 6 varsayılan yalıtım tuzağı).
nonisolated final class KameraAkisi: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let oturum = AVCaptureSession()
    private let kuyruk = DispatchQueue(label: "asistan.kamera")
    private let kilit = NSLock()
    private var sonGoruntu: CGImage?
    /// Son karenin yazıldığı an (kilit altında); bayat kare (kesinti, yeniden açılış) modele gitmez.
    private var sonKareZamani = Date.distantPast
    /// Kare seyreltme kapısı; yalnız `kuyruk` içinde okunur/yazılır.
    private var sonZaman = Date.distantPast
    static let azamiKareYasi: TimeInterval = 1.5
    private let ci = CIContext()
    private var kuruldu = false
    static let kenar: CGFloat = 768

    /// İzin ister ve oturumu başlatır; izin yoksa false.
    func baslat() async -> Bool {
        var izin = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if !izin { izin = await AVCaptureDevice.requestAccess(for: .video) }
        guard izin else { return false }
        return await withCheckedContinuation { (d: CheckedContinuation<Bool, Never>) in
            kuyruk.async {
                if !self.kuruldu {
                    self.oturum.beginConfiguration()
                    self.oturum.sessionPreset = .high
                    guard let cihaz = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let giris = try? AVCaptureDeviceInput(device: cihaz), self.oturum.canAddInput(giris) else {
                        self.oturum.commitConfiguration(); d.resume(returning: false); return
                    }
                    self.oturum.addInput(giris)
                    let cikis = AVCaptureVideoDataOutput()
                    cikis.alwaysDiscardsLateVideoFrames = true
                    cikis.setSampleBufferDelegate(self, queue: self.kuyruk)
                    if self.oturum.canAddOutput(cikis) { self.oturum.addOutput(cikis) }
                    cikis.connection(with: .video)?.videoRotationAngle = 90
                    self.oturum.commitConfiguration()
                    self.kuruldu = true
                }
                if !self.oturum.isRunning { self.oturum.startRunning() }
                d.resume(returning: true)
            }
        }
    }

    func durdur() {
        // Temizlik seri kuyrukta, durdurmadan sonra: o an işlenen kare temizlikten önce biter, eski kareyi geri yazamaz.
        kuyruk.async {
            if self.oturum.isRunning { self.oturum.stopRunning() }
            self.kilit.lock(); self.sonGoruntu = nil; self.sonKareZamani = .distantPast; self.kilit.unlock()
            self.sonZaman = .distantPast
        }
    }

    /// En son kare (en çok `azamiKareYasi` sn eski; daha eskiyse nil), uzun kenarı 768 px.
    func sonKare() -> CGImage? {
        kilit.lock(); defer { kilit.unlock() }
        return Self.kareTaze(yazildi: sonKareZamani, simdi: Date()) ? sonGoruntu : nil
    }

    /// Kare yaşı sınırı (saf mantık).
    static func kareTaze(yazildi: Date, simdi: Date) -> Bool { simdi.timeIntervalSince(yazildi) <= azamiKareYasi }

    /// OpenAI Realtime için JPEG verisi.
    func sonKareJPEG() -> Data? { sonKare().flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.7) } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(sonZaman) > 0.5, let piksel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        sonZaman = Date()
        var resim = CIImage(cvPixelBuffer: piksel)
        let olcek = min(1, Self.kenar / max(resim.extent.width, resim.extent.height))
        resim = resim.transformed(by: CGAffineTransform(scaleX: olcek, y: olcek))
        guard let cg = ci.createCGImage(resim, from: resim.extent) else { return }
        kilit.lock(); sonGoruntu = cg; sonKareZamani = Date(); kilit.unlock()
    }
}

/// Kamera önizlemesi (AVCaptureVideoPreviewLayer).
struct KameraOnizleme: UIViewRepresentable {
    let oturum: AVCaptureSession
    final class Gorunum: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var katman: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Gorunum {
        let v = Gorunum(); v.katman.session = oturum; v.katman.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: Gorunum, context: Context) {}
}
