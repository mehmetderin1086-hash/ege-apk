import Foundation
import FoundationModels
import Testing
@testable import Asistan

/// P4.5: MCP 2.0 (oturum önbelleği, dinamik araçlar, OAuth 2.1 + PKCE saf parçaları) ve okul kütüphanesi aracı.
/// Ağa, izne ya da gerçek modele çıkmaz.
@MainActor
@Suite("P4.5 okul köprüleri ve MCP 2.0")
struct Gelistirme_P4_5_McpIkiTestleri {

    // MARK: Ad kuralı ve şema çevirici

    @Test func adlandirTurkceVeBosluguAsciiyeCevirir() {
        #expect(McpSemaCevirici.adlandir(sunucu: "Öğretmen Çantası", arac: "günün dersleri") == "mcp_ogretmen_cantasi_gunun_dersleri")
        #expect(McpSemaCevirici.adlandir(sunucu: "ogretmen-cantasi", arac: "yoklama_oku") == "mcp_ogretmen_cantasi_yoklama_oku")
        #expect(McpSemaCevirici.adlandir(sunucu: "İzmir Şube", arac: "ÇIKIŞ") == "mcp_izmir_sube_cikis")
        let uzun = McpSemaCevirici.adlandir(sunucu: String(repeating: "a", count: 40), arac: String(repeating: "b", count: 40))
        #expect(uzun.count <= 64)
        #expect(uzun.hasPrefix("mcp_aaaa"))
        #expect(!uzun.hasSuffix("_"))
        #expect(uzun.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") })
    }

    @Test func duzSemaCevrilirIcIceVeRefNil() throws {
        let duz = #"{"type":"object","properties":{"sorgu":{"type":"string","description":"aranan"},"adet":{"type":"integer"},"oran":{"type":"number"},"acik":{"type":"boolean"},"etiketler":{"type":"array","items":{"type":"string"}},"tur":{"type":"string","enum":["a","b"]},"secim":{"anyOf":[{"const":"x"},{"const":"y"}]},"bos":{"type":["string","null"]}},"required":["sorgu"]}"#
        let s = try #require(McpSemaCevirici.sema(duz, ad: "mcp_a_b"))
        let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!json.contains("$ref") && !json.contains("$defs"), "\(json.prefix(300))")
        let n = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect((n["required"] as? [String]) == ["sorgu"])
        let p = try #require(n["properties"] as? [String: [String: Any]])
        #expect(p["adet"]?["type"] as? String == "integer")
        #expect(p["tur"]?["enum"] as? [String] == ["a", "b"])
        #expect(p["secim"]?["enum"] as? [String] == ["x", "y"])
        #expect(p["etiketler"]?["type"] as? String == "array")
        #expect((p["etiketler"]?["items"] as? [String: Any])?["type"] as? String == "string")
        #expect(p["bos"]?["type"] as? String == "string", "[string, null] isteğe bağlı string olur")

