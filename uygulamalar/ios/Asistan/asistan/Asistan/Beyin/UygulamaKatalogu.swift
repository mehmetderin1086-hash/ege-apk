import Foundation
import Observation

@MainActor @Observable
final class UygulamaKatalogu {
    struct Uygulama: Codable, Identifiable, Equatable {
        let id: String
        let ad: String
        let digerAdlar: [String]
        let kestirme: String
        let dosya: String
    }
    static let ortak = UygulamaKatalogu()
    let uygulamalar: [Uygulama]
    private(set) var ozelUygulamalar: [Uygulama] { didSet { saklaOzelUygulamalari() } }
    var tumUygulamalar: [Uygulama] { ozelUygulamalar + uygulamalar.filter { sabit in !ozelUygulamalar.contains(where: { $0.id == sabit.id }) } }
    var kopruEklendi: Bool { didSet { d.set(kopruEklendi, forKey: "uygulama.katalog.kopru.v1") } }
    static let kopruAdi = "Mehmet Uygulama Koprusu"
    var ekranAcik = false
    var secilen: String?
    private let d: UserDefaults
    init(defaults: UserDefaults = .standard) {
        d = defaults
        kopruEklendi = defaults.bool(forKey: "uygulama.katalog.kopru.v1")
        uygulamalar = Bundle.main.url(forResource: "uygulama-katalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Uygulama].self, from: $0) } ?? []
        ozelUygulamalar = defaults.data(forKey: "uygulama.katalog.ozel.v1")
            .flatMap { try? JSONDecoder().decode([Uygulama].self, from: $0) } ?? []
    }
    func bul(_ ad: String) -> Uygulama? {
        let q = TelefonAdresleri.ad(ad)
        return tumUygulamalar.first { TelefonAdresleri.ad($0.ad) == q || $0.digerAdlar.contains { TelefonAdresleri.ad($0) == q } || $0.id == ad }
    }
    func ozelEkle(ad: String, kimlik: String, digerAdlar: String = "") throws {
        let temizAd = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        let temizKimlik = kimlik.trimmingCharacters(in: .whitespacesAndNewlines)
        let kimlikDeseni = #"^[A-Za-z0-9][A-Za-z0-9.-]{2,160}$"#
        guard !temizAd.isEmpty, temizAd.count <= 80,
              temizKimlik.range(of: kimlikDeseni, options: .regularExpression) != nil else { throw Hata.gecersiz }
        let diger = digerAdlar.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let yeni = Uygulama(id: temizKimlik, ad: temizAd, digerAdlar: diger, kestirme: Self.kopruAdi, dosya: temizKimlik)
        if let index = ozelUygulamalar.firstIndex(where: { $0.id == temizKimlik || TelefonAdresleri.ad($0.ad) == TelefonAdresleri.ad(temizAd) }) {
            ozelUygulamalar[index] = yeni
        } else {
            guard ozelUygulamalar.count < 100 else { throw Hata.sinir }
            ozelUygulamalar.append(yeni)
        }
    }
    func ozelSil(_ id: String) { ozelUygulamalar.removeAll { $0.id == id } }
    private func saklaOzelUygulamalari() {
        if let veri = try? JSONEncoder().encode(ozelUygulamalar) { d.set(veri, forKey: "uygulama.katalog.ozel.v1") }
    }
    enum Hata: LocalizedError {
        case gecersiz, sinir
        var errorDescription: String? {
            switch self {
            case .gecersiz: return "Uygulama adı ve geçerli paket kimliği gir. Örnek: com.ornek.uygulama"
            case .sinir: return "En fazla 100 özel uygulama eklenebilir."
            }
        }
    }
    func calistirmaURL(_ app: Uygulama) -> URL? {
        if kopruEklendi { return TelefonAdresleri.kisayol(Self.kopruAdi, girdi: app.id) }
        return nil
    }
    func kopruHazirla() throws -> URL {
        guard let url = Bundle.main.url(forResource: "mehmet-uygulama-koprusu", withExtension: "shortcut") else { throw CocoaError(.fileNoSuchFile) }
        return try kopyala(url, ad: Self.kopruAdi)
    }
    private func kopyala(_ kaynak: URL, ad: String) throws -> URL {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "UygulamaKestirmeleri", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let url = klasor.appending(path: ad + ".shortcut")
        try Data(contentsOf: kaynak).write(to: url, options: .atomic)
        return url
    }
}
