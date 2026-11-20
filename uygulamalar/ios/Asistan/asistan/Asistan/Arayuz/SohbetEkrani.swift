import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Vision

struct SohbetEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(SesOturumu.self) private var ses
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(OnayKapisi.self) private var onay
    @Environment(KisiselAlan.self) private var alan
    @Environment(\.colorScheme) private var sema
    @State private var gorunumAcik = false
    @State private var kisiselAcik = false
    @State private var ajanAcik = false
    @State private var tetikAcik = false
    @State private var projelerAcik = false
    @State private var herYerdeAcik = false
    @State private var sohbetAra = false
    @State private var sorgu = ""
    @State private var metin = ""
    @State private var ayarlarAcik = false
    @State private var telefonAcik = false
    @State private var atolyeAcik = false
    @State private var dosyaKasasiAcik = false
    @State private var otomatikGorsel: Beyin.AtolyeIstegi?
    @State private var gecmisAcik = false
    @State private var belgeSec = false
    @State private var donusturmeAcik = false
    @State private var uretkenlikAcik = false
    @State private var belge: OkunanBelge?
    @State private var belgeOkunuyor = false
    @State private var belgeOkumaGorevi: Task<Void, Never>?
    @State private var belgeNesli = 0
    @State private var belgeHatasi: String?
    @State private var secilenFotolar: [PhotosPickerItem] = []
    @State private var ekler: [GorselEk] = []
    @State private var kameraAcik = false
    @State private var barkodKameraAcik = false
    @State private var fotoSecAcik = false
    @State private var ekSayfasiAcik = false
    @State private var bekleyenEk: EkEylemi?
    @State private var taramaAcik = false
    @State private var duzenlenen: GorselEk?
    /// Sohbet bazında yazılmış ama gönderilmemiş metin (anahtar: sohbet kimliği; nil = henüz kaydedilmemiş yeni sohbet).
    @State private var taslaklar: [UUID?: String] = [:]
    /// Hareketi Azalt: sürekli simge efektleri (dinleme dalgası) durur.
    @Environment(\.accessibilityReduceMotion) private var azHareket
    @State private var cekmeceAcik = false
    @State private var kullanimAcik = false
    @State private var gezgin = AsistanGezgin.ortak
    /// Kullanıcı listenin altında mı; yukarı kaydırdıysa akan yanıt onu zorla aşağı çekmez.
    @State private var alttaMi = true
    @State private var kullaniciKaydiriyor = false
    /// Kullanıcı yukarıdayken yeni içerik (akan yanıt ya da mesaj) geldi: "↓" düğmesinde nokta yanar; alta inince söner.
    @State private var yeniVar = false
    /// Sohbet içi arama gezinmesi: seçili eşleşmenin sırası, vurgulanan mesaj ve kaydırma tetiği
    /// (aynı UUID yeniden atanınca onChange tetiklenmediği için kaydırma artan sayaçla verilir).
    @State private var aramaSirasi = 0
    @State private var aramaHedefi: UUID?
    /// Sorguyla eşleşen mesajlar; her çizimde değil, sorgu/mesaj değişince yenilenir (`eslesmeleriYenile`).
    @State private var eslesmeListesi: [UUID] = []
    @State private var aramaYuklemesi: Task<Void, Never>?
    @State private var aramaAdimNo = 0
    /// İndirilen ya da küçültülen (henüz şeride düşmemiş) görsel sayısı; bitene kadar Gönder kapalı, ek sonraki mesaja kaymaz.
    @State private var hazirlanan = 0
    /// Fotoğraf hazırlığının nesli: "Vazgeç" artırır; eski nesilden geç dönen sonuç atılır, sayaca dokunmaz.
    @State private var fotoNesli = 0
    /// Ek hazırlıklarının zinciri: yükleme/küçültme paralel sürer, şeride ekleme seçim sırasıyla yapılır.
    @State private var ekZinciri: Task<Void, Never>?
    /// Fotoğraflar hazırlanırken basılan Gönder: hazırlık bitince (ya da "Beklemeden gönder" ile) mesaj gider.
    @State private var gonderimBekliyor = false
    /// Gönder basıldı, görseller küçültülüyor: beyin henüz boşta; ikinci gönderim ve dış tur bu pencerede araya girmesin.
    @State private var gonderiliyor = false
    /// Live tam ekranı: önce açık sayfalar kapanır, sonra sunulur (iki sunum üst üste binince Live görünmez kalıyordu).
    @State private var canliGoster = false
    /// Live açılmadan önceki kısa geçiş: bekleyen onay diyaloğu gizlenir (reddedilmez), Live ekranı onu kendisi sorar.
    @State private var canliHazirlaniyor = false
    /// P2.3 durum şeridi: kullanıcının kapattığı iletiler (kimlik = tür + metin; yeni tur başlayınca temizlenir).
    @State private var kapatilanDurumlar: Set<String> = []
    /// P2.3: yan etkili turda "Yeniden dene"/"Başka model" onayı bekleyen istek.
    @State private var yenidenDenemeOnayi: YenidenDenemeIstegi?
    @FocusState private var odak: Bool
    /// Yazı boyutu ayarıyla büyüyen simge ölçeği (üst sınırlı; düzen bozulmasın).
    @ScaledMetric(relativeTo: .body) private var olcek = 1.0
    private var k: CGFloat { min(olcek, 1.5) }

    /// Ekranın gövdesi + üst/alt katmanlar, haptik ve taslak geçişi (`body` zinciri derleyicinin tür denetimi
    /// sınırını aşmasın diye ayrı).
    private var anaYigin: some View {
        VStack(spacing: 0) {
            if sohbetAra { aramaCubugu }
            if sohbetVar {
                mesajListesi
            } else {
                baslangic
            }
            // P3.7: bağlantı halkaları (ağa bağlıyken internet/VPS/yerel vekil sorunu); çevrimdışı durum BekleyenlerSeridi'nde.
            if AgIzleyici.ortak.cevrimici, let n = BaglantiDurumu.ozet(BaglantiDurumu.ortak.haller, cevrimici: true) {
                Label(n, systemImage: "network.slash")
                    .font(.footnote).foregroundStyle(UyariRengi.renk(sema == .dark)).padding(.horizontal)
                    .accessibilityIdentifier("baglanti-durumu")
            }
            if !AgIzleyici.ortak.cevrimici || !beyin.bekleyenGonderiler.isEmpty {
                BekleyenlerSeridi()   // başlık satırı "cevrimdisi-notu" kimliğini korur
            }
            // P2.3: kota, model hatası, mikrofon, ses ve kişisel alan iletileri tek şeritte (öncelikli olan + "+N").
            durumSeridiKatmani
            dinlemeSeridi
            OlguOnayCipi(depo: beyin.depo)   // yalnız onay bekleyen olgu varsa görünür
            // P3.12: sesli okuma sürerken duraklat/hız/durdur (Live tam ekranı kendi denetimini taşır).
            if ses.konusmaci.konusuyor || OkumaCubugu.sinamada { OkumaCubugu() }
            girisCubugu
        }
        .overlay(alignment: .top) { ustCubuk }
        // Kısa bildirim (kopyalandı, beceri kaydedildi): giriş çubuğunun üstünde.
        .overlay(alignment: .bottom) { TostKatmani().padding(.bottom, 96) }
        .overlay { cekmeceKatmani }
        // P2.3: yan etkili araç başlamış turda "Yeniden dene" işlemi yineleyebilir; önce sorulur.
        .alert("Yeniden denensin mi?", isPresented: Binding(get: { yenidenDenemeOnayi != nil }, set: { if !$0 { yenidenDenemeOnayi = nil } }), presenting: yenidenDenemeOnayi) { istek in
            Button("Evet, yeniden dene") { beyin.yenidenDene(model: istek.model) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Bu istek bir işlem yapmış olabilir (mesaj, takvim, dosya…). Tekrarlamak işlemi yineleyebilir.")
        }
        // Yeni tur başlayınca kapatılan iletiler yeniden gösterilebilir.
        .onChange(of: beyin.durum) { _, yeni in if yeni != .bosta { kapatilanDurumlar = [] } }
        .sensoryFeedback(.success, trigger: TostDefteri.ortak.gorunen?.id) { _, yeni in yeni != nil }
        // Mikrofon dinlemeye geçti (uyandırma sözcüğü beklemesi sayılmaz).
        .sensoryFeedback(.impact(weight: .light), trigger: ses.dinleyici.durum == .dinliyor && !ses.uyandirmaBekliyor) { _, yeni in yeni }
        // Sohbet değişince yazılan ama gönderilmeyen metin o sohbete saklanır, yeni sohbetin taslağı geri gelir.
        .onChange(of: beyin.sohbet?.kimlik) { eski, yeni in
            // Yeni sohbetten (nil) kimliğe geçiş yalnız sohbet şimdi kaydedildiyse "kayda dönüş"tür; çekmeceden/Spotlight'tan
            // açılan eski bir sohbet olağan geçiştir (yeni sohbet taslağı o sohbete taşınmaz).
            let taze = beyin.sohbet.map { Date.now.timeIntervalSince($0.olusturma) < 10 } ?? true
            let g = Self.taslakGecisi(taslaklar, eski: eski, yeni: yeni, metin: metin, yeniKayitTaze: taze)
            taslaklar = g.taslaklar
            if g.metin != metin { metin = g.metin }
        }
    }

    var body: some View {
        NavigationStack {
            anaYigin
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
                if v.startLocation.x < 28, v.translation.width > 70, abs(v.translation.height) < 60 { withAnimation(.easeOut(duration: 0.25)) { cekmeceAcik = true } }
            })
            .sheet(isPresented: $kullanimAcik) { NavigationStack { KullanimEkrani().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kullanimAcik = false } } } } }
            .onChange(of: beyin.durum) { eski, yeni in
                // VoiceOver açıkken yanıt bitince kısa duyuru (ekran okuyucu akan metni takip edemez).
                guard UIAccessibility.isVoiceOverRunning, eski != .bosta, yeni == .bosta else { return }
                let m = beyin.sonHata == nil ? "Yanıt hazır" : "Yanıt alınamadı"
                UIAccessibility.post(notification: .announcement, argument: m)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .sensoryFeedback(trigger: beyin.durum) { eski, yeni in
                if eski == .bosta, yeni != .bosta { return .impact(weight: .light) }          // gönderildi
                if eski != .bosta, yeni == .bosta { return beyin.sonHata == nil ? .success : .error }   // yanıt bitti / hata
                return nil
            }
            .background(SohbetZemini())
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(ayarlar.gorunum.renkSemasi)
            .tint(ayarlar.gorunum.metinRengi(sema == .dark))
            .sheet(isPresented: $gorunumAcik) { NavigationStack { GorunumEkrani().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { gorunumAcik = false } } } } }
            .sheet(isPresented: $kisiselAcik) {
                NavigationStack {
                    KisiselAlanEkrani(taslakSecildi: { taslak in
                        metin = taslak
                        beyin.disTaslak = nil
                        kisiselAcik = false
                    })
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kisiselAcik = false } } }
                }
            }
            .sheet(isPresented: $ayarlarAcik) { AyarlarEkrani() }
            .sheet(isPresented: $ajanAcik) { AjanEkrani { istek in Task { try? await Task.sleep(for: .milliseconds(400)); beyin.gonder(istek) } } }
            .sheet(isPresented: $tetikAcik) { TetikleyicilerEkrani() }
            .sheet(isPresented: Binding(get: { TarayiciOturumu.ortak.gorunur }, set: { TarayiciOturumu.ortak.gorunur = $0 })) { TarayiciSayfasi() }
            .sheet(isPresented: $projelerAcik) { ProjelerEkrani() }
            .sheet(isPresented: $herYerdeAcik) { HerYerdeAraEkrani() }
            .mesajTaslagiSunumu(etkin: true)
            .sheet(isPresented: Binding(get: { DosyaKitapligi.ortak.ekranAcik }, set: { DosyaKitapligi.ortak.ekranAcik = $0 })) { DosyalarEkrani() }
            .sheet(isPresented: Binding(get: { UygulamaKatalogu.ortak.ekranAcik }, set: { UygulamaKatalogu.ortak.ekranAcik = $0 })) { NavigationStack { UygulamaKatalogEkrani().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { UygulamaKatalogu.ortak.ekranAcik = false } } } } }
            .sheet(isPresented: Binding(get: { IndirmeYoneticisi.ortak.ekranAcik }, set: { IndirmeYoneticisi.ortak.ekranAcik = $0 })) { IndirmelerEkrani() }
            .sheet(isPresented: Binding(get: { SistemKoprusu.ortak.ekranAcik }, set: { SistemKoprusu.ortak.ekranAcik = $0 })) { NavigationStack { SistemKoprusuEkrani().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { SistemKoprusu.ortak.ekranAcik = false } } } } }
            .sheet(isPresented: $telefonAcik) { TelefonEkrani() }
            .sheet(isPresented: $atolyeAcik) { AtolyeEkrani() }
            .sheet(isPresented: $dosyaKasasiAcik) {
                NavigationStack { DosyaKasasiEkrani().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Tamam") { dosyaKasasiAcik = false } }
                } }
            }
            .sheet(item: $otomatikGorsel) { istek in GorselEkrani(baslangicIstemi: istek.metin, otomatikBaslat: true) }
            .sheet(isPresented: $gecmisAcik) { GecmisEkrani() }
            .sheet(isPresented: $donusturmeAcik) { OfisDonusturmeEkrani() }
            .sheet(isPresented: $uretkenlikAcik) { UretkenlikEkrani() }
            .sheet(isPresented: Binding(get: { ArsivMerkezi.ortak.ekranAcik }, set: { ArsivMerkezi.ortak.ekranAcik = $0 })) { ArsivEkrani() }
            .sheet(isPresented: Binding(get: { GelenKutusu.ortak.ekranAcik }, set: { GelenKutusu.ortak.ekranAcik = $0 })) { GelenKutusuEkrani() }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--asistan-ui-onizleme"), ProcessInfo.processInfo.arguments.contains("--studyo") { gorunumAcik = true }
                if ProcessInfo.processInfo.arguments.contains("--cekmece-ac") { cekmeceAcik = true }
                if ProcessInfo.processInfo.arguments.contains("--durum-ornek") {   // P2.3 durum şeridi önizlemesi
                    beyin.sonHata = HataSozlugu.kotaMetni
                    beyin.sonHataTuru = .kota
                }
                if ProcessInfo.processInfo.arguments.contains("--ek-ornek") {
                    let ornek = { (c: UIColor) in UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { k in c.setFill(); k.fill(CGRect(x: 0, y: 0, width: 600, height: 400)) } }
                    ekler = [GorselEk(resim: ornek(.systemTeal)), GorselEk(resim: ornek(.systemOrange), tur: .sayfa)]
                    if ProcessInfo.processInfo.arguments.contains("--duzenleyici-ac") { duzenlenen = ekler.first }
                }
                #endif
            }
            .onChange(of: gezgin.hedef) { _, hedef in
                guard let hedef else { return }
                switch hedef {
                case .atolye:
                    ayarlar.calismaKipi = "arastirma"
                    atolyeAcik = true
                case .indirmeler: IndirmeYoneticisi.ortak.ekranAcik = true
                case .telefon: telefonAcik = true
                case .donustur: donusturmeAcik = true
                case .arsiv: ArsivMerkezi.ortak.ekranAcik = true
                case .gelenKutusu: GelenKutusu.ortak.ekranAcik = true
                case .uretkenlik: uretkenlikAcik = true
                case .herYerdeAra: herYerdeAcik = true
                }
                gezgin.tamamla()
            }
            .onChange(of: beyin.atolyeIstegi?.id) { _, _ in
                guard let istek = beyin.atolyeIstegi else { return }
                odak = false
                switch istek.kip {
                case .gorsel: otomatikGorsel = istek
                case .arsiv: gecmisAcik = true
                case .belge: belgeSec = true
                default: break
                }
                beyin.atolyeIstegi = nil
            }
            .fileImporter(isPresented: $belgeSec, allowedContentTypes: BelgeOkuyucu.desteklenenTurler) { sonuc in
                switch sonuc {
                case .success(let url):
                    belgeOkunuyor = true; belgeHatasi = nil
                    // Taranmış PDF'in OCR'ı uzun sürebilir: yeni seçim eskisini iptal eder; geç biten eski okuma yeni
                    // belgenin yerine geçmesin diye sonuç yalnız kendi nesli güncelse yazılır.
                    belgeOkumaGorevi?.cancel()
                    belgeNesli += 1
                    let nesil = belgeNesli
                    belgeOkumaGorevi = Task {
                        // P2.12: PDF'nin kopyası da saklanır (pdfIslem aracı 'ek:<kimlik>' ile adresler).
                        let is_ = Task.detached { try BelgeOkuyucu.oku(url, ekKopyasi: true) }
                        do {
                            let okunan = try await withTaskCancellationHandler { try await is_.value } onCancel: { is_.cancel() }
                            if nesil == belgeNesli { belge = okunan }
                        } catch {
                            if nesil == belgeNesli, !(error is CancellationError) { belgeHatasi = error.localizedDescription }
                        }
                        if nesil == belgeNesli { belgeOkunuyor = false }
                    }
                case .failure(let hata): belgeHatasi = hata.localizedDescription
                }
            }
            .onChange(of: beyin.disTaslak, initial: true) { _, t in
                if let t { metin = t; beyin.disTaslak = nil; kisiselAcik = false; ayarlarAcik = false; gorunumAcik = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .asistanKamera)) { _ in kameraAcik = true }
            .onReceive(NotificationCenter.default.publisher(for: .asistanSor)) { n in
                guard let url = n.object as? URL, case .sor(let metin)? = AsistanBaglantisi.coz(url) else { return }
                let sira = DisSoruKuyrugu.ic
                if beyin.durum == .bosta, sira.bekleyenler.isEmpty, !gonderiliyor {
                    // Takvim tetiğinin iç notu modele gider ama balonda/geçmişte görünmez.
                    beyin.gonder(metin, gorunenMetin: Tetik.notsuz(metin))
                    // P2.13: Siri'den sesli devir (ses=1): yanıt sesli okunur, ardından kısa takip dinlemesi açılır.
                    if AsistanBaglantisi.sesliMi(url) { Task { await ses.disSesliTurBasladi() } }
                    // Teslim alındı: köprü tek seferlik yolu (eğik çizgi, 4000+ karakter, çevrimdışı) bir daha yayınlamaz.
                    GorevKopru.ortak.alindi(url)
                } else if Self.kestirmeyiBekliyor(beklenen: GorevKopru.ortak.beklenen, metin: metin) {
                    // Yanıtı beklenen Kestirme görevi: köprü kendisi yeniden yayınlar, süresi dolunca Kestirmeye hata döner.
                    // Sıraya alınsaydı Kestirme vazgeçtikten sonra kendiliğinden çalışırdı.
                    // Burada `alindi` çağrılmaz: istek bilerek bırakılıyor; teslim sayılsa tek seferlik istek kaybolurdu.
                } else {
                    // Meşgulken (ya da önünde bekleyen varken) Siri devri / tetik bildirimi kaybolmasın: sırayla gönderilir.
                    // Köprünün yeniden yayınları aynı metni yinelemez (`sirala` yineleneni eklemez).
                    sira.ekle(metin, beyin: beyin)
                    GorevKopru.ortak.alindi(url)
                }
            }
            .confirmationDialog(onay.bekleyen?.baslik ?? "", isPresented: onayAcik, titleVisibility: .visible) {
                Button("Evet, yap") { onay.yanitla(true) }
                Button("Hayır", role: .cancel) { onay.yanitla(false) }
            } message: {
                Text(onay.bekleyen?.ayrinti ?? "")
            }
            // P2.12: Önizlemeli onay (imza) metin diyaloğuyla değil, görselli sayfayla sorulur. Live öndeyken CanliEkrani sorar.
            .sheet(item: onizlemeliOnay) { istek in
                // Kaydırarak kapatma bağlamanın setter'ında reddedilir; Live'a geçişte sayfa gizlenir, istek reddedilmez.
                ImzaOnizlemeSayfasi(istek: istek) { onay.yanitla($0, id: istek.id) }
            }
        }
    }

    private var sohbetMetni: String {
        // P3.9: sayfalı açılışta (daha eski mesaj yüklenmemişken) paylaşım bütün sohbeti kalıcı depodan kurar. Yanıt akarken
        // (gövde her parçada yeniden çizilir) veritabanına gidilmez; o sırada yüklü mesajlar paylaşılır.
        if beyin.dahaEskiVar, beyin.durum == .bosta, let s = beyin.sohbet { return beyin.depo.sohbetMetni(s, gorunenAd: ayarlar.gorunenAd) }
        return beyin.mesajlar.map { ($0.rol == .kullanici ? "Sen" : ayarlar.gorunenAd) + ":\n" + $0.metin }.joined(separator: "\n\n")
    }

    // MARK: Sohbet içi arama (süzmez; eşleşmeler arasında gezinir, seçili mesaj vurgulanır)

    /// Sorguyla eşleşen mesajların kimlikleri, sohbet sırasıyla (eskiden yeniye).
    private var eslesmeler: [UUID] { eslesmeListesi }

    private func eslesmeleriYenile() {
        let yeni = sorgu.isEmpty ? [] : Self.aramaEslesmeleri(beyin.mesajlar.map { (id: $0.id, metin: $0.metin) }, sorgu: sorgu)
        if yeni != eslesmeListesi { eslesmeListesi = yeni }
    }

    private var aramaCubugu: some View {
        let e = eslesmeler
        let sira = Self.aramaSinirla(aramaSirasi, adet: e.count)
        return HStack {
            Image(systemName: "magnifyingglass")
            TextField("Bu sohbette ara", text: $sorgu).autocorrectionDisabled()
            if !sorgu.isEmpty {
                Text(e.isEmpty ? "0/0" : "\(sira + 1)/\(e.count)")
                    .monospacedDigit().foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                    .accessibilityLabel(e.isEmpty ? "Eşleşme yok" : "\(sira + 1)/\(e.count)")
                    .accessibilityIdentifier("arama-sayaci")
                Button { aramaGit(ileri: false) } label: { Image(systemName: "chevron.up").frame(width: 32, height: 36) }
                    .buttonStyle(.plain).disabled(e.isEmpty)
                    .accessibilityLabel("Önceki eşleşme").accessibilityIdentifier("arama-onceki")
                Button { aramaGit(ileri: true) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 36) }
                    .buttonStyle(.plain).disabled(e.isEmpty)
                    .accessibilityLabel("Sonraki eşleşme").accessibilityIdentifier("arama-sonraki")
            }
            Button("Kapat") { sorgu = ""; aramaHedefi = nil; sohbetAra = false }
        }.font(.callout).foregroundStyle(SohbetRenk.metin(sema == .dark)).padding(12).temaDugmesi(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 14).padding(.top, 60)
    }

    /// Önceki/sonraki eşleşmeye geç; sıra her erişimde sınırlanır (akan yanıt eşleşme sayısını değiştirebilir).
    private func aramaGit(ileri: Bool) {
        let e = eslesmeler
        guard !e.isEmpty else { return }
        aramaSirasi = Self.aramaAdimi(Self.aramaSinirla(aramaSirasi, adet: e.count), adet: e.count, ileri: ileri)
        aramaHedefi = e[Self.aramaSinirla(aramaSirasi, adet: e.count)]
        aramaAdimNo += 1
    }

    /// Sorgu değişince: en yeni (son) eşleşmeye kurulur; boş sorguda hedef bırakılır.
    private func aramaSorgusuDegisti() {
        let e = eslesmeler
        guard !e.isEmpty else { aramaSirasi = 0; aramaHedefi = nil; return }
        aramaSirasi = e.count - 1
        aramaHedefi = e[aramaSirasi]
        aramaAdimNo += 1
    }

    /// Eşleşme listesi: `localizedStandardContains` (büyük/küçük harf ve aksan duyarsız, yerel kurallı); boş sorguda boş.
    nonisolated static func aramaEslesmeleri(_ ogeler: [(id: UUID, metin: String)], sorgu: String) -> [UUID] {
        guard !sorgu.isEmpty else { return [] }
        return ogeler.filter { $0.metin.localizedStandardContains(sorgu) }.map(\.id)
    }

    /// Dairesel adım: sondan ileri başa, baştan geri sona döner; adet 0 iken 0.
    nonisolated static func aramaAdimi(_ sira: Int, adet: Int, ileri: Bool) -> Int {
        guard adet > 0 else { return 0 }
        return ((sira + (ileri ? 1 : -1)) % adet + adet) % adet
    }

    /// Sırayı geçerli aralığa çeker (eşleşme sayısı küçülünce dizi taşmasın).
    nonisolated static func aramaSinirla(_ sira: Int, adet: Int) -> Int {
        adet == 0 ? 0 : min(max(0, sira), adet - 1)
    }

    /// "↓" düğmesindeki "yeni" noktası: altta iken hep sönük; yukarıdayken içerik gelince yanar ve alta inene kadar kalır.
    nonisolated static func yeniNoktasi(onceki: Bool, alttaMi: Bool, icerikGeldi: Bool) -> Bool {
        alttaMi ? false : (onceki || icerikGeldi)
    }

    /// Sohbet değişiminde taslak geçişi: çıkılan sohbetin metni saklanır (boşsa anahtar silinir), girilenin taslağı döner.
    /// Yeni sohbet (nil) ilk mesajla ya da araç iletisiyle kayda dönüşünce (nil → taslağı olmayan kimlik) aynı sohbettir:
    /// yazılan metin kutuda kalır; yoksa o arada yazılan metin sessizce kaybolurdu.
    /// `yeniKayitTaze`: girilen sohbet az önce oluşturuldu mu; eski bir kayıt açılıyorsa nil → kimlik geçişi olağan sayılır.
    nonisolated static func taslakGecisi(_ t: [UUID?: String], eski: UUID?, yeni: UUID?, metin: String, yeniKayitTaze: Bool = true) -> (taslaklar: [UUID?: String], metin: String) {
        guard eski != yeni else { return (t, metin) }
        var d = t
        if eski == nil, let y = yeni, d[y] == nil, yeniKayitTaze {
            d[nil] = nil
            return (d, metin)
        }
        if metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { d[eski] = nil } else { d[eski] = metin }
        let geri = d[yeni] ?? ""
        d[yeni] = nil
        return (d, geri)
    }

    private func yeniIcerikGeldi() {
        let y = Self.yeniNoktasi(onceki: yeniVar, alttaMi: alttaMi, icerikGeldi: true)
        if y != yeniVar { yeniVar = y }
    }
    /// Yeni sohbet: tamamen boş; yalnız giriş çubuğu görünür.
    private var baslangic: some View { Color.clear.frame(maxHeight: .infinity).accessibilityHidden(true) }

    /// Live tam ekranı açıkken (ya da açılmak üzereyken) onay burada sunulmaz ve reddedilmez; Live ekranı kendi diyaloğunu gösterir.
    private var canliOnde: Bool { (canliGoster || canliHazirlaniyor) && ses.mod == .live }

    private var onayAcik: Binding<Bool> {
        Binding(get: { onay.bekleyen != nil && onay.bekleyen?.onizleme == nil && !canliOnde },
                set: { if !$0, onay.bekleyen != nil, onay.bekleyen?.onizleme == nil, !canliOnde { onay.yanitla(false) } })
    }

    /// P2.12: Önizlemesi olan bekleyen onay (imza sayfası). Kapanış yalnız ekrandaki isteği reddeder.
    private var onizlemeliOnay: Binding<OnayKapisi.Istek?> {
        Binding(get: { onay.bekleyen?.onizleme != nil && !canliOnde ? onay.bekleyen : nil },
                set: { if $0 == nil, let i = onay.bekleyen, i.onizleme != nil, !canliOnde { onay.yanitla(false, id: i.id) } })
    }

    /// `AsistanBaglantisi.coz` metni kırpıp 4000 karakterde keser; Kestirmenin beklediği görev de aynı biçimde karşılaştırılır
    /// (uzun görev eşleşmeyip sıraya girerse Kestirme "alamadı" dedikten sonra kendiliğinden çalışıyordu).
    nonisolated static func kestirmeyiBekliyor(beklenen: String?, metin: String) -> Bool {
        guard let b = beklenen else { return false }
        return String(b.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000)) == metin
    }

    /// Çok adımlı iş bittiğinde: "Bu işi beceri olarak kaydet" (deneyimden öğrenme).
    private func beceriOnerisiSatiri(_ id: UUID) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    let sonuc = await beyin.beceriOlarakKaydet(id, onay: onay)
                    TostDefteri.ortak.goster(sonuc, simge: "sparkles")
                }
            } label: {
                Label("Bu işi beceri olarak kaydet", systemImage: "sparkles.rectangle.stack")
                    .font(.footnote.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 36)
                    .temaDugmesi(Capsule())
            }
            .buttonStyle(.plain).accessibilityIdentifier("beceri-oner")
            Button { beyin.beceriOnerisi = nil } label: { Image(systemName: "xmark").font(.caption).frame(width: 36, height: 36) }
                .buttonStyle(.plain).accessibilityLabel("Öneriyi kapat")
        }
        .foregroundStyle(SohbetRenk.metin(sema == .dark))
        .padding(.horizontal, 16)
    }

    private var mesajListesi: some View {
        ScrollViewReader { sv in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ayarlar.gorunum.sik ? 2 : 6) {
                    // Arama listeyi süzmez: bütün mesajlar görünür, seçili eşleşme vurgulanıp ortalanır.
                    let gorunen = beyin.mesajlar
                    // Eylem satırı yalnız son asistan yanıtında ve yeni yanıt akmıyorken.
                    let sonYanitID = beyin.durum == .bosta && beyin.akanMetin.isEmpty ? gorunen.last(where: { $0.rol == .asistan })?.id : nil
                    // P3.9: eski sohbet 60'ar mesajlık sayfalarla açılır; yükleme sonrası okunan yer korunur (eski ilk mesaja
                    // ScrollViewReader ile üstten kaydırılır; kenar API'si kullanılmaz: yerleşim döngüsü tuzağı).
                    if beyin.dahaEskiVar {
                        Button {
                            let onceki = beyin.mesajlar.first?.id
                            guard beyin.dahaEskiYukle() > 0, let onceki else { return }
                            sv.scrollTo(onceki, anchor: .top)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
                                sv.scrollTo(onceki, anchor: .top)
                            }
                        } label: {
                            Label("Daha eski mesajlar", systemImage: "arrow.up.circle").font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                        .accessibilityIdentifier("daha-eski")
                    }
                    ForEach(Array(gorunen.enumerated()), id: \.element.id) { i, m in
                        if SohbetTemaDeposu.ortak.tema.tarihRozeti, i == 0 || !Calendar.current.isDate(m.zaman, inSameDayAs: gorunen[i - 1].zaman) { TarihRozeti(tarih: m.zaman) }
                        MesajBalonu(rol: m.rol, metin: m.metin, sure: m.sure, model: m.model, caba: m.caba, resimler: m.resimler, gorselAdlari: m.gorselAdlari, mesajID: m.id, zaman: m.zaman, kontrol: m.kontrol, ekler: m.ekler, vurgulu: !sorgu.isEmpty && aramaHedefi == m.id, sonYanit: m.id == sonYanitID, iz: m.iz).id(m.id)
                        if beyin.beceriOnerisi == m.id { beceriOnerisiSatiri(m.id) }
                    }
                    if ses.gercekZamanliEtkin {
                        let m = ses.openaiLive.etkin ? ses.openaiLive as any GercekZamanliMotor : ses.gercekLive
                        if !m.kullaniciMetni.isEmpty { MesajBalonu(rol: .kullanici, metin: m.kullaniciMetni) }
                        if !m.yanitMetni.isEmpty { MesajBalonu(rol: .asistan, metin: m.yanitMetni) }
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.mic").symbolEffect(.variableColor.iterative, isActive: !azHareket)
                            Text(ses.canliDurum)
                        }.font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    if !sorgu.isEmpty, !beyin.mesajlar.contains(where: { $0.metin.localizedStandardContains(sorgu) }) {
                        ContentUnavailableView.search(text: sorgu)
                    }
                    if beyin.durum == .dusunuyor {
                        HStack(spacing: 6) { ProgressView(); SureEtiketi(baslangic: beyin.istekBaslangic) }
                            .font(.footnote).padding(.horizontal).id("dusunuyor")
                    } else if !beyin.akanMetin.isEmpty {
                        MesajBalonu(rol: .asistan, metin: beyin.akanMetin, canliBaslangic: beyin.istekBaslangic, model: beyin.aktifModel.map(Beyin.modelEtiketi), caba: beyin.uygulananCaba?.ad).id("akan")
                    }
                    // Plan panosu ve çalışan adım: sohbetin sonunda, son mesajın altında (üst çubuğun arkasına girmez).
                    if !PlanDefteri.ortak.maddeler.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plan · \(PlanDefteri.ortak.maddeler.filter { $0.durum == .bitti }.count)/\(PlanDefteri.ortak.maddeler.count) tamam").font(.caption.weight(.semibold))
                            ForEach(PlanDefteri.ortak.maddeler) { m in
                                HStack(alignment: .top, spacing: 6) { Text(m.durum.simge); Text(m.metin).strikethrough(m.durum == .bitti) }.font(.caption)
                            }
                        }
                        .foregroundStyle(SohbetRenk.ikincil(sema == .dark)).fontDesign(.default)
                        .padding(.horizontal, 16).padding(.top, 4).accessibilityIdentifier("plan-panosu")
                    }
                    if beyin.durum != .bosta, let adim = beyin.gorevler.adimlar.last(where: { $0.durum == "Çalışıyor" }) {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(GorevGunlugu.eylemCumlesi(adim.ad)).font(.footnote).foregroundStyle(SohbetRenk.ikincil(sema == .dark)) }
                            .padding(.horizontal, 16).padding(.top, 2).id("islem")
                            .accessibilityIdentifier("islem-satiri")
                    }
                    // Alt uç işareti: uzun (tablo/kartlı) yanıtlarda bile kaydırma buraya yapılır.
                    Color.clear.frame(height: 1).id(Self.altUc)
                }
                .padding(.vertical, 14)
            }
            .contentMargins(.top, 56, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            // Alt uç takibi: yalnız kullanıcının kendi kaydırması "alttan ayrıldı" sayılır; içerik büyümesi ya da yerleşim sıçraması takibi bozmaz.
            .onScrollPhaseChange { _, faz in kullaniciKaydiriyor = faz == .interacting || faz == .decelerating }
            .onScrollGeometryChange(for: Bool.self) { g in
                Self.alttaYakin(gorunurAlt: g.visibleRect.maxY, icerikBoyu: g.contentSize.height)
            } action: { _, altta in
                // Arama gezinmesi (programlı kaydırma) alttan ayırınca da takip bırakılır; yoksa "↓" görünmez, arama kapanınca akış zorla aşağı çekerdi.
                alttaMi = Self.takipDurumu(onceki: alttaMi, altta: altta, kullaniciKaydiriyor: kullaniciKaydiriyor || !sorgu.isEmpty)
            }
            // Akış: parça başına animasyonsuz ve yalnız kullanıcı alttayken (yukarıyı okurken aşağı çekilmez).
            // Parmak listedeyken (sürükleme/yavaşlama) akış kaydırmaz: alttaki 80 pt bandında her parça görünümü alta geri itiyordu.
            .onChange(of: beyin.akanMetin) { _, _ in yeniIcerikGeldi(); guard sorgu.isEmpty, alttaMi, !kullaniciKaydiriyor else { return }; sv.scrollTo(Self.altUc, anchor: .bottom) }
            .onChange(of: beyin.gorevler.adimlar.count) { _, _ in guard sorgu.isEmpty, alttaMi, !kullaniciKaydiriyor, beyin.durum != .bosta else { return }; withAnimation { sv.scrollTo(Self.altUc, anchor: .bottom) } }
            // Son mesaj değişince (P3.9: başa eklenen eski sayfa yeni içerik sayılmaz, alta çekmez).
            .onChange(of: beyin.mesajlar.last?.id) { _, _ in yeniIcerikGeldi(); if alttaMi, !kullaniciKaydiriyor { asagiKaydir(sv) } }
            // Yeni istek (gönderildi) ve sohbet değişimi: her zaman en alta.
            .onChange(of: beyin.durum) { eski, yeni in if eski == .bosta, yeni != .bosta { alttaMi = true; asagiKaydir(sv) } }
            .onChange(of: beyin.sohbet?.kimlik) { _, _ in alttaMi = true; yeniVar = false; eslesmeleriYenile(); asagiKaydir(sv) }
            .onChange(of: alttaMi) { _, a in if a { yeniVar = false } }
            // Sohbet içi arama: sorgu en yeni eşleşmeye kurar; sayı değişirse sıra sınırlanır; kaydırma artan adım sayacıyla.
            // P3.9: arama bütün sohbette yapılır; sayfalı açılışta kalan eski mesajlar önce yüklenir.
            // Eşleşmeler yüklü mesajlarda hemen bulunur; kalan eski mesajlar yazma durunca (350 ms) tek seferde yüklenir.
            .onChange(of: sorgu) { _, yeni in
                aramaYuklemesi?.cancel()
                eslesmeleriYenile()
                aramaSorgusuDegisti()
                guard !yeni.isEmpty, beyin.dahaEskiVar else { return }
                aramaYuklemesi = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, !sorgu.isEmpty, beyin.dahaEskiVar else { return }
                    beyin.dahaEskiYukle(hepsi: true)
                    eslesmeleriYenile()
                    if let h = aramaHedefi, let i = eslesmeListesi.firstIndex(of: h) { aramaSirasi = i }
                }
            }
            .onChange(of: beyin.mesajlar.count) { _, _ in if !sorgu.isEmpty { eslesmeleriYenile() } }
            .onChange(of: beyin.durum) { _, yeni in if yeni == .bosta, !sorgu.isEmpty { eslesmeleriYenile() } }
            .onChange(of: eslesmeler.count) { _, adet in
                aramaSirasi = Self.aramaSinirla(aramaSirasi, adet: adet)
                if let h = aramaHedefi, !eslesmeler.contains(h) { aramaHedefi = adet == 0 ? nil : eslesmeler[aramaSirasi] }
            }
            .onChange(of: aramaAdimNo) { _, _ in
                guard let id = aramaHedefi else { return }
                withAnimation { sv.scrollTo(id, anchor: .center) }
                Task { @MainActor in
                    // LazyVStack tahmini yükseklik yüzünden ilk kaydırma şaşabilir: yerleşimden sonra bir kez daha (asagiKaydir deseni).
                    try? await Task.sleep(for: .milliseconds(150))
                    guard aramaHedefi == id else { return }
                    withAnimation { sv.scrollTo(id, anchor: .center) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    if !alttaMi {
                        Button {
                            alttaMi = true
                            // Arama açıkken `asagiKaydir` kaydırmaz (otomatik takip kapalı); düğme yine de kullanıcıyı alta götürür.
                            if sorgu.isEmpty { asagiKaydir(sv) } else { withAnimation { sv.scrollTo(Self.altUc, anchor: .bottom) } }
                        } label: {
                            Image(systemName: "arrow.down").font(.system(size: 17 * k, weight: .semibold)).foregroundStyle(SohbetRenk.metin(sema == .dark))
                                .frame(width: 44, height: 44).temaDugmesi(Circle())
                                .overlay(alignment: .topTrailing) {
                                    if yeniVar {
                                        Circle().fill(ayarlar.gorunum.vurgu).frame(width: 10, height: 10)
                                            .accessibilityIdentifier("yeni-icerik-noktasi")
                                    }
                                }
                        }
                        .buttonStyle(.plain).padding(.trailing, 16).padding(.bottom, 10)
                        .accessibilityLabel(yeniVar ? "En alta git, yeni yanıt var" : "En alta git").accessibilityIdentifier("en-alta-git")
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: alttaMi)
            }
        }
    }

    /// Görünür alanın alt kenarı içeriğin sonuna `pay` kadar yakınsa "altta" sayılır (içerik kısaysa da altta).
    nonisolated static func alttaYakin(gorunurAlt: CGFloat, icerikBoyu: CGFloat, pay: CGFloat = 80) -> Bool {
        gorunurAlt >= icerikBoyu - pay
    }

    /// Takip kararı: alta dönen her zaman takibe girer; alttan ayrılma yalnız kullanıcı kaydırırken takibi bırakır.
    nonisolated static func takipDurumu(onceki: Bool, altta: Bool, kullaniciKaydiriyor: Bool) -> Bool {
        if altta { return true }
        return kullaniciKaydiriyor ? false : onceki
    }

    private static let altUc = "sohbet-alt-uc"
    /// LazyVStack ölçülmemiş uzun satırın yüksekliğini tahmin ettiği için tek `scrollTo` yanlış yere iner
    /// (kartlı uzun yanıttan sonra görünüm yukarı sıçrıyor, yeni mesaj görünmüyordu). Yerleşim bitince ikinci kez kaydırılır.
    private func asagiKaydir(_ sv: ScrollViewProxy) {
        guard sorgu.isEmpty else { return }
        withAnimation { sv.scrollTo(Self.altUc, anchor: .bottom) }
        Task { @MainActor in
            // Uzun kartlar yerleşince içerik boyu değişir: yerleşimden sonra bir kez daha kenara git.
            try? await Task.sleep(for: .milliseconds(180))
            guard sorgu.isEmpty, alttaMi, !kullaniciKaydiriyor else { return }
            withAnimation { sv.scrollTo(Self.altUc, anchor: .bottom) }
        }
    }

    private var cekmeceKatmani: some View {
        GeometryReader { geo in
            let genislik = min(geo.size.width * 0.75, 320)   // sağda sohbetten belirgin bir şerit görünsün
            ZStack(alignment: .leading) {
                if cekmeceAcik {
                    Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { withAnimation(.easeOut(duration: 0.25)) { cekmeceAcik = false } }
                        .accessibilityLabel("Menüyü kapat").accessibilityIdentifier("cekmece-perde")
                }
                if cekmeceAcik {
                    CekmeceGorunumu(acik: $cekmeceAcik, eylem: cekmeceEylemi)
                        .frame(width: genislik).frame(maxHeight: .infinity)
                        .shadow(color: .black.opacity(0.18), radius: 12)
                        .transition(.move(edge: .leading))
                        .gesture(DragGesture(minimumDistance: 20).onEnded { v in if v.translation.width < -60 { withAnimation(.easeOut(duration: 0.25)) { cekmeceAcik = false } } })
                }
            }
            .animation(.easeOut(duration: 0.25), value: cekmeceAcik)
            .allowsHitTesting(cekmeceAcik)
        }
    }

    private var sohbetVar: Bool { !beyin.mesajlar.isEmpty || !beyin.akanMetin.isEmpty }

    private var durumYazisi: String {
        if beyin.durum == .dusunuyor { return "düşünüyor…" }
        if beyin.durum != .bosta { return "yazıyor…" }
        return AgIzleyici.ortak.cevrimici ? "çevrimiçi" : "bağlantı bekleniyor…"
    }

    /// Üst çubuk (temaya göre): menü dairesi, isteğe bağlı başlık hapı, arama + diğer hapı.
    private var ustCubuk: some View {
        let koyu = sema == .dark
        let renk = SohbetRenk.metin(koyu)
        let tema = SohbetTemaDeposu.ortak.tema
        return HStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.25)) { cekmeceAcik = true } } label: {
                Image(systemName: tema.menu == .geri ? "chevron.left" : "line.3.horizontal.decrease").font(.system(size: 20 * k, weight: .semibold)).foregroundStyle(renk)
                    .frame(width: 46, height: 46).temaDugmesi(Circle())
            }.accessibilityLabel("Menü").accessibilityIdentifier("menu-dugmesi")
            if tema.baslik {
                VStack(spacing: 1) {
                    Text(ayarlar.gorunenAd).font(.system(size: 19 * k, weight: .bold)).foregroundStyle(renk).lineLimit(1)
                    Text(durumYazisi).font(.system(size: 14 * k)).foregroundStyle(SohbetRenk.ikincil(koyu)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 46).padding(.horizontal, 12).temaDugmesi(Capsule())
                .accessibilityElement(children: .combine).accessibilityIdentifier("baslik-hapi")
            } else {
                Spacer()
            }
            HStack(spacing: 0) {
                Button { sohbetAra.toggle(); if !sohbetAra { sorgu = "" } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 20 * k)).foregroundStyle(renk).frame(width: 44, height: 46)
                }.accessibilityLabel("Ara").accessibilityIdentifier("sohbet-ara-dugmesi")
                Menu {
                    Button { sorgu = ""; beyin.yeniSohbet() } label: { Label("Yeni sohbet", systemImage: "square.and.pencil") }
                    if sohbetVar {
                        Button { sohbetAra.toggle(); if !sohbetAra { sorgu = "" } } label: { Label("Sohbette ara", systemImage: "magnifyingglass") }
                        ShareLink(item: sohbetMetni) { Label("Sohbeti paylaş", systemImage: "square.and.arrow.up") }
                    }
                    Button { Task { await ses.canliModuAc() } } label: { Label("Live sesli diyalog", systemImage: "waveform") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20 * k, weight: .semibold)).foregroundStyle(renk).frame(width: 44, height: 46)
                }.accessibilityLabel("Sohbet menüsü").accessibilityIdentifier("sohbet-menusu")
            }
            .temaDugmesi(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
        .background(alignment: .top) {
            // Desensiz (düz) temalarda üst çubuğun arkası zemin rengiyle örtülür; kayan yazı altından görünmez.
            if !tema.palet(koyu).desen {
                Color(hex: tema.palet(koyu).zemin).ignoresSafeArea(edges: .top)
                    .overlay(alignment: .bottom) { Rectangle().fill(SohbetRenk.ikincil(koyu).opacity(0.25)).frame(height: 0.5) }
            }
        }
    }

    /// Çekmeceden gelen eylemleri mevcut ekran bayraklarına eşler.
    private func cekmeceEylemi(_ e: CekmeceEylemi) {
        switch e {
        case .yeni: sorgu = ""; beyin.yeniSohbet()
        case .herYerdeAra: herYerdeAcik = true
        case .ayarlar: ayarlarAcik = true
        case .kullanim: kullanimAcik = true
        case .gelenKutusu: GelenKutusu.ortak.ekranAcik = true
        case .atolye: atolyeAcik = true
        case .indirmeler: IndirmeYoneticisi.ortak.ekranAcik = true
        case .donustur: donusturmeAcik = true
        case .arsiv: ArsivMerkezi.ortak.ekranAcik = true
        case .uretkenlik: uretkenlikAcik = true
        case .telefon: telefonAcik = true
        case .gorunum: gorunumAcik = true
        case .kisisel: kisiselAcik = true
        case .ajan: ajanAcik = true
        case .tetikleyiciler: tetikAcik = true
        case .projeler: projelerAcik = true
        }
    }

    /// Live tetiklenince açık sayfaları kapatır: tam ekran Live başka bir sunumun üstüne açılamıyor, mikrofon görünmez açık kalıyordu.
    /// Açık bir sunum varsa true döner (Live, kapanma animasyonu bitince sunulur).
    @discardableResult
    private func sunumlariKapat() -> Bool {
        // Mesaj satırlarının kendi açtığı sunumlar (büyük fotoğraf, galeri, Safari, QuickLook, tablo) bu ekranın bayraklarında görünmez: yayınla kapanırlar.
        NotificationCenter.default.post(name: .asistanSunumlariKapat, object: nil)
        let yerel = [herYerdeAcik, kullanimAcik, gorunumAcik, kisiselAcik, ayarlarAcik, ajanAcik, tetikAcik, projelerAcik, telefonAcik, atolyeAcik, dosyaKasasiAcik,
                     gecmisAcik, donusturmeAcik, uretkenlikAcik, kameraAcik, barkodKameraAcik, taramaAcik, ekSayfasiAcik, fotoSecAcik, belgeSec,
                     yenidenDenemeOnayi != nil]
        let ortak = [TarayiciOturumu.ortak.gorunur, DosyaKitapligi.ortak.ekranAcik, UygulamaKatalogu.ortak.ekranAcik,
                     IndirmeYoneticisi.ortak.ekranAcik, ArsivMerkezi.ortak.ekranAcik, GelenKutusu.ortak.ekranAcik]
        let acikVardi = yerel.contains(true) || ortak.contains(true) || otomatikGorsel != nil || duzenlenen != nil || MesajTaslagi.ortak.istek != nil
        guard acikVardi else { cekmeceAcik = false; return false }
        bekleyenEk = nil   // ek sayfası kapanınca yeni bir sunum açılmasın
        kullanimAcik = false; gorunumAcik = false; kisiselAcik = false; ayarlarAcik = false; ajanAcik = false; tetikAcik = false
        projelerAcik = false; herYerdeAcik = false; telefonAcik = false; atolyeAcik = false; gecmisAcik = false; donusturmeAcik = false; uretkenlikAcik = false
        dosyaKasasiAcik = false
        kameraAcik = false; barkodKameraAcik = false; taramaAcik = false; ekSayfasiAcik = false; fotoSecAcik = false; belgeSec = false
        otomatikGorsel = nil; duzenlenen = nil; cekmeceAcik = false; yenidenDenemeOnayi = nil
        if TarayiciOturumu.ortak.gorunur { TarayiciOturumu.ortak.gorunur = false }
        if DosyaKitapligi.ortak.ekranAcik { DosyaKitapligi.ortak.ekranAcik = false }
        if UygulamaKatalogu.ortak.ekranAcik { UygulamaKatalogu.ortak.ekranAcik = false }
        if IndirmeYoneticisi.ortak.ekranAcik { IndirmeYoneticisi.ortak.ekranAcik = false }
        if ArsivMerkezi.ortak.ekranAcik { ArsivMerkezi.ortak.ekranAcik = false }
        if GelenKutusu.ortak.ekranAcik { GelenKutusu.ortak.ekranAcik = false }
        if let istek = MesajTaslagi.ortak.istek { MesajTaslagi.ortak.bitir(id: istek.id, sonuc: "Live başladığı için mesaj taslağı kapatıldı; mesaj gönderilmedi.") }
        return true
    }

    /// Kök denetleyicinin üstünde hâlâ bir sunum (sayfa, diyalog, tam ekran) var mı; bayrağı bu ekranda olmayanlar dahil.
    private static func ustteSunumVar() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.presentedViewController != nil
    }

    // MARK: P2.3 durum şeridi

    /// O anki durumların seçimi. Çevrimdışı ve bekleyen mesajlar kendi listeli şeridinde (`BekleyenlerSeridi`: tek tek iptal/gönder)
    /// kaldığı için burada aday yapılmaz; iki şerit aynı iletiyi yinelemesin.
    private var durumSecimi: (DurumBildirimi?, ek: Int) {
        var mikrofonHatasi: String?
        if case .hata(let h) = ses.dinleyici.durum { mikrofonHatasi = h }
        let a = DurumSecici.adaylar(sonHata: beyin.sonHata, hataTuru: beyin.sonHataTuru, cevrimici: true, cevrimdisiNotu: nil, bekleyenSayisi: 0,
                                    kota: beyin.kotaUyarisi, sesHatasi: ses.konusmaci.sesHatasi, kisiselHata: alan.hata,
                                    mikrofonHatasi: mikrofonHatasi, mikrofonIzniYok: mikrofonHatasi != nil && DurumSeridi.mikrofonIzniYok())
        return DurumSecici.sec(a, kapatilanlar: kapatilanDurumlar)
    }

    @ViewBuilder
    private var durumSeridiKatmani: some View {
        let secim = durumSecimi
        if let b = secim.0 {
            DurumSeridi(bildirim: b, ek: secim.ek, eylem: durumEylemi, baskaModel: { m in yenidenDeneIste(model: m) }, kapat: { durumKapat(b) })
        }
    }

    private func durumKapat(_ b: DurumBildirimi) {
        if b.tur == .modelHatasi {
            beyin.sonHata = nil
            beyin.sonHataTuru = nil
        } else {
            kapatilanDurumlar.insert(b.id)
        }
    }

    private func durumEylemi(_ e: DurumBildirimi.Eylem) {
        switch e {
        case .yenidenDene: yenidenDeneIste(model: nil)
        case .baskaModel: break   // Menü seçimi `baskaModel` kapanışından gelir.
        case .baglantiyiSina:
            Task {
                await TelefonProxy.ortak.sina()
                TostDefteri.ortak.goster(TelefonProxy.ortak.sonSinama ?? TelefonProxy.ortak.durum, simge: "network")
            }
        case .bekleyenleriIptal: beyin.bekleyenleriIptal()
        case .mikrofonuYenidenBaslat: Task { await ses.yuvarlagaDokun() }
        case .ayarlariAc: IzinDenetcisi.ayarlariAc()
        }
    }

    /// Yan etkili araç başlamış turda önce onay sorulur; değilse hemen yeniden gönderilir.
    private func yenidenDeneIste(model: String?) {
        if beyin.sonTurYanEtkili {
            yenidenDenemeOnayi = YenidenDenemeIstegi(model: model)
        } else {
            beyin.yenidenDene(model: model)
        }
    }

    @ViewBuilder
    private var dinlemeSeridi: some View {
        switch ses.dinleyici.durum {
        case .dinliyor:
            if !ses.uyandirmaBekliyor {
            HStack {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: !azHareket)
                Text(ses.dinleyici.sonReddedilen ?? (ses.dinleyici.canliMetin.isEmpty ? "Dinliyorum…" : ses.dinleyici.canliMetin)).lineLimit(2)
                Spacer()
                Image(systemName: ses.dinleyici.girisDb > -65 ? "waveform.circle.fill" : "waveform.circle")
                    .foregroundStyle(ses.dinleyici.girisDb > -65 ? .green : .secondary)
                    .accessibilityLabel(ses.dinleyici.girisDb > -65 ? "Ses alınıyor" : "Ses bekleniyor")
            }
            .font(.callout).padding(.horizontal).padding(.vertical, 6)
            .background(ayarlar.gorunum.vurgu.opacity(0.12))
            }
        case .hazirlaniyor:
            HStack { ProgressView(); Text("Ses modeli hazırlanıyor…") }.font(.callout).padding(6)
        case .cozumluyor:
            HStack { ProgressView(); Text("Whisper çözümlüyor…") }.font(.callout).padding(6)
        case .hata:
            EmptyView()   // P2.3: mikrofon hatası ve "Mikrofonu başlat" durum şeridinde
        case .kapali:
            EmptyView()
        }
    }

    private var girisCubugu: some View {
        VStack(spacing: 6) {
            if belgeOkunuyor { ProgressView("Belge okunuyor…").font(.footnote) }
            if hazirlanan > 0 {
                // Asılı kalan iCloud indirmesi gönderimi süresiz kilitlemesin: hazırlık bırakılabilir, bekleyen mesaj o an gider.
                HStack(spacing: 10) {
                    ProgressView(gonderimBekliyor ? "Fotoğraflar hazırlanınca gönderilecek…" : "Fotoğraflar hazırlanıyor…")
                    Button(gonderimBekliyor ? "Beklemeden gönder" : "Vazgeç") { fotoHazirliginiBirak() }
                        .accessibilityIdentifier("foto-vazgec")
                }.font(.footnote)
            }
            if let belgeHatasi { Text(belgeHatasi).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            if let belge {
                HStack {
                    Image(systemName: "doc.text")
                    VStack(alignment: .leading) {
                        Text(belge.ad).font(.caption.bold()).lineLimit(1)
                        if !belge.not.isEmpty { Text(belge.not).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { self.belge = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Belgeyi kaldır")
                }.padding(.horizontal)
            }
            if let p = ProjeDeposu.ortak.aktif {
                HStack(spacing: 6) {
                    Button { projelerAcik = true } label: { Label(p.ad, systemImage: "folder").lineLimit(1) }
                        .accessibilityLabel("Etkin proje: \(p.ad)").accessibilityIdentifier("proje-cipi")
                    Button { ProjeDeposu.ortak.aktifKimlik = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Projeyi kaldır")
                }
                .font(.footnote.weight(.medium)).foregroundStyle(SohbetRenk.ikincil(sema == .dark)).buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
            }
            if !ekler.isEmpty { EkSeridi(ekler: $ekler) { duzenlenen = $0 } }
            girisSatiri
        }
        .padding(.vertical, 4)
        .onChange(of: secilenFotolar) { _, yeni in
            guard !yeni.isEmpty else { return }
            // Seçim hemen bırakılır: seçici yeniden açılınca eski seçim işaretli gelip ikinci kez eklenmesin.
            secilenFotolar = []
            hazirla(.secici(yeni))
        }
        // Fotoğraflar hazırlanırken basılan Gönder: hazırlık bitince mesaj fotoğraflarıyla gider.
        .onChange(of: hazirlanan) { _, yeni in
            guard yeni == 0, gonderimBekliyor else { return }
            gonderimBekliyor = false
            gonder()
        }
        .photosPicker(isPresented: $fotoSecAcik, selection: $secilenFotolar, maxSelectionCount: max(1, kalanYer), selectionBehavior: .ordered, matching: .images)
        .fullScreenCover(isPresented: $kameraAcik) { KameraGorunumu { ekle([$0]) } .ignoresSafeArea() }
        .fullScreenCover(isPresented: $barkodKameraAcik) { KameraGorunumu { barkodOku($0) }.ignoresSafeArea() }
        .fullScreenCover(isPresented: $taramaAcik) { BelgeTarayici(sinir: kalanYer) { ekle($0, tur: .sayfa) }.ignoresSafeArea() }
        .fullScreenCover(item: $duzenlenen) { e in
            FotoDuzenleyici(resim: e.resim) { yeni in if let i = ekler.firstIndex(where: { $0.id == e.id }) { ekler[i].resim = yeni } }
        }
        .fullScreenCover(isPresented: Binding(get: { canliGoster && ses.mod == .live }, set: { if !$0 { canliGoster = false; if ses.mod == .live { Task { await ses.canliBitir() } } } })) {
            CanliEkrani()
        }
        // Live dışarıdan (Kestirme, asistan://live) bir sayfa açıkken gelirse önce sayfalar kapanır, sonra tam ekran sunulur.
        // Bekleyen onay diyaloğu da bir sunumdur: geçiş boyunca gizlenir (reddedilmez), kapanması beklenir.
        // Kapatılamayan bir sistem sayfası (ör. paylaşım) Live'ı süresiz bekletmez: en çok ~1,8 sn sonra yine sunulur.
        .onChange(of: ses.mod == .live, initial: true) { _, live in
            guard live else { canliGoster = false; canliHazirlaniyor = false; return }
            let onayVardi = onay.bekleyen != nil
            let kapatildi = sunumlariKapat()
            guard kapatildi || onayVardi || Self.ustteSunumVar() else { canliGoster = true; return }
            canliHazirlaniyor = true
            Task {
                for _ in 0..<6 {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard ses.mod == .live else { canliHazirlaniyor = false; return }
                    if !Self.ustteSunumVar() { break }
                }
                canliHazirlaniyor = false
                if ses.mod == .live { canliGoster = true }
            }
        }
        .sheet(isPresented: $ekSayfasiAcik, onDismiss: ekEyleminiCalistir) {
            EkSayfasi(kalanYer: kalanYer) { bekleyenEk = $0; ekSayfasiAcik = false }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    /// Hazırlanmakta olan görseller de yer tutar: arka plan işi sürerken gelen ek sınırı aşmasın.
    private var kalanYer: Int { Beyin.enFazlaGorsel - ekler.count - hazirlanan }

    /// Kamera ve belge tarayıcıdan gelen hazır görseller.
    private func ekle(_ resimler: [UIImage], tur: GorselEk.Tur = .foto) {
        guard !resimler.isEmpty else { return }
        hazirla(.hazir(resimler), tur: tur)
    }

    /// Bir ek seçiminin kaynağı: yükleme, hazırlık zincirinin içinde yapılır (sıra seçim anında alınır).
    private enum FotoKaynagi {
        case secici([PhotosPickerItem])
        case son([String])
        case hazir([UIImage])
        var adet: Int {
            switch self {
            case .secici(let o): o.count
            case .son(let k): k.count
            case .hazir(let r): r.count
            }
        }
    }

    /// Görseller eklenirken 2048 px'e indirilir: tam boy bitmap'ler (48 MP, çok sayfalı tarama) bellekte birikmesin.
    /// Çizim (HEIC çözümü dahil) arka planda yapılır; ana iş parçacığında 8 fotoğraf ekranı donduruyordu.
    /// Yükleme ve küçültme paralel sürer; şeride ekleme seçim sırasıyla yapılır (sonra seçilen küçük görsel öne geçip sayfa sırasını bozuyordu).
    private func hazirla(_ kaynak: FotoKaynagi, tur: GorselEk.Tur = .foto) {
        let adet = kaynak.adet
        guard adet > 0 else { return }
        let nesil = fotoNesli
        let onceki = ekZinciri
        hazirlanan += adet
        ekZinciri = Task {
            var resimler: [UIImage] = []
            switch kaynak {
            case .secici(let ogeler):
                for oge in ogeler { if let veri = try? await oge.loadTransferable(type: Data.self), let img = UIImage(data: veri) { resimler.append(img) } }
            case .son(let kimlikler):
                resimler = await SonFotograflar.tamBoy(kimlikler)
            case .hazir(let r):
                resimler = r
            }
            let ham = resimler
            var kucuk: [UIImage] = []
            if !ham.isEmpty {
                kucuk = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                    ham.map { r in r.kucultulmus(2048).map { UIImage(cgImage: $0) } ?? r }
                }.value
            }
            await onceki?.value   // önceki seçim şeride girmeden bu grup girmesin
            guard nesil == fotoNesli else { return }   // "Vazgeç" basıldı: sonucu at, sayaca dokunma
            hazirlanan -= adet
            let yer = max(0, kalanYer)
            let sinirNotu = kucuk.count > yer ? "Bir mesaja en fazla \(Beyin.enFazlaGorsel) görsel eklenir; fazlası eklenmedi." : nil
            ekler += kucuk.prefix(yer).map { GorselEk(resim: $0, tur: tur) }
            belgeHatasi = Self.eksikFotoNotu(adet - ham.count, onceki: sinirNotu)
        }
    }

    /// Asılı kalan hazırlığı bırakır: geç gelen sonuç atılır; Gönder beklemedeyse mesaj hazır eklerle hemen gider.
    private func fotoHazirliginiBirak() {
        fotoNesli += 1
        ekZinciri = nil
        secilenFotolar = []
        hazirlanan = 0   // onChange(hazirlanan) bekleyen gönderimi çalıştırır
    }

    /// İndirilemeyen (iCloud/bağlantı) ya da okunamayan fotoğraf sessizce düşmesin; önceki uyarı korunur.
    nonisolated static func eksikFotoNotu(_ eksik: Int, onceki: String?) -> String? {
        guard eksik > 0 else { return onceki }
        let not = "\(eksik) fotoğraf eklenemedi (iCloud'dan indirilemedi ya da okunamadı)."
        return onceki.map { not + " " + $0 } ?? not
    }

    /// Ek sayfası kapandıktan sonra seçilen işi açar (iki sunum üst üste binmesin).
    private func ekEyleminiCalistir() {
        guard let e = bekleyenEk else { return }
        bekleyenEk = nil
        odak = false
        switch e {
        case .kamera: kameraAcik = true
        case .barkod: barkodKameraAcik = true
        case .fotoSec: fotoSecAcik = true
        case .belgeTara: taramaAcik = true
        case .dosya: belgeSec = true
        case .baglanti: IndirmeYoneticisi.ortak.ekranAcik = true
        case .dosyalarim: DosyaKitapligi.ortak.ekranAcik = true
        case .donustur: donusturmeAcik = true
        case .arsiv: ArsivMerkezi.ortak.ekranAcik = true
        case .atolye: atolyeAcik = true
        case .dosyaKasasi: dosyaKasasiAcik = true
        case .sonFotolar(let kimlikler):
            guard !kimlikler.isEmpty else { return }   // "Kapat": boş seçim önceki uyarıyı silmesin
            hazirla(.son(kimlikler))
        }
    }

    private func barkodOku(_ resim: UIImage) {
        Task {
            if let kod = await BarkodOkuyucu.kod(resim) {
                metin = "\(kod) barkodlu ürünü incele; besin değeri, içerik ve alerjenlerini söyle."
                odak = true
            } else {
                belgeHatasi = "Barkod okunamadı. Barkodu düz, aydınlık ve kadrajı dolduracak biçimde yeniden çek."
            }
        }
    }

    /// Giriş: tema "tek kutu" ise Claude stili (yazı alanı üstte, düğmeler altta tek kutuda), değilse ayrık daireler.
    @ViewBuilder private var girisSatiri: some View {
        if SohbetTemaDeposu.ortak.tema.giris == .tekKutu { tekKutuGiris } else { ayrikGiris }
    }

    /// Hazırlanan fotoğraf da giriş sayılır: mikrofon değil Gönder görünür (sesli tur fotoğrafsız gidip ek sonraki mesaja kalıyordu).
    private var girisBos: Bool { metin.trimmingCharacters(in: .whitespaces).isEmpty && ekler.isEmpty && belge == nil && hazirlanan == 0 }
    private var mesguller: Bool { ses.sesliKip || ses.uyandirmaBekliyor || ses.konusmaci.konusuyor || beyin.durum != .bosta }

    private func mesajAlani(_ yer: String) -> some View {
        let koyu = sema == .dark
        return TextField(yer, text: $metin, prompt: Text(yer).foregroundColor(SohbetRenk.ikincil(koyu)), axis: .vertical)
            .accessibilityIdentifier("mesaj-girisi")
            // SwiftUI çok satırlı TextField bazı iOS sürümlerinde güncel içeriği erişilebilirlik ağacına geç iletebiliyor.
            .accessibilityValue(metin)
            .lineLimit(1...6).font(.system(size: 19 * k)).foregroundStyle(SohbetRenk.kullaniciMetni(koyu)).focused($odak).onSubmit(gonder)
    }

    private func sesDugmesi(_ boyut: CGFloat, dolgu: Bool) -> some View {
        let koyu = sema == .dark
        let dinliyor = ses.dinleyici.durum == .dinliyor && !ses.uyandirmaBekliyor
        return Button {
            odak = false
            Task { await ses.yuvarlagaDokun() }
        } label: {
            Image(systemName: dinliyor ? "waveform" : "mic").font(.system(size: 21 * k))
                .symbolEffect(.variableColor.iterative, isActive: (dinliyor || ses.gercekZamanliEtkin) && !azHareket)
                .foregroundStyle(dinliyor || ses.sesliKip || ses.gercekZamanliEtkin ? ayarlar.gorunum.vurgu : SohbetRenk.metin(koyu))
                .frame(width: boyut, height: boyut)
                .background { if dolgu { Circle().fill(SohbetRenk.gidenBalon(koyu)) } }
        }
        .disabled(ses.gecisVar)
        .accessibilityLabel(dinliyor ? "Konuşmayı gönder" : "Konuşmaya başla")
        .accessibilityIdentifier("ses-yuvarlagi")
    }

    private func gonderDugmesi(_ boyut: CGFloat) -> some View {
        Button(action: gonder) {
            Image(systemName: "arrow.up").font(.system(size: 20 * k, weight: .bold)).foregroundStyle(.white)
                .frame(width: boyut, height: boyut).background(ayarlar.gorunum.vurgu, in: Circle())
        }
        // Fotoğraflar hazırlanırken basılabilir: gönderim hazırlık bitene kadar bekler (fotoğrafsız gitmez).
        .disabled(beyin.durum != .bosta || belgeOkunuyor || gonderiliyor || gonderimBekliyor).accessibilityLabel("Gönder")
    }

    private func durdurDugmesi(_ boyut: CGFloat, kare: Bool) -> some View {
        let koyu = sema == .dark
        return Button {
            odak = false
            Task { await ses.sesliKipiKapat(); beyin.iptal() }
        } label: {
            Image(systemName: kare ? "stop.fill" : "xmark").font(.system(size: (kare ? 17 : 20) * k, weight: .semibold))
                .foregroundStyle(kare ? SohbetRenk.metin(koyu) : .white)
                .frame(width: boyut, height: boyut)
                .background(kare ? SohbetRenk.gidenBalon(koyu) : Color.black.opacity(0.85), in: Circle())
        }.accessibilityLabel("Sesli oturumu ve yanıtı durdur")
    }

    /// Kısa model adı: "Opus 5.5", otomatikte "Otomatik".
    private var modelHapiAdi: String {
        let ad = ayarlar.otomatikModel ? "Otomatik" : TelefonProxy.Model.kisaAd(ayarlar.modelKimligi)
        // P3.7: VPS/internet halkası yoksa kısa ek (erişilebilirlik etiketi de bunu okur).
        if let ek = BaglantiDurumu.hapEki(BaglantiDurumu.ortak.haller) { return "\(ad) · \(ek)" }
        return ad
    }

    /// Vekildeki bütün sohbet modelleri aileye göre; liste henüz gelmediyse bilinen Claude modelleri.
    private var modelAileleri: [(String, [TelefonProxy.Model])] {
        var liste = TelefonProxy.ortak.modeller.filter(\.sohbet)
        if liste.isEmpty { liste = ModelSecimi.allCases.map { .init(id: $0.rawValue) } }
        let sira = ["Claude", "ChatGPT / Codex", "Gemini", "Grok", "Diğer"]
        return sira.compactMap { aile in
            let m = liste.filter { $0.aile == aile }.sorted { $0.kisaAd < $1.kisaAd }
            return m.isEmpty ? nil : (aile, m)
        }
    }

    private var modelHapi: some View {
        let koyu = sema == .dark
        return Menu {
            Button { ayarlar.otomatikModel = true } label: { Label("Otomatik (işe göre)", systemImage: ayarlar.otomatikModel ? "checkmark" : "sparkles") }
            ForEach(modelAileleri, id: \.0) { aile, modeller in
                Menu(aile) {
                    ForEach(modeller) { m in
                        Button { ayarlar.modelKimligi = m.id; ayarlar.otomatikModel = false } label: {
                            if !ayarlar.otomatikModel, ayarlar.modelKimligi == m.id { Label(m.kisaAd, systemImage: "checkmark") } else { Text(m.kisaAd) }
                        }
                    }
                }
            }
        } label: {
            Text(modelHapiAdi).font(.system(size: 16 * k, weight: .medium)).foregroundStyle(SohbetRenk.metin(koyu)).lineLimit(1)
                .padding(.horizontal, 16).frame(height: 44).background(SohbetRenk.gidenBalon(koyu), in: Capsule())
        }
        .accessibilityLabel("Model: \(modelHapiAdi)").accessibilityIdentifier("model-hapi")
    }

    private var tekKutuGiris: some View {
        let koyu = sema == .dark
        return VStack(alignment: .leading, spacing: 10) {
            mesajAlani("Asistan'a yaz…").padding(.horizontal, 6).padding(.top, 4)
            HStack(spacing: 10) {
                Button { odak = false; ekSayfasiAcik = true } label: {
                    Image(systemName: "plus").font(.system(size: 21 * k)).foregroundStyle(SohbetRenk.metin(koyu))
                        .frame(width: 44, height: 44).background(SohbetRenk.gidenBalon(koyu), in: Circle())
                }
                .accessibilityLabel("Dosya veya fotoğraf ekle")
                modelHapi
                Spacer(minLength: 4)
                if girisBos { sesDugmesi(44, dolgu: true) } else { gonderDugmesi(44) }
                if mesguller { durdurDugmesi(44, kare: true) }
            }
        }
        .padding(12)
        .temaDugmesi(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 2)
    }

    private var ayrikGiris: some View {
        let koyu = sema == .dark
        return HStack(alignment: .bottom, spacing: 8) {
            Button { odak = false; ekSayfasiAcik = true } label: {
                Image(systemName: "paperclip").font(.system(size: 22 * k)).foregroundStyle(SohbetRenk.metin(koyu)).frame(width: 48, height: 48).temaDugmesi(Circle())
            }
            .accessibilityLabel("Dosya veya fotoğraf ekle")
            mesajAlani("Mesaj yazın")
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(minHeight: 48)
                .temaDugmesi(RoundedRectangle(cornerRadius: 24))
            if girisBos { sesDugmesi(48, dolgu: false).temaDugmesi(Circle()) } else { gonderDugmesi(48) }
            if mesguller { durdurDugmesi(48, kare: false) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 2)
    }

    private func gonder() {
        guard beyin.durum == .bosta, !belgeOkunuyor, !gonderiliyor else { return }
        // Fotoğraflar hâlâ hazırlanıyor: mesaj fotoğrafsız gitmesin; hazırlık bitince (ya da "Beklemeden gönder" ile) gönderilir.
        if hazirlanan > 0 { gonderimBekliyor = true; return }
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && belge != nil ? "Bu belgeyi özetle: \(belge!.ad)" : metin
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ekler.isEmpty else { return }
        let eskiMetin = metin, eskiEkler = ekler, eskiBelge = belge
        metin = ""
        let kaynak = ekler.map { ($0.resim, $0.kenar) }
        ekler = []
        let belgeMetni = belge.map { "Dosya: \($0.ad)\n\($0.not)\n\($0.metin)" }
        belge = nil
        belgeHatasi = nil   // gönderilen taslağın uyarısı sonraki mesaja taşınmasın
        alttaMi = true
        gonderiliyor = true
        // Gönderim boyutuna küçültme ana iş parçacığında değil; sesli kip kapanırken paralel sürer.
        let kucultme: Task<[CGImage], Never>? = kaynak.isEmpty ? nil : Task.detached(priority: .userInitiated) { () -> [CGImage] in
            kaynak.compactMap { $0.0.kucultulmus($0.1) }
        }
        Task {
            await ses.sesliKipiKapat()   // önce ses yolları susar: uyandırma dinleyicisi bekleme boyunca araya girmesin
            let gorseller = await kucultme?.value ?? []
            gonderiliyor = false
            // Beklerken iç kuyruk / Siri devri yuvayı aldıysa yazılan sessizce kaybolmasın: giriş alanına geri konur.
            guard beyin.durum == .bosta else {
                metin = Self.girdiyiBirlestir(eski: eskiMetin, simdiki: metin)
                ekler = Self.ekleriBirlestir(eski: eskiEkler, simdiki: ekler, sinir: max(0, Beyin.enFazlaGorsel - hazirlanan))
                if belge == nil { belge = eskiBelge }
                return
            }
            ses.konusmaci.akisBasladi()
            beyin.gonder(t, ekGorseller: gorseller, belge: belgeMetni)
            ses.akisiIzle()
        }
    }

    /// Gönderilemeyen metin geri konurken bu arada yazılan kaybolmaz: eski önce, yeni sonra.
    nonisolated static func girdiyiBirlestir(eski: String, simdiki: String) -> String {
        let e = eski.trimmingCharacters(in: .whitespacesAndNewlines), s = simdiki.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return simdiki }
        if s.isEmpty { return eski }
        return eski + "\n" + simdiki
    }

    /// Geri konan ekler önce (seçim sırası), bu arada eklenenler sonra; mesaj sınırını aşmaz.
    nonisolated static func ekleriBirlestir<T>(eski: [T], simdiki: [T], sinir: Int) -> [T] {
        Array((eski + simdiki).prefix(max(0, sinir)))
    }
}

struct MesajBalonu: View {
    let rol: Mesaj.Rol
    let metin: String
    /// Tamamlanmış yanıtın toplam süresi; akan yanıtta `canliBaslangic` ile canlı sayaç.
    var sure: TimeInterval? = nil
    var canliBaslangic: Date? = nil
    var model: String? = nil
    var caba: String? = nil
    /// Kullanıcı mesajına eklenen fotoğraflar.
    var resimler: [UIImage] = []
    /// P3.9: eski sohbetten gelen mesajın kalıcı fotoğraf adları (`resimler` boşken küçük resim olarak gösterilir).
    var gorselAdlari: [String] = []
    var mesajID: UUID? = nil
    var zaman: Date? = nil
    /// Eleştirmen/sayısal sağlama notu.
    var kontrol: String? = nil
    /// Önizlenebilir sonuç kartları.
    var ekler: [MesajEki] = []
    /// Sohbet içi aramada seçili eşleşme: satırın arkasında yumuşak vurgu.
    var vurgulu = false
    /// Sohbetin son (bitmiş) asistan yanıtı: altında eylem satırı (kopyala, sesli oku, yeniden üret, paylaş) görünür.
    var sonYanit = false
    /// P3.3: yanıtın izi (yol, kip, çaba, araçlar); beğeni/beğenmeme kaydına ve değerlendirme setine geçer.
    var iz: YanitIzi? = nil
    /// P3.3: beğenmeme nedeni diyaloğu ve "Değerlendirme setine ekle" sayfası.
    @State private var nedenSoruluyor = false
    @State private var setTaslagi: DegerlendirmeTaslagi?
    @State private var buyukResim: BuyukResim?
    /// VoiceOver "Paylaş" eylemiyle açılan paylaşım sayfası.
    @State private var paylasilan: PaylasMetni?
    var etkileşim = true
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(KisiselAlan.self) private var alan
    @Environment(Beyin.self) private var beyin
    @Environment(SesOturumu.self) private var ses
    @Environment(\.colorScheme) private var sema
    @ScaledMetric(relativeTo: .body) private var punto = 17.0
    /// Alt satır (model adı, saat) Dynamic Type ile büyür; satır taşmasın diye üst sınırlı.
    @ScaledMetric(relativeTo: .caption) private var altPunto = 12.0
    private var profil: GorunumTercihleri { ayarlar.gorunum }
    private var duzMetin: String { rol == .kullanici ? metin.replacingOccurrences(of: "📷 ", with: "") : metin }

    /// Balonun alt satırı: yalnız küçük model adı (dokununca model değiştirme menüsü açılır) ve saat.
    /// Kopyala/paylaş/kaydet/sesli oku uzun basma menüsünde ve VoiceOver eylemlerinde.
    private var altSatir: some View {
        let ikincil = SohbetRenk.ikincil(sema == .dark)
        return HStack(spacing: 6) {
            if rol == .asistan, tema.modelAdi, let ad = model ?? (sure != nil ? "Model" : nil) {
                if etkileşim, sure != nil, let id = mesajID {
                    Menu {
                        Section("Başka modelle yeniden üret") {
                            ForEach(Beyin.yenidenUretModelleri, id: \.self) { m in Button(Beyin.modelEtiketi(m)) { beyin.yenidenUret(id, model: m) } }
                        }
                    } label: {
                        Text(ad).lineLimit(1).truncationMode(.middle).frame(minHeight: 28).contentShape(Rectangle())
                    }
                    .disabled(beyin.durum != .bosta)
                    .accessibilityLabel("Model: \(ad). Başka modelle yeniden üret").accessibilityIdentifier("yeniden-uret")
                } else {
                    Text(ad).lineLimit(1).truncationMode(.middle)
                }
            }
            if geriBildirimVar, let id = mesajID { geriBildirim(id) }
            Spacer(minLength: 8)
            if tema.saat, let zaman { Text(Self.saat(zaman)) }
        }
        .font(.system(size: min(altPunto, 18))).fontDesign(.default).foregroundStyle(ikincil)
    }

    /// P3.3: bitmiş asistan yanıtında beğeni/beğenmeme (13 pt küçük simgeler; beğenmeme neden sorar).
    private var geriBildirimVar: Bool { etkileşim && rol == .asistan && sure != nil && mesajID != nil && tema.geriBildirim }

    private func geriBildirim(_ id: UUID) -> some View {
        let oy = KaliteDefteri.ortak.oylar[id]
        let begenDegeri: String = oy == true ? "seçili" : ""
        let begenmeDegeri: String = oy == false ? "seçili" : ""
        return HStack(spacing: 0) {
            Button { KaliteDefteri.ortak.oyla(id, begendi: true, model: model, iz: iz) } label: { eylemSimgesi(oy == true ? "hand.thumbsup.fill" : "hand.thumbsup") }
                .accessibilityLabel("Beğendim").accessibilityValue(begenDegeri)
                .accessibilityIdentifier("begen")
            Button { nedenSoruluyor = true } label: { eylemSimgesi(oy == false ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                .accessibilityLabel("Beğenmedim").accessibilityValue(begenmeDegeri)
                .accessibilityIdentifier("begenme")
        }
        .buttonStyle(.plain)
        .confirmationDialog("Neyi beğenmedin?", isPresented: $nedenSoruluyor, titleVisibility: .visible) {
            ForEach(KaliteDefteri.nedenler, id: \.self) { n in
                Button(n) { KaliteDefteri.ortak.oyla(id, begendi: false, neden: n, model: model, iz: iz) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func sesliOku() { Task { await ses.sesliKipiKapat(); ses.konusmaci.akisBasladi(); ses.konusmaci.akisBitti(metin) } }
    private var kopyaMetni: String { rol == .kullanici ? duzMetin : YanitBicimi.duzelt(metin) }
    private func kopyala() {
        UIPasteboard.general.string = kopyaMetni
        TostDefteri.ortak.goster("Kopyalandı", simge: "doc.on.doc")
    }

    /// Eylem satırı yalnız etkileşimli, bitmiş son asistan yanıtında ve tema açıkken.
    private var eylemSatiriVar: Bool { etkileşim && sonYanit && rol == .asistan && sure != nil && mesajID != nil && tema.eylemSatiri }

    /// Son yanıtın altındaki küçük simge satırı (34×32 dokunma alanı, 13 pt simge).
    private var eylemSatiri: some View {
        let ikincil = SohbetRenk.ikincil(sema == .dark)
        let mesgul = beyin.durum != .bosta
        return HStack(spacing: 2) {
            Button { kopyala() } label: { eylemSimgesi("doc.on.doc") }
                .accessibilityLabel("Kopyala").accessibilityIdentifier("yanit-kopyala")
            Button { sesliOku() } label: { eylemSimgesi("speaker.wave.2") }
                .disabled(mesgul)
                .accessibilityLabel("Sesli oku").accessibilityIdentifier("yanit-sesli-oku")
            if let id = mesajID {
                Menu {
                    Button("Yeniden üret", systemImage: "arrow.clockwise") { beyin.yenidenUret(id, model: nil) }
                    Section("Başka modelle") {
                        ForEach(Beyin.yenidenUretModelleri, id: \.self) { m in Button(Beyin.modelEtiketi(m)) { beyin.yenidenUret(id, model: m) } }
                    }
                } label: { eylemSimgesi("arrow.clockwise") }
                .disabled(mesgul)
                .accessibilityLabel("Yeniden üret").accessibilityIdentifier("yanit-yeniden-uret")
            }
            ShareLink(item: kopyaMetni) { eylemSimgesi("square.and.arrow.up") }
                .accessibilityLabel("Paylaş").accessibilityIdentifier("yanit-paylas")
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ikincil).tint(ikincil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yanit-eylemleri")
    }

    private func eylemSimgesi(_ ad: String) -> some View {
        Image(systemName: ad).font(.system(size: 13, weight: .regular))
            .frame(width: 34, height: 32).contentShape(Rectangle())
    }

    private var tema: SohbetTemasi { SohbetTemaDeposu.ortak.tema }
    /// Asistan yanıtı balonsuz mu (Claude stili: düz yazı, tam genişlik).
    private var balonsuz: Bool { rol == .asistan && !tema.asistanBalonlu }
    private var altSatirVar: Bool {
        (tema.saat && zaman != nil) || (rol == .asistan && tema.modelAdi && (sure != nil || canliBaslangic != nil)) || geriBildirimVar
    }

    struct BuyukResim: Identifiable { let id = UUID(); let resim: UIImage }
    private func mesajResmi(_ r: UIImage) -> some View {
        Image(uiImage: r).resizable()
            .accessibilityLabel("Eklenen fotoğraf").accessibilityHint("Büyütmek için çift dokun").accessibilityIdentifier("mesaj-resmi")
            .onTapGesture(count: 2) { buyukResim = BuyukResim(resim: r) }
            // VoiceOver'ın çift dokunması tek etkinleştirme gönderir; count: 2 hareketi tetiklenmiyordu.
            .accessibilityAction { buyukResim = BuyukResim(resim: r) }
    }
    /// P3.9: kalıcı fotoğrafın tam boyunu ana iş parçacığı dışında yükleyip büyütür.
    private func tamBoyAc(_ url: URL) {
        Task { @MainActor in if let r = await GorselOnbellegi.tamBoy(url) { buyukResim = BuyukResim(resim: r) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if resimler.count == 1 {
                mesajResmi(resimler[0]).scaledToFit().frame(maxWidth: 260, maxHeight: 260).clipShape(.rect(cornerRadius: 12))
            } else if resimler.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(resimler.indices, id: \.self) { i in
                            mesajResmi(resimler[i]).scaledToFill().frame(width: 150, height: 150).clipShape(.rect(cornerRadius: 12))
                        }
                    }
                }
            } else if gorselAdlari.count == 1 {
                // P3.9: eski sohbet fotoğrafı küçük resimle (ana iş parçacığı dışında, önbellekli); büyütünce tam boy yüklenir.
                KucukGorsel(url: EkKalici.gorselURL(gorselAdlari[0]), kenar: 220, buyut: tamBoyAc)
            } else if gorselAdlari.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gorselAdlari, id: \.self) { ad in
                            KucukGorsel(url: EkKalici.gorselURL(ad), kenar: 150, buyut: tamBoyAc)
                        }
                    }
                }
            }
            if rol == .kullanici {
                Text(duzMetin).textSelection(.enabled).font(.system(size: punto * profil.yaziOlcegi)).lineSpacing(punto * profil.yaziOlcegi * 0.2)
                    .fontDesign(tema.kullaniciYaziTipi.tasarim)
                    .foregroundStyle(SohbetRenk.kullaniciMetni(sema == .dark))
            } else {
                ZenginMetinGorunumu(metin: YanitBicimi.duzelt(metin, zengin: true), imlec: canliBaslangic != nil && sure == nil, olcek: profil.yaziOlcegi)
                    .fontDesign(tema.asistanYaziTipi.tasarim)
                    .textSelection(.enabled)
            }
            if etkileşim, alan.kayitli(metin), rol == .kullanici { Label("Kaydedildi", systemImage: "bookmark.fill").font(.caption2).foregroundStyle(.secondary) }
            if !ekler.isEmpty { EkKartlari(ekler: ekler) }
            if altSatirVar { altSatir }
            if eylemSatiriVar { eylemSatiri }
        }
        .foregroundStyle(SohbetRenk.metin(sema == .dark))
        .padding(.horizontal, balonsuz ? 6 : (tema.kuyruk ? 13 : 16)).padding(.top, balonsuz ? 4 : 10).padding(.bottom, balonsuz ? 4 : 8)
        .background {
            if !balonsuz {
                BalonSekli(giden: rol == .kullanici, kose: tema.kose, kuyruk: tema.kuyruk)
                    .fill(rol == .kullanici ? SohbetRenk.gidenBalon(sema == .dark) : SohbetRenk.gelenBalon(sema == .dark))
                    .shadow(color: .black.opacity(tema.kuyruk ? 0.10 : 0), radius: 0.6, y: 0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: rol == .kullanici ? .trailing : .leading)
        .padding(rol == .kullanici ? .leading : .trailing, balonsuz ? 0 : 40)
        .padding(rol == .kullanici ? .trailing : .leading, balonsuz ? 10 : 8)
        .padding(.vertical, balonsuz ? 8 : 2)
        .background { if vurgulu { RoundedRectangle(cornerRadius: 10).fill(profil.vurgu.opacity(0.14)) } }
        .fullScreenCover(item: $buyukResim) { FotoGoruntuleyici(resim: $0.resim) }
        // Live tetiklenince büyütülmüş fotoğraf kapanır (Live tam ekranı başka sunumun üstüne açılamıyor).
        .sheet(item: $paylasilan) { PaylasSayfasi(ogeler: [$0.metin]) }
        .sheet(item: $setTaslagi) { DegerlendirmeEkleSayfasi(taslak: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in
            if buyukResim != nil { buyukResim = nil }
            if paylasilan != nil { paylasilan = nil }
            if setTaslagi != nil { setTaslagi = nil }
            if nedenSoruluyor { nedenSoruluyor = false }
        }
        .accessibilityElement(children: .contain)
        // Tamamlanmış asistan yanıtı: UI testleri tamamlanmayı model etiketine değil buna bakarak anlar (tema etiketi gizleyebilir).
        .accessibilityIdentifier(rol == .asistan && sure != nil && mesajID != nil ? "yanit-tamam" : "")
        .accessibilityAction(named: "Kopyala") { kopyala() }
        .accessibilityAction(named: "Kaydet") { alan.yanitKaydet(metin) }
        .accessibilityAction(named: "Sesli oku") { sesliOku() }
        .accessibilityAction(named: "Paylaş") { paylasilan = PaylasMetni(metin: kopyaMetni) }
        .accessibilityActions {
            if etkileşim, rol == .asistan, sure != nil, let id = mesajID {
                Button("Yeniden üret") { beyin.yenidenUret(id, model: nil) }
            }
        }
        .contextMenu {
            if etkileşim {
                Button("Kopyala", systemImage: "doc.on.doc") { kopyala() }
                ShareLink(item: kopyaMetni) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                Button(alan.kayitli(metin) ? "Kaydedildi" : "Kaydet", systemImage: "bookmark") { alan.yanitKaydet(metin) }.disabled(alan.kayitli(metin))
                if rol == .asistan { Button("Sesli oku", systemImage: "speaker.wave.2") { sesliOku() }.disabled(beyin.durum != .bosta) }
                Button("Düzenleyip yeniden kullan", systemImage: "square.and.pencil") { beyin.disTaslak = metin }
                // P3.3: bitmiş asistan yanıtını (önceki istekle) değerlendirme setine örnek olarak ekle.
                if rol == .asistan, sure != nil, let id = mesajID, let istek = beyin.degerlendirmeIstegi(yanitID: id) {
                    Button("Değerlendirme setine ekle", systemImage: "checklist") {
                        setTaslagi = DegerlendirmeTaslagi(istek: istek, iz: iz, yanit: metin)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private static func saat(_ t: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"
        return f.string(from: t)
    }
}

extension Notification.Name {
    /// Live açılmadan önce mesaj satırlarının/kartlarının kendi sunumlarını (Safari, galeri, QuickLook, tablo, büyük fotoğraf) kapatma çağrısı.
    /// Ana aktörde eşzamanlı yayınlanır; dinleyen görünüm kendi @State sunum bayrağını sıfırlar.
    static let asistanSunumlariKapat = Notification.Name("asistan.sunumlariKapat")
}

/// Uyarı metni rengi (kota, çevrimdışı, ses hatası, kontrol notu): sistem turuncusu açık zeminde (FAF9F5) ~2:1 zıtlık
/// veriyordu; koyu turuncu B25000 ~4,9:1 (WCAG 4,5:1 üstü). Koyu zeminde sistem koyu turuncusu.
enum UyariRengi {
    static func renk(_ koyu: Bool) -> Color { Color(hex: koyu ? "FF9F0A" : "B25000") }
}

extension UIImage {
    /// Uzun kenarı en çok `kenar` piksel olan CGImage (ağ ve bellek için).
    nonisolated func kucultulmus(_ kenar: CGFloat) -> CGImage? {   // UIGraphicsImageRenderer iş parçacığı güvenli
        let oran = min(1, kenar / max(size.width, size.height))
        let boyut = CGSize(width: size.width * oran, height: size.height * oran)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1   // varsayılan ekran ölçeği (3×) kenarı üçe katlıyordu
        let r = UIGraphicsImageRenderer(size: boyut, format: f)
        return r.image { _ in draw(in: CGRect(origin: .zero, size: boyut)) }.cgImage
    }
}

/// VoiceOver "Paylaş" eylemiyle paylaşılan metin (sheet(item:) için kimlikli).
struct PaylasMetni: Identifiable { let id = UUID(); let metin: String }

/// Paylaşım sayfası (UIActivityViewController) sarmalayıcısı; WebKazima'daki özel `PaylasimSayfasi`'nın eşi.
struct PaylasSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: ogeler, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Kamera (UIImagePickerController) sarmalayıcısı.
struct KameraGorunumu: UIViewControllerRepresentable {
    let secildi: (UIImage) -> Void
    @Environment(\.dismiss) private var kapat

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let ana: KameraGorunumu
        init(_ ana: KameraGorunumu) { self.ana = ana }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { ana.secildi(img) }
            ana.kapat()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { ana.kapat() }
    }
}

nonisolated enum BarkodOkuyucu {
    static func kod(_ resim: UIImage) async -> String? {
        guard let cg = resim.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let istek = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(resim.imageOrientation), options: [:]).perform([istek])
            return istek.results?.first?.payloadStringValue
        }.value
    }
}

nonisolated extension CGImagePropertyOrientation {
    init(_ y: UIImage.Orientation) {
        self = switch y {
        case .up: .up; case .upMirrored: .upMirrored; case .down: .down; case .downMirrored: .downMirrored
        case .left: .left; case .leftMirrored: .leftMirrored; case .right: .right; case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
