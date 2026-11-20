import AVKit
import SwiftUI

/// Kütüphane oynatıcısı: AVPlayerViewController (Resim içinde Resim, arka planda ses), .srt altyazı katmanı,
/// kaldığı yerden sürme ve seslerde sırayla çalma.
struct Oynatici: View {
    let oge: KutuphaneOgesi
    var sira: [KutuphaneOgesi] = []
    @Environment(\.dismiss) private var kapat
    @State private var simdiki: KutuphaneOgesi?

    var body: some View {
        OynaticiTemsilcisi(ogeler: sira.isEmpty ? [oge] : sira) { simdiki = $0 }
            .ignoresSafeArea()
            .background(.black)
            .overlay(alignment: .topLeading) {
                Button { kapat() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(.leading, 16)
                .padding(.top, 8)
            }
            .overlay(alignment: .topTrailing) {
                let paylasilan = simdiki ?? oge
                ShareLink(item: Kutuphane.shared.url(paylasilan), preview: Paylasim.onizleme(paylasilan)) {
                    Image(systemName: "square.and.arrow.up").font(.headline).padding(12)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .contextMenu { PaylasMenusu(oge: paylasilan) }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
    }
}

private struct OynaticiTemsilcisi: UIViewControllerRepresentable {
    let ogeler: [KutuphaneOgesi]
    let degisti: (KutuphaneOgesi) -> Void
    func makeUIViewController(context: Context) -> KepceOynaticiDenetcisi {
        let denetci = KepceOynaticiDenetcisi(ogeler: ogeler)
        denetci.degisti = degisti
        return denetci
    }
    func updateUIViewController(_ denetci: KepceOynaticiDenetcisi, context: Context) {}
}

final class KepceOynaticiDenetcisi: AVPlayerViewController {
    private let ogeler: [KutuphaneOgesi]
    private var sira = 0
    private let kuyrukOynatici = AVQueuePlayer()
    private var zamanGozlemcisi: Any?
    private var bitisGozlemcisi: NSObjectProtocol?
    private var altyazilar: [AltyaziSatiri] = []
    private let altyaziEtiketi = UILabel()
    private let kapakGorunumu = UIImageView()
    private let kutuphane = Kutuphane.shared
    private var oynatmaOgeleri: [AVPlayerItem] = []
    var degisti: ((KutuphaneOgesi) -> Void)?

    init(ogeler: [KutuphaneOgesi]) {
        self.ogeler = ogeler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setActive(true)
        allowsPictureInPicturePlayback = true
        canStartPictureInPictureAutomaticallyFromInline = true
        updatesNowPlayingInfoCenter = true
        player = kuyrukOynatici
        kurKatmanlar()
        oynatmaOgeleri = ogeler.map(ogeYap)
        for oge in oynatmaOgeleri { kuyrukOynatici.insert(oge, after: nil) }
        bitisGozlemcisi = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] bildirim in
            let kimlik = (bildirim.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.bitti(kimlik) }
        }
        zamanGozlemcisi = kuyrukOynatici.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] zaman in
            MainActor.assumeIsolated { self?.zamanDegisti(zaman.seconds) }
        }
        hazirla(0)
        kuyrukOynatici.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        konumuKaydet()
    }

    isolated deinit {
        if let bitisGozlemcisi { NotificationCenter.default.removeObserver(bitisGozlemcisi) }
    }

    private func ogeYap(_ oge: KutuphaneOgesi) -> AVPlayerItem {
        let oge_ = AVPlayerItem(url: kutuphane.url(oge))
        var bilgiler: [AVMetadataItem] = []
        let baslik = AVMutableMetadataItem()
        baslik.identifier = .commonIdentifierTitle
        baslik.value = oge.baslik as NSString
        bilgiler.append(baslik)
        if let yazar = oge.yazar {
            let s = AVMutableMetadataItem()
            s.identifier = .commonIdentifierArtist
            s.value = yazar as NSString
            bilgiler.append(s)
        }
        if let kapak = kutuphane.kapakURL(oge), let veri = try? Data(contentsOf: kapak) {
            let k = AVMutableMetadataItem()
            k.identifier = .commonIdentifierArtwork
            k.value = veri as NSData
            k.dataType = kCMMetadataBaseDataType_JPEG as String
            bilgiler.append(k)
        }
        oge_.externalMetadata = bilgiler
        return oge_
    }

    private func kurKatmanlar() {
        guard let katman = contentOverlayView else { return }
        kapakGorunumu.contentMode = .scaleAspectFit
        kapakGorunumu.translatesAutoresizingMaskIntoConstraints = false
        katman.addSubview(kapakGorunumu)
        altyaziEtiketi.numberOfLines = 0
        altyaziEtiketi.textAlignment = .center
        altyaziEtiketi.font = .preferredFont(forTextStyle: .title3).withSize(19)
        altyaziEtiketi.textColor = .white
        altyaziEtiketi.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        altyaziEtiketi.layer.cornerRadius = 6
        altyaziEtiketi.clipsToBounds = true
        altyaziEtiketi.translatesAutoresizingMaskIntoConstraints = false
        katman.addSubview(altyaziEtiketi)
        NSLayoutConstraint.activate([
            kapakGorunumu.centerXAnchor.constraint(equalTo: katman.centerXAnchor),
            kapakGorunumu.centerYAnchor.constraint(equalTo: katman.centerYAnchor),
            kapakGorunumu.widthAnchor.constraint(equalTo: katman.widthAnchor, multiplier: 0.7),
            kapakGorunumu.heightAnchor.constraint(equalTo: katman.heightAnchor, multiplier: 0.6),
            altyaziEtiketi.centerXAnchor.constraint(equalTo: katman.centerXAnchor),
            altyaziEtiketi.bottomAnchor.constraint(equalTo: katman.safeAreaLayoutGuide.bottomAnchor, constant: -64),
            altyaziEtiketi.widthAnchor.constraint(lessThanOrEqualTo: katman.widthAnchor, multiplier: 0.9),
        ])
    }

    /// Sıradaki öğenin altyazısını, kapağını ve kaldığı yeri hazırlar.
    private func hazirla(_ i: Int, konumaGit: Bool = true) {
        guard ogeler.indices.contains(i) else { return }
        sira = i
        let oge = ogeler[i]
        degisti?(oge)
        altyazilar = []
        altyaziEtiketi.isHidden = true
        if let dil = oge.altyazilar.keys.sorted().first, let url = kutuphane.altyaziURL(oge, dil: dil), let metin = try? String(contentsOf: url, encoding: .utf8) {
            altyazilar = Altyazi.srt(metin)
        }
        kapakGorunumu.image = oge.sesMi ? kutuphane.kapakURL(oge).flatMap { UIImage(contentsOfFile: $0.path) } : nil
        kapakGorunumu.isHidden = !oge.sesMi
        if konumaGit, let konum = oge.konum, let sure = oge.sure, konum > 5, konum < sure - 10 {
            kuyrukOynatici.seek(to: CMTime(seconds: konum, preferredTimescale: 600))
        }
    }

    private func zamanDegisti(_ t: Double) {
        guard !altyazilar.isEmpty else { return }
        if let satir = altyazilar.first(where: { $0.baslangic <= t && t < $0.bitis }) {
            let metin = "  \(satir.metin.replacingOccurrences(of: "\n", with: "  \n  "))  "
            if altyaziEtiketi.text != metin { altyaziEtiketi.text = metin }
            altyaziEtiketi.isHidden = false
        } else {
            altyaziEtiketi.isHidden = true
        }
    }

    private func bitti(_ kimlik: ObjectIdentifier?) {
        guard let kimlik, let i = oynatmaOgeleri.firstIndex(where: { ObjectIdentifier($0) == kimlik }) else { return }
        kutuphane.konumKaydet(ogeler[i].id, 0)
        if i + 1 < ogeler.count { hazirla(i + 1, konumaGit: false) }
    }

    private func konumuKaydet() {
        guard ogeler.indices.contains(sira) else { return }
        let t = kuyrukOynatici.currentTime().seconds
        if t.isFinite, t > 0 { kutuphane.konumKaydet(ogeler[sira].id, t) }
        kuyrukOynatici.pause()
    }
}
