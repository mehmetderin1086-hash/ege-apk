import SwiftUI
import Charts

/// Hermes tarzı beceriler: asistanın oluşturduğu ya da senin yazdığın yeniden kullanılabilir yöntem notları.
struct BecerilerEkrani: View {
    @State private var liste = BeceriDeposu.listele()
    @State private var yeniAcik = false

    var body: some View {
        List {
            Section {
                Text("Asistan karmaşık bir işi çözünce yöntemini beceri olarak kaydeder, benzer işte yeniden kullanır ve eksik çıkarsa günceller. Buradan okuyabilir, ekleyebilir ya da silebilirsin.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Kayıtlı beceriler (\(liste.count))") {
                if liste.isEmpty { Text("Henüz beceri yok.").foregroundStyle(.secondary) }
                ForEach(liste, id: \.ad) { b in
                    NavigationLink {
                        ScrollView { Text(b.icerik).frame(maxWidth: .infinity, alignment: .leading).padding() }
                            .navigationTitle(b.ad).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.ad).font(.body.weight(.medium))
                            Text(b.aciklama).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .onDelete { idx in idx.map { liste[$0].ad }.forEach { BeceriDeposu.sil($0) }; liste = BeceriDeposu.listele() }
            }
        }
        .navigationTitle("Beceriler")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { yeniAcik = true } label: { Image(systemName: "plus") }.accessibilityLabel("Yeni beceri") } }
        .sheet(isPresented: $yeniAcik, onDismiss: { liste = BeceriDeposu.listele() }) { YeniBeceriFormu() }
        .onAppear { liste = BeceriDeposu.listele() }
    }
}

private struct YeniBeceriFormu: View {
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var aciklama = ""
    @State private var icerik = ""
    @State private var hata: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ad") { TextField("ör. haftalik-plan", text: $ad).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section("Ne zaman kullanılır?") { TextField("Tek cümle", text: $aciklama, axis: .vertical) }
                Section("Adımlar (Markdown)") { TextEditor(text: $icerik).frame(minHeight: 160) }
                if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Yeni beceri").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do { try BeceriDeposu.kaydet(ad: ad, aciklama: aciklama, icerik: icerik); kapat() }
                        catch { hata = error.localizedDescription }
                    }
                }
            }
        }
    }
}

/// MCP sunucuları: asistan bu sunucuların araçlarını `mcp` aracıyla kullanır (çağrılar onay ister).
struct McpEkrani: View {
    @State private var kayit = McpKaydi.ortak
    @State private var ad = ""
    @State private var url = ""
    @State private var yetki = ""
    @State private var durum: [UUID: String] = [:]
    @State private var hata: String?
    /// P4.5: 401 alınan sunucular (WWW-Authenticate değeriyle); bunlarda "OAuth ile bağlan" görünür.
    @State private var yetkiIsteyen: [UUID: String] = [:]
    @State private var oauthRozeti: [UUID: String] = [:]
    @State private var oauthSuruyor = false

