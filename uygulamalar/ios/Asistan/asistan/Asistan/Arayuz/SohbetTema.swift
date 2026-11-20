import SwiftUI
import Observation

/// Sohbet ekranı renk paleti (açık ve koyu mod için ayrı tutulur). Renkler 6 haneli onaltılık.
nonisolated struct SohbetPaleti: Codable, Equatable, Sendable {
    var zemin: String
    var zemin2: String
    var desen: Bool
    var kullaniciBalon: String
    var kullaniciYazi: String
    var asistanBalon: String
    var asistanYazi: String
    var ikincil: String
    var dugme: String
    var cizgi: String

    var renkler: [String] { [zemin, zemin2, kullaniciBalon, kullaniciYazi, asistanBalon, asistanYazi, ikincil, dugme, cizgi] }
}

/// Sohbet ekranının bütün değiştirilebilir görünümü: renkler, balon biçimi, yazı tipleri, üst/alt çubuk stili.
nonisolated struct SohbetTemasi: Codable, Equatable, Sendable {
    enum YaziTipi: String, Codable, CaseIterable, Sendable { case serif = "Tırnaklı", duz = "Düz", yuvarlak = "Yuvarlak", mono = "Eş aralıklı" }
    enum GirisStili: String, Codable, CaseIterable, Sendable { case tekKutu = "Tek kutu", ayrik = "Ayrık düğmeler" }
    enum MenuSimgesi: String, Codable, CaseIterable, Sendable { case cizgiler = "Çizgiler", geri = "Geri oku" }

    var ad: String
    var acik: SohbetPaleti
    var koyu: SohbetPaleti
    var asistanBalonlu: Bool
    var kuyruk: Bool
    var kose: Double
    var asistanYaziTipi: YaziTipi
    var kullaniciYaziTipi: YaziTipi
    var saat: Bool
    var modelAdi: Bool
    var tarihRozeti: Bool
    var dugmeKenarlik: Bool
    var baslik: Bool
    var giris: GirisStili
    var menu: MenuSimgesi
    /// Son yanıtın altındaki eylem satırı (kopyala, sesli oku, yeniden üret, paylaş). Eski profillerde alan yok:
    /// isteğe bağlı tutulur ki çözülsün; yokken açık sayılır (`eylemSatiri`).
    var eylemSatiriAcik: Bool? = nil
    /// Yanıt altındaki beğen/beğenme düğmeleri. Eski profillerde alan yok: isteğe bağlı, yokken açık (`geriBildirim`).
    var geriBildirimAcik: Bool? = nil

    /// Eylem satırı görünsün mü (kayıtlı değer yoksa açık).
    var eylemSatiri: Bool {
        get { eylemSatiriAcik ?? true }
        set { eylemSatiriAcik = newValue }
    }
    /// Beğeni düğmeleri görünsün mü (kayıtlı değer yoksa açık).
    var geriBildirim: Bool {
        get { geriBildirimAcik ?? true }
        set { geriBildirimAcik = newValue }
    }

    func palet(_ koyuMod: Bool) -> SohbetPaleti { koyuMod ? koyu : acik }

    func gecerli() -> Bool {
        let hex = (acik.renkler + koyu.renkler).allSatisfy { $0.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }
        return hex && kose.isFinite && (4...28).contains(kose) && ad.count <= 40
    }

    /// Claude uygulaması: kırık beyaz zemin, gri kullanıcı balonu, balonsuz tırnaklı yanıt, siyah kenarlıklı düğmeler.
    static let claude = SohbetTemasi(
        ad: "Claude",
        acik: .init(zemin: "FAF9F5", zemin2: "FAF9F5", desen: false, kullaniciBalon: "F0EEE6", kullaniciYazi: "141413", asistanBalon: "FFFFFF",
                    asistanYazi: "141413", ikincil: "87867F", dugme: "FAF9F5", cizgi: "141413"),
        koyu: .init(zemin: "262624", zemin2: "262624", desen: false, kullaniciBalon: "141413", kullaniciYazi: "F5F4EE", asistanBalon: "30302E",
                    asistanYazi: "F5F4EE", ikincil: "9C9A92", dugme: "30302E", cizgi: "E8E6DC"),
        asistanBalonlu: false, kuyruk: false, kose: 22, asistanYaziTipi: .serif, kullaniciYaziTipi: .duz,
        saat: false, modelAdi: true, tarihRozeti: false, dugmeKenarlik: true, baslik: false, giris: .tekKutu, menu: .cizgiler)

    /// Karma (varsayılan, 20 Eki 2026): Claude'un kırık beyaz zemini, turuncu vurgusu, tek kutu girişi ve çizgili menüsü;
    /// Telegram'ın kuyruklu kart balonları (asistan yanıtı da kart), düz yazı tipi ve saat damgası. Desen ve tarih rozeti yok.
    static let karma = SohbetTemasi(
        ad: "Karma",
        acik: .init(zemin: "FAF9F5", zemin2: "FAF9F5", desen: false, kullaniciBalon: "EDE9DE", kullaniciYazi: "141413", asistanBalon: "FFFFFF",
                    asistanYazi: "141413", ikincil: "87867F", dugme: "FAF9F5", cizgi: "141413"),
        koyu: .init(zemin: "262624", zemin2: "262624", desen: false, kullaniciBalon: "3D3B36", kullaniciYazi: "F5F4EE", asistanBalon: "30302E",
                    asistanYazi: "F5F4EE", ikincil: "9C9A92", dugme: "30302E", cizgi: "E8E6DC"),
        asistanBalonlu: true, kuyruk: true, kose: 18, asistanYaziTipi: .duz, kullaniciYaziTipi: .duz,
        saat: true, modelAdi: false, tarihRozeti: false, dugmeKenarlik: true, baslik: false, giris: .tekKutu, menu: .cizgiler,
        eylemSatiriAcik: false, geriBildirimAcik: false)   // Telegram gibi temiz kart: yalnız metin + saat; eylemler uzun basma menüsünde

    static let telegram = SohbetTemasi(
        ad: "Telegram",
        acik: .init(zemin: "D6DE8F", zemin2: "7DB878", desen: true, kullaniciBalon: "EDFCDB", kullaniciYazi: "000000", asistanBalon: "FFFFFF",
                    asistanYazi: "000000", ikincil: "737373", dugme: "FFFFFF", cizgi: "1A1A1A"),
        koyu: .init(zemin: "212B21", zemin2: "121F17", desen: true, kullaniciBalon: "2B5C45", kullaniciYazi: "FFFFFF", asistanBalon: "292929",
                    asistanYazi: "FFFFFF", ikincil: "9E9E9E", dugme: "1F1F1F", cizgi: "BFBFBF"),
        asistanBalonlu: true, kuyruk: true, kose: 18, asistanYaziTipi: .duz, kullaniciYaziTipi: .duz,
        saat: true, modelAdi: true, tarihRozeti: true, dugmeKenarlik: true, baslik: true, giris: .ayrik, menu: .geri)

    static let sade = SohbetTemasi(
        ad: "Sade",
        acik: .init(zemin: "FFFFFF", zemin2: "FFFFFF", desen: false, kullaniciBalon: "F2F2F7", kullaniciYazi: "000000", asistanBalon: "F2F2F7",
                    asistanYazi: "000000", ikincil: "8E8E93", dugme: "FFFFFF", cizgi: "C7C7CC"),
        koyu: .init(zemin: "000000", zemin2: "000000", desen: false, kullaniciBalon: "1C1C1E", kullaniciYazi: "FFFFFF", asistanBalon: "1C1C1E",
                    asistanYazi: "FFFFFF", ikincil: "8E8E93", dugme: "1C1C1E", cizgi: "3A3A3C"),
        asistanBalonlu: false, kuyruk: false, kose: 18, asistanYaziTipi: .duz, kullaniciYaziTipi: .duz,
        saat: false, modelAdi: true, tarihRozeti: false, dugmeKenarlik: false, baslik: false, giris: .tekKutu, menu: .cizgiler)

    static let gece = SohbetTemasi(
        ad: "Gece",
        acik: .init(zemin: "1B1F2A", zemin2: "2A2140", desen: false, kullaniciBalon: "3B3370", kullaniciYazi: "FFFFFF", asistanBalon: "262B38",
                    asistanYazi: "ECECF1", ikincil: "9A9DB0", dugme: "262B38", cizgi: "6D6F85"),
        koyu: .init(zemin: "0E1016", zemin2: "1A1430", desen: false, kullaniciBalon: "3B3370", kullaniciYazi: "FFFFFF", asistanBalon: "1C2030",
                    asistanYazi: "ECECF1", ikincil: "8D90A3", dugme: "1C2030", cizgi: "5A5C70"),
        asistanBalonlu: true, kuyruk: false, kose: 20, asistanYaziTipi: .yuvarlak, kullaniciYaziTipi: .yuvarlak,
        saat: true, modelAdi: true, tarihRozeti: true, dugmeKenarlik: true, baslik: true, giris: .ayrik, menu: .cizgiler)

    static let hazirlar: [SohbetTemasi] = [.karma, .claude, .telegram, .sade, .gece]
}

