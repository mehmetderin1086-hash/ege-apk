import KagitKit
import SwiftUI

/// VPS dönüşüm sunucusu (PDF Studio) ayarları.
struct BulutAyarlari: View {
    @State private var adres = Sunucu.kok
    @State private var anahtar = Gizli.vekilAnahtari ?? ""
    @State private var sinaniyor = false
    @State private var sonuc: (ok: Bool, metin: String)?

    var body: some View {
        @Bindable var ayarlar = Ayarlar.paylasilan
        Section {
            Toggle("Office dönüşümü için sunucu", isOn: $ayarlar.sunucuEtkin)
            if ayarlar.sunucuEtkin {
                LabeledContent("Adres") {
                    TextField(Sunucu.varsayilanKok, text: $adres)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { Sunucu.kok = adres.trimmingCharacters(in: .whitespaces) }
                }
                LabeledContent("Anahtar") {
                    SecureField("Erişim anahtarı", text: $anahtar)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Gizli.vekilAnahtari = anahtar }
                }
                Button {
                    sina()
                } label: {
                    HStack {
                        Text("Bağlantıyı sına")
                        Spacer()
                        if sinaniyor { ProgressView() }
                    }
                }
                .disabled(sinaniyor)
                if let sonuc {
                    Label(sonuc.metin, systemImage: sonuc.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(sonuc.ok ? .green : .red)
                        .font(.footnote)
                }
                Button("Varsayılan adrese dön") {
                    adres = Sunucu.varsayilanKok
                    Sunucu.kok = adres
                }
            }
        } header: {
            Text("Sunucu")
        } footer: {
            Text("Açıkken Word, Excel, PowerPoint ve ODT dosyaları dönüştürme için kendi sunucuna gönderilir ve işlem bitince silinir. Kapalıyken yalnız cihazda yapılabilen dönüşümler çalışır.")
        }
    }

    private func sina() {
        let temiz = adres.trimmingCharacters(in: .whitespaces)
        Sunucu.kok = temiz
        Gizli.vekilAnahtari = anahtar
        sinaniyor = true
        sonuc = nil
        let istemci = pdfStudioIstemcisi()
        Task {
            defer { sinaniyor = false }
            do {
                let surum = try await istemci.saglik()
                sonuc = (true, "PDF Studio yanıt verdi" + (surum.isEmpty ? "." : " (sürüm \(surum))."))
            } catch {
                sonuc = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}
