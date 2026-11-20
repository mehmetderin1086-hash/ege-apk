import SwiftUI

struct UygulamaBaglantiEkrani: View {
    private let baglar = UygulamaBaglantilari.ortak
    @State private var ad = ""
    @State private var uygulama = ""
    @State private var kestirme = ""
    @State private var whatsapp = false
    @State private var hata: String?
    var body: some View {
        let durum = baglar.ozet(uygulamaKoprusuKurulu: UygulamaKatalogu.ortak.kopruEklendi)
        Form {
            Section("Bağlantı durumu") {
                Label(durum.uygulamaKoprusuKurulu ? "Uygulama köprüsü hazır" : "Uygulama köprüsü kurulmadı", systemImage: durum.uygulamaKoprusuKurulu ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(durum.uygulamaKoprusuKurulu ? .green : .orange)
                LabeledContent("Bağlı eylem", value: "\(durum.bagliEylemSayisi) / 40")
                Label(durum.whatsappHazir ? "WhatsApp gönderim köprüsü bağlı" : "WhatsApp gönderim köprüsü bağlı değil", systemImage: durum.whatsappHazir ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(durum.whatsappHazir ? .green : .secondary)
                Text("Bu ekran yalnız Asistan'ın çalıştırabileceği kayıtlı Kestirmeleri gösterir. Uygulama içindeki son işlem sonucu iOS veya ilgili uygulama tarafından ayrıca doğrulanır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Bağlı eylemler") {
                if baglar.kayitlar.isEmpty { Text("Henüz eylem bağlanmadı.").foregroundStyle(.secondary) }
                ForEach(baglar.kayitlar) { k in
                    VStack(alignment: .leading) {
                        Text(k.ad).font(.headline)
                        Text("\(k.uygulama) · \(k.kestirme)").font(.caption).foregroundStyle(.secondary)
                        if k.whatsapp { Text("WhatsApp gönderim köprüsü").font(.caption) }
                    }.swipeActions { Button("Kaldır", role: .destructive) { baglar.sil(k.id) } }
                }
            }
            Section("Mevcut kestirmeyi bağla") {
                TextField("Eylem adı (ör. Alışveriş listesine ekle)", text: $ad)
                TextField("Uygulama (ör. Anımsatıcılar)", text: $uygulama)
                TextField("Kestirmeler’deki tam ad", text: $kestirme)
                Toggle("WhatsApp mesaj gönderimi", isOn: $whatsapp)
                Button("Bağlantıyı kaydet") {
                    do { try baglar.kaydet(ad: ad, uygulama: uygulama, kestirme: kestirme, whatsapp: whatsapp); ad = ""; uygulama = ""; kestirme = ""; hata = nil }
                    catch { hata = error.localizedDescription }
                }
                if let hata { Text(hata).foregroundStyle(.red) }
                Text("Kayıt, kestirmeyi oluşturmaz. Kestirmeler’de önceden hazırladığın eylemi bağlar. Asistan istediğin işte metni kestirme girdisine aktarır; sistemin istediği izinler geçerlidir.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("WhatsApp gönderimini bağla") {
                Text("1. Kestirmeler’de yeni kestirme oluştur. ‘Girdiden Sözlük Al’ eylemine Kestirme Girdisi’ni bağla.\n\n2. Sözlükteki ‘telefon’ ve ‘mesaj’ değerlerini al.\n\n3. WhatsApp’ın ‘Mesaj Gönder’ eylemi cihazında varsa alıcısını telefon, metnini mesaj değerine bağla. Kestirmeyi kaydet; burada aynı adla WhatsApp gönderimi olarak bağla.")
                Text("WhatsApp eylemi yoksa ya da alıcı girdisini kabul etmiyorsa hazır sohbet ekranı kullanılır. Kestirmenin açılması, mesajın teslim edildiği anlamına gelmez. Asistan gelen WhatsApp mesajlarını kendiliğinden okuyamaz.").font(.footnote).foregroundStyle(.secondary)
                Link("Kestirmeler’i aç", destination: URL(string: "shortcuts://")!)
                Link("Apple: Uygulamadan kestirme çalıştırma", destination: URL(string: "https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios")!)
            }
        }.navigationTitle("Uygulama bağlantıları")
    }
}
