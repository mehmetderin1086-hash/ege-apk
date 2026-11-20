import Compression
import Foundation

/// En yalın ZIP yazıcı (DOCX/XLSX/EPUB/PPTX üretimi için). DEFLATE ya da saklama.
public struct ZipYazici {
    private struct Girdi {
        let ad: [UInt8]
        let crc: UInt32
        let sikistirilmis: Int
        let ham: Int
        let yontem: UInt16
        let konum: Int
    }

    private var veri = Data()
    private var girdiler: [Girdi] = []

    public init() {}

    /// Dosya ekler. `sakla` true ise sıkıştırmadan (EPUB'un "mimetype" girdisi için şart).
    public mutating func ekle(_ ad: String, _ icerik: Data, sakla: Bool = false) {
        let adBaytlari = Array(ad.utf8)
        let crc = CRC32.hesapla(icerik)
        var yontem: UInt16 = 0
        var govde = icerik
        if !sakla, icerik.count > 64, let sikisik = Self.deflate(icerik), sikisik.count < icerik.count {
            govde = sikisik
            yontem = 8
        }
        let konum = veri.count
        veri.le32(0x0403_4b50)
        veri.le16(20)          // sürüm
        veri.le16(0x0800)      // UTF-8 adlar
        veri.le16(yontem)
        veri.le16(0); veri.le16(0x21)  // saat, tarih (1980-01-01)
        veri.le32(crc)
        veri.le32(UInt32(govde.count))
        veri.le32(UInt32(icerik.count))
        veri.le16(UInt16(adBaytlari.count))
        veri.le16(0)
        veri.append(contentsOf: adBaytlari)
        veri.append(govde)
        girdiler.append(Girdi(ad: adBaytlari, crc: crc, sikistirilmis: govde.count, ham: icerik.count,
                              yontem: yontem, konum: konum))
    }

    public mutating func ekle(_ ad: String, metin: String, sakla: Bool = false) {
        ekle(ad, Data(metin.utf8), sakla: sakla)
    }

    /// Merkezi dizini yazıp ZIP verisini döndürür.
    public func bitir() -> Data {
        var cikti = veri
        let dizinBasi = cikti.count
        for g in girdiler {
            cikti.le32(0x0201_4b50)
            cikti.le16(20); cikti.le16(20)
            cikti.le16(0x0800)
            cikti.le16(g.yontem)
            cikti.le16(0); cikti.le16(0x21)
            cikti.le32(g.crc)
            cikti.le32(UInt32(g.sikistirilmis))
            cikti.le32(UInt32(g.ham))
            cikti.le16(UInt16(g.ad.count))
            cikti.le16(0); cikti.le16(0); cikti.le16(0); cikti.le16(0)
            cikti.le32(0)
            cikti.le32(UInt32(g.konum))
            cikti.append(contentsOf: g.ad)
        }
        let dizinBoyu = cikti.count - dizinBasi
        cikti.le32(0x0605_4b50)
        cikti.le16(0); cikti.le16(0)
        cikti.le16(UInt16(girdiler.count)); cikti.le16(UInt16(girdiler.count))
        cikti.le32(UInt32(dizinBoyu))
        cikti.le32(UInt32(dizinBasi))
        cikti.le16(0)
        return cikti
    }

    /// Ham DEFLATE (RFC 1951). Apple'ın COMPRESSION_ZLIB'i başlıksız ham akış üretir.
    static func deflate(_ girdi: Data) -> Data? {
        let kapasite = girdi.count + girdi.count / 10 + 1024
        var cikti = Data(count: kapasite)
        let boy = cikti.withUnsafeMutableBytes { hedef in
            girdi.withUnsafeBytes { kaynak in
                compression_encode_buffer(hedef.bindMemory(to: UInt8.self).baseAddress!, kapasite,
                                          kaynak.bindMemory(to: UInt8.self).baseAddress!, girdi.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard boy > 0 else { return nil }
        cikti.count = boy
        return cikti
    }
}

/// ZIP okuyucu (yalnızca okuma; DOCX/XLSX içeriğini sınamak ve içe aktarmak için).
public enum ZipOkuyucu {
    /// Ad → içerik sözlüğü. Yalnız saklama ve DEFLATE desteklenir.
    public static func ac(_ zip: Data) -> [String: Data] {
        var sonuc: [String: Data] = [:]
        let b = [UInt8](zip)
        var i = 0
        func u16(_ k: Int) -> Int { Int(b[k]) | Int(b[k + 1]) << 8 }
        func u32(_ k: Int) -> Int { u16(k) | u16(k + 2) << 16 }
        while i + 30 <= b.count, u32(i) == 0x0403_4b50 {
            let yontem = u16(i + 8)
            let sikisik = u32(i + 18), ham = u32(i + 22)
            let adBoy = u16(i + 26), ekBoy = u16(i + 28)
            let ad = String(decoding: b[(i + 30)..<(i + 30 + adBoy)], as: UTF8.self)
            let bas = i + 30 + adBoy + ekBoy
            guard bas + sikisik <= b.count else { break }
            let govde = Data(b[bas..<(bas + sikisik)])
            if yontem == 0 {
                sonuc[ad] = govde
            } else if yontem == 8 {
                var cikti = Data(count: max(ham, 1))
                let n = cikti.withUnsafeMutableBytes { h in
                    govde.withUnsafeBytes { k in
                        compression_decode_buffer(h.bindMemory(to: UInt8.self).baseAddress!, max(ham, 1),
                                                  k.bindMemory(to: UInt8.self).baseAddress!, govde.count,
                                                  nil, COMPRESSION_ZLIB)
                    }
                }
                cikti.count = n
                sonuc[ad] = cikti
            }
            i = bas + sikisik
        }
        return sonuc
    }
}

enum CRC32 {
    static let tablo: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func hesapla(_ veri: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        veri.withUnsafeBytes { tampon in
            for bayt in tampon.bindMemory(to: UInt8.self) {
                c = tablo[Int((c ^ UInt32(bayt)) & 0xFF)] ^ (c >> 8)
            }
        }
        return c ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
}
