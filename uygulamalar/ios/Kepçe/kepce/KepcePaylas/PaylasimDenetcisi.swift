import SwiftUI
import UniformTypeIdentifiers

/// Paylaş menüsündeki "Kepçe": bağlantıyı App Group kutusuna bırakır ve uygulamayı açmayı dener.
final class PaylasimDenetcisi: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let gorunum = PaylasimGorunumu(
            yukle: { [weak self] in await self?.adresBul() },
            bitir: { [weak self] adres, tur in self?.bitir(adres: adres, tur: tur) })
        let barindirici = UIHostingController(rootView: gorunum)
        barindirici.view.backgroundColor = .clear
        addChild(barindirici)
        view.addSubview(barindirici.view)
        barindirici.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            barindirici.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barindirici.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barindirici.view.topAnchor.constraint(equalTo: view.topAnchor),
            barindirici.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        barindirici.didMove(toParent: self)
    }

    private func adresBul() async -> String? {
        let ogeler = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for oge in ogeler {
            for saglayici in oge.attachments ?? [] {
                if saglayici.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await saglayici.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, url.scheme?.hasPrefix("http") == true {
                    return url.absoluteString
                }
                if saglayici.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let metin = try? await saglayici.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let adres = PaylasimKutusu.adresBul(metin) {
                    return adres
                }
            }
            if let metin = oge.attributedContentText?.string, let adres = PaylasimKutusu.adresBul(metin) { return adres }
        }
        return nil
    }

    private func bitir(adres: String?, tur: PaylasilanBaglanti.Tur?) {
        if let adres, let tur {
            try? PaylasimKutusu.ekle(PaylasilanBaglanti(adres: adres, tur: tur))
            uygulamayiAc(URL(string: "kepce://paylasim")!)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Uzantılarda `UIApplication.open` doğrudan çağrılamaz; yanıtlayıcı zincirinden uygulama nesnesine ulaşılır.
    private func uygulamayiAc(_ url: URL) {
        var yanitlayici: UIResponder? = self
        let secici = NSSelectorFromString("openURL:options:completionHandler:")
        while let simdiki = yanitlayici {
            if let uygulama = simdiki as? UIApplication, uygulama.responds(to: secici), let yontem = uygulama.method(for: secici) {
                typealias Ac = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                unsafeBitCast(yontem, to: Ac.self)(uygulama, secici, url as NSURL, NSDictionary(), nil)
                return
            }
            yanitlayici = simdiki.next
        }
    }
}

struct PaylasimGorunumu: View {
    let yukle: () async -> String?
    let bitir: (String?, PaylasilanBaglanti.Tur?) -> Void
    @State private var adres: String?
    @State private var yuklendi = false
    @State private var gonderildi = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                HStack {
                    Label("Kepçe", systemImage: "arrow.down.circle.fill").font(.headline).foregroundStyle(Color(red: 0.93, green: 0.26, blue: 0.22))
                    Spacer()
                    Button("Vazgeç") { bitir(nil, nil) }
                }
                if gonderildi {
                    Label("Kepçe'ye gönderildi", systemImage: "checkmark.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.green).padding(.vertical, 20)
                } else if let adres {
                    Text(adres).font(.footnote).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    dugme("Video indir", "film", .video, adres)
                    dugme("Yalnız ses (M4A)", "music.note", .ses, adres)
                    dugme("Seçerek indir…", "slider.horizontal.3", .sec, adres)
                } else if yuklendi {
                    Text("Paylaşılan öğede bağlantı bulunamadı.").foregroundStyle(.secondary).padding(.vertical, 20)
                } else {
                    ProgressView().padding(.vertical, 20)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
            .padding()
        }
        .task {
            adres = await yukle()
            yuklendi = true
        }
    }

    private func dugme(_ baslik: String, _ simge: String, _ tur: PaylasilanBaglanti.Tur, _ adres: String) -> some View {
        Button {
            withAnimation { gonderildi = true }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                bitir(adres, tur)
            }
        } label: {
            Label(baslik, systemImage: simge).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tur == .sec ? .gray : Color(red: 0.93, green: 0.26, blue: 0.22))
        .controlSize(.large)
    }
}
