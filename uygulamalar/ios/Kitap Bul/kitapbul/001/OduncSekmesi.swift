import SwiftUI
import SwiftData

struct OduncSekmesi: View {
    enum Bolum: String, CaseIterable, Identifiable {
        case etkin = "Etkin", geciken = "Geciken", rezervasyon = "Sıra", gecmis = "Geçmiş"
        var id: String { rawValue }
    }
    private enum HistoryPeriod: String, CaseIterable, Identifiable {
        case all = "Tüm tarihler", month = "Bu ay", year = "Bu yıl"
        var id: String { rawValue }
        var start: Date? {
            switch self {
            case .all: nil
            case .month: Calendar.current.dateInterval(of: .month, for: .now)?.start
            case .year: Calendar.current.dateInterval(of: .year, for: .now)?.start
            }
        }
    }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @Query(sort: \ActiveLoan.dueDate) private var loans: [ActiveLoan]
    @Query(filter: #Predicate<Reservation> { !$0.isClosed }, sort: \Reservation.createdAt) private var reservations: [Reservation]
    @AppStorage("loanDurationDays") private var loanDurationDays = 15
    @SceneStorage("loanSection") private var sectionRaw = Bolum.etkin.rawValue
    @SceneStorage("loanSearch") private var search = ""
    @SceneStorage("loanClass") private var selectedClass = ""
    @SceneStorage("loanKindFilter") private var kindRaw = LoanKindFilter.kutuphane.rawValue
    @AppStorage("schoolName") private var schoolName = ""
    @State private var todayOnly = false
    @State private var period = HistoryPeriod.all
    @State private var historyLimit = 100
    @State private var history = LoanHistoryStore.all
    /// Barkod masası hangi modda açık (ödünç ya da iade); `nil` kapalı.
    @State private var masaModu: HizliOduncSayfasi.Mode?
    @State private var classLoan = false
    @State private var students = false
    @State private var members = false
    @State private var okurGecmisi = false
    @State private var kiosk = false
    @State private var message: String?
    @State private var error: String?
    @State private var selectedLoan: ActiveLoan?
    @State private var lostCandidate: ActiveLoan?
    @State private var closeCandidate: Reservation?
    @State private var report: String?
    @State private var identityLoan: ActiveLoan?
    /// Arama dizini her çizimde yeniden kurulmaz; ekran açılınca ve öğrenci/üye ekranları kapanınca yenilenir.
    @State private var identityIndex = LibraryIdentitySearchIndex(students: StudentStore.all(), members: MemberStore.all())

    private var kindFilter: LoanKindFilter { LoanKindFilter(rawValue: kindRaw) ?? .kutuphane }
    private func refreshIdentityIndex() { identityIndex = LibraryIdentitySearchIndex(students: StudentStore.all(), members: MemberStore.all()) }

    private var section: Bolum { Bolum(rawValue: sectionRaw) ?? .etkin }
    private var sectionBinding: Binding<Bolum> { Binding(get: { section }, set: { sectionRaw = $0.rawValue; todayOnly = false; historyLimit = 100 }) }
    /// Özet kartları ve gecikenler kütüphane ödünçleriyle sınırlıdır; ders kitapları ayrı süzgeçte.
    private var libraryLoans: [ActiveLoan] { LoanKindFilter.kutuphane.uygula(loans) }
    private var overdue: [ActiveLoan] { LoanKindFilter.gecikenKutuphane(loans: loans) }
    private var textbookWaiting: Int { LoanKindFilter.dersKitabiBekleyen(loans: loans) }
    private var classes: [String] { Array(Set(loans.map(\.studentClass) + reservations.map(\.studentClass) + history.compactMap(\.classSnapshot))).filter { !$0.isEmpty }.sorted() }
    private func matches(_ text: String, className: String) -> Bool {
        (selectedClass.isEmpty || selectedClass == className) && (search.isEmpty || CatalogMatcher.normalize(text).contains(CatalogMatcher.normalize(search)))
    }
    private var displayedLoans: [ActiveLoan] {
        let index = identityIndex
        let kapsam = kindFilter.uygula(loans)
        let source = section == .geciken ? kapsam.filter(\.isOverdue) : kapsam
        return source.filter {
            (!todayOnly || Calendar.current.isDateInToday($0.dueDate)) && matches($0.bookTitleSnapshot + " " + index.text(name: $0.studentName, className: $0.studentClass, studentID: $0.studentID, memberID: $0.memberID, numberSnapshot: $0.studentNumberSnapshot), className: $0.studentClass)
        }
    }
    private var displayedReservations: [Reservation] {
        let index = identityIndex
        return reservations.filter { matches($0.bookTitleSnapshot + " " + index.text(name: $0.studentName, className: $0.studentClass, studentID: $0.studentID, memberID: $0.memberID, numberSnapshot: $0.studentNumberSnapshot), className: $0.studentClass) }
    }
    private var displayedHistory: [LoanEvent] {
        let index = identityIndex
        return history.filter {
            (period.start == nil || $0.date >= period.start!) && matches(index.text(for: $0), className: $0.classSnapshot ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Birincil düğmeler ve özet tek satırda: büyük yazıda aşağı itilen kartlar
                    // ayrı bir liste hücresi olarak ağaçtan düşmez (erişilebilirlik denetimi).
                    VStack(spacing: 12) {
                        quickActions
                        summary
                    }
                }.listRowBackground(Color.clear)
                Section {
                    if typeSize.isAccessibilitySize {
                        Picker("Bölüm", selection: sectionBinding) { ForEach(Bolum.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.menu).accessibilityIdentifier("loans.section")
                    } else {
                        Picker("Bölüm", selection: sectionBinding.animation(reduceMotion || !effects ? nil : .snappy)) { ForEach(Bolum.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("loans.section")
                    }
                    if section == .etkin || section == .geciken {
                        Picker("Tür", selection: $kindRaw) { ForEach(LoanKindFilter.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("loans.kind")
                    }
                    if todayOnly {
                        HStack { Label("Bugün iade edilecekler", systemImage: "calendar"); Spacer(); Button("Tümü") { todayOnly = false }.frame(minHeight: 44) }
                    }
                    if section == .gecmis {
                        Picker("Tarih aralığı", selection: $period) { ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) } }
                    }
                    if !selectedClass.isEmpty {
                        Button("Sınıf: \(selectedClass) · Temizle", systemImage: "xmark.circle") { selectedClass = "" }.frame(minHeight: 44)
                    }
                }
                switch section {
                case .etkin, .geciken:
                    if section == .geciken, !displayedLoans.isEmpty {
                        sinifMesajlari
                    }
                    if displayedLoans.isEmpty { emptyState(section == .geciken ? "Geciken ödünç yok" : "Ödünçte kitap yok") }
                    ForEach(displayedLoans) { loan in
                        Button { selectedLoan = loan } label: { loanRow(loan) }.buttonStyle(.plain)
                            .accessibilityIdentifier("loan.row.\(loan.id.uuidString)")
                            .accessibilityHint("Ayrıntı, iade ve uzatma için açın")
                            // Sona kadar kaydırma iade yapmaz: geri alınamayan iade ayrı bir dokunuş ister.
                            .swipeActions(edge: .leading, allowsFullSwipe: false) { Button("İade al", systemImage: "arrow.uturn.left") { returnLoan(loan) }.tint(KitapTema.basari) }
                            .swipeActions(edge: .trailing) {
                                if loan.extensionCount < OduncMerkezi.enFazlaUzatma {
                                    Button("Uzat", systemImage: "calendar.badge.plus") { extend(loan) }.tint(KitapTema.amazon)
                                }
                            }
                            .contextMenu {
                                Button("Ayrıntı", systemImage: "info.circle") { selectedLoan = loan }
                                Button("İade al", systemImage: "arrow.uturn.left") { returnLoan(loan) }
                                HasarliIadeSecenekleri { returnLoan(loan, durum: $0) }
                                ShareLink(item: OduncMerkezi.veliMesaji(ogrenci: loan.studentName, sinif: loan.studentClass, kitap: loan.bookTitleSnapshot, sonGun: loan.dueDate, okul: schoolName, kind: loan.kind)) { Label("Veli mesajını paylaş", systemImage: "square.and.arrow.up") }
                                Button("Kayıp bildir", systemImage: "exclamationmark.octagon", role: .destructive) { lostCandidate = loan }
                            }
                    }
                case .rezervasyon:
                    if displayedReservations.isEmpty { emptyState("Bekleyen rezervasyon yok") }
                    ForEach(displayedReservations) { reservation in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reservation.bookTitleSnapshot).font(.headline)
                            Text(identityIndex.text(name: reservation.studentName, className: reservation.studentClass,
                                studentID: nil, memberID: nil, numberSnapshot: reservation.studentNumberSnapshot)).font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
                            if reservation.memberID != nil { Text("Üye rezervasyonu").font(.footnote) }
                            if reservation.needsIdentityReview { Text("Eski kişi kaydı — kimlik incelemesi gerekiyor").font(.footnote) }
                            if let expiry = reservation.expiresAt {
                                Label(expiry < .now ? "Ayırma süresi doldu" : "\(expiry.formatted(OduncMerkezi.tarihSaatBicimi)) tarihine kadar ayrıldı", systemImage: "clock").font(.footnote)
                            } else { Label("Sırada bekliyor", systemImage: "hourglass").font(.footnote) }
                            Button("Sırayı kapat", systemImage: "checkmark") { closeCandidate = reservation }.buttonStyle(.borderless).frame(minHeight: 44)
                        }.padding(.vertical, 4).accessibilityElement(children: .contain)
                    }
                case .gecmis:
                    if displayedHistory.isEmpty { emptyState("Ödünç geçmişi yok") }
                    ForEach(displayedHistory.prefix(historyLimit)) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.bookTitle).font(.headline)
                            Text([event.person, event.classSnapshot ?? "", event.kind.rawValue].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                            Text(event.date.formatted(OduncMerkezi.tarihSaatBicimi) + (event.wasLate ? " · gecikmeli" : "")).font(.footnote).foregroundStyle(KitapTema.ikincilMetin)
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                    }
                    if displayedHistory.count > historyLimit {
                        Button("Daha fazla göster (\(min(historyLimit, displayedHistory.count))/\(displayedHistory.count))") { historyLimit += 100 }.frame(minHeight: 44)
                    }
                }
            }
            .okunurAltKaydirmaKenari()
            .navigationTitle("Ödünç")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ara")
            .accessibilityHint("Öğrenci, üye, okul numarası, kitap, sınıf veya işlem arayın")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Tüm sınıflar") { selectedClass = "" }
                        ForEach(classes, id: \.self) { name in Button(name) { selectedClass = name } }
                    } label: { Label("Sınıf filtresi", systemImage: "line.3.horizontal.decrease") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sınıfa toplu ödünç", systemImage: "person.3.sequence") { classLoan = true }
                        Button("Öğrenciler", systemImage: "person.2") { students = true }
                        Button("Üyeler", systemImage: "person.crop.rectangle.stack") { members = true }
                        Button("Okur geçmişi", systemImage: "clock.arrow.circlepath") { okurGecmisi = true }
                        Button("Kiosk modu", systemImage: "person.crop.rectangle") { kiosk = true }
                    } label: { Label("Diğer", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("loans.more")
                }
            }
            .onAppear { KioskPIN.gocEt(); history = LoanHistoryStore.all; refreshIdentityIndex(); yenileRezervasyonlar(); applyRoute() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { yenileRezervasyonlar() } }
            .onChange(of: KutuphaneRotasi.shared.oduncBolumu) { _, _ in applyRoute() }
            .onChange(of: KutuphaneRotasi.shared.oduncAramasi) { _, _ in applyRoute() }
            .onChange(of: loans.map(\.id)) { _, _ in history = LoanHistoryStore.all }
            .onChange(of: search) { _, _ in historyLimit = 100 }
            .onChange(of: period) { _, _ in historyLimit = 100 }
            .onChange(of: selectedClass) { _, _ in historyLimit = 100 }
            .fullScreenCover(item: $masaModu) { HizliOduncSayfasi(baslangic: $0) }
            .fullScreenCover(isPresented: $kiosk) { KioskOturumu() }
            .sheet(isPresented: $classLoan) { ClassLoanView() }
            .sheet(isPresented: $students, onDismiss: { refreshIdentityIndex() }) { StudentsView() }
            .sheet(isPresented: $members, onDismiss: { refreshIdentityIndex() }) { MembersView() }
            .sheet(item: $identityLoan) { loan in
                YoneticiKilidi(baslik: "Ödünç kimliğini düzelt") {
                    LoanIdentityReviewSheet(loan: loan) { identityLoan = nil; history = LoanHistoryStore.all }
                }
            }
            .sheet(isPresented: $okurGecmisi) { LoanHistoryView() }
            .sheet(item: $selectedLoan, onDismiss: { history = LoanHistoryStore.all }) { OduncDetaySayfasi(loan: $0) { message = $0 } }
            .sheet(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                KapatilabilirSayfa { ScrollView { Text(report ?? "").textSelection(.enabled).padding() }.navigationTitle("Kayıp tutanağı") }
            }
            .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) { } } message: { Text(error ?? "") }
            .confirmationDialog("Bu nüsha kayıp olarak kaydedilsin mi?", isPresented: Binding(get: { lostCandidate != nil }, set: { if !$0 { lostCandidate = nil } }), titleVisibility: .visible) {
                Button("Kayıp bildir", role: .destructive) {
                    guard let loan = lostCandidate else { return }
                    lostCandidate = nil
                    Task {
                        do {
                            report = try await YetkiKapisi.yoneticiyleCalistir(neden: "Kayıp bildirmek için kimliğinizi doğrulayın") {
                                try SchoolLibraryService.reportLost(loan, context: modelContext)
                            }
                            history = LoanHistoryStore.all
                        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .kayipNushaGerekli {
                            // Hangi nüshanın kaybolduğu bilinmiyor: önce nüsha kimliği düzeltilir.
                            self.error = hata.message
                            identityLoan = loan
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .confirmationDialog("Rezervasyon kapatılsın mı? Sıradaki kişiye haber verilir; geçmiş kaydı korunur.", isPresented: Binding(get: { closeCandidate != nil }, set: { if !$0 { closeCandidate = nil } }), titleVisibility: .visible) {
                Button("Sırayı kapat", role: .destructive) { if let reservation = closeCandidate { closeReservation(reservation) }; closeCandidate = nil }
                Button("Vazgeç", role: .cancel) { closeCandidate = nil }
            }
            .safeAreaInset(edge: .bottom) {
                if let message {
                    HStack {
                        Label(message, systemImage: "checkmark.circle").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button { self.message = nil } label: { Label("Bildirimi kapat", systemImage: "xmark").labelStyle(.iconOnly).frame(width: 44, height: 44) }
                    }.padding(.horizontal).background(.bar)
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 8) {
            summaryGrid
            if textbookWaiting > 0 {
                Button { sectionRaw = Bolum.etkin.rawValue; kindRaw = LoanKindFilter.dersKitabi.rawValue; todayOnly = false } label: {
                    Label("Ders kitabı: \(textbookWaiting) teslim bekliyor", systemImage: "text.book.closed")
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.kitapSade).accessibilityIdentifier("loans.textbookWaiting")
            }
        }
    }
    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            if typeSize.isAccessibilitySize {
                ForEach(0..<4) { index in GridRow { summaryItem(index) } }
            } else {
                GridRow { summaryItem(0); summaryItem(1) }
                GridRow { summaryItem(2); summaryItem(3) }
            }
        }.buttonStyle(.kitapSade)
            .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder
    private func summaryItem(_ index: Int) -> some View {
        switch index {
        case 0:
            Button { sectionRaw = Bolum.etkin.rawValue; kindRaw = LoanKindFilter.kutuphane.rawValue; todayOnly = false } label: { IstatistikKarti(deger: libraryLoans.count, baslik: "Ödünçte", ikon: "books.vertical", renk: KitapTema.amazon) }
        case 1:
            Button { sectionRaw = Bolum.geciken.rawValue; kindRaw = LoanKindFilter.kutuphane.rawValue; todayOnly = false } label: { IstatistikKarti(deger: overdue.count, baslik: "Gecikmiş", ikon: "exclamationmark.circle", renk: .red) }
        case 2:
            Button { sectionRaw = Bolum.etkin.rawValue; kindRaw = LoanKindFilter.kutuphane.rawValue; todayOnly = true } label: { IstatistikKarti(deger: libraryLoans.filter { Calendar.current.isDateInToday($0.dueDate) }.count, baslik: "Bugün iade", ikon: "calendar", renk: KitapTema.dosya) }
        default:
            Button { sectionRaw = Bolum.rezervasyon.rawValue; todayOnly = false } label: { IstatistikKarti(deger: reservations.count, baslik: "Sırada", ikon: "bookmark", renk: KitapTema.toplu) }
        }
    }
    /// İki birincil iş: barkod masasını ödünç ya da iade modunda açar. Sınıfa, Öğrenciler,
    /// Üyeler ve Kiosk araç çubuğundaki "Diğer" menüsündedir.
    private var quickActions: some View {
        EsitSutunIzgara(sutun: typeSize.isAccessibilitySize ? 1 : 2, yatayAralik: 8) {
            Button { masaModu = .lend } label: { quickLabel("Barkodla ödünç ver", "barcode.viewfinder") }
                .buttonStyle(.kitapDolu(KitapTema.anaDolu))
                .accessibilityIdentifier("loans.quick")
            Button { masaModu = .giveBack } label: { quickLabel("Barkodla iade al", "arrow.uturn.left") }
                .buttonStyle(.kitapTonlu())
                .accessibilityHint("Öğrenci seçmeden kitabı okutarak iade alır")
                .accessibilityIdentifier("loans.quickReturn")
        }
    }
    private func quickLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private func emptyState(_ normal: String) -> some View {
        ContentUnavailableView(search.isEmpty && selectedClass.isEmpty && !todayOnly ? normal : "Filtreye uygun kayıt yok", systemImage: "books.vertical", description: Text(search.isEmpty && selectedClass.isEmpty ? "“Barkodla ödünç ver” ile öğrenci kartını ve kitabı okutabilirsiniz." : "Aramayı veya sınıf filtresini değiştirin."))
    }
    private func loanRow(_ loan: ActiveLoan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loan.bookTitleSnapshot).font(.headline).foregroundStyle(Color.primary)
            Text("\(loan.studentName)\(loan.studentClass.isEmpty ? "" : " · \(loan.studentClass)")").font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
            // Yalnız ikon kırmızı; metin kontrast için birincil renkte kalır.
            let gecikme = OduncMerkezi.gecikmeGunu(sonGun: loan.dueDate)
            Label {
                Text(gecikme > 0 ? "\(OduncMerkezi.sonGunMetni(loan.dueDate)) · Son gün \(loan.dueDate.formatted(OduncMerkezi.tarihBicimi))" : OduncMerkezi.sonGunMetni(loan.dueDate))
                    .foregroundStyle(gecikme >= 0 ? Color.primary : KitapTema.ikincilMetin)
            } icon: {
                Image(systemName: gecikme > 0 ? "exclamationmark.circle.fill" : (gecikme == 0 ? "clock" : "calendar"))
                    .foregroundStyle(gecikme > 0 ? Color.red : KitapTema.ikincilMetin)
            }.font(.footnote.weight(gecikme >= 0 ? .semibold : .regular))
            if loan.extensionCount > 0 { Text("\(loan.extensionCount) kez uzatıldı").font(.footnote).foregroundStyle(KitapTema.ikincilMetin) }
            if let number = loan.studentNumberSnapshot, !number.isEmpty { Text("Okul no: " + number).font(.footnote) }
            if loan.needsIdentityReview { Label("Kimliği düzeltmek için aç", systemImage: "person.crop.circle.badge.questionmark").font(.footnote) }
        }.padding(.vertical, 4).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func returnLoan(_ loan: ActiveLoan, durum: String? = nil) {
        let title = loan.bookTitleSnapshot, person = loan.studentName
        do {
            let notice = try SchoolLibraryService.returnLoan(loan, context: modelContext, returnedCondition: durum)
            message = "\(title) iade alındı: \(person)." + (notice.map { " " + $0 } ?? "")
            history = LoanHistoryStore.all
        }
        catch { self.error = error.localizedDescription }
    }
    private func extend(_ loan: ActiveLoan) {
        do { let date = try OduncMerkezi.uzat(loan, context: modelContext, defaultDays: loanDurationDays); message = "Yeni son gün: \(date.formatted(OduncMerkezi.tarihBicimi))" }
        catch { self.error = error.localizedDescription }
    }
    /// Sınıf bazlı toplu veli mesajı: sınıf süzgeci açıksa doğrudan, değilse sınıf seçmeli menü.
    @ViewBuilder private var sinifMesajlari: some View {
        let geciken = displayedLoans
        if !selectedClass.isEmpty {
            ShareLink(item: OduncMerkezi.sinifVeliMesajlari(geciken, okul: schoolName)) {
                Label("Bu sınıfın veli mesajlarını paylaş", systemImage: "square.and.arrow.up.on.square")
            }.frame(minHeight: 44).accessibilityIdentifier("loans.classMessages")
        } else {
            let siniflar = Array(Set(geciken.map(\.studentClass))).filter { !$0.isEmpty }.sorted()
            if !siniflar.isEmpty {
                Menu {
                    ForEach(siniflar, id: \.self) { sinif in
                        ShareLink(item: OduncMerkezi.sinifVeliMesajlari(geciken.filter { $0.studentClass == sinif }, okul: schoolName)) { Text(sinif) }
                    }
                } label: { Label("Sınıfın veli mesajlarını paylaş", systemImage: "square.and.arrow.up.on.square") }
                .frame(minHeight: 44).accessibilityIdentifier("loans.classMessages")
            }
        }
    }

    /// Ayırma süresi dolan sıra ilerler (uygulama arka plandayken süre dolmuş olabilir).
    private func yenileRezervasyonlar() {
        do { _ = try SchoolLibraryService.refreshReservations(context: modelContext) }
        catch { AppLog.write("Rezervasyonlar yenilenemedi") }
    }

    private func closeReservation(_ reservation: Reservation) {
        do { try SchoolLibraryService.cancelReservation(reservation, context: modelContext); message = "Rezervasyon kapatıldı." }
        catch { self.error = error.localizedDescription }
    }
    private func applyRoute() {
        if let value = KutuphaneRotasi.shared.oduncBolumu {
            sectionRaw = value.rawValue
            kindRaw = LoanKindFilter.kutuphane.rawValue
            search = ""
            selectedClass = ""
            todayOnly = KutuphaneRotasi.shared.bugunIadeler
            KutuphaneRotasi.shared.bugunIadeler = false
            KutuphaneRotasi.shared.oduncBolumu = nil
        }
        if let value = KutuphaneRotasi.shared.oduncAramasi {
            search = value
            KutuphaneRotasi.shared.oduncAramasi = nil
        }
    }
}
