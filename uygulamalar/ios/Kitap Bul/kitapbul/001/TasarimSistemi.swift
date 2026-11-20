import SwiftUI

/// Arayüz tasarım sistemi: renkli kartlar, canlı gradyan zeminler, istatistik kartları,
/// kenardan kaydırarak sekme değiştirme ve efekt/sade mod ayarları.
enum Tasarim {
    static let sadeModAnahtari = "simpleMode"
    static let kenarKaydirmaAnahtari = "edgeSwipeTabs"
    static let efektAnahtari = "visualEffectsEnabled"
}

// MARK: - Sekme değiştirme ortam değeri

extension EnvironmentValues {
    /// +1 sonraki sekme, -1 önceki sekme (MainTabView sağlar)
    @Entry var sekmeDegistir: (Int) -> Void = { _ in }
    /// Kenar şeritleri bu görünümün üstünde zaten var; içteki ikinci uygulama etkisiz kalır
    /// (aksi hâlde tek kaydırma iki sekme atlatırdı).
    @Entry var kenarSeridiVar = false
}

/// Ekranın sol/sağ kenarından yatay kaydırma ile önceki/sonraki sekmeye geçiş.
/// Yalnız kenardaki 18 pt'lik şeritte çalışır: listelerdeki kaydırma düğmeleri ve
/// raflardaki yatay kaydırmayla çakışmaz. Sekme çubuğu her zaman ayrıca kullanılabilir.
private struct KenardanSekmeKaydirma: ViewModifier {
    @Environment(\.sekmeDegistir) private var sekmeDegistir
    @AppStorage(Tasarim.kenarKaydirmaAnahtari) private var acik = false
    @State private var tetik = 0

    @Environment(\.kenarSeridiVar) private var seritVar

    @ViewBuilder
    func body(content: Content) -> some View {
        if seritVar {
            content
        } else {
            content
                .overlay(alignment: .leading) { serit(yon: -1) }
                .overlay(alignment: .trailing) { serit(yon: 1) }
                .sensoryFeedback(.selection, trigger: tetik)
                .environment(\.kenarSeridiVar, true)
        }
    }

    @ViewBuilder
    private func serit(yon: Int) -> some View {
        if acik {
            Color.clear
                .frame(width: 18)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { deger in
                            let dx = deger.translation.width
                            guard abs(dx) > 60, abs(dx) > abs(deger.translation.height) * 1.5 else { return }
                            // Sağ kenardan sola çekmek → sonraki; sol kenardan sağa çekmek → önceki
                            if yon == 1 && dx < 0 { tetik += 1; sekmeDegistir(1) }
                            if yon == -1 && dx > 0 { tetik += 1; sekmeDegistir(-1) }
                        }
                )
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func kenardanSekmeKaydir() -> some View { modifier(KenardanSekmeKaydirma()) }
}

// MARK: - Okunur alt kaydırma kenarı

/// Alt sekme çubuğunun yumuşak kenar efekti görünür metni zemin rengine solduruyordu.
/// Metin kendi kontrastını korur; kaydırma ve sekme çubuğu normal çalışmaya devam eder.
private struct OkunurAltKaydirmaKenari: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(visionOS)
        content
#else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            content
        }
#endif
    }
}

extension View {
    func okunurAltKaydirmaKenari() -> some View { modifier(OkunurAltKaydirmaKenari()) }
}

// MARK: - Canlı gradyan zemin

/// Yavaşça dalgalanan renkli ağ gradyanı. Hareketi Azalt, efektlerin kapalı olması, arka plan,
/// Düşük Güç Modu ya da ekran dışında kalma durumunda durağan tek kare çizilir; aksi hâlde 10 kare/sn.
struct CanliGradyan: View {
    var renkler: [Color] = [KitapTema.ana, KitapTema.foto, KitapTema.amazon]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Tasarim.efektAnahtari) private var efektler = true
    @State private var gorunur = true
    @State private var dusukGuc = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Animasyonun çalışıp çalışmayacağı; saf karar, testlenebilir.
    nonisolated static func animasyonluMu(azaltilmisHareket: Bool, efektler: Bool, etkin: Bool,
                                          dusukGuc: Bool, gorunur: Bool) -> Bool {
        !azaltilmisHareket && efektler && etkin && !dusukGuc && gorunur
    }

    var body: some View {
        Group {
            if Self.animasyonluMu(azaltilmisHareket: reduceMotion, efektler: efektler, etkin: scenePhase == .active,
                                  dusukGuc: dusukGuc, gorunur: gorunur) {
                TimelineView(.animation(minimumInterval: 1 / 10)) { zaman in
                    ag(t: zaman.date.timeIntervalSinceReferenceDate)
                }
            } else {
                ag(t: 0)
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { gorunur = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            dusukGuc = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func ag(t: Double) -> some View {
        let a = Float(sin(t * 0.35) * 0.18)
        let b = Float(cos(t * 0.28) * 0.18)
        let r = renkler + renkler
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + a, 0.5 + b], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                r[0], r[1], r[2],
                r[2].opacity(0.9), r[0].mix(with: .white, by: 0.25), r[1],
                r[1], r[2], r[0]
            ]
        )
    }
}

