import LocalAuthentication
import SwiftUI

/// Kilit tetikleme süresi: arka plana alındıktan ne kadar sonra yeniden kimlik istenir.
enum KilitSuresi: Int, CaseIterable, Identifiable {
    case hemen = 0, birDakika = 60, besDakika = 300
    var id: Int { rawValue }
    var ad: String {
        switch self {
        case .hemen: "Hemen"
        case .birDakika: "1 dakika sonra"
        case .besDakika: "5 dakika sonra"
        }
    }
}

/// Face ID / cihaz parolası kilidinin durumu.
@Observable
final class KilitYoneticisi {
    static let paylasilan = KilitYoneticisi()

    var kilitli: Bool
    private(set) var dogruluyor = false
    private(set) var hata: String?
    private var arkaPlanZamani: Date?
    @ObservationIgnored private let d = UserDefaults.standard

    var sure: KilitSuresi {
        get { KilitSuresi(rawValue: d.integer(forKey: "kilit.sure")) ?? .hemen }
        set { d.set(newValue.rawValue, forKey: "kilit.sure") }
    }

    init() {
        // Açılışta kilit etkinse kilitli başla.
        kilitli = Ayarlar.paylasilan.kilitEtkin
    }

    /// Cihaz kimlik doğrulaması kullanılabilir mi (parola ya da biyometri tanımlı mı).
    static func kullanilabilir() -> (bool: Bool, neden: String?) {
        var e: NSError?
        let ok = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &e)
        return (ok, ok ? nil : "Bu cihazda parola ya da Face ID tanımlı değil. Ayarlar > Face ID ve Parola'dan tanımla.")
    }

    /// Kimlik doğrular; başarılıysa true.
    @discardableResult
    func dogrula(sebep: String = "Kâğıt'ı açmak için kimliğini doğrula") async -> Bool {
        guard !dogruluyor else { return false }
        dogruluyor = true
        hata = nil
        defer { dogruluyor = false }
        let baglam = LAContext()
        baglam.localizedCancelTitle = "Vazgeç"
        do {
            let ok = try await baglam.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: sebep)
            if ok { kilitli = false }
            return ok
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            return false
        } catch {
            hata = (error as? LAError).map(Self.aciklama) ?? error.localizedDescription
            return false
        }
    }

    private static func aciklama(_ e: LAError) -> String {
        switch e.code {
        case .authenticationFailed: "Kimlik doğrulanamadı."
        case .biometryLockout: "Face ID kilitlendi. Cihaz parolanı girerek aç."
        case .passcodeNotSet: "Cihazda parola tanımlı değil."
        case .biometryNotAvailable, .biometryNotEnrolled: "Face ID kullanılamıyor."
        default: e.localizedDescription
        }
    }

    // MARK: - Yaşam döngüsü

    func arkaPlanaGecti() {
        guard Ayarlar.paylasilan.kilitEtkin else { return }
        arkaPlanZamani = Date()
        // "Hemen": uygulama değiştiricide bile kilit ekranı görünsün.
        if sure == .hemen { kilitli = true }
    }

    func onPlanaGeldi() {
        guard Ayarlar.paylasilan.kilitEtkin else { kilitli = false; return }
        if let t = arkaPlanZamani, Date().timeIntervalSince(t) >= TimeInterval(sure.rawValue) { kilitli = true }
        arkaPlanZamani = nil
    }
}

extension View {
    /// Face ID kilidi + uygulama değiştiricide bulanıklaştırma.
    func kilitKatmani() -> some View { modifier(KilitKatmaniDuzenleyici()) }
}

private struct KilitKatmaniDuzenleyici: ViewModifier {
    @Environment(\.scenePhase) private var faz
    @Environment(Ayarlar.self) private var ayarlar
    @State private var yonetici = KilitYoneticisi.paylasilan
    @State private var otomatikDenendi = false

    private var gizle: Bool { ayarlar.kilitEtkin && (yonetici.kilitli || faz != .active) }

    func body(content: Content) -> some View {
        content
            .blur(radius: gizle ? 28 : 0)
            .allowsHitTesting(!(ayarlar.kilitEtkin && yonetici.kilitli))
            .accessibilityHidden(ayarlar.kilitEtkin && yonetici.kilitli)
            .overlay {
                if ayarlar.kilitEtkin && yonetici.kilitli {
                    KilitEkrani(yonetici: yonetici)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: gizle)
            .onChange(of: faz) { eski, yeni in
                switch yeni {
                case .background:
                    yonetici.arkaPlanaGecti()
                    otomatikDenendi = false
                case .active:
                    if eski == .background { yonetici.onPlanaGeldi() }
                    otomatikDenendi = false
                    otomatikAc()
                default: break
                }
            }
            .onChange(of: yonetici.kilitli) { _, yeni in if yeni { otomatikDenendi = false; otomatikAc() } }
            .task { otomatikAc() }
    }

    /// Kilitliyse ve uygulama önde ise Face ID istemini kendiliğinden açar (bir etkinleşmede bir kez).
    private func otomatikAc() {
        guard ayarlar.kilitEtkin, yonetici.kilitli, faz == .active, !otomatikDenendi else { return }
        otomatikDenendi = true
        Task { await yonetici.dogrula() }
    }
}

/// Türkçe kilit ekranı.
private struct KilitEkrani: View {
    let yonetici: KilitYoneticisi

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 54)).foregroundStyle(Tema.vurgu)
                Text("Kâğıt kilitli").font(.title2.bold())
                Text("Belgelerini görmek için kimliğini doğrula.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let h = yonetici.hata {
                    Text(h).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    Task { await yonetici.dogrula() }
                } label: {
                    Label("Face ID ile aç", systemImage: "faceid").frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(yonetici.dogruluyor)
            }
            .padding(32)
        }
    }
}
