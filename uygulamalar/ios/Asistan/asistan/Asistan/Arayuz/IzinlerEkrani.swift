import SwiftUI
import UIKit
import EventKit
import Contacts
import AVFoundation
import Speech
import CoreLocation
import Photos
import UserNotifications
import AlarmKit

/// P1.10: uygulamanın istediği sistem izinleri (sohbetteki izin kartı ve Ayarlar > İzinler ekranı).
nonisolated enum IzinTuru: String, Codable, CaseIterable, Sendable {
    case mikrofon, konusma, takvim, hatirlatici, kisiler, alarm, konum, kamera, fotograflar, bildirimler

    var ad: String {
        switch self {
        case .mikrofon: "Mikrofon"
        case .konusma: "Konuşma tanıma"
        case .takvim: "Takvim"
        case .hatirlatici: "Hatırlatıcılar"
        case .kisiler: "Kişiler"
        case .alarm: "Alarm ve zamanlayıcı"
        case .konum: "Konum"
        case .kamera: "Kamera"
        case .fotograflar: "Fotoğraflar"
        case .bildirimler: "Bildirimler"
        }
    }

    var simge: String {
        switch self {
        case .mikrofon: "mic"
        case .konusma: "waveform"
        case .takvim: "calendar"
        case .hatirlatici: "checklist"
        case .kisiler: "person.crop.circle"
        case .alarm: "alarm"
        case .konum: "location"
        case .kamera: "camera"
        case .fotograflar: "photo.on.rectangle"
        case .bildirimler: "bell"
        }
    }
}

