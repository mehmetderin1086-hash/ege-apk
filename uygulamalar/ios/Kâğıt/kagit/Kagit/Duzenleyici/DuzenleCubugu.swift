import KagitKit
import PDFKit
import SwiftUI

/// Düzenle kipi: PDFium ile gerçek metin düzenleme, metin ekleme, örtü, bağlantı ve görsel.
struct DuzenleCubugu: View {
    let oturum: BelgeOturumu

    var body: some View {
        @Bindable var d = oturum.duzenleyici
        VStack(spacing: 0) {
            if let y = d.yerlestirme { YerlestirmeBandi(yerlestirme: y) { d.yerlestirme = nil } }
            if d.secili != nil { SecimEylemleri(durum: d) }
            ipucu(d)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(DuzenleAraci.allCases) { a in
                        Button { sec(a, d) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: a.simge).font(.system(size: 18))
                                Text(a.ad).font(.caption2).lineLimit(1)
                            }
                            .frame(minWidth: 74)
                            .padding(.vertical, 5).padding(.horizontal, 3)
                            .foregroundStyle(d.duzenleAraci == a ? Tema.vurgu : .secondary)
                            .background(d.duzenleAraci == a ? Tema.vurgu.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
        }
        .onAppear { d.kipAcildi() }
        .onDisappear { d.kipKapandi() }
        .duzenleyiciSayfalari(d)
        .kaynakSecici(isPresented: $d.duzenleGorselSeciciAcik, girdi: .gorseller) { urller in
            guard let u = urller.first else { return }
            d.yerlestirme = Yerlestirme(ad: "Görsel (içerik olarak)") { sayfa, p in d.pdfiumGorselEkle(u, sayfa: sayfa, merkez: p) }
        }
    }

    private func sec(_ a: DuzenleAraci, _ d: DuzenleyiciDurumu) {
        d.yerlestirme = nil
        d.duzenleAraci = a
        d.dokunusuKur()
        if a == .gorsel { d.duzenleGorselSeciciAcik = true }
    }

    @ViewBuilder private func ipucu(_ d: DuzenleyiciDurumu) -> some View {
        let metin: String? = switch d.duzenleAraci {
        case .metniDuzenle: "Düzenlemek istediğiniz metin satırına dokunun."
        case .metinEkle: "Metni eklemek istediğiniz yere dokunun."
        case .ortu: "Örtülecek alanı parmağınızla sürükleyerek seçin. Kaydederken sayfa içeriğine işlenir."
        case .baglanti: "Bağlantı alanını sürükleyerek seçin."
        case .gorsel: nil
        }
        if let metin, d.yerlestirme == nil, d.secili == nil {
            Text(metin).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 6)
        }
    }
}
