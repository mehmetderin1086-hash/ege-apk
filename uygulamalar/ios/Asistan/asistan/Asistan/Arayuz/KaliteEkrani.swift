import SwiftUI

/// P3.3: Ayarlar → Kalite ve değerlendirme. Son 7 günün model bazlı beğeni/itiraz özeti, beğenmeme nedenleri,
/// telefonda toplanan değerlendirme seti (silme, JSON paylaşma) ve kalite kayıtlarını temizleme.
struct KaliteEkrani: View {
    @State private var temizleSor = false
    @State private var paylasilacak: URL?

    private var defter: KaliteDefteri { KaliteDefteri.ortak }
    private var depo: DegerlendirmeDeposu { DegerlendirmeDeposu.ortak }

    var body: some View {
        let ozet = defter.ozet(gun: 7)
        let nedenler = KaliteDefteri.nedenSayilari(defter.kayitlar, gun: 7)
        Form {
            Section {
                if ozet.isEmpty {
                    Text("Son 7 günde kayıt yok. Yanıtın altındaki başparmak simgeleriyle, Durdur, yeniden üret ve \"hayır, yanlış anladın\" itirazlarıyla dolar.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(ozet) { o in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(o.model).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 12) {
                                Label("\(o.begeni)", systemImage: "hand.thumbsup")
                                Label("\(o.begenmeme)", systemImage: "hand.thumbsdown")
                                Label("\(o.itiraz)", systemImage: "exclamationmark.bubble")
                                Label("\(o.durdur)", systemImage: "stop.circle")
                                Label("\(o.yenidenUret)", systemImage: "arrow.clockwise")
                            }
                            .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(o.model): \(o.begeni) beğeni, \(o.begenmeme) beğenmeme, \(o.itiraz) itiraz, \(o.durdur) durdurma, \(o.yenidenUret) yeniden üretme")
                        .accessibilityIdentifier("kalite-ozet-satiri")
                    }
                }
            } header: { Text("Son 7 gün") }
            if !nedenler.isEmpty {
                Section("Beğenmeme nedenleri") {
                    ForEach(nedenler, id: \.neden) { n in LabeledContent(n.neden, value: "\(n.sayi)") }
                }
            }
            Section {
                if depo.ornekler.isEmpty {
                    Text("Henüz örnek yok. Bir yanıta uzun basıp \"Değerlendirme setine ekle\"yi seç.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(depo.ornekler) { o in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.istek).lineLimit(2)
                            Text(([o.beklenenYol] + o.beklenenAraclar).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("degerlendirme-satiri")
                    }
                    .onDelete { konumlar in
                        let silinecek = konumlar.map { depo.ornekler[$0].id }
                        for id in silinecek { depo.sil(id) }
                    }
                    if let paylasilacak {
                        ShareLink(item: paylasilacak) { Label("Seti JSON olarak paylaş", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("degerlendirme-paylas")
                    }
                }
            } header: { Text("Değerlendirme seti (\(depo.ornekler.count))") } footer: {
                Text("Paylaşılan JSON depodaki AsistanTests/Veri/DegerlendirmeSeti.json biçimindedir; her birim test turunda yol, çaba ve hızlı yol uygunluğu denetlenir.")
            }
            Section {
                Button("Kalite kayıtlarını temizle", role: .destructive) { temizleSor = true }
                    .disabled(defter.kayitlar.isEmpty)
                    .accessibilityIdentifier("kalite-temizle")
            } footer: {
                Text("Kayıtlarda istek ya da yanıt metni tutulmaz; yalnız olay, model, yol ve araç adları.")
            }
        }
        .navigationTitle("Kalite ve değerlendirme")
        .accessibilityIdentifier("kalite-ekrani")
        // Paylaşım kopyası set değiştikçe yenilenir (ShareLink dosyayı hemen okur).
        .task(id: depo.ornekler) { paylasilacak = depo.ornekler.isEmpty ? nil : depo.disaAktar() }
        .confirmationDialog("Kalite kayıtları silinsin mi?", isPresented: $temizleSor, titleVisibility: .visible) {
            Button("Temizle", role: .destructive) { defter.temizle() }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

/// P3.3: "Değerlendirme setine ekle" sayfasının girdisi (balon menüsünden).
struct DegerlendirmeTaslagi: Identifiable {
    let id = UUID()
    let istek: String
    let iz: YanitIzi?
    let yanit: String
}

/// P3.3: balondaki yanıtı değerlendirme setine örnek olarak ekler. Beklenen yol izden (yoksa YolTahmini'nden) dolar.
struct DegerlendirmeEkleSayfasi: View {
    let taslak: DegerlendirmeTaslagi
    @Environment(\.dismiss) private var kapat
    @State private var yol = "zincir"
    @State private var caba = ""
    @State private var araclar = ""
    @State private var not = ""
    @State private var yanitiSakla = false
    @State private var hazir = false

    var body: some View {
        NavigationStack {
            Form {
                Section("İstek") {
                    Text(taslak.istek).lineLimit(6).textSelection(.enabled)
                }
                Section {
                    Picker("Beklenen yol", selection: $yol) {
                        ForEach(YolTahmini.yollar, id: \.self) { Text($0).tag($0) }
                    }
                    .accessibilityIdentifier("degerlendirme-yol")
                    Picker("Beklenen çaba", selection: $caba) {
                        Text("Denetleme").tag("")
                        ForEach(DusunmeSecimi.Caba.allCases, id: \.self) { Text($0.ad).tag($0.rawValue) }
                    }
                    TextField("Beklenen araçlar (virgülle)", text: $araclar)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    if let iz = taslak.iz {
                        Text("Bu yanıt: \(iz.yol) yolu, \(iz.kip) kipi" + (iz.araclar.isEmpty ? "" : ", araçlar: " + iz.araclar.joined(separator: ", ")))
                    }
                }
                Section {
                    Toggle("Yanıtı \"yaptım\" bekçisi örneği olarak sakla", isOn: $yanitiSakla)
                    TextField("Not (isteğe bağlı)", text: $not, axis: .vertical)
                }
            }
            .navigationTitle("Değerlendirme setine ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet() }.accessibilityIdentifier("degerlendirme-kaydet")
                }
            }
            .onAppear {
                guard !hazir else { return }
                hazir = true
                let tahmin = YolTahmini.tahmin(taslak.istek)
                yol = taslak.iz?.yol ?? tahmin.yol
                if !YolTahmini.yollar.contains(yol) { yol = tahmin.yol }
                caba = taslak.iz?.caba ?? ""
                araclar = (taslak.iz?.araclar ?? []).joined(separator: ", ")
            }
        }
    }

    private func kaydet() {
        let liste = araclar.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ornekYanit = yanitiSakla ? String(taslak.yanit.prefix(600)) : nil
        let notMetni = not.trimmingCharacters(in: .whitespacesAndNewlines)
        DegerlendirmeDeposu.ortak.ekle(DegerlendirmeOrnegi(
            istek: taslak.istek, beklenenYol: yol, beklenenCaba: caba.isEmpty ? nil : caba,
            hizliUygun: yol == "yaris" ? true : nil, beklenenAraclar: liste, ornekYanit: ornekYanit,
            eylemIddiasiBeklenir: ornekYanit.map { EylemIddiasi.denetle($0, basariliAraclar: []) != nil },
            not: notMetni.isEmpty ? nil : notMetni))
        TostDefteri.ortak.goster("Değerlendirme setine eklendi", simge: "checklist")
        kapat()
    }
}

extension Beyin {
    /// P3.3: asistan yanıtından önceki kullanıcı isteği (modele giden özgün metin; yalnız fotoğrafta görünen metin).
    func degerlendirmeIstegi(yanitID: UUID) -> String? {
        guard let i = mesajlar.firstIndex(where: { $0.id == yanitID }),
              let k = mesajlar[..<i].lastIndex(where: { $0.rol == .kullanici }) else { return nil }
        let m = mesajlar[k]
        if let istek = m.istek, !istek.isEmpty { return istek }
        return m.metin.replacingOccurrences(of: "📷 ", with: "")
    }
}
