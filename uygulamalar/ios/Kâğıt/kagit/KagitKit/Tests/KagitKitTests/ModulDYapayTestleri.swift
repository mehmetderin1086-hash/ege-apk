import Foundation
import PDFKit
import Testing
@testable import KagitKit

// MARK: - Saplamalar

/// URLProtocol saplaması: istek başına yanıt üretir.
final class SaplamaProtokol: URLProtocol, @unchecked Sendable {
    struct Yanit {
        var kod = 200
        var tur = "application/json"
        var govde: String
    }
    nonisolated(unsafe) static var isleyici: (@Sendable (URLRequest) -> Yanit)?
    nonisolated(unsafe) static var istekler: [URLRequest] = []
    static let kilit = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.kilit.lock()
        var r = request
        if r.httpBody == nil, let s = r.httpBodyStream {
            s.open(); defer { s.close() }
            var d = Data()
            var tampon = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&tampon, maxLength: 4096); if n <= 0 { break }; d.append(tampon, count: n) }
            r.httpBody = d
        }
        Self.istekler.append(r)
        let y = Self.isleyici?(r) ?? Yanit(kod: 500, govde: "{}")
        Self.kilit.unlock()
        let http = HTTPURLResponse(url: request.url!, statusCode: y.kod, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": y.tur])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(y.govde.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func oturum() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SaplamaProtokol.self]
        return URLSession(configuration: c)
    }

    static func sifirla(_ i: @escaping @Sendable (URLRequest) -> Yanit) {
        kilit.lock(); isleyici = i; istekler = []; kilit.unlock()
    }
}

/// Sabit yanıt veren kaynak.
struct SahteKaynak: YapayKaynak {
    var etiket: String { "Sahte" }
    var baglamSiniri: Int { 60_000 }
    let yanitla: @Sendable (YapayIstek) -> String
    func yanit(_ istek: YapayIstek, akis: YapayAkisi?) async throws -> YapayYaniti {
        YapayYaniti(metin: yanitla(istek), model: "sahte", kaynakEtiketi: "Sahte")
    }
}