    var body: some View {
        Form {
            Section {
                Text("Uzak MCP sunucularını (Streamable HTTP) bağla; asistan araçlarını görür ve kullanır. Şeması düz olan araçlar modele doğrudan 'mcp_<sunucu>_<araç>' adıyla açılır. Dış sisteme etki eden her çağrı için sana onay sorulur. Yalnız https adresleri (ya da localhost) kabul edilir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Bağlı sunucular") {
                if kayit.sunucular.isEmpty { Text("Henüz sunucu yok.").foregroundStyle(.secondary) }
                ForEach(kayit.sunucular) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.ad).font(.body.weight(.medium))
                        Text(s.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let r = oauthRozeti[s.id] {
                            Text(r).font(.caption2.weight(.medium)).foregroundStyle(.green).accessibilityIdentifier("mcp-oauth-rozeti")
                        }
                        HStack {
                            Button("Bağlantıyı dene") { Task { await dene(s) } }.font(.caption)
                            if let d = durum[s.id] { Text(d).font(.caption).foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 16) {
                            Button("Araç listesini yenile") { Task { await dene(s) } }.font(.caption2)
                                .accessibilityIdentifier("mcp-araclari-yenile")
                            if yetkiIsteyen[s.id] != nil || oauthRozeti[s.id] != nil {
                                Button("OAuth ile bağlan") { Task { await oauthBaglan(s, www: yetkiIsteyen[s.id]) } }.font(.caption2)
                                    .disabled(oauthSuruyor)
                                    .accessibilityIdentifier("mcp-oauth-\(s.ad)")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { idx in idx.map { kayit.sunucular[$0].id }.forEach { kayit.sil($0) } }
            }
            Section("Sunucu ekle") {
                TextField("Ad (ör. notlar)", text: $ad).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("https://…/mcp", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Authorization değeri (isteğe bağlı, ör. Bearer …)", text: $yetki)
                if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                Button("Ekle") {
                    if kayit.ekle(ad: ad, url: url, yetki: yetki) { ad = ""; url = ""; yetki = ""; hata = nil }
                    else { hata = kayit.sonHata ?? "Ad boş olamaz; adres https:// ile başlamalı." }
                }
                // P4.5 OAuth 2.1 + PKCE: sunucu yetki istiyorsa tarayıcıda giriş yapılır, belirteç Keychain'e yazılır.
                Button(oauthSuruyor ? "OAuth sürüyor…" : "OAuth ile bağlan") {
                    guard kayit.ekle(ad: ad, url: url), let s = kayit.bul(ad) else {
                        hata = kayit.sonHata ?? "Ad boş olamaz; adres https:// ile başlamalı."; return
                    }
                    ad = ""; url = ""; yetki = ""; hata = nil
                    Task { await oauthBaglan(s, www: nil) }
                }
                .disabled(oauthSuruyor)
                .accessibilityIdentifier("mcp-oauth")
            }
        }
        .navigationTitle("MCP sunucuları")
        .onAppear { rozetleriYenile() }
    }

    private func rozetleriYenile() {
        var r: [UUID: String] = [:]
        for s in kayit.sunucular {
            guard let b = McpOAuth.belirtecOku(s.id) else { continue }
            r[s.id] = b.bitis.map { "Yetkili · süresi \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Yetkili (OAuth)"
        }
        oauthRozeti = r
    }

    /// Bağlantıyı dener ve araç listesi önbelleğini (bellek + kalıcı) ağdan yeniler.
    private func dene(_ s: McpSunucu) async {
        durum[s.id] = "deniyor…"
        do {
            let l = try await McpIstemci.araclar(s, tazele: true)
            let dogrudan = min(McpKaydi.sunucuBasinaDinamik, l.filter { McpSemaCevirici.sema($0.sema) != nil }.count)
            durum[s.id] = "✓ \(l.count) araç · \(dogrudan) doğrudan"
            yetkiIsteyen[s.id] = nil
        } catch McpIstemci.Hata.yetkiGerekli(let w) {
            yetkiIsteyen[s.id] = w ?? ""
            durum[s.id] = "✗ Yetki gerekli (401): OAuth ile bağlanabilirsin."
        } catch { durum[s.id] = "✗ \(error.localizedDescription)" }
        rozetleriYenile()
    }

    private func oauthBaglan(_ s: McpSunucu, www: String?) async {
        oauthSuruyor = true
        defer { oauthSuruyor = false }
        durum[s.id] = "OAuth: tarayıcıda giriş bekleniyor…"
        do {
            _ = try await McpOAuthOturumu().baglan(s, wwwAuthenticate: (www?.isEmpty ?? true) ? nil : www)
            yetkiIsteyen[s.id] = nil
            rozetleriYenile()
            if let guncel = kayit.sunucular.first(where: { $0.id == s.id }) { await dene(guncel) }
        } catch { durum[s.id] = "✗ OAuth: \(error.localizedDescription)" }
    }
}


/// OpenClaw tarzı çalışma alanı: asistanın her sohbette okuduğu Markdown dosyaları ve günlük notlar.
struct CalismaAlaniEkrani: View {
    @State private var metinler: [CalismaAlani.Dosya: String] = [:]
    /// Diskteki hâl: kaydedilmemiş değişiklik bununla karşılaştırılır.
    @State private var kayitli: [CalismaAlani.Dosya: String] = [:]
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var gunluk = ""

    /// Kaydedilmemiş değişikliği olan dosyalar (baştaki/sondaki boşluk sayılmaz; `CalismaAlani.yaz` da kırpar).
    nonisolated static func degisenler(_ metinler: [CalismaAlani.Dosya: String], kayitli: [CalismaAlani.Dosya: String]) -> [CalismaAlani.Dosya] {
        [CalismaAlani.Dosya.soul, .user, .agents].filter {
            (metinler[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != (kayitli[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Sınırı aşan ilk dosya: biri aşıyorsa hiçbiri yazılmaz (yarım kayıt olmasın).
    nonisolated static func sinirAsan(_ metinler: [CalismaAlani.Dosya: String]) -> CalismaAlani.Dosya? {
        [CalismaAlani.Dosya.soul, .user, .agents].first { (metinler[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count > CalismaAlani.enFazlaKarakter }
    }

    /// Kaydedilmemiş değişiklik var ve bir dosya sınırı aşıyor: çıkışta otomatik kayıt yapılamaz, düzenleme kaybolurdu.
    /// Bu durumda geri oku gizlenir; çıkış yalnız onaylı "Değişiklikleri at" yolundan olur.
    nonisolated static func cikisKilitliMi(_ metinler: [CalismaAlani.Dosya: String], kayitli: [CalismaAlani.Dosya: String]) -> Bool {
        !degisenler(metinler, kayitli: kayitli).isEmpty && sinirAsan(metinler) != nil
    }

    private var kirli: Bool { !Self.degisenler(metinler, kayitli: kayitli).isEmpty }
    private var cikisKilitli: Bool { Self.cikisKilitliMi(metinler, kayitli: kayitli) }
    @Environment(\.dismiss) private var kapat
    @State private var atmaSor = false

    private func bagla(_ d: CalismaAlani.Dosya) -> Binding<String> {
        Binding(get: { metinler[d] ?? "" }, set: { metinler[d] = $0 })
    }

    var body: some View {
        Form {
            Section {
                Text("Asistan bu dosyaları her sohbette bağlam olarak okur. SOUL ve AGENTS'ı asistan ancak senin onayınla değiştirir; USER ve günlüğe kendi ekleyebilir. Her dosya en çok \(CalismaAlani.enFazlaKarakter) karakter.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach([CalismaAlani.Dosya.soul, .user, .agents], id: \.self) { d in
                Section(d.baslik) {
                    TextEditor(text: bagla(d)).frame(minHeight: 100).font(.callout)
                        .accessibilityIdentifier("calisma-\(d.rawValue)")
                    if (metinler[d] ?? "").isEmpty { Text(d.ipucu).font(.caption).foregroundStyle(.secondary) }
                    let n = (metinler[d] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
                    if n > CalismaAlani.enFazlaKarakter { Text("\(n)/\(CalismaAlani.enFazlaKarakter) karakter: kısaltmadan kaydedilemez.").font(.caption).foregroundStyle(.orange) }
                }
            }
            if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
            if let bilgi { Text(bilgi).foregroundStyle(.secondary).font(.footnote) }
            Section("Günlük notlar (son 3 gün)") {
                Text(gunluk.isEmpty ? "Henüz not yok. Asistan önemli gelişmeleri buraya yazar." : gunluk).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Çalışma alanı")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { kaydet() }.disabled(!kirli) }
            if cikisKilitli {
                ToolbarItem(placement: .cancellationAction) { Button("Geri") { atmaSor = true }.accessibilityIdentifier("calisma-geri") }
            }
        }
        // Sınır aşılmışsa çıkışta otomatik kayıt yapılamaz: geri oku (ve kenardan geri kaydırma) gizlenir,
        // sayfa aşağı kaydırılarak kapanmaz; "Geri" önce uyarır, düzenleme sessizce kaybolmaz.
        .navigationBarBackButtonHidden(cikisKilitli)
        .interactiveDismissDisabled(cikisKilitli)
        .confirmationDialog("Sınırı aşan metin kaydedilemez", isPresented: $atmaSor, titleVisibility: .visible) {
            Button("Değişiklikleri at ve çık", role: .destructive) { metinler = kayitli; kapat() }
            Button("Ekranda kal", role: .cancel) {}
        } message: {
            Text("\(Self.sinirAsan(metinler)?.rawValue ?? "Bir dosya").md \(CalismaAlani.enFazlaKarakter) karakteri aşıyor. Çıkarsan bu ekrandaki kaydedilmemiş bütün düzenlemeler kaybolur.")
        }
        .onChange(of: metinler) { _, _ in bilgi = nil }
        .onAppear {
            for d in CalismaAlani.Dosya.allCases { metinler[d] = CalismaAlani.oku(d) }
            kayitli = metinler
            gunluk = CalismaAlani.gunlukOku(gun: 3)
        }
        // Sınır içindeyken geri okuyla ya da Ayarlar sayfası kapatılarak çıkışta otomatik kaydeder;
        // sınır aşılmışsa geri oku gizlidir, "Geri" onay ister.
        .onDisappear { if kirli { kaydet() } }
    }

    private func kaydet() {
        if let d = Self.sinirAsan(metinler) {
            hata = "\(d.rawValue).md \(CalismaAlani.enFazlaKarakter) karakteri aşıyor; hiçbir dosya kaydedilmedi. Kısaltıp yeniden dene."
            return
        }
        do {
            for d in Self.degisenler(metinler, kayitli: kayitli) {
                try CalismaAlani.yaz(d, metinler[d] ?? "")
                kayitli[d] = CalismaAlani.oku(d)
            }
            hata = nil
            bilgi = "Kaydedildi."
        } catch { hata = error.localizedDescription }
    }
}

/// OpenClaw "heartbeat": aralıkla kontrol listesine bakar; yalnız dikkat gerektiren bir şey varsa bildirim gönderir.
struct NabizEkrani: View {
    @Environment(Ayarlar.self) private var ayarlar
    @State private var liste = ""
    /// Diskteki HEARTBEAT.md; kaydedilmemiş değişiklik bununla karşılaştırılır.
    @State private var kayitliListe = ""
    @State private var bilgi: String?
    @State private var calisiyor = false
    @State private var sonuc = NabizMotoru.sonSonuc()
    @State private var hata: String?

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section {
                Text("Asistan seçtiğin aralıkta kontrol listesine, takvimine ve hatırlatıcılarına bakar; dikkat gerektiren bir şey yoksa sessiz kalır. iOS arka plan çalışma zamanını kendisi belirler: aralık bir en erken süredir, kesin saat garantisi yoktur.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Aralık") {
                Picker("Nabız", selection: $a.nabizDakika) {
                    Text("Kapalı").tag(0); Text("30 dakika").tag(30); Text("1 saat").tag(60); Text("3 saat").tag(180)
                }
                .onChange(of: ayarlar.nabizDakika) { _, yeni in
                    NabizMotoru.planla(dakika: yeni)
                    if yeni > 0 { Task { if !(await NabizMotoru.bildirimIzni()) { hata = "Bildirim izni verilmedi; uyarılar gösterilemez (Ayarlar > Asistan > Bildirimler)." } } }
                }
            }
            Section("HEARTBEAT.md — kontrol listesi") {
                TextEditor(text: $liste).frame(minHeight: 120).font(.callout).accessibilityIdentifier("nabiz-liste")
                if liste.isEmpty { Text(CalismaAlani.Dosya.heartbeat.ipucu).font(.caption).foregroundStyle(.secondary) }
                let n = liste.trimmingCharacters(in: .whitespacesAndNewlines).count
                if n > CalismaAlani.enFazlaKarakter { Text("\(n)/\(CalismaAlani.enFazlaKarakter) karakter: kısaltmadan kaydedilemez.").font(.caption).foregroundStyle(.orange) }
                Button("Listeyi kaydet") { if listeyiKaydet() { bilgi = "Kaydedildi." } }
                if let bilgi { Text(bilgi).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Son kontrol") {
                if let s = sonuc {
                    Text(s.zaman.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(s.hata ?? s.uyari ?? "Her şey yolunda; dikkat gerektiren bir şey yok.").font(.callout)
                } else { Text("Henüz çalışmadı.").foregroundStyle(.secondary) }
                Button(calisiyor ? "Çalışıyor…" : "Şimdi çalıştır") {
                    calisiyor = true
                    // Kayıt başarısızsa motor diskteki eski listeyle çalışıp yanıltıcı sonuç vermesin; hata satırı nedenini gösterir.
                    Task { if kirli, !listeyiKaydet() { calisiyor = false; return }; sonuc = await NabizMotoru.calistir(); calisiyor = false }
                }.disabled(calisiyor)
            }
            if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle("Nabız")
        // Sınır aşılmışsa çıkışta otomatik kayıt yapılamaz: geri oku gizlenir, "Geri" önce uyarır.
        .toolbar {
            if cikisKilitli {
                ToolbarItem(placement: .cancellationAction) { Button("Geri") { atmaSor = true }.accessibilityIdentifier("nabiz-geri") }
            }
        }
        .navigationBarBackButtonHidden(cikisKilitli)
        .interactiveDismissDisabled(cikisKilitli)
        .confirmationDialog("Sınırı aşan liste kaydedilemez", isPresented: $atmaSor, titleVisibility: .visible) {
            Button("Değişiklikleri at ve çık", role: .destructive) { liste = kayitliListe; kapat() }
            Button("Ekranda kal", role: .cancel) {}
        } message: {
            Text("HEARTBEAT.md \(CalismaAlani.enFazlaKarakter) karakteri aşıyor. Çıkarsan kaydedilmemiş liste kaybolur.")
        }
        .onChange(of: liste) { _, _ in bilgi = nil }
        .onAppear { liste = CalismaAlani.oku(.heartbeat); kayitliListe = liste; sonuc = NabizMotoru.sonSonuc() }
        // Kaydet'e basmadan çıkılırsa liste kaybolmasın (sınır içindeyken otomatik kaydedilir).
        .onDisappear { if kirli { _ = listeyiKaydet() } }
    }

    @Environment(\.dismiss) private var kapat
    @State private var atmaSor = false

    private var kirli: Bool { liste.trimmingCharacters(in: .whitespacesAndNewlines) != kayitliListe.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cikisKilitli: Bool { Self.cikisKilitliMi(liste, kayitli: kayitliListe) }

    /// Kaydedilmemiş liste sınırı aşıyorsa çıkışta otomatik kayıt başarısız olur; geri oku kilitlenir.
    nonisolated static func cikisKilitliMi(_ liste: String, kayitli: String) -> Bool {
        let t = liste.trimmingCharacters(in: .whitespacesAndNewlines)
        return t != kayitli.trimmingCharacters(in: .whitespacesAndNewlines) && t.count > CalismaAlani.enFazlaKarakter
    }

    /// HEARTBEAT.md'yi yazar; başarıda diskteki hâli günceller.
    private func listeyiKaydet() -> Bool {
        do {
            try CalismaAlani.yaz(.heartbeat, liste)
            kayitliListe = CalismaAlani.oku(.heartbeat); hata = nil
            return true
        } catch { hata = error.localizedDescription; return false }
    }
}

/// "Asistan seni böyle tanıyor": olgular, kullanıcı profili, günlük notlar ve çalışma alanı tek yerde; düzenle/sil/dışa aktar.
struct HafizaEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(Ayarlar.self) private var ayarlar
    @State private var olgular: [Olgu] = []
    @State private var gunluk: [(gun: String, metin: String)] = []
    @State private var arama = ""
    @State private var duzenlenen: Olgu?
    @State private var duzenMetni = ""
    @State private var yeniMetin = ""
    @State private var temizlemeOnayi = false
    @State private var hata: String?
    @State private var kategoriSuzgeci: OlguKategorisi?
    @State private var gecmisSonuclari: [HafizaIndeksi.Sonuc] = []
    @State private var birlesen: Int?
    @State private var bilgi: String?
    @FocusState private var yeniOdak: Bool

    private var gorunenOlgular: [Olgu] {
        let arananlar = arama.isEmpty ? olgular : olgular.filter { $0.metin.localizedStandardContains(arama) || HafizaIndeksi.normalize($0.metin).contains(HafizaIndeksi.normalize(arama)) }
        let k = kategoriSuzgeci.map { f in arananlar.filter { $0.kategori == f.rawValue } } ?? arananlar
        // Sabitlenenler ve önemliler üstte (arama yoksa).
        return arama.isEmpty ? k.sorted { ($0.sabit == true ? 10 : 0) + ($0.onem ?? 3) > ($1.sabit == true ? 10 : 0) + ($1.onem ?? 3) } : k
    }
    private var disaAktarim: String {
        var s = "Asistan — hafıza dışa aktarımı\n\nOLGULAR\n" + olgular.map { "- \($0.metin)" }.joined(separator: "\n")
        let u = CalismaAlani.oku(.user).trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { s += "\n\nUSER.md\n\(u)" }
        if !gunluk.isEmpty { s += "\n\nGÜNLÜK\n" + gunluk.map { "[\($0.gun)]\n\($0.metin)" }.joined(separator: "\n") }
        return s
    }

    var body: some View {
        @Bindable var a = ayarlar
        List {
            Section {
                Text("Asistanın seni tanımak için sakladığı her şey burada. Yanlış ya da gereksiz olanı düzeltebilir veya silebilirsin; silinen bilgi bir daha kullanılmaz.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Konuşmalardan otomatik olgu çıkar", isOn: $a.otomatikHafiza)
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        kategoriCipi(nil, "Tümü", "tray.full")
                        ForEach(OlguKategorisi.allCases, id: \.self) { k in
                            let n = olgular.filter { $0.kategori == k.rawValue }.count
                            if n > 0 { kategoriCipi(k, "\(k.ad) \(n)", k.simge) }
                        }
                    }
                }
                HStack(spacing: 14) {
                    Label("\(HafizaIndeksi.ortak.say(tur: .mesaj)) mesaj aranabilir", systemImage: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                    Label("\(olgular.filter { $0.sabit == true }.count) sabit", systemImage: "pin").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Yinelenenleri birleştir") { birlesen = beyin.depo.yinelenenleriBirlestir(); yenile() }.font(.caption).accessibilityIdentifier("hafiza-birlestir")
                }
                if let birlesen { Text(birlesen == 0 ? "Birleştirilecek yinelenen olgu yok." : "\(birlesen) yinelenen olgu birleştirildi.").font(.caption).foregroundStyle(.secondary) }
            }
            // Onay bekleyenler (P3.8): çıkarımla gelen hassas olgular ve çelişen yeni değerler; boşsa bölüm hiç görünmez.
            let bekleyenler = olgular.filter { $0.durum == OlguDurumu.bekliyor || $0.durum == OlguDurumu.celiski }
            if !bekleyenler.isEmpty {
                Section("Onay bekleyenler") {
                    ForEach(bekleyenler, id: \.kimlik) { o in
                        let celiski = o.durum == OlguDurumu.celiski
                        let eski = celiski ? beyin.depo.celiskiAdayi(o) : nil
                        VStack(alignment: .leading, spacing: 6) {
                            Text(OlguOnayCipi.metin(o, eski: eski)).font(.callout)
                            HStack {
                                Button(celiski ? "Yenisi doğru" : "Onayla") {
                                    if celiski { beyin.depo.celiskiCoz(yeni: o.kimlik, eski: eski?.kimlik, yeniDogru: true) } else { beyin.depo.olguOnayla(o.kimlik) }
                                    yenile()
                                }.buttonStyle(.borderedProminent).controlSize(.small)
                                Button(celiski ? "Eskisi doğru" : "Reddet", role: celiski ? nil : .destructive) {
                                    if celiski { beyin.depo.celiskiCoz(yeni: o.kimlik, eski: eski?.kimlik, yeniDogru: false) } else { beyin.depo.olguReddet(o.kimlik) }
                                    yenile()
                                }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .accessibilityIdentifier("olgu-bekleyen-satiri")
                    }
                }
            }
            Section("Olgular (\(gorunenOlgular.count)/\(olgular.count))") {
                HStack {
                    TextField("Yeni olgu ekle…", text: $yeniMetin).submitLabel(.done).onSubmit(ekle).focused($yeniOdak)
                    Button("Ekle", action: ekle).disabled(yeniMetin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let bilgi { Text(bilgi).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("olgu-bilgi") }
                if gorunenOlgular.isEmpty { Text(arama.isEmpty ? "Henüz olgu yok." : "Eşleşen olgu yok.").foregroundStyle(.secondary) }
                ForEach(gorunenOlgular, id: \.kimlik) { o in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: (o.kategori.flatMap(OlguKategorisi.init(rawValue:)) ?? .diger).simge).foregroundStyle(.secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.metin).font(.callout)
                            Text("\(o.kaynak == "asistan" ? "asistan öğrendi" : o.kaynak == "kullanici" ? "sen ekledin" : o.kaynak) · \(o.olusturma.formatted(date: .abbreviated, time: .omitted))"
                                 + ((o.kullanimSayisi ?? 0) > 0 ? " · \(o.kullanimSayisi ?? 0) kez kullanıldı" : ""))
                                .font(.caption2).foregroundStyle(.secondary)
                            // Durum ve geçerlilik rozeti (onay bekliyor / çelişiyor / bitiş günü).
                            if o.durum == OlguDurumu.bekliyor || o.durum == OlguDurumu.celiski || o.gecerlilikSonu != nil {
                                HStack(spacing: 6) {
                                    if o.durum == OlguDurumu.bekliyor { Label("onay bekliyor", systemImage: "hourglass") }
                                    if o.durum == OlguDurumu.celiski { Label("çelişiyor", systemImage: "exclamationmark.triangle") }
                                    if let son = o.gecerlilikSonu {
                                        Label((son <= .now ? "süresi doldu " : "bitiş ") + son.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted), systemImage: "calendar.badge.clock")
                                    }
                                }
                                .font(.caption2).foregroundStyle(.orange)
                                .accessibilityIdentifier("olgu-durum-rozeti")
                            }
                        }
                        Spacer(minLength: 4)
                        if o.sabit == true { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                        else if (o.onem ?? 3) >= 4 { Text(String(repeating: "★", count: o.onem ?? 3)).font(.caption2).foregroundStyle(.orange) }
                    }
                    .contextMenu {
                        Button(o.sabit == true ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: o.sabit == true ? "pin.slash" : "pin") { beyin.depo.olguAyarla(o.kimlik, sabit: !(o.sabit == true)); yenile() }
                        Menu("Önem", systemImage: "star") { ForEach(1...5, id: \.self) { n in Button(String(repeating: "★", count: n)) { beyin.depo.olguAyarla(o.kimlik, onem: n); yenile() } } }
                        Menu("Kategori", systemImage: "tag") { ForEach(OlguKategorisi.allCases, id: \.self) { k in Button(k.ad, systemImage: k.simge) { beyin.depo.olguAyarla(o.kimlik, kategori: k); yenile() } } }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { duzenlenen = o; duzenMetni = o.metin }
                    .accessibilityIdentifier("olgu-satiri")
                }
                .onDelete { idx in
                    let hedef = idx.map { gorunenOlgular[$0].kimlik }
                    hedef.forEach { beyin.depo.olguSil($0) }; yenile()
                }
            }
            if !gecmisSonuclari.isEmpty {
                Section("Geçmiş sohbetlerde (\(gecmisSonuclari.count))") {
                    ForEach(gecmisSonuclari, id: \.kimlik) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(r.metin.prefix(200))).font(.callout).lineLimit(3)
                            Text(r.zaman.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.accessibilityIdentifier("gecmis-sonuclari")
            }
            Section("Profil ve kurallar") {
                NavigationLink { CalismaAlaniEkrani() } label: { Label("SOUL · USER · AGENTS dosyaları", systemImage: "doc.text") }
                NavigationLink { BecerilerEkrani() } label: { Label("Beceriler (\(BeceriDeposu.listele().count))", systemImage: "sparkles") }
                NavigationLink { HafizaYedekleriEkrani() } label: { Label("Yedekler ve kurtarma", systemImage: "clock.arrow.circlepath") }
            }
            Section("Günlük notlar (\(gunluk.count) gün)") {
                if gunluk.isEmpty { Text("Henüz not yok. Asistan önemli gelişmeleri buraya yazar.").foregroundStyle(.secondary) }
                ForEach(gunluk, id: \.gun) { g in
                    DisclosureGroup(g.gun) { Text(g.metin).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                .onDelete { idx in idx.map { gunluk[$0].gun }.forEach { CalismaAlani.gunlukSil($0) }; yenile() }
            }
            Section {
                ShareLink(item: disaAktarim) { Label("Hafızayı dışa aktar (metin)", systemImage: "square.and.arrow.up") }
                Button("Tüm olguları sil", role: .destructive) { temizlemeOnayi = true }.disabled(olgular.isEmpty)
            }
            if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle("Hafıza")
        .searchable(text: $arama, prompt: "Olgularda ve geçmiş sohbetlerde ara")
        .onChange(of: arama) { _, y in
            gecmisSonuclari = y.trimmingCharacters(in: .whitespaces).count >= 3 ? HafizaIndeksi.ortak.ara(y, tur: .mesaj, adet: 12) : []
        }
        .onAppear(perform: yenile)
        .onChange(of: OlguOnayIzleyici.ortak.surum) { _, _ in yenile() }   // çıkarıcı/onay çipi olgu durumunu değiştirdi
        .confirmationDialog("Tüm olgular silinsin mi?", isPresented: $temizlemeOnayi, titleVisibility: .visible) {
            Button("\(olgular.count) olguyu sil", role: .destructive) { beyin.depo.olgulariTemizle(); yenile() }
        } message: { Text("Bu işlem geri alınamaz. Günlük notlar ve çalışma alanı dosyaları silinmez.") }
        .alert("Olguyu düzenle", isPresented: Binding(get: { duzenlenen != nil }, set: { if !$0 { duzenlenen = nil } })) {
            TextField("Olgu", text: $duzenMetni)
            Button("Kaydet") {
                if let o = duzenlenen, !beyin.depo.olguDuzenle(o.kimlik, metin: duzenMetni) { hata = "Olgu boş olamaz ve en çok 300 karakter olabilir." } else { hata = nil }
                duzenlenen = nil; yenile()
            }
            Button("Vazgeç", role: .cancel) { duzenlenen = nil }
        }
    }

    private func kategoriCipi(_ k: OlguKategorisi?, _ ad: String, _ simge: String) -> some View {
        let secili = kategoriSuzgeci == k
        return Button { kategoriSuzgeci = k } label: {
            Label(ad, systemImage: simge).font(.caption.weight(.medium)).padding(.horizontal, 10).frame(minHeight: 32)
                .background(secili ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier("kategori-cipi").accessibilityAddTraits(secili ? .isSelected : [])
    }
    private func ekle() {
        let temiz = yeniMetin.trimmingCharacters(in: .whitespacesAndNewlines)
        let onceki = Dictionary(olgular.map { ($0.kimlik, $0.metin) }, uniquingKeysWith: { a, _ in a })
        if let o = beyin.depo.hatirlaZengin(yeniMetin, kaynak: "kullanici") {
            // Depo aynı olguyu döndürür ya da benzerini günceller: kullanıcı sessizce "yeni eklendi" sanmasın.
            if let eski = onceki[o.kimlik] { bilgi = eski == o.metin ? "Bu bilgi zaten kayıtlı." : "Benzer olgu güncellendi (eskisi: “\(eski)”)." } else { bilgi = nil }
            yeniMetin = ""; hata = nil
            yeniOdak = false   // klavye listeyi örtmesin; yeni satır görünür ve kaydırılarak silinebilir
        } else if temiz.isEmpty || temiz.count > 300 {
            hata = "Olgu boş olamaz ve en çok 300 karakter olabilir."
        } else {
            hata = "Olgu kaydedilemedi; yeniden dene."
        }
        yenile()
    }
    private func yenile() {
        olgular = beyin.depo.olgular().sorted { $0.olusturma > $1.olusturma }
        gunluk = CalismaAlani.gunlukGunleri()
    }
}

/// Kullanım ve kota: bugünkü istekler, paralel yarış maliyeti, kota beklemeleri, son 7 gün.
struct KullanimEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(Ayarlar.self) private var ayarlar
    @State private var bugun = KullanimDefteri.ortak.kayit()
    @State private var gunler = KullanimDefteri.ortak.sonGunler()
    @State private var proxyBeklemeleri: [String: TimeInterval] = [:]
    @State private var silmeOnayi = false

    private var beklemeler: [KotaOzeti.Bekleme] {
        // Yalnız model geneli askılar; yol askıları Sağlık → 'Askıdaki rotalar ve modeller'de (P3.7).
        KotaOzeti.beklemeler(askilar: beyin.modelVitesi.modelGeneliAskilar)
    }

    var body: some View {
        @Bindable var ay = ayarlar
        Form {
            Section("Bugün") {
                let toplam = bugun.aileler.values.reduce(0) { $0 + $1.istek }
                if toplam == 0 { Text("Bugün henüz model isteği yok.").foregroundStyle(.secondary) }
                ForEach(SaglayiciAilesi.allCases, id: \.self) { a in
                    if let s = bugun.aileler[a.rawValue], s.istek > 0 {
                        LabeledContent(a.ad) { Text("\(s.istek) istek · \(s.basari) başarılı\(s.hata > 0 ? " · \(s.hata) hata" : "")").font(.callout) }
                    }
                }
                LabeledContent("Toplam", value: "\(toplam) istek")
            }
            Section {
                Picker("Yarışan sağlayıcı", selection: $ay.yarisSaglayici) {
                    Text("1 (en az kota)").tag(1); Text("2").tag(2); Text("3 (en hızlı)").tag(3)
                }
                if bugun.yarisSohbet > 0 {
                    LabeledContent("Bugün yarışan sohbet", value: "\(bugun.yarisSohbet)")
                    LabeledContent("Bunlar için model çağrısı", value: "\(bugun.yarisCagri) (≈ ×\(String(format: "%.1f", Double(bugun.yarisCagri) / Double(bugun.yarisSohbet))))")
                }
            } header: { Text("Paralel yarış") } footer: {
                Text("Düz sohbet birkaç sağlayıcıya aynı anda gider, ilk yanıt kazanır; kaybedenler iptal edilir ama istek sayılır. Kotanı korumak için sayıyı düşürebilirsin.")
            }
            Section("Kota beklemeleri") {
                if beklemeler.isEmpty && proxyBeklemeleri.isEmpty { Label("Şu an bekleyen kota yok", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                ForEach(beklemeler, id: \.model) { b in
                    LabeledContent(Beyin.modelEtiketi(b.model), value: "\(KotaOzeti.sureMetni(b.kalanSn)) bekleme")
                }
                ForEach(proxyBeklemeleri.sorted { $0.key < $1.key }, id: \.key) { k, sn in
                    LabeledContent("Hesap: \(k)", value: KotaOzeti.sureMetni(Int(sn)))
                }
                Text("Bir hesabın gerçek kalan kullanım yüzdesi uygulama içinde bilinmez; yalnızca sağlayıcının bildirdiği bekleme süreleri gösterilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Son 7 gün (istek)") {
                Chart(gunler, id: \.gun) { g in
                    BarMark(x: .value("Gün", String(g.gun.suffix(5))), y: .value("İstek", g.istek))
                }.frame(height: 120)
                LabeledContent("Toplam hata", value: "\(gunler.reduce(0) { $0 + $1.hata })")
            }
            Section("Hesaplar") {
                LabeledContent("Bağlı hesap", value: "\(TelefonProxy.ortak.hesapSayisi)")
                Text(TelefonProxy.ortak.durum).font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Kullanım kayıtlarını sıfırla", role: .destructive) { silmeOnayi = true } }
        }
        .navigationTitle("Kullanım ve kota")
        .task { await yenile() }
        .refreshable { await yenile() }
        .confirmationDialog("Kullanım sayaçları silinsin mi?", isPresented: $silmeOnayi, titleVisibility: .visible) {
            Button("Sıfırla", role: .destructive) { KullanimDefteri.ortak.temizle(); Task { await yenile() } }
        }
    }

    private func yenile() async {
        bugun = KullanimDefteri.ortak.kayit()
        gunler = KullanimDefteri.ortak.sonGunler()
        proxyBeklemeleri = await TelefonProxy.ortak.kotaBeklemeleri()
    }
}

/// Çökme, takılma ve performans kayıtları (MetricKit) ile arka plan nabız tetiklenmeleri.
struct IzlemeEkrani: View {
    @State private var kayitlar = IzlemeDefteri.ortak.hepsi()
    @State private var silmeOnayi = false

    private func simge(_ t: IzlemeKaydi.Tur) -> String {
        switch t { case .cokme: "exclamationmark.octagon.fill"; case .takilma: "hourglass"; case .cpu: "cpu"; case .disk: "externaldrive"
                   case .metrik: "chart.xyaxis.line"; case .nabiz: "waveform.path.ecg"; case .uyari: "exclamationmark.triangle" }
    }
    private func renk(_ t: IzlemeKaydi.Tur) -> Color { t == .cokme ? .red : (t == .takilma || t == .cpu || t == .disk || t == .uyari) ? .orange : .secondary }

    var body: some View {
        List {
            Section {
                Text("iOS çökme, takılma ve günlük performans bilgisini uygulamaya kendiliğinden teslim eder (genelde ertesi gün). Veriler yalnız bu telefonda tutulur.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Son 30 gün") {
                LabeledContent("Çökme", value: "\(IzlemeDefteri.ortak.sayi(.cokme))")
                LabeledContent("Takılma", value: "\(IzlemeDefteri.ortak.sayi(.takilma))")
                LabeledContent("Arka plan nabız çalışması", value: "\(IzlemeDefteri.ortak.sayi(.nabiz))")
            }
            Section("Kayıtlar") {
                if kayitlar.isEmpty { Text("Henüz kayıt yok. iOS ilk raporu genellikle 24 saat içinde verir.").foregroundStyle(.secondary) }
                ForEach(kayitlar) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(k.ozet, systemImage: simge(k.tur)).font(.callout).foregroundStyle(renk(k.tur))
                        Text(k.zaman.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                // P2.4: Sağlık ve hız merkezi yalnız Ayarlar → Gelişmiş'ten açılır (çift giriş kaldırıldı).
                Button("Kayıtları sil", role: .destructive) { silmeOnayi = true }.disabled(kayitlar.isEmpty)
            }
        }
        .navigationTitle("Çökme ve performans")
        .onAppear { kayitlar = IzlemeDefteri.ortak.hepsi() }
        .confirmationDialog("İzleme kayıtları silinsin mi?", isPresented: $silmeOnayi, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { IzlemeDefteri.ortak.temizle(); TaniGunlugu.sil(); kayitlar = [] }
        } message: {
            Text(Self.silmeAciklamasi)
        }
    }

    /// Silme kapsamı: izleme kayıtlarıyla birlikte tanı günlüğü de gider (kullanıcı habersiz kalmasın).
    nonisolated static let silmeAciklamasi = "Çökme ve performans kayıtlarıyla birlikte tanı günlüğü (tani.log ve tani.1.log) da silinir. Geri alınamaz."
}


/// OpenAI API anahtarı: iPhone'daki CLIProxy kasasında varsa otomatik kullanılır; istersen elle girilir (Keychain, öncelikli).
struct OpenAIAnahtarSatiri: View {
    @State private var girdi = ""
    @State private var kaynak = OpenAIAnahtari.kaynak
    @State private var kasadaki = OpenAIAnahtari.kasaAnahtari
    @State private var mesaj: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch kaynak {
            case "kasa": Label("iPhone'daki CLIProxy kasasında OpenAI anahtarı bulundu; otomatik kullanılır.", systemImage: "checkmark.seal")
                    .font(.footnote).foregroundStyle(.green)
            case "elle": LabeledContent("OpenAI anahtarı (elle)", value: OpenAIAnahtari.maske(OpenAIAnahtari.elleGirilen ?? ""))
                Button("Elle girilen anahtarı sil", role: .destructive) { OpenAIAnahtari.sil(); yenile(); mesaj = "Silindi." }
            default: Label("Anahtar bulunamadı: aşağıya gir ya da CLIProxy'ye OpenAI API anahtarı ekle.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if kaynak != "elle" {
                SecureField("Elle OpenAI API anahtarı (sk-…) — isteğe bağlı", text: $girdi).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("openai-anahtar-alani")
                Button("Kaydet") {
                    if OpenAIAnahtari.kaydet(girdi) { girdi = ""; yenile(); mesaj = "Kaydedildi (yalnız bu telefonda)." } else { mesaj = "Geçersiz anahtar: 'sk-' ile başlamalı." }
                }.disabled(girdi.isEmpty)
            }
            Text("Anahtar sunucuya gönderilmez, günlüğe yazılmaz. Gerçek zamanlı ses OpenAI hesabından ücretlendirilir. Bağlanamazsa Live Claude ile sürer.")
                .font(.caption).foregroundStyle(.secondary)
            if let mesaj { Text(mesaj).font(.caption).foregroundStyle(.orange) }
        }
        .task { await TelefonProxy.ortak.hazirla(); yenile() }
    }
    private func yenile() { kaynak = OpenAIAnahtari.kaynak; kasadaki = OpenAIAnahtari.kasaAnahtari }
}
