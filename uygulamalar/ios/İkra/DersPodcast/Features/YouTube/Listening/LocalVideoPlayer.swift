import AVKit
import SwiftUI

/// İndirilmiş dersin videosu: yerleşik oynatıcı denetimleri ve resim içinde resim (PiP).
/// AVPlayer'ı `VideoPlayerModel` yönetir (konum, hız, kilit ekranı onda); burası yalnızca görüntüyü gösterir.
/// PiP açıkken ders ekranından çıkılırsa oynatıcı `PictureInPictureKeeper` ile PiP kapanana dek yaşar.
struct LocalVideoPlayerView: UIViewControllerRepresentable {
    var model: VideoPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.videoPlayer
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        // Kilit ekranı bilgisini ders oynatıcısı kendisi yazar; yerleşik oynatıcı ezmesin.
        controller.updatesNowPlayingInfoCenter = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.model = model
        if controller.player !== model.videoPlayer { controller.player = model.videoPlayer }
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var model: VideoPlayerModel

        init(model: VideoPlayerModel) { self.model = model }

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            model.pictureInPictureStarted(playerViewController)
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            model.pictureInPictureStopped()
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  failedToStartPictureInPictureWithError error: any Error) {
            model.pictureInPictureStopped()
        }

        /// Kullanıcı PiP'teki "uygulamaya dön" düğmesine bastı: arayüz geri yüklenmiş sayılır.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
}

/// Ders ekranı kapandığında PiP'te oynayan oynatıcıyı PiP kapanana dek canlı tutar.
enum PictureInPictureKeeper {
    private static var held: [ObjectIdentifier: VideoPlayerModel] = [:]

    static func hold(_ model: VideoPlayerModel) { held[ObjectIdentifier(model)] = model }
    static func release(_ model: VideoPlayerModel) { held[ObjectIdentifier(model)] = nil }
    static var count: Int { held.count }
}

/// Yerel video açılamadığında oynatıcı alanında gösterilen hata.
struct LocalVideoFailure: View {
    var message: String
    var onOpenYouTube: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            Text(message).font(.callout).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.7)
            Button("YouTube’da aç", systemImage: "arrow.up.right.square", action: onOpenYouTube)
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }
}