func sse(_ parcalar: [String]) -> String {
    var s = "event: message_start\ndata: {\"type\":\"message_start\"}\n\n"
    for p in parcalar {
        let j = try! JSONSerialization.data(withJSONObject: ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": p]])
        s += "event: content_block_delta\ndata: \(String(decoding: j, as: UTF8.self))\n\n"
    }
    return s + "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
}

// MARK: - JSON, parçalama, BM25

@Suite struct JSONAyiklaTestleri {
    @Test func citliVeOnsozlu() throws {
        let ham = "Tabii, işte sorular:\n```json\n{\"sorular\": [{\"soru\": \"A } B\", \"dogru\": \"C\",},]}\n```\nBaşka bir şey?"
        let j = try #require(JSONAyikla.metin(ham))
        #expect(j.hasPrefix("{") && j.hasSuffix("}"))
        struct K: Decodable { struct S: Decodable { let soru: String; let dogru: String }; let sorular: [S] }
        let k = try JSONAyikla.coz(K.self, ham)
        #expect(k.sorular[0].soru == "A } B")   // dizge içindeki } dengeyi bozmaz
    }

    @Test func citsizDizi() throws {
        let k = try JSONAyikla.coz([Int].self, "Sonuç: [1, 2, 3] bitti")
        #expect(k == [1, 2, 3])
    }

    @Test func jsonYoksa() {
        #expect(JSONAyikla.metin("hiç json yok") == nil)
        #expect(JSONAyikla.metin("{\"a\": [1, 2") == nil)   // yarım kalmış
        #expect(throws: KagitHata.self) { try JSONAyikla.coz([Int].self, "yok") }
    }
}

@Suite struct ParcalamaBM25Testleri {
    let sayfalar: [Int: String] = [
        1: "Hücre zarı fosfolipit çift tabakadan oluşur. Zar seçici geçirgendir ve madde alışverişini düzenler.",
        2: "Mitokondri hücrenin enerji santralidir. ATP sentezi mitokondri içinde gerçekleşir.",
        3: "Kloroplast fotosentez yapan organeldir. Işık enerjisi kimyasal enerjiye dönüştürülür.",
        4: "DNA nükleotitlerden oluşur. Çift sarmal yapıdadır ve kalıtım bilgisini taşır.",
    ]

    @Test func parcalamaSayfaBilgisiniKorur() {
        let p = Parcalayici.parcala(sayfalar, hedef: 120)
        #expect(p.count >= 4)
        #expect(p.first?.sayfaBas == 1)
        #expect(p.last?.sayfaSon == 4)
        #expect(p.allSatisfy { $0.metin.count <= 130 })
        #expect(Parcalayici.parcala(sayfalar, hedef: 10_000).count == 1)
    }

    @Test func bm25TurkceEklerle() {
        let d = BM25Dizin(parcalar: Parcalayici.parcala(sayfalar, hedef: 120))
        // “mitokondrinin” (ekli) sorgusu 2. sayfayı bulmalı
        let a = d.ara("Mitokondrinin görevi nedir?", en: 2)
        #expect(a.first?.parca.sayfaBas == 2)
        #expect(d.ara("fotosentezi nerede yapılır", en: 1).first?.parca.sayfaBas == 3)
        #expect(d.ara("kalıtım bilgisi DNA", en: 1).first?.parca.sayfaBas == 4)
        #expect(d.ara("xyzqq", en: 3).isEmpty)
    }

    @Test func atifAyiklama() {
        #expect(BelgeSohbeti.atiflar("Zar fosfolipitten oluşur (s. 3).") == [3])
        #expect(BelgeSohbeti.atiflar("Bkz. (s. 2-4) ve sayfa 7") == [2, 3, 4, 7])
        #expect(BelgeSohbeti.atiflar("(s. 5, 9)") == [5, 9])
        #expect(BelgeSohbeti.atiflar("atıf yok") == [])
    }

    @Test func sohbetKaynakSayfalariVerir() async throws {
        let kaynak = SahteKaynak { istek in
            let son = istek.mesajlar.last?.icerik ?? ""
            #expect(son.contains("SORU:"))
            return "Mitokondri enerji üretir (s. 2)."
        }
        let sohbet = BelgeSohbeti(sayfalar: sayfalar, yz: YapayZeka(kaynak: kaynak))
        let y = try await sohbet.sor("Mitokondrinin görevi nedir?")
        #expect(y.kaynakSayfalar == [2])
        #expect(y.kaynakEtiketi == "Sahte")
    }

    @Test func sohbetAtifYoksaBaglamSayfalari() async throws {
        let kaynak = SahteKaynak { _ in "Atıf içermeyen yanıt." }
        let sohbet = BelgeSohbeti(sayfalar: sayfalar, yz: YapayZeka(kaynak: kaynak))
        let y = try await sohbet.sor("Kloroplast nedir?")
        #expect(!y.kaynakSayfalar.isEmpty)
    }
}

// MARK: - İstemci

@Suite(.serialized) struct VekilIstemciTestleri {
    func istemci(model: String = "claude-sonnet-5-5") -> VekilIstemci {
        VekilIstemci(kok: "https://ornek.test/v1", anahtar: "gizli", model: model, oturum: SaplamaProtokol.oturum())
    }

    @Test func claudeAkisliYanit() async throws {
        SaplamaProtokol.sifirla { _ in .init(tur: "text/event-stream", govde: sse(["Merhaba", " dünya"])) }
        let toplanan = Birikim()
        let y = try await istemci().yanit(YapayIstek(sistem: "Kısa ol", kullanici: "Selam"), akis: { toplanan.ekle($0) })
        #expect(y.metin == "Merhaba dünya")
        #expect(y.model == "claude-sonnet-5-5")
        #expect(y.kaynakEtiketi == "Claude (bulut)")
        #expect(toplanan.deger == "Merhaba dünya")
        let r = try #require(SaplamaProtokol.istekler.first)
        #expect(r.url?.absoluteString == "https://ornek.test/v1/messages")
        #expect(r.value(forHTTPHeaderField: "X-Personal-Token") == "gizli")
        let g = try #require(r.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(g["model"] as? String == "claude-sonnet-5-5")
        #expect(g["system"] as? String == "Kısa ol")
        #expect(g["stream"] as? Bool == true)
    }

    @Test func akissizJSONYaniti() async throws {
        SaplamaProtokol.sifirla { _ in .init(govde: "{\"content\":[{\"type\":\"text\",\"text\":\"Tamam\"}]}") }
        #expect(try await istemci().yanit(YapayIstek(kullanici: "x")).metin == "Tamam")
    }

    @Test func hatadaSiradakiModeleDuser() async throws {
        SaplamaProtokol.sifirla { r in
            let govde = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
            if govde.contains("claude-sonnet-5-5") { return .init(kod: 529, govde: "{\"error\":\"asiri yuk\"}") }
            if govde.contains("claude-opus-5-5") { return .init(kod: 429, govde: "{}") }
            return .init(govde: "{\"choices\":[{\"message\":{\"content\":\"Gemini yanıtı\"}}]}")
        }
        let y = try await istemci().yanit(YapayIstek(kullanici: "x"))
        #expect(y.model == "gemini-3.8-flash")
        #expect(y.kaynakEtiketi == "Gemini (bulut)")
        let urller = SaplamaProtokol.istekler.map { $0.url!.path }
        #expect(urller == ["/v1/messages", "/v1/messages", "/v1/chat/completions"])
    }

    @Test func akistaHataOlayiSiradakineDuser() async throws {
        SaplamaProtokol.sifirla { r in
            let govde = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
            if govde.contains("\"claude-") { return .init(tur: "text/event-stream", govde: "data: {\"error\": {\"message\": \"model desteklenmiyor\"}}\n\ndata: [DONE]\n\n") }
            return .init(tur: "text/event-stream", govde: "data: {\"choices\":[{\"delta\":{\"content\":\"Parça\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" 2\"}}]}\n\ndata: [DONE]\n\n")
        }
        let y = try await istemci().yanit(YapayIstek(kullanici: "x"))
        #expect(y.metin == "Parça 2")
    }

    @Test func yetkisizseDurur() async {
        SaplamaProtokol.sifirla { _ in .init(kod: 401, govde: "{\"error\":\"yetkisiz\"}") }
        await #expect(throws: KagitHata.self) { try await istemci().yanit(YapayIstek(kullanici: "x")) }
        #expect(SaplamaProtokol.istekler.count == 1)
    }

    @Test func hepsiBasarisizsaAciklayiciHata() async {
        SaplamaProtokol.sifirla { _ in .init(kod: 503, govde: "{}") }
        do {
            _ = try await istemci().yanit(YapayIstek(kullanici: "x"))
            Issue.record("hata bekleniyordu")
        } catch {
            #expect(SaplamaProtokol.istekler.count == 4)
            #expect((error as? KagitHata)?.errorDescription?.contains("Hiçbir model") == true)
        }
    }

    @Test func modelSiralamasi() {
        #expect(YapayModeller.siralama(secili: "gpt-5.5") == ["gpt-5.5", "claude-sonnet-5-5", "claude-opus-5-5", "gemini-3.8-flash"])
        #expect(YapayModeller.siralama(secili: "ozel").first == "ozel")
    }
}

final class Birikim: @unchecked Sendable {
    private let k = NSLock()
    private var s = ""
    func ekle(_ x: String) { k.lock(); s += x; k.unlock() }
    var deger: String { k.lock(); defer { k.unlock() }; return s }
}

// MARK: - Kaynak seçimi

@Suite struct KaynakSecimiTestleri {
    func yz(_ t: KaynakTercihi, cihaz: Bool, bulut: Bool = true, anahtar: String? = "k") -> YapayZeka {
        YapayZeka(YapayYapilandirma(tercih: t, bulutAcik: bulut, kok: "https://ornek.test/v1", anahtar: anahtar), cihazKullanilabilir: cihaz)
    }

    @Test func otomatikCihazYoksaBulut() throws {
        #expect(try yz(.otomatik, cihaz: false).birincil().etiket == "Claude (bulut)")
        #expect(try yz(.otomatik, cihaz: true).birincil().etiket == "Cihaz")
    }

    @Test func yalnizCihazDestekYoksaAciklayiciHata() {
        let e = yz(.yalnizCihaz, cihaz: false).kullanilamazNedeni
        #expect(e?.contains("Apple Intelligence") == true)
    }

    @Test func bulutKapaliysaAciklayiciHata() {
        #expect(yz(.otomatik, cihaz: false, bulut: false).kullanilamazNedeni?.contains("kapalı") == true)
        #expect(yz(.yalnizBulut, cihaz: true, bulut: false).kullanilamazNedeni?.contains("kapalı") == true)
        #expect(yz(.yalnizBulut, cihaz: true, anahtar: nil).kullanilamazNedeni?.contains("anahtarı") == true)
        #expect(yz(.yalnizBulut, cihaz: true).kullanilamazNedeni == nil)
    }
}

// MARK: - Görevler

@Suite struct YapayGorevTestleri {
    let kisaMetin: [Int: String] = [1: "Hücre canlıların temel birimidir.", 2: "Çekirdek kalıtım bilgisini taşır."]

    @Test func kisaBelgeTekCagriylaOzetlenir() async throws {
        let sayac = Birikim()
        let kaynak = SahteKaynak { istek in
            sayac.ekle("x")
            #expect(istek.mesajlar[0].icerik.contains("madde"))
            return "- Özet maddesi"
        }
        let o = try await Ozetleyici.ozetle(sayfalar: kisaMetin, stil: .maddeler, yz: YapayZeka(kaynak: kaynak))
        #expect(o.metin == "- Özet maddesi")
        #expect(sayac.deger == "x")
    }

    @Test func uzunBelgeMapReduce() async throws {
        let uzun = Dictionary(uniqueKeysWithValues: (1...40).map { ($0, "Sayfa \($0) içeriği: " + String(repeating: "hücre bölünmesi mitoz mayoz ", count: 40)) })
        // Küçük bağlamlı kaynak: parçalama zorunlu
        struct Kucuk: YapayKaynak {
            let sayac: Birikim
            var etiket: String { "Küçük" }
            var baglamSiniri: Int { 6_000 }
            func yanit(_ istek: YapayIstek, akis: YapayAkisi?) async throws -> YapayYaniti {
                sayac.ekle("x")
                #expect(istek.mesajlar[0].icerik.count < 7_000)
                return YapayYaniti(metin: "kısa not", model: "k", kaynakEtiketi: "Küçük")
            }
        }
        let sayac = Birikim()
        let ilerleme = Birikim()
        let o = try await Ozetleyici.ozetle(sayfalar: uzun, stil: .ayrintili, yz: YapayZeka(kaynak: Kucuk(sayac: sayac)),
                                            ilerleme: { _ in ilerleme.ekle("i") })
        #expect(o.metin == "kısa not")
        #expect(sayac.deger.count > 3)       // birden çok çağrı (harita + indirge)
        #expect(!ilerleme.deger.isEmpty)
    }

    @Test func bosBelgeHata() async {
        await #expect(throws: KagitHata.self) {
            _ = try await Ozetleyici.ozetle(sayfalar: [:], stil: .kisa, yz: YapayZeka(kaynak: SahteKaynak { _ in "" }))
        }
    }

    @Test func ceviriSayfaIsaretcileriniKorur() async throws {
        let kaynak = SahteKaynak { istek in
            // Girdideki işaretçileri aynen koruyup İngilizce metin yaz
            let g = istek.mesajlar[0].icerik
            var cikti = ""
            for n in 1...2 where g.contains("<<<SAYFA \(n)>>>") { cikti += "<<<SAYFA \(n)>>>\nEnglish page \(n)\n" }
            return cikti
        }
        let r = try await Cevirmen.cevir(sayfalar: kisaMetin, hedef: .ingilizce, yz: YapayZeka(kaynak: kaynak))
        #expect(r.sayfalar[1] == "English page 1")
        #expect(r.sayfalar[2] == "English page 2")
    }

    @Test func isaretciAyirma() {
        let s = Cevirmen.isaretciyleAyir("<<<SAYFA 3>>>\nbir\niki\n<<<SAYFA 4>>>\nüç")
        #expect(s[3] == "bir\niki" && s[4] == "üç")
    }
}

