import SwiftUI
import AVFoundation
import MediaPlayer

/// Çalışma alanındaki sesli anlatım çıktısı için ayrıntılı oynatıcı (MP3 + transkript).
/// Transkript zamanları sunucudan gelmez; karakter oranına göre KESTİRİLİR (bkz. SesBolumleri) ve ekranda böyle belirtilir.
struct SesOynaticiEkrani: View {
    private let transkript: String
    private let baslik: String
    @State private var denetci: SesOynaticiDenetcisi
    @State private var kaydirilan: Double?
    @State private var otomatikKaydir = true

    init(dosya: URL, transkript: String, baslik: String, kimlik: String) {
        self.transkript = transkript
        self.baslik = baslik
        _denetci = State(initialValue: SesOynaticiDenetcisi(dosya: dosya, transkript: transkript, baslik: baslik, kimlik: kimlik))
    }

    var body: some View {
        VStack(spacing: 12) {
            ustBilgi
            kontroller
            Divider()
            transkriptListesi
        }
        .padding(.horizontal)
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { denetci.baslat() }
        .onDisappear { denetci.bitir() }
        .accessibilityIdentifier("sesOynaticiEkrani")
    }

    private var ustBilgi: some View {
        HStack {
            Menu {
                ForEach(denetci.plan.bolumler) { b in
                    Button("\(b.baslik) (~\(SesBolumleri.zamanMetni(b.baslangic)))") { denetci.git(b.baslangic) }
                }
            } label: {
                Label(denetci.aktifBolumBasligi ?? "Bölümler", systemImage: "list.bullet")
                    .lineLimit(1)
            }
            .disabled(denetci.plan.bolumler.isEmpty)
            .accessibilityIdentifier("sesOynaticiBolumler")
            Spacer()
            if denetci.hata != nil {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }

    private var kontroller: some View {
        VStack(spacing: 8) {
            if let h = denetci.hata { Text(h).font(.footnote).foregroundStyle(.orange) }
            Slider(value: Binding(get: { kaydirilan ?? denetci.zaman },
                                  set: { kaydirilan = $0 }),
                   in: 0...max(denetci.sure, 1)) { duzenleniyor in
                if !duzenleniyor, let k = kaydirilan { denetci.git(k); kaydirilan = nil }
            }
            .disabled(denetci.sure <= 0)
            .accessibilityLabel("Konum")
            .accessibilityIdentifier("sesOynaticiKonum")
            HStack {
                Text(SesBolumleri.zamanMetni(kaydirilan ?? denetci.zaman))
                Spacer()
                Text(SesBolumleri.zamanMetni(denetci.sure))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

            HStack(spacing: 28) {
                Button { denetci.atla(-SesBolumleri.atlamaSaniyesi) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("15 saniye geri").accessibilityIdentifier("sesOynaticiGeri")
                Button { denetci.oynatDuraklat() } label: {
                    Image(systemName: denetci.caliyor ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52))
                }
                .accessibilityLabel(denetci.caliyor ? "Duraklat" : "Oynat").accessibilityIdentifier("sesOynaticiOynat")
                Button { denetci.atla(SesBolumleri.atlamaSaniyesi) } label: { Image(systemName: "goforward.15") }
                    .accessibilityLabel("15 saniye ileri").accessibilityIdentifier("sesOynaticiIleri")
            }
            .font(.title)

            HStack {
                Menu {
                    ForEach(SesBolumleri.hizAdimlari, id: \.self) { h in
                        Button(hizMetni(h)) { denetci.hizAyarla(h) }
                    }
                } label: { Label(hizMetni(denetci.hiz), systemImage: "speedometer") }
                    .accessibilityIdentifier("sesOynaticiHiz")
                Spacer()
                Menu {
                    ForEach(UykuSecenegi.secenekler, id: \.self) { s in
                        Button(s.etiket) { denetci.uykuKur(s) }
                    }
                } label: { Label(denetci.uyku.etiket, systemImage: "moon.zzz") }
                    .accessibilityIdentifier("sesOynaticiUyku")
            }
            .font(.subheadline)
        }
    }

    private var transkriptListesi: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Zamanlar tahminidir (metin uzunluğuna göre); gerçek konumdan birkaç saniye sapabilir.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Toggle("Otomatik kaydır", isOn: $otomatikKaydir).labelsHidden()
                    .accessibilityLabel("Otomatik kaydır").accessibilityIdentifier("sesOynaticiOtoKaydir")
            }
            if denetci.plan.satirlar.isEmpty {
                ContentUnavailableView("Transkript yok", systemImage: "text.alignleft")
            } else {
                ScrollViewReader { vekil in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(denetci.plan.satirlar) { s in
                                satirGorunumu(s).id(s.indeks)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: denetci.aktifSatir) { _, yeni in
                        guard otomatikKaydir, let yeni else { return }
                        withAnimation { vekil.scrollTo(yeni, anchor: .center) }
                    }
                }
            }
        }
    }

