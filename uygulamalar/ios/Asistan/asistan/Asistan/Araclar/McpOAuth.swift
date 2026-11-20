import Foundation
import CryptoKit
import Security
import AuthenticationServices
import UIKit

/// P4.5: MCP yetkilendirmesi (OAuth 2.1 + PKCE S256, RFC 9728 kaynak metası, RFC 8414 sunucu metası,
/// RFC 7591 dinamik istemci kaydı, RFC 8707 `resource`). Saf parçalar burada ve test edilir; akışı
/// `McpOAuthOturumu` yürütür. Belirteçler Keychain'de (`McpYetkiKasasi`, hesap "<id>.oauth"); hiçbiri günlüğe yazılmaz.
nonisolated enum McpOAuth {
    static let donusAdresi = "asistan://mcp-oauth"
    static let donusSemasi = "asistan"
    static let istemciAdi = "Asistan"

    enum Hata: LocalizedError, Equatable {
        case meta(String), s256Yok, kayitYok, durumUyusmuyor, kodYok(String?), belirtec(String), adres, iptal, kasa
        var errorDescription: String? {
            switch self {
            case .meta(let s): "Yetki sunucusu bilgisi alınamadı: \(s)"
            case .s256Yok: "Yetki sunucusu PKCE S256'yı desteklemiyor; güvenli bağlantı kurulamaz."
            case .kayitYok: "Yetki sunucusu dinamik istemci kaydını desteklemiyor."
            case .durumUyusmuyor: "Dönüş adresindeki durum (state) uyuşmuyor; istek reddedildi."
            case .kodYok(let h): h.map { "Yetki verilmedi: \($0)" } ?? "Dönüş adresinde yetki kodu yok."
            case .belirtec(let s): "Belirteç alınamadı: \(s)"
            case .adres: "Yetki uç adresi güvenli değil (yalnız https)."
            case .iptal: "Giriş iptal edildi."
            case .kasa: "Belirteç güvenli depoya (Keychain) yazılamadı."
            }
        }
    }

    // MARK: PKCE (RFC 7636)
    struct Pkce: Equatable, Sendable { let dogrulayici: String; let meydanOkuma: String }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func meydanOkuma(_ dogrulayici: String) -> String { base64url(Data(SHA256.hash(data: Data(dogrulayici.utf8)))) }
    static func rastgele(_ bayt: Int = 32) -> String {
        var b = [UInt8](repeating: 0, count: bayt)
        if SecRandomCopyBytes(kSecRandomDefault, bayt, &b) != errSecSuccess {
            // Çok olası değil; yine de tahmin edilemez kaynak: SystemRandomNumberGenerator.
            var g = SystemRandomNumberGenerator(); for i in b.indices { b[i] = UInt8.random(in: 0...255, using: &g) }
        }
        return base64url(Data(b))
    }
    /// 32 rastgele bayt → 43 karakterlik base64url doğrulayıcı.
    static func pkce() -> Pkce { let v = rastgele(32); return Pkce(dogrulayici: v, meydanOkuma: meydanOkuma(v)) }

    // MARK: Meta keşfi
    /// `WWW-Authenticate: Bearer resource_metadata="…"` çözülür; yoksa (ya da güvensizse) sunucu kökünde
    /// `/.well-known/oauth-protected-resource{yol}` (RFC 9728 §3.1).
    static func kaynakMetaAdresi(wwwAuthenticate: String?, sunucu: URL) -> URL? {
        if let w = wwwAuthenticate, let d = parametre("resource_metadata", w), McpIstemci.oauthAdresiGecerli(d), let u = URL(string: d) { return u }
        guard var b = URLComponents(url: sunucu, resolvingAgainstBaseURL: false), b.host != nil else { return nil }
        let yol = b.path == "/" ? "" : b.path
        b.path = "/.well-known/oauth-protected-resource" + yol
        b.query = nil; b.fragment = nil
        return b.url
    }
    /// Basit auth-param çözücü: `ad="değer"` ya da `ad=değer`.
    static func parametre(_ ad: String, _ baslik: String) -> String? {
        guard let r = baslik.range(of: ad + "=", options: .caseInsensitive) else { return nil }
        var kalan = baslik[r.upperBound...]
        if kalan.hasPrefix("\"") {
            kalan = kalan.dropFirst()
            guard let son = kalan.firstIndex(of: "\"") else { return nil }
            return String(kalan[..<son])
        }
        return String(kalan.prefix { $0 != "," && $0 != " " })
    }

    struct KaynakMetasi: Equatable, Sendable { let kaynak: String?; let yetkiSunuculari: [URL]; let kapsamlar: [String] }
    static func kaynakMetasiCoz(_ veri: Data) throws -> KaynakMetasi {
        guard let n = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] else { throw Hata.meta("kaynak metası JSON değil") }
        let sunucular = ((n["authorization_servers"] as? [String]) ?? []).filter(McpIstemci.oauthAdresiGecerli).compactMap(URL.init(string:))
        return KaynakMetasi(kaynak: n["resource"] as? String, yetkiSunuculari: sunucular, kapsamlar: (n["scopes_supported"] as? [String]) ?? [])
    }

    /// RFC 8414 + OIDC yedeği: issuer yolu varsa iki biçim de denenir.
    static func yetkiSunucusuMetaAdresleri(_ issuer: URL) -> [URL] {
        guard let k = URLComponents(url: issuer, resolvingAgainstBaseURL: false), let host = k.host, let sema = k.scheme else { return [] }
        let kok = sema + "://" + host + (k.port.map { ":\($0)" } ?? "")
        let yol = k.path == "/" ? "" : k.path
        var l = [kok + "/.well-known/oauth-authorization-server" + yol]
        if !yol.isEmpty { l.append(kok + "/.well-known/openid-configuration" + yol); l.append(kok + yol + "/.well-known/openid-configuration") }
        else { l.append(kok + "/.well-known/openid-configuration") }
        return l.compactMap(URL.init(string:))
    }

    struct SunucuMetasi: Equatable, Sendable { let yetkiUcu: URL; let tokenUcu: URL; let kayitUcu: URL?; let kapsamlar: [String] }
    /// authorization/token uçları https olmalı; `code_challenge_methods_supported` S256 içermiyorsa reddedilir
    /// (MCP yetki şartnamesi: alan yoksa da istemci yetkiyi sürdürmemeli).
    static func sunucuMetasiCoz(_ veri: Data) throws -> SunucuMetasi {
        guard let n = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] else { throw Hata.meta("sunucu metası JSON değil") }
        guard let y = n["authorization_endpoint"] as? String, let t = n["token_endpoint"] as? String else { throw Hata.meta("uç adresleri eksik") }
        guard McpIstemci.oauthAdresiGecerli(y), McpIstemci.oauthAdresiGecerli(t), let yu = URL(string: y), let tu = URL(string: t) else { throw Hata.adres }
        guard ((n["code_challenge_methods_supported"] as? [String]) ?? []).contains("S256") else { throw Hata.s256Yok }
        let kayit = (n["registration_endpoint"] as? String).flatMap { McpIstemci.oauthAdresiGecerli($0) ? URL(string: $0) : nil }
        return SunucuMetasi(yetkiUcu: yu, tokenUcu: tu, kayitUcu: kayit, kapsamlar: (n["scopes_supported"] as? [String]) ?? [])
    }

    // MARK: Yetki isteği ve dönüş
    static func yetkiAdresi(meta: SunucuMetasi, istemciKimligi: String, pkce: Pkce, durum: String, kaynak: String, kapsam: String?) -> URL? {
        guard var k = URLComponents(url: meta.yetkiUcu, resolvingAgainstBaseURL: false) else { return nil }
        var q = k.queryItems ?? []
        q += [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: istemciKimligi),
              URLQueryItem(name: "redirect_uri", value: donusAdresi), URLQueryItem(name: "code_challenge", value: pkce.meydanOkuma),
              URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "state", value: durum),
              URLQueryItem(name: "resource", value: kaynak)]
        if let kapsam, !kapsam.isEmpty { q.append(URLQueryItem(name: "scope", value: kapsam)) }
        k.queryItems = q
        // URLComponents "+" karakterini kaçırmaz; form çözücüler onu boşluk sanar.
        k.percentEncodedQuery = k.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return k.url
    }

    /// Dönüş adresi `asistan://mcp-oauth?code=…&state=…`; state uyuşmazlığı ve `error` reddedilir.
    static func donusCoz(url: URL, beklenenDurum: String) throws -> String {
        let k = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = k?.queryItems ?? []
        func deger(_ ad: String) -> String? { q.first { $0.name == ad }?.value }
        guard url.scheme == donusSemasi, url.host == "mcp-oauth" else { throw Hata.kodYok("beklenmeyen dönüş adresi") }
        guard let d = deger("state"), !beklenenDurum.isEmpty, d == beklenenDurum else { throw Hata.durumUyusmuyor }
        if let e = deger("error") { throw Hata.kodYok(deger("error_description") ?? e) }
        guard let kod = deger("code"), !kod.isEmpty else { throw Hata.kodYok(nil) }
        return kod
    }

    // MARK: Belirteç uç gövdeleri (application/x-www-form-urlencoded)
    static func formKodla(_ s: String) -> String {
        // Yalnız RFC 3986 "unreserved" ASCII karakterler açık kalır (alphanumerics Türkçe harfleri de içerirdi).
        let izinli = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: izinli) ?? s
    }
    static func tokenGovdesi(_ alanlar: [(String, String)]) -> Data {
        Data(alanlar.map { formKodla($0.0) + "=" + formKodla($0.1) }.joined(separator: "&").utf8)
    }
    static func kodGovdesi(kod: String, dogrulayici: String, istemciKimligi: String, kaynak: String) -> Data {
        tokenGovdesi([("grant_type", "authorization_code"), ("code", kod), ("redirect_uri", donusAdresi),
                      ("client_id", istemciKimligi), ("code_verifier", dogrulayici), ("resource", kaynak)])
    }
    static func yenilemeGovdesi(yenileme: String, istemciKimligi: String, kaynak: String?) -> Data {
        var a = [("grant_type", "refresh_token"), ("refresh_token", yenileme), ("client_id", istemciKimligi)]
        if let kaynak { a.append(("resource", kaynak)) }
        return tokenGovdesi(a)
    }
    /// RFC 7591 istemci kaydı gövdesi (genel istemci: gizli anahtar yok).
    static func kayitGovdesi() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["client_name": istemciAdi, "redirect_uris": [donusAdresi],
            "token_endpoint_auth_method": "none", "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"]])) ?? Data()
    }

    // MARK: Belirteç kaydı
    struct Belirtec: Codable, Equatable, Sendable {
        var erisim: String
        var yenileme: String?
        var bitis: Date?
        var istemciKimligi: String
        var tokenUcu: String
        var kaynak: String?
        /// Süresi 60 sn içinde dolacaksa yenilenmeli sayılır.
        func suresiDoldu(_ simdi: Date = .now) -> Bool { bitis.map { $0.timeIntervalSince(simdi) < 60 } ?? false }
    }
    /// Belirteç ucu yanıtı (saf). Yenilemede yeni refresh gelmezse eskisi korunur.
    static func belirtecCoz(_ veri: Data, simdi: Date = .now, onceki: Belirtec?, istemciKimligi: String, tokenUcu: String, kaynak: String?) throws -> Belirtec {
        guard let n = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] else { throw Hata.belirtec("yanıt JSON değil") }
        if let e = n["error"] as? String { throw Hata.belirtec((n["error_description"] as? String) ?? e) }
        guard let a = n["access_token"] as? String, !a.isEmpty else { throw Hata.belirtec("access_token yok") }
        if let tur = n["token_type"] as? String, tur.lowercased() != "bearer" { throw Hata.belirtec("desteklenmeyen tür: \(tur)") }
        let sure = (n["expires_in"] as? Double) ?? (n["expires_in"] as? Int).map(Double.init) ?? (n["expires_in"] as? String).flatMap(Double.init)
        return Belirtec(erisim: a, yenileme: (n["refresh_token"] as? String) ?? onceki?.yenileme, bitis: sure.map { simdi.addingTimeInterval($0) },
                        istemciKimligi: istemciKimligi, tokenUcu: tokenUcu, kaynak: kaynak)
    }

    static func hesap(_ id: UUID) -> String { id.uuidString + ".oauth" }
    static func belirtecOku(_ id: UUID) -> Belirtec? {
        let ham = McpYetkiKasasi.oku(hesap: hesap(id))
        guard !ham.isEmpty else { return nil }
        return try? JSONDecoder().decode(Belirtec.self, from: Data(ham.utf8))
    }
    @discardableResult
    static func belirtecYaz(_ b: Belirtec, id: UUID) -> Bool {
        guard let v = try? JSONEncoder().encode(b) else { return false }
        return McpYetkiKasasi.yaz(String(decoding: v, as: UTF8.self), hesap: hesap(id))
    }
    static func belirtecSil(_ id: UUID) { McpYetkiKasasi.sil(hesap: hesap(id)) }

    // MARK: Ağ
    static func formGonder(_ url: URL, _ govde: Data) async throws -> Data {
        guard McpIstemci.oauthAdresiGecerli(url.absoluteString) else { throw Hata.adres }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"; r.httpBody = govde
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (v, y) = try await URLSession.shared.data(for: r)
        let kod = (y as? HTTPURLResponse)?.statusCode ?? 0
        // 400 gövdesi OAuth hata nesnesidir; belirtecCoz onu okur. Diğer kodlar yalnız sayıyla bildirilir (gövde günlüğe/ekrana gitmez).
        guard (200..<300).contains(kod) || kod == 400 || kod == 401 else { throw Hata.belirtec("HTTP \(kod)") }
        return v
    }
    static func jsonGetir(_ url: URL) async throws -> Data {
        guard McpIstemci.oauthAdresiGecerli(url.absoluteString) else { throw Hata.adres }
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue(McpIstemci.protokolSurumu, forHTTPHeaderField: "MCP-Protocol-Version")
        let (v, y) = try await URLSession.shared.data(for: r)
        guard let kod = (y as? HTTPURLResponse)?.statusCode, (200..<300).contains(kod) else { throw Hata.meta("HTTP \((y as? HTTPURLResponse)?.statusCode ?? 0)") }
        return v
    }

    /// Yenileme belirteci varsa erişim belirtecini yeniler, Keychain'i ve `McpKaydi`'nı günceller; güncel sunucuyu döndürür.
    /// Aynı sunucu için eşzamanlı çağrılar tek yenilemeye iner. Başarısızsa nil (çağıran 401'i olduğu gibi bildirir).
    static func yenile(_ s: McpSunucu) async -> McpSunucu? {
        let id = s.id
        let yetki = await McpOturumDefteri.ortak.tekYenileme(id) {
            guard let b = belirtecOku(id), let r = b.yenileme, let u = URL(string: b.tokenUcu) else { return nil }
            guard let v = try? await formGonder(u, yenilemeGovdesi(yenileme: r, istemciKimligi: b.istemciKimligi, kaynak: b.kaynak)),
                  let yeni = try? belirtecCoz(v, onceki: b, istemciKimligi: b.istemciKimligi, tokenUcu: b.tokenUcu, kaynak: b.kaynak),
                  belirtecYaz(yeni, id: id) else { return nil }
            return "Bearer " + yeni.erisim
        }
        guard let yetki else { return nil }
        var y = s; y.yetki = yetki
        let (ad, url) = (s.ad, s.url)
        await MainActor.run { _ = McpKaydi.ortak.ekle(ad: ad, url: url, yetki: yetki) }
        return y
    }
}

