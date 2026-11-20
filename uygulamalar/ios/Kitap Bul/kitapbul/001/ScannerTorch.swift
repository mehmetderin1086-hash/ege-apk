import Foundation
#if os(iOS)
import AVFoundation

/// Barkod tarayıcı sırasında cihaz fenerini açıp kapatır.
/// Karanlık depo/raf ortamlarında okuma başarısını belirgin artırır.
enum ScannerTorch {
    static func set(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Fener kullanılamıyorsa tarama normal şekilde sürer
        }
    }
}
#else
enum ScannerTorch {
    static func set(on: Bool) { }
}
#endif
