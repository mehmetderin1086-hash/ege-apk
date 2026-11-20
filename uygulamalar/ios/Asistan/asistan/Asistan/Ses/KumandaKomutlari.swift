import Foundation
import MediaPlayer
import Observation

/// P3.12: AirPods / kilit ekranı kumandası (MPRemoteCommandCenter). Yalnız Ayarlar 'Kulaklık düğmesi' açıkken ve sesli
/// kipte bağlanır (SesOturumu). Bağlıyken ses oturumu karışmaz kurulur (`YolSecici.bayraklar.kumandaEtkin`): uygulama
/// 'Şu an çalan' olabilir, bu yüzden başka uygulamanın müziği kısılmak yerine durur.
/// Eşleme: tek basış (oynat/duraklat) → okuma sürüyorsa duraklat/devam, dinliyorsa gönder, değilse yuvarlağa dokunuş;
/// iki basış (sonraki) → sözü al; hız komutu → okuma hızı.
/// Swift 6: addTarget kapanışları sistem kuyruğundan çağrılabilir, bu yüzden @Sendable; ana aktöre Task ile geçilir.
@MainActor
final class KumandaKomutlari {
    nonisolated enum Komut: Sendable, Equatable { case oynatDuraklat, oynat, duraklat, sonraki, hiz(Float) }

    private weak var ses: SesOturumu?
    private var hedefler: [(MPRemoteCommand, Any)] = []
    private(set) var bagli = false
    /// `izle` zinciri nesli: coz/bagla döngüsünde eski zincir ölür (aksi hâlde her bağlanışta bir zincir daha birikir).
    private var izlemeNesli = 0
    static let hizlar: [Float] = [1.0, 1.25, 1.5]

    func bagla(_ ses: SesOturumu) {
        self.ses = ses
        guard !bagli else { bilgiyiYenile(); return }
        bagli = true
        YolSecici.bayraklar.kumandaEtkin = true
        let merkez = MPRemoteCommandCenter.shared()
        ekle(merkez.togglePlayPauseCommand, .oynatDuraklat)
        ekle(merkez.playCommand, .oynat)
        ekle(merkez.pauseCommand, .duraklat)
        ekle(merkez.nextTrackCommand, .sonraki)
        merkez.changePlaybackRateCommand.supportedPlaybackRates = Self.hizlar.map { NSNumber(value: $0) }
        let hizHedefi = merkez.changePlaybackRateCommand.addTarget { @Sendable [weak self] olay in
            let oran = (olay as? MPChangePlaybackRateCommandEvent)?.playbackRate ?? 1
            Task { @MainActor [weak self] in self?.isle(.hiz(oran)) }
            return .success
        }
        hedefler.append((merkez.changePlaybackRateCommand, hizHedefi))
        for (komut, _) in hedefler { komut.isEnabled = true }
        izlemeNesli += 1
        izle(nesil: izlemeNesli)
    }

    func coz() {
        YolSecici.bayraklar.kumandaEtkin = false
        guard bagli else { return }
        bagli = false
        izlemeNesli += 1
        for (komut, hedef) in hedefler { komut.removeTarget(hedef) }
        hedefler.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func ekle(_ komut: MPRemoteCommand, _ k: Komut) {
        let hedef = komut.addTarget { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.isle(k) }
            return .success
        }
        hedefler.append((komut, hedef))
    }

    /// Saf karar: komut ve okuma/dinleme durumundan yapılacak iş.
    nonisolated enum Is: Equatable, Sendable { case duraklat, devam, gonder, dokun, sozuAl, hiz(Float), hicbiri }
    nonisolated static func karar(_ k: Komut, konusuyor: Bool, duraklatildi: Bool, dinliyor: Bool) -> Is {
        switch k {
        case .hiz(let h): return .hiz(h)
        case .sonraki: return .sozuAl
        case .duraklat:
            if konusuyor { return duraklatildi ? .hicbiri : .duraklat }
            return dinliyor ? .gonder : .hicbiri
        case .oynat:
            if konusuyor { return duraklatildi ? .devam : .hicbiri }
            return dinliyor ? .gonder : .dokun
        case .oynatDuraklat:
            if konusuyor { return duraklatildi ? .devam : .duraklat }
            return dinliyor ? .gonder : .dokun
        }
    }

    private func isle(_ k: Komut) {
        guard bagli, let ses else { return }
        let m = ses.konusmaci
        switch Self.karar(k, konusuyor: m.konusuyor, duraklatildi: m.duraklatildi, dinliyor: ses.dinleyici.durum == .dinliyor) {
        case .duraklat: m.duraklat()
        case .devam: m.devamEt()
        case .gonder: ses.dinleyici.gonder()
        case .dokun: Task { await ses.yuvarlagaDokun() }
        case .sozuAl: Task { await ses.sozuAl() }
        case .hiz(let h): m.hiziDegistir(h)
        case .hicbiri: break
        }
    }

    // MARK: Şu an çalan bilgisi

    /// Okuma durumu değişince 'Şu an çalan' yenilenir (withObservationTracking tek atış; her değişimde yeniden kurulur).
    private func izle(nesil: Int) {
        guard bagli, nesil == izlemeNesli, let ses else { return }
        withObservationTracking {
            _ = (ses.konusmaci.konusuyor, ses.konusmaci.duraklatildi, ses.konusmaci.simdiCalan, ses.konusmaci.hiz)
        } onChange: { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.izle(nesil: nesil) }
        }
        bilgiyiYenile()
    }

    private func bilgiyiYenile() {
        guard bagli, let m = ses?.konusmaci else { return }
        guard m.konusuyor else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: m.simdiCalan.map { String($0.prefix(120)) } ?? "Asistan yanıtı",
            MPMediaItemPropertyArtist: m.ayarlar?.gorunenAd ?? "Asistan",
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: m.duraklatildi ? 0 : m.hiz),
        ]
    }
}
