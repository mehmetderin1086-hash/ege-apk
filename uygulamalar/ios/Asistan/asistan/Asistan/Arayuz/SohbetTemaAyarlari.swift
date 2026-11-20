import SwiftUI

/// Görünüm stüdyosundaki sohbet teması bölümleri: hazır temalar, her renk (açık/koyu ayrı), balon ve çubuk seçenekleri.
struct SohbetTemaAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(\.colorScheme) private var sema
    @State private var koyuPalet = false
    @State private var ilk = true

    /// Hazır temayla birlikte önerilen vurgu rengi.
    static func vurgu(_ ad: String) -> String {
        switch ad { case "Karma", "Claude": "D97757"; case "Telegram": "3390EC"; case "Sade": "007AFF"; case "Gece": "9164E8"; default: "D97757" }
    }

    var body: some View {
        @Bindable var a = ayarlar
        let t = a.gorunum.sohbetTemasi
        Group {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(SohbetTemasi.hazirlar, id: \.ad) { h in
                            Button {
                                a.gorunum.sohbet = h; a.gorunum.renk = Self.vurgu(h.ad)
                            } label: { kart(h, secili: t.ad == h.ad) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(h.ad) sohbet teması").accessibilityAddTraits(t.ad == h.ad ? .isSelected : [])
                            .accessibilityIdentifier("sohbet-tema-\(h.ad)")
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            } header: { Text("Sohbet teması") } footer: { Text("Hazır temayı seçip aşağıdan her rengi ve özelliği tek tek değiştirebilirsin.") }

            Section {
                Picker("Düzenlenen", selection: $koyuPalet) {
                    Text("Açık mod").tag(false); Text("Koyu mod").tag(true)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("palet-secimi")
                renkSatiri("Zemin", \.zemin)
                renkSatiri("Zemin (gradyan sonu)", \.zemin2)
                Toggle("Desenli duvar kâğıdı", isOn: paletBool(\.desen))
                renkSatiri("Senin balonun", \.kullaniciBalon)
                renkSatiri("Senin yazın", \.kullaniciYazi)
                renkSatiri("Asistan balonu", \.asistanBalon)
                renkSatiri("Asistan yazısı", \.asistanYazi)
                renkSatiri("İkincil yazı (saat, model)", \.ikincil)
                renkSatiri("Düğme zemini", \.dugme)
                renkSatiri("Kenarlık", \.cizgi)
            } header: { Text("Sohbet renkleri") } footer: { Text("Açık ve koyu mod renkleri ayrı saklanır; telefon hangi moddaysa o kullanılır. Vurgu rengi aşağıdaki Tema ve renk bölümündedir.") }

            Section("Mesaj biçimi") {
                Toggle("Asistan yanıtı balon içinde", isOn: temaBool(\.asistanBalonlu))
                Toggle("Balon kuyruğu", isOn: temaBool(\.kuyruk))
                LabeledContent("Köşe yuvarlaklığı", value: "\(Int(t.kose))")
                Slider(value: Binding(get: { a.gorunum.sohbetTemasi.kose }, set: { a.gorunum.sohbetTemasi.kose = $0 }), in: 4...28, step: 1)
                    .accessibilityLabel("Balon köşe yuvarlaklığı")
                Picker("Asistan yazı tipi", selection: Binding(get: { a.gorunum.sohbetTemasi.asistanYaziTipi }, set: { a.gorunum.sohbetTemasi.asistanYaziTipi = $0 })) {
                    ForEach(SohbetTemasi.YaziTipi.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Senin yazı tipin", selection: Binding(get: { a.gorunum.sohbetTemasi.kullaniciYaziTipi }, set: { a.gorunum.sohbetTemasi.kullaniciYaziTipi = $0 })) {
                    ForEach(SohbetTemasi.YaziTipi.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Model adını göster (dokununca model değişir)", isOn: temaBool(\.modelAdi))
                Toggle("Mesaj saatini göster", isOn: temaBool(\.saat))
                Toggle("Gün ayırıcı (Bugün, 8 Ekim)", isOn: temaBool(\.tarihRozeti))
                Toggle("Son yanıtın altında eylem satırı", isOn: temaBool(\.eylemSatiri))
                    .accessibilityIdentifier("tema-eylem-satiri")
                Toggle("Beğen / beğenme düğmeleri", isOn: temaBool(\.geriBildirim))
                    .accessibilityIdentifier("tema-geri-bildirim")
            }

            Section("Çubuklar ve düğmeler") {
                Toggle("Üstte ad ve durum hapı", isOn: temaBool(\.baslik))
                Toggle("Düğme kenarlıkları", isOn: temaBool(\.dugmeKenarlik))
                Picker("Yazma alanı", selection: Binding(get: { a.gorunum.sohbetTemasi.giris }, set: { a.gorunum.sohbetTemasi.giris = $0 })) {
                    ForEach(SohbetTemasi.GirisStili.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Menü simgesi", selection: Binding(get: { a.gorunum.sohbetTemasi.menu }, set: { a.gorunum.sohbetTemasi.menu = $0 })) {
                    ForEach(SohbetTemasi.MenuSimgesi.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("\(t.ad) temasının özgün hâline dön", systemImage: "arrow.counterclockwise") {
                    let h = SohbetTemasi.hazirlar.first { $0.ad == t.ad } ?? .claude
                    a.gorunum.sohbet = h; a.gorunum.renk = Self.vurgu(h.ad)
                }
            }
        }
        .onAppear { if ilk { koyuPalet = sema == .dark; ilk = false } }
    }

    private func kart(_ h: SohbetTemasi, secili: Bool) -> some View {
        let p = h.palet(sema == .dark)
        return VStack(spacing: 6) {
            ZStack {
                LinearGradient(colors: [Color(hex: p.zemin), Color(hex: p.zemin2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(hex: p.kullaniciBalon)).frame(width: 36, height: 10).frame(maxWidth: .infinity, alignment: .trailing)
                    if h.asistanBalonlu {
                        RoundedRectangle(cornerRadius: 5).fill(Color(hex: p.asistanBalon)).frame(width: 44, height: 14)
                    } else {
                        Capsule().fill(Color(hex: p.asistanYazi).opacity(0.7)).frame(width: 46, height: 3)
                        Capsule().fill(Color(hex: p.asistanYazi).opacity(0.7)).frame(width: 34, height: 3)
                    }
                    Circle().fill(Color(hex: Self.vurgu(h.ad))).frame(width: 8, height: 8).frame(maxWidth: .infinity, alignment: .trailing)
                }.padding(8)
            }
            .frame(width: 84, height: 70).clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(secili ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: secili ? 3 : 1))
            Text(h.ad).font(.caption.bold())
        }
    }

    private func renkSatiri(_ ad: String, _ kp: WritableKeyPath<SohbetPaleti, String>) -> some View {
        ColorPicker(ad, selection: Binding(get: {
            Color(hex: ayarlar.gorunum.sohbetTemasi.palet(koyuPalet)[keyPath: kp])
        }, set: { yeni in
            var t = ayarlar.gorunum.sohbetTemasi
            if koyuPalet { t.koyu[keyPath: kp] = yeni.rgbHex } else { t.acik[keyPath: kp] = yeni.rgbHex }
            ayarlar.gorunum.sohbetTemasi = t
        }), supportsOpacity: false)
    }

    private func paletBool(_ kp: WritableKeyPath<SohbetPaleti, Bool>) -> Binding<Bool> {
        Binding(get: { ayarlar.gorunum.sohbetTemasi.palet(koyuPalet)[keyPath: kp] }, set: { yeni in
            var t = ayarlar.gorunum.sohbetTemasi
            if koyuPalet { t.koyu[keyPath: kp] = yeni } else { t.acik[keyPath: kp] = yeni }
            ayarlar.gorunum.sohbetTemasi = t
        })
    }

    private func temaBool(_ kp: WritableKeyPath<SohbetTemasi, Bool>) -> Binding<Bool> {
        Binding(get: { ayarlar.gorunum.sohbetTemasi[keyPath: kp] }, set: { ayarlar.gorunum.sohbetTemasi[keyPath: kp] = $0 })
    }
}
