import Foundation

/// Kişisel dikte düzeltme defteri: istem süzgecinin sesli isteklerde yaptığı küçük düzeltmeler ("mitos" → "mitoz") ve
/// kullanıcının elle girdiği "yanlış → doğru" çiftleri. Dikte ve Whisper çıktısına uygulanır, Whisper istemine ve cihaz içi
/// dil modeline (`DikteDilModeli`) ipucu olur. Dosya: Application Support/DikteDefteri.json (en çok 300 kayıt).
/// Tanı günlüğüne metin yazılmaz.
nonisolated final class DikteDuzeltmeDefteri: @unchecked Sendable {
    nonisolated enum Kaynak: String, Codable, Sendable { case suzgec, kullanici }

    nonisolated struct Kayit: Codable, Sendable, Equatable, Identifiable {
        var yanlis: String
        var dogru: String
        var sayac: Int
        var kaynak: Kaynak
        var son: Date
        var id: String { Self.anahtar(yanlis) }
        /// Süzgeç kaydı en az iki kez görülmeden uygulanmaz; kullanıcının kaydı hemen uygulanır.
        var etkin: Bool { kaynak == .kullanici || sayac >= 2 }
        static func anahtar(_ s: String) -> String { s.lowercased(with: DikteDuzeltmeDefteri.tr).trimmingCharacters(in: .whitespaces) }
    }

    static let ortak = DikteDuzeltmeDefteri()
    /// Defter değişti (öğrenme, ekleme, silme): `DikteDilModeli` dil modelini yeniden kurar.
    static let degisti = Notification.Name("asistan.dikteDefteriDegisti")
    static let enFazlaKayit = 300
    static let tr = Locale(identifier: "tr_TR")

    private let kilit = NSLock()
    private let dosya: URL
    private var kayitlar: [Kayit]
    private var _sonDikte: String?

    init(dosya: URL? = nil) {
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.dosya = dosya ?? taban.appending(path: "DikteDefteri.json")
        kayitlar = (try? Data(contentsOf: self.dosya)).flatMap { try? JSONDecoder().decode([Kayit].self, from: $0) } ?? []
    }

    /// Son sesli girdinin (defter uygulanmış) metni. Süzgeç yalnız bu metinle aynı istekte öğrenir: klavyeyle yazılan isteklerin
    /// yazım düzeltmeleri dikte sözlüğüne girmez. Öğrenme denemesinden sonra temizlenir.
    var sonDikte: String? {
        get { kilit.withLock { _sonDikte } }
        set { kilit.withLock { _sonDikte = newValue } }
    }

    // MARK: fark (saf)

    /// Ham ve düzeltilmiş metnin sözcük hizalaması (LCS). Yalnız iki yanı da 1-3 sözcüklük değişim parçaları döner; durak
    /// sözcüğü, rakam ya da 3 harften kısa sözcük içeren, karakter düzenleme oranı 0,6'yı aşan (başka bir sözcük yazılmış)
    /// parçalar alınmaz. Ortak sözcükler ham metnin yarısından azsa cümle yeniden yazılmış sayılır: boş.
    static func fark(ham: String, duzeltilmis: String) -> [(String, String)] {
        let a = sozcukler(ham), b = sozcukler(duzeltilmis)
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let na = a.map(esitlikBicimi), nb = b.map(esitlikBicimi)
        // LCS tablosu (kısa metinler; en çok 80 sözcük).
        guard a.count <= 80, b.count <= 80 else { return [] }
        var t = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = na[i] == nb[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        guard t[0][0] * 2 >= a.count else { return [] }
        var sonuc: [(String, String)] = []
        var i = 0, j = 0
        var parcaA: [String] = [], parcaB: [String] = []
        func kapat() {
            defer { parcaA = []; parcaB = [] }
            guard !parcaA.isEmpty, !parcaB.isEmpty, parcaA.count <= 3, parcaB.count <= 3 else { return }
            let y = parcaA.joined(separator: " "), d = parcaB.joined(separator: " ")
            guard kabulEdilir(yanlis: y, dogru: d) else { return }
            sonuc.append((y, d))
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, na[i] == nb[j] { kapat(); i += 1; j += 1 }
            else if j < b.count, i == a.count || t[i][j + 1] >= t[i + 1][j] { parcaB.append(b[j]); j += 1 }
            else { parcaA.append(a[i]); i += 1 }
        }
        kapat()
        return sonuc
    }

    /// Noktalama soyulmuş sözcükler (özgün harf büyüklüğüyle).
    static func sozcukler(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    /// Hizalamada eşitlik: harf büyüklüğü katlanır, aksanlar KORUNUR (cüz ≠ cuz bir düzeltmedir).
    static func esitlikBicimi(_ s: String) -> String { s.lowercased(with: tr) }

    static func kabulEdilir(yanlis: String, dogru: String) -> Bool {
        let y = esitlikBicimi(yanlis), d = esitlikBicimi(dogru)
        guard y != d else { return false }
        for s in sozcukler(yanlis) + sozcukler(dogru) {
            if s.contains(where: \.isNumber) || s.count < 3 { return false }
            if HafizaIndeksi.durak.contains(HafizaIndeksi.normalize(s)) { return false }
        }
        let oran = Double(IstemSuzgeci.duzenlemeUzakligi(y, d)) / Double(max(y.count, d.count))
        return oran <= 0.6
    }

    // MARK: öğrenme / kayıt

    /// Süzgeç ya da kullanıcı düzeltmesinden öğrenir: bilinen çiftin sayacı artar, yeni çift eklenir. Kullanıcının kaydını
    /// süzgeç değiştiremez. Değişiklik varsa diske yazılır ve `degisti` bildirilir.
    func ogren(ham: String, duzeltilmis: String, kaynak: Kaynak, simdi: Date = .now) {
        let ciftler = Self.fark(ham: ham, duzeltilmis: duzeltilmis)
        guard !ciftler.isEmpty else { return }
        kilit.withLock {
            for (y, d) in ciftler { kaydetKilitsiz(yanlis: y, dogru: d, kaynak: kaynak, simdi: simdi) }
            budaKilitsiz()
        }
        yaz()
    }

    /// İstek son sesli girdinin kendisi mi (yazılı istek değil). Harf büyüklüğü, aksan ve noktalama farkı yok sayılır.
    static func sesliIstekMi(ham: String, sonDikte: String?) -> Bool {
        guard let sonDikte, !sonDikte.isEmpty else { return false }
        return AtolyeYonlendirme.normalize(ham) == AtolyeYonlendirme.normalize(sonDikte)
    }

    /// İstem süzgecinin düzeltmesinden öğrenir: yalnız istek son sesli girdiyse (`sesliIstekMi`); deneme sonrası `sonDikte`
    /// temizlenir. Dikte sözlüğü ayarı kapalıysa öğrenmez.
    func suzgectenOgren(ham: String, duzeltilmis: String) {
        let son = sonDikte
        sonDikte = nil
        guard DikteDilModeli.ayarAcik, Self.sesliIstekMi(ham: ham, sonDikte: son) else { return }
        ogren(ham: ham, duzeltilmis: duzeltilmis, kaynak: .suzgec)
    }

    /// Elle ekleme ("yanlış → doğru"). Boş ya da aynı çift reddedilir.
    @discardableResult
    func ekle(yanlis: String, dogru: String, simdi: Date = .now) -> Bool {
        let y = yanlis.trimmingCharacters(in: .whitespacesAndNewlines), d = dogru.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !y.isEmpty, !d.isEmpty, y.count <= 60, d.count <= 60, Self.esitlikBicimi(y) != Self.esitlikBicimi(d) else { return false }
        kilit.withLock {
            kaydetKilitsiz(yanlis: y, dogru: d, kaynak: .kullanici, simdi: simdi)
            budaKilitsiz()
        }
        yaz()
        return true
    }

    func sil(_ yanlis: String) {
        let k = Kayit.anahtar(yanlis)
        let silindi = kilit.withLock { () -> Bool in
            let n = kayitlar.count
            kayitlar.removeAll { $0.id == k }
            return kayitlar.count != n
        }
        if silindi { yaz() }
    }

    /// Kayıtlar: önce kullanıcınınkiler, sonra sayaca ve yeniliğe göre.
    func liste() -> [Kayit] {
        kilit.withLock { kayitlar }.sorted { a, b in
            if a.kaynak != b.kaynak { return a.kaynak == .kullanici }
            return a.sayac == b.sayac ? a.son > b.son : a.sayac > b.sayac
        }
    }

    private func kaydetKilitsiz(yanlis y: String, dogru d: String, kaynak: Kaynak, simdi: Date) {
        let k = Kayit.anahtar(y)
        if let i = kayitlar.firstIndex(where: { $0.id == k }) {
            var e = kayitlar[i]
            if Self.esitlikBicimi(e.dogru) == Self.esitlikBicimi(d) {
                e.sayac += 1; e.son = simdi
                if kaynak == .kullanici { e.kaynak = .kullanici; e.dogru = d }
            } else if kaynak == .kullanici || e.kaynak == .suzgec {
                // Yeni doğru biçim: kullanıcı her zaman değiştirir; süzgeç yalnız kendi kaydını, sayacı sıfırdan başlatarak.
                e.dogru = d; e.sayac = 1; e.kaynak = kaynak; e.son = simdi
            }
            kayitlar[i] = e
        } else {
            kayitlar.append(Kayit(yanlis: y, dogru: d, sayac: 1, kaynak: kaynak, son: simdi))
        }
    }

    /// 300 sınırı: önce en az görülen, en eski süzgeç kayıtları düşer.
    private func budaKilitsiz() {
        guard kayitlar.count > Self.enFazlaKayit else { return }
        let sirali = kayitlar.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if a.kaynak != b.kaynak { return a.kaynak == .suzgec }
            return a.sayac == b.sayac ? a.son < b.son : a.sayac < b.sayac
        }
        let dusen = Set(sirali.prefix(kayitlar.count - Self.enFazlaKayit).map(\.offset))
        kayitlar = kayitlar.enumerated().filter { !dusen.contains($0.offset) }.map(\.element)
    }

    private func yaz() {
        let v = kilit.withLock { kayitlar }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        try? e.encode(v).write(to: dosya, options: .atomic)
        NotificationCenter.default.post(name: Self.degisti, object: self)
    }

    // MARK: uygulama

    /// Etkin kayıtları (kullanıcınınkiler ve en az iki kez görülen süzgeç düzeltmeleri) sözcük sınırında uygular; harf
    /// büyüklüğü korunur (cümle başındaki "Mitos" → "Mitoz"). Sözcük içi eşleşme yapılmaz ("mitoskondri" bozulmaz).
    func uygula(_ metin: String) -> String {
        let etkin = kilit.withLock { kayitlar.filter(\.etkin) }
        guard !etkin.isEmpty, !metin.isEmpty else { return metin }
        var s = metin
        for k in etkin.sorted(by: { $0.yanlis.count > $1.yanlis.count }) {
            let desen = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: k.yanlis) + "(?![\\p{L}\\p{N}])"
            guard let rx = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive]) else { continue }
            let ns = s as NSString
            let eslesmeler = rx.matches(in: s, range: NSRange(location: 0, length: ns.length))
            guard !eslesmeler.isEmpty else { continue }
            let m = NSMutableString(string: s)
            for e in eslesmeler.reversed() {
                let bulunan = ns.substring(with: e.range)
                m.replaceCharacters(in: e.range, with: Self.buyuklukKoru(bulunan, k.dogru))
            }
            s = m as String
        }
        return s
    }

    /// Bulunan sözcük büyük harfle başlıyorsa doğru biçimin ilk harfi de büyür; tamamı büyükse tamamı büyür.
    static func buyuklukKoru(_ bulunan: String, _ dogru: String) -> String {
        guard let ilk = bulunan.first, ilk.isUppercase else { return dogru }
        if bulunan.count > 1, bulunan == bulunan.uppercased(with: tr) { return dogru.uppercased(with: tr) }
        return dogru.prefix(1).uppercased(with: tr) + dogru.dropFirst()
    }

    /// Whisper istemi ve dil modeli için doğru biçimler (virgüllü, tekrarsız; çok görülen önde, en çok `enFazla`).
    func ipucu(enFazla: Int = 30) -> String {
        var gorulen = Set<String>(), sonuc: [String] = []
        for k in liste() where gorulen.insert(Self.esitlikBicimi(k.dogru)).inserted {
            sonuc.append(k.dogru)
            if sonuc.count >= enFazla { break }
        }
        return sonuc.joined(separator: ", ")
    }

    /// Dil modeline girecek doğru biçimler (tamamı).
    func dogruBicimler() -> [String] {
        var gorulen = Set<String>()
        return liste().map(\.dogru).filter { gorulen.insert(Self.esitlikBicimi($0)).inserted }
    }
}