@Suite struct SoruUretimTestleri {
    let metin: [Int: String] = [1: "Hücre zarı fosfolipit çift tabakadan oluşur. Seçici geçirgendir. Ribozomlar protein sentezler."]

    static let jsonYaniti = """
    Elbette! İşte sorular:
    ```json
    {"sorular": [
      {"tur":"coktan_secmeli","soru":"Hücre zarının temel yapısı hangisidir?","secenekler":["A) Fosfolipit çift tabaka","B) Selüloz","C) Nişasta","D) Glikojen","E) Kitin"],"dogru":"A","aciklama":"Zar fosfolipitlidir."},
      {"tur":"coktan_secmeli","soru":"Eksik şıklı soru burada yer alıyor","secenekler":["bir","iki","üç"],"dogru":"B"},
      {"tur":"coktan_secmeli","soru":"Yanlış harfli soru metni burada","secenekler":["a1","b2","c3","d4","e5"],"dogru":"Z"}
    ]}
    ```
    """

    @Test func ayristirmaGecersizleriEler() throws {
        let s = try SoruDogrulama.ayristir(Self.jsonYaniti, varsayilanTur: .coktanSecmeli)
        #expect(s.count == 1)
        #expect(s[0].secenekler == ["Fosfolipit çift tabaka", "Selüloz", "Nişasta", "Glikojen", "Kitin"])
        #expect(s[0].dogru == "A")
    }

