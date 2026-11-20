import KagitKit
import SwiftUI

/// Ayarlar › Yapay Zekâ: kaynak, model, vekil anahtarı, bağlantı sınama.
struct YapayZekaAyarlari: View {
    @State private var ayar = YapayAyar.paylasilan
    @Environment(Ayarlar.self) private var ayarlar
    @State private var sinaniyor = false
    @State private var sonuc: String?
    @State private var sonucHata = false

    var body: some View {
        Section {
            Picker("Kaynak", selection: $ayar.tercih) { ForEach(KaynakTercihi.allCases) { Text($0.ad).tag($0) } }
            Picker("Bulut modeli", selection: $ayar.model) {
                ForEach(YapayModeller.secenekler, id: \.kod) { Text($0.ad).tag($0.kod) }
            }
            SecureField("Vekil anahtarı", text: $ayar.anahtar).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
            LabeledContent("Cihaz modeli", value: CihazModeli.kullanilabilir ? "Kullanılabilir" : "Bu cihazda yok")
            LabeledContent("Bulut", value: ayarlar.bulutYapayZeka ? "Açık" : "Kapalı")
            Button {
                sina()
            } label: {
                HStack { Text("Bağlantıyı sına"); if sinaniyor { Spacer(); ProgressView() } }
            }
            .disabled(sinaniyor)
            if let sonuc { Text(sonuc).font(.footnote).foregroundStyle(sonucHata ? .red : .green) }
        } header: {
            Text("Yapay zekâ")
        } footer: {
            Text("Otomatik: Apple Intelligence uygunsa cihazda, değilse bulutta (Claude) çalışır. Seçili model yanıt vermezse sıradaki modele geçilir. Bulut, Ayarlar'daki bulut anahtarı açıksa kullanılır.")
        }
    }

    private func sina() {
        sinaniyor = true
        sonuc = nil
        let yz = ayar.yapayZeka()
        Task {
            defer { sinaniyor = false }
            do {
                let y = try await yz.sina()
                sonuc = "Bağlantı tamam · \(y.kaynakEtiketi) (\(y.model))"
                sonucHata = false
            } catch {
                sonuc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                sonucHata = true
            }
        }
    }
}
