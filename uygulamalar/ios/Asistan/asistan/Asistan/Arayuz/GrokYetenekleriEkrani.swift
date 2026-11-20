import SwiftUI

struct GrokYetenekleriEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var takim = UzmanTakimi.ortak
    @State private var kitaplik = BeceriKitapligi.ortak
    @State private var sunucu = SunucuGorevleri.ortak
    @State private var yeniUzman = false
    @State private var yeniBeceri = false
    @State private var yeniRutin = false
    @State private var paylasim: URL?
    @Environment(Ayarlar.self) private var ayarlar
    @State private var rutinYukleniyor = true
    @State private var rutinBildirim: String?
    @State private var sinanan: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("En fazla 6 uzmanı birlikte seç. Mesajda @Araştırmacı gibi bir ad kullanırsan yalnız etiketlediğin uzman o isteğe katılır.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(takim.uzmanlar) { uzman in
                        let secili = takim.secilenler.contains(uzman.id)
                        HStack(alignment: .top) {
                            Button { takim.sec(uzman.id) } label: {
                                Image(systemName: secili ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                            }.buttonStyle(.plain)
                            .disabled(!Self.secimAcik(secili: secili, sayi: takim.secilenler.count))
                            .accessibilityLabel(uzman.ad)
                            .accessibilityAddTraits(secili ? .isSelected : [])
                            .accessibilityHint(secili ? "Uzmanı takımdan çıkarır" : "Uzmanı takıma ekler")
                            Image(systemName: uzman.simge).frame(width: 24).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(uzman.ad).font(.headline)
                                Text(uzman.unvan).font(.caption).foregroundStyle(.secondary)
                                Text(uzman.aciklama).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Spacer()
                            Menu {
                                Button("Çoğalt", systemImage: "plus.square.on.square") { takim.cogalt(uzman) }
                                Button("Profili paylaş", systemImage: "square.and.arrow.up") { paylasim = try? takim.disariAktar(uzman) }
                                if !uzman.sablon { Button("Sil", systemImage: "trash", role: .destructive) { takim.sil(uzman) } }
                            } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("\(uzman.ad) seçenekleri")
                        }
                    }
                    Button("Yeni uzman oluştur", systemImage: "person.crop.circle.badge.plus") { yeniUzman = true }
                } header: { Text("Uzman botlar · \(takim.secilenler.count)/6 etkin") }

                Section("Beceri kütüphanesi") {
                    ForEach(kitaplik.beceriler) { beceri in
                        Button {
                            beyin.disTaslak = beceri.istem
                            kapat()
                        } label: {
                            Label {
                                VStack(alignment: .leading) { Text(beceri.ad); Text(beceri.istem).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            } icon: { Image(systemName: beceri.simge) }
                        }.swipeActions { if !beceri.sablon { Button("Sil", role: .destructive) { kitaplik.sil(beceri) } } }
                    }
                    Button("Yeni beceri kaydet", systemImage: "wand.and.stars") { yeniBeceri = true }
                }

                Section("Zamanlanmış rutinler") {
                    if let hata = sunucu.rutinHatasi {
                        Text(hata).foregroundStyle(.red).font(.footnote)
                        Button("Yeniden dene", systemImage: "arrow.clockwise") { Task { await rutinleriYukle() } }.disabled(rutinYukleniyor)
                    } else if rutinYukleniyor && sunucu.rutinler.isEmpty {
                        ProgressView()
                    } else if sunucu.rutinler.isEmpty { Text("Henüz rutin yok.").foregroundStyle(.secondary) }
                    if let rutinBildirim { Text(rutinBildirim).font(.footnote).foregroundStyle(rutinBildirim.hasPrefix("Gönderilemedi") ? Color.red : Color.secondary) }
                    ForEach(sunucu.rutinler) { rutin in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                VStack(alignment: .leading) { Text(rutin.name).font(.headline); Text("Her \(rutin.intervalMinutes) dakikada · \(rutin.kind)").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Toggle("", isOn: Binding(get: { rutin.etkin }, set: { etkin in
                                    Task {
                                        // Başarıda rutinHatasi alanını rutinleriYenile kendisi temizler; iç yenileme başarısızsa hata görünür kalır.
                                        // Görev listesi hatası (sunucu.hata) ayrıdır; rutin işlemi ona dokunmaz.
                                        do { try await sunucu.rutinEtkin(rutin, etkin: etkin) }
                                        catch { sunucu.rutinHatasi = error.localizedDescription }
                                    }
                                })).labelsHidden()
                            }
                            Text(rutin.prompt).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Button(sinanan == rutin.id ? "Gönderiliyor…" : "Şimdi sına") {
                                    sinanan = rutin.id; rutinBildirim = nil
                                    Task {
                                        // Gönderim sonucu satır bildirimine yazılır; ortak sunucu.hata / rutinHatasi alanlarına dokunulmaz
                                        // (liste hatasını silmesin, "Yeniden dene" gönderimi yinelemediği için onu da göstermesin).
                                        do { _ = try await sunucu.ekle(rutin.prompt, tur: rutin.kind); rutinBildirim = "Sunucuya gönderildi; sonuç Sunucu görevleri bölümüne düşer." }
                                        catch { rutinBildirim = "Gönderilemedi: \(error.localizedDescription)" }
                                        sinanan = nil
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(!ayarlar.sunucuGorevleri || sinanan != nil)
                                Spacer()
                                Button("Sil", role: .destructive) {
                                    Task {
                                        do { try await sunucu.rutinSil(rutin) }
                                        catch { sunucu.rutinHatasi = error.localizedDescription }
                                    }
                                }.buttonStyle(.borderless)
                            }.font(.caption)
                        }
                    }
                    Button("Yeni rutin", systemImage: "calendar.badge.clock") { yeniRutin = true }
                    Text("Rutin sunucuda çalışır; iPhone kapalı olsa da sürer. En kısa aralık 5 dakikadır. Sonuç Sunucu görevleri bölümüne düşer.").font(.footnote).foregroundStyle(.secondary)
                }

                Section("Çalışma düzeni") {
                    Label("Kalıcı iPhone hafızası ve sohbet arşivi", systemImage: "brain.head.profile")
                    Label("Telefon kapalıyken süren sunucu görevleri", systemImage: "server.rack")
                    Label("Otomatik model, düşünme ve kota yönlendirmesi", systemImage: "arrow.triangle.branch")
                    Text("iOS, uygulamaya başka uygulamaların özel ekranlarını sürekli yönetme veya sınırsız arka plan çalışma izni vermez. Bu işler bağlı Kestirmeler ve mevcut özel sunucu kuyruğuyla yürütülür.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Uzmanlar ve Beceriler")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .sheet(isPresented: $yeniUzman) { YeniUzmanEkrani() }
            .sheet(isPresented: $yeniBeceri) { YeniBeceriEkrani() }
            .sheet(isPresented: $yeniRutin) { YeniRutinEkrani() }
            .sheet(isPresented: Binding(get: { paylasim != nil }, set: { if !$0 { paylasim = nil } })) {
                if let paylasim { NavigationStack { ShareLink(item: paylasim) { Label("Uzman profilini paylaş", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).padding().navigationTitle("Profili paylaş") } }
            }
            .task { await rutinleriYukle() }
        }
    }

    private func rutinleriYukle() async {
        rutinYukleniyor = true
        await sunucu.rutinleriYenile()
        rutinYukleniyor = false
    }

    /// Uzman seçim düğmesi açık mı: seçili olan her zaman çıkarılabilir; 6 sınırı dolunca yenisi eklenemez (`UzmanTakimi.sec` ile aynı kural).
    nonisolated static func secimAcik(secili: Bool, sayi: Int) -> Bool { secili || sayi < 6 }
}

