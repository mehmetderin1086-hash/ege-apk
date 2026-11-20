import Photos
import SwiftUI

/// P4.4: Ayarlar → Sistem araması. Spotlight'ta sohbet başlıkları her zaman aranabilir; içerik özeti ve fotoğraf metni
/// indeksi varsayılan KAPALI (gizlilik ve pil). Ayarlar yalnız bayrağı tutar; yeniden kurulum/planlama burada tetiklenir.
struct SistemAramasiAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(Beyin.self) private var beyin
    @State private var metinli = 0
    @State private var islenen = 0
    @State private var calisiyor = false

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section {
                Toggle("Spotlight'ta içerik özeti", isOn: $a.spotlightIcerik)
                    .accessibilityIdentifier("ayar-spotlight-icerik")
                Button("Spotlight indeksini yeniden kur") {
                    AsistanSpotlight.tamYenile(depo: beyin.depo, zorla: true)
                    AsistanSpotlight.dosyalariYenile(IndirmeYoneticisi.ortak.kayitlar)
                    TostDefteri.ortak.goster("Spotlight indeksi yeniden kuruluyor")
                }
                .accessibilityIdentifier("spotlight-yeniden-kur")
                Button("Spotlight indeksini temizle", role: .destructive) {
                    AsistanSpotlight.hepsiniSil()
                    TostDefteri.ortak.goster("Spotlight indeksi temizlendi", simge: "trash")
                }
                .accessibilityIdentifier("spotlight-temizle")
            } header: {
                Text("Spotlight")
            } footer: {
                Text("Sohbet başlıkları ve indirilen dosyalar Spotlight'ta aranabilir. Özet açıkken sohbetin ilk mesajının ilk 200 karakteri de eklenir. Hafızadaki kişisel bilgiler Spotlight'a hiç girmez; yalnız Kestirmeler'deki 'Asistan hafızasında bul' eylemi okur.")
            }

            Section {
                Toggle("Fotoğraf metni indeksi", isOn: $a.fotoMetinIndeksi)
                    .accessibilityIdentifier("ayar-foto-metin")
                LabeledContent("Yazısı aranabilir", value: "\(metinli) fotoğraf")
                    .accessibilityIdentifier("foto-indeks-sayisi")
                LabeledContent("Okunan", value: "\(islenen) fotoğraf")
                if ayarlar.fotoMetinIndeksi {
                    Button {
                        Task { await simdiIndeksle() }
                    } label: {
                        HStack {
                            Text("Şimdi 300 fotoğraf oku")
                            if calisiyor { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(calisiyor)
                    .accessibilityIdentifier("foto-indeks-simdi")
                }
                Button("Fotoğraf metni indeksini temizle", role: .destructive) {
                    Task {
                        await Task.detached(priority: .utility) { FotoIndeksi.ortak.temizle() }.value
                        await sayilariYenile()
                    }
                }
                .accessibilityIdentifier("foto-indeks-temizle")
            } header: {
                Text("Fotoğraflar")
            } footer: {
                Text("Açıkken telefon şarjdayken fotoğraflardaki yazılar cihaz içinde okunur; yalnız telefonda duran küçük resimler kullanılır, iCloud'dan indirme yapılmaz. Metin yalnız bu telefonda, ayrı bir dosyada tutulur ve yedeğe girmez.")
            }
        }
        .navigationTitle("Sistem araması")
        .onChange(of: ayarlar.spotlightIcerik) { _, _ in
            AsistanSpotlight.tamYenile(depo: beyin.depo, zorla: true)
        }
        .onChange(of: ayarlar.fotoMetinIndeksi) { _, yeni in
            FotoIndeksi.planla(acik: yeni)
            if yeni, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                Task { await IzinIstegi.fotograflar() }
            }
        }
        .task { await sayilariYenile() }
    }

    private func sayilariYenile() async {
        let s = await Task.detached(priority: .utility) { (FotoIndeksi.ortak.sayi(), FotoIndeksi.ortak.islenenSayisi()) }.value
        metinli = s.0
        islenen = s.1
    }

    /// Uygulama açıkken bir tur (arka plan görevini beklemeden); iş ana iş parçacığı dışında yürür.
    private func simdiIndeksle() async {
        guard !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        let durum = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if durum == .notDetermined { await IzinIstegi.fotograflar() }
        let izin = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard izin == .authorized || izin == .limited else {
            TostDefteri.ortak.goster("Fotoğraflar izni kapalı", simge: "exclamationmark.triangle")
            return
        }
        _ = await Task.detached(priority: .userInitiated) { await FotoIndeksi.ortak.calistir(ayarDenetle: false) }.value
        await sayilariYenile()
        TostDefteri.ortak.goster("Fotoğraf yazıları okundu")
    }
}
