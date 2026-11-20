import SwiftUI
import AVFoundation

/// Live modu tam ekran konuşma görünümü: büyük ses küresi, canlı altyazı ve tek "Bitir" düğmesi.
/// Küreye dokunmak söz alır (yanıtı keser) ya da konuşmayı gönderir.
struct CanliEkrani: View {
    @Environment(SesOturumu.self) private var ses
    @Environment(Beyin.self) private var beyin
    @Environment(Ayarlar.self) private var ayarlar
    /// Zemin ve yazı renkleri sohbet temasının açık/koyu paletinden gelir (sohbet ekranıyla aynı görünüm).
    @Environment(\.colorScheme) private var sema
    /// Live turundaki araç onayları (dış içerik okunduktan sonraki arama, mesaj, kestirme…) burada sorulur:
    /// sohbet ekranının diyaloğu bu tam ekran örtünün altında kalır, tur askıda kalırdı.
    @Environment(OnayKapisi.self) private var onay
    @Environment(\.accessibilityReduceMotion) private var azHareket
    @State private var altyaziAcik = true
    @State private var sesSecimiAcik = false
    @State private var sesSecimiSunuluyor = false

    private var motor: (any GercekZamanliMotor)? {
        ses.openaiLive.etkin ? ses.openaiLive : (ses.gercekLive.etkin ? ses.gercekLive : nil)
    }

    /// Kullanıcının son sözü: gerçek zamanlı motorun dökümü, sürüyorsa anlık tanıma, yoksa son kullanıcı mesajı.
    private var kullaniciAltyazisi: String {
        if let m = motor { return m.kullaniciMetni }
        if ses.dinleyici.durum == .dinliyor, !ses.dinleyici.canliMetin.isEmpty { return ses.dinleyici.canliMetin }
        return beyin.mesajlar.last(where: { $0.rol == .kullanici })?.metin.replacingOccurrences(of: "📷 ", with: "") ?? ""
    }

    private var asistanAltyazisi: String {
        if let m = motor { return m.yanitMetni }
        if beyin.durum != .bosta { return YanitBicimi.duzelt(beyin.akanMetin) }
        guard let son = beyin.mesajlar.last, son.rol == .asistan else { return "" }
        return YanitBicimi.duzelt(son.metin)
    }

    private var seviye: Double {
        gorselDurum.duzey(girisDb: Double(ses.canliGirisDb), cikisDb: Double(ses.canliCikisDb))
    }

    private var gorselDurum: CanliGorselDurum {
        CanliGorselDurum.sec(baglaniyor: baglaniyor || ses.gecisVar || ses.dinleyici.durum == .hazirlaniyor,
                            dinliyor: dinliyor,
                            sesCaliyor: motor?.durum == .yanitliyor || (ses.konusmaci.simdiCalan != nil && ses.konusmaci.konusuyor && !ses.konusmaci.duraklatildi),
                            yanitBekleniyor: yanitliyor || ses.dinleyici.durum == .cozumluyor,
                            hata: hataMetni != nil)
    }

    private var hataMetni: String? {
        if case .hata(let h) = ses.dinleyici.durum, motor == nil { return h }
        guard !ses.canliMod, motor == nil else { return nil }
        return beyin.sonHata ?? ses.konusmaci.sesHatasi
    }

    private var altyaziVar: Bool { altyaziAcik && (!kullaniciAltyazisi.isEmpty || !asistanAltyazisi.isEmpty) }

    /// Gerçek zamanlı motor bağlanırken küre kapalı: ikinci bir ses yolu açılmasın.
    private var baglaniyor: Bool { ses.openaiLive.durum == .baglaniyor || ses.gercekLive.durum == .baglaniyor }
    private var dinliyor: Bool { ses.dinleyici.durum == .dinliyor || motor?.durum == .dinliyor }
    private var yanitliyor: Bool { ses.konusmaci.konusuyor || motor?.durum == .yanitliyor || beyin.durum != .bosta }

    /// Küre boyu: kamera önizlemesi yer kaplarken küre %100'ün üstüne büyümez (altyazıya yer kalsın).
    nonisolated static func kureBoyu(olcek: Double, kameraAcik: Bool) -> CGFloat {
        CGFloat(240 * (kameraAcik ? min(olcek, 1) : olcek))
    }

    /// Kapanış yalnız ekrandaki isteği reddeder (yanıtlanmış ya da sıradaki istek etkilenmez).
    private var onayAcik: Binding<Bool> {
        Binding(get: { !sesSecimiAcik && !sesSecimiSunuluyor && onay.bekleyen != nil && onay.bekleyen?.onizleme == nil },
                set: { if !$0, let i = onay.bekleyen, i.onizleme == nil { onay.yanitla(false, id: i.id) } })
    }

