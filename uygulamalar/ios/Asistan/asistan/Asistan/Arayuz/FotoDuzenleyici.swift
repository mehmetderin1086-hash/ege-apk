import SwiftUI
import PencilKit

/// Gönderim öncesi fotoğraf düzenleyici: kırp, döndür, üzerine çiz/işaretle.
struct FotoDuzenleyici: View {
    let bitti: (UIImage) -> Void
    @Environment(\.dismiss) private var kapat
    @State private var resim: UIImage
    @State private var kip = Kip.kirp
    @State private var kirpma = CGRect(x: 0, y: 0, width: 1, height: 1)   // görüntüye göre 0…1
    @State private var cizim = PKDrawing()
    @State private var tuvalBoyutu: CGSize = .zero
    /// Açılıştaki (düzleştirilmiş) görüntü: Sıfırla işlenmiş çizimi ve döndürmeyi de geri alır.
    private let ozgun: UIImage

    enum Kip: String, CaseIterable { case kirp = "Kırp", ciz = "Çiz" }

    init(resim: UIImage, bitti: @escaping (UIImage) -> Void) {
        let duz = FotoIslem.duzlestir(resim)
        self.ozgun = duz
        _resim = State(initialValue: duz)
        self.bitti = bitti
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Düzenleme", selection: $kip) {
                    ForEach(Kip.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).padding(.horizontal)
                .accessibilityIdentifier("duzenle-kip")
                .onChange(of: kip) { _, _ in cizimiIsle() }
                GeometryReader { g in
                    let boyut = FotoIslem.sigdir(resim.size, g.size)
                    ZStack {
                        Image(uiImage: resim).resizable().frame(width: boyut.width, height: boyut.height)
                        if kip == .ciz {
                            CizimTuvali(cizim: $cizim).frame(width: boyut.width, height: boyut.height)
                                .accessibilityIdentifier("cizim-tuvali")
                        } else {
                            KirpmaCercevesi(oran: $kirpma, boyut: boyut)
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                    .onAppear { tuvalBoyutu = boyut }
                    .onChange(of: boyut) { _, y in tuvalBoyutu = y }
                }
                .padding(.horizontal)
                HStack(spacing: 24) {
                    Button { cizimiIsle(); resim = FotoIslem.dondur(resim); kirpma = CGRect(x: 0, y: 0, width: 1, height: 1) } label: {
                        Label("Döndür", systemImage: "rotate.right").frame(minWidth: 44, minHeight: 44)
                    }
                    Button { resim = ozgun; kirpma = CGRect(x: 0, y: 0, width: 1, height: 1); cizim = PKDrawing() } label: {
                        Label("Sıfırla", systemImage: "arrow.uturn.backward").frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Düzenle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") {
                        cizimiIsle()
                        bitti(FotoIslem.kirp(resim, kirpma))
                        kapat()
                    }
                    .accessibilityIdentifier("duzenle-bitti")
                }
            }
        }
    }

    /// Çizimi görüntüye işler ve tuvali boşaltır (kırpma/döndürme çizimi de kapsasın diye).
    private func cizimiIsle() {
        guard !cizim.strokes.isEmpty, tuvalBoyutu.width > 0 else { return }
        resim = FotoIslem.cizimEkle(resim, cizim, tuval: tuvalBoyutu)
        cizim = PKDrawing()
    }
}

/// Saf görüntü işlemleri (birim test edilir).
enum FotoIslem {
    static func bicim() -> UIGraphicsImageRendererFormat { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }

    /// Yönlendirmeyi piksele işler (`.up`), böylece kırpma dikdörtgeni doğru yere düşer.
    static func duzlestir(_ r: UIImage) -> UIImage {
        guard r.imageOrientation != .up || r.scale != 1 else { return r }
        let boyut = CGSize(width: r.size.width * r.scale, height: r.size.height * r.scale)
        return UIGraphicsImageRenderer(size: boyut, format: bicim()).image { _ in r.draw(in: CGRect(origin: .zero, size: boyut)) }
    }

    static func sigdir(_ resim: CGSize, _ alan: CGSize) -> CGSize {
        guard resim.width > 0, resim.height > 0, alan.width > 0, alan.height > 0 else { return .zero }
        let o = min(alan.width / resim.width, alan.height / resim.height)
        return CGSize(width: resim.width * o, height: resim.height * o)
    }

    /// Saat yönünde 90°.
    static func dondur(_ r: UIImage) -> UIImage {
        let yeni = CGSize(width: r.size.height, height: r.size.width)
        return UIGraphicsImageRenderer(size: yeni, format: bicim()).image { c in
            c.cgContext.translateBy(x: yeni.width / 2, y: yeni.height / 2)
            c.cgContext.rotate(by: .pi / 2)
            r.draw(in: CGRect(x: -r.size.width / 2, y: -r.size.height / 2, width: r.size.width, height: r.size.height))
        }
    }

    /// `oran` 0…1 aralığında; tam çerçeve ise görüntü aynen döner.
    static func kirp(_ r: UIImage, _ oran: CGRect) -> UIImage {
        let o = oran.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !o.isNull, o.width > 0.01, o.height > 0.01, o != CGRect(x: 0, y: 0, width: 1, height: 1),
              let cg = duzlestir(r).cgImage else { return r }
        let piksel = CGRect(x: o.minX * CGFloat(cg.width), y: o.minY * CGFloat(cg.height),
                            width: o.width * CGFloat(cg.width), height: o.height * CGFloat(cg.height)).integral
        guard let k = cg.cropping(to: piksel) else { return r }
        return UIImage(cgImage: k)
    }

