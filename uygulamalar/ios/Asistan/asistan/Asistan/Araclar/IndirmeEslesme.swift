import Foundation

/// Ada göre YouTube indirmelerinde adayın isteğe uyup uymadığını yerel olarak ölçer.
/// "Kur'an meali Ayhan Kaya 15. cüz" isteği için "1. Cüz — Mazlum Kiper" indirilmemeli:
/// istekteki sayıların hepsi adayda geçmeli, anlamlı sözcüklerin büyük kısmı eşleşmeli.
nonisolated enum IndirmeEslesme {
    /// Bu puanın altındaki en iyi aday otomatik indirilmez; liste kullanıcıya/modele döner.
    static let esik = 0.8
    /// Biçim, betimleme ve çekimli dolgu sözcükleri ("şarkısını", "videosu", "en çok dinlenen") puana katılmaz.
    /// "canli"/"konser" bilerek yok: sürüm ayırt ederler.
    private static let dolgu: Set<String> = ["official", "video", "videosu", "videosunu", "videoyu", "audio", "resmi", "klip", "klibi", "klibini",
                                             "sarki", "sarkisi", "sarkisini", "sarkiyi", "muzik", "music", "sozleri", "full", "hd", "4k", "lyrics",
                                             "lyric", "mp3", "mp4", "ve", "ile", "the", "feat", "ft", "indir", "dinle", "izle", "youtube",
                                             "en", "cok", "dinlenen", "izlenen", "populer", "yeni", "son", "guzel"]
    /// Biçim/dil/tarih/adet/işlem kısıtları başlıkta geçmez; eşleşmede aranmaz ("işlem: indirme", "tarih: 2023").
    private static let atlananEtiketler: Set<String> = ["dil", "bicim", "format", "dosya turu", "dosya tipi", "tur", "tip", "kalite", "cozunurluk",
                                                        "sure", "uzanti", "tarih", "yil", "adet", "miktar", "islem", "eylem", "altyazi"]
    /// Etiketsiz gelse de başlıkta aranmayan biçim/dil/kalite/betim sözcükleri ("sadece ses", "Türkçe altyazılı",
    /// "1080p kalite", "resmi kanal", "son çıkan"): kısıt yalnız okuyucu/kanal/sayı gibi ayırt edici simgeleri ek olarak denetler.
    private static let bicimSozcukleri: Set<String> = ["ses", "sesi", "sesini", "sesli", "sadece", "yalniz", "yalnizca", "dosya", "dosyasi",
                                                       "format", "formati", "formatinda", "bicim", "bicimi", "biciminde", "kalite", "kaliteli",
                                                       "cozunurluk", "altyazi", "altyazili", "dublaj", "dublajli", "turkce", "ingilizce", "arapca",
                                                       "almanca", "fransizca", "m4a", "mp3", "mp4", "audio", "video", "kayit", "kaydi", "kanal",
                                                       "kanali", "orijinal", "original", "cikan", "indirme", "indirilecek"]
    private static func bicimSozcugu(_ sozcuk: String) -> Bool {
        simgeler(sozcuk).allSatisfy { bicimSozcukleri.contains($0) || $0.range(of: #"^\d{3,4}p$"#, options: .regularExpression) != nil }
    }

    static func simgeler(_ s: String) -> [String] {
        // Yazıyla sayılar rakama iner ("on beşinci cüz" → "15. cuz"); yalnız karşılaştırma içindir.
        var n = TurkceSayi.normalize(AtolyeYonlendirme.normalize(s))
        // Ekli sayılar yalın sayıya iner: "15'inci" / "5’te" → "15" / "5", "15inci" → "15".
        // Genel "rakam + harf" ayrıştırması yapılmaz ("4k", "2pac" sahte sayı kapısı açmasın).
        n = n.replacingOccurrences(of: #"(\d+)['’]\p{L}+"#, with: "$1", options: .regularExpression)
        n = n.replacingOccurrences(of: #"(\d+)(?:inci|nci|uncu|ncu)\p{L}*"#, with: "$1", options: .regularExpression)
        // On yıl/çoğul eki kesmesiz de aynı simgeye iner: "90s" / "90lar" / "1990ların" → "90" / "90" / "1990"
        // ("90's" / "90'lar" yukarıda zaten "90" oldu). En az iki hane: "4k", "2pac", "4s" dokunulmaz.
        n = n.replacingOccurrences(of: #"\b(\d{2,})(?:s|lar\p{L}*|ler\p{L}*)\b"#, with: "$1", options: .regularExpression)
        n = n.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        // Tek haneli sayılar da kalır: "5. cüz" isteğinde 5 zorunlu sayıdır.
        return n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { ($0.count >= 2 || $0.allSatisfy(\.isNumber)) && !dolgu.contains($0) }
    }

    /// İki simge aynı mı (çekim eki payıyla); `KisitDenetimi.eksikKisitlar` da kullanır.
    static func uyar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Çekim ekleri: "kuran" ~ "kurani", "meal" ~ "meali" (en az 4 harf ortak kök);
        // 3 harfli kökte yalnız tek harf ek ("cuz" ~ "cuzu").
        let kisa = min(a.count, b.count)
        guard a.hasPrefix(b) || b.hasPrefix(a) else { return false }
        return kisa >= 4 || (kisa == 3 && max(a.count, b.count) == 4 && !(a + b).contains(where: \.isNumber))
    }

    /// 0…1 arası puan. İstekteki her sayı adayda yoksa puan 0,3 ile sınırlanır.
    static func puan(istek: String, baslik: String?, kanal: String?) -> Double {
        let istenen = simgeler(istek)
        guard !istenen.isEmpty else { return 0 }
        let aday = simgeler((baslik ?? "") + " " + (kanal ?? ""))
        let eslesen = istenen.filter { i in aday.contains { uyar(i, $0) } }
        var p = Double(eslesen.count) / Double(istenen.count)
        let sayilar = istenen.filter { $0.allSatisfy(\.isNumber) }
        let sayiEksik = sayilar.contains { s in !aday.contains(s) }
        if sayiEksik { p = min(p, 0.3) }
        return p
    }

    /// İstem süzgecinin zorunlu kısıtlarından eşleşmede aranacak sözcükler: "kaynak: Vav Radyo"
    /// gibi etiket önekleri atılır, biçim/dil/tarih kısıtları ve biçim sözcükleri atlanır; her kısıttan sayılar ve
    /// özel adlar (büyük harfle başlayan sözcükler) alınır. Tümüyle küçük harfli kısıtın bütün sözcükleri yalnız
    /// etiketliyse alınır ("okuyucu: ayhan kaya"); etiketsizse betimleyicidir ("resmi kanal") ve zorunlu simgeye dönüşmez.
    static func kisitMetni(_ kisitlar: [String]) -> String {
        var parcalar: [String] = []
        for k in kisitlar {
            var m = k.trimmingCharacters(in: .whitespacesAndNewlines)
            var etiketli = false
            if let r = m.range(of: #"^[\p{L} ]{1,20}:\s*"#, options: .regularExpression) {
                let etiket = AtolyeYonlendirme.normalize(String(m[r]).replacingOccurrences(of: ":", with: ""))
                if atlananEtiketler.contains(etiket) { continue }
                m = String(m[r.upperBound...])
                etiketli = true
            }
            let sozcukler = m.split(whereSeparator: \.isWhitespace).map(String.init).filter { !bicimSozcugu($0) }
            let ozel = sozcukler.filter { s in s.first.map { $0.isUppercase || $0.isNumber } ?? false }
            if !ozel.isEmpty { parcalar += ozel } else if etiketli { parcalar += sozcukler }
        }
        return parcalar.joined(separator: " ")
    }

    /// Modelin yazdığı sorgu kısaltılmış olabilir ("Kuran meali 15. cüz"): süzgeç kısıtları varsa
    /// aday onlara da ayrıca uymalı. Düz birleştirme yapılmaz (yinelenen simgeler eşiği geçirir); düşük olan puan alınır.
    static func puan(istek: String, kisitlar: [String], baslik: String?, kanal: String?) -> Double {
        let ham = puan(istek: istek, baslik: baslik, kanal: kanal)
        let kisit = kisitMetni(kisitlar)
        guard !simgeler(kisit).isEmpty else { return ham }
        return min(ham, puan(istek: kisit, baslik: baslik, kanal: kanal))
    }

    struct Aday { let baslik: String; let kanal: String; let sure: Double?; let url: String; let puan: Double }

    /// Adayları puana göre sıralar; en iyisi eşiği geçiyorsa onu döndürür.
    static func sec(istek: String, adaylar: [Aday]) -> (secilen: Aday?, sirali: [Aday]) {
        let sirali = adaylar.sorted { $0.puan > $1.puan }
        guard let ilk = sirali.first, ilk.puan >= esik else { return (nil, sirali) }
        return (ilk, sirali)
    }

    static func sureMetni(_ s: Double?) -> String {
        guard let s, s > 0 else { return "" }
        let m = Int(s) / 60, sn = Int(s) % 60
        return m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, sn) : String(format: "%d:%02d", m, sn)
    }
}
