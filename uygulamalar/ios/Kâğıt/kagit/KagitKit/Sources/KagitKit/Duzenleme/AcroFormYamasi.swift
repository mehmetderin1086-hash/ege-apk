import Foundation

/// PDFKit'in oluşturduğu form alanları (widget) belge kataloğunda `/AcroForm` olmadan yazılır;
/// bu yüzden başka okuyucular (PDFium, Acrobat, Chrome) alanları form olarak tanımaz.
/// Bu yardımcı kaydedilmiş PDF'e artımlı güncelleme olarak `/AcroForm /Fields` ekler.
///
/// Yalnız klasik `xref` tablolu, şifresiz dosyalarda çalışır (PDFKit'in yazdığı biçim);
/// diğerlerinde veriyi olduğu gibi döndürür.
public enum AcroFormYamasi {

    /// `/Widget` açıklaması var ama `/AcroForm` yoksa yama uygular; yoksa `veri`yi aynen döndürür.
    public static func uygula(_ veri: Data) -> Data {
        (try? yamala(veri)) ?? veri
    }

    /// Yama gerekli mi (hızlı ön kontrol)?
    public static func gerekliMi(_ veri: Data) -> Bool {
        veri.range(of: Data("/Widget".utf8)) != nil && veri.range(of: Data("/AcroForm".utf8)) == nil
    }

    private struct Nesne { let numara: Int; let nesil: Int; let govde: Range<Int> }

    static func yamala(_ veri: Data) throws -> Data {
        guard gerekliMi(veri) else { return veri }
        let baytlar = [UInt8](veri)
        let metin = String(decoding: baytlar.map { UInt16($0) }, as: UTF16.self)
        let ns = metin as NSString

        // 1. son startxref ve trailer
        let sx = ns.range(of: "startxref", options: .backwards)
        guard sx.location != NSNotFound else { throw KagitHata.desteklenmiyor("startxref yok") }
        let sxSonrasi = ns.substring(from: sx.location + sx.length).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let eskiXref = Int(sxSonrasi.prefix { $0.isNumber }) else { throw KagitHata.desteklenmiyor("startxref okunamadı") }
        guard eskiXref < baytlar.count, ns.substring(with: NSRange(location: eskiXref, length: min(4, ns.length - eskiXref))) == "xref" else {
            throw KagitHata.desteklenmiyor("xref akışı")
        }
        let tr = ns.range(of: "trailer", options: .backwards, range: NSRange(location: 0, length: sx.location))
        guard tr.location != NSNotFound, tr.location > eskiXref else { throw KagitHata.desteklenmiyor("trailer yok") }
        let trailerMetni = ns.substring(with: NSRange(location: tr.location + tr.length, length: sx.location - tr.location - tr.length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailerMetni.hasPrefix("<<"), trailerMetni.hasSuffix(">>"), !trailerMetni.contains("/Encrypt") else {
            throw KagitHata.desteklenmiyor("trailer")
        }
        guard let boyut = tamSayi(#"/Size\s+(\d+)"#, trailerMetni), let kok = tamSayi(#"/Root\s+(\d+)\s+\d+\s+R"#, trailerMetni) else {
            throw KagitHata.desteklenmiyor("trailer alanları")
        }

        // 2. nesneleri tara (satır başındaki "n g obj"); sonraki tanım öncekini ezer.
        let obj = try NSRegularExpression(pattern: #"(?m)^(\d+)\s+(\d+)\s+obj\b"#)
        var nesneler: [Int: Nesne] = [:]
        let eslesmeler = obj.matches(in: metin, range: NSRange(location: 0, length: ns.length))
        for (i, m) in eslesmeler.enumerated() {
            let numara = Int(ns.substring(with: m.range(at: 1))) ?? -1
            let nesil = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let bas = m.range.location + m.range.length
            let sinir = i + 1 < eslesmeler.count ? eslesmeler[i + 1].range.location : sx.location
            let bitis = ns.range(of: "endobj", range: NSRange(location: bas, length: sinir - bas))
            let son = bitis.location == NSNotFound ? sinir : bitis.location
            nesneler[numara] = Nesne(numara: numara, nesil: nesil, govde: bas..<son)
        }
        func govde(_ n: Nesne) -> String { ns.substring(with: NSRange(location: n.govde.lowerBound, length: n.govde.count)) }

        guard let katalog = nesneler[kok] else { throw KagitHata.desteklenmiyor("katalog bulunamadı") }
        let katalogMetni = govde(katalog)
        guard !katalogMetni.contains("/AcroForm"), let sonKapanis = katalogMetni.range(of: ">>", options: .backwards) else { return veri }

        // 3. alan kökleri
        var kokler: [Int] = []
        for n in nesneler.keys.sorted() {
            guard let nesne = nesneler[n] else { continue }
            let g = govde(nesne)
            guard g.contains("/Widget") else { continue }
            var guncel = n
            var tur = 0
            while tur < 16, let ust = tamSayi(#"/Parent\s+(\d+)\s+\d+\s+R"#, govde(nesneler[guncel] ?? nesne)) {
                guncel = ust
                tur += 1
            }
            if !kokler.contains(guncel) { kokler.append(guncel) }
        }
        guard !kokler.isEmpty else { return veri }

        // 4. yeni nesneler
        let yaziTipiNo = boyut
        var cikti = Data(veri)
        if cikti.last != 0x0A { cikti.append(0x0A) }
        var ofsetler: [(Int, Int, Int)] = []   // numara, nesil, ofset

        func ekle(_ numara: Int, _ nesil: Int, _ icerik: String) {
            ofsetler.append((numara, nesil, cikti.count))
            cikti.append(Data("\(numara) \(nesil) obj\n\(icerik)\nendobj\n".utf8))
        }

        ekle(yaziTipiNo, 0, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        let alanlar = kokler.map { "\($0) \(nesneler[$0]?.nesil ?? 0) R" }.joined(separator: " ")
        let acro = " /AcroForm << /Fields [\(alanlar)] /DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv \(yaziTipiNo) 0 R >> >> >> "
        var yeniKatalog = katalogMetni
        yeniKatalog.insert(contentsOf: acro, at: sonKapanis.lowerBound)
        ekle(katalog.numara, katalog.nesil, yeniKatalog.trimmingCharacters(in: .whitespacesAndNewlines))

        // 5. xref bölümü + trailer
        let xrefOfset = cikti.count
        var xref = "xref\n"
        for (numara, nesil, ofset) in ofsetler.sorted(by: { $0.0 < $1.0 }) {
            xref += "\(numara) 1\n" + String(format: "%010d %05d n \n", ofset, nesil)
        }
        var yeniTrailer = trailerMetni
        if let r = yeniTrailer.range(of: #"/Prev\s+\d+"#, options: .regularExpression) { yeniTrailer.removeSubrange(r) }
        if let r = yeniTrailer.range(of: #"/Size\s+\d+"#, options: .regularExpression) {
            yeniTrailer.replaceSubrange(r, with: "/Size \(boyut + 1)")
        }
        if let k = yeniTrailer.range(of: ">>", options: .backwards) {
            yeniTrailer.insert(contentsOf: " /Prev \(eskiXref) ", at: k.lowerBound)
        }
        xref += "trailer\n\(yeniTrailer)\nstartxref\n\(xrefOfset)\n%%EOF\n"
        cikti.append(Data(xref.utf8))
        return cikti
    }

    private static func tamSayi(_ desen: String, _ metin: String) -> Int? {
        guard let r = metin.range(of: desen, options: .regularExpression) else { return nil }
        let parca = String(metin[r])
        guard let s = parca.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(parca[s])
    }
}