extension SohbetTemasi.YaziTipi {
    var tasarim: Font.Design {
        switch self { case .serif: .serif; case .duz: .default; case .yuvarlak: .rounded; case .mono: .monospaced }
    }
}

/// Etkin sohbet teması; görünümler buradan okur (değişince ekran kendiliğinden yenilenir).
@Observable
final class SohbetTemaDeposu {
    static let ortak = SohbetTemaDeposu()
    var tema: SohbetTemasi = .karma
}

/// Görünümlerin kullandığı renk erişimi (etkin temanın açık/koyu paletinden).
enum SohbetRenk {
    private static func p(_ koyu: Bool) -> SohbetPaleti { SohbetTemaDeposu.ortak.tema.palet(koyu) }
    static func gelenBalon(_ koyu: Bool) -> Color { Color(hex: p(koyu).asistanBalon) }
    static func gidenBalon(_ koyu: Bool) -> Color { Color(hex: p(koyu).kullaniciBalon) }
    static func metin(_ koyu: Bool) -> Color { Color(hex: p(koyu).asistanYazi) }
    static func kullaniciMetni(_ koyu: Bool) -> Color { Color(hex: p(koyu).kullaniciYazi) }
    static func ikincil(_ koyu: Bool) -> Color { Color(hex: p(koyu).ikincil) }
    static func dugmeZemini(_ koyu: Bool) -> Color { Color(hex: p(koyu).dugme).opacity(0.94) }
    static func cizgi(_ koyu: Bool) -> Color { Color(hex: p(koyu).cizgi) }
}