    @Test func turDogrulamalari() throws {
        let j = """
        [{"tur":"dogru_yanlis","soru":"Ribozomlar zarlı organeldir.","dogru":"yanlış"},
         {"tur":"dogru_yanlis","soru":"Belirsiz cevaplı ifade metni","dogru":"belki"},
         {"tur":"bosluk_doldurma","soru":"Fotosentez ......... organelinde olur.","dogru":"kloroplast"},
         {"tur":"bosluk_doldurma","soru":"Boşluğu olmayan cümle yazılmış","dogru":"x"},
         {"tur":"eslestirme","soru":"Eşleştiriniz.","ciftler":[{"sol":"a","sag":"1"},{"sol":"b","sag":"2"},{"sol":"c","sag":"3"}]},
         {"tur":"eslestirme","soru":"Az çiftli eşleştirme.","ciftler":[{"sol":"a","sag":"1"}]},
         {"tur":"acik_uclu","soru":"Mitozun evrelerini yazınız.","dogru":"Profaz, metafaz, anafaz, telofaz"}]
        """
        let s = try SoruDogrulama.ayristir(j, varsayilanTur: .acikUclu)
        #expect(s.map(\.tur) == [.dogruYanlis, .bosluk, .eslestirme, .acikUclu])
        #expect(s[0].dogru == "Yanlış")
        #expect(s[1].metin.contains("________"))
    }

