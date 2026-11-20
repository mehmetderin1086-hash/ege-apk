import SwiftUI

/// Bağlantının bilgisini getirir; video için kalite/ses/altyazı/kesit seçtirir, liste için öğe seçtirir.
struct BilgiSayfasi: View {
    let istek: BilgiIstegi
    @Environment(\.dismiss) private var kapat
    @State private var bilgi: MedyaBilgisi?
    @State private var hata: String?
    @State private var listeyiAc = false

    var body: some View {
        NavigationStack {
            Group {
                if let bilgi, bilgi.liste {
                    ListeIcerigi(bilgi: bilgi) { kapat() }
                } else if let bilgi {
                    VideoSecimi(adres: istek.adres, bilgi: bilgi, listeVar: listeBaglantisi) { kapat() } listeyiAc: { listeyiAc = true }
                } else if let hata {
                    ContentUnavailableView {
                        Label("Bilgi alınamadı", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(hata).textSelection(.enabled)
                    } actions: {
                        Button("Yeniden dene") { Task { await yukle() } }.buttonStyle(.borderedProminent)
                    }
                } else {
                    yukleniyor
                }
            }
            .navigationTitle(bilgi?.liste == true ? "Liste" : "İndir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat", systemImage: "xmark") { kapat() } }
            }
            .navigationDestination(isPresented: $listeyiAc) {
                ListeYukleyici(adres: istek.adres) { kapat() }
            }
        }
        .task { await yukle() }
    }

    private var listeBaglantisi: Bool {
        URLComponents(string: istek.adres)?.queryItems?.contains { $0.name == "list" && !($0.value ?? "").isEmpty } ?? false
    }

    private var yukleniyor: some View {
        VStack(spacing: 16) {
            if let kapak = istek.kapak { KucukResim(adres: kapak, genislik: 280) }
            if let baslik = istek.baslik { Text(baslik).font(.headline).multilineTextAlignment(.center).padding(.horizontal) }
            ProgressView("Bağlantı çözülüyor…")
            Text(istek.adres).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func yukle() async {
        hata = nil
        do {
            bilgi = try await PythonMotoru.shared.coz(istek.adres, liste: istek.liste || ListeAdresi.listeMi(istek.adres))
        } catch {
            hata = error.localizedDescription
        }
    }
}

/// Bir listeyi (oynatma listesi/kanal) ayrıca yükleyen ara görünüm.
struct ListeYukleyici: View {
    let adres: String
    let bitti: () -> Void
    @State private var bilgi: MedyaBilgisi?
    @State private var hata: String?

    var body: some View {
        Group {
            if let bilgi { ListeIcerigi(bilgi: bilgi, bitti: bitti) }
            else if let hata { ContentUnavailableView("Liste alınamadı", systemImage: "exclamationmark.triangle", description: Text(hata)) }
            else { ProgressView("Liste getiriliyor…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .navigationTitle("Liste")
        .task {
            do { bilgi = try await PythonMotoru.shared.coz(adres, liste: true) } catch { hata = error.localizedDescription }
        }
    }
}

// MARK: Tek video

struct VideoSecimi: View {
    let adres: String
    let bilgi: MedyaBilgisi
    var listeVar = false
    let bitti: () -> Void
    var listeyiAc: () -> Void = {}

    @Environment(Yonlendirici.self) private var yonlendirici
    @State private var tur: IndirmeTuru = Ayarlar.shared.hizliTur
    @State private var kaliteID: String?
    @State private var sesID: String?
    @State private var dil: String?
    @State private var altyazi = Ayarlar.shared.altyaziDili
    @State private var otomatik = Ayarlar.shared.otomatikAltyazi
    @State private var kesitAcik = false
    @State private var kesitBas: Double = 0
    @State private var kesitSon: Double = 0

    private var kaliteler: [KaliteSecenegi] { BicimSecici.kaliteler(bilgi) }
    private var sesler: [Bicim] { BicimSecici.sesler(bilgi, dil: dil) }
    private var diller: [String] { BicimSecici.diller(bilgi) }
    private var sure: Double { bilgi.duration ?? 0 }

    private var secim: IndirmeSecimi {
        IndirmeSecimi(tur: tur, kaliteID: tur == .video ? kaliteID : nil, enFazla: Ayarlar.shared.enFazlaCozunurluk,
                      sesID: sesID, dil: dil, altyazi: altyazi.isEmpty ? nil : altyazi, otomatikAltyazi: otomatik,
                      kesit: kesitAcik && kesitSon > kesitBas ? kesitBas...kesitSon : nil)
    }
    private var plan: IndirmePlani? {
        BicimSecici.plan(bilgi, tur: tur, enFazla: Ayarlar.shared.enFazlaCozunurluk, kaliteID: kaliteID, sesID: sesID, dil: dil)
    }

    var body: some View {
        Form {
            Section { baslik }
            if listeVar {
                Section {
                    Button(action: listeyiAc) { Label("Bu listenin tüm videoları", systemImage: "list.bullet.rectangle") }
                }
            }
            Section {
                Picker("Tür", selection: $tur) {
                    ForEach(IndirmeTuru.allCases) { Text($0.ad).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch tur {
            case .video: videoBolumu
            case .ses: sesBolumu
            case .ham: hamBolumu
            }
            if diller.count > 1 && tur != .ham {
                Section("Ses dili") {
                    Picker("Dil", selection: $dil) {
                        Text("Asıl ses").tag(String?.none)
                        ForEach(diller, id: \.self) { Text(Self.dilAdi($0)).tag(String?.some($0)) }
                    }
                }
            }
            if tur == .video { altyaziBolumu }
            if tur != .ham && sure > 1 { kesitBolumu }
        }
        .safeAreaInset(edge: .bottom) { indirCubugu }
        .onAppear {
            if kaliteID == nil { kaliteID = BicimSecici.plan(bilgi, tur: .video, enFazla: Ayarlar.shared.enFazlaCozunurluk)?.video.flatMap { v in kaliteler.first { $0.video == v }?.id } }
            if kesitSon == 0 { kesitSon = sure }
            if tur == .video && kaliteler.isEmpty { tur = .ham }
        }
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 8) {
            KucukResim(adres: bilgi.thumbnail, sure: bilgi.duration, genislik: 320)
                .frame(maxWidth: .infinity)
            Text(bilgi.title ?? adres).font(.headline)
            HStack(spacing: 6) {
                if let yazar = bilgi.yazar { Text(yazar) }
                if let izlenme = bilgi.viewCount { Text("· \(izlenme.formatted(.number.notation(.compactName))) izlenme") }
                if let site = bilgi.extractorKey, site != "Youtube" { Text("· \(site)") }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var videoBolumu: some View {
        Section {
            if kaliteler.isEmpty {
                Text("Bu videoda iPhone'un oynatabildiği (H.264/HEVC) bir biçim yok. \"Özgün dosya\" ile olduğu gibi indirebilirsin.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(kaliteler) { k in
                Button { kaliteID = k.id } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(k.etiket).font(.body.weight(.semibold).monospacedDigit())
                            Text(k.ayrinti).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(BicimSecici.boyutMetni(videoBoyutu(k))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: kaliteID == k.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(kaliteID == k.id ? Color.kepce : .secondary)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Kalite")
        } footer: {
            if !BicimSecici.av1Donanim, (bilgi.formats ?? []).contains(where: { ($0.height ?? 0) > 1080 && $0.videoVar }) {
                Text("1080p üstü yalnız AV1/VP9 olarak sunuluyor; bu iPhone AV1'i donanımla çözemediği için listelenmedi. \"Özgün dosya\" ile WebM olarak alabilirsin.")
            }
        }
    }

    private func videoBoyutu(_ k: KaliteSecenegi) -> Int64? {
        let v = k.video.boyut(sure: bilgi.duration)
        guard !k.video.sesVar else { return v }
        let s = (sesID.flatMap { id in sesler.first { $0.formatID == id } } ?? sesler.first)?.boyut(sure: bilgi.duration)
        return v.map { $0 + (s ?? 0) }
    }

    @ViewBuilder private var sesBolumu: some View {
        Section("Ses kalitesi") {
            if sesler.isEmpty {
                Text(plan == nil ? "Uygun ses akışı yok." : "Ayrı ses akışı yok; ses videodan ayrılacak.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(sesler) { s in
                let secili = (sesID ?? sesler.first?.formatID) == s.formatID
                Button { sesID = s.formatID } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(BicimSecici.kodekAdi(s.sesKodegi)) · \(Int((s.abr ?? s.tbr ?? 0).rounded())) kb/sn").font(.body.weight(.semibold))
                            Text([s.language.map(Self.dilAdi), s.drc ? "ses dengelemeli" : nil, s.ext?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(BicimSecici.boyutMetni(s.boyut(sure: bilgi.duration))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: secili ? "checkmark.circle.fill" : "circle").foregroundStyle(secili ? Color.kepce : .secondary)
                    }
                }
                .tint(.primary)
            }
        }
    }

    @ViewBuilder private var hamBolumu: some View {
        Section {
            if let plan { LabeledContent("Biçim", value: plan.etiket); LabeledContent("Boyut", value: BicimSecici.boyutMetni(plan.tahminiBoyut)) }
        } header: {
            Text("Özgün dosya")
        } footer: {
            Text("Sitenin sunduğu en iyi tek dosya, dönüştürmeden kaydedilir (WebM/MKV olabilir). Dosyalar uygulamasında \"Kepçe › Özgün dosyalar\" altında durur; her oynatıcı açamayabilir.")
        }
    }

    @ViewBuilder private var altyaziBolumu: some View {
        let elle = (bilgi.subtitles ?? [:]).keys.filter { $0 != "live_chat" }.sorted()
        let oto = (bilgi.automaticCaptions ?? [:]).keys.sorted()
        if !elle.isEmpty || !oto.isEmpty {
            Section {
                Picker("Altyazı", selection: $altyazi) {
                    Text("Yok").tag("")
                    ForEach(Array(Set(elle + (otomatik ? oto : []))).sorted(), id: \.self) { kod in
                        Text(Self.dilAdi(kod) + (elle.contains(kod) ? "" : " (otomatik)")).tag(kod)
                    }
                }
                if !oto.isEmpty { Toggle("Otomatik altyazıları da göster", isOn: $otomatik) }
            } header: {
                Text("Altyazı")
            } footer: {
                Text("Altyazı videonun yanına .srt olarak kaydedilir ve Kepçe oynatıcısında gösterilir.")
            }
        }
    }

    @ViewBuilder private var kesitBolumu: some View {
        Section {
            Toggle("Yalnız bir kesit indir", isOn: $kesitAcik.animation())
            if kesitAcik {
                if let bolumler = bilgi.chapters, !bolumler.isEmpty {
                    Menu {
                        ForEach(Array(bolumler.enumerated()), id: \.offset) { _, b in
                            Button("\(BicimSecici.sureMetni(b.startTime)) \(b.title ?? "")") { kesitBas = b.startTime; kesitSon = b.endTime }
                        }
                    } label: { Label("Bölüm seç", systemImage: "list.number") }
                }
                ZamanSecici(baslik: "Başlangıç", deger: $kesitBas, aralik: 0...max(0, sure - 1))
                ZamanSecici(baslik: "Bitiş", deger: $kesitSon, aralik: min(sure, kesitBas + 1)...sure)
            }
        } header: {
            Text("Kesit")
        } footer: {
            if kesitAcik { Text("Video yeniden kodlanmadan kesilir; başlangıç en yakın anahtar kareye kayabilir. Önce bütün akış indirilir.") }
        }
    }

    private var indirCubugu: some View {
        VStack(spacing: 6) {
            if let plan {
                Text("\(plan.etiket) · ≈ \(BicimSecici.boyutMetni(tahmin(plan)))").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                IndirmeKuyrugu.shared.ekle(adres: adres, bilgi: bilgi, secim: secim)
                yonlendirici.bildirim = "Sıraya eklendi"
                yonlendirici.sekme = .indir
                bitti()
            } label: {
                Label("İndir", systemImage: "arrow.down.circle.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(plan == nil)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func tahmin(_ plan: IndirmePlani) -> Int64? {
        guard let boyut = plan.tahminiBoyut else { return nil }
        guard let kesit = secim.kesit, sure > 0 else { return boyut }
        return Int64(Double(boyut) * (kesit.upperBound - kesit.lowerBound) / sure)
    }

    static func dilAdi(_ kod: String) -> String {
        let taban = String(kod.split(separator: "-").first ?? Substring(kod))
        let ad = Locale(identifier: "tr").localizedString(forLanguageCode: taban) ?? kod
        return kod.contains("-") ? "\(ad.capitalized(with: Locale(identifier: "tr"))) (\(kod))" : ad.capitalized(with: Locale(identifier: "tr"))
    }
}

/// Dakika:saniye ayarlı kaydırıcı.
struct ZamanSecici: View {
    let baslik: String
    @Binding var deger: Double
    let aralik: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(baslik)
                Spacer()
                Stepper(BicimSecici.sureMetni(deger), value: $deger, in: aralik, step: 1).monospacedDigit().fixedSize()
            }
            Slider(value: $deger, in: aralik, step: 1)
        }
        .onChange(of: aralik) { _, yeni in deger = min(max(deger, yeni.lowerBound), yeni.upperBound) }
    }
}

// MARK: Liste

struct ListeIcerigi: View {
    let bilgi: MedyaBilgisi
    let bitti: () -> Void
    @Environment(Yonlendirici.self) private var yonlendirici
    @State private var secili: Set<String> = []
    @State private var tur: IndirmeTuru = Ayarlar.shared.hizliTur == .ham ? .video : Ayarlar.shared.hizliTur
    @State private var cozunurluk = Ayarlar.shared.enFazlaCozunurluk
    @State private var klasorle = Ayarlar.shared.listeKlasoru
    @State private var numarala = Ayarlar.shared.listeNumarala
    @State private var atla = Ayarlar.shared.indirilenleriAtla
    @State private var mevcut: Set<String> = []
    @State private var arama = ""

    private var ogeler: [ListeOgesi] { (bilgi.entries ?? []).filter { $0.adres != nil && !$0.canli } }
    private var gorunen: [ListeOgesi] {
        arama.isEmpty ? ogeler : ogeler.filter { ($0.title ?? "").localizedStandardContains(arama) }
    }
    private func indirildi(_ oge: ListeOgesi) -> Bool { oge.adres.map { mevcut.contains(IndirmeKuyrugu.anahtar($0)) } ?? false }
    private var toplamSure: Double { ogeler.filter { secili.contains($0.id) }.compactMap(\.duration).reduce(0, +) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bilgi.title ?? "Liste").font(.headline)
                    Text([bilgi.yazar, "\(ogeler.count) video", mevcut.isEmpty ? nil : "\(ogeler.filter(indirildi).count) indirilmiş"]
                        .compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                }
                Picker("Tür", selection: $tur) {
                    Text("Video").tag(IndirmeTuru.video)
                    Text("Ses").tag(IndirmeTuru.ses)
                }
                .pickerStyle(.segmented)
                if tur == .video {
                    Picker("En yüksek kalite", selection: $cozunurluk) {
                        ForEach(Ayarlar.cozunurlukler, id: \.self) { Text(Ayarlar.cozunurlukAdi($0)).tag($0) }
                    }
                }
                Toggle("Liste adıyla klasöre kaydet", isOn: $klasorle)
                Toggle("Sıra numarası ekle", isOn: $numarala)
                Toggle("Zaten indirilenleri atla", isOn: $atla)
            }
            Section {
                ForEach(gorunen) { oge in
                    Button {
                        if secili.contains(oge.id) { secili.remove(oge.id) } else { secili.insert(oge.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: secili.contains(oge.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(secili.contains(oge.id) ? Color.kepce : .secondary)
                            KucukResim(adres: oge.thumbnail, sure: oge.duration, genislik: 88)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(oge.title ?? oge.id).font(.subheadline).lineLimit(3)
                                if indirildi(oge) { Label("İndirilmiş", systemImage: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green) }
                            }
                        }
                    }
                    .tint(.primary)
                    .contextMenu {
                        if let adres = oge.adres {
                            Button { yonlendirici.bilgi = BilgiIstegi(adres: adres, baslik: oge.title, kapak: oge.thumbnail) } label: { Label("Seçerek indir", systemImage: "slider.horizontal.3") }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(secili.count) seçili" + (toplamSure > 0 ? " · \(BicimSecici.sureMetni(toplamSure))" : ""))
                    Spacer()
                    Menu("Seç") {
                        Button("Tümü") { secili = Set(ogeler.map(\.id)) }
                        Button("Hiçbiri") { secili = [] }
                        Button("İndirilmemişler") { secili = Set(ogeler.filter { !indirildi($0) }.map(\.id)) }
                        Button("Tersini seç") { secili = Set(ogeler.map(\.id)).subtracting(secili) }
                        Divider()
                        ForEach([10, 25, 50, 100], id: \.self) { n in
                            Button("İlk \(n)") { secili = Set(ogeler.prefix(n).map(\.id)) }
                        }
                        Button("Son 10") { secili = Set(ogeler.suffix(10).map(\.id)) }
                    }
                    .textCase(nil)
                }
            }
        }
        .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Listede ara")
        .safeAreaInset(edge: .bottom) {
            Button {
                var secim = IndirmeSecimi.hizli(tur)
                secim.enFazla = cozunurluk
                secim.liste = bilgi.title
                if klasorle { secim.altKlasor = bilgi.title ?? bilgi.yazar }
                // Sıra numarası listedeki asıl konumdur (seçim atlasa bile).
                var eklenen = 0, atlanan = 0
                let kuyruk = IndirmeKuyrugu.shared
                let secilenler = ogeler.enumerated().filter { secili.contains($0.element.id) }
                if numarala {
                    for (i, oge) in secilenler {
                        var s = secim
                        s.siraNo = i + 1
                        let r = kuyruk.topluEkle([.init(adres: oge.adres!, baslik: oge.title, kapak: oge.thumbnail, sure: oge.duration)], secim: s, atla: atla)
                        eklenen += r.eklenen; atlanan += r.atlanan
                    }
                } else {
                    let r = kuyruk.topluEkle(secilenler.map { .init(adres: $0.element.adres!, baslik: $0.element.title, kapak: $0.element.thumbnail, sure: $0.element.duration) },
                                             secim: secim, atla: atla)
                    eklenen = r.eklenen; atlanan = r.atlanan
                }
                yonlendirici.bildirim = "\(eklenen) öğe sıraya eklendi" + (atlanan > 0 ? ", \(atlanan) zaten vardı" : "")
                yonlendirici.sekme = .indir
                bitti()
            } label: {
                Label("Seçilenleri indir (\(secili.count))", systemImage: "arrow.down.circle.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(secili.isEmpty)
            .padding()
            .background(.bar)
        }
        .onAppear {
            mevcut = IndirmeKuyrugu.shared.mevcutAnahtarlar()
            if secili.isEmpty { secili = Set(ogeler.filter { !atla || !indirildi($0) }.map(\.id)) }
        }
    }
}