/// Temaya göre zeminli ve (açıksa) kenarlıklı düğme biçimi (daire, hap, yuvarlak dikdörtgen).
struct TemaDugmeZemini<S: Shape>: ViewModifier {
    let sekil: S
    @Environment(\.colorScheme) private var sema
    func body(content: Content) -> some View {
        content
            .background(sekil.fill(SohbetRenk.dugmeZemini(sema == .dark)))
            .overlay(sekil.stroke(SohbetRenk.cizgi(sema == .dark).opacity(SohbetTemaDeposu.ortak.tema.dugmeKenarlik ? 1 : 0), lineWidth: 1))
    }
}

extension View {
    func temaDugmesi<S: Shape>(_ sekil: S) -> some View { modifier(TemaDugmeZemini(sekil: sekil)) }
}

/// Sohbet zemini: düz renk ya da gradyan, istenirse sönük doodle deseni.
struct SohbetZemini: View {
    @Environment(\.colorScheme) private var sema
    private static let simgeler = ["pawprint.fill", "leaf.fill", "star.fill", "heart.fill", "cloud.fill", "moon.fill", "flame.fill", "gift.fill", "bubble.left.fill",
                                   "music.note", "camera.fill", "bolt.fill", "balloon.fill", "birthday.cake.fill", "cup.and.saucer.fill", "fork.knife", "umbrella.fill",
                                   "paperplane.fill", "gamecontroller.fill", "tortoise.fill", "hare.fill", "bird.fill", "fish.fill", "ant.fill", "lightbulb.fill"]