    @Test func uretimAkisi() async throws {
        let sayac = Birikim()
        let kaynak = SahteKaynak { istek in
            sayac.ekle("x")
            let g = istek.mesajlar[0].icerik
            #expect(g.contains("9. sınıf") && g.contains("ÇOKTAN SEÇMELİ"))
            return Self.jsonYaniti
        }
        let istek = SoruIstegi(adetler: [.coktanSecmeli: 1], zorluk: .orta, sinif: "9. sınıf", konu: "hücre zarı")
        let s = try await SoruUretici.uret(sayfalar: metin, istek: istek, yz: YapayZeka(kaynak: kaynak))
        #expect(s.count == 1)
        #expect(sayac.deger == "x")
    }

    @Test func eksikSoruIcinYenidenDener() async throws {
        let sayac = Birikim()
        let kaynak = SahteKaynak { _ in
            sayac.ekle("x")
            return Self.jsonYaniti
        }
        // 2 soru isteniyor, her çağrı yalnız 1 geçerli üretiyor (ikincide aynı metin)
        let istek = SoruIstegi(adetler: [.coktanSecmeli: 2])
        let s = try await SoruUretici.uret(sayfalar: metin, istek: istek, yz: YapayZeka(kaynak: kaynak))
        #expect(sayac.deger.count == 2)
        #expect(s.count >= 1)
    }

