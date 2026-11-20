import KagitKit
import PDFKit
import SwiftUI

/// İşaretle kipi: araç şeridi, renk paleti ve seçili açıklama eylemleri.
struct IsaretleCubugu: View {
    let oturum: BelgeOturumu
    @State private var ayarAcik = false

    var body: some View {
        @Bindable var d = oturum.duzenleyici
        VStack(spacing: 0) {
            if let y = d.yerlestirme { YerlestirmeBandi(yerlestirme: y) { d.yerlestirme = nil } }
            if d.secili != nil {
                SecimEylemleri(durum: d)
            } else if d.metinSecimiVar {
                MetinSecimiEylemleri(durum: d)
            }
            if d.arac.renkVar || d.secili != nil {
                RenkSatiri(durum: d, ayarAcik: $ayarAcik)
            }
            aracSeridi(d)
        }
        .onAppear { d.kipAcildi() }
        .onDisappear { d.kipKapandi() }
        .duzenleyiciSayfalari(d)
        .sheet(isPresented: $ayarAcik) { IsaretAyarSayfasi(durum: d) }
        .kaynakSecici(isPresented: $d.gorselSeciciAcik, girdi: .gorseller) { urller in
            if let u = urller.first { d.gorselEkleOrtaya(u) }
            d.arac = .sec
        }
    }

    private func aracSeridi(_ d: DuzenleyiciDurumu) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(IsaretAraci.allCases) { a in
                    Button {
                        d.arac = a
                        if a == .damga { d.damgaSeciciAcik = true }
                        if a == .gorsel { d.gorselSeciciAcik = true }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: a.simge).font(.system(size: 18))
                            Text(a.ad).font(.caption2).lineLimit(1)
                        }
                        .frame(minWidth: 58)
                        .padding(.vertical, 5).padding(.horizontal, 3)
                        .foregroundStyle(d.arac == a ? Tema.vurgu : .secondary)
                        .background(d.arac == a ? Tema.vurgu.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 28)
                Button { d.aciklamaListesiAcik = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet.rectangle").font(.system(size: 18))
                        Text("Liste").font(.caption2)
                    }
                    .frame(minWidth: 58).padding(.vertical, 5).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }
}

/// "Yerleştirmek için sayfaya dokunun" bandı.
struct YerlestirmeBandi: View {
    let yerlestirme: Yerlestirme
    let iptal: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "hand.tap")
            Text("\(yerlestirme.ad): yerleştirmek için sayfaya dokunun").font(.footnote)
            Spacer()
            Button("Vazgeç", action: iptal).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Tema.vurgu.opacity(0.12))
    }
}

/// Seçili açıklamanın eylemleri.
struct SecimEylemleri: View {
    let durum: DuzenleyiciDurumu

    var body: some View {
        if let a = durum.secili {
            HStack(spacing: 18) {
                Text(AciklamaFabrikasi.ad(a)).font(.footnote.weight(.semibold))
                Spacer()
                if a.type == "FreeText" || a.type == "Text" {
                    Button { durum.seciliyiDuzenle() } label: { Image(systemName: "pencil") }
                }
                Button { durum.seciliyiKopyala() } label: { Image(systemName: "plus.square.on.square") }
                Button(role: .destructive) { durum.seciliyiSil() } label: { Image(systemName: "trash") }
                Button { durum.secili = nil } label: { Image(systemName: "checkmark.circle.fill") }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.08))
        }
    }
}

/// Metin seçilmişken hızlı işaretleme düğmeleri.
struct MetinSecimiEylemleri: View {
    let durum: DuzenleyiciDurumu

    var body: some View {
        HStack(spacing: 14) {
            Text("Seçili metin").font(.footnote.weight(.semibold))
            Spacer()
            ForEach(AciklamaFabrikasi.MetinIsareti.allCases, id: \.self) { t in
                Button { durum.secimdenIsaretle(t) } label: {
                    Image(systemName: simge(t)).padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
    }

    private func simge(_ t: AciklamaFabrikasi.MetinIsareti) -> String {
        switch t {
        case .vurgu: "highlighter"
        case .altCizgi: "underline"
        case .ustuCizili: "strikethrough"
        case .dalgali: "scribble.variable"
        }
    }
}

/// Hazır renkler, son kullanılanlar, özel renk ve ayar düğmesi.
struct RenkSatiri: View {
    let durum: DuzenleyiciDurumu
    @Binding var ayarAcik: Bool

    var body: some View {
        let ayarlar = durum.ayarlar
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array((ayarlar.sonKullanilan + IsaretAyarlari.hazirRenkler).enumerated()), id: \.offset) { _, r in
                        Button { sec(r) } label: {
                            Circle().fill(r.swiftUIRengi).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay {
                                    if esit(ayarlar.renk, r) { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white).shadow(radius: 1) }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("", selection: Binding(get: { ayarlar.renk.swiftUIRengi }, set: { sec(RGBA($0)) }), supportsOpacity: false)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
            }
            Button { ayarAcik = true } label: { Image(systemName: "slider.horizontal.3").padding(.trailing, 14) }
        }
        .padding(.vertical, 6)
    }

    private func esit(_ a: RGBA, _ b: RGBA) -> Bool { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.02 }

    private func sec(_ r: RGBA) {
        durum.kalemiTamamla()
        if durum.secili != nil { durum.seciliRengiDegistir(r) } else { durum.ayarlar.renkSec(r); durum.katman.yenile() }
    }
}

/// Kalınlık, opaklık, dolgu, metin ve kalem ayarları.
struct IsaretAyarSayfasi: View {
    let durum: DuzenleyiciDurumu
    @Environment(\.dismiss) private var kapat

    var body: some View {
        @Bindable var a = durum.ayarlar
        NavigationStack {
            Form {
                if durum.arac.kalinlikVar {
                    Section("Kalınlık: \(Int(a.kalinlik)) pt") {
                        Slider(value: $a.kalinlik, in: 1...30, step: 1)
                    }
                }
                if durum.arac.opaklikVar {
                    Section("Opaklık: %\(Int(a.opaklik * 100))") {
                        Slider(value: $a.opaklik, in: 0.1...1)
                    }
                }
                if durum.arac.sekil == .dikdortgen || durum.arac.sekil == .daire {
                    Section { Toggle("Dolgulu", isOn: $a.dolgu) }
                }
                if durum.arac.metinAyariVar {
                    Section("Metin") {
                        Stepper("Punto: \(Int(a.punto))", value: $a.punto, in: 6...96)
                        Toggle("Kalın", isOn: $a.kalin)
                        Picker("Hizalama", selection: $a.hiza) {
                            ForEach(IsaretAyarlari.Hiza.allCases) { Text($0.ad).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if durum.arac.kalemMi {
                    Section {
                        Toggle("Yalnız Apple Pencil ile çiz", isOn: $a.yalnizPencil)
                    } footer: {
                        Text("Kapalıyken parmakla da çizilir; sayfayı kaydırmak için iki parmak kullanın.")
                    }
                }
                Section {
                    Text("Not: iOS 27'de PDFKit açıklamaları yakınlaştırınca pikselleşebilir. Paylaşırken \"Düzleştirerek paylaş\" bunu önler.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Araç ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
            .onChange(of: a.kalinlik) { _, _ in durum.katman.yenile() }
            .onChange(of: a.yalnizPencil) { _, _ in durum.kaydirmaAyarla(); durum.katman.yenile() }
        }
        .presentationDetents([.medium, .large])
    }
}
