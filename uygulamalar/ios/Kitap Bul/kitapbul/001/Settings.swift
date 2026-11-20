import SwiftUI

/// Uygulama ayarları. Ana sayfa: sık kullanılanlar ve görev odaklı altı bölüm kartı; her bölüm
/// kendi sayfasında açılır. `AyarBolumu` ham değerleri UI testlerinin sözleşmesidir; bölüm sayfaları
/// eski kategorileri birleştirir (Tarama + OCR belleği, Ödünç + Kademe kuralları, Veri + Yardım).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.ayarlariKapat) private var ayarlariKapat

    /// nil: kategori kartları (ana sayfa); değer: yalnız o bölümün formu
    var bolum: AyarBolumu? = nil

    var body: some View {
        if let bolum {
            AyarBolumSayfasi(bolum: bolum)
        } else {
            NavigationStack {
                AyarKartlari()
                    .navigationTitle("Ayarlar")
                    .toolbar {
                        if isPresented {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Kapat") { dismiss() }
                            }
                        }
                    }
            }
            // Alt sayfalar (ör. Yardım) sayfa olarak açılan Ayarlar'ı kapatabilsin; iPad sekmesinde gerekmez.
            // Ayarlar'ı başka bir sayfanın içinden açan ekran (Katalog Yönetimi) kendi kapatıcısını verirse
            // o kullanılır: Ayarlar onunla birlikte kapanır.
            .environment(\.ayarlariKapat, isPresented ? (ayarlariKapat ?? { dismiss() }) : nil)
        }
    }
}

extension EnvironmentValues {
    /// Sayfa olarak açılan Ayarlar'ı (onu bir sayfanın içinden açan ekran verdiyse o sayfayla birlikte)
    /// alt sayfadan kapatır; iPad'deki Ayarlar sekmesinde `nil`.
    @Entry var ayarlariKapat: (() -> Void)? = nil
}

/// Ayar kategorileri (her biri ayrı sayfa).
enum AyarBolumu: String, CaseIterable, Identifiable {
    case gorunum, yapayZeka, tarama, odunc, kurallar, roller, veri, ocr, yardim
    var id: String { rawValue }

    /// Ayarlar ana sayfasındaki kartlar. Kalan kategoriler bu sayfaların içine katıldı.
    static let kartlar: [AyarBolumu] = [.gorunum, .tarama, .odunc, .roller, .yapayZeka, .veri]

    var baslik: String {
        switch self {
        case .gorunum: "Görünüm"
        case .yapayZeka: "Yapay Zekâ"
        case .tarama: "Tarama"
        case .odunc: "Ödünç"
        case .kurallar: "Kademe Kuralları"
        case .roller: "Güvenlik"
        case .veri: "Veri ve Yardım"
        case .ocr: "OCR Belleği"
        case .yardim: "Yardım"
        }
    }

    var aciklama: String {
        switch self {
        case .gorunum: "Tema, ana renk, sade mod"
        case .yapayZeka: "Bağlantı, veri paylaşımı, sınır"
        case .tarama: "Ses, titreşim, OCR belleği"
        case .odunc: "Süre, kota, kademe kuralları"
        case .kurallar: "Sınıfa göre süre ve sınır"
        case .roller: "Roller, Face ID, kiosk PIN"
        case .veri: "Arşiv, çöp kutusu, tanıtım"
        case .ocr: "Öğrenilen düzeltmeler"
        case .yardim: "Tanıtım, yenilikler"
        }
    }

    var ikon: String {
        switch self {
        case .gorunum: "paintpalette.fill"
        case .yapayZeka: "sparkles"
        case .tarama: "barcode.viewfinder"
        case .odunc: "person.badge.clock.fill"
        case .kurallar: "person.3.sequence.fill"
        case .roller: "lock.shield.fill"
        case .veri: "externaldrive.fill.badge.checkmark"
        case .ocr: "brain.head.profile"
        case .yardim: "lifepreserver.fill"
        }
    }

    var renk: Color {
        switch self {
        case .gorunum: KitapTema.foto
        case .yapayZeka: KitapTema.ana
        case .tarama: KitapTema.dosya
        case .odunc: KitapTema.amazon
        case .kurallar: KitapTema.toplu
        case .roller: KitapTema.vurgu
        case .veri: KitapTema.basari
        case .ocr: .indigo
        case .yardim: .gray
        }
    }
}

