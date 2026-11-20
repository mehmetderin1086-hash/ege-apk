import KagitKit
import PDFKit
import SwiftUI

/// PDF sayfasının (ya da bir bölgesinin) küçük resmi. Belgeyi kendi arka plan görevinde açar.
struct SayfaResmi: View {
    let url: URL
    let sayfa: Int
    /// Kırpma kutusuna göre bölge (sol alt köken); nil ise tüm sayfa.
    var bolge: CGRect?
    var dpi: CGFloat = 40
    var yukseklik: CGFloat = 72
    @State private var resim: UIImage?

    var body: some View {
        Group {
            if let resim {
                Image(uiImage: resim).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color(.secondarySystemBackground)).overlay(ProgressView().controlSize(.small))
                    .aspectRatio(0.72, contentMode: .fit)
            }
        }
        .frame(maxHeight: yukseklik)
        .background(.white)
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
        .task(id: "\(url.path)-\(sayfa)-\(bolge.map { "\($0)" } ?? "")-\(dpi)") {
            let u = url, s = sayfa, b = bolge, d = dpi
            resim = await Task.detached { Self.uret(u, s, b, d) }.value
        }
    }

    nonisolated static func uret(_ url: URL, _ sayfa: Int, _ bolge: CGRect?, _ dpi: CGFloat) -> UIImage? {
        guard let belge = PDFDocument(url: url), let p = belge.page(at: sayfa),
              var g = PDFCizim.goruntu(p, dpi: dpi) else { return nil }
        if let b = bolge {
            let boyut = p.bounds(for: .cropBox).size
            let o = dpi / 72
            let kirp = CGRect(x: b.minX * o, y: (boyut.height - b.maxY) * o, width: b.width * o, height: b.height * o)
                .intersection(CGRect(x: 0, y: 0, width: g.width, height: g.height))
            guard !kirp.isEmpty, let k = g.cropping(to: kirp.integral) else { return nil }
            g = k
        }
        return UIImage(cgImage: g)
    }
}

/// Araç ekranlarında tek PDF girdisi: geleni gösterir, yoksa seçtirir.
struct TekPDFSecimi: View {
    @Binding var url: URL?
    @State private var sec = false

    var body: some View {
        Section("PDF") {
            if let url { GirdiSatiri(url: url) }
            Button { sec = true } label: { Label(url == nil ? "Dosya seç" : "Başka dosya seç", systemImage: "doc.badge.plus") }
        }
        .kaynakSecici(isPresented: $sec, girdi: .tekPDF) { url = $0.first }
    }
}

/// Uzun işlerde ortada ilerleme katmanı.
extension View {
    func calisiyorKatmani(_ metin: String?, oran: Double? = nil) -> some View {
        overlay { if let metin { CalisiyorKatmani(metin: metin, oran: oran) } }
    }
}

/// Bir araç ekranını kapatıp ardından belgeyi açmak için ortak yardımcı.
@MainActor
func belgeyiAc(_ yon: Yonlendirici, _ oge: KitaplikOgesi, kip: BelgeKipi = .oku) {
    yon.acikArac = nil
    Task {
        try? await Task.sleep(for: .milliseconds(450))
        yon.ac(oge, kip: kip)
    }
}
