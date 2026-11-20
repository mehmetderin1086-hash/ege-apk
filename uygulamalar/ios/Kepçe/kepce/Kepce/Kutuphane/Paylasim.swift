import SwiftUI

/// İndirilen dosyayı ya da kaynağın bağlantısını paylaşma (WhatsApp, Telegram, Mesajlar, AirDrop, Mail…).
enum Paylasim {
    static func onizleme(_ oge: KutuphaneOgesi) -> SharePreview<Image, Image> {
        let resim = Kutuphane.shared.kapakURL(oge).flatMap { UIImage(contentsOfFile: $0.path) }.map(Image.init(uiImage:))
            ?? Image(systemName: oge.sesMi ? "music.note" : "film")
        return SharePreview(oge.baslik, image: resim, icon: resim)
    }

    static func baglantiMetni(_ oge: KutuphaneOgesi) -> String { "\(oge.baslik)\n\(oge.kaynak)" }

    static var whatsappVar: Bool { UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!) }

    /// WhatsApp'ı sohbet seçme ekranında bağlantıyla açar (dosya göndermek için paylaşım sayfası kullanılır).
    static func whatsappBaglanti(_ oge: KutuphaneOgesi) {
        var bilesen = URLComponents(string: "whatsapp://send")!
        bilesen.queryItems = [URLQueryItem(name: "text", value: baglantiMetni(oge))]
        if let url = bilesen.url { UIApplication.shared.open(url) }
    }
}

/// Satırdaki paylaş düğmesi: dokununca dosyayı paylaşır; basılı tutunca bağlantı seçenekleri çıkar.
struct PaylasDugmesi: View {
    let oge: KutuphaneOgesi
    var buyuk = false

    var body: some View {
        ShareLink(item: Kutuphane.shared.url(oge), preview: Paylasim.onizleme(oge)) {
            Image(systemName: "square.and.arrow.up")
                .font(buyuk ? .title3.weight(.semibold) : .body.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .contextMenu { PaylasMenusu(oge: oge) }
        .accessibilityLabel("Paylaş")
    }
}

/// Bağlam menülerine eklenen paylaşım seçenekleri.
struct PaylasMenusu: View {
    let oge: KutuphaneOgesi

    var body: some View {
        ShareLink(item: Kutuphane.shared.url(oge), preview: Paylasim.onizleme(oge)) {
            Label(oge.sesMi ? "Sesi gönder (WhatsApp, Telegram…)" : "Videoyu gönder (WhatsApp, Telegram…)", systemImage: "paperplane")
        }
        if !oge.kaynak.isEmpty {
            ShareLink(item: Paylasim.baglantiMetni(oge)) { Label("Bağlantıyı paylaş", systemImage: "link") }
            if Paylasim.whatsappVar {
                Button { Paylasim.whatsappBaglanti(oge) } label: { Label("WhatsApp'ta bağlantı gönder", systemImage: "message") }
            }
            Button { UIPasteboard.general.string = oge.kaynak } label: { Label("Bağlantıyı kopyala", systemImage: "doc.on.doc") }
        }
    }
}
