import SwiftUI

/// Kitap Bul'un merkezi renk teması. Tüm ekranlar renkleri buradan alır;
/// paleti değiştirmek uygulamanın tamamını değiştirir.
/// Kullanıcının seçtiği ana renk (Ayarlar › Görünüm).
enum TemaRengi: String, CaseIterable, Identifiable {
    case indigo = "İndigo", mavi = "Mavi", yesil = "Yeşil", turuncu = "Turuncu"
    case pembe = "Pembe", mor = "Mor", kirmizi = "Kırmızı", kahve = "Kahve"

    static let anahtar = "themeAccent"
    var id: String { rawValue }

    var renk: Color {
        switch self {
        case .indigo: .indigo
        case .mavi: .blue
        case .yesil: Color(red: 0.12, green: 0.55, blue: 0.30)
        case .turuncu: Color(red: 0.85, green: 0.40, blue: 0.05)
        case .pembe: .pink
        case .mor: .purple
        case .kirmizi: Color(red: 0.78, green: 0.12, blue: 0.16)
        case .kahve: .brown
        }
    }

    static var secili: TemaRengi { oku(.standard) }

    /// Kayıtlı seçimi okur; yoksa ya da bozuksa İndigo.
    static func oku(_ defaults: UserDefaults) -> TemaRengi {
        TemaRengi(rawValue: defaults.string(forKey: anahtar) ?? "") ?? .indigo
    }
}

/// Seçili ana renk için gözlemlenebilir tek kaynak. Kök görünüm yeniden kurulmadan (kimlik değişmeden)
/// renk değişir: `KitapTema.ana`'yı gövdesinde okuyan her görünüm bu nesneyi izler.
@MainActor @Observable
final class TemaDurumu {
    static let shared = TemaDurumu()

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var secili: TemaRengi
    var ana: Color { secili.renk }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        secili = TemaRengi.oku(defaults)
    }

    /// Kayıtlı seçim değiştiyse (Ayarlar, arşivden geri yükleme) durumu günceller.
    func yenile() {
        let yeni = TemaRengi.oku(defaults)
        if yeni != secili { secili = yeni }
    }
}

extension EnvironmentValues {
    /// Seçili ana renk; kök görünüm sağlar. Sıcak görünümler statik `KitapTema.ana` yerine bunu okur.
    @Entry var temaAna: Color = TemaRengi.indigo.renk
}

