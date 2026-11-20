import SwiftUI
import Observation

/// Onay bekleyen/çelişen olgu sayısı değişince artan sayaç: sohbet ekranındaki çip ve Hafıza ekranı yeniden okur.
/// (Çıkarıcı arka planda yazar; SwiftData sorgusunu her çizimde yapmamak için tek bir gözlenen değer.)
@MainActor
@Observable
final class OlguOnayIzleyici {
    static let ortak = OlguOnayIzleyici()
    private(set) var surum = 0
    func degisti() { surum &+= 1 }
}

/// Giriş çubuğunun hemen üstündeki tek satırlık onay çipi: çıkarımla gelen hassas olgu ("Hatırlayayım mı") ya da kullanıcının
/// verdiği bilgiyle çelişen yeni değer ("Önceki bilgiyle çelişiyor"). Bekleyen yoksa hiç yer kaplamaz.
@MainActor
struct OlguOnayCipi: View {
    let depo: HafizaDeposu
    @State private var olgu: Olgu?
    @State private var eski: Olgu?
    private var izleyici: OlguOnayIzleyici { .ortak }

    var body: some View {
        // Boş Group'ta (EmptyView) .task tetiklenmeyebilir: sıfır yükseklikli çapa hep görünür.
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).accessibilityHidden(true)
            if let o = olgu {
                HStack(spacing: 8) {
                    Image(systemName: o.durum == OlguDurumu.celiski ? "exclamationmark.arrow.triangle.2.circlepath" : "brain.head.profile")
                        .foregroundStyle(.secondary)
                    Text(Self.metin(o, eski: eski))
                        .font(.footnote).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button(o.durum == OlguDurumu.celiski ? "Yenisi doğru" : "Evet") { evet(o) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityIdentifier("olgu-onay-evet")
                    Button(o.durum == OlguDurumu.celiski ? "Eskisi doğru" : "Hayır") { hayir(o) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("olgu-onay-hayir")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("olgu-onay-cipi")
            }
        }
        .task(id: izleyici.surum) { yenile() }
    }

    private func yenile() {
        let ilk = depo.bekleyenOlgular().first
        olgu = ilk
        eski = ilk.flatMap { $0.durum == OlguDurumu.celiski ? depo.celiskiAdayi($0) : nil }
    }

    private func evet(_ o: Olgu) {
        if o.durum == OlguDurumu.celiski { depo.celiskiCoz(yeni: o.kimlik, eski: eski?.kimlik, yeniDogru: true) }
        else { depo.olguOnayla(o.kimlik) }
        yenile()
    }

    private func hayir(_ o: Olgu) {
        if o.durum == OlguDurumu.celiski { depo.celiskiCoz(yeni: o.kimlik, eski: eski?.kimlik, yeniDogru: false) }
        else { depo.olguReddet(o.kimlik) }
        yenile()
    }

    /// Çip metni: bekleyen olguda soru, çelişkide yeni değer (eskisi biliniyorsa yanında).
    static func metin(_ o: Olgu, eski: Olgu?) -> String {
        metin(yeni: o.metin, celiski: o.durum == OlguDurumu.celiski, eski: eski?.metin)
    }

    nonisolated static func metin(yeni: String, celiski: Bool, eski: String?) -> String {
        guard celiski else { return "Hatırlayayım mı: \(yeni)" }
        return "Önceki bilgiyle çelişiyor: \(yeni)" + (eski.map { " (önceki: \($0))" } ?? "")
    }
}
