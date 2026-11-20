import KagitKit
import PDFKit
import PencilKit
import SwiftUI

/// Doldur & İmzala kipi: form alanları, imza, baş harf, tarih, ad, işaretler, serbest metin, alan oluşturma.
struct ImzalaCubugu: View {
    let oturum: BelgeOturumu
    @State private var imzalar = ImzaDeposu.paylasilan

    var body: some View {
        @Bindable var d = oturum.duzenleyici
        VStack(spacing: 0) {
            if let y = d.yerlestirme { YerlestirmeBandi(yerlestirme: y) { d.yerlestirme = nil } }
            if d.secili != nil { SecimEylemleri(durum: d) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    dugme("Alanları vurgula", d.alanlariVurgula ? "checklist.checked" : "checklist", etkin: d.alanlariVurgula) {
                        d.alanlariVurgula.toggle()
                    }
                    dugme("Sonraki alan", "arrow.down.to.line") { d.sonrakiAlan() }
                    imzaMenusu(d, baslik: "İmza", simge: "signature", liste: imzalar.tamImzalar, basHarf: false)
                    imzaMenusu(d, baslik: "Baş harf", simge: "textformat.abc", liste: imzalar.basHarfler, basHarf: true)
                    dugme("Tarih", "calendar") {
                        d.damgaYerlestirmeyiBaslat(DamgaTanimi(metin: tarihMetni(), renk: .siyah, cerceve: false), ad: "Tarih")
                    }
                    dugme("Ad", "person.text.rectangle") { adYerlestir(d) }
                    ForEach(["✓", "✗", "●"], id: \.self) { s in
                        dugme(s, nil, metin: s) {
                            d.damgaYerlestirmeyiBaslat(DamgaTanimi(metin: s, renk: .siyah, cerceve: false),
                                                       ad: "İşaret \(s)", tekSefer: false)
                        }
                    }
                    dugme("Metin", "textformat") {
                        d.yerlestirme = Yerlestirme(ad: "Metin") { s, p in d.istek = .kutuEkle(s, p) }
                    }
                    Menu {
                        ForEach(DuzenleyiciDurumu.AlanTuru.allCases) { t in
                            Button { d.alanYerlestirmeyiBaslat(t) } label: { Label(t.ad, systemImage: t.simge) }
                        }
                    } label: { etiket("Alan ekle", "rectangle.badge.plus", etkin: false) }
                    dugme("Liste", "list.bullet.rectangle") { d.aciklamaListesiAcik = true }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
        }
        .onAppear { d.kipAcildi() }
        .onDisappear { d.kipKapandi() }
        .duzenleyiciSayfalari(d)
        .sheet(isPresented: $d.imzaCizimAcik) { ImzaCizimSayfasi() }
    }

    private func imzaMenusu(_ d: DuzenleyiciDurumu, baslik: String, simge: String, liste: [KayitliImza], basHarf: Bool) -> some View {
        Menu {
            ForEach(liste) { i in
                Button {
                    if let t = imzalar.damga(i) {
                        d.damgaYerlestirmeyiBaslat(t, ad: i.ad)
                    }
                } label: { Label(i.ad, systemImage: simge) }
            }
            Button { d.imzaCizimAcik = true } label: { Label(basHarf ? "Yeni baş harf çiz" : "Yeni imza çiz", systemImage: "plus") }
        } label: { etiket(baslik, simge, etkin: false) }
    }

    private func dugme(_ ad: String, _ simge: String?, metin: String? = nil, etkin: Bool = false, eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) { etiket(ad, simge, metin: metin, etkin: etkin) }.buttonStyle(.plain)
    }

