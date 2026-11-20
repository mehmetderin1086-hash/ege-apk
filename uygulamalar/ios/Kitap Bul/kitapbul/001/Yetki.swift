import SwiftUI
import LocalAuthentication

/// Kullanıcı rolleri: kütüphane masasında öğrenci görevli çalışırken silme, toplu değişiklik
/// ve ayarlar kilitlenir; yönetici Face ID / cihaz parolasıyla kilidi açar.
enum KullaniciRolu: String, CaseIterable, Identifiable {
    case yonetici = "Yönetici"
    case gorevli = "Görevli (kısıtlı)"
    var id: String { rawValue }
}

@Observable
final class YetkiDurumu {
    static let shared = YetkiDurumu()
    static let kilitAnahtari = "roleLockEnabled"
    static let hosgoruAnahtari = "adminGraceSeconds"
    /// Uygulama arka plandan dönerken yönetici oturumunun korunacağı süre seçenekleri (sn).
    static let hosgoruSecenekleri = [0, 60, 90, 300]
    static let varsayilanHosgoru = 90

    @ObservationIgnored private let defaults: UserDefaults

    /// Rol kilidi kapalıysa herkes yöneticidir (varsayılan: eski davranış korunur).
    var kilitEtkin: Bool {
        didSet {
            defaults.set(kilitEtkin, forKey: Self.kilitAnahtari)
            if !kilitEtkin { oturumYonetici = false }
        }
    }
    /// Arka plana geçişten sonra yönetici oturumunun açık kalacağı süre; 0 = hemen görevliye dön.
    var hosgoruSaniye: Int {
        didSet { defaults.set(hosgoruSaniye, forKey: Self.hosgoruAnahtari) }
    }
    /// Bu oturumda kimlik doğrulanarak yönetici olundu mu? (Uygulama kapanınca sıfırlanır)
    private(set) var oturumYonetici = false
    /// Uygulamanın arka plana geçtiği an; öne dönünce hoşgörü süresiyle karşılaştırılır.
    private(set) var sonArkaPlan: Date?
    var hata: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        kilitEtkin = defaults.bool(forKey: Self.kilitAnahtari)
        let kayitli = defaults.object(forKey: Self.hosgoruAnahtari) as? Int
        hosgoruSaniye = kayitli.flatMap { Self.hosgoruSecenekleri.contains($0) ? $0 : nil } ?? Self.varsayilanHosgoru
    }

    /// Kimlik doğrulamasından sonra yönetici oturumunu açar.
    func yoneticiOturumuBaslat() {
        guard kilitEtkin else { return }
        oturumYonetici = true
        sonArkaPlan = nil
    }

    /// Arka plana geçişte yalnız zaman damgası tutulur; oturum hoşgörü süresi dolunca kapanır.
    /// Süre 0 ise eski davranış: hemen görevliye dönülür.
    func arkaPlanaGecti(simdi: Date = .now) {
        guard oturumYonetici else { return }
        if hosgoruSaniye <= 0 { gorevliyeGec(); return }
        sonArkaPlan = simdi
    }

    /// Öne dönüşte süre aşıldıysa görevliye geçer. Dönüşü `true`: oturum kapatıldı.
    @discardableResult
    func onePlanaDondu(simdi: Date = .now) -> Bool {
        defer { sonArkaPlan = nil }
        guard oturumYonetici, let son = sonArkaPlan else { return false }
        guard simdi.timeIntervalSince(son) > Double(hosgoruSaniye) else { return false }
        gorevliyeGec()
        return true
    }

    var rol: KullaniciRolu { yonetici ? .yonetici : .gorevli }
    var yonetici: Bool { !kilitEtkin || oturumYonetici }

    /// Face ID / Touch ID, yoksa cihaz parolası.
    @discardableResult
    func yoneticiOl(neden: String = "Yönetici işlemleri için kimliğinizi doğrulayın") async -> Bool {
        guard !yonetici else { return true }
        let baglam = LAContext()
        var hataNesnesi: NSError?
        guard baglam.canEvaluatePolicy(.deviceOwnerAuthentication, error: &hataNesnesi) else {
            hata = "Bu cihazda kimlik doğrulama kurulu değil (Face ID ya da parola gerekir)."
            return false
        }
        do {
            let basarili = try await baglam.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: neden)
            if basarili { oturumYonetici = true; sonArkaPlan = nil }
            hata = nil
            if basarili { AppLog.write("Yönetici oturumu açıldı") }
            return basarili
        } catch {
            hata = "Kimlik doğrulanamadı."
            return false
        }
    }

    /// Rol kilidini açar: önce kimlik doğrulanır, kilit ancak sonra kalıcılaşır. Doğrulama
    /// kurulu değilse ya da iptal edilirse kilit açılmaz; yoksa ayarlar bir daha açılamaz.
    @discardableResult
    func kilidiEtkinlestir() async -> Bool {
        guard !kilitEtkin else { return true }
        let baglam = LAContext()
        var hataNesnesi: NSError?
        guard baglam.canEvaluatePolicy(.deviceOwnerAuthentication, error: &hataNesnesi) else {
            hata = "Bu cihazda kimlik doğrulama kurulu değil (Face ID ya da parola gerekir); rol kilidi açılmadı."
            return false
        }
        guard (try? await baglam.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Rol kilidini etkinleştirmek için doğrulayın")) == true else {
            hata = "Kimlik doğrulanamadı; rol kilidi açılmadı."
            return false
        }
        kilitEtkin = true
        // Kilidi açan kişi yönetici olarak devam eder
        yoneticiOturumuBaslat()
        hata = nil
        AppLog.write("Rol kilidi etkinleştirildi")
        return true
    }

    static func hosgoruEtiketi(_ saniye: Int) -> String {
        switch saniye {
        case 0: "Arka planda hemen kapat"
        case 60: "1 dakika açık kalsın"
        case 300: "5 dakika açık kalsın"
        default: "\(saniye) saniye açık kalsın"
        }
    }

    func gorevliyeGec() {
        oturumYonetici = false
        sonArkaPlan = nil
        AppLog.write("Görevli moduna geçildi")
    }
}