    @Test func hicGecerliYoksaHata() async {
        let kaynak = SahteKaynak { _ in "{\"sorular\": []}" }
        await #expect(throws: KagitHata.self) {
            _ = try await SoruUretici.uret(sayfalar: metin, istek: SoruIstegi(adetler: [.dogruYanlis: 3]), yz: YapayZeka(kaynak: kaynak))
        }
    }
}

// MARK: - Canlı (KAGIT_CANLI=1)

@Suite(.enabled(if: ProcessInfo.processInfo.environment["KAGIT_CANLI"] == "1")) struct CanliVekilTestleri {
    func yz() throws -> YapayZeka {
        let anahtar = try #require(ProcessInfo.processInfo.environment["KAGIT_VEKIL_ANAHTARI"])
        return YapayZeka(YapayYapilandirma(tercih: .yalnizBulut, bulutAcik: true,
                                           kok: "https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/dersdas/claude/v1", anahtar: anahtar),
                         cihazKullanilabilir: false)
    }

    @Test func baglanti() async throws {
        let y = try await yz().sina()
        #expect(!y.metin.isEmpty)
        print("CANLI sina: model=\(y.model) etiket=\(y.kaynakEtiketi)")
    }

    @Test func ozet() async throws {
        let o = try await Ozetleyici.ozetle(sayfalar: [1: "Mitokondri hücrenin enerji santralidir. ATP üretimi iç zarda gerçekleşir. Kloroplast ise fotosentez yapar."],
                                            stil: .kisa, yz: try yz())
        #expect(o.metin.count > 20)
        print("CANLI özet: \(o.metin.prefix(200))")
    }

    @Test func soruUretimi() async throws {
        let m: [Int: String] = [1: "Hücre zarı fosfolipit çift tabakadan oluşur; proteinler zara gömülüdür. Seçici geçirgendir. Difüzyon, maddelerin çok yoğundan az yoğuna geçişidir. Osmoz suyun yarı geçirgen zardan geçişidir. Aktif taşıma ATP harcar."]
        let s = try await SoruUretici.uret(sayfalar: m, istek: SoruIstegi(adetler: [.coktanSecmeli: 2, .dogruYanlis: 1], zorluk: .orta, sinif: "9. sınıf"), yz: try yz())
        #expect(s.count >= 2)
        print("CANLI sorular: \(s.count) adet; ilk: \(s[0].metin)")
        let pdf = SinavPDF.sinav(sorular: s, baslik: OkulBasligi(okulAdi: "Deneme"), sinavAdi: "Canlı")
        #expect(PDFDocument(data: pdf)?.pageCount ?? 0 >= 1)
    }

    @Test func ceviri() async throws {
        let r = try await Cevirmen.cevir(sayfalar: [1: "Mitokondri hücrenin enerji santralidir."], hedef: .ingilizce, yz: try yz())
        #expect((r.sayfalar[1] ?? "").lowercased().contains("mitochondri"))
        print("CANLI çeviri: \(r.sayfalar[1] ?? "")")
    }
}
