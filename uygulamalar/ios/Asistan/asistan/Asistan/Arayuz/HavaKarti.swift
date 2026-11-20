import SwiftUI

/// Hava durumu önizleme kartı (`MesajEki.Tur.hava`): yanıt balonunun içinde durur, sohbetle birlikte saklanır.
struct HavaKarti: View {
    let ozet: HavaOzeti
    @State private var sekme = "Sıcaklık"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(ozet.ad).font(.headline)
                    Text(HavaAraci.kod(ozet.kod).capitalized).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ozet.sicaklikMetni).font(.largeTitle.bold())
            }
            if let dusuk = ozet.dusuk, let yuksek = ozet.yuksek {
                Text("Yüksek: \(Int(yuksek.rounded()))° · Düşük: \(Int(dusuk.rounded()))°").font(.subheadline)
            }
            if !ozet.saatler.isEmpty {
                Picker("Tahmin türü", selection: $sekme) {
                    ForEach(["Sıcaklık", "Yağış", "Rüzgâr"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(ozet.saatler.indices, id: \.self) { i in
                            let s = ozet.saatler[i]
                            VStack(spacing: 7) {
                                Text(s.saat).font(.caption)
                                Image(systemName: simge(s.kod)).symbolRenderingMode(.multicolor)
                                Text(s.deger(sekme)).font(.subheadline.bold())
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            HStack {
                Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                Spacer()
                Text(ozet.zaman, style: .time)
            }.font(.caption).foregroundStyle(.secondary)
            Text("Saatler tahmin konumunun yerel saatidir.").font(.caption2).foregroundStyle(.secondary)
        }
        .modifier(KartZemini())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hava-karti")
    }
    private func simge(_ kod: Int?) -> String {
        switch kod {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3, 45, 48: "cloud.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        case nil: "questionmark.circle"
        default: "cloud.rain.fill"
        }
    }
}
nonisolated extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