    private func satirGorunumu(_ s: SesSatiri) -> some View {
        let aktif = s.indeks == denetci.aktifSatir
        return Button { denetci.git(s.baslangic) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let k = s.konusmaci { Text(k).font(.caption.bold()) }
                    Text("~" + SesBolumleri.zamanMetni(s.baslangic)).font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                Text(s.metin).font(.body).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(aktif ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(aktif ? .isSelected : [])
        .accessibilityIdentifier("sesOynaticiSatir.\(s.indeks)")
    }

    private func hizMetni(_ h: Double) -> String {
        (h == h.rounded() ? String(Int(h)) : String(h).replacingOccurrences(of: ".", with: ",")) + "x"
    }
}

/// AVPlayer + kilit ekranı kumandası + devam kaydı. Tüm durum ana aktörde; sistem kuyruğundan gelen kapanışlar
/// @Sendable'dır ve ana aktöre yalnız Sendable değer (Double/Bool) taşır.
@MainActor @Observable
final class SesOynaticiDenetcisi {
    private(set) var plan = SesPlani()
    private(set) var zaman: Double = 0
    private(set) var sure: Double = 0
    private(set) var caliyor = false
    private(set) var hiz: Double = 1
    private(set) var uyku: UykuSecenegi = .kapali
    private(set) var hata: String?
    private(set) var aktifSatir: Int?
    var aktifBolumBasligi: String? {
        guard let z = SesBolumleri.aktifBolum(zaman: zaman, plan: plan), plan.bolumler.indices.contains(z) else { return nil }
        return plan.bolumler[z].baslik
    }

    @ObservationIgnored private let dosya: URL
    @ObservationIgnored private let transkript: String
    @ObservationIgnored private let baslik: String
    @ObservationIgnored private let kimlik: String
    @ObservationIgnored private let oynatici = AVPlayer()
    @ObservationIgnored private var zamanGozlemcisi: Any?
    @ObservationIgnored private var bitisGozlemcisi: NSObjectProtocol?
    @ObservationIgnored private var kesintiGozlemcisi: NSObjectProtocol?
    @ObservationIgnored private var hedefler: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var uykuSayaci = UykuSayaci(secenek: .kapali)
    @ObservationIgnored private var sonTik: Double?
    @ObservationIgnored private var sonKayit: Double = 0
    @ObservationIgnored private var basladi = false

    init(dosya: URL, transkript: String, baslik: String, kimlik: String) {
        self.dosya = dosya; self.transkript = transkript; self.baslik = baslik; self.kimlik = kimlik
        plan = SesBolumleri.coz(transkript: transkript, sure: 0)
    }

    // MARK: Yaşam döngüsü

    /// SesCalar açık medya sayacına bu oynatıcı eklendi mi (kapanışta yalnız eklendiyse düşülür).
    private var medyaSayildi = false

    func baslat() {
        guard !basladi else { return }
        basladi = true
        guard FileManager.default.fileExists(atPath: dosya.path) || !dosya.isFileURL else {
            hata = "Ses dosyası bulunamadı."; return
        }
        // Açık video gibi sayılır: SesOturumu bu ekran açıkken oturumu bırakmaz, kapanınca bırakma kararını kendisi verir.
        SesCalar.ortak.videoAcildi(); medyaSayildi = true
        do {
            let o = AVAudioSession.sharedInstance()
            // Sesli kip/Live/toplantı kaydı .playAndRecord tutuyorsa kategori değiştirilmez (mikrofon ve kayıt düşmesin).
            if o.category != .playAndRecord { try o.setCategory(.playback, mode: .spokenAudio) }
            try o.setActive(true)
        } catch { hata = "Ses oturumu açılamadı." }

        let oge = AVPlayerItem(url: dosya)
        oynatici.replaceCurrentItem(with: oge)
        oynatici.defaultRate = Float(hiz)

        zamanGozlemcisi = oynatici.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { @Sendable [weak self] t in
            let saniye = t.seconds
            Task { @MainActor [weak self] in self?.tik(saniye) }
        }
        bitisGozlemcisi = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: oge, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.bitti() }
        }
        kesintiGozlemcisi = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { @Sendable [weak self] bildirim in
            let tur = (bildirim.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let basliyor = tur == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor [weak self] in if basliyor { self?.duraklat() } }
        }
        kumandalariKur()

        Task { [weak self, oge] in
            do {
                let d = try await oge.asset.load(.duration).seconds
                self?.sureBelli(d)
            } catch { self?.hata = "Ses dosyası okunamadı." }
        }
    }