/// OAuth akışı: meta → dinamik istemci kaydı → ASWebAuthenticationSession → kod/belirteç değişimi → Keychain + McpKaydi.
/// Sunum bağlamı protokolü UI aktörlüdür (NS_SWIFT_UI_ACTOR); tamamlayıcı kapanış @Sendable (sistem kuyruğundan çağrılabilir).
@MainActor
final class McpOAuthOturumu: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var oturum: ASWebAuthenticationSession?
    private var capa: ASPresentationAnchor?

    /// Başarıda belirtecin bitiş tarihi (bilinmiyorsa nil) döner; sunucu kaydı `Bearer …` ile güncellenir.
    func baglan(_ s: McpSunucu, wwwAuthenticate: String? = nil) async throws -> Date? {
        guard let sunucuURL = URL(string: s.url) else { throw McpIstemci.Hata.url }
        // 1) Korunan kaynak metası (yoksa yetki sunucusu = MCP sunucusunun kökü).
        var kaynak = s.url
        guard let h = sunucuURL.host, !h.isEmpty,
              var issuer = URL(string: (sunucuURL.scheme ?? "https") + "://" + h + (sunucuURL.port.map { ":\($0)" } ?? "")) else { throw McpIstemci.Hata.url }
        var kapsamlar: [String] = []
        if let km = McpOAuth.kaynakMetaAdresi(wwwAuthenticate: wwwAuthenticate, sunucu: sunucuURL),
           let v = try? await McpOAuth.jsonGetir(km), let meta = try? McpOAuth.kaynakMetasiCoz(v) {
            if let k = meta.kaynak, !k.isEmpty { kaynak = k }
            if let ilk = meta.yetkiSunuculari.first { issuer = ilk }
            kapsamlar = meta.kapsamlar
        }
        // 2) Yetki sunucusu metası.
        var sunucuMetasi: McpOAuth.SunucuMetasi?
        var sonHata: Error = McpOAuth.Hata.meta("bulunamadı")
        for adres in McpOAuth.yetkiSunucusuMetaAdresleri(issuer) {
            do { sunucuMetasi = try McpOAuth.sunucuMetasiCoz(try await McpOAuth.jsonGetir(adres)); break }
            catch let h as McpOAuth.Hata where h == .s256Yok || h == .adres { throw h }
            catch { sonHata = error }
        }
        guard let meta = sunucuMetasi else { throw sonHata }
        // 3) Dinamik istemci kaydı (RFC 7591).
        guard let kayitUcu = meta.kayitUcu else { throw McpOAuth.Hata.kayitYok }
        guard McpIstemci.oauthAdresiGecerli(kayitUcu.absoluteString) else { throw McpOAuth.Hata.adres }
        var r = URLRequest(url: kayitUcu, timeoutInterval: 20)
        r.httpMethod = "POST"; r.httpBody = McpOAuth.kayitGovdesi()
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (kv, ky) = try await URLSession.shared.data(for: r)
        guard let kk = (ky as? HTTPURLResponse)?.statusCode, (200..<300).contains(kk),
              let kn = try? JSONSerialization.jsonObject(with: kv) as? [String: Any], let istemci = kn["client_id"] as? String, !istemci.isEmpty
        else { throw McpOAuth.Hata.kayitYok }
        // 4) Tarayıcıda giriş.
        let pkce = McpOAuth.pkce(), durum = McpOAuth.rastgele(16)
        // Kapsam yalnız kaynak metası söylüyorsa istenir (yetki sunucusunun bütün kapsamları istenmez).
        let kapsam = kapsamlar.isEmpty ? nil : kapsamlar.joined(separator: " ")
        guard let adres = McpOAuth.yetkiAdresi(meta: meta, istemciKimligi: istemci, pkce: pkce, durum: durum, kaynak: kaynak, kapsam: kapsam)
        else { throw McpOAuth.Hata.adres }
        let donus = try await tarayicidaAc(adres)
        let kod = try McpOAuth.donusCoz(url: donus, beklenenDurum: durum)
        // 5) Kod → belirteç.
        let tv = try await McpOAuth.formGonder(meta.tokenUcu, McpOAuth.kodGovdesi(kod: kod, dogrulayici: pkce.dogrulayici, istemciKimligi: istemci, kaynak: kaynak))
        let b = try McpOAuth.belirtecCoz(tv, onceki: nil, istemciKimligi: istemci, tokenUcu: meta.tokenUcu.absoluteString, kaynak: kaynak)
        guard McpOAuth.belirtecYaz(b, id: s.id) else { throw McpOAuth.Hata.kasa }
        guard McpKaydi.ortak.ekle(ad: s.ad, url: s.url, yetki: "Bearer " + b.erisim) else {
            throw McpOAuth.Hata.belirtec(McpKaydi.ortak.sonHata ?? "sunucu kaydı güncellenemedi")
        }
        await McpOturumDefteri.ortak.temizle(s.id)
        return b.bitis
    }

    private func tarayicidaAc(_ adres: URL) async throws -> URL {
        // Sunum penceresi başlatmadan önce bulunur: pencere yoksa oturum hiç açılmaz.
        guard let pencere = Self.pencere() else { throw McpOAuth.Hata.iptal }
        capa = pencere
        return try await withCheckedThrowingContinuation { (devam: CheckedContinuation<URL, Error>) in
            let o = ASWebAuthenticationSession(url: adres, callback: .customScheme(McpOAuth.donusSemasi)) { @Sendable url, hata in
                if let url { devam.resume(returning: url); return }
                if let h = hata as? ASWebAuthenticationSessionError, h.code == .canceledLogin { devam.resume(throwing: McpOAuth.Hata.iptal); return }
                devam.resume(throwing: hata ?? McpOAuth.Hata.iptal)
            }
            o.presentationContextProvider = self
            o.prefersEphemeralWebBrowserSession = false
            oturum = o
            if !o.start() { oturum = nil; devam.resume(throwing: McpOAuth.Hata.iptal) }
        }
    }

    /// `tarayicidaAc` capa'yı `start()`tan önce kurar; buraya hep dolu gelir. Yedek yalnız savunma amaçlı.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let capa { return capa }
        return Self.pencere() ?? Self.sahnesizCapa()
    }
    /// Sahne yoksa (pratikte olmaz) çökmemek için boş pencere; iOS 26'da init() kullanımdan kalktı, uyarı bilinçli.
    private static func sahnesizCapa() -> ASPresentationAnchor { ASPresentationAnchor() }

    private static func pencere() -> ASPresentationAnchor? {
        let sahneler = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let w = sahneler.flatMap(\.windows).first(where: \.isKeyWindow) ?? sahneler.first?.windows.first { return w }
        return sahneler.first.map { UIWindow(windowScene: $0) }
    }
}
