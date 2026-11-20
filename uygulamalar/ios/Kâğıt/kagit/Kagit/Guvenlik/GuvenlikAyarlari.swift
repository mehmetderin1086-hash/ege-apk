import SwiftUI

/// Ayarlar > Güvenlik: Face ID kilidi ve kilitleme süresi.
struct GuvenlikAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @State private var yonetici = KilitYoneticisi.paylasilan
    @State private var sure: KilitSuresi = KilitYoneticisi.paylasilan.sure
    @State private var uyari: String?
    @State private var dogruluyor = false

    var body: some View {
        Section {
            Toggle("Face ID ile kilitle", isOn: Binding(get: { ayarlar.kilitEtkin }, set: { degistir($0) }))
                .disabled(dogruluyor)
            if ayarlar.kilitEtkin {
                Picker("Yeniden kilitle", selection: $sure) {
                    ForEach(KilitSuresi.allCases) { Text($0.ad).tag($0) }
                }
                .onChange(of: sure) { _, yeni in yonetici.sure = yeni }
            }
            if let uyari { Text(uyari).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Güvenlik")
        } footer: {
            Text("Kâğıt açılırken ve arka plandan dönerken Face ID (ya da cihaz parolası) istenir. Uygulama değiştiricide içerik bulanık görünür.")
        }
    }

    private func degistir(_ aciliyor: Bool) {
        uyari = nil
        guard aciliyor else {
            // Kapatmak da kimlik ister: kilidi başkası kaldıramasın.
            dogruluyor = true
            Task {
                defer { dogruluyor = false }
                if await yonetici.dogrula(sebep: "Kilidi kapatmak için kimliğini doğrula") { ayarlar.kilitEtkin = false }
            }
            return
        }
        let durum = KilitYoneticisi.kullanilabilir()
        guard durum.bool else { uyari = durum.neden; return }
        dogruluyor = true
        Task {
            defer { dogruluyor = false }
            if await yonetici.dogrula(sebep: "Kilidi açmak için kimliğini doğrula") {
                ayarlar.kilitEtkin = true
                yonetici.kilitli = false
            } else {
                uyari = yonetici.hata ?? "Kimlik doğrulanamadığı için kilit açılmadı."
            }
        }
    }
}