    func bitir() {
        duraklat()
        kaydet(zorla: true)
        if let g = zamanGozlemcisi { oynatici.removeTimeObserver(g); zamanGozlemcisi = nil }
        if let g = bitisGozlemcisi { NotificationCenter.default.removeObserver(g); bitisGozlemcisi = nil }
        if let g = kesintiGozlemcisi { NotificationCenter.default.removeObserver(g); kesintiGozlemcisi = nil }
        for (komut, hedef) in hedefler { komut.removeTarget(hedef) }
        hedefler = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        oynatici.replaceCurrentItem(with: nil)
        basladi = false
        // Oturum doğrudan kapatılmaz: SesCalar.bitti → SesOturumu.oturumBirakilir (dinleme/kayıt sürüyorsa açık kalır).
        if medyaSayildi { medyaSayildi = false; SesCalar.ortak.videoKapandi() }
    }

    private func sureBelli(_ d: Double) {
        guard d.isFinite, d > 0 else { hata = "Ses süresi okunamadı."; return }
        sure = d
        plan = SesBolumleri.coz(transkript: transkript, sure: d)
        let kayitli = UserDefaults.standard.object(forKey: SesBolumleri.devamAnahtari(kimlik)) as? Double
        let bas = SesBolumleri.devamZamani(kayitli: kayitli, sure: d)
        if bas > 0 { git(bas) } else { tik(0) }
        nowPlayingGuncelle()
    }

    // MARK: Denetim

    func oynatDuraklat() { caliyor ? duraklat() : oynat() }

    func oynat() {
        guard hata == nil || sure > 0 else { return }
        if sure > 0, zaman >= sure - 0.5 { git(0) }
        oynatici.defaultRate = Float(hiz)
        oynatici.play()
        caliyor = true
        sonTik = nil
        nowPlayingGuncelle()
    }

    func duraklat() {
        oynatici.pause()
        caliyor = false
        kaydet(zorla: true)
        nowPlayingGuncelle()
    }

