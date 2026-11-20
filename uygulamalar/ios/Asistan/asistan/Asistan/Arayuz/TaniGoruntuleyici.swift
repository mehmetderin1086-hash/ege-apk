import SwiftUI

/// tani.log'un bir satırı: `<zaman> <B|U|H> [r=xxxxxx] <olay>`. Eski (v1) satırlarda seviye öneki yoktur; olaydan tahmin edilir.
nonisolated struct TaniSatiri: Identifiable, Equatable, Sendable {
    let id: Int
    let metin: String
    let seviye: TaniGunlugu.Seviye
    let istek: String?

    static func coz(_ satir: String, sira: Int) -> TaniSatiri {
        let parcalar = satir.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        var seviye: TaniGunlugu.Seviye?
        var istek: String?
        var olayBasi = 1
        if parcalar.count > 1, let s = TaniGunlugu.Seviye(rawValue: parcalar[1]) { seviye = s; olayBasi = 2 }
        if seviye != nil, parcalar.count > 2, parcalar[2].hasPrefix("[r="), parcalar[2].hasSuffix("]") {
            istek = String(parcalar[2].dropFirst(3).dropLast())
            olayBasi = 3
        }
        let olay = parcalar.dropFirst(olayBasi).joined(separator: " ")
        return TaniSatiri(id: sira, metin: satir, seviye: seviye ?? TaniGunlugu.tahmin(olay), istek: istek)
    }
}

/// Sağlık → Tanı günlüğü → "Günlüğü göster": son 1000 satır (tani.1.log + tani.log), en yenisi üstte.
/// Seviye süzgeci, arama ve `r=` kimliğine dokununca o isteğin satırları.
struct TaniGoruntuleyici: View {
    enum Suzgec: String, CaseIterable, Identifiable {
        case tumu = "Tümü", uyariHata = "Uyarı+Hata", hata = "Hata"
        var id: Self { self }
    }

    @State private var satirlar: [TaniSatiri] = []
    @State private var suzgec: Suzgec = .tumu
    @State private var arama = ""
    @State private var kimlik: String?
    @State private var yukleniyor = false

    private var gorunen: [TaniSatiri] {
        satirlar.filter { s in
            switch suzgec {
            case .tumu: break
            case .uyariHata: if s.seviye == .bilgi { return false }
            case .hata: if s.seviye != .hata { return false }
            }
            if let kimlik, s.istek != kimlik { return false }
            return arama.isEmpty || s.metin.localizedCaseInsensitiveContains(arama)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Seviye", selection: $suzgec) {
                    ForEach(Suzgec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("tani-seviye-suzgeci")
                if let kimlik {
                    HStack {
                        Text("Yalnız istek r=\(kimlik)").font(.footnote.monospaced())
                        Spacer()
                        Button("Kaldır") { self.kimlik = nil }
                    }
                }
            } footer: {
                Text("Bir isteğin bütün satırlarını görmek için satırına dokun. Uzun basarak metni seçebilirsin.")
            }
            Section(gorunen.isEmpty ? (yukleniyor ? "Yükleniyor…" : "Satır yok") : "\(gorunen.count) satır") {
                ForEach(gorunen) { s in
                    Text(s.metin)
                        .font(.caption.monospaced())
                        .foregroundStyle(renk(s.seviye))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { if let r = s.istek { kimlik = r } }
                }
            }
        }
        .accessibilityIdentifier("tani-goruntuleyici")
        .navigationTitle("Tanı günlüğü")
        .searchable(text: $arama, prompt: "Günlükte ara")
        .toolbar {
            Button("Yenile") { Task { await yukle() } }
                .disabled(yukleniyor)
                .accessibilityIdentifier("tani-yenile")
        }
        .task { await yukle() }
    }

    private func yukle() async {
        yukleniyor = true
        defer { yukleniyor = false }
        // Dosya okuma ve çözümleme ana iş parçacığı dışında.
        satirlar = await Task.detached(priority: .userInitiated) {
            TaniGunlugu.sonSatirlar(1000).reversed().enumerated().map { TaniSatiri.coz($0.element, sira: $0.offset) }
        }.value
    }

    private func renk(_ s: TaniGunlugu.Seviye) -> Color {
        switch s { case .bilgi: .primary; case .uyari: .orange; case .hata: .red }
    }
}
