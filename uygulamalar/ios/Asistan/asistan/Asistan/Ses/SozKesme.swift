import Foundation
import AVFoundation

/// Söz kesme kararı (saf mantık): asistan konuşurken mikrofona gelen ses düzeyini izler.
/// İlk `tabanSuresi` saniye asistanın kendi sesinin yankısı taban alınır; tabanın `payDb` üstünde
/// en az `gerekenSure` saniye süren ses kullanıcının konuşması sayılır. Kısa sıçramalar (öksürük, kapı) tetiklemez.
nonisolated struct SozKesmeKarari {
    static let tabanSuresi = 0.6
    static let gerekenSure = 0.3
    static let payDb: Float = 10
    static let enAzDb: Float = -38

    private var gecen = 0.0
    private var tabanOrnekleri: [Float] = []
    private(set) var taban: Float?
    private var yuksekSure = 0.0

    /// true = kullanıcı konuşuyor, söz kesilmeli.
    mutating func adim(db: Float, dt: Double) -> Bool {
        gecen += dt
        if gecen <= Self.tabanSuresi { tabanOrnekleri.append(db); return false }
        if taban == nil {
            let s = tabanOrnekleri.sorted()
            taban = s.isEmpty ? -60 : s[s.count / 2]
        }
        let esik = max((taban ?? -60) + Self.payDb, Self.enAzDb)
        if db > esik { yuksekSure += dt } else { yuksekSure = max(0, yuksekSure - dt * 2) }
        return yuksekSure >= Self.gerekenSure
    }

    static func rmsDb(_ b: AVAudioPCMBuffer) -> Float {
        guard let k = b.floatChannelData?[0], b.frameLength > 0 else { return -100 }
        var t: Float = 0
        for i in 0..<Int(b.frameLength) { t += k[i] * k[i] }
        let rms = (t / Float(b.frameLength)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -100
    }
}

/// Söz kesme ölçüm kapısı (saf mantık): yankı bastırmalı motor sessizlikte (ses kuyruğa alınırken) açılır,
/// ama taban ölçümü ve karar yalnız oynatma gerçekten başlayınca (`olcumuBaslat`) işler. Böylece VPIO
/// çalan sesin ortasında açılıp ilk heceleri kesmez; taban da asistanın gerçek yankısından ölçülür.
nonisolated struct SozKesmeKapisi {
    private(set) var olcumAcik = false
    private var karar = SozKesmeKarari()

    mutating func sifirla() {
        olcumAcik = false
        karar = SozKesmeKarari()
    }

    /// Oynatma başladı: taban örnekleri sıfırdan toplanır (sessizlikteki örnekler tabanı etkilemez).
    mutating func olcumuBaslat() {
        karar = SozKesmeKarari()
        olcumAcik = true
    }

    /// true = kullanıcı konuşuyor, söz kesilmeli. Ölçüm açılmadan hiçbir zaman tetiklemez.
    mutating func adim(db: Float, dt: Double) -> Bool {
        guard olcumAcik else { return false }
        return karar.adim(db: db, dt: dt)
    }
}

/// P4.3 ön ses (saf mantık): söz kesmenin halka tamponundan dinleyiciye verilecek parçayı hazırlar.
/// En çok `enCokSaniye` (son kısım) tutulur; yankı bastırılmış baştaki sessizlik atılır.
nonisolated enum OnSes {
    /// Son `enCokSaniye` saniyelik örnekler; kısa veri değişmez.
    static func kirp(_ o: [Float], oran: Double, enCokSaniye: Double = 1.5) -> [Float] {
        guard oran > 0 else { return o }
        let azami = max(0, Int(enCokSaniye * oran))
        return o.count > azami ? Array(o.suffix(azami)) : o
    }

    /// Mutlak değeri `esik`i aşan ilk örnekten öncesini atar; hepsi sessizse boş döner.
    static func basSessizligiAt(_ o: [Float], esik: Float = 0.004) -> [Float] {
        guard let i = o.firstIndex(where: { abs($0) > esik }) else { return [] }
        return i == 0 ? o : Array(o[i...])
    }

    /// Dinleyiciye verilecek hazır ön ses: önce kırp, sonra baştaki sessizliği at.
    static func hazirla(_ o: [Float], oran: Double, enCokSaniye: Double = 1.5) -> [Float] {
        basSessizligiAt(kirp(o, oran: oran, enCokSaniye: enCokSaniye))
    }
}

/// Asistan konuşurken çalışan hafif, yankı bastırmalı mikrofon izleyicisi. Kullanıcı konuşursa `tetiklendi` çağrılır.
@MainActor
final class SozKesmeDinleyici {
    var tetiklendi: (() -> Void)?
    private var motor: AVAudioEngine?
    private var kapi = SozKesmeKapisi()
    var calisiyor: Bool { motor != nil }
    /// P4.3: son 1,5 sn yankı bastırılmış mikrofon sesi (halka). Söz kesilince dinleyiciye ön ses olarak verilir:
    /// kullanıcının ilk hecesi (söz kesme kararından önceki 0,3 sn+) kaybolmaz. `durdur` silmez, `baslat` sıfırlar.
    let onTampon = SesTamponu()
    static let onSesSuresi = 1.5
    /// Dinleyiciye verilen ön sesin tetiklenme anından geriye en çok uzunluğu: karar 0,3 sn konuşma gerektirir, daha eski
    /// kısım asistanın yankı artığıdır (dinleyici onu kullanıcı sözü sanıp metne katıyordu).
    static let onSesGeriSuresi = 0.5

    func baslat() {
        guard motor == nil else { return }
        let m = AVAudioEngine()
        let giris = m.inputNode
        // Yankı bastırma: asistanın hoparlörden gelen sesi mikrofonda zayıflar. Diğer sesleri kısma en düşük düzeyde.
        try? giris.setVoiceProcessingEnabled(true)
        giris.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        let bicim = giris.outputFormat(forBus: 0)
        guard bicim.sampleRate > 0, bicim.channelCount > 0 else { return }
        kapi.sifirla()
        onTampon.ayarla(oran: bicim.sampleRate, azamiSure: Self.onSesSuresi)
        // Kapanış ses iş parçacığında çalışır: MainActor özelliğine self üzerinden değil, yerel kopyayla erişilir.
        let onTampon = self.onTampon
        giris.installTap(onBus: 0, bufferSize: 1024, format: bicim) { @Sendable [weak self] tampon, _ in
            onTampon.ekle(tampon)
            let db = SozKesmeKarari.rmsDb(tampon)
            let dt = Double(tampon.frameLength) / bicim.sampleRate
            Task { @MainActor in self?.isle(db: db, dt: dt) }
        }
        do { try m.start(); motor = m } catch { giris.removeTap(onBus: 0) }
    }

    /// Oynatma başladı: taban ölçümü ve karar şimdi başlar. Motor açılamadıysa etkisizdir.
    /// Yanıt ortasındaki cümle boşluğundan sonra yeniden çağrılırsa ölçülmüş taban korunur (kör pencere açılmaz);
    /// yeni deneme/bitiş `durdur` ile kapıyı sıfırlar.
    func olcumuBaslat() {
        guard motor != nil, !kapi.olcumAcik else { return }
        kapi.olcumuBaslat()
    }

    /// P4.3: biriken ön sesi alır ve tamponu boşaltır (`tetiklendi` içinde, `durdur`dan hemen sonra okunur).
    func onSesiAl() -> (ornekler: [Float], oran: Double) {
        (onTampon.al(), onTampon.oran)
    }

    private func isle(db: Float, dt: Double) {
        guard motor != nil, kapi.adim(db: db, dt: dt) else { return }
        durdur()
        tetiklendi?()
    }

    func durdur() {
        guard let m = motor else { return }
        m.inputNode.removeTap(onBus: 0); m.stop()
        try? m.inputNode.setVoiceProcessingEnabled(false)
        motor = nil
        kapi.sifirla()
    }
}
