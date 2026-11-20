import SwiftUI

/// Araçlar sekmesi: kategorilere ayrılmış araç ızgarası (iLovePDF düzeni) + arama.
struct AraclarGorunumu: View {
    @Environment(Yonlendirici.self) private var yon
    @State private var arama = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(AracKategorisi.allCases) { k in
                        let araclar = suz(AracKatalogu.kategoride(k))
                        if !araclar.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(k.ad).font(.headline).padding(.horizontal)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                                    ForEach(araclar) { a in
                                        Button { yon.aracAc(a) } label: { AracKutusu(arac: a) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .searchable(text: $arama, prompt: "Araç ara")
            .navigationTitle("Araçlar")
        }
    }

    private func suz(_ a: [Arac]) -> [Arac] {
        guard !arama.isEmpty else { return a }
        let k = arama.lowercased(with: Locale(identifier: "tr_TR"))
        return a.filter { "\($0.ad) \($0.aciklama)".lowercased(with: Locale(identifier: "tr_TR")).contains(k) }
    }
}

/// Izgaradaki tek araç kutusu.
struct AracKutusu: View {
    let arac: Arac

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: arac.simge)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Tema.renk(arac.kategori).gradient, in: RoundedRectangle(cornerRadius: 12))
            Text(arac.ad)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12).padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
