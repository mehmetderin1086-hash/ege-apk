import SwiftUI
import UniformTypeIdentifiers

struct KisiselAlanEkrani: View {
    enum Bolum: String, CaseIterable { case komutlar = "Komutlar", yanitlar = "Kaydedilenler" }
    @Environment(KisiselAlan.self) private var alan
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var bolum: Bolum
    @State private var sorgu = ""
    @State private var duzenlenen: HazirKomut?
    @State private var yedek: KisiselAlanBelgesi?
    @State private var disaAktar = false
    @State private var iceAktar = false
    @State private var mesaj: String?
    /// Geri yükleme mevcut içeriğin tamamını değiştirir: dosya önce okunup doğrulanır, sonra onay sorulur.
    @State private var bekleyenYedek: Data?
    @State private var yedekOzeti = ""
    @State private var yedekSorusu = false
    /// Sohbet ekranı, seçilen komutu doğrudan kendi yazı alanına aktarabilir.
    /// Bağımsız kullanımda `disTaslak` eski davranış olarak korunur.
    private let taslakSecildi: ((String) -> Void)?
    init(baslangic: Bolum = .komutlar, taslakSecildi: ((String) -> Void)? = nil) {
        _bolum = State(initialValue: baslangic)
        self.taslakSecildi = taslakSecildi
    }
    var body: some View {
        List {
            Picker("Bölüm", selection: $bolum) { ForEach(Bolum.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if let hata = alan.hata { Text(hata).font(.footnote).foregroundStyle(.red) }
            if bolum == .komutlar {
                Section {
                    ForEach(alan.icerik.komutlar.filter { eslesir($0.baslik + " " + $0.metin) }) { komut in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(komut.baslik, systemImage: komut.simge).font(.headline)
                            Text(komut.metin).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            HStack {
                                Button("Taslağa ekle", systemImage: "text.badge.plus") {
                                    if let taslakSecildi {
                                        taslakSecildi(komut.metin)
                                    } else {
                                        beyin.disTaslak = komut.metin
                                    }
                                    kapat()
                                }
                                Spacer()
                                Button("Düzenle", systemImage: "pencil") { duzenlenen = komut }
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical, 4)
                            .swipeActions { Button("Sil", role: .destructive) { alan.komutSil(komut.id) } }
                    }
                    .onMove { kaynak, hedef in if sorgu.isEmpty { alan.tasi(kaynak, hedef: hedef) } }
                    .moveDisabled(!sorgu.isEmpty)
                    if alan.icerik.komutlar.filter({ eslesir($0.baslik + " " + $0.metin) }).isEmpty {
                        ContentUnavailableView("Komut bulunamadı", systemImage: "text.badge.plus", description: Text("+ ile kendi komutunu oluşturabilirsin."))
                    }
                } footer: { Text("Komutlar taslak olarak açılır. Düzenle düğmesiyle metni değiştirebilir, üstteki Sırala ile kartların yerini değiştirebilirsin.") }
            } else {
                ForEach(alan.icerik.yanitlar.filter { eslesir($0.metin) }) { yanit in
                    NavigationLink {
                        ScrollView { Text(yanit.metin).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                            .navigationTitle("Kaydedilen yanıt")
                            .toolbar { ShareLink(item: yanit.metin) { Label("Paylaş", systemImage: "square.and.arrow.up") } }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(yanit.baslik).lineLimit(3)
                            Text(yanit.tarih, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Kaldır", role: .destructive) { alan.yanitSil(yanit.id) } }
                }
                if alan.icerik.yanitlar.filter({ eslesir($0.metin) }).isEmpty {
                    ContentUnavailableView("Kaydedilen yanıt yok", systemImage: "bookmark", description: Text("Sohbette bir yanıta uzun basıp Kaydet'i seç."))
                }
            }
        }
        .navigationTitle("Kişisel alanım")
        .onAppear { alan.yenidenDene() }   // telefon kilitliyken açılan süreçte dosya okunamadıysa
        .searchable(text: $sorgu, prompt: bolum == .komutlar ? "Komut ara" : "Kaydedilen yanıtlarda ara")
        .toolbar {
            if bolum == .komutlar {
                ToolbarItem(placement: .topBarTrailing) { Button("Komut ekle", systemImage: "plus") { duzenlenen = HazirKomut(baslik: "", metin: "") } }
                ToolbarItem(placement: .topBarLeading) { EditButton().disabled(!sorgu.isEmpty).accessibilityLabel("Komutları sırala") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Menu {
                Button("Yedeği dosyaya aktar", systemImage: "square.and.arrow.up") {
                    do { yedek = .init(data: try alan.yedekVerisi()); disaAktar = true }
                    catch { mesaj = "Yedek oluşturulamadı: \(error.localizedDescription)" }
                }
                Button("Yedeği dosyadan geri yükle", systemImage: "square.and.arrow.down") { iceAktar = true }
                if alan.oncekiIcerik != nil {
                    Button("Son geri yüklemeyi geri al", systemImage: "arrow.uturn.backward") {
                        mesaj = alan.geriYuklemeyiGeriAl() ? "Geri yüklemeden önceki içerik geri getirildi." : (alan.hata ?? "Geri alınamadı.")
                    }
                }
            } label: {
                Label("Kişisel alan yedeği", systemImage: "externaldrive.badge.checkmark")
                    .font(.footnote)
            }
            .padding(.vertical, 8)
        }
        .fileExporter(isPresented: $disaAktar, document: yedek, contentType: .json, defaultFilename: "Mehmet-Asistan-Kisisel-Alan") { sonuc in
            if case .failure(let hata) = sonuc { mesaj = "Yedek dışa aktarılamadı: \(hata.localizedDescription)" }
        }
        .fileImporter(isPresented: $iceAktar, allowedContentTypes: [.json]) { sonuc in
            do {
                let url = try sonuc.get(); let erisim = url.startAccessingSecurityScopedResource()
                defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                // Güvenlik kapsamı kapanınca okunamaz: veri burada okunur, geri yükleme onaydan sonra yapılır.
                let veri = try Data(contentsOf: url)
                // Kilit yüzünden okunamamışsa önce yeniden okunur; özet boş (0 komut) içerikle yanıltmasın.
                alan.yenidenDene()
                // Yalnız okuma hatası (KisiselAlan.oku metinleri) uyarı olur; başka işlemin eski hatası özete karışmasın.
                let durumUyarisi = alan.hata.flatMap { $0.contains("okunamadı") || $0.contains("kilidi açılınca") ? $0 : nil }
                guard let y = alan.yedegiCoz(veri) else { mesaj = alan.hata ?? "Kişisel alan yedeği geçersiz; mevcut içerik korunuyor."; return }
                yedekOzeti = Self.yedekOzetiMetni(mevcutKomut: alan.icerik.komutlar.count, mevcutYanit: alan.icerik.yanitlar.count,
                                             yedekKomut: y.komutlar.count, yedekYanit: y.yanitlar.count, uyari: durumUyarisi)
                bekleyenYedek = veri
                yedekSorusu = true
            } catch { mesaj = "Yedek yüklenemedi; mevcut içerik korundu. \(error.localizedDescription)" }
        }
        .confirmationDialog("Yedek geri yüklensin mi?", isPresented: $yedekSorusu, titleVisibility: .visible) {
            Button("Değiştir", role: .destructive) {
                if let v = bekleyenYedek, alan.yedegiYukle(v) { mesaj = "Kişisel alan yedeği geri yüklendi. Menüden geri alabilirsin." }
                else { mesaj = alan.hata ?? "Yedek yüklenemedi; mevcut içerik korundu." }
                bekleyenYedek = nil
            }
            Button("Vazgeç", role: .cancel) { bekleyenYedek = nil }
        } message: { Text(yedekOzeti) }
        .alert("Kişisel alan", isPresented: Binding(get: { mesaj != nil }, set: { if !$0 { mesaj = nil } })) {
            Button("Tamam") { mesaj = nil }
        } message: { Text(mesaj ?? "") }
        .sheet(item: $duzenlenen) { komut in KomutDuzenleyici(komut: komut) }
    }
    private func eslesir(_ metin: String) -> Bool { sorgu.isEmpty || metin.localizedStandardContains(sorgu) }

    /// Geri yükleme onay metni. Geri alma bir sonraki geri yüklemeye kadar (yeniden açılışta da) sürdüğü için süresi açıkça söylenir;
    /// mevcut alan okunamıyorsa (bozuk dosya) uyarı başa eklenir, "0 komut" özeti yanıltmasın.
    nonisolated static func yedekOzetiMetni(mevcutKomut: Int, mevcutYanit: Int, yedekKomut: Int, yedekYanit: Int, uyari: String?) -> String {
        let ozet = "Mevcut \(mevcutKomut) komut ve \(mevcutYanit) kayıtlı yanıt, yedekteki \(yedekKomut) komut ve \(yedekYanit) yanıtla değiştirilecek. Bir sonraki geri yüklemeye kadar menüden geri alabilirsin."
        guard let uyari, !uyari.isEmpty else { return ozet }
        return "Uyarı: \(uyari)\n\n" + ozet
    }
}

private struct KisiselAlanBelgesi: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct KomutDuzenleyici: View {
    @Environment(KisiselAlan.self) private var alan
    @Environment(\.dismiss) private var kapat
    @State var komut: HazirKomut
    var body: some View {
        NavigationStack {
            Form {
                Section("Kart") {
                    TextField("Başlık", text: $komut.baslik).onChange(of: komut.baslik) { _, v in komut.baslik = String(v.prefix(40)) }
                    Picker("Simge", selection: $komut.simge) {
                        ForEach(["sparkles", "calendar", "text.alignleft", "chevron.left.forwardslash.chevron.right", "book", "text.bubble", "lightbulb", "checklist", "star", "music.note"], id: \.self) { Image(systemName: $0).tag($0) }
                    }
                }
                Section("Komut metni") {
                    TextEditor(text: $komut.metin).frame(minHeight: 180).accessibilityLabel("Komut metni")
                    Text("\(komut.metin.count) / 4000 karakter").font(.caption).foregroundStyle(.secondary)
                }
                if let hata = alan.hata { Text(hata).foregroundStyle(.red) }
            }
            .navigationTitle("Komutu düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { if alan.komutKaydet(komut) { kapat() } }.disabled(komut.baslik.trimmingCharacters(in: .whitespaces).isEmpty || komut.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || komut.metin.count > 4000) }
            }
        }
    }
}
