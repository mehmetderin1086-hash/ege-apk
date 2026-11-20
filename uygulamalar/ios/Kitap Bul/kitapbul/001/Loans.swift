import SwiftUI
import SwiftData

// MARK: - Kiosk modu (kendi kendine ödünç/iade)

/// Kiosk girişi: PIN değiştirilmemişse (1234), boşsa ya da geçersizse kiosk açılmadan önce yeni PIN
/// belirlenir. PIN kaydedilmeden kiosk açılmaz; Ayarlar ile aynı `kioskPIN` anahtarı kullanılır.
/// PIN bir ayardır: Ayarlar gibi yönetici kimliği ister (rol kilidi kapalıysa herkes yöneticidir).
struct KioskOturumu: View {
    @Environment(\.dismiss) private var dismiss
    @State private var yetki = YetkiDurumu.shared
    /// PIN özeti Keychain'de durur; eski düz metin değer ilk kontrolde özete taşınır.
    @State private var pinAyarli = KioskPIN.ayarli()
    @State private var kaydetHatasi: String?
    /// Kiosk açılırken yönetici oturumu yoksa PIN için açılan kilit, kiosk başlamadan kapatılır;
    /// öğrencilere bırakılan cihaz yönetici oturumuyla kalmasın.
    @State private var acilistaYonetici = YetkiDurumu.shared.oturumYonetici

    var body: some View {
        Group {
            if pinAyarli {
#if os(iOS)
                KioskView()
#else
                ContentUnavailableView("Kiosk bu cihazda kullanılamıyor", systemImage: "person.crop.rectangle")
#endif
            } else if yetki.yonetici {
                KioskPINBelirlemeSayfasi {
                    do {
                        try KioskPIN.kaydet($0)
                        pinAyarli = true
                        if !acilistaYonetici && yetki.oturumYonetici { yetki.gorevliyeGec() }
                    } catch { kaydetHatasi = error.localizedDescription }
                } onVazgec: { dismiss() }
            } else {
                // Görevli modunda PIN'i masadaki herkes belirleyemesin; kilit açılınca PIN sayfası gelir.
                NavigationStack {
                    YoneticiKilidi(baslik: "Kiosk PIN'i") { EmptyView() }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
                }
            }
        }
        .alert("PIN kaydedilemedi", isPresented: Binding(get: { kaydetHatasi != nil }, set: { if !$0 { kaydetHatasi = nil } })) {
            Button("Tamam", role: .cancel) { }
        } message: { Text(kaydetHatasi ?? "") }
    }
}

