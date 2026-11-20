import Foundation
import FoundationModels

/// `public-apis/public-apis` kataloğundan seçilen, anahtar istemeyen ve salt okunur hizmetler.
nonisolated struct UcretsizServisAraci: Tool {
    let name = "ucretsizServis"
    let description = "Ücretsiz ve API anahtarı istemeyen genel bilgi hizmetleri. islem: 'liste' (kullanılabilir hizmetler), 'doviz' (kaynakPara, hedefPara, miktar; güncel referans kuruyla çevirir), 'ulke' (sorgu: ülke adı veya ISO kodu), 'kitap' (sorgu: kitap/yazar/ISBN), 'tatil' (ulkeKodu: iki harfli ISO kodu, yil). Güncel döviz, ülke, dünya resmî tatili veya genel kitap kataloğu sorularında bu aracı kullan."

    @Generable
    struct Arguments {
        @Guide(description: "liste, doviz, ulke, kitap veya tatil") var islem: String
        @Guide(description: "Ülke ya da kitap arama metni") var sorgu: String?
        @Guide(description: "Döviz kaynak para birimi; ör. TRY, USD, EUR") var kaynakPara: String?
        @Guide(description: "Döviz hedef para birimi; ör. TRY, USD, EUR") var hedefPara: String?
        @Guide(description: "Çevrilecek miktar; belirtilmezse 1") var miktar: Double?
        @Guide(description: "Resmî tatil ülkesi, iki harfli ISO kodu; ör. TR, DE") var ulkeKodu: String?
        @Guide(description: "Resmî tatil yılı; belirtilmezse içinde bulunulan yıl") var yil: Int?
    }

    func call(arguments a: Arguments) async throws -> String {
        switch AtolyeYonlendirme.normalize(a.islem) {
        case "liste":
            return Self.hizmetler
        case "doviz":
            return try await doviz(a)
        case "ulke":
            guard let sorgu = a.sorgu?.trimmingCharacters(in: .whitespacesAndNewlines), !sorgu.isEmpty else {
                return "Ülke adı ya da ISO kodu gerekli."
            }
            return try await ulke(sorgu)
        case "kitap":
            guard let sorgu = a.sorgu?.trimmingCharacters(in: .whitespacesAndNewlines), !sorgu.isEmpty else {
                return "Kitap adı, yazar ya da ISBN gerekli."
            }
            return try await kitap(sorgu)
        case "tatil":
            let kod = Self.ulkeKodu(a.ulkeKodu ?? a.sorgu ?? "")
            guard kod.count == 2 else { return "İki harfli ülke kodu gerekli; örneğin Türkiye için TR." }
            let yil = a.yil ?? Calendar.current.component(.year, from: .now)
            guard (1900...2100).contains(yil) else { return "Yıl 1900–2100 aralığında olmalı." }
            return try await tatiller(kod: kod, yil: yil)
        default:
            return "İşlem anlaşılmadı. Kullanılabilir işlemler: liste, doviz, ulke, kitap, tatil."
        }
    }

    nonisolated static let hizmetler = """
    Ücretsiz hizmetler (API anahtarı gerekmez):
    • Döviz: Frankfurter — güncel ve geçmiş merkez bankası kurları.
    • Ülke: Dünya Bankası — ülke, bölge, gelir grubu ve başkent bilgisi.
    • Kitap: Open Library — kitap, yazar, ISBN ve ilk yayın yılı araması.
    • Resmî tatil: Nager.Date — ülke ve yıla göre dünya resmî tatilleri.
    • Hava: Open-Meteo — Asistan'ın havaDurumu aracında ayrıca kullanılır.
    Katalog: https://github.com/public-apis/public-apis
    """

    private func doviz(_ a: Arguments) async throws -> String {
        let kaynak = Self.paraKodu(a.kaynakPara ?? "TRY")
        let hedef = Self.paraKodu(a.hedefPara ?? "USD")
        guard kaynak.count == 3, hedef.count == 3, kaynak != hedef else {
            return kaynak == hedef ? "Kaynak ve hedef para birimleri farklı olmalı." : "Para birimlerini üç harfli ISO koduyla belirt; ör. TRY, USD, EUR."
        }
        let miktar = a.miktar ?? 1
        guard miktar.isFinite, miktar > 0, miktar <= 1_000_000_000 else { return "Miktar 0 ile 1 milyar arasında olmalı." }
        let adres = URL(string: "https://api.frankfurter.dev/v2/rate/\(kaynak.lowercased())/\(hedef.lowercased())")!
        let veri = try await Self.getir(adres)
        let kur = try JSONDecoder().decode(DovizYaniti.self, from: veri)
        return Self.dovizMetni(kur, miktar: miktar)
    }

    private func ulke(_ sorgu: String) async throws -> String {
        var c = URLComponents(string: "https://api.worldbank.org/v2/country")!
        c.queryItems = [.init(name: "format", value: "json"), .init(name: "per_page", value: "400")]
        let ulkeler = try Self.ulkeleriCoz(try await Self.getir(c.url!))
        let aranan = AtolyeYonlendirme.normalize(sorgu)
        let bulunan = ulkeler.first { $0.kod2.lowercased() == sorgu.lowercased() || $0.kod3.lowercased() == sorgu.lowercased() }
            ?? ulkeler.first { AtolyeYonlendirme.normalize($0.ad) == aranan }
            ?? ulkeler.first { AtolyeYonlendirme.normalize($0.ad).contains(aranan) }
        guard let bulunan else { return "Dünya Bankası ülke listesinde '\(sorgu)' bulunamadı. ISO koduyla da deneyebilirsin." }
        return Self.ulkeMetni(bulunan)
    }

    private func kitap(_ sorgu: String) async throws -> String {
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        c.queryItems = [
            .init(name: "q", value: sorgu),
            .init(name: "fields", value: "key,title,author_name,first_publish_year,language,isbn"),
            .init(name: "lang", value: "tr"),
            .init(name: "limit", value: "5"),
        ]
        var istek = URLRequest(url: c.url!, timeoutInterval: 20)
        istek.setValue("Asistan/0.21 (com.mehmetderin.asistan)", forHTTPHeaderField: "User-Agent")
        let veri = try await Self.getir(istek)
        return Self.kitapMetni(try JSONDecoder().decode(KitapYaniti.self, from: veri), sorgu: sorgu)
    }

    private func tatiller(kod: String, yil: Int) async throws -> String {
        let adres = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(yil)/\(kod)")!
        let veri = try await Self.getir(adres)
        return Self.tatilMetni(try JSONDecoder().decode([Tatil].self, from: veri), kod: kod, yil: yil)
    }

    private static func getir(_ adres: URL) async throws -> Data {
        try await getir(URLRequest(url: adres, timeoutInterval: 20))
    }

    private static func getir(_ istek: URLRequest) async throws -> Data {
        let (veri, yanit) = try await URLSession.shared.data(for: istek)
        guard let http = yanit as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        try Task.checkCancellation()
        return veri
    }

    nonisolated static func paraKodu(_ ham: String) -> String {
        let n = AtolyeYonlendirme.normalize(ham).replacingOccurrences(of: " ", with: "")
        let bilinen = ["tl": "TRY", "turklirasi": "TRY", "lira": "TRY", "dolar": "USD", "amerikandolari": "USD", "euro": "EUR", "avro": "EUR", "sterlin": "GBP"]
        if let kod = bilinen[n] { return kod }
        let kod = ham.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return kod.count == 3 && kod.allSatisfy({ $0.isASCII && $0.isLetter }) ? kod : ""
    }

    nonisolated static func ulkeKodu(_ ham: String) -> String {
        let n = AtolyeYonlendirme.normalize(ham).trimmingCharacters(in: .whitespacesAndNewlines)
        let bilinen = ["turkiye": "TR", "almanya": "DE", "fransa": "FR", "italya": "IT", "ispanya": "ES", "ingiltere": "GB", "amerika": "US", "abd": "US", "japonya": "JP"]
        if let kod = bilinen[n] { return kod }
        let kod = ham.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return kod.count == 2 && kod.allSatisfy({ $0.isASCII && $0.isLetter }) ? kod : ""
    }

    nonisolated struct DovizYaniti: Decodable, Sendable { let date: String; let base: String; let quote: String; let rate: Double }
    nonisolated static func dovizMetni(_ y: DovizYaniti, miktar: Double) -> String {
        let sonuc = miktar * y.rate
        return "Frankfurter (\(y.date)) referans kuru: 1 \(y.base) = \(sayi(y.rate, basamak: 6)) \(y.quote). \(sayi(miktar, basamak: 2)) \(y.base) = \(sayi(sonuc, basamak: 2)) \(y.quote). Bu alış/satış kuru değil, bilgi amaçlı orta piyasa kurudur."
    }

    nonisolated struct Ulke: Equatable, Sendable {
        let kod2: String; let kod3: String; let ad: String; let baskent: String; let bolge: String; let gelir: String
    }

    nonisolated static func ulkeleriCoz(_ veri: Data) throws -> [Ulke] {
        guard let kok = try JSONSerialization.jsonObject(with: veri) as? [Any], kok.count > 1,
              let satirlar = kok[1] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return satirlar.compactMap { o in
            guard let kod2 = o["iso2Code"] as? String, let kod3 = o["id"] as? String, let ad = o["name"] as? String,
                  let bolgeNesnesi = o["region"] as? [String: Any], let bolge = bolgeNesnesi["value"] as? String,
                  bolge != "Aggregates" else { return nil }
            let gelir = (o["incomeLevel"] as? [String: Any])?["value"] as? String ?? "bilinmiyor"
            return Ulke(kod2: kod2, kod3: kod3, ad: ad, baskent: o["capitalCity"] as? String ?? "", bolge: bolge, gelir: gelir)
        }
    }

    nonisolated static func ulkeMetni(_ u: Ulke) -> String {
        "Dünya Bankası: \(u.ad) (\(u.kod2)/\(u.kod3)). Başkent: \(u.baskent.isEmpty ? "belirtilmemiş" : u.baskent). Bölge: \(u.bolge). Gelir grubu: \(u.gelir)."
    }

    nonisolated struct KitapYaniti: Decodable, Sendable {
        struct Kitap: Decodable, Sendable { let key: String; let title: String; let author_name: [String]?; let first_publish_year: Int?; let language: [String]?; let isbn: [String]? }
        let numFound: Int
        let docs: [Kitap]
    }

    nonisolated static func kitapMetni(_ y: KitapYaniti, sorgu: String) -> String {
        guard !y.docs.isEmpty else { return "Open Library'de '\(sorgu)' için sonuç bulunamadı." }
        let satirlar = y.docs.prefix(5).map { k in
            let yazar = k.author_name?.prefix(2).joined(separator: ", ") ?? "yazar bilinmiyor"
            let yil = k.first_publish_year.map(String.init) ?? "yıl bilinmiyor"
            let isbn = k.isbn?.first.map { " · ISBN \($0)" } ?? ""
            return "• \(k.title) — \(yazar) · \(yil)\(isbn) · https://openlibrary.org\(k.key)"
        }
        return "Open Library: \(y.numFound) eşleşme; ilk \(satirlar.count) sonuç:\n" + satirlar.joined(separator: "\n")
    }

    nonisolated struct Tatil: Decodable, Sendable { let date: String; let localName: String; let name: String }
    nonisolated static func tatilMetni(_ tatiller: [Tatil], kod: String, yil: Int) -> String {
        guard !tatiller.isEmpty else { return "Nager.Date, \(kod) için \(yil) yılında resmî tatil döndürmedi." }
        return "Nager.Date — \(kod), \(yil), \(tatiller.count) resmî tatil:\n" + tatiller.prefix(30).map { "• \($0.date): \($0.localName)" }.joined(separator: "\n")
    }

    nonisolated static func sayi(_ deger: Double, basamak: Int) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "tr_TR"); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = basamak
        return f.string(from: NSNumber(value: deger)) ?? String(deger)
    }
}
