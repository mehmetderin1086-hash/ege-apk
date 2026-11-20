import SwiftUI

/// Mesajdaki fotoğrafı tam ekran açar: iki parmakla yakınlaştır, çift dokunuşla yakınlaştır/uzaklaştır, kaydırarak gez.
struct FotoGoruntuleyici: View {
    let resim: UIImage
    @Environment(\.dismiss) private var kapat
    @State private var olcek: CGFloat = 1
    @State private var taban: CGFloat = 1
    @State private var kayma: CGSize = .zero
    @State private var sonKayma: CGSize = .zero

    private static let enFazla: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: resim).resizable().scaledToFit()
                .scaleEffect(olcek).offset(kayma)
                .gesture(
                    MagnifyGesture()
                        .onChanged { olcek = min(max(1, taban * $0.magnification), Self.enFazla) }
                        .onEnded { _ in
                            taban = olcek
                            if olcek <= 1 { sifirla() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { if olcek > 1 { kayma = CGSize(width: sonKayma.width + $0.translation.width, height: sonKayma.height + $0.translation.height) } }
                        .onEnded { _ in sonKayma = kayma }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if olcek > 1 { sifirla() } else { olcek = 2.5; taban = 2.5 }
                    }
                }
                .accessibilityLabel("Büyütülmüş fotoğraf").accessibilityIdentifier("foto-buyuk")
            Button { kapat() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 32)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.35)).padding(16)
            }
            .accessibilityLabel("Kapat").accessibilityIdentifier("foto-kapat")
        }
        .statusBarHidden(true)
    }

    private func sifirla() { olcek = 1; taban = 1; kayma = .zero; sonKayma = .zero }
}
