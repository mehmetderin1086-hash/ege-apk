import SwiftUI
import UIKit

struct UygulamaKatalogEkrani: View {
    private let katalog = UygulamaKatalogu.ortak
    @State private var sorgu = ""
    @State private var hazirKopru: URL?
    @State private var hata: String?
    @State private var ozelAd = ""
    @State private var ozelKimlik = ""
    @State private var ozelDigerAdlar = ""
    var body: some View {
        @Bindable var k = katalog
        List {
            Section("Tek kestirmeyle tüm uygulamalar") {
                Button("Tüm uygulamalar için köprüyü ekle") {
                    do { hazirKopru = try katalog.kopruHazirla(); hata = nil }
                    catch { hata = "Köprü dosyası açılamadı: \(error.localizedDescription)" }
                }
                if let hazirKopru {
                    ShareLink(item: hazirKopru) {
                        Label("Mehmet Uygulama Köprüsünü paylaş", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("uygulama-koprusu-paylas")
                    Text("Köprü dosyası hazır. Paylaş'a dokunup Kestirmeler'i seç; görünmüyorsa Dosyalar'a kaydet, sonra dosyayı aç.")
                        .font(.footnote).foregroundStyle(.green)
                }
                Text("Bir kez ‘Mehmet Uygulama Koprusu’nü Kestirmeler’e ekle; tüm listedeki uygulamalar için yeterli. Paylaşım ekranında Kestirmeler görünmüyorsa Dosyalar’a kaydet, kaydettiğin dosyaya dokun ve Kestirme Ekle’yi seç. İsmini değiştirme.").font(.footnote).foregroundStyle(.secondary)
                Toggle("Uygulama köprüsünü ekledim", isOn: $k.kopruEklendi)
                Text("iOS, eklenip eklenmediğini Asistan’a bildirmez; bu işareti kurulumu bitirince aç.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("\(katalog.tumUygulamalar.count) uygulama için açılış kestirmesi hazır.").font(.headline)
                Text("18 Ekim 2026 telefon listesinden hazırlandı. Köprü kurulduktan sonra ‘Telegram’ı aç’ gibi söyle. Yeni yüklenen uygulamaları Telefon işlemleri bölümünden ayrıca bağlayabilirsin.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Bu kestirmeler uygulamayı açar. Mesaj gönderme gibi uygulama içi işler için Uygulama bağlantıları bölümüne o uygulamanın sunduğu eylemi bağla.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let hata { Text(hata).foregroundStyle(.red) }
            }
            Section("Yeni uygulama ekle") {
                TextField("Uygulama adı", text: $ozelAd)
                TextField("Paket kimliği (ör. com.ornek.uygulama)", text: $ozelKimlik)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Diğer adlar, virgülle (isteğe bağlı)", text: $ozelDigerAdlar)
                Button("Uygulamayı köprüye ekle") {
                    do {
                        try katalog.ozelEkle(ad: ozelAd, kimlik: ozelKimlik, digerAdlar: ozelDigerAdlar)
                        ozelAd = ""; ozelKimlik = ""; ozelDigerAdlar = ""; hata = nil
                    } catch { hata = error.localizedDescription }
                }
                Text("iOS başka uygulamalara yüklü uygulamaların tam listesini vermez. Yeni bir uygulamanın paket kimliğini biliyorsan burada ekle; aynı Mehmet Uygulama Köprüsü ile açılır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !katalog.ozelUygulamalar.isEmpty {
                Section("Özel uygulamalar") {
                    ForEach(katalog.ozelUygulamalar) { app in
                        Text("\(app.ad) · \(app.id)")
                            .swipeActions { Button("Kaldır", role: .destructive) { katalog.ozelSil(app.id) } }
                    }
                }
            }
            ForEach(katalog.tumUygulamalar.filter { app in
                sorgu.isEmpty || TelefonAdresleri.ad(app.ad + " " + app.digerAdlar.joined(separator: " ")).contains(TelefonAdresleri.ad(sorgu))
            }) { app in
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.ad).font(.headline)
                            Text(katalog.kopruEklendi ? "Köprüye bağlı" : "Köprü kurulumu bekliyor").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let url = katalog.calistirmaURL(app) {
                        Link("\(app.ad) uygulamasını aç", destination: url)
                    }
                }
            }
        }
        .navigationTitle("Telefondaki uygulamalar")
        .searchable(text: $sorgu, prompt: "Uygulama ara")
        .onAppear { if let ad = katalog.secilen { sorgu = ad; katalog.secilen = nil } }
    }
}
