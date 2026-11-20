import KagitKit
import PDFKit
import SwiftUI

/// Tam ekran belge görüntüleyici/düzenleyici: üstte belge araçları, ortada PDF,
/// altta seçili kipin araç çubuğu ve kip seçici.
struct BelgeEkrani: View {
    let oge: KitaplikOgesi
    var acilisKipi: BelgeKipi = .oku

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var oturum: BelgeOturumu
    @State private var parolaMetni = ""
    @State private var paylasilacak: [URL]?
    @State private var bilgiAcik = false
    @State private var surumlerAcik = false
    @State private var kucukResimlerAcik = false
    @State private var kapatmaSor = false

    init(oge: KitaplikOgesi, acilisKipi: BelgeKipi = .oku) {
        self.oge = oge
        self.acilisKipi = acilisKipi
        _oturum = State(initialValue: BelgeOturumu(oge: oge))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if oturum.belge != nil {
                    if oturum.kip == .sayfalar {
                        SayfaDuzenleyici(oturum: oturum)
                    } else {
                        HStack(spacing: 0) {
                            if kucukResimlerAcik { KucukResimSeridi(oturum: oturum).frame(width: 96) }
                            PDFGorunumu(oturum: oturum, baslangicSayfasi: kitaplik.bilgi(oge).sonSayfa)
                                .overlay { okumaRengiKatmani }
                                .overlay(alignment: .bottomTrailing) { sayfaGostergesi }
                        }
                    }
                    KipCubugu(oturum: oturum)
                    kipSecici
                } else if oturum.parolaGerekli {
                    parolaEkrani
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(oge.ad)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ustAraclar }
            .overlay { if let m = oturum.calisiyor { CalisiyorKatmani(metin: m) } }
            .iletiGoster($oturum.ileti)
            .sheet(item: Binding(get: { paylasilacak.map { PaylasimIstegi(urller: $0) } }, set: { paylasilacak = $0?.urller })) {
                PaylasimSayfasi(ogeler: $0.urller)
            }
            .sheet(isPresented: $bilgiAcik) { BelgeBilgisi(oturum: oturum) }
            .sheet(isPresented: $surumlerAcik) { SurumlerSayfasi(oturum: oturum) }
            .confirmationDialog("Değişiklikler kaydedilsin mi?", isPresented: $kapatmaSor, titleVisibility: .visible) {
                Button("Kaydet") { Task { if await oturum.kaydet() { await bitir() } } }
                Button("Kaydetmeden kapat", role: .destructive) { Task { await bitir() } }
                Button("Vazgeç", role: .cancel) {}
            }
        }
        .onAppear {
            oturum.kip = acilisKipi
            oturum.yukle()
            kitaplik.acildi(oge)
        }
    }

    // MARK: Üst araçlar

    @ToolbarContentBuilder private var ustAraclar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                if oturum.degisti {
                    if Ayarlar.paylasilan.otomatikKaydet { Task { if await oturum.kaydet() { await bitir() } } }
                    else { kapatmaSor = true }
                } else {
                    Task { await bitir() }
                }
            } label: { Image(systemName: "chevron.down") }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { oturum.geriAl() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!oturum.geriAlinabilir)
            Button { oturum.yinele() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!oturum.yinelenebilir)
            Button { oturum.pdfView?.findInteraction.presentFindNavigator(showingReplace: false) } label: {
                Image(systemName: "magnifyingglass")
            }
            Menu {
                Button { paylas() } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                Button { paylas(duzlestir: true) } label: { Label("Düzleştirerek paylaş", systemImage: "square.3.layers.3d.down.right") }
                Button { yazdir() } label: { Label("Yazdır", systemImage: "printer") }
                Divider()
                Button { Task { _ = await oturum.kaydet() } } label: { Label("Kaydet", systemImage: "square.and.arrow.down") }
                    .disabled(!oturum.degisti)
                Button { surumlerAcik = true } label: { Label("Önceki sürümler", systemImage: "clock.arrow.circlepath") }
                Divider()
                Button { kucukResimlerAcik.toggle() } label: { Label("Küçük resimler", systemImage: "sidebar.left") }
                Picker("Görünüm", selection: $oturum.gorunumKipi) {
                    Text("Tek sayfa").tag(PDFDisplayMode.singlePage)
                    Text("Sürekli").tag(PDFDisplayMode.singlePageContinuous)
                    Text("İki sayfa").tag(PDFDisplayMode.twoUpContinuous)
                }
                Toggle("Yatay kaydırma", isOn: $oturum.yatayKaydirma)
                Picker("Okuma rengi", selection: $oturum.okumaRengi) {
                    ForEach(BelgeOturumu.OkumaRengi.allCases) { Text($0.ad).tag($0) }
                }
                Divider()
                Menu {
                    ForEach(AracKatalogu.pdfAraclari) { a in
                        Button { aracAc(a) } label: { Label(a.ad, systemImage: a.simge) }
                    }
                } label: { Label("Araçla aç", systemImage: "wrench.and.screwdriver") }
                Button { bilgiAcik = true } label: { Label("Belge bilgisi", systemImage: "info.circle") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    // MARK: Parçalar

    private var kipSecici: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BelgeKipi.allCases) { k in
                    Button {
                        withAnimation(.snappy) {
                            oturum.dokunusIsleyici = nil
                            oturum.kip = k
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: k.simge).font(.system(size: 17))
                            Text(k.ad).font(.caption2).lineLimit(1)
                        }
                        .frame(minWidth: 64)
                        .padding(.vertical, 6).padding(.horizontal, 4)
                        .foregroundStyle(oturum.kip == k ? Tema.vurgu : .secondary)
                        .background(oturum.kip == k ? Tema.vurgu.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder private var okumaRengiKatmani: some View {
        switch oturum.okumaRengi {
        case .normal: EmptyView()
        case .sepya: Color(red: 1, green: 0.93, blue: 0.80).blendMode(.multiply).allowsHitTesting(false)
        case .gece: Color.white.blendMode(.difference).allowsHitTesting(false)
        }
    }

    private var sayfaGostergesi: some View {
        Text("\(oturum.seciliSayfa + 1) / \(oturum.belge?.pageCount ?? 0)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
    }

    private var parolaEkrani: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Bu belge parola korumalı").font(.headline)
            SecureField("Parola", text: $parolaMetni)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                .onSubmit(kilidiAc)
            Button("Aç", action: kilidiAc).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Eylemler

    private func kilidiAc() {
        if !oturum.kilidiAc(parolaMetni) { oturum.ileti = Ileti(KagitHata.parolaYanlis) }
    }

    private func bitir() async {
        kitaplik.acildi(oge, sayfa: oturum.seciliSayfa)
        await kitaplik.tara()
        kapat()
    }

    private func paylas(duzlestir: Bool = false) {
        do {
            if !duzlestir && !oturum.degisti && oturum.parola == nil {
                paylasilacak = [oge.url]
            } else {
                paylasilacak = [try oturum.kopyaYaz(secenekler: KayitSecenekleri(aciklamalariGom: duzlestir))]
            }
        } catch { oturum.ileti = Ileti(error) }
    }

    private func yazdir() {
        guard let veri = try? oturum.veriAl() else { return }
        let bilgi = UIPrintInfo(dictionary: nil)
        bilgi.jobName = oge.ad
        bilgi.outputType = .general
        let y = UIPrintInteractionController.shared
        y.printInfo = bilgi
        y.printingItem = veri
        y.present(animated: true)
    }

    private func aracAc(_ a: Arac) {
        Task {
            if oturum.degisti { _ = await oturum.kaydet() }
            kapat()
            try? await Task.sleep(for: .milliseconds(350))
            yon.aracAc(a, girdiler: [oge.url])
        }
    }
}

/// Kip araç çubuğu dağıtıcısı. Her kipin görünümü kendi dosyasındadır.
struct KipCubugu: View {
    let oturum: BelgeOturumu

    var body: some View {
        Group {
            switch oturum.kip {
            case .oku: OkumaCubugu(oturum: oturum)
            case .isaretle: IsaretleCubugu(oturum: oturum)
            case .duzenle: DuzenleCubugu(oturum: oturum)
            case .imzala: ImzalaCubugu(oturum: oturum)
            case .sayfalar: EmptyView()
            case .ogretmen: OgretmenCubugu(oturum: oturum)
            case .yapay: YapayZekaCubugu(oturum: oturum)
            }
        }
        .background(.bar)
    }
}

/// Okuma kipi: sayfa gezinme ve yakınlaştırma.
struct OkumaCubugu: View {
    let oturum: BelgeOturumu
    @State private var sayfaSor = false
    @State private var sayfaMetni = ""

    var body: some View {
        HStack(spacing: 22) {
            Button { oturum.pdfView?.goToFirstPage(nil) } label: { Image(systemName: "backward.end") }
            Button { oturum.pdfView?.goToPreviousPage(nil) } label: { Image(systemName: "chevron.left") }
            Button { sayfaSor = true } label: {
                Text("Sayfa \(oturum.seciliSayfa + 1)").font(.callout.monospacedDigit())
            }
            Button { oturum.pdfView?.goToNextPage(nil) } label: { Image(systemName: "chevron.right") }
            Button { oturum.pdfView?.goToLastPage(nil) } label: { Image(systemName: "forward.end") }
            Spacer()
            Button { if let v = oturum.pdfView { v.scaleFactor = v.scaleFactorForSizeToFit } } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .alert("Sayfaya git", isPresented: $sayfaSor) {
            TextField("Sayfa numarası", text: $sayfaMetni).keyboardType(.numberPad)
            Button("Git") {
                if let n = Int(sayfaMetni), let s = oturum.belge?.page(at: n - 1) { oturum.pdfView?.go(to: s) }
                sayfaMetni = ""
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

/// Sol kenar küçük resim şeridi.
struct KucukResimSeridi: View {
    let oturum: BelgeOturumu

    var body: some View {
        ScrollViewReader { kaydir in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(0..<(oturum.belge?.pageCount ?? 0), id: \.self) { i in
                        Button {
                            if let s = oturum.belge?.page(at: i) { oturum.pdfView?.go(to: s) }
                        } label: {
                            VStack(spacing: 2) {
                                SayfaKucukResmi(oturum: oturum, indeks: i, genislik: 72)
                                    .overlay(RoundedRectangle(cornerRadius: 2)
                                        .stroke(i == oturum.seciliSayfa ? Tema.vurgu : .clear, lineWidth: 2))
                                Text("\(i + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: oturum.seciliSayfa) { _, i in withAnimation { kaydir.scrollTo(i, anchor: .center) } }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Oturumdaki belgenin bir sayfasının küçük resmi (ana iş parçacığında, küçük boyutta).
struct SayfaKucukResmi: View {
    let oturum: BelgeOturumu
    let indeks: Int
    var genislik: CGFloat = 80
    @State private var resim: UIImage?

    var body: some View {
        Group {
            if let resim {
                Image(uiImage: resim).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color(.secondarySystemBackground)).aspectRatio(0.707, contentMode: .fit)
            }
        }
        .frame(width: genislik)
        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
        .task(id: "\(indeks)-\(oturum.belge.map { ObjectIdentifier($0).hashValue } ?? 0)-\(oturum.geriAlinabilir)") {
            guard let s = oturum.belge?.page(at: indeks) else { return }
            resim = s.thumbnail(of: CGSize(width: genislik * 2, height: genislik * 2.9), for: .cropBox)
        }
    }
}

/// İşlem sürerken gösterilen yarı saydam katman.
struct CalisiyorKatmani: View {
    let metin: String
    var oran: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                if let oran { ProgressView(value: oran).frame(width: 160) } else { ProgressView() }
                Text(metin).font(.callout)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Belge bilgisi: sayfa sayısı, boyut, üst veri.
struct BelgeBilgisi: View {
    let oturum: BelgeOturumu
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            Form {
                let b = oturum.belge
                let oz = b?.documentAttributes ?? [:]
                Section("Dosya") {
                    LabeledContent("Ad", value: oturum.oge.tamAd)
                    LabeledContent("Boyut", value: BicimYardimci.boyut(oturum.oge.boyut))
                    LabeledContent("Sayfa", value: "\(b?.pageCount ?? 0)")
                    LabeledContent("Şifreli", value: (b?.isEncrypted ?? false) ? "Evet" : "Hayır")
                    if let s = b?.page(at: 0)?.bounds(for: .mediaBox).size {
                        LabeledContent("Sayfa boyutu", value: "\(Int(s.width / 72 * 25.4)) × \(Int(s.height / 72 * 25.4)) mm")
                    }
                }
                Section("Üst veri") {
                    ForEach([(PDFDocumentAttribute.titleAttribute, "Başlık"), (.authorAttribute, "Yazar"),
                             (.subjectAttribute, "Konu"), (.creatorAttribute, "Oluşturan"), (.producerAttribute, "Üretici")], id: \.0) { anahtar, ad in
                        if let d = oz[anahtar] as? String, !d.isEmpty { LabeledContent(ad, value: d) }
                    }
                    if let t = oz[PDFDocumentAttribute.creationDateAttribute] as? Date {
                        LabeledContent("Oluşturma", value: t.formatted())
                    }
                }
            }
            .navigationTitle("Belge bilgisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
        }
    }
}

/// Önceki sürümlere dönüş.
struct SurumlerSayfasi: View {
    let oturum: BelgeOturumu
    @Environment(\.dismiss) private var kapat
    @State private var surumler: [(url: URL, tarih: Date)] = []

    var body: some View {
        NavigationStack {
            List {
                if surumler.isEmpty {
                    Text("Bu belge Kâğıt'ta henüz kaydedilmedi; önceki sürüm yok.").foregroundStyle(.secondary)
                }
                ForEach(surumler, id: \.url) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.tarih.formatted(date: .abbreviated, time: .standard))
                            Text(BicimYardimci.boyut(Int64((try? s.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Geri yükle") {
                            do {
                                try SurumDeposu.geriYukle(s.url, oturum.url)
                                if let v = try? Data(contentsOf: oturum.url) { try oturum.belgeyiDegistir(v, ad: "Sürüm") }
                                oturum.degisti = false
                                kapat()
                            } catch { oturum.ileti = Ileti(error) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Önceki sürümler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
            .onAppear { surumler = SurumDeposu.surumler(oturum.url) }
        }
    }
}