// MARK: - Ana sayfa

/// Ayarlar ana sayfası: sık kullanılan düz satırlar ve renkli kategori kartları.
private struct AyarKartlari: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var gemini = GeminiDurumu.shared
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false
    @AppStorage("scanSoundEnabled") private var scanSoundEnabled = true
    @AppStorage("loanDurationDays") private var loanDurationDays = 15

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sikKullanilanlar
                EsitSutunIzgara(sutun: typeSize.isAccessibilitySize ? 1 : nil, enKucukGenislik: 160,
                                yatayAralik: 14, dikeyAralik: 14) {
                    ForEach(AyarBolumu.kartlar) { bolum in
                        NavigationLink {
                            SettingsView(bolum: bolum)
                        } label: {
                            RenkliKart(baslik: bolum.baslik, altBaslik: bolum.aciklama, ikon: bolum.ikon, renk: bolum.renk,
                                       rozet: bolum == .yapayZeka && gemini.isActive ? "Açık" : nil)
                        }
                        .buttonStyle(.kitapSade)
                        .accessibilityHint(bolum.aciklama)
                        .accessibilityIdentifier("settings.card.\(bolum.rawValue)")
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var sikKullanilanlar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sık kullanılanlar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Stepper("Ödünç süresi: \(loanDurationDays) gün", value: $loanDurationDays, in: 1...180)
                    .frame(minHeight: 44).padding(.horizontal, 16)
                Divider().padding(.leading, 16)
                Toggle("Sade mod", isOn: $sadeMod)
                    .frame(minHeight: 44).padding(.horizontal, 16)
                    .accessibilityIdentifier("settings.simpleMode")
                Divider().padding(.leading, 16)
                Toggle("Tarama sesi", isOn: $scanSoundEnabled)
                    .frame(minHeight: 44).padding(.horizontal, 16)
                Divider().padding(.leading, 16)
                KioskPINSatiri().padding(.horizontal, 16)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Bölüm sayfası

/// Tek bölümün (ya da birleşik bölümlerin) formu. Kademe kuralları yalnız ilgili sayfada yüklenir.
private struct AyarBolumSayfasi: View {
    let bolum: AyarBolumu
    @Environment(\.dismiss) private var dismiss
    @State private var kurallar = KademeKurallariDurumu()
    @State private var kuralAtilsinMi = false

    private var kuralSayfasi: Bool { bolum == .odunc || bolum == .kurallar }
    private var kirli: Bool { kuralSayfasi && kurallar.kirli }

    var body: some View {
        Form {
            switch bolum {
            case .gorunum: GorunumAyarlari()
            case .yapayZeka: YapayZekaAyarlariBolumu()
            case .tarama: TaramaAyarlari(); OCRBellegiAyarlari()
            case .ocr: OCRBellegiAyarlari()
            case .odunc: OduncAyarlari(); OduncAyarlariBolumu(); KademeKurallariBolumu(durum: kurallar)
            case .kurallar: KademeKurallariBolumu(durum: kurallar)
            case .roller: RolAyarlariBolumu(); KioskAyarlari()
            case .veri: VeriAyarlari(); YardimAyarlari()
            case .yardim: YardimAyarlari()
            }
        }
        .navigationTitle(bolum.baslik)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(kirli)
        .toolbar {
            if kirli { ToolbarItem(placement: .topBarLeading) { Button("Geri") { kuralAtilsinMi = true } } }
        }
        .interactiveDismissDisabled(kirli)
        .confirmationDialog("Kural değişiklikleri kaydedilmeden kapatılsın mı?", isPresented: $kuralAtilsinMi, titleVisibility: .visible) {
            Button("Kaydet ve çık") { Task { if await kurallar.kaydet() { dismiss() } } }
            Button("Kaydetmeden kapat", role: .destructive) { dismiss() }
            Button("Devam et", role: .cancel) { }
        }
        .alert("Kurallar kaydedilemedi", isPresented: Binding(get: { kurallar.hata != nil }, set: { if !$0 { kurallar.hata = nil } })) {
            Button("Tamam") { kurallar.hata = nil }
        } message: { Text(kurallar.hata ?? "") }
    }
}

// MARK: - Görünüm

private struct GorunumAyarlari: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(TemaRengi.anahtar) private var themeAccent = TemaRengi.indigo.rawValue
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false
    @AppStorage(Tasarim.kenarKaydirmaAnahtari) private var kenarKaydirma = false
    @AppStorage(Tasarim.efektAnahtari) private var efektler = true

    private var secilenRenk: Color { TemaRengi(rawValue: themeAccent)?.renk ?? TemaRengi.indigo.renk }

    var body: some View {
        Section {
            Picker("Tema", selection: $appearanceMode) {
                Text("Sistem").tag("system")
                Text("Açık").tag("light")
                Text("Koyu").tag("dark")
            }
            Picker("Ana renk", selection: $themeAccent) {
                ForEach(TemaRengi.allCases) { tema in
                    Label {
                        Text(tema.rawValue)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(tema.renk)
                    }
                    .tag(tema.rawValue)
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("settings.themeAccent")
            Toggle("Sade mod (büyük yazı, temel işlemler)", isOn: $sadeMod)
            Toggle("Kenardan kaydırarak sekme değiştir", isOn: $kenarKaydirma)
            Toggle("Hareketli efektler", isOn: $efektler)
        } header: {
            Label("Görünüm", systemImage: "paintpalette")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.foto))
        } footer: {
            Text("Sistem seçildiğinde cihazın görünümü kullanılır. Sade mod günlük işlemleri öne çıkarır; tüm araçlar Yönetim’den açılabilir.")
        }

        Section {
            TemaOnizleme(renk: secilenRenk)
        } header: {
            Text("Önizleme")
        } footer: {
            Text("Renk seçince uygulama anında değişir; bu sayfa açık kalır.")
        }
    }
}

/// Seçilen ana rengin düğme, çip ve sayı kartındaki görünümü.
private struct TemaOnizleme: View {
    let renk: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button("Dolu düğme") { }
                    .buttonStyle(.kitapDolu(renk))
                    .allowsHitTesting(false)
                Cip(ad: "Seçili çip", ikon: "checkmark", secili: true, renk: renk) { }
                    .allowsHitTesting(false)
            }
            IstatistikKarti(deger: 128, baslik: "Örnek kart", ikon: "books.vertical.fill", renk: renk)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seçilen ana renk önizlemesi")
        .accessibilityIdentifier("settings.themePreview")
    }
}