/// Yönetici gerektiren ekranları örter: kilit açılana kadar açıklama + "Kilidi Aç".
struct YoneticiKilidi<Icerik: View>: View {
    let baslik: String
    /// Kilit ekranında Sade mod anahtarı da gösterilir (Ayarlar): görevli, yazıyı yönetici
    /// kimliği olmadan büyütebilir. Bu tercih veriye dokunmaz.
    var sadeModAnahtari = false
    @ViewBuilder var icerik: () -> Icerik
    @State private var yetki = YetkiDurumu.shared
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false

    var body: some View {
        // İçerik kilitliyken de ağaçta kalır: yarım kalan taslaklar (örn. Ayarlar'daki kural düzenlemesi)
        // kilit açılınca geri gelir. Kilitliyken dokunma, odak ve VoiceOver'a kapalıdır.
        ZStack {
            icerik()
                .disabled(!yetki.yonetici)
                .allowsHitTesting(yetki.yonetici)
                .accessibilityHidden(!yetki.yonetici)
            if !yetki.yonetici { kilitKarti }
        }
    }

    private var kilitKarti: some View {
        ContentUnavailableView {
            Label("\(baslik) kilitli", systemImage: "lock.shield")
        } description: {
            Text("Görevli modundasınız. Ayarlar, silme ve toplu değişiklikler için yönetici kimliği gerekir.")
            if let hata = yetki.hata { Text(hata).foregroundStyle(.red) }
        } actions: {
            Button("Face ID ile Kilidi Aç", systemImage: "faceid") {
                Task { await yetki.yoneticiOl() }
            }
            .buttonStyle(.kitapDolu())
            if sadeModAnahtari {
                Toggle("Sade mod (büyük yazı, temel işlemler)", isOn: $sadeMod)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("lock.simpleMode")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Ayarlar'daki rol bölümü.
struct RolAyarlariBolumu: View {
    @State private var yetki = YetkiDurumu.shared

    var body: some View {
        Section {
            Toggle("Rol kilidi (görevli modu)", isOn: Binding(
                get: { yetki.kilitEtkin },
                set: { yeni in
                    if yeni {
                        Task { await yetki.kilidiEtkinlestir() }
                    } else {
                        Task {
                            if await yetki.yoneticiOl(neden: "Rol kilidini kapatmak için doğrulayın") { yetki.kilitEtkin = false }
                        }
                    }
                }
            ))
            if !yetki.kilitEtkin, let hata = yetki.hata {
                Text(hata).font(.footnote).foregroundStyle(.red)
            }
            if yetki.kilitEtkin {
                LabeledContent("Şu anki rol", value: yetki.rol.rawValue)
                if yetki.yonetici {
                    Button("Görevli moduna geç", systemImage: "person.badge.shield.checkmark") { yetki.gorevliyeGec() }
                }
                Picker("Yönetici oturumu", selection: Binding(get: { yetki.hosgoruSaniye }, set: { yetki.hosgoruSaniye = $0 })) {
                    ForEach(YetkiDurumu.hosgoruSecenekleri, id: \.self) { saniye in
                        Text(YetkiDurumu.hosgoruEtiketi(saniye)).tag(saniye)
                    }
                }
                .accessibilityIdentifier("settings.adminGrace")
            }
        } header: {
            Label("Roller ve Güvenlik", systemImage: "lock.shield")
                .foregroundStyle(KitapTema.vurgu)
        } footer: {
            Text("Açıkken uygulama her açılışta görevli modunda başlar: ödünç verme, iade ve arama serbesttir; silme, düşme, toplu değişiklik ve ayarlar Face ID ister. Kısa süreliğine başka uygulamaya geçerseniz yönetici oturumu seçtiğiniz süre boyunca açık kalır.")
        }
    }
}
