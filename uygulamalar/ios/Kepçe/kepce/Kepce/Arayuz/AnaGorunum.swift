import SwiftUI

struct AnaGorunum: View {
    @Environment(Yonlendirici.self) private var yonlendirici
    private let kuyruk = IndirmeKuyrugu.shared

    var body: some View {
        @Bindable var y = yonlendirici
        TabView(selection: $y.sekme) {
            Tab("İndir", systemImage: "arrow.down.circle.fill", value: Yonlendirici.Sekme.indir) { IndirGorunumu() }
                .badge(kuyruk.etkinSayisi)
            Tab("Kütüphane", systemImage: "play.square.stack.fill", value: Yonlendirici.Sekme.kutuphane) { KutuphaneGorunumu() }
            Tab("Ayarlar", systemImage: "gearshape.fill", value: Yonlendirici.Sekme.ayarlar) { AyarlarGorunumu() }
            Tab("Ara", systemImage: "magnifyingglass", value: Yonlendirici.Sekme.ara, role: .search) { AraGorunumu() }
        }
        .sheet(item: $y.bilgi) { BilgiSayfasi(istek: $0) }
        .fullScreenCover(item: $y.oynatilan) { Oynatici(oge: $0) }
        .overlay(alignment: .top) {
            if let metin = yonlendirici.bildirim {
                Label(metin, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: metin) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { yonlendirici.bildirim = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: yonlendirici.bildirim)
    }
}

/// Küçük resim (16:9) ve üstünde süre etiketi.
struct KucukResim: View {
    var adres: String?
    var yerel: URL?
    var sure: Double?
    var genislik: CGFloat = 112

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let yerel, let resim = UIImage(contentsOfFile: yerel.path) {
                    Image(uiImage: resim).resizable().scaledToFill()
                } else if let adres, let url = URL(string: adres) {
                    AsyncImage(url: url) { evre in
                        if let resim = evre.image { resim.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                    }
                } else {
                    Color.secondary.opacity(0.15).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                }
            }
            .frame(width: genislik, height: genislik * 9 / 16)
            .clipShape(.rect(cornerRadius: 8))
            if let sure, sure > 0 {
                Text(BicimSecici.sureMetni(sure))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
    }
}
