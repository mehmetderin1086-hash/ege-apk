import Foundation

/// P3.12: uyarlanabilir konuşma sonu. Söz virgülle, iki noktayla ya da bağlaçla ("ve", "ama", "ya da"…) bitiyorsa
/// kullanıcı düşünüyordur: uzun bekle. Kısa SORU ("saat kaç") tamamdır: kısa bekle. Kısa ama soru biçimli olmayan
/// metin ("fener", "annemi ara") çoğu kez yarımdır: kipin tabanı. Aksi hâlde kipin tabanı.
/// SesDinleyici `akilliSon` açıkken sessizlik zamanlayıcısını buradan kurar; sonSes < 0,55 sn döngüsü ayrıca korunur.
nonisolated enum UcNoktasiKarari {
    static let kisaMs = 850
    static let uzunMs = 1600
    static let baglaclar: Set<String> = ["ve", "ama", "fakat", "ancak", "veya", "yahut", "çünkü", "sonra", "ile", "ki",
                                         "de", "da", "yani", "mesela", "hani", "ayrıca", "hem", "eğer", "için", "gibi", "diye"]
    static let kisaKelimeSiniri = 3
    static let soruSozcukleri: Set<String> = ["kaç", "ne", "nedir", "nasıl", "kim", "kimin", "nerede", "nereye", "nereden", "hangi",
                                              "kaçta", "neden", "niye", "mi", "mı", "mu", "mü", "mısın", "misin", "musun", "müsün"]

    static func bekleme(metin: String, taban: Int) -> Int {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let son = t.last else { return taban }
        if son == "," || son == ":" { return uzunMs }
        let kelimeler = t.lowercased(with: Locale(identifier: "tr_TR"))
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard let sonKelime = kelimeler.last else { return taban }
        // "ya da" da "da" ile biter.
        if baglaclar.contains(sonKelime) { return uzunMs }
        if kelimeler.count <= kisaKelimeSiniri, son == "?" || kelimeler.contains(where: { soruSozcukleri.contains($0) }) {
            return min(kisaMs, taban)
        }
        return taban
    }
}