    /// P2.12: Önizlemeli onay (imza) Live'da da görselle sorulur; önizlemesiz imza onayı hiçbir ekranda olmaz.
    private var onizlemeliOnay: Binding<OnayKapisi.Istek?> {
        Binding(get: { !sesSecimiAcik && !sesSecimiSunuluyor && onay.bekleyen?.onizleme != nil ? onay.bekleyen : nil },
                set: { if $0 == nil, let i = onay.bekleyen, i.onizleme != nil { onay.yanitla(false, id: i.id) } })
    }

    var body: some View {
        GeometryReader { alan in
        VStack(spacing: 0) {
            HStack {
                Image(systemName: gorselDurum.simge)
                    .foregroundStyle(ayarlar.gorunum.vurgu).accessibilityHidden(true)
                Text(gorselDurum.baslik)
                    .font(.subheadline.weight(.medium)).foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                    .contentTransition(.opacity)
                    .animation(azHareket || !ayarlar.gorunum.hareket ? nil : .easeInOut(duration: 0.2), value: gorselDurum)
                    .accessibilityIdentifier("canli-durum")
                Spacer()
                Button { altyaziAcik.toggle() } label: {
                    Image(systemName: altyaziAcik ? "captions.bubble.fill" : "captions.bubble")
                        .font(.title3).foregroundStyle(SohbetRenk.metin(sema == .dark))
                        .frame(width: 48, height: 48).temaDugmesi(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(altyaziAcik ? "Altyazıyı gizle" : "Altyazıyı göster")
                .accessibilityIdentifier("canli-altyazi")
                Button { Task { await ses.kameraDegistir() } } label: {
                    Image(systemName: ses.kameraAcik ? "video.fill" : "video").font(.title3)
                        .foregroundStyle(SohbetRenk.metin(sema == .dark))
                        .frame(width: 48, height: 48).temaDugmesi(Circle())
                }
                .buttonStyle(.plain)
                // Gemini Live görüntü almıyor: o motorda kamera açılmaz (açıksa kapatılabilir).
                .disabled(!ses.kameraAcik && !ses.kameraKullanilabilir)
                .opacity(ses.kameraAcik || ses.kameraKullanilabilir ? 1 : 0.4)
                .accessibilityLabel(ses.kameraAcik ? "Kamerayı kapat" : (ses.kameraKullanilabilir ? "Kamerayı aç (asistan görsün)" : "Kamera bu Live motorunda kullanılamıyor")).accessibilityIdentifier("canli-kamera")
            }
            .padding(.top, 16).padding(.horizontal, 24)
            Button { sesSecimiAcik = true } label: {
                Label(motor != nil ? "Live sesi · Değiştir" : AsistanSesleri.ortak.sesAdi(ayarlar.sesKimligi), systemImage: "speaker.wave.2")
                    .font(.footnote).lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(ayarlar.gorunum.vurgu.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 8)
            .disabled(onay.bekleyen != nil)
            .accessibilityLabel("Live sesini değiştir")
            .accessibilityIdentifier("canli-ses-sec")
            if motor == nil, let hata = ses.konusmaci.sesHatasi {
                Text(hata).font(.caption).foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 6)
                    .accessibilityIdentifier("canli-ses-uyari")
            }
            if ses.kameraAcik {
                KameraOnizleme(oturum: ses.kamera.oturum)
                    .frame(width: 150, height: 200).clipShape(.rect(cornerRadius: 16))
                    .padding(.top, 8).accessibilityLabel("Kamera önizlemesi").accessibilityIdentifier("canli-onizleme")
            }
            Spacer(minLength: 12)
            let boy = min(Self.kureBoyu(olcek: ayarlar.gorunum.kureOlcegi, kameraAcik: ses.kameraAcik),
                          max(100, min(alan.size.width - 48, alan.size.height * (ses.kameraAcik ? 0.24 : 0.38))))
            Button { Task { await ses.yuvarlagaDokun() } } label: {
                SesGostergesi(duzey: seviye, etkin: true, profil: ayarlar.gorunum, durum: gorselDurum, olcum: { seviye })
                    .frame(width: boy, height: boy).contentShape(Circle())
            }
            .buttonStyle(.plain).disabled(ses.gecisVar || baglaniyor)
            .accessibilityLabel(yanitliyor ? "Söz al" : (dinliyor ? "Konuşmayı gönder" : "Konuşmaya başla"))
            .accessibilityValue(gorselDurum.baslik)
            .accessibilityIdentifier("canli-kure")
            Text(gorselDurum.ipucu)
                .font(.footnote).foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 14)
                .accessibilityIdentifier("canli-ipucu")
            if gorselDurum == .hata, let hata = hataMetni {
                Text(hata).font(.footnote).foregroundStyle(SohbetRenk.metin(sema == .dark))
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8)
                    .accessibilityIdentifier("canli-hata")
            }
            Spacer(minLength: 12)
            // Altyazı boş alanı boşluklarla eşit paylaşmasın: önce kendi yerini alır.
            if altyaziVar { altyazi.layoutPriority(1) }
            Button { Task { await ses.canliBitir() } } label: {
                Label("Bitir", systemImage: "xmark")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: 220, minHeight: 56)
                    .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live'ı bitir").accessibilityIdentifier("canli-bitir")
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SohbetZemini())
        .sensoryFeedback(.impact(weight: .light), trigger: dinliyor) { _, yeni in yeni }
        .sensoryFeedback(.selection, trigger: yanitliyor) { _, yeni in yeni }
        .sensoryFeedback(.warning, trigger: onay.bekleyen) { _, yeni in yeni != nil }
        .confirmationDialog(onay.bekleyen?.baslik ?? "", isPresented: onayAcik, titleVisibility: .visible, presenting: onay.bekleyen) { istek in
            Button("Evet, yap") { onay.yanitla(true, id: istek.id) }
            Button("Hayır", role: .cancel) { onay.yanitla(false, id: istek.id) }
        } message: { istek in
            Text(istek.ayrinti)
        }
        .sheet(item: onizlemeliOnay) { istek in
            ImzaOnizlemeSayfasi(istek: istek) { onay.yanitla($0, id: istek.id) }
        }
        .sheet(isPresented: $sesSecimiAcik, onDismiss: { sesSecimiSunuluyor = false }) {
            CanliSesSecimi().onAppear { sesSecimiSunuluyor = true }
        }
        .onChange(of: onay.bekleyen?.id) { _, yeni in
            // Diyalog, ses seçimi tamamen kapandıktan sonra sunulur; altta görünmeden beklemez.
            if yeni != nil { sesSecimiAcik = false }
        }
    }

    /// Son kullanıcı sözü küçük ve soluk, asistanın yanıtı büyük; uzun yanıt aşağı kayar.
    private var altyazi: some View {
        ScrollViewReader { sv in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !kullaniciAltyazisi.isEmpty {
                        Text(kullaniciAltyazisi).font(.callout).foregroundStyle(SohbetRenk.ikincil(sema == .dark))
                            .accessibilityLabel("Sen: \(kullaniciAltyazisi)").accessibilityIdentifier("canli-kullanici")
                    }
                    if !asistanAltyazisi.isEmpty {
                        Text(asistanAltyazisi).font(.title3).foregroundStyle(SohbetRenk.metin(sema == .dark))
                            .accessibilityIdentifier("canli-yanit")
                    }
                    Color.clear.frame(height: 1).id("son")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 220)
            .scrollIndicators(.hidden)
            .onChange(of: asistanAltyazisi) { _, _ in sv.scrollTo("son", anchor: .bottom) }
        }
    }
}

