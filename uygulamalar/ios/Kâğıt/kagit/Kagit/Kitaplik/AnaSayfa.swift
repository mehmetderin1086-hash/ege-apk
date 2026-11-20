import SwiftUI

/// Ana sayfa: hızlı eylemler, son belgeler, yıldızlılar, öğretmen kısayolları.
struct AnaSayfa: View {
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @State private var dosyaSec = false

    private let hizliAraclar = ["birlestir", "sikistir", "gorseldenPDF", "ocr", "imzala", "pdftenWord", "filigran", "yiginiBol"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hizliEylemler
                    let son = kitaplik.sonAcilanlar()
                    if !son.isEmpty {
                        bolum("Son belgeler") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(son) { o in
                                        Button { ac(o) } label: { IzgaraHucresi(oge: o, secili: nil).frame(width: 96) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    let araclar = hizliAraclar.compactMap(AracKatalogu.bul)
                    if !araclar.isEmpty {
                        bolum("Sık kullanılan araçlar") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                                ForEach(araclar) { a in
                                    Button { yon.aracAc(a) } label: { AracKutusu(arac: a) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    let yildiz = kitaplik.yildizlilar
                    if !yildiz.isEmpty {
                        bolum("Yıldızlılar") {
                            VStack(spacing: 0) {
                                ForEach(yildiz.prefix(6)) { o in
                                    Button { ac(o) } label: { SatirHucresi(oge: o, secili: nil).padding(.vertical, 6) }
                                        .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    if kitaplik.belgeler.isEmpty {
                        BosKitaplik(dosyaSec: $dosyaSec).padding(.top, 20)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Kâğıt")
            .refreshable { await kitaplik.tara() }
            .fileImporter(isPresented: $dosyaSec, allowedContentTypes: [.item], allowsMultipleSelection: true) { s in
                if case .success(let u) = s { Task { _ = try? await kitaplik.iceAktar(u) } }
            }
        }
    }

    private var hizliEylemler: some View {
        HStack(spacing: 12) {
            buyukEylem("Tara", "doc.viewfinder", .teal) { yon.taramaAcik = true }
            buyukEylem("İçe aktar", "square.and.arrow.down", .blue) { dosyaSec = true }
            buyukEylem("Araçlar", "square.grid.2x2", .orange) { yon.sekme = .araclar }
        }
        .padding(.horizontal)
    }

    private func buyukEylem(_ ad: String, _ simge: String, _ renk: Color, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            VStack(spacing: 8) {
                Image(systemName: simge).font(.title2)
                Text(ad).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(renk.gradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func bolum(_ baslik: String, @ViewBuilder _ icerik: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(baslik).font(.title3.bold()).padding(.horizontal)
            icerik()
        }
    }

    private func ac(_ o: KitaplikOgesi) {
        if o.pdfMi { yon.ac(o) } else { yon.sekme = .dosyalar }
    }
}