/// Kiosktaki "şu anki okur" oturumu: işlemden ya da hareketsizlikten sonra kişi bilgisi silinir ki sıradaki
/// öğrenci öncekinin adı, sınıfı veya işlemleri üzerinden kitap alamasın/göremesin. Saat dışarıdan verilir.
nonisolated struct KioskKisiOturumu: Equatable {
    static let zamanAsimi: TimeInterval = 45
    var ad = ""
    var studentID: UUID?
    var memberID: UUID?
    var sinif = ""
    var sonEtkilesim: Date = .now

    var kisiVar: Bool { !ad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func etkilesim(now: Date = .now) { sonEtkilesim = now }
    func suresiDoldu(now: Date = .now) -> Bool { kisiVar && now.timeIntervalSince(sonEtkilesim) >= Self.zamanAsimi }
    mutating func temizle(now: Date = .now) { self = KioskKisiOturumu(sonEtkilesim: now) }
    mutating func kartOkundu(_ student: Student, now: Date = .now) {
        ad = student.name; studentID = student.id; memberID = nil; sinif = student.className; sonEtkilesim = now
    }
}

private extension View {
    func rakamKlavyesi() -> some View {
#if os(iOS)
        keyboardType(.numberPad)
#else
        self
#endif
    }
}

/// Kiosk ilk kez açılırken çıkış PIN'ini belirletir (4–8 rakam, 1234 olamaz, iki kez girilir).
struct KioskPINBelirlemeSayfasi: View {
    let onKaydet: (String) -> Void
    let onVazgec: () -> Void
    @State private var pin = ""
    @State private var tekrar = ""
    /// Uyarı alan doldukça gösterilir: tekrar alanı boşken "aynı değil" denmez.
    private var gorunenSorun: String? { pin.isEmpty ? nil : KioskPIN.sorun(pin, tekrar: tekrar.isEmpty ? nil : tekrar) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Yeni PIN", text: $pin)
                        .rakamKlavyesi()
                        .accessibilityIdentifier("kiosk.pin")
                    SecureField("PIN'i tekrar girin", text: $tekrar)
                        .rakamKlavyesi()
                        .accessibilityIdentifier("kiosk.pinRepeat")
                } header: {
                    Text("Kiosk çıkış PIN'i")
                } footer: {
                    Text("Kiosk açıkken öğrenciler uygulamanın geri kalanına geçemesin diye çıkışta bu PIN sorulur. PIN 4–8 rakamdır ve 1234 olamaz. Sonradan Ayarlar › Ödünç ve Kiosk bölümünden değiştirilebilir.")
                }
                if let gorunenSorun {
                    Section { Label(gorunenSorun, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .navigationTitle("PIN belirleyin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { onVazgec() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet ve aç") { onKaydet(pin) }
                        .disabled(KioskPIN.sorun(pin, tekrar: tekrar) != nil)
                        .accessibilityIdentifier("kiosk.savePIN")
                }
            }
        }
    }
}