// MARK: - Tembel olmayan ızgara

/// Eşit sütunlu, tembel olmayan ızgara (birkaç düzine hücrelik kısa içerik için).
/// LazyVGrid, yazı büyüyünce ekranın altına itilen hücreleri erişilebilirlik ağacından
/// düşürüyordu; erişilebilirlik denetimi bunları "Dynamic Type kısmen desteklenmiyor" sayıyordu.
/// Burada her hücre her boyutta yerleşimde kalır. Sütun sayısı sabit verilir (`sutun`) ya da
/// en küçük hücre genişliğine göre hesaplanır (`GridItem(.adaptive)` gibi).
struct EsitSutunIzgara: Layout {
    var sutun: Int? = nil
    var enKucukGenislik: CGFloat = 100
    var enBuyukGenislik: CGFloat = .infinity
    var yatayAralik: CGFloat = 10
    var dikeyAralik: CGFloat = 10

    /// Verilen genişlikte sütun sayısı ve hücre genişliği.
    func sutunOlcusu(_ genislik: CGFloat?) -> (sayi: Int, hucre: CGFloat) {
        // Sınırsız öneride (ör. ideal boyut ölçümü) hücreler en küçük genişlikte dizilir.
        let toplam = genislik.flatMap { $0.isFinite ? $0 : nil } ?? enKucukGenislik * CGFloat(sutun ?? 1)
        let sayi = max(1, sutun ?? Int((toplam + yatayAralik) / (enKucukGenislik + yatayAralik)))
        let hucre = max(0, (toplam - yatayAralik * CGFloat(sayi - 1)) / CGFloat(sayi))
        return (sayi, min(hucre, enBuyukGenislik))
    }

    private func satirYukseklikleri(_ subviews: Subviews, sayi: Int, hucre: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: sayi).map { bas in
            subviews[bas..<min(bas + sayi, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: hucre, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sayi, hucre) = sutunOlcusu(proposal.width)
        let satirlar = satirYukseklikleri(subviews, sayi: sayi, hucre: hucre)
        let yukseklik = satirlar.reduce(0, +) + dikeyAralik * CGFloat(max(0, satirlar.count - 1))
        let genislik = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? (hucre * CGFloat(sayi) + yatayAralik * CGFloat(sayi - 1))
        return CGSize(width: genislik, height: yukseklik)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sayi, hucre) = sutunOlcusu(bounds.width)
        let satirlar = satirYukseklikleri(subviews, sayi: sayi, hucre: hucre)
        // Hücreler LazyVGrid'deki gibi ortalanır; enBuyukGenislik varsa ızgara da ortalanır.
        let doluGenislik = hucre * CGFloat(sayi) + yatayAralik * CGFloat(sayi - 1)
        let solBosluk = max(0, (bounds.width - doluGenislik) / 2)
        var y = bounds.minY
        for (satir, yukseklik) in satirlar.enumerated() {
            for sira in 0..<sayi {
                let indeks = satir * sayi + sira
                guard indeks < subviews.count else { break }
                let x = bounds.minX + solBosluk + CGFloat(sira) * (hucre + yatayAralik)
                subviews[indeks].place(at: CGPoint(x: x + hucre / 2, y: y + yukseklik / 2), anchor: .center,
                                       proposal: ProposedViewSize(width: hucre, height: nil))
            }
            y += yukseklik + dikeyAralik
        }
    }
}

// MARK: - Renkli ikonlu başlık