// MARK: - Tarama ve OCR

private struct TaramaAyarlari: View {
    @AppStorage("scanSoundEnabled") private var scanSoundEnabled = true
    @AppStorage("scanHapticsEnabled") private var scanHapticsEnabled = true
    @AppStorage("barcodePhotoCapture") private var barcodePhotoCapture = true
    @AppStorage(SeriTaramaSesi.ayarAnahtari) private var spokenCounter = true
    @AppStorage(GeminiFotoGruplayici.ayarAnahtari) private var aiPhotoGrouping = false
    @AppStorage("autoStraightenCover") private var autoStraighten = true

    var body: some View {
        Section {
            Toggle("Tarama sesi", isOn: $scanSoundEnabled)
            Toggle("Titreşimli geri bildirim", isOn: $scanHapticsEnabled)
            Toggle("Barkodla birlikte arka kapağı çek", isOn: $barcodePhotoCapture)
            Toggle("Seri taramada sesli sayaç (her 10 kitap)", isOn: $spokenCounter)
            Toggle("Eğik kapağı otomatik düzelt", isOn: $autoStraighten)
            Toggle("Karışık fotoğrafları Gemini gruplasın", isOn: $aiPhotoGrouping)
        } header: {
            Label("Tarama", systemImage: "barcode.viewfinder")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.ana))
        } footer: {
            Text("Seri ve depo taramasında her okumada onay verilir. Arka kapak fotoğrafından özet, etiket ve okuma düzeyi çıkarılır. Gruplama açıkken çoklu fotoğraf seçiminde soru sorulmaz.")
        }
    }
}

private struct OCRBellegiAyarlari: View {
    @State private var correctionCount = CorrectionMemory.count
    @State private var isShowingResetConfirm = false

