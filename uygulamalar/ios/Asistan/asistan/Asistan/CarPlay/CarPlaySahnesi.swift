// P4.7 aşama 2: CarPlay sesli konuşma sahnesi. Apple'ın `com.apple.developer.carplay-voice-based-conversation`
// yetkisi onaylanana dek KAPALI: dosya kaynaklarda durur ama `ASISTAN_CARPLAY` derleme bayrağı olmadan boş derlenir.
// Yetki gelince (AGENTS.md): SWIFT_ACTIVE_COMPILATION_CONDITIONS += ASISTAN_CARPLAY; Info.plist sahne manifestine
// CPTemplateApplicationSceneSessionRoleApplication (UISceneDelegateClassName $(PRODUCT_MODULE_NAME).CarPlaySahnesi);
// Asistan.entitlements'a com.apple.developer.carplay-voice-based-conversation = true.
#if ASISTAN_CARPLAY
import CarPlay
import UIKit

/// CarPlay ekranı: kök listede tek "Konuş" satırı, dokununca (ya da bağlanınca) sesli konuşma şablonu açılır.
/// Şablon durumu `SesOturumu` ile eşlenir: dinliyor / düşünüyor / konuşuyor. Bağlıyken sürüş kipi zorunlu açıktır.
final class CarPlaySahnesi: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var arayuz: CPInterfaceController?
    private var sesSablonu: CPVoiceControlTemplate?
    private var izleme: Task<Void, Never>?
    private var sonDurum = ""

    nonisolated enum Durum {
        static let hazir = "hazir", dinliyor = "dinliyor", dusunuyor = "dusunuyor", konusuyor = "konusuyor"
    }

    // CarPlay sahne olaylarını ana iş parçacığında verir; yöntemler nonisolated kalır (SDK yalıtımı değişse de
    // derlensin) ve ana aktöre `assumeIsolated` ile geçer (iOS 27 SDK'da CPInterfaceController Sendable).
    nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                              didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { self.baglandi(interfaceController) }
    }

    nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                              didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { self.ayrildi() }
    }

    // Kullanıcı sesli şablonu kapatınca (geri/kapat) başvuru düşer; "Konuş" satırı şablonu yeniden sunabilsin.
    nonisolated func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        MainActor.assumeIsolated { self.sablonKapandi(aTemplate) }
    }

    private func sablonKapandi(_ sablon: CPTemplate) {
        guard sablon === sesSablonu else { return }
        sesSablonu = nil
        sonDurum = ""
    }

    private func baglandi(_ ic: CPInterfaceController) {
        arayuz = ic
        ic.delegate = self
        SurusKipi.ortak.carPlayBagli = true
        let konus = CPListItem(text: "Konuş", detailText: "Asistan seni dinlesin")
        konus.handler = { [weak self] _, tamam in
            self?.sesliAc()
            tamam()
        }
        let kok = CPListTemplate(title: "Asistan", sections: [CPListSection(items: [konus])])
        ic.setRootTemplate(kok, animated: false, completion: nil)
        sesliAc()
    }

    private func ayrildi() {
        izleme?.cancel(); izleme = nil
        sesSablonu = nil
        arayuz = nil
        sonDurum = ""
        SurusKipi.ortak.carPlayBagli = false
    }

    /// Sesli konuşma şablonunu açar ve sesli kipi başlatır; durum değişimi kısa aralıkla şablona yansıtılır.
    private func sesliAc() {
        guard let ic = arayuz else { return }
        if sesSablonu == nil {
            let durumlar = [
                CPVoiceControlState(identifier: Durum.hazir, titleVariants: ["Hazır"], image: nil, repeats: false),
                CPVoiceControlState(identifier: Durum.dinliyor, titleVariants: ["Dinliyorum"], image: nil, repeats: true),
                CPVoiceControlState(identifier: Durum.dusunuyor, titleVariants: ["Düşünüyorum"], image: nil, repeats: true),
                CPVoiceControlState(identifier: Durum.konusuyor, titleVariants: ["Konuşuyorum"], image: nil, repeats: true),
            ]
            let s = CPVoiceControlTemplate(voiceControlStates: durumlar)
            sesSablonu = s
            ic.presentTemplate(s, animated: true, completion: nil)
        }
        if let ses = SurusKipi.ortak.ses, !ses.sesliKip {
            Task { await ses.sesliKipiAc() }
        }
        izlemeyiBaslat()
    }

    private func izlemeyiBaslat() {
        izleme?.cancel()
        izleme = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.durumuYansit()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func durumuYansit() {
        guard let s = sesSablonu, let ses = SurusKipi.ortak.ses else { return }
        let yeni = Self.durum(konusuyor: ses.konusmaci.konusuyor, dinliyor: ses.dinleyici.durum == .dinliyor,
                              hazirlaniyor: ses.canliDurum == "Yanıt hazırlanıyor")
        guard yeni != sonDurum else { return }
        sonDurum = yeni
        s.activateVoiceControlState(withIdentifier: yeni)
    }

    /// Saf eşleme: konuşma > dinleme > hazırlık > hazır.
    nonisolated static func durum(konusuyor: Bool, dinliyor: Bool, hazirlaniyor: Bool) -> String {
        if konusuyor { return Durum.konusuyor }
        if dinliyor { return Durum.dinliyor }
        if hazirlaniyor { return Durum.dusunuyor }
        return Durum.hazir
    }
}
#endif
