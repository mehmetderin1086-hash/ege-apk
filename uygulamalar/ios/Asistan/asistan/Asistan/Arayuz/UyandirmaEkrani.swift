import SwiftUI

struct UyandirmaEkrani: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SesOturumu.self) private var ses
    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section("Hey Asistan · uygulama açıkken") {
                Toggle("Hey Asistan'ı cihazda dinle", isOn: $a.heyAsistan)
                    .onChange(of: a.heyAsistan) { _, acik in
                        Task { await ses.modSec(acik ? .ellerSerbest : .normal) }
                    }
                Text("Uygulama ön plandayken mikrofon açık kalır. “Hey Asistan” dedikten sonra komutunu söyleyebilirsin. Her çağrıda tek komut alınır; yanıt sonrası yeniden “Hey Asistan” beklenir. 12 saniye komut gelmezse beklemeye dönülür. Uyandırma öncesindeki konuşmalar ekranda gösterilmez ve modele gönderilmez. Mikrofon düğmesiyle beklemeyi durdurabilirsin.").font(.footnote)
                // P4.3: bekleme ekran kilitlenince de sürer; varsayılan kapalı.
                Toggle("Arka planda Hey Asistan", isOn: $a.arkaPlanUyandirma)
                    .disabled(!a.heyAsistan)
                    .accessibilityIdentifier("ayar-arka-plan-uyandirma")
                Text("Ekran kilitlenince ya da başka uygulamaya geçince de “Hey Asistan” beklenir. Turuncu mikrofon noktası sürekli yanar, pil tüketir; iOS dinlemeyi kesebilir. Arka planda ilk komuttan sonra dinleme durabilir; uygulamayı açınca sürer.")
                    .font(.footnote).foregroundStyle(.secondary)
                if ses.uyandirmaHazir {
                    Label("Hey Asistan bekleniyor", systemImage: "ear.badge.waveform")
                } else if let hata = ses.uyandirmaHatasi {
                    Label("Mikrofon yeniden deneniyor: \(hata)", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                } else if ses.uyandirmaBekliyor {
                    Label("Hey Asistan hazırlanıyor", systemImage: "ear.badge.waveform")
                }
            }
            // P4.2: bas-konuş (AsistanBasKonusIntent) ve parametreli kontroller.
            Section("Uygulamayı açmadan") {
                Text("Bas konuş: uygulama ekrana gelmeden tek sesli komut alır, yanıtı sesli söyler. Kilit ekranında ve Dynamic Island'da “Dinliyorum” görünür; 12 saniye komut gelmezse kapanır.")
                Text("1. Eylem Düğmesi: iPhone Ayarlar → Eylem Düğmesi → Kestirme → Asistan → Bas konuş.")
                Text("2. Kilit ekranı ya da Kontrol Merkezi: düzenle → Kontrol ekle → Asistan → Bas konuş.")
                Text("3. Siri: “Asistan bas konuş” ya da “Asistan dinle beni”.")
                Text("Kipli kontrol (Asistan kipi) eklerken dinle, canlı + kamera, son sohbete devam ya da sabah özeti seçilir; bunlar uygulamayı açar. Hey Asistan kontrolü buradaki anahtarla aynı ayarı açıp kapatır; Hey Asistan yine yalnız uygulama öndeyken dinler.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Live'ı ekran kilitliyken sürdürmek için Ayarlar → Ses ve Live → “Live arka planda sürsün” (yalnız Claude motoru, 10 dk sessizlikte kapanır).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Başka uygulamadayken çağır") {
                Text("1. iPhone Ayarlar → Erişilebilirlik → Sesli Kestirmeler bölümünü aç.")
                Text("2. Eylem ekle. Asistan'ı başlat eylemini seç. Listede yoksa Siri İsteği seçip “Asistan ile konuş” yaz.")
                Text("3. Söylenecek ifadeyi “Hey Asistan” yap ve iPhone'un istediği ses tekrarlarını tamamla.")
                Text("Bu kişisel ses kaydını uygulama senin yerine yapamaz. Kilitli telefonda iOS kilidi açmanı isteyebilir. Asistan çağrıldığında kendi ekranında açılır.").font(.footnote).foregroundStyle(.secondary)
                Link("Apple'ın Sesli Kestirmeler rehberi", destination: URL(string: "https://support.apple.com/tr-tr/guide/iphone/iph7f242ea2c/ios")!)
            }
            Section("Diğer uygulamalardan metin aktar") {
                Text("Kestirmeler'de yeni kestirme oluştur. Paylaşım Sayfasında Göster'i aç, Asistan'a metin aktar eylemini ekle ve Metin alanına Kestirme Girdisi'ni bağla. Sonra Safari veya metin paylaşabilen bir uygulamadan Paylaş ile çalıştır.")
                Text("İçerik Asistan'da taslak olarak açılır. Fotoğraf veya ekran görüntüsünü sohbette + düğmesiyle ekleyebilirsin. Diğer uygulamaların ekranı ve mesajları kendiliğinden okunmaz.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Ekrana bak · Arkaya Dokun") {
                Text("1. Kestirmeler'de + ile yeni kestirme oluştur ve Ekran Görüntüsü Al eylemini ekle.")
                Text("2. Uygulamalar → Asistan → Asistan'a göster eylemini ekle. Dosyalar alanına Ekran Görüntüsü'nü bağla; Soru boş kalabilir.")
                Text("3. iPhone Ayarlar → Erişilebilirlik → Dokunma → Arkaya Dokun → İki Kez Dokun bölümünden bu kestirmeyi seç.")
                Text("Telefonun arkasına iki kez dokununca o anki ekranın görüntüsü Asistan'da açılır ve ne olduğu anlatılır. Aynı eylemle Dosyalar'dan PDF ya da metin dosyası da gösterebilirsin (en çok 8 dosya, toplam 40 MB).").font(.footnote).foregroundStyle(.secondary)
                Link("Kestirmeler'i aç", destination: URL(string: "shortcuts://")!)
            }
            Section("Hızlı erişim") {
                Text("Siri: “Asistan ile konuş”. Kontrol Merkezi: Asistan'ı başlat kontrolünü ekle. Arkaya Dokun: Ayarlar → Erişilebilirlik → Dokunma → Arkaya Dokun üzerinden Asistan kestirmesini ya da yukarıdaki ekrana bak kestirmesini seç.")
                Text("Asistan'a göster yalnız Kestirmeler ve Arkaya Dokun ile çalışır; Siri sesle dosya veremez.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Hey Asistan")
    }
}