    /// Kırpma köşesini (0 sol üst, 1 sağ üst, 2 sol alt, 3 sağ alt) oransal öteleme kadar taşır; 0…1 ve `enAz` sınırı korunur.
    nonisolated static func koseTasi(_ b: CGRect, kose: Int, dx: CGFloat, dy: CGFloat, enAz: CGFloat) -> CGRect {
        var x0 = b.minX, y0 = b.minY, x1 = b.maxX, y1 = b.maxY
        if kose % 2 == 0 { x0 = min(max(0, b.minX + dx), x1 - enAz) } else { x1 = max(min(1, b.maxX + dx), x0 + enAz) }
        if kose < 2 { y0 = min(max(0, b.minY + dy), y1 - enAz) } else { y1 = max(min(1, b.maxY + dy), y0 + enAz) }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// VoiceOver ayarı: artı adım köşeyi içeri (daha çok kırp), eksi adım dışarı taşır.
    nonisolated static func koseAdimi(_ b: CGRect, kose: Int, adim: CGFloat, enAz: CGFloat) -> CGRect {
        koseTasi(b, kose: kose, dx: kose % 2 == 0 ? adim : -adim, dy: kose < 2 ? adim : -adim, enAz: enAz)
    }

    nonisolated static let koseAdlari = ["Sol üst", "Sağ üst", "Sol alt", "Sağ alt"]

    /// Köşenin VoiceOver değeri: hangi köşe ve görüntünün yüzde kaçı kırpıldı.
    nonisolated static func koseDegeri(_ kose: Int, _ oran: CGRect) -> String {
        let ad = (0..<koseAdlari.count).contains(kose) ? koseAdlari[kose] : "Köşe"
        let kirpilan = Int(((1 - oran.width * oran.height) * 100).rounded())
        return "\(ad), yüzde \(max(0, min(100, kirpilan))) kırpıldı"
    }

    static func cizimEkle(_ r: UIImage, _ cizim: PKDrawing, tuval: CGSize) -> UIImage {
        let olcek = r.size.width / tuval.width
        let katman = cizim.image(from: CGRect(origin: .zero, size: tuval), scale: olcek)
        return UIGraphicsImageRenderer(size: r.size, format: bicim()).image { _ in
            r.draw(in: CGRect(origin: .zero, size: r.size))
            katman.draw(in: CGRect(origin: .zero, size: r.size))
        }
    }
}

/// Dört köşe tutamaklı kırpma çerçevesi.
private struct KirpmaCercevesi: View {
    @Binding var oran: CGRect
    let boyut: CGSize
    @State private var baslangic: CGRect?
    @GestureState private var surukleniyor = false   // hareket iptal edilse de sıfırlanır
    private let enAz: CGFloat = 0.08

    var body: some View {
        let r = CGRect(x: oran.minX * boyut.width, y: oran.minY * boyut.height, width: oran.width * boyut.width, height: oran.height * boyut.height)
        ZStack(alignment: .topLeading) {
            Path { p in p.addRect(CGRect(origin: .zero, size: boyut)); p.addRect(r) }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Rectangle().stroke(Color.white, lineWidth: 2).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
            ForEach(0..<4, id: \.self) { kose in
                let nokta = CGPoint(x: kose % 2 == 0 ? r.minX : r.maxX, y: kose < 2 ? r.minY : r.maxY)
                Circle().fill(Color.white).frame(width: 22, height: 22).shadow(radius: 2)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .position(nokta)
                    .gesture(DragGesture(minimumDistance: 0).updating($surukleniyor) { _, s, _ in s = true }
                        .onChanged { d in tasi(kose, d.translation) })
                    .accessibilityLabel("Kırpma köşesi")
                    .accessibilityValue(FotoIslem.koseDegeri(kose, oran))
                    .accessibilityAdjustableAction { yon in
                        switch yon {
                        case .increment: oran = FotoIslem.koseAdimi(oran, kose: kose, adim: 0.05, enAz: enAz)
                        case .decrement: oran = FotoIslem.koseAdimi(oran, kose: kose, adim: -0.05, enAz: enAz)
                        @unknown default: break
                        }
                    }
            }
        }
        .frame(width: boyut.width, height: boyut.height)
        .onChange(of: surukleniyor) { _, yeni in if !yeni { baslangic = nil } }
    }

    private func tasi(_ kose: Int, _ t: CGSize) {
        if baslangic == nil { baslangic = oran }
        guard let b = baslangic, boyut.width > 0, boyut.height > 0 else { return }
        oran = FotoIslem.koseTasi(b, kose: kose, dx: t.width / boyut.width, dy: t.height / boyut.height, enAz: enAz)
    }
}

/// PencilKit tuvali + araç paleti (parmakla çizim açık).
private struct CizimTuvali: UIViewRepresentable {
    @Binding var cizim: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.backgroundColor = .clear; v.isOpaque = false
        v.drawingPolicy = .anyInput
        v.tool = PKInkingTool(.marker, color: .systemRed, width: 8)
        v.drawing = cizim
        v.delegate = context.coordinator
        context.coordinator.palet.addObserver(v)
        context.coordinator.palet.setVisible(true, forFirstResponder: v)
        DispatchQueue.main.async { v.becomeFirstResponder() }
        return v
    }
    func updateUIView(_ v: PKCanvasView, context: Context) { if v.drawing != cizim { v.drawing = cizim } }
    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, PKCanvasViewDelegate {
        let ana: CizimTuvali
        let palet = PKToolPicker()
        init(_ ana: CizimTuvali) { self.ana = ana }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { ana.cizim = canvasView.drawing }
    }
}