    private func etiket(_ ad: String, _ simge: String?, metin: String? = nil, etkin: Bool) -> some View {
        VStack(spacing: 2) {
            if let simge { Image(systemName: simge).font(.system(size: 18)) }
            else if let metin { Text(metin).font(.system(size: 20, weight: .semibold)).frame(height: 22) }
            Text(ad).font(.caption2).lineLimit(1)
        }
        .frame(minWidth: 58)
        .padding(.vertical, 5).padding(.horizontal, 3)
        .foregroundStyle(etkin ? Tema.vurgu : .secondary)
        .background(etkin ? Tema.vurgu.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }

    private func tarihMetni() -> String {
        let b = DateFormatter()
        b.locale = Locale(identifier: "tr_TR")
        b.dateFormat = "d.MM.yyyy"
        return b.string(from: Date())
    }

    private func adYerlestir(_ d: DuzenleyiciDurumu) {
        let ad = Ayarlar.paylasilan.yazarAdi.trimmingCharacters(in: .whitespaces)
        guard !ad.isEmpty else {
            d.ileti("Ayarlar > Genel bölümünden adınızı girin.", baslik: "Ad yok")
            return
        }
        d.damgaYerlestirmeyiBaslat(DamgaTanimi(metin: ad, renk: .siyah, cerceve: false), ad: "Ad")
    }
}

// MARK: - İmza çizimi

/// İmza ya da baş harf çizim sayfası (PencilKit), kayıtlı imzalara ekler.
struct ImzaCizimSayfasi: View {
    @Environment(\.dismiss) private var kapat
    @State private var cizim = PKDrawing()
    @State private var ad = ""
    @State private var basHarf = false
    @State private var renk: Color = .black
    @State private var kalinlik: Double = 3
    @State private var temizle = 0
    @State private var hata: Ileti?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ImzaTuvali(cizim: $cizim, renk: UIColor(renk), kalinlik: CGFloat(kalinlik), temizle: temizle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.4)))
                    .overlay(alignment: .bottomLeading) {
                        Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 52)
                    }
                    .padding(.horizontal)
                Form {
                    Picker("Tür", selection: $basHarf) {
                        Text("İmza").tag(false)
                        Text("Baş harf").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("Ad (ör. Resmî imza)", text: $ad)
                    HStack {
                        Text("Kalınlık")
                        Slider(value: $kalinlik, in: 1...8, step: 0.5)
                    }
                    Picker("Renk", selection: $renk) {
                        Text("Siyah").tag(Color.black)
                        Text("Lacivert").tag(Color(red: 0.05, green: 0.12, blue: 0.5))
                        Text("Mavi").tag(Color.blue)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("İmza çiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Temizle") { temizle += 1 }.disabled(cizim.strokes.isEmpty)
                    Button("Kaydet") { kaydet() }.disabled(cizim.strokes.isEmpty)
                }
            }
            .iletiGoster($hata)
        }
        .presentationDetents([.large])
    }

    private func kaydet() {
        do {
            try ImzaDeposu.paylasilan.ekle(cizim, ad: ad, basHarf: basHarf)
            kapat()
        } catch { hata = Ileti(error) }
    }
}

/// PencilKit tuvali (parmak ve Apple Pencil).
struct ImzaTuvali: UIViewRepresentable {
    @Binding var cizim: PKDrawing
    let renk: UIColor
    let kalinlik: CGFloat
    let temizle: Int

    func makeUIView(context: Context) -> PKCanvasView {
        let k = PKCanvasView()
        k.backgroundColor = .clear
        k.isOpaque = false
        k.drawingPolicy = .anyInput
        k.overrideUserInterfaceStyle = .light
        k.delegate = context.coordinator
        k.tool = PKInkingTool(.pen, color: renk, width: kalinlik)
        return k
    }

    func updateUIView(_ k: PKCanvasView, context: Context) {
        k.tool = PKInkingTool(.pen, color: renk, width: kalinlik)
        if context.coordinator.sonTemizle != temizle {
            context.coordinator.sonTemizle = temizle
            k.drawing = PKDrawing()
        }
    }

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, PKCanvasViewDelegate {
        var ust: ImzaTuvali
        var sonTemizle = 0
        init(_ u: ImzaTuvali) { ust = u }
        func canvasViewDrawingDidChange(_ k: PKCanvasView) { ust.cizim = k.drawing }
    }
}