    var body: some View {
        Section {
            LabeledContent("Öğrenilen düzeltme", value: "\(correctionCount)")
            Button(role: .destructive) {
                isShowingResetConfirm = true
            } label: {
                Label("Düzeltme Belleğini Temizle", systemImage: "trash")
            }
            .disabled(correctionCount == 0)
        } header: {
            Label("OCR Belleği", systemImage: "brain")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.vurgu))
        } footer: {
            Text("Elle yaptığınız düzeltmeler sonraki taramalarda otomatik uygulanır.")
        }
        .confirmationDialog("Öğrenilen tüm düzeltmeler silinsin mi?", isPresented: $isShowingResetConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                CorrectionMemory.reset()
                correctionCount = 0
            }
            Button("Vazgeç", role: .cancel) { }
        }
    }
}

// MARK: - Ödünç ve kademe kuralları

private struct OduncAyarlari: View {
    @AppStorage("loanDurationDays") private var loanDurationDays = 15
    @AppStorage(OduncKotasi.genelSinirAnahtari) private var maxLoansPerPerson = 0
    @AppStorage(OduncKotasi.gecikmeEngeliAnahtari) private var blockOverdue = false

    var body: some View {
        Section {
            Stepper("Ödünç süresi: \(loanDurationDays) gün", value: $loanDurationDays, in: 1...180)
            Stepper(maxLoansPerPerson == 0 ? "Kişi başı sınır: yok" : "Kişi başı en fazla \(maxLoansPerPerson) kitap",
                    value: $maxLoansPerPerson, in: 0...20)
            Toggle("Gecikmesi olana yeni kitap verme", isOn: $blockOverdue)
        } header: {
            Label("Ödünç", systemImage: "person.badge.clock")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.amazon))
        }
    }
}

/// Kademe kuralları düzenleme durumu. Dosya yalnız kural bölümü görününce, bir kez yüklenir.
@MainActor @Observable
final class KademeKurallariDurumu {
    var kurallar: [GradeLoanRule] = []
    private(set) var kayitliImza = ""
    private(set) var yuklendi = false
    var mesaj: String?
    var hata: String?

    var kirli: Bool { yuklendi && GradeLoanRule.imza(kurallar) != kayitliImza }

    func yukle() {
        guard !yuklendi else { return }
        kurallar = GradeLoanRuleStore.all()
        kayitliImza = GradeLoanRule.imza(kurallar)
        yuklendi = true
    }

    func kaydet() async -> Bool {
        guard await YetkiDurumu.shared.yoneticiOl() else {
            hata = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."
            return false
        }
        do {
            try GradeLoanRuleStore.saveVerified(kurallar)
            kayitliImza = GradeLoanRule.imza(kurallar)
            mesaj = "Kurallar kaydedildi."
            return true
        } catch {
            hata = error.localizedDescription
            return false
        }
    }
}

extension GradeLoanRule {
    /// Kural listesinin sıra duyarlı parmak izi: yalnız kullanıcıya görünen alanlar karşılaştırılır.
    static func imza(_ rules: [GradeLoanRule]) -> String {
        rules.map { "\($0.id.uuidString)|\($0.gradePrefix.utf8.count):\($0.gradePrefix)|\($0.loanDurationDays)|\($0.maxConcurrentLoans)" }
            .joined(separator: "\n")
    }
}

private struct KademeKurallariBolumu: View {
    let durum: KademeKurallariDurumu
    /// Kaydedilmemiş düzenleme, sayfa kapanıp açılsa da (sahne yaşadıkça) taslak olarak saklanır.
    @SceneStorage("gradeRulesDraft") private var taslakJSON = ""
    @State private var taslak: [GradeLoanRule]?

