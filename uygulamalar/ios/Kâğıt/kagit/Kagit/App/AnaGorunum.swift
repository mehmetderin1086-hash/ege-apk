import KagitKit
import SwiftUI

/// Kök görünüm: sekmeler + tam ekran belge/araç/tarayıcı sunumları.
struct AnaGorunum: View {
    @Environment(Yonlendirici.self) private var yon
    @Environment(Kitaplik.self) private var kitaplik

    var body: some View {
        @Bindable var yon = yon
        TabView(selection: $yon.sekme) {
            Tab("Ana Sayfa", systemImage: "house", value: .anaSayfa) {
                AnaSayfa()
            }
            Tab("Dosyalar", systemImage: "folder", value: .dosyalar) {
                DosyalarGorunumu()
            }
            Tab("Araçlar", systemImage: "square.grid.2x2", value: .araclar) {
                AraclarGorunumu()
            }
            Tab("Öğretmen", systemImage: "graduationcap", value: .ogretmen) {
                OgretmenMerkezi()
            }
            Tab("Ayarlar", systemImage: "gearshape", value: .ayarlar) {
                AyarlarGorunumu()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(item: $yon.acikBelge) { oge in
            BelgeEkrani(oge: oge, acilisKipi: yon.acilisKipi)
        }
        .sheet(item: $yon.acikArac) { istek in
            NavigationStack {
                istek.arac.ekran(AracBaglami(girdiler: istek.girdiler))
            }
        }
        .fullScreenCover(isPresented: $yon.taramaAcik) {
            TaramaEkrani()
        }
        .iletiGoster($yon.ileti)
    }
}

/// Uygulama renkleri.
enum Tema {
    static let vurgu = Color(red: 0.86, green: 0.24, blue: 0.20)
    static let kagit = Color(red: 0.98, green: 0.97, blue: 0.94)

    static func renk(_ kategori: AracKategorisi) -> Color {
        switch kategori {
        case .duzenle: .orange
        case .sayfa: .blue
        case .donustur: .green
        case .guvenlik: .red
        case .tarama: .teal
        case .ogretmen: .purple
        case .yapay: .indigo
        }
    }
}
