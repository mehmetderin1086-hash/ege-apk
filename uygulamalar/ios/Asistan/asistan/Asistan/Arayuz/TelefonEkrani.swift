import SwiftUI
import AppIntents

struct TelefonEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var kestirme = ""
    private let kayit = TelefonKestirmeleri.ortak

    private let ornekler: [(String, String, String)] = [
        ("Arama", "phone", "Bir kişiyi aramak istiyorum"),
        ("WhatsApp", "message", "WhatsApp mesajı göndermek istiyorum"),
        ("SMS", "bubble.left", "Bir mesaja yanıt yazmak istiyorum"),
        ("Gelen Kutusu", "tray.full", "Aktarılan yeni iletilerimi oku"),
        ("Arama cevaplama", "phone.arrow.down.left", "Gelen aramaları sesle nasıl cevaplarım?"),
        ("Uygulama aç", "app.badge", "YouTube'u aç"),
        ("Hatırlatıcı", "checklist", "Yarın saat 9'da su içmemi hatırlat"),
        ("Takvim", "calendar", "Bugünkü takvimimi göster"),
        ("Zamanlayıcı", "timer", "5 dakikalık zamanlayıcı başlat"),
        ("Yol tarifi", "map", "Yakındaki eczaneleri bul"),
        ("El feneri", "flashlight.on.fill", "El fenerini aç"),
        ("Parlaklık", "sun.max", "Ekran parlaklığını yüzde 50 yap"),
        ("Wi-Fi", "wifi", "Wi-Fi'yi kapat"),
        ("Rahatsız Etme", "moon.fill", "Rahatsız etmeyi aç"),
        ("Görünüm", "circle.lefthalf.filled", "Karanlık moda geç"),
        ("Ses düzeyi", "speaker.wave.2.fill", "Sesi yüzde 40 yap"),
        ("Pil", "battery.100percent", "Pilimin durumu nedir?"),
        ("Müzik", "music.note", "Müziği devam ettir"),
        ("Hava", "cloud.sun", "İstanbul'da yarın hava nasıl?"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ne yapmak istediğini söyle. Asistan uygun telefon aracını çalıştırır; arama, mesaj ve kestirmelerde işlem ayrıntısını gösterir.")
                        .foregroundStyle(.secondary)
                }
                Section("Uygulamalar ve dosyalar") {
                    NavigationLink { SistemKoprusuEkrani() } label: {
                        LabeledContent("Sistem ayarları", value: SistemKoprusu.ortak.kuruldu ? "Kurulu" : "Kurulum gerekli")
                    }.accessibilityIdentifier("telefon-sistem-ayarlari")
                    NavigationLink("Telefondaki uygulamalar") { UygulamaKatalogEkrani() }
                    NavigationLink("Uygulama bağlantıları") { UygulamaBaglantiEkrani() }
                    Button("Dosyalarımda ara") { kapat(); Task { try? await Task.sleep(for: .milliseconds(350)); DosyaKitapligi.ortak.ekranAcik = true } }
                    Button("Aktarılan iletilerim") { kapat(); GelenKutusu.ortak.ekranAcik = true }
                }
                Section("Bir komut dene") {
                    ForEach(ornekler, id: \.0) { ornek in
                        Button {
                            beyin.gonder(ornek.2); kapat()
                        } label: { Label(ornek.2, systemImage: ornek.1) }
                        .disabled(beyin.durum != .bosta)
                    }
                }
                Section {
                    ForEach(kayit.kayitlar) { k in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(k.ad).font(.headline)
                                Text(k.kestirme).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // .borderless: Form satırının tamamı silme düğmesine bağlanmasın (ada dokunmak kaydı silmesin).
                            Button(role: .destructive) { kayit.sil(k.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(k.ad) bağlantısını kaldır")
                        }
                    }
                    TextField("Söyleyeceğin ad: ör. Bankam", text: $ad)
                    TextField("Kestirmeler'deki tam ad", text: $kestirme)
                    Button("Kestirmeyi bağla") {
                        kayit.kaydet(ad: ad, kestirme: kestirme)
                        ad = ""; kestirme = ""
                    }.disabled(ad.trimmingCharacters(in: .whitespaces).isEmpty || kestirme.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("Kendi uygulamalarını ve işlemlerini bağla") }
                  footer: { Text("Önce Kestirmeler'de ‘Uygulamayı Aç’ eylemiyle bir kestirme oluştur. Buraya aynı adı yaz. Sonra Asistan'a ‘Bankamı aç’ diyebilirsin. Bağlama işlemi kestirmeyi otomatik oluşturmaz.") }
                Section("Arama ve mesajlar") {
                    Text("‘Ayşe’yi ara’, ‘Ayşe’ye WhatsApp’tan 10 dakika sonra geleceğim yaz’ veya ‘Aktarılan yeni iletilerimi oku’ diyebilirsin. iOS 27 bildirim otomasyonu WhatsApp ve diğer uygulamalardan; iletişim otomasyonları Mail ve Mesajlar'dan yeni içeriği Gelen Kutusu'na aktarabilir.")
                    NavigationLink("Gelen Kutusu kurulumu") { GelenKutusuKurulumEkrani() }
                    Text("Asistan gelen aramayı devralamaz; Bildirim Merkezi geçmişini, Mail veya WhatsApp'ın özel gelen kutusunu doğrudan tarayamaz. Yalnız senin seçtiğin otomasyonun aktardığı veya paylaştığın iletileri okur. Sesle çağrı yanıtlama, Siri’nin Aramaları Duyur özelliğiyle yapılır.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Apple: Siri ile aramaları duyur ve yanıtla", destination: URL(string: "https://support.apple.com/tr-tr/guide/iphone/iph838fd6fd4/ios")!)
                }
                Section("Daha fazla telefon işlemi") {
                    Text("Wi-Fi, Bluetooth, Odak, ses düzeyi ve birden çok uygulamayı içeren işler için Kestirmeler'de bir akış oluşturup buraya bağlayabilirsin. Asistan diğer uygulamaların ekranına dokunamaz ve korumalı verilerini okuyamaz.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Kestirmeler'i aç", destination: URL(string: "shortcuts://")!)
                    ShortcutsLink()
                }
            }
            .navigationTitle("Telefon işlemleri")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
        }
    }
}