    var body: some View {
        @Bindable var durum = durum
        Section {
            if let taslak {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Kaydedilmemiş taslak var", systemImage: "doc.badge.clock").font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Devam") { durum.kurallar = taslak; self.taslak = nil }
                            .buttonStyle(.kitapTonlu())
                        Button("At", role: .destructive) { taslakJSON = ""; self.taslak = nil }
                            .buttonStyle(.kitapTonlu(.red))
                    }
                }
                .accessibilityIdentifier("settings.rulesDraft")
            }
            ForEach($durum.kurallar) { $rule in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Sınıf öneki (örn. 9)", text: $rule.gradePrefix)
                    Stepper("Süre: \(rule.loanDurationDays) gün", value: $rule.loanDurationDays, in: 1...180)
                    Stepper("En fazla \(rule.maxConcurrentLoans) kitap", value: $rule.maxConcurrentLoans, in: 1...20)
                }
            }
            .onDelete { offsets in
                durum.kurallar.remove(atOffsets: offsets)
                durum.mesaj = nil
            }

            Button {
                durum.kurallar.append(GradeLoanRule(gradePrefix: ""))
                durum.mesaj = nil
            } label: {
                Label("Kademe Kuralı Ekle", systemImage: "plus.circle")
            }

            Button {
                Task { if await durum.kaydet() { taslakJSON = "" } }
            } label: { Label("Kuralları Kaydet", systemImage: "checkmark.circle") }
                .disabled(!durum.kirli)
            if durum.kirli { Label("Kaydedilmemiş değişiklikler var", systemImage: "pencil.circle").font(.subheadline) }
            if let mesaj = durum.mesaj { Label(mesaj, systemImage: "checkmark.circle").font(.subheadline) }
        } header: {
            Label("Kademe Bazlı Ödünç Kuralları", systemImage: "person.3.sequence")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.toplu))
        } footer: {
            Text("Sınıf adı bu önekle başlayan öğrenciler için süre ve kitap sınırı uygulanır (örn. \"9\" → 9-A, 9-B). Eşleşme yoksa yukarıdaki genel süre kullanılır.")
        }
        .task {
            durum.yukle()
            guard let veri = taslakJSON.data(using: .utf8), !taslakJSON.isEmpty,
                  let cozulen = try? JSONDecoder().decode([GradeLoanRule].self, from: veri),
                  GradeLoanRule.imza(cozulen) != durum.kayitliImza else { return }
            taslak = cozulen
        }
        .onChange(of: GradeLoanRule.imza(durum.kurallar)) {
            guard durum.yuklendi else { return }
            if durum.kirli {
                taslakJSON = (try? JSONEncoder().encode(durum.kurallar)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            } else {
                taslakJSON = ""
            }
        }
    }
}

// MARK: - Güvenlik ve kiosk

private struct KioskAyarlari: View {
    var body: some View {
        Section {
            KioskPINSatiri()
        } header: {
            Label("Kiosk", systemImage: "rectangle.on.rectangle")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.amazon))
        } footer: {
            Text("Kiosk modundan çıkmak için bu PIN sorulur. PIN 4–8 rakamdır; 1234 ya da kısa bir PIN kabul edilmez. PIN cihazda anahtarlıkta korunur ve ekranda gösterilmez.")
        }
    }
}

/// "Kiosk PIN" satırı: değer asla gösterilmez; yalnız ayarlı olup olmadığı ('••••' / 'Ayarlanmadı').
private struct KioskPINSatiri: View {
    @State private var ayarli = KioskPIN.ayarli()
    @State private var sayfa = false

    var body: some View {
        Button { sayfa = true } label: {
            LabeledContent("Kiosk PIN") {
                Text(ayarli ? "••••" : "Ayarlanmadı").foregroundStyle(KitapTema.ikincilMetin)
            }
            .foregroundStyle(Color.primary)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(ayarli ? "Gizli" : "Ayarlanmadı")
        .accessibilityHint("Yeni kiosk PIN’i belirler")
        .accessibilityIdentifier("settings.kioskPIN")
        .sheet(isPresented: $sayfa, onDismiss: { ayarli = KioskPIN.ayarli() }) { KioskPINDegistirme() }
    }
}

/// PIN değiştirme: iki kez, gizli girişle. Kayıt yönetici kimliği ister.
private struct KioskPINDegistirme: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var tekrar = ""
    @State private var hata: String?
    @State private var kaydediliyor = false

    private var sorun: String? { KioskPIN.sorun(pin, tekrar: tekrar) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Yeni PIN (4–8 rakam)", text: $pin)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("kioskPIN.new")
                    SecureField("PIN’i tekrarla", text: $tekrar)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("kioskPIN.repeat")
                } footer: {
                    if let hata {
                        Text(hata).foregroundStyle(.red)
                    } else if !pin.isEmpty, let sorun {
                        Text(sorun)
                    }
                }
            }