/// Başlık etiketi: ikon renkli, metin ana renkte (kontrast). Ana Sayfa bölüm başlıkları,
/// Ayarlar bölüm başlıkları ve uyarı metinleri bu stili kullanır; renk tek başına anlam taşımaz.
struct RenkliIkonEtiketi: LabelStyle {
    let renk: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(renk)
            configuration.title.foregroundStyle(Color.primary)
        }
    }
}

// MARK: - Renkli kart

/// Gradyanlı, ikonlu gezinme kartı (ayarlar, araçlar, ana sayfa bölümleri).
struct RenkliKart: View {
    let baslik: String
    let altBaslik: String
    let ikon: String
    let renk: Color
    var rozet: String? = nil

    @State private var belirdi = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.22), in: .rect(cornerRadius: 12))
                    .symbolEffect(.bounce, value: belirdi)
                Spacer()
                if let rozet {
                    Text(rozet)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white, in: .capsule)
                        .foregroundStyle(renk)
                }
            }
            Text(baslik)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(altBaslik)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(
            // Beyaz yazının kontrastı için koyulaştırılmış gradyan
            LinearGradient(colors: [renk.mix(with: .black, by: 0.55), renk.mix(with: .black, by: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
        .shadow(color: renk.opacity(0.3), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .symbolEffectsRemoved(reduceMotion || !effects)
        .onAppear { if !reduceMotion && effects { belirdi = true } }
    }
}

// MARK: - İstatistik kartı

struct IstatistikKarti: View {
    let deger: Int
    let baslik: String
    let ikon: String
    let renk: Color

    @State private var gosterilen = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Tasarim.efektAnahtari) private var effects = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: ikon)
                .font(.headline)
                .foregroundStyle(KitapTema.erisilebilirVurgu(renk, scheme: colorScheme))
                .symbolEffect(.bounce, value: deger)
            Text("\(gosterilen)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1)
                // Izgara büyük yazıda tek sütuna iner; küçültme yalnız çok basamaklı sayılar için
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText(value: Double(gosterilen)))
                .foregroundStyle(Color.primary)
            Text(baslik)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(renk.opacity(0.12), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(renk.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(baslik): \(deger)")
        .symbolEffectsRemoved(reduceMotion || !effects)
        .onAppear { sayac(deger) }
        .onChange(of: deger) { _, yeni in sayac(yeni) }
    }

    /// Sayı sıfırdan yukarı sayarak belirir (Hareketi Azalt'ta doğrudan).
    private func sayac(_ hedef: Int) {
        if reduceMotion || !effects {
            gosterilen = hedef
        } else {
            withAnimation(.spring(duration: 0.9)) { gosterilen = hedef }
        }
    }
}

// MARK: - Kaydırınca belirme efekti

private struct KitapKaydirmaEfekti: ViewModifier {
    var yatay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var efektler = true
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion || !efektler { content }
        else if yatay {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view.offset(x: phase.value * 4)
            }
        } else {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                view.offset(y: phase.value * 4)
            }
        }
    }
}

extension View {
    func kaydirmaEfekti() -> some View { modifier(KitapKaydirmaEfekti()) }
    func yatayKaydirmaEfekti() -> some View { modifier(KitapKaydirmaEfekti(yatay: true)) }
}

// MARK: - Kapak kartı (raflar)

