import KagitKit
import SwiftUI

/// Elle köşe sürükleyerek kırpma + otomatik köşe algılama. Uygulanınca perspektif düzeltilir.
struct KirpmaGorunumu: View {
    let model: TaramaModeli
    let sayfaID: UUID
    @Environment(\.dismiss) private var kapat

    @State private var dortgen = Dortgen.tam
    @State private var kaynak: CGImage?
    @State private var araniyor = false
    @State private var ileti: Ileti?

    private enum Kose: CaseIterable { case ustSol, ustSag, altSag, altSol }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if let kaynak {
                    let alan = sigdir(CGSize(width: kaynak.width, height: kaynak.height), geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: kaynak, scale: 1)
                            .resizable()
                            .frame(width: alan.width, height: alan.height)
                            .offset(x: alan.minX, y: alan.minY)
                        cokgen(alan)
                            .fill((dortgen.gecerli ? Tema.vurgu : Color.orange).opacity(0.18))
                        cokgen(alan)
                            .stroke(dortgen.gecerli ? Tema.vurgu : Color.orange, lineWidth: 2)
                        ForEach(Kose.allCases, id: \.self) { k in tutamac(k, alan: alan) }
                    }
                    .coordinateSpace(name: "kirp")
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Kırp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        model.guncelle(sayfaID) { $0.dortgen = dortgen }
                        kapat()
                    }
                    .disabled(!dortgen.gecerli)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { otomatik() } label: {
                        if araniyor { ProgressView() } else { Label("Otomatik", systemImage: "wand.and.stars") }
                    }
                    .disabled(araniyor)
                    Spacer()
                    Button { dortgen = .tam } label: { Label("Tüm sayfa", systemImage: "rectangle.dashed") }
                }
            }
            .iletiGoster($ileti)
        }
        .task {
            guard let s = model.sayfalar.first(where: { $0.id == sayfaID }) else { return }
            dortgen = s.dortgen
            let k = s.kucuk, d = s.dondurme
            kaynak = await Task.detached { TaramaIslemleri.dondur(k, derece: d) }.value
        }
    }

    // MARK: - Geometri

    private func sigdir(_ resim: CGSize, _ kutu: CGSize) -> CGRect {
        guard resim.width > 0, resim.height > 0, kutu.width > 0, kutu.height > 0 else { return .zero }
        let pad: CGFloat = 24
        let o = min((kutu.width - pad * 2) / resim.width, (kutu.height - pad * 2) / resim.height)
        let g = resim.width * o, y = resim.height * o
        return CGRect(x: (kutu.width - g) / 2, y: (kutu.height - y) / 2, width: g, height: y)
    }

    private func nokta(_ p: CGPoint, _ alan: CGRect) -> CGPoint {
        CGPoint(x: alan.minX + p.x * alan.width, y: alan.minY + p.y * alan.height)
    }

    private func cokgen(_ alan: CGRect) -> Path {
        Path { yol in
            let n = dortgen.koseler.map { nokta($0, alan) }
            yol.move(to: n[0])
            for p in n.dropFirst() { yol.addLine(to: p) }
            yol.closeSubpath()
        }
    }

    private func deger(_ k: Kose) -> CGPoint {
        switch k {
        case .ustSol: dortgen.ustSol
        case .ustSag: dortgen.ustSag
        case .altSag: dortgen.altSag
        case .altSol: dortgen.altSol
        }
    }

    private func ata(_ k: Kose, _ p: CGPoint) {
        switch k {
        case .ustSol: dortgen.ustSol = p
        case .ustSag: dortgen.ustSag = p
        case .altSag: dortgen.altSag = p
        case .altSol: dortgen.altSol = p
        }
    }

    private func tutamac(_ k: Kose, alan: CGRect) -> some View {
        let n = nokta(deger(k), alan)
        return Circle()
            .fill(Color.white.opacity(0.9))
            .overlay(Circle().stroke(Tema.vurgu, lineWidth: 3))
            .frame(width: 26, height: 26)
            .contentShape(Circle().inset(by: -14))
            .position(n)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("kirp"))
                    .onChanged { v in
                        guard alan.width > 0, alan.height > 0 else { return }
                        let x = min(max((v.location.x - alan.minX) / alan.width, 0), 1)
                        let y = min(max((v.location.y - alan.minY) / alan.height, 0), 1)
                        ata(k, CGPoint(x: x, y: y))
                    }
            )
            .accessibilityLabel("Kırpma köşesi")
    }

    private func otomatik() {
        guard let kaynak else { return }
        araniyor = true
        Task {
            let d = await TaramaIslemleri.kenarlariBul(kaynak)
            araniyor = false
            if let d { dortgen = d } else {
                ileti = Ileti(baslik: "Köşeler bulunamadı", metin: "Belge kenarı algılanamadı. Köşeleri elle sürükleyin.", hata: false)
            }
        }
    }
}
