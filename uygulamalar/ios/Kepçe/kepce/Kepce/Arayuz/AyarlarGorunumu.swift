import SwiftUI
import UniformTypeIdentifiers

struct AyarlarGorunumu: View {
    @State private var ayarlar = Ayarlar.shared
    @State private var surum: PythonMotoru.Surum?
    @State private var motorDurumu: String?
    @State private var guncelleniyor = false
    @State private var cerezVar = FileManager.default.fileExists(atPath: PythonMotoru.cerezDosyasi.path)
    @State private var cerezSecici = false
    @State private var onbellekBoyutu: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("İndirme") {
                    Picker("Video kalitesi", selection: $ayarlar.enFazlaCozunurluk) {
                        ForEach(Ayarlar.cozunurlukler, id: \.self) { Text(Ayarlar.cozunurlukAdi($0)).tag($0) }
                    }
                    Picker("Hızlı indirme türü", selection: $ayarlar.hizliTur) {
                        ForEach(IndirmeTuru.allCases) { Text($0.ad).tag($0) }
                    }
                    Stepper("Aynı anda \(ayarlar.esZamanli) indirme", value: $ayarlar.esZamanli, in: 1...8)
                    Stepper("Dosya başına \(ayarlar.baglantiSayisi) bağlantı", value: $ayarlar.baglantiSayisi, in: 1...8)
                    Toggle("Videoları Fotoğraflar'a da kaydet", isOn: $ayarlar.fotograflaraKaydet)
                }

                Section {
                    Toggle("Zaten indirilenleri atla", isOn: $ayarlar.indirilenleriAtla)
                    Toggle("Liste adıyla klasöre kaydet", isOn: $ayarlar.listeKlasoru)
                    Toggle("Dosya adına sıra numarası ekle", isOn: $ayarlar.listeNumarala)
                } header: {
                    Text("Toplu ve liste indirme")
                } footer: {
                    Text("Yüzlerce videoda YouTube hız sınırı koyabilir; Kepçe bunu görünce sırayı birkaç dakika bekletip kendiliğinden sürdürür.")
                }

                Section {
                    Picker("Altyazı", selection: $ayarlar.altyaziDili) {
                        Text("İndirme").tag("")
                        Text("Türkçe").tag("tr")
                        Text("İngilizce").tag("en")
                        Text("Almanca").tag("de")
                        Text("Arapça").tag("ar")
                    }
                    Toggle("Yoksa otomatik altyazıyı kullan", isOn: $ayarlar.otomatikAltyazi)
                    Picker("Tercih edilen ses dili", selection: $ayarlar.tercihEdilenSesDili) {
                        Text("Asıl ses").tag("")
                        Text("Türkçe").tag("tr")
                        Text("İngilizce").tag("en")
                    }
                } header: {
                    Text("Altyazı ve ses dili")
                } footer: {
                    Text("Çok dilli seslendirmesi olan videolarda seçilen dil önce gelir.")
                }

                Section("Uygulama") {
                    Toggle("Bitince bildirim gönder", isOn: $ayarlar.bildirim)
                    Toggle("Panodaki bağlantıyı öner", isOn: $ayarlar.panoyuIzle)
                }