/// Aynı katalog Ayarlar ile paylaşılır; seçim sonraki konuşmaya ve sonraki açılışa kalır.
private struct CanliSesSecimi: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SesOturumu.self) private var ses
    @Environment(OnayKapisi.self) private var onay
    @Environment(\.dismiss) private var kapat
    @State private var seciliyor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ses.gercekZamanliEtkin || ayarlar.canliMotor != "claude" {
                        Text("Buradan ses seçtiğinde Live, Claude yanıtları ve seçtiğin sesle devam eder.")
                    }
                    if !ses.canliSesSecilebilir {
                        Text("Ses değiştirmek için yanıtın bitmesini bekle veya Live ekranındaki küreye dokunarak söz al.")
                    }
                    Text("İşaretli sese tekrar dokunarak yeniden deneyebilirsin. Bulut sesleri internet ve sağlayıcı erişimi gerektirir.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diğer sesler") {
                    ForEach(AsistanSesleri.ortak.sesler) { secenek in
                        satir(secenek.title, kimlik: secenek.id)
                    }
                }
                Section("iPhone · Çevrimdışı") {
                    satir("Türkçe", kimlik: "apple")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }, id: \.identifier) { voice in
                        satir(voice.name, kimlik: "apple:" + voice.identifier)
                    }
                }
                if let hata = AsistanSesleri.ortak.hata {
                    Section { Text(hata).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Live sesi")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .task { await AsistanSesleri.ortak.yenile() }
            .refreshable { await AsistanSesleri.ortak.yenile() }
        }
    }

    private func satir(_ ad: String, kimlik: String) -> some View {
        Button {
            seciliyor = true
            Task {
                if await ses.canliSesiSec(kimlik) { kapat() }
                seciliyor = false
            }
        } label: {
            HStack {
                Text(ad).foregroundStyle(.primary)
                Spacer()
                if ayarlar.sesKimligi == kimlik { Image(systemName: "checkmark").accessibilityLabel("Seçili") }
            }
        }
        .disabled(seciliyor || !ses.canliSesSecilebilir || onay.bekleyen != nil)
        .accessibilityIdentifier("canli-ses-" + kimlik)
    }
}
