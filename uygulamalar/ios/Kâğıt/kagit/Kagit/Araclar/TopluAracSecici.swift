import KagitKit
import SwiftUI

/// Seçili PDF'lere aynı aracı toplu uygulamak için araç seçici.
struct TopluAracSecici: View {
    let girdiler: [URL]
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var arama = ""

    private var araclar: [Arac] {
        let hepsi = AracKatalogu.topluAraclar
        guard !arama.isEmpty else { return hepsi }
        let k = TurkceMetin.kucuk(arama)
        return hepsi.filter { TurkceMetin.kucuk("\($0.ad) \($0.aciklama)").contains(k) }
    }

    var body: some View {
        List {
            Section {
                ForEach(araclar) { a in
                    Button { ac(a) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: a.simge)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Tema.renk(a.kategori).gradient, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(a.ad).foregroundStyle(.primary)
                                Text(a.aciklama).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("\(girdiler.count) PDF'e uygula")
            } footer: {
                Text("Seçilen araç her dosyaya aynı ayarlarla uygulanır; sonuçlar kitaplığa kaydedilir.")
            }
        }
        .searchable(text: $arama, prompt: "Araç ara")
        .overlay { if girdiler.isEmpty { ContentUnavailableView("PDF seçilmedi", systemImage: "doc") } }
        .navigationTitle("Toplu işlem")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
        }
    }

    private func ac(_ a: Arac) {
        let urller = girdiler
        kapat()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            yon.aracAc(a, girdiler: urller)
        }
    }
}