private struct YeniRutinEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var istem = ""
    @State private var tur = "text"
    @State private var dakika = 60
    @State private var kaydediliyor = false
    @State private var hata: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Rutin adı", text: $ad)
                TextField("Yapılacak iş", text: $istem, axis: .vertical).lineLimit(5...12)
                Picker("Tür", selection: $tur) { Text("Metin").tag("text"); Text("Kaynaklı araştırma").tag("research"); Text("Kod").tag("code") }
                Stepper("Her \(dakika) dakika", value: $dakika, in: 5...10080, step: 5)
                if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Yeni rutin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button(kaydediliyor ? "Kaydediliyor…" : "Kaydet") {
                    kaydediliyor = true; hata = nil
                    Task { do { try await SunucuGorevleri.ortak.rutinEkle(ad: ad, metin: istem, tur: tur, dakika: dakika); kapat() } catch { hata = error.localizedDescription; kaydediliyor = false } }
                }.disabled(kaydediliyor || ad.trimmingCharacters(in: .whitespaces).isEmpty || istem.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }
}

private struct YeniUzmanEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var unvan = ""
    @State private var aciklama = ""
    var body: some View {
        NavigationStack { Form { TextField("Uzman adı", text: $ad); TextField("Görevi / unvanı", text: $unvan); TextField("Daimi çalışma kuralları", text: $aciklama, axis: .vertical).lineLimit(5...12) }
            .navigationTitle("Yeni uzman").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }; ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { UzmanTakimi.ortak.ekle(ad: ad, unvan: unvan, aciklama: aciklama); kapat() }.disabled(ad.trimmingCharacters(in: .whitespaces).isEmpty || aciklama.trimmingCharacters(in: .whitespaces).isEmpty) } } }
    }
}

private struct YeniBeceriEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var istem = ""
    var body: some View {
        NavigationStack { Form { TextField("Beceri adı", text: $ad); TextField("Her çalıştırmada uygulanacak adımlar", text: $istem, axis: .vertical).lineLimit(6...14) }
            .navigationTitle("Yeni beceri").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }; ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { BeceriKitapligi.ortak.ekle(ad: ad, istem: istem); kapat() }.disabled(ad.trimmingCharacters(in: .whitespaces).isEmpty || istem.trimmingCharacters(in: .whitespaces).isEmpty) } } }
    }
}