                Section {
                    LabeledContent("yt-dlp", value: surum?.yt_dlp ?? "…")
                    LabeledContent("JS çözücü (EJS)", value: surum?.ejs ?? "…")
                    LabeledContent("Python", value: surum?.python ?? "…")
                    Button {
                        Task { await motorIslemi { try await PythonMotoru.shared.guncelle() } }
                    } label: {
                        HStack {
                            Label("yt-dlp'yi güncelle", systemImage: "arrow.triangle.2.circlepath")
                            if guncelleniyor { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(guncelleniyor)
                    if FileManager.default.fileExists(atPath: PythonMotoru.guncelMotor.path) {
                        Button("Paketteki sürüme dön", role: .destructive) {
                            Task { await motorIslemi { try await PythonMotoru.shared.paketSurumuneDon() } }
                        }
                        .disabled(guncelleniyor)
                    }
                    if let motorDurumu { Text(motorDurumu).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text("İndirme motoru")
                } footer: {
                    Text("YouTube sık değişir. İndirme bozulursa önce yt-dlp'yi güncelle; en yeni sürüm PyPI'den telefona kurulur.")
                }

                Section {
                    if cerezVar {
                        Label("Çerez dosyası yüklü", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Button("Çerezleri sil", role: .destructive) {
                            try? FileManager.default.removeItem(at: PythonMotoru.cerezDosyasi)
                            cerezVar = false
                            Task { try? await PythonMotoru.shared.cerezleriYenile() }
                        }
                    }
                    Button(cerezVar ? "Çerez dosyasını değiştir" : "Çerez dosyası (cookies.txt) ekle") { cerezSecici = true }
                } header: {
                    Text("Oturum (isteğe bağlı)")
                } footer: {
                    Text("Yaş sınırlı ya da üyelere özel videolar için tarayıcından dışa aktardığın Netscape biçimli cookies.txt dosyası. Dosya yalnız bu telefonda kalır. Ana hesabın yerine ayrı bir hesap kullanman önerilir.")
                }

                Section("Depolama") {
                    LabeledContent("Kütüphane", value: BicimSecici.boyutMetni(Kutuphane.shared.toplamBoyut))
                    LabeledContent("Geçici dosyalar", value: BicimSecici.boyutMetni(onbellekBoyutu))
                    Button("Geçici dosyaları temizle") {
                        let etkinler = Set(IndirmeKuyrugu.shared.isler.filter { $0.durum != .tamam && $0.durum != .hata }.map(\.id.uuidString))
                        let kok = IndirmeKuyrugu.calismaKoku
                        for ad in (try? FileManager.default.contentsOfDirectory(atPath: kok.path)) ?? [] where !etkinler.contains(ad) {
                            try? FileManager.default.removeItem(at: kok.appending(path: ad))
                        }
                        onbellekBoyutu = Self.boyut(kok)
                    }
                }

                Section {
                    Text("Kepçe yalnızca hakkına sahip olduğun ya da indirmeye izin verilen içerikler (kendi videoların, Creative Commons lisanslı içerikler, eğitim amaçlı kişisel kopyalar) için tasarlandı. Sitelerin kullanım koşullarına ve telif haklarına uymak senin sorumluluğundadır. DRM korumalı içerik indirilemez.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Hakkında")
                }
            }
            .navigationTitle("Ayarlar")
            .task {
                surum = try? await PythonMotoru.shared.surum()
                onbellekBoyutu = Self.boyut(IndirmeKuyrugu.calismaKoku)
            }
            .fileImporter(isPresented: $cerezSecici, allowedContentTypes: [.plainText, .data]) { sonuc in
                guard case .success(let url) = sonuc else { return }
                let erisim = url.startAccessingSecurityScopedResource()
                defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                guard let veri = try? Data(contentsOf: url), String(decoding: veri, as: UTF8.self).contains("\t") else {
                    motorDurumu = "Bu dosya Netscape çerez biçiminde görünmüyor."
                    return
                }
                try? veri.write(to: PythonMotoru.cerezDosyasi, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                cerezVar = true
                Task { try? await PythonMotoru.shared.cerezleriYenile() }
            }
        }
    }

    private func motorIslemi(_ islem: () async throws -> PythonMotoru.Surum) async {
        guncelleniyor = true
        motorDurumu = nil
        do {
            let yeni = try await islem()
            motorDurumu = yeni.yt_dlp == surum?.yt_dlp ? "Zaten güncel (\(yeni.yt_dlp))." : "yt-dlp \(yeni.yt_dlp) kuruldu."
            surum = yeni
        } catch {
            motorDurumu = error.localizedDescription
        }
        guncelleniyor = false
    }

    static func boyut(_ kok: URL) -> Int64 {
        guard let sayici = FileManager.default.enumerator(at: kok, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var toplam: Int64 = 0
        for case let url as URL in sayici { toplam += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return toplam
    }
}