/// Sistem izin durumlarının tek biçimi. Eşlemeler saftır (birim testli); okuma/isteme `IzinDenetcisi`nde.
nonisolated enum IzinDurumu: Equatable, Sendable {
    case verildi, reddedildi, sorulmadi, kisitli

    var ad: String {
        switch self {
        case .verildi: "Açık"
        case .reddedildi: "Kapalı"
        case .sorulmadi: "Sorulmadı"
        case .kisitli: "Sınırlı"
        }
    }

    /// Duruma göre eylem düğmesi: sorulmamışsa sistem sorusu, reddedilmiş/sınırlıysa Ayarlar; verilmişse düğme yok.
    static func dugme(_ d: IzinDurumu) -> String? {
        switch d {
        case .sorulmadi: "İzin ver"
        case .reddedildi, .kisitli: "Ayarlar'ı aç"
        case .verildi: nil
        }
    }

    static func ek(_ s: EKAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .fullAccess: .verildi
        case .writeOnly: .kisitli
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        default: .reddedildi
        }
    }

    static func cn(_ s: CNAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorized: .verildi
        case .limited: .kisitli
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func kayit(_ s: AVAudioApplication.recordPermission) -> IzinDurumu {
        switch s {
        case .granted: .verildi
        case .denied: .reddedildi
        case .undetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func konusma(_ s: SFSpeechRecognizerAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorized: .verildi
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func konum(_ s: CLAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: .verildi
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func kamera(_ s: AVAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorized: .verildi
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func foto(_ s: PHAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorized: .verildi
        case .limited: .kisitli
        case .denied, .restricted: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func alarm(_ s: AlarmManager.AuthorizationState) -> IzinDurumu {
        switch s {
        case .authorized: .verildi
        case .denied: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }

    static func bildirim(_ s: UNAuthorizationStatus) -> IzinDurumu {
        switch s {
        case .authorized, .provisional, .ephemeral: .verildi
        case .denied: .reddedildi
        case .notDetermined: .sorulmadi
        @unknown default: .reddedildi
        }
    }
}

/// Sistem izin sorularını ana aktör DIŞINDA açar. Tamamlayıcılı API'lerin kapanışı (SFSpeechRecognizer.requestAuthorization)
/// arka plan kuyruğunda çağrılır; ana aktöre bağlı kalırsa telefonda `dispatch_assert_queue` ile çöker (AGENTS.md).
nonisolated enum IzinIstegi {
    @concurrent nonisolated static func mikrofon() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
    @concurrent nonisolated static func konusma() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable _ in c.resume() }
        }
    }
    @concurrent nonisolated static func takvim() async {
        let depo = EKEventStore()
        _ = try? await depo.requestFullAccessToEvents()
    }
    @concurrent nonisolated static func hatirlatici() async {
        let depo = EKEventStore()
        _ = try? await depo.requestFullAccessToReminders()
    }
    @concurrent nonisolated static func kisiler() async {
        let depo = CNContactStore()
        _ = try? await depo.requestAccess(for: .contacts)
    }
    @concurrent nonisolated static func alarm() async {
        _ = try? await AlarmManager.shared.requestAuthorization()
    }
    @concurrent nonisolated static func kamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }
    @concurrent nonisolated static func fotograflar() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
    @concurrent nonisolated static func bildirimler() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// İzin durumunu okur, sistem sorusunu açar ya da Ayarlar'a gönderir.
@MainActor
enum IzinDenetcisi {
    static func durum(_ t: IzinTuru) async -> IzinDurumu {
        switch t {
        case .mikrofon: return .kayit(AVAudioApplication.shared.recordPermission)
        case .konusma: return .konusma(SFSpeechRecognizer.authorizationStatus())
        case .takvim: return .ek(EKEventStore.authorizationStatus(for: .event))
        case .hatirlatici: return .ek(EKEventStore.authorizationStatus(for: .reminder))
        case .kisiler: return .cn(CNContactStore.authorizationStatus(for: .contacts))
        case .alarm: return .alarm(AlarmManager.shared.authorizationState)
        case .konum: return .konum(CLLocationManager().authorizationStatus)
        case .kamera: return .kamera(AVCaptureDevice.authorizationStatus(for: .video))
        case .fotograflar: return .foto(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .bildirimler:
            // Geri çağrılı varyant kullanılmaz (kapanış arka plan kuyruğunda gelir).
            let ayar = await UNUserNotificationCenter.current().notificationSettings()
            return .bildirim(ayar.authorizationStatus)
        }
    }

    /// Sistem sorusunu açar (yalnız 'sorulmadı' iken anlamlı; sistem daha önce yanıtlanmış soruyu yeniden göstermez) ve yeni durumu döndürür.
    static func iste(_ t: IzinTuru) async -> IzinDurumu {
        switch t {
        case .mikrofon: await IzinIstegi.mikrofon()
        case .konusma: await IzinIstegi.konusma()
        case .takvim: await IzinIstegi.takvim()
        case .hatirlatici: await IzinIstegi.hatirlatici()
        case .kisiler: await IzinIstegi.kisiler()
        case .alarm: await IzinIstegi.alarm()
        case .konum: _ = try? await Konum.paylasilan.al()
        case .kamera: await IzinIstegi.kamera()
        case .fotograflar: await IzinIstegi.fotograflar()
        case .bildirimler: await IzinIstegi.bildirimler()
        }
        return await durum(t)
    }

    static func ayarlariAc() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func hepsi() async -> [IzinTuru: IzinDurumu] {
        var sonuc: [IzinTuru: IzinDurumu] = [:]
        for t in IzinTuru.allCases { sonuc[t] = await durum(t) }
        return sonuc
    }
}

/// Araçların izin reddinde sohbete kart eklemesi: hata metni aynen döner, kart ek olarak gelir.
nonisolated enum IzinKarti {
    static func ekle(_ t: IzinTuru) async {
        await MainActor.run { EkDefteri.ortak.ekle(MesajEki(tur: .izin(t))) }
    }
}

// MARK: Görünümler

/// Sohbetteki izin kartı: durum canlı okunur; "İzin ver" sistem sorusunu, "Ayarlar'ı aç" Ayarlar'ı açar.
struct IzinEkKarti: View {
    let tur: IzinTuru
    @State private var durum: IzinDurumu?
    @Environment(\.scenePhase) private var sahne

    private var baslik: String {
        switch durum {
        case .verildi: "\(tur.ad) izni açık"
        case .reddedildi: "\(tur.ad) izni kapalı"
        case .kisitli: "\(tur.ad) izni sınırlı"
        case .sorulmadi: "\(tur.ad) izni gerekli"
        case nil: "\(tur.ad) izni"
        }
    }
    private var aciklama: String {
        switch durum {
        case .verildi: "İzin verildi; isteğini yeniden söyleyebilirsin."
        case .reddedildi: "Ayarlar > Asistan'dan açabilirsin."
        case .kisitli: "Erişim sınırlı; Ayarlar'dan tam erişim verebilirsin."
        case .sorulmadi: "İzin verirsen isteğini yeniden söyleyebilirsin."
        case nil: "Durum okunuyor…"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: durum == .verildi ? "checkmark.shield" : tur.simge)
                .font(.title3)
                .foregroundStyle(durum == .verildi ? Color.green : Color.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik).font(.subheadline.weight(.semibold))
                Text(aciklama).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let d = durum, let metin = IzinDurumu.dugme(d) {
                Button(metin) {
                    if d == .sorulmadi {
                        Task { durum = await IzinDenetcisi.iste(tur) }
                    } else {
                        IzinDenetcisi.ayarlariAc()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("izin-dugmesi")
            }
        }
        .modifier(KartZemini())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("izin-karti")
        .task { durum = await IzinDenetcisi.durum(tur) }
        .onChange(of: sahne) { _, yeni in
            // Ayarlar'dan dönünce durumu tazele.
            if yeni == .active { Task { durum = await IzinDenetcisi.durum(tur) } }
        }
    }
}

/// Ayarlar > İzinler: bütün izinlerin durumu ve duruma göre "İzin ver" / "Ayarlar'ı aç".
struct IzinlerEkrani: View {
    @State private var durumlar: [IzinTuru: IzinDurumu] = [:]
    @Environment(\.scenePhase) private var sahne

    private func renk(_ d: IzinDurumu?) -> Color {
        switch d {
        case .verildi: .green
        case .reddedildi, .kisitli: .red
        case .sorulmadi, nil: .gray
        }
    }

    private func baslikSatiri(_ t: IzinTuru) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.simge).frame(width: 24).foregroundStyle(.secondary)
            Text(t.ad)
        }
    }

    @ViewBuilder
    private func durumSatiri(_ t: IzinTuru, _ d: IzinDurumu?) -> some View {
        Circle().fill(renk(d)).frame(width: 8, height: 8).accessibilityHidden(true)
        Text(d?.ad ?? "…").font(.caption).foregroundStyle(.secondary)
        if let d, let metin = IzinDurumu.dugme(d) {
            Button(metin) {
                if d == .sorulmadi {
                    Task { durumlar[t] = await IzinDenetcisi.iste(t) }
                } else {
                    IzinDenetcisi.ayarlariAc()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(IzinTuru.allCases, id: \.self) { t in
                    let d = durumlar[t]
                    // Büyük yazı boyutunda tek satıra sığmazsa ad üstte, durum ve düğme altta.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            baslikSatiri(t)
                            Spacer(minLength: 4)
                            durumSatiri(t, d)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            baslikSatiri(t)
                            HStack(spacing: 10) {
                                durumSatiri(t, d)
                                Spacer(minLength: 4)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("izin-satiri-\(t.rawValue)")
                }
            } footer: {
                Text("Reddedilen izin yalnız iOS Ayarlar > Asistan'dan yeniden açılır; döndüğünde liste kendiliğinden tazelenir.")
            }
        }
        .navigationTitle("İzinler")
        .task { durumlar = await IzinDenetcisi.hepsi() }
        .onChange(of: sahne) { _, yeni in
            if yeni == .active { Task { durumlar = await IzinDenetcisi.hepsi() } }
        }
    }
}