    var body: some View {
        let koyu = sema == .dark
        let p = SohbetTemaDeposu.ortak.tema.palet(koyu)
        ZStack {
            LinearGradient(colors: [Color(hex: p.zemin), Color(hex: p.zemin2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if p.desen {
                Canvas { ctx, boyut in
                    let adim: CGFloat = 76
                    let renk = Color(hex: p.ikincil).opacity(koyu ? 0.10 : 0.16)
                    var satir = 0
                    var y: CGFloat = 20
                    while y < boyut.height + adim {
                        var x: CGFloat = satir % 2 == 0 ? 20 : 20 + adim / 2
                        var sutun = 0
                        while x < boyut.width + adim {
                            let n = (satir * 7 + sutun * 13) % Self.simgeler.count
                            let aci = Double((satir * 31 + sutun * 17) % 60) - 30
                            var c = ctx
                            c.translateBy(x: x, y: y); c.rotate(by: .degrees(aci))
                            c.draw(Text(Image(systemName: Self.simgeler[n])).font(.system(size: 26, weight: .light)).foregroundStyle(renk), at: .zero)
                            x += adim; sutun += 1
                        }
                        y += adim * 0.8; satir += 1
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Mesaj balonu; kuyruk açıksa giden mesajda sağ altta, gelende sol altta (şeklin dışına taşar).
nonisolated struct BalonSekli: Shape {
    let giden: Bool
    var kose: CGFloat = 18
    var kuyruk = true
    func path(in r: CGRect) -> Path {
        guard kuyruk else { return Path(roundedRect: r, cornerRadius: min(kose, r.height / 2), style: .continuous) }
        let c = min(kose, r.height / 2), t: CGFloat = 7, w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: c, y: 0))
        p.addLine(to: CGPoint(x: w - c, y: 0))
        p.addArc(center: CGPoint(x: w - c, y: c), radius: c, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: h - c))
        p.addArc(center: CGPoint(x: w - c, y: h - c), radius: c, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 4, y: h))
        p.addQuadCurve(to: CGPoint(x: -t, y: h), control: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - 9), control: CGPoint(x: -1, y: h - 1))
        p.addLine(to: CGPoint(x: 0, y: c))
        p.addArc(center: CGPoint(x: c, y: c), radius: c, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return giden ? p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)) : p
    }
}

/// Gün ayırıcı: siyah hap, beyaz kalın yazı ("8 Ekim", "Bugün").
struct TarihRozeti: View {
    let tarih: Date
    static func metin(_ t: Date, simdi: Date = .now) -> String {
        let t0 = Calendar.current
        if t0.isDate(t, inSameDayAs: simdi) { return "Bugün" }
        if let dun = t0.date(byAdding: .day, value: -1, to: simdi), t0.isDate(t, inSameDayAs: dun) { return "Dün" }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = t0.isDate(t, equalTo: simdi, toGranularity: .year) ? "d MMMM" : "d MMMM yyyy"
        return f.string(from: t)
    }
    var body: some View {
        // .callout varsayılan boyutta 16 punto; Dynamic Type ile birlikte büyür.
        Text(Self.metin(tarih)).font(.callout.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7).background(Color.black, in: Capsule())
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("tarih-rozeti")
    }
}
