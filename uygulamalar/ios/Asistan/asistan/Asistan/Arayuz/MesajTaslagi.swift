import SwiftUI
import MessageUI
import Observation

@MainActor @Observable
final class MesajTaslagi {
    static let ortak = MesajTaslagi()
    struct Istek: Identifiable { let id: UUID; let alici: String; let metin: String }
    var istek: Istek?
    /// Taslağın bitiş sonucu: araç metni + sistemin mesajı gönderim için kabul edip etmediği (yalnız `.sent`).
    nonisolated struct Sonuc: Equatable, Sendable { let metin: String; let gonderildi: Bool }
    private var devam: CheckedContinuation<Sonuc, Never>?
    func goster(alici: String, metin: String) async -> String {
        await gosterSonuclu(alici: alici, metin: metin).metin
    }
    /// Eylem kartı yalnız `gonderildi` iken eklenir (iptal, hata, kapatma, durdurma: kart yok).
    func gosterSonuclu(alici: String, metin: String) async -> Sonuc {
        guard MFMessageComposeViewController.canSendText() else { return Sonuc(metin: "Bu cihaz SMS/iMessage gönderemiyor. Mesaj gönderilmedi.", gonderildi: false) }
        guard devam == nil else { return Sonuc(metin: "Açık mesaj taslağını önce tamamla.", gonderildi: false) }
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return Sonuc(metin: "Mesaj işlemi durduruldu.", gonderildi: false) }
            return await withCheckedContinuation { c in
                devam = c
                istek = Istek(id: id, alici: alici, metin: metin)
            }
        } onCancel: {
            Task { @MainActor in self.bitir(id: id, sonuc: "Mesaj işlemi durduruldu; gönderim doğrulanmadı.") }
        }
    }
    func bitir(id: UUID, sonuc: String, gonderildi: Bool = false) {
        guard istek?.id == id else { return }
        let c = devam; devam = nil; istek = nil; c?.resume(returning: Sonuc(metin: sonuc, gonderildi: gonderildi))
    }
}

/// SMS taslağı sayfasının sunumu. Yalnız EN ÜSTTEKİ ekran uygulamalı (`etkin`): SohbetEkrani bir sayfa (ör. Sınıflarım)
/// açıkken `etkin: false` verir, o sayfa kendisi `etkin: true` ile sunar; yoksa ikinci sayfa görünmez ve `goster`
/// sürekliliği askıda kalır (Live'daki onay diyaloğu sorunuyla aynı sınıf). Kapatılınca `bitir` sonucu yazar.
struct MesajTaslagiSunumu: ViewModifier {
    let etkin: Bool
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { etkin ? MesajTaslagi.ortak.istek : nil }, set: { yeni in
            guard etkin, yeni == nil, let istek = MesajTaslagi.ortak.istek else { return }
            MesajTaslagi.ortak.bitir(id: istek.id, sonuc: "Mesaj taslağı kapatıldı; gönderim doğrulanmadı.")
        })) { istek in MesajOlusturucu(istek: istek).interactiveDismissDisabled().accessibilityIdentifier("mesaj-taslagi") }
    }
}

extension View {
    func mesajTaslagiSunumu(etkin: Bool) -> some View { modifier(MesajTaslagiSunumu(etkin: etkin)) }
}

struct MesajOlusturucu: UIViewControllerRepresentable {
    let istek: MesajTaslagi.Istek
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let c = MFMessageComposeViewController()
        c.recipients = [istek.alici]; c.body = istek.metin; c.messageComposeDelegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(id: istek.id) }
    final class Koordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let id: UUID
        init(id: UUID) { self.id = id }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            let sonuc: String
            switch result {
            case .sent: sonuc = "Kullanıcı Gönder'e dokundu; sistem mesajı gönderim için kabul etti. Alıcıya teslim edildiği doğrulanmadı."
            case .cancelled: sonuc = "Kullanıcı mesaj taslağını iptal etti. Mesaj gönderilmedi."
            case .failed: sonuc = "Sistem mesajı gönderemedi."
            @unknown default: sonuc = "Mesajın gönderim durumu doğrulanamadı."
            }
            MesajTaslagi.ortak.bitir(id: id, sonuc: sonuc, gonderildi: result == .sent)
        }
    }
}
