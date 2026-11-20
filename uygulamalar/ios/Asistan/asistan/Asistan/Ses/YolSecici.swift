import AVFoundation
import Foundation

/// P3.12: sıralı dinlemenin (SesDinleyici) mikrofon yolu. Varsayılan bugünkü davranıştır: Bluetooth HFP kapalı,
/// giriş dahili mikrofonda kalır, çıkış AirPods'a (A2DP) gidebilir (14 Eki: kutudaki kulaklıkta HFP girişi sıfır geliyordu).
/// Ayarlar 'Kulaklık mikrofonu' açıkken (`ayar.kulaklikMikrofonuV1`) Bluetooth çıkış varsa HFP girişi seçilir; giriş
/// sessiz kalırsa (`MikrofonSinyali.engelli`) `hfpYasakla` 5 dk dahili mikrofona döndürür. Kablolu kulaklık mikrofonu her
/// zaman tercih edilir (tam bant, kutu sorunu yok). Saf çekirdek (`sec`, `secenekler`, `hedefPort`) birim testlidir.
nonisolated enum YolSecici {
    nonisolated enum Giris: Equatable, Sendable { case bluetooth, kablolu, dahili }

    static let kulaklikAnahtari = "ayar.kulaklikMikrofonuV1"
    static let kumandaAnahtari = "ayar.kumandaV1"

    static func bluetoothMu(_ p: AVAudioSession.Port) -> Bool {
        p == .bluetoothA2DP || p == .bluetoothHFP || p == .bluetoothLE
    }

    /// `cikislar`: o anki çıkış portları; `girisler`: kullanılabilir giriş portları.
    static func sec(cikislar: [AVAudioSession.Port], girisler: [AVAudioSession.Port], kulaklikTercih: Bool, hfpYasakli: Bool) -> Giris {
        if girisler.contains(.headsetMic) { return .kablolu }
        if kulaklikTercih, !hfpYasakli, cikislar.contains(where: bluetoothMu) { return .bluetooth }
        return .dahili
    }

    /// Kumanda (AirPods düğmesi) açıkken oturum karışmaz olur: `.duckOthers` (mixWithOthers içerir) uygulamanın
    /// 'Şu an çalan' olmasını engeller. Bu yüzden müzik kısılmaz, durur.
    static func secenekler(_ g: Giris, kumanda: Bool) -> AVAudioSession.CategoryOptions {
        var s: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
        if g == .bluetooth { s.insert(.allowBluetoothHFP) }
        if !kumanda { s.insert(.duckOthers) }
        return s
    }

    static func hedefPort(_ g: Giris) -> AVAudioSession.Port {
        switch g {
        case .bluetooth: .bluetoothHFP
        case .kablolu: .headsetMic
        case .dahili: .builtInMic
        }
    }

    /// Kategoriyi ve tercih edilen girişi kurar (SesOturumuKapisi aktöründen çağrılır; setActive çağıranda kalır).
    /// Bluetooth seçilip HFP girişi listede yoksa dahiliye düşülür ve kategori HFP'siz yeniden kurulur.
    @discardableResult static func uygula(_ o: AVAudioSession, defaults d: UserDefaults = .standard) throws -> Giris {
        let tercih = d.object(forKey: kulaklikAnahtari) as? Bool ?? false
        let kumanda = (d.object(forKey: kumandaAnahtari) as? Bool ?? false) && bayraklar.kumandaEtkin
        let cikislar = o.currentRoute.outputs.map(\.portType)
        let girisler = (o.availableInputs ?? []).map(\.portType) + o.currentRoute.inputs.map(\.portType)
        var g = sec(cikislar: cikislar, girisler: girisler, kulaklikTercih: tercih, hfpYasakli: hfpYasakli)
        try o.setCategory(.playAndRecord, mode: .default, options: secenekler(g, kumanda: kumanda))
        let sonra = (o.availableInputs ?? []).map(\.portType)
        if g == .bluetooth, !sonra.contains(.bluetoothHFP) {
            g = .dahili
            try o.setCategory(.playAndRecord, mode: .default, options: secenekler(g, kumanda: kumanda))
        } else if g == .dahili, sonra.contains(.headsetMic) {
            g = .kablolu   // kategori ilk kez kayda alınınca görünen kablolu mikrofon (seçenekler aynı)
        }
        let hedef = hedefPort(g)
        if let p = o.availableInputs?.first(where: { $0.portType == hedef }) { try? o.setPreferredInput(p) }
        return g
    }

    /// Live (CanliSesIO) için: kategoriye dokunmaz (.voiceChat + HFP kalır), yalnız tercih edilen girişi seçer.
    /// Live zaten HFP'lidir: Bluetooth çıkış varken kulaklık mikrofonu korunur (dahiliyi seçmek çıkışı da hoparlöre
    /// taşırdı); kulaklık yasaklıysa ya da HFP girişi yoksa dahili mikrofon, kablolu varsa o seçilir.
    static func tercihUygula(_ o: AVAudioSession) {
        let girisler = (o.availableInputs ?? []).map(\.portType)
        var g = sec(cikislar: o.currentRoute.outputs.map(\.portType), girisler: girisler, kulaklikTercih: true, hfpYasakli: hfpYasakli)
        if g == .bluetooth, !girisler.contains(.bluetoothHFP) { g = .dahili }
        let hedef = hedefPort(g)
        guard o.currentRoute.inputs.first?.portType != hedef,
              let p = o.availableInputs?.first(where: { $0.portType == hedef }) else { return }
        try? o.setPreferredInput(p)
    }

    // MARK: Paylaşılan bayraklar (herhangi bir iş parçacığından)

    static let bayraklar = YolBayraklari()

    /// Kutudaki AirPods tuzağı: HFP girişi sessiz geldi, `dakika` boyunca dahili mikrofon kullanılır.
    static func hfpYasakla(dakika: Int = 5, simdi: Date = .now) {
        bayraklar.hfpYasakBitis = simdi.addingTimeInterval(TimeInterval(dakika * 60))
    }
    static var hfpYasakli: Bool { yasakSurer(bitis: bayraklar.hfpYasakBitis, simdi: .now) }
    static func yasakSurer(bitis: Date?, simdi: Date) -> Bool { bitis.map { simdi < $0 } ?? false }
}

/// Kilitli bayraklar: SesOturumuKapisi aktörü ve ana aktör birlikte okur/yazar.
nonisolated final class YolBayraklari: @unchecked Sendable {
    private let kilit = NSLock()
    private var _hfpYasakBitis: Date?
    private var _kumandaEtkin = false
    var hfpYasakBitis: Date? {
        get { kilit.withLock { _hfpYasakBitis } }
        set { kilit.withLock { _hfpYasakBitis = newValue } }
    }
    /// KumandaKomutlari bağlıyken true: oturum ancak o zaman karışmaz kurulur (Hey Asistan beklemesi müziği durdurmasın).
    var kumandaEtkin: Bool {
        get { kilit.withLock { _kumandaEtkin } }
        set { kilit.withLock { _kumandaEtkin = newValue } }
    }
}