enum KitapTema {
    /// Açık zeminde doygun ikon/sekme renkleri metin için yeterince koyu olmalıdır.
    static func erisilebilirVurgu(_ renk: Color, scheme: ColorScheme) -> Color {
        renk.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.25 : 0.45)
    }
    /// İşlem düğmelerinin içindeki açıklamalar tint rengini soluk biçimde miras almaz.
    static let ikincilMetin = Color.primary.opacity(0.75)
    /// Ana renk kullanıcı seçimine bağlıdır; `TemaDurumu` gözlemlenebilir olduğundan gövdede okuyan
    /// görünümler, kök yeniden kurulmadan güncellenir.
    static var ana: Color { TemaDurumu.shared.ana }
    /// Beyaz yazılı dolu düğme zemini: her tema renginde, açık ve koyu modda yeterli kontrast
    /// için ana renk koyulaştırılır (koyu modda sistem renkleri açıldığından düz ana renk yetmiyordu).
    static var anaDolu: Color { ana.mix(with: .black, by: 0.35) }
    static let vurgu = Color.orange
    static let amazon = Color.teal
    static let foto = Color.purple
    static let toplu = Color.pink
    static let dosya = Color.blue
    static let basari = Color.green

    /// Kitap kartları için palet: her kitap, adına göre tutarlı bir renk alır.
    static let palet: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .mint, .red]

    /// Aynı ad her açılışta aynı rengi verir (hash yerine kararlı toplam kullanılır).
    static func kitapRengi(_ ad: String) -> Color {
        var toplam = 7
        for karakter in ad.unicodeScalars {
            toplam = (toplam &* 31 &+ Int(karakter.value)) & 0xFFFF
        }
        return palet[toplam % palet.count]
    }

    static var baslikGradyani: LinearGradient {
        LinearGradient(
            colors: [ana.opacity(0.14), amazon.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var kapakGradyani: LinearGradient {
        LinearGradient(
            colors: [ana, amazon],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Sayfa (sheet) vurgusu: sekmeye göre değişen sekme vurgusunu miras almaz, seçili ana renkten türer.
private struct SayfaVurgusu: ViewModifier {
    @Environment(\.temaAna) private var ana
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.tint(KitapTema.erisilebilirVurgu(ana, scheme: scheme))
    }
}

extension View {
    /// Sheet içeriğine sabit, erişilebilir ana renk vurgusu verir.
    func sayfaVurgusu() -> some View { modifier(SayfaVurgusu()) }
}

// MARK: - Ortak düğme stilleri (tepki veren tema)

/// Uygulama genelinde kullanılan düğme stili: basınca yumuşakça küçülür ve hafif
/// titreşim verir, Hareketi Azalt açıksa animasyon yapmaz, Dynamic Type ile büyür,
/// en az 44 pt dokunma alanı korur. Dört biçim: dolu, tonlu, kart, sade.
struct KitapButonStili: ButtonStyle {
    enum Bicim { case dolu, tonlu, kart, sade }

    /// `nil`: seçili ana renk (ortamdan).
    var renkSecimi: Color? = nil
    var bicim: Bicim = .tonlu
    var genis = false

    @Environment(\.temaAna) private var temaAna
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @AppStorage("scanHapticsEnabled") private var haptics = true

    /// Kendi zeminini çizen kartlar (örn. gradyanlı araç kartları) için `.sade`:
    /// yalnızca basma tepkisi verir, zemin/kenarlık eklemez.
    private var kendiZemini: Bool { bicim == .kart || bicim == .sade }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kendiZemini ? nil : .body.weight(.semibold))
            .padding(.horizontal, kendiZemini ? 0 : 16)
            .padding(.vertical, kendiZemini ? 0 : 11)
            .frame(minWidth: 44, maxWidth: genis ? .infinity : nil, minHeight: 44)
            .foregroundStyle(onRengi)
            .background(zemin, in: .rect(cornerRadius: bicim == .kart ? 16 : 12))
            .overlay {
                if bicim == .kart {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(renk.opacity(configuration.isPressed ? 0.6 : 0.25), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion && effects ? 0.96 : 1)
            .animation(reduceMotion || !effects ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, basili in basili && haptics }
            .contentShape(.rect(cornerRadius: bicim == .kart ? 16 : 12))
    }

    private var renk: Color { renkSecimi ?? temaAna }

    private var onRengi: Color {
        switch bicim {
        case .dolu: .white
        case .tonlu: .primary
        case .kart, .sade: .primary
        }
    }

    private var zemin: AnyShapeStyle {
        switch bicim {
        case .dolu: AnyShapeStyle(renk.gradient)
        case .tonlu: AnyShapeStyle(renk.opacity(0.14))
        case .kart: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        case .sade: AnyShapeStyle(.clear)
        }
    }
}

extension ButtonStyle where Self == KitapButonStili {
    /// Dolu, birincil eylem düğmesi (tam genişlik).
    static func kitapDolu(_ renk: Color? = nil) -> KitapButonStili {
        KitapButonStili(renkSecimi: renk, bicim: .dolu, genis: true)
    }

    /// Tonlu, ikincil eylem düğmesi.
    static func kitapTonlu(_ renk: Color? = nil) -> KitapButonStili {
        KitapButonStili(renkSecimi: renk, bicim: .tonlu)
    }

    /// Kart görünümlü düğme (işlem kartları, araç panelleri).
    static func kitapKart(_ renk: Color? = nil) -> KitapButonStili {
        KitapButonStili(renkSecimi: renk, bicim: .kart)
    }

    /// Zemini kendi çizen içerik için yalnızca basma tepkisi.
    static var kitapSade: KitapButonStili {
        KitapButonStili(bicim: .sade)
    }
}
