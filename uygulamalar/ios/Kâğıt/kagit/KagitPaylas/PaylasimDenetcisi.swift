import UIKit
import UniformTypeIdentifiers

/// Paylaş menüsündeki "Kâğıt'a kaydet": gelen PDF/görsel/belgeleri App Group'taki
/// Gelenler klasörüne kopyalar; uygulama açılınca kitaplığa alır.
final class PaylasimDenetcisi: UIViewController {
    private let etiket = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        etiket.text = "Kâğıt'a kaydediliyor…"
        etiket.font = .preferredFont(forTextStyle: .headline)
        etiket.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(etiket)
        NSLayoutConstraint.activate([etiket.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     etiket.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        Task { await kaydet() }
    }

    private func kaydet() async {
        let ogeler = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var sayi = 0
        let ekler = ogeler.flatMap { $0.attachments ?? [] }
        if let hedef = OrtakKlasor.gelenler {
            for (i, ek) in ekler.enumerated() {
                let tur = [UTType.pdf, .image, .content].first { ek.hasItemConformingToTypeIdentifier($0.identifier) }
                guard let tur else { continue }
                etiket.text = "Kâğıt'a kaydediliyor… (\(i + 1)/\(ekler.count))"
                if await kopyala(ek, tur, hedef) { sayi += 1 }
            }
        }
        etiket.text = sayi > 0 ? "\(sayi) dosya kaydedildi ✓" : "Kaydedilecek dosya bulunamadı"
        try? await Task.sleep(for: .milliseconds(700))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func kopyala(_ ek: NSItemProvider, _ tur: UTType, _ hedef: URL) async -> Bool {
        await withCheckedContinuation { devam in
            _ = ek.loadFileRepresentation(for: tur, openInPlace: false) { url, _, _ in
                guard let url else { devam.resume(returning: false); return }
                var h = hedef.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: h.path) {
                    h = hedef.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
                }
                devam.resume(returning: (try? FileManager.default.copyItem(at: url, to: h)) != nil)
            }
        }
    }
}