#if os(iOS)
/// iPad/iPhone masaya konur; okuyucu kartını okutur ya da tam adını yazar, kitabın barkodunu okutur.
/// Kayıtlı kitap ödünçteyse iade alınır, değilse ödünç verilir. Her işlemden ve 45 sn hareketsizlikten sonra
/// kişi bilgisi silinir; ad önerisi gösterilmez, kayıtlı kişiler yalnız kart ya da tam ad eşleşmesiyle bulunur.
struct KioskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var transactionMode = "Ödünç ver"
    @State private var oturum = KioskKisiOturumu()
    @State private var isScanning = false
    @State private var isScanningCard = false
    /// Yalnız şu anki okurun son 3 satırı; okur değişince ya da işlem bitince silinir.
    @State private var log: [String] = []
    /// Son işlemin kişisiz özeti (kitap adı); kısa süre sonra kaybolur.
    @State private var sonuc: String?
    @State private var isAskingPIN = false
    @State private var enteredPIN = ""
    @State private var isShowingAsk = false
    @State private var rehberliErisim = UIAccessibility.isGuidedAccessEnabled
    /// İadede isteğe bağlı: öğrenci kitabı bitirdi mi? nil = söylemek istemiyor.
    @State private var okudu: Bool?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "books.vertical.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(KitapTema.ana)

                Text("Kitap Ödünç Kiosku")
                    .font(.largeTitle.weight(.bold))

                Picker("İşlem", selection: $transactionMode) {
                    Text("Ödünç ver").tag("Ödünç ver")
                    Text("İade al").tag("İade al")
                }.pickerStyle(.segmented).padding(.horizontal)

                if transactionMode == "İade al" {
                    Picker("Kitabı bitirdin mi?", selection: $okudu) {
                        Text("Söylemeyeceğim").tag(Bool?.none)
                        Text("Bitirdim").tag(Bool?.some(true))
                        Text("Bitirmedim").tag(Bool?.some(false))
                    }
                    .pickerStyle(.segmented).padding(.horizontal)
                    .accessibilityIdentifier("kiosk.readingCompleted")
                }

                // Öneri listesi yok: başkasının adı yazarken görünmesin. Kart okutmak en güvenli yoldur.
                TextField("Kartınızı okutun ya da adınızı yazın", text: Binding(
                    get: { oturum.ad },
                    set: { yeni in
                        guard yeni != oturum.ad else { return }
                        oturum.ad = yeni; oturum.studentID = nil; oturum.memberID = nil; oturum.sinif = ""
                        oturum.etkilesim()
                    }))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.title2)
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier("kiosk.person")

                // Öğrenci kütüphane kartı: barkodu okutunca ad otomatik dolar
                Button {
                    oturum.etkilesim()
                    isScanningCard = true
                } label: {
                    Label("Öğrenci Kartımı Okut", systemImage: "person.text.rectangle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("kiosk.scanCard")

                // Öğrenci kitabın yerini konuşarak sorar (ad/ödünç bilgisi Google'a gitmez)
                Button {
                    isShowingAsk = true
                } label: {
                    Label("Sesli Kitap Sor", systemImage: "questionmark.bubble")
                }
                .buttonStyle(.kitapTonlu(KitapTema.amazon))
                .disabled(!GeminiSettings.isActive)

                Button {
                    oturum.etkilesim()
                    if oturum.kisiVar { isScanning = true } else { addLog("Önce kartınızı okutun ya da adınızı yazın.") }
                } label: {
                    Label("Kitabın Barkodunu Okut", systemImage: "barcode.viewfinder")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("kiosk.scanBook")

                Text("İşlem türünü seçin; kayıtlı öğrenci kartı ve kitap barkoduyla devam edin. Her kitaptan sonra kartınızı yeniden okutmanız gerekir.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let sonuc {
                    Label(sonuc, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KitapTema.baslikGradyani, in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("kiosk.result")
                }

                if !log.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.callout.weight(.medium))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KitapTema.baslikGradyani, in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                if !rehberliErisim {
                    Label("Öğrencilerin başka uygulamaya geçememesi için Rehberli Erişim'i açın: Ayarlar › Erişilebilirlik › Rehberli Erişim, sonra Sağ/Yan düğmeye üç kez basın.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("kiosk.guidedAccessHint")
                }

                Spacer()
            }
            .padding(.top, 40)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { oturum.etkilesim() })
            .task {
                // Hareketsizlik denetimi: süre dolunca kişi ve satırlar silinir.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if oturum.suresiDoldu() { kisiyiTemizle() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
                rehberliErisim = UIAccessibility.isGuidedAccessEnabled
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kiosku Kapat") {
                        enteredPIN = ""
                        isAskingPIN = true
                    }
                }
            }
            .alert("Kiosk PIN'i", isPresented: $isAskingPIN) {
                SecureField("PIN", text: $enteredPIN)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Button("Çık") {
                    // Ayarlar'da boş bırakılan PIN, PIN'siz çıkış anlamına gelmez
                    if KioskPIN.dogrula(enteredPIN) {
                        dismiss()
                    } else {
                        addLog("⚠️ PIN hatalı. Kiosk açık kalıyor.")
                    }
                    enteredPIN = ""
                }
                Button("Vazgeç", role: .cancel) { enteredPIN = "" }
            } message: {
                Text("Kiosk modundan çıkmak için PIN girin. PIN, Ayarlar'dan değiştirilebilir.")
            }
            .sheet(isPresented: $isShowingAsk) { KioskAskView() }
            .fullScreenCover(isPresented: $isScanning) {
                ZStack(alignment: .topTrailing) {
                    LiveISBNScannerView { code in
                        isScanning = false
                        handleKioskScan(code)
                    } onCancel: {
                        isScanning = false
                    }
                    Button {
                        isScanning = false
                    } label: {
                        Label("Kapat", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .padding()
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $isScanningCard) {
                ZStack(alignment: .topTrailing) {
                    LiveISBNScannerView { code in
                        isScanningCard = false
                        handleStudentCardScan(code)
                    } onCancel: {
                        isScanningCard = false
                    }
                    Button {
                        isScanningCard = false
                    } label: {
                        Label("Kapat", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .padding()
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Öğrenci kartı barkodunu (OGR…) okuyup adı otomatik doldurur; önceki okurun satırları silinir.
    private func handleStudentCardScan(_ code: String) {
        do {
            let student = try SchoolLibraryService.student(forCard: code)
            kisiyiTemizle()
            oturum.kartOkundu(student)
            addLog("👤 \(student.name) (\(student.className))")
        } catch { addLog("⚠️ " + error.localizedDescription) }
    }

    private func handleKioskScan(_ code: String) {
        oturum.etkilesim()
        // Demirbaş, ISBN ve kurum içi barkod aynı çözümleyiciyle bulunur (barkod masasıyla aynı kural).
        switch OkutCozumleyici.coz(code, context: modelContext) {
        case .hata(let mesaj):
            addLog("⚠️ " + mesaj)
        case .ogrenci(let student):
            kisiyiTemizle()
            oturum.kartOkundu(student)
            addLog("👤 \(student.name) (\(student.className))")
        case .kitap(let book, let nusha, _):
            guard oturum.kisiVar else { addLog("Önce kartınızı okutun ya da adınızı yazın."); return }
            islemYap(book: book, nusha: nusha)
        }
    }

    private func islemYap(book: CatalogBook, nusha: BookCopy?) {
        let name = oturum.ad.trimmingCharacters(in: .whitespaces)
        var studentID = oturum.studentID
        var memberID = oturum.memberID
        let sinif = oturum.sinif
        do {
            // Yazılan ad kayıtlı bir üyenin tam adıysa (ve tek eşleşiyorsa) üye kimliğiyle işlem yapılır.
            if studentID == nil, memberID == nil {
                let uyeler = MemberStore.all().filter { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }
                let ogrenciVar = (try? SchoolLibraryService.resolvedStudent(name: name, className: sinif)) != nil
                if uyeler.count == 1, !ogrenciVar { memberID = uyeler[0].id }
            }
            if transactionMode == "İade al" {
                // Adını yazarak alan kayıtlı öğrencinin ödüncü kimlikle tutulur; iadede de
                // aynı kimlik çözülür ki "ödünç kaydı bulunamadı" hatasına düşmesin
                if studentID == nil, memberID == nil,
                   let student = try? SchoolLibraryService.resolvedStudent(name: name, className: sinif) {
                    let bookID = book.id
                    let bookLoans = try modelContext.fetch(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.bookID == bookID }))
                    if bookLoans.contains(where: { $0.studentID == student.id && $0.memberID == nil }) { studentID = student.id }
                }
                _ = try SchoolLibraryService.giveBack(book: book, person: name, className: sinif, studentID: studentID, copyID: nusha?.id,
                                                      context: modelContext, memberID: memberID, readingCompleted: okudu)
                tamamlandi("↩︎ \(book.title) iade kaydedildi.")
            } else {
                let loan = try SchoolLibraryService.lend(book: book, person: name, className: sinif, context: modelContext,
                                                         studentID: studentID, copyID: nusha?.id, memberID: memberID)
                if loan.studentID == nil && loan.memberID == nil {
                    // Ödünç kaydedildi; yalnız ad defteri yazılamadıysa sessiz geçilmez
                    do { try MemberStore.addVerified(Member(name: name)) }
                    catch { addLog("⚠️ Üye defterine eklenemedi: \(error.localizedDescription)") }
                }
                tamamlandi("✓ \(book.title) ödünç verildi.")
            }
        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .zatenElinde {
            addLog("⚠️ Bu kitap zaten üzerinizde görünüyor. İade etmek için “İade al”ı seçin.")
        } catch { addLog("⚠️ " + error.localizedDescription) }
    }

    /// İşlem sonrası: kişi ve satırlar silinir, yalnız kişisiz özet kısa süre görünür.
    private func tamamlandi(_ metin: String) {
        kisiyiTemizle()
        sonuc = metin
        AccessibilityNotification.Announcement(metin).post()
        Task {
            try? await Task.sleep(for: .seconds(8))
            if sonuc == metin { sonuc = nil }
        }
    }

    private func kisiyiTemizle() {
        oturum.temizle()
        okudu = nil
        log = []
        sonuc = nil
    }

    private func addLog(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 3 {
            log.removeLast(log.count - 3)
        }
    }
}
#endif