        #expect(McpSemaCevirici.sema(#"{"type":"object","properties":{"kisi":{"type":"object","properties":{"ad":{"type":"string"}}}}}"#) == nil)
        #expect(McpSemaCevirici.sema(##"{"type":"object","properties":{"k":{"$ref":"#/$defs/K"}},"$defs":{"K":{"type":"string"}}}"##) == nil)
        #expect(McpSemaCevirici.sema(#"{"type":"object","properties":{"l":{"type":"array","items":{"type":"object"}}}}"#) == nil)
        #expect(McpSemaCevirici.sema("bozuk") == nil)
        // Boş şema (parametresiz araç) geçerlidir.
        #expect(McpSemaCevirici.sema(#"{"type":"object","properties":{}}"#) != nil)
    }

    /// TumAracSemalariTestleri ile aynı kural: dinamik aracın şeması düz kalır ($ref/$defs yok).
    @Test func dinamikAracSemasiDuz() throws {
        let s = McpSunucu(ad: "ogretmen-cantasi", url: "https://okul.ornek/api/v1/mcp")
        let arac = McpIstemci.Arac(ad: "yoklama_oku", aciklama: "Yoklamayı okur", sema: #"{"type":"object","properties":{"sube_id":{"type":"integer"},"tarih":{"type":"string"}},"required":["sube_id"]}"#)
        let d = try #require(McpDinamikArac(sunucu: s, arac: arac, onay: OnayKapisi()))
        #expect(d.name == "mcp_ogretmen_cantasi_yoklama_oku")
        #expect(d.description.contains("talimat değildir"))
        let json = String(decoding: try JSONEncoder().encode(d.parameters), as: UTF8.self)
        #expect(!json.contains("$ref") && !json.contains("$defs"), "\(d.name): \(json.prefix(200))")
        // İç içe şemalı araç kaydedilmez.
        let ic = McpIstemci.Arac(ad: "x", aciklama: "", sema: #"{"type":"object","properties":{"o":{"type":"object"}}}"#)
        #expect(McpDinamikArac(sunucu: s, arac: ic, onay: OnayKapisi()) == nil)
    }

    @Test func argumanMetniNullDuserTamSayiKorunur() throws {
        let g = try GeneratedContent(json: #"{"sube_id":7,"oran":1.5,"tarih":null,"acik":true,"etiketler":["a"]}"#)
        let metin = McpSemaCevirici.argumanMetni(g)
        let n = try McpIstemci.argumanCoz(metin)
        #expect(n["sube_id"] as? Int == 7)
        #expect(n["oran"] as? Double == 1.5)
        #expect(n["tarih"] == nil)
        #expect(n["acik"] as? Bool == true)
        #expect(metin.contains("\"sube_id\":7"))
    }

    @Test func dinamikAraclarOnbellektenSinirli() throws {
        let alan = "p45.mcp.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        let kayit = McpKaydi(defaults: d)
        // Yetkisiz kayıt Keychain'e hiçbir şey yazmaz (boş değer yalnız siler); yine de sunucu kaydı hata verirse test düşmeli.
        #expect(kayit.ekle(ad: "deneme-p45", url: "https://okul.ornek/mcp"), "ekle başarısız: \(kayit.sonHata ?? "-")")
        let s = try #require(kayit.bul("deneme-p45"))
        defer { kayit.sil(s.id) }
        let duz = #"{"type":"object","properties":{"q":{"type":"string"}}}"#
        let l = (0..<12).map { McpIstemci.Arac(ad: "arac\($0)", aciklama: "", sema: duz) } + [McpIstemci.Arac(ad: "ic", aciklama: "", sema: #"{"properties":{"o":{"type":"object"}}}"#)]
        kayit.araclariSakla(l, id: s.id)
        let dinamik = kayit.dinamikAraclar(onay: OnayKapisi())
        #expect(dinamik.count == McpKaydi.sunucuBasinaDinamik)
        #expect(dinamik.allSatisfy { $0.name.hasPrefix("mcp_deneme_p45_") })
        // Kalıcı önbellek yeniden açılışta okunur; sil temizler.
        #expect(McpKaydi(defaults: d).aracOnbellegi[s.id]?.count == 13)
        kayit.sil(s.id)
        #expect(d.data(forKey: McpKaydi.aracAnahtari(s.id)) == nil)
        #expect(kayit.dinamikAraclar(onay: OnayKapisi()).isEmpty)
    }

    @Test func aracListesiCozulurVeCodable() throws {
        let sonuc: [String: Any] = ["tools": [["name": "bugun", "description": "Günün dersleri", "inputSchema": ["type": "object", "properties": [:] as [String: Any]]], ["description": "adsız"]]]
        let l = McpIstemci.aracListesiCoz(sonuc)
        #expect(l.map(\.ad) == ["bugun"])
        let geri = try JSONDecoder().decode([McpIstemci.Arac].self, from: try JSONEncoder().encode(l))
        #expect(geri == l)
    }

    // MARK: Başlıklar ve oturum

    @Test func ekBaslikAuthorizationYanindaGider() {
        var s = McpSunucu(ad: "c", url: "https://a.ornek/mcp", yetki: "Basic eDp5")
        s.ekBaslik = "X-Api-Token"; s.ekDeger = "gizli"
        let b = McpIstemci.basliklar(s, oturum: "o1", surum: "2025-06-18")
        #expect(b["Authorization"] == "Basic eDp5")
        #expect(b["X-Api-Token"] == "gizli")
        #expect(b["Mcp-Session-Id"] == "o1")
        #expect(b["MCP-Protocol-Version"] == "2025-06-18")
        s.ekBaslik = "Host"
        #expect(McpIstemci.basliklar(s, oturum: nil, surum: "x")["Host"] == nil)
        #expect(McpKaydi.ekBaslikGecerli("X-Api-Token"))
        #expect(!McpKaydi.ekBaslikGecerli("Authorization"))
        #expect(!McpKaydi.ekBaslikGecerli("X Api"))
        #expect(!McpKaydi.ekBaslikGecerli("X-Çanta"))
    }

    @Test func oturumDefteriSureDolunca404teGecersiz() async {
        let defter = McpOturumDefteri()
        let id = UUID(), url = "https://a.ornek/mcp", t0 = Date(timeIntervalSince1970: 1_000_000)
        await defter.oturumYaz(id, oturum: "s1", surum: "2025-06-18", url: url, simdi: t0)
        #expect(await defter.oturum(id, url: url, simdi: t0.addingTimeInterval(60))?.oturum == "s1")
        #expect(await defter.oturum(id, url: "https://b.ornek/mcp", simdi: t0.addingTimeInterval(60)) == nil, "adres değişince kullanılmaz")
        await defter.oturumYaz(id, oturum: "s1", surum: "2025-06-18", url: url, simdi: t0)
        #expect(await defter.oturum(id, url: url, simdi: t0.addingTimeInterval(McpOturumDefteri.oturumOmru + 1)) == nil, "15 dk sonra boş")
        await defter.oturumYaz(id, oturum: "s2", surum: "2025-06-18", url: url, simdi: t0)
        await defter.gecersizKil(id)
        #expect(await defter.oturum(id, url: url, simdi: t0) == nil)

        let l = [McpIstemci.Arac(ad: "a", aciklama: "", sema: "{}")]
        await defter.araclarYaz(id, url: url, l, simdi: t0)
        #expect(await defter.araclar(id, url: url, simdi: t0.addingTimeInterval(9 * 60)) == l)
        #expect(await defter.araclar(id, url: url, simdi: t0.addingTimeInterval(McpOturumDefteri.aracOmru + 1)) == nil)

        // 404 (oturum gönderilmişken) ya da "session" geçen 400 oturum düşmesidir.
        #expect(McpIstemci.oturumDustuMu(kod: 404, govde: Data(), oturumGonderildi: true))
        #expect(!McpIstemci.oturumDustuMu(kod: 404, govde: Data(), oturumGonderildi: false))
        #expect(McpIstemci.oturumDustuMu(kod: 400, govde: Data("Invalid Session ID".utf8), oturumGonderildi: true))
        #expect(!McpIstemci.oturumDustuMu(kod: 400, govde: Data("bad params".utf8), oturumGonderildi: true))
        #expect(McpIstemci.Hata.yetkiGerekli(nil).errorDescription?.contains("401") == true)
    }

    // MARK: OAuth 2.1 + PKCE

    @Test func pkceRfc7636EkBVektoru() {
        #expect(McpOAuth.meydanOkuma("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let p = McpOAuth.pkce()
        #expect((43...128).contains(p.dogrulayici.count))
        #expect(p.dogrulayici.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(p.meydanOkuma == McpOAuth.meydanOkuma(p.dogrulayici))
        #expect(McpOAuth.pkce().dogrulayici != p.dogrulayici)
    }

    @Test func kaynakMetaAdresiBasliktanVeYedek() throws {
        let sunucu = try #require(URL(string: "https://okul.ornek/api/v1/mcp"))
        let w = #"Bearer error="invalid_token", resource_metadata="https://okul.ornek/.well-known/oauth-protected-resource/api/v1/mcp""#
        #expect(McpOAuth.kaynakMetaAdresi(wwwAuthenticate: w, sunucu: sunucu)?.absoluteString == "https://okul.ornek/.well-known/oauth-protected-resource/api/v1/mcp")
        #expect(McpOAuth.kaynakMetaAdresi(wwwAuthenticate: nil, sunucu: sunucu)?.absoluteString == "https://okul.ornek/.well-known/oauth-protected-resource/api/v1/mcp")
        // Güvensiz (http, yerel değil) adres başlıktan alınmaz; yedeğe düşülür.
        let kotu = #"Bearer resource_metadata="http://saldirgan.ornek/meta""#
        #expect(McpOAuth.kaynakMetaAdresi(wwwAuthenticate: kotu, sunucu: sunucu)?.host == "okul.ornek")
        #expect(McpOAuth.parametre("resource_metadata", "Bearer resource_metadata=https://a.ornek/m, scope=x") == "https://a.ornek/m")
        let issuer = try #require(URL(string: "https://kimlik.ornek/kiraci"))
        #expect(McpOAuth.yetkiSunucusuMetaAdresleri(issuer).first?.absoluteString == "https://kimlik.ornek/.well-known/oauth-authorization-server/kiraci")
    }

    @Test func s256DesteklemeyenSunucuReddedilir() throws {
        let s256siz = Data(#"{"authorization_endpoint":"https://k.ornek/yetki","token_endpoint":"https://k.ornek/token","code_challenge_methods_supported":["plain"]}"#.utf8)
        #expect(throws: McpOAuth.Hata.s256Yok) { try McpOAuth.sunucuMetasiCoz(s256siz) }
        let alansiz = Data(#"{"authorization_endpoint":"https://k.ornek/yetki","token_endpoint":"https://k.ornek/token"}"#.utf8)
        #expect(throws: McpOAuth.Hata.s256Yok) { try McpOAuth.sunucuMetasiCoz(alansiz) }
        let httpli = Data(#"{"authorization_endpoint":"http://k.ornek/yetki","token_endpoint":"https://k.ornek/token","code_challenge_methods_supported":["S256"]}"#.utf8)
        #expect(throws: McpOAuth.Hata.adres) { try McpOAuth.sunucuMetasiCoz(httpli) }
        let iyi = Data(#"{"authorization_endpoint":"https://k.ornek/yetki","token_endpoint":"https://k.ornek/token","registration_endpoint":"https://k.ornek/kayit","code_challenge_methods_supported":["S256"]}"#.utf8)
        let m = try McpOAuth.sunucuMetasiCoz(iyi)
        #expect(m.kayitUcu?.absoluteString == "https://k.ornek/kayit")

        let p = McpOAuth.Pkce(dogrulayici: "v", meydanOkuma: "c+d")
        let adres = try #require(McpOAuth.yetkiAdresi(meta: m, istemciKimligi: "ist", pkce: p, durum: "d1", kaynak: "https://okul.ornek/mcp", kapsam: nil))
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: adres, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["redirect_uri"] == "asistan://mcp-oauth")
        #expect(q["resource"] == "https://okul.ornek/mcp")
        #expect(q["state"] == "d1" && q["client_id"] == "ist")
        #expect(adres.absoluteString.contains("c%2Bd"), "+ kaçırılır")
        #expect(q["scope"] == nil)
    }

    @Test func donusCozStateUyusmazligindaHata() throws {
        let iyi = try #require(URL(string: "asistan://mcp-oauth?code=kod123&state=abc"))
        #expect(try McpOAuth.donusCoz(url: iyi, beklenenDurum: "abc") == "kod123")
        #expect(throws: McpOAuth.Hata.durumUyusmuyor) { try McpOAuth.donusCoz(url: iyi, beklenenDurum: "baska") }
        let statesiz = try #require(URL(string: "asistan://mcp-oauth?code=kod123"))
        #expect(throws: McpOAuth.Hata.durumUyusmuyor) { try McpOAuth.donusCoz(url: statesiz, beklenenDurum: "abc") }
        let red = try #require(URL(string: "asistan://mcp-oauth?error=access_denied&state=abc"))
        #expect(throws: McpOAuth.Hata.kodYok("access_denied")) { try McpOAuth.donusCoz(url: red, beklenenDurum: "abc") }
        let baskaAdres = try #require(URL(string: "asistan://sor?code=x&state=abc"))
        #expect(throws: (any Error).self) { try McpOAuth.donusCoz(url: baskaAdres, beklenenDurum: "abc") }
    }

    @Test func tokenGovdesiKodlamasi() {
        let g = String(decoding: McpOAuth.tokenGovdesi([("a", "b c"), ("x", "ç+&=/")]), as: UTF8.self)
        #expect(g == "a=b%20c&x=%C3%A7%2B%26%3D%2F")
        let k = String(decoding: McpOAuth.kodGovdesi(kod: "K", dogrulayici: "V", istemciKimligi: "I", kaynak: "https://o.ornek/mcp"), as: UTF8.self)
        #expect(k.hasPrefix("grant_type=authorization_code&code=K&redirect_uri=asistan%3A%2F%2Fmcp-oauth"))
        #expect(k.contains("code_verifier=V") && k.contains("resource=https%3A%2F%2Fo.ornek%2Fmcp"))
        let y = String(decoding: McpOAuth.yenilemeGovdesi(yenileme: "R", istemciKimligi: "I", kaynak: nil), as: UTF8.self)
        #expect(y == "grant_type=refresh_token&refresh_token=R&client_id=I")
    }

    @Test func belirtecCozulurYenilemeKorunur() throws {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let b = try McpOAuth.belirtecCoz(Data(#"{"access_token":"A1","token_type":"Bearer","expires_in":3600,"refresh_token":"R1"}"#.utf8),
                                         simdi: t0, onceki: nil, istemciKimligi: "I", tokenUcu: "https://k.ornek/token", kaynak: "https://o.ornek/mcp")
        #expect(b.erisim == "A1" && b.yenileme == "R1")
        #expect(b.bitis == t0.addingTimeInterval(3600))
        #expect(!b.suresiDoldu(t0) && b.suresiDoldu(t0.addingTimeInterval(3590)))
        let yeni = try McpOAuth.belirtecCoz(Data(#"{"access_token":"A2","token_type":"bearer"}"#.utf8), simdi: t0, onceki: b,
                                            istemciKimligi: "I", tokenUcu: b.tokenUcu, kaynak: b.kaynak)
        #expect(yeni.yenileme == "R1", "yeni refresh gelmezse eskisi korunur")
        #expect(throws: McpOAuth.Hata.self) {
            try McpOAuth.belirtecCoz(Data(#"{"error":"invalid_grant"}"#.utf8), onceki: nil, istemciKimligi: "I", tokenUcu: "t", kaynak: nil)
        }
    }

    // MARK: Politika ve görev günlüğü

    @Test func dinamikMcpAraciPolitikayiMcpdenDevralir() throws {
        let alan = "p45.ajan.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        let dosya = FileManager.default.temporaryDirectory.appendingPathComponent("p45-ajan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: dosya) }
        let defter = AjanDefteri(defaults: d, dosya: dosya)
        #expect(defter.politika("mcp_x_y") == .otomatik)
        defter.politikaAta("mcp", .sor)
        #expect(defter.politika("mcp_x_y") == .sor)
        #expect(defter.politika("mcpx") == .otomatik, "önek 'mcp_' olmalı")
        defter.politikaAta("mcp_x_y", .kapali)
        #expect(defter.politika("mcp_x_y") == .kapali, "kendi kaydı önce gelir")
    }

    /// Kayıt ihtiyacı (GorevGunlugu'na `mcp_` öneki) bütünleştirici tarafından uygulanınca geçer.
    @Test func dinamikMcpCiktisiDisIcerikSayilir() {
        #expect(GorevGunlugu.disIcerikGetirdi("mcp_a_b", argumanlar: "", sonuc: McpAraci.disVeri("a", "veri")))
        #expect(!GorevGunlugu.disIcerikGetirdi("mcp_a_b", argumanlar: "", sonuc: "Kullanıcı onaylamadı; çağrı yapılmadı."))
        #expect(GorevGunlugu.yanEtkiliMi("mcp_a_b", islem: nil))
    }

    // MARK: Kütüphane

}