#if os(iOS)
            .keyboardType(.numberPad)
#endif
            .navigationTitle("PIN değiştir")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pin) { _, yeni in
                let temiz = String(yeni.filter(\.isNumber).prefix(8))
                if temiz != yeni { pin = temiz }
                hata = nil
            }
            .onChange(of: tekrar) { _, yeni in
                let temiz = String(yeni.filter(\.isNumber).prefix(8))
                if temiz != yeni { tekrar = temiz }
                hata = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet() }
                        .disabled(sorun != nil || kaydediliyor)
                        .accessibilityIdentifier("kioskPIN.save")
                }
            }
        }
    }

    private func kaydet() {
        guard sorun == nil else { return }
        kaydediliyor = true
        Task {
            defer { kaydediliyor = false }
            guard await YetkiDurumu.shared.yoneticiOl(neden: "Kiosk PIN’ini değiştirmek için kimliğinizi doğrulayın") else {
                hata = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."
                return
            }
            do {
                try KioskPIN.kaydet(pin)
                dismiss()
            } catch {
                hata = error.localizedDescription
            }
        }
    }
}

// MARK: - Veri ve yardım

private struct VeriAyarlari: View {
    @Environment(\.ayarlariKapat) private var ayarlariKapat

    var body: some View {
        Section {
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("Veri Güvenliği ve Tanılama", systemImage: "externaldrive.badge.checkmark")
            }
            NavigationLink {
                TrashView()
            } label: {
                Label("Çöp Kutusu", systemImage: "trash")
            }
            // Arşiv dışa/içe aktarma ve geri yükleme Yönetim > Yedek ve aktarım'dadır.
            Button {
                DerinBaglanti.shared.hedefSekme = .yonetim
                ayarlariKapat?()
            } label: {
                Label("Arşivler ve Yedek (Yönetim)", systemImage: "archivebox")
                    .foregroundStyle(Color.primary)
            }
            .accessibilityHint("Yönetim sekmesini açar")
        } header: {
            Label("Veri", systemImage: "lock.shield")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.ana))
        } footer: {
            Text("Silinen kitaplar 30 gün çöp kutusunda kalır; her gün otomatik tam arşiv alınır.")
        }
    }
}

private struct YardimAyarlari: View {
    @Environment(\.ayarlariKapat) private var ayarlariKapat
    @State private var tanitimAcik = false
    /// Tanıtımın son düğmesiyle Ekle'ye geçildi: tanıtım kapanınca Ayarlar da kapanır
    @State private var tanitimdanEkleye = false
    @State private var yeniliklerAcik = false

    var body: some View {
        Section {
            // Tanıtım doğrudan burada açılır (Ayarlar kapanıp başka bir ekranı beklemez)
            Button {
                tanitimAcik = true
            } label: {
                Label("Tanıtımı Yeniden Göster", systemImage: "questionmark.circle")
            }
            // Güncellemeden sonra bir kez açılan liste sonradan da okunabilsin
            Button {
                yeniliklerAcik = true
            } label: {
                Label("Yenilikleri Göster", systemImage: "sparkles")
            }
            .accessibilityIdentifier("settings.whatsNew")
        } header: {
            Label("Yardım", systemImage: "lifepreserver")
                .labelStyle(RenkliIkonEtiketi(renk: KitapTema.dosya))
        } footer: {
            Text("Dört adımlı tanıtım bu sayfanın üstünde açılır; son adım okulunuzu tanıtır ve Ekle’ye ya da tablodan içe aktarmaya götürür. Kamera ve mikrofon izinleri ilgili işlemi başlatınca istenir.")
        }
        .sheet(isPresented: $tanitimAcik, onDismiss: {
            // Son düğmeyle Ekle'ye geçildiyse Ayarlar da kapanır; yoksa Ekle bu sayfanın arkasında kalırdı
            if tanitimdanEkleye { tanitimdanEkleye = false; ayarlariKapat?() }
        }) {
            OnboardingView { tanitimdanEkleye = true }
        }
        .sheet(isPresented: $yeniliklerAcik) {
            YeniliklerSayfasi()
        }
    }
}