struct RafKapagi: View {
    let kitap: CatalogBook
    @Environment(\.dynamicTypeSize) private var typeSize
    private var width: CGFloat { typeSize.isAccessibilitySize ? 200 : 104 }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let veri = kitap.coverData, let resim = CoverImageDecoder.thumbnail(from: veri, maxPixelSize: 600) {
                    Image(decorative: resim, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(KitapTema.kitapRengi(kitap.title).gradient)
                    Rectangle().fill(Color.black.opacity(0.45))
                    Text(kitap.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .padding(6)
                }
            }
            .frame(width: width, height: typeSize.isAccessibilitySize ? 190 : 150)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
            Text(kitap.title)
                .font(.caption.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .frame(width: width, alignment: .leading)
            Text(kitap.author)
                .font(.caption2)
                .foregroundStyle(KitapTema.ikincilMetin)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Boş durum

/// Boş durumdan çıkış yolu: "Filtreleri temizle (2)", "Kataloğa ekle" gibi.
struct BosDurumEylemi: Identifiable {
    let ad: String
    let ikon: String
    var kimlik: String? = nil
    let eylem: () -> Void
    var id: String { ad }
}

/// Kaydırılabilir, her yazı boyutunda sığan boş durum görünümü (sistem görünümü büyük
/// yazıda metni kırpıyordu). Eylem verilirse metnin altında düğme olarak gösterilir.
struct BosDurum: View {
    let baslik: String
    let aciklama: String
    let ikon: String
    var renk: Color = KitapTema.ana
    var eylemler: [BosDurumEylemi] = []
    /// Dekoratif ikon yazıyla büyür; gövde metnine bağlı olduğu için AX5'te ekranı doldurmaz.
    @ScaledMetric(relativeTo: .body) private var ikonBoyu: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: ikon)
                        .font(.system(size: ikonBoyu, weight: .semibold))
                        .foregroundStyle(renk)
                        .symbolEffect(.bounce, options: .nonRepeating, value: baslik)
                    Text(baslik)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(aciklama)
                        .font(.body)
                        .foregroundStyle(KitapTema.ikincilMetin)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Yalnız metin tek öğe olur; düğmeler ayrı ayrı erişilebilir kalır.
                .accessibilityElement(children: .combine)
                ForEach(eylemler) { eylem in
                    Button(action: eylem.eylem) {
                        Label(eylem.ad, systemImage: eylem.ikon)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kitapTonlu())
                    .frame(maxWidth: 420)
                    .accessibilityIdentifier(eylem.kimlik ?? eylem.ad)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Rozet ve çip

/// Renkli rozet: metin ana renkte (kontrast), ikon rozet renginde. Uzun metinde (konum gibi)
/// `satirSiniri` artırılırsa kırpılmak yerine alt satıra geçer.
struct Rozet: View {
    let metin: String
    let renk: Color
    var ikon: String? = nil
    /// `nil`: sınırsız satır.
    var satirSiniri: Int? = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let ikon { Image(systemName: ikon).foregroundStyle(renk).imageScale(.small).accessibilityHidden(true) }
            Text(metin).foregroundStyle(Color.primary)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(renk.opacity(0.14), in: tekSatir ? AnyShape(.capsule) : AnyShape(.rect(cornerRadius: 8)))
        .lineLimit(satirSiniri)
        .fixedSize(horizontal: false, vertical: !tekSatir)
    }

    private var tekSatir: Bool { satirSiniri == 1 }
}

/// Seçilebilir çip (durum süzgeci gibi): en az 44 pt yükseklik, seçili durum özelliği.
struct Cip: View {
    let ad: String
    let ikon: String
    let secili: Bool
    let renk: Color
    let eylem: () -> Void

    var body: some View {
        Button(action: eylem) {
            CipEtiketi(ad: ad, ikon: ikon, secili: secili, renk: renk)
        }
        .buttonStyle(.kitapSade)
        .accessibilityLabel(ad)
        .accessibilityAddTraits(secili ? [.isSelected] : [])
    }
}

struct CipEtiketi: View {
    let ad: String
    let ikon: String
    let secili: Bool
    let renk: Color
    @Environment(\.colorScheme) private var gorunum

    var body: some View {
        // Seçili değilken metin ana renkte, ikon koyulaştırılmış renkte (açık yeşil ikon açık zeminde
        // kontrast denetiminden geçmiyordu); seçiliyken beyaz yazı koyulaştırılmış zeminde durur.
        Label {
            Text(ad).foregroundStyle(secili ? Color.white : Color.primary)
        } icon: {
            Image(systemName: ikon).foregroundStyle(secili ? Color.white : KitapTema.erisilebilirVurgu(renk, scheme: gorunum))
        }
        .font(.footnote.weight(secili ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .background(secili ? renk.mix(with: .black, by: 0.35) : renk.opacity(0.12), in: .capsule)
        .overlay(Capsule().strokeBorder(renk.opacity(secili ? 0 : 0.35), lineWidth: 1))
    }
}

// Hareketi Azalt ve efekt tercihi tüm kapak geçişlerinde birlikte uygulanır.
private struct KitapZoomHedefi: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion || !effects { content } else { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
    }
}
private struct KitapZoomKaynagi: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace, !reduceMotion, effects { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}
extension View {
    func zoomHedefi(_ id: UUID, _ namespace: Namespace.ID) -> some View { modifier(KitapZoomHedefi(id: id, namespace: namespace)) }
    func zoomKaynagi(_ id: UUID, _ namespace: Namespace.ID?) -> some View { modifier(KitapZoomKaynagi(id: id, namespace: namespace)) }
}