    func git(_ saniye: Double) {
        let hedef = SesBolumleri.atla(zaman: saniye, fark: 0, sure: sure)
        oynatici.seek(to: CMTime(seconds: hedef, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        sonTik = nil
        tik(hedef)
        nowPlayingGuncelle()
    }

    func atla(_ fark: Double) { git(SesBolumleri.atla(zaman: zaman, fark: fark, sure: sure)) }

    func hizAyarla(_ yeni: Double) {
        hiz = SesBolumleri.hizSinirla(yeni)
        oynatici.defaultRate = Float(hiz)
        if caliyor { oynatici.rate = Float(hiz) }
        nowPlayingGuncelle()
    }

    func uykuKur(_ secenek: UykuSecenegi) {
        uyku = secenek
        var bitis: Double?
        if secenek == .bolumSonu, let b = SesBolumleri.aktifBolum(zaman: zaman, plan: plan), plan.bolumler.indices.contains(b) {
            bitis = plan.bolumler[b].bitis
        }
        uykuSayaci = UykuSayaci(secenek: secenek, bolumBitisi: bitis)
    }

    // MARK: Dahili

    private func tik(_ saniye: Double) {
        guard saniye.isFinite else { return }
        if caliyor, let onceki = sonTik, saniye >= onceki, saniye - onceki < 2 {
            if uykuSayaci.ilerlet(gecen: (saniye - onceki) / max(hiz, 0.01), zaman: saniye) {
                zaman = saniye
                duraklat()
                uyku = .kapali; uykuSayaci = UykuSayaci(secenek: .kapali)
                return
            }
        }
        sonTik = saniye
        zaman = saniye
        let yeni = SesBolumleri.aktifSatir(zaman: saniye, plan: plan)
        if yeni != aktifSatir { aktifSatir = yeni }
        kaydet(zorla: false)
    }

    private func bitti() {
        caliyor = false
        zaman = sure
        UserDefaults.standard.removeObject(forKey: SesBolumleri.devamAnahtari(kimlik))
        nowPlayingGuncelle()
    }

    private func kaydet(zorla: Bool) {
        guard sure > 0, zorla || abs(zaman - sonKayit) >= 5 else { return }
        sonKayit = zaman
        UserDefaults.standard.set(zaman, forKey: SesBolumleri.devamAnahtari(kimlik))
    }

    // MARK: Kilit ekranı

    private func nowPlayingGuncelle() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: baslik,
            MPMediaItemPropertyArtist: "Asistan",
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: sure),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: zaman),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: caliyor ? hiz : 0),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: hiz),
        ]
    }

    /// addTarget kapanışları sistem kuyruğundan çağrılır: @Sendable, ana aktöre yalnız Double/Bool/Void taşınır.
    private func kumandalariKur() {
        let merkez = MPRemoteCommandCenter.shared()
        func ekle(_ komut: MPRemoteCommand, _ islem: @escaping @MainActor @Sendable (SesOynaticiDenetcisi) -> Void) {
            komut.isEnabled = true
            let hedef = komut.addTarget { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in if let s = self { islem(s) } }
                return .success
            }
            hedefler.append((komut, hedef))
        }
        ekle(merkez.playCommand) { $0.oynat() }
        ekle(merkez.pauseCommand) { $0.duraklat() }
        ekle(merkez.togglePlayPauseCommand) { $0.oynatDuraklat() }
        merkez.skipForwardCommand.preferredIntervals = [NSNumber(value: SesBolumleri.atlamaSaniyesi)]
        merkez.skipBackwardCommand.preferredIntervals = [NSNumber(value: SesBolumleri.atlamaSaniyesi)]
        ekle(merkez.skipForwardCommand) { $0.atla(SesBolumleri.atlamaSaniyesi) }
        ekle(merkez.skipBackwardCommand) { $0.atla(-SesBolumleri.atlamaSaniyesi) }
        ekle(merkez.nextTrackCommand) { s in
            if let h = SesBolumleri.sonrakiBolumHedefi(zaman: s.zaman, plan: s.plan) { s.git(h) }
        }
        ekle(merkez.previousTrackCommand) { s in s.git(SesBolumleri.oncekiBolumHedefi(zaman: s.zaman, plan: s.plan)) }

        merkez.changePlaybackPositionCommand.isEnabled = true
        let konum = merkez.changePlaybackPositionCommand.addTarget { @Sendable [weak self] olay in
            guard let e = olay as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let hedef = e.positionTime
            Task { @MainActor [weak self] in self?.git(hedef) }
            return .success
        }
        hedefler.append((merkez.changePlaybackPositionCommand, konum))
    }
}
