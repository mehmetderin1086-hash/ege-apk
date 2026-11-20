import AVFoundation
import UIKit

nonisolated struct MedyaEtiketi: Sendable {
    var baslik: String
    var sanatci: String?
    var aciklama: String?
    var tarih: String?
    var kapak: Data?
}

nonisolated enum BirlestirmeHatasi: LocalizedError {
    case izYok, disaAktarilamadi(String)
    var errorDescription: String? {
        switch self {
        case .izYok: "Dosyada oynatılabilir ses ya da görüntü izi bulunamadı."
        case .disaAktarilamadi(let neden): "Dosya birleştirilemedi: \(neden)"
        }
    }
}

/// Ayrı gelen görüntü ve ses akışlarını yeniden kodlamadan (passthrough) tek MP4/M4A dosyasına koyar,
/// başlık/kanal/kapak etiketlerini yazar ve istenirse bir kesit alır.
nonisolated enum Birlestirici {
    @concurrent static func birlestir(video: URL?, ses: URL?, cikis: URL, yalnizSes: Bool, etiket: MedyaEtiketi, kesit: ClosedRange<Double>?) async throws {
        for dosya in [video, ses].compactMap({ $0 }) { MP4Onarici.parcaliSureleriSifirla(dosya) }
        let kompozisyon = AVMutableComposition()
        var izVar = false
        var goruntuSuresi: CMTime?

        if let video {
            let varlik = AVURLAsset(url: video)
            if !yalnizSes, let iz = try await varlik.loadTracks(withMediaType: .video).first {
                let aralik = try await iz.load(.timeRange)
                let hedef = kompozisyon.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                try hedef?.insertTimeRange(aralik, of: iz, at: .zero)
                hedef?.preferredTransform = try await iz.load(.preferredTransform)
                goruntuSuresi = aralik.duration
                izVar = true
            }
            if ses == nil, let iz = try await varlik.loadTracks(withMediaType: .audio).first {
                let aralik = try await iz.load(.timeRange)
                let hedef = kompozisyon.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try hedef?.insertTimeRange(aralik, of: iz, at: .zero)
                izVar = true
            }
        }
        if let ses {
            let varlik = AVURLAsset(url: ses)
            if let iz = try await varlik.loadTracks(withMediaType: .audio).first {
                var aralik = try await iz.load(.timeRange)
                // Ses görüntüden uzunsa sonunu kes (YouTube'da çoğu zaman birkaç kare farkı olur).
                if let goruntuSuresi, aralik.duration > goruntuSuresi + CMTime(seconds: 1, preferredTimescale: 600) {
                    aralik = CMTimeRange(start: aralik.start, duration: goruntuSuresi)
                }
                let hedef = kompozisyon.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try hedef?.insertTimeRange(aralik, of: iz, at: .zero)
                izVar = true
            }
        }
        guard izVar else { throw BirlestirmeHatasi.izYok }

        try? FileManager.default.removeItem(at: cikis)
        let tur: AVFileType = yalnizSes ? .m4a : .mp4
        do {
            do {
                try await disaAktar(kompozisyon, preset: AVAssetExportPresetPassthrough, cikis: cikis, tur: tur, etiket: etiket, kesit: kesit, ses: yalnizSes)
            } catch where yalnizSes && !Task.isCancelled {
                // AC-3 gibi kodekler M4A'ya doğrudan konamaz: AAC'ye yeniden kodla.
                try? FileManager.default.removeItem(at: cikis)
                try await disaAktar(kompozisyon, preset: AVAssetExportPresetAppleM4A, cikis: cikis, tur: tur, etiket: etiket, kesit: kesit, ses: true)
            }
        } catch {
            try? FileManager.default.removeItem(at: cikis)   // yarım çıktı kalmasın
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private static func disaAktar(_ varlik: AVAsset, preset: String, cikis: URL, tur: AVFileType, etiket: MedyaEtiketi,
                                  kesit: ClosedRange<Double>?, ses: Bool) async throws {
        guard let oturum = AVAssetExportSession(asset: varlik, presetName: preset) else {
            throw BirlestirmeHatasi.disaAktarilamadi("dışa aktarma oturumu kurulamadı")
        }
        oturum.metadata = etiketler(etiket, ses: ses)
        oturum.shouldOptimizeForNetworkUse = true
        if let kesit, kesit.upperBound > kesit.lowerBound {
            oturum.timeRange = CMTimeRange(start: CMTime(seconds: kesit.lowerBound, preferredTimescale: 600),
                                           end: CMTime(seconds: kesit.upperBound, preferredTimescale: 600))
        }
        do {
            try await oturum.export(to: cikis, as: tur)
        } catch {
            throw BirlestirmeHatasi.disaAktarilamadi(error.localizedDescription)
        }
    }

    static func etiketler(_ etiket: MedyaEtiketi, ses: Bool) -> [AVMetadataItem] {
        func oge(_ kimlik: AVMetadataIdentifier, _ deger: (NSCopying & NSObjectProtocol)?, tur: String? = nil) -> AVMetadataItem? {
            guard let deger else { return nil }
            let m = AVMutableMetadataItem()
            m.identifier = kimlik
            m.value = deger
            m.extendedLanguageTag = "und"
            if let tur { m.dataType = tur }
            return m
        }
        return [
            oge(.commonIdentifierTitle, etiket.baslik as NSString),
            oge(.commonIdentifierArtist, etiket.sanatci as NSString?),
            oge(.commonIdentifierDescription, etiket.aciklama.map { String($0.prefix(1000)) as NSString }),
            oge(.commonIdentifierCreationDate, etiket.tarih as NSString?),
            oge(.commonIdentifierArtwork, etiket.kapak as NSData?, tur: kCMMetadataBaseDataType_JPEG as String),
        ].compactMap { $0 }
    }

    /// Küçük resmi indirip kapak yapar; ses dosyalarında ortadan kare kırpılır.
    @concurrent static func kapak(_ adres: String?, kare: Bool) async -> Data? {
        guard let adres, let url = URL(string: adres),
              let (veri, _) = try? await URLSession.shared.data(from: url), let resim = UIImage(data: veri) else { return nil }
        var boyut = resim.size
        var kirpma = CGRect(origin: .zero, size: boyut)
        if kare {
            let kenar = min(boyut.width, boyut.height)
            kirpma = CGRect(x: (boyut.width - kenar) / 2, y: (boyut.height - kenar) / 2, width: kenar, height: kenar)
            boyut = kirpma.size
        }
        let olcek = min(1, 1280 / max(boyut.width, boyut.height))
        let hedef = CGSize(width: (boyut.width * olcek).rounded(), height: (boyut.height * olcek).rounded())
        let bicim = UIGraphicsImageRendererFormat()
        bicim.scale = 1
        let cizilen = UIGraphicsImageRenderer(size: hedef, format: bicim).image { _ in
            resim.draw(in: CGRect(x: -kirpma.minX * olcek, y: -kirpma.minY * olcek, width: resim.size.width * olcek, height: resim.size.height * olcek))
        }
        return cizilen.jpegData(compressionQuality: 0.85)
    }
}

// MARK: Parçalı MP4

/// YouTube'un DASH (parçalı) MP4'lerinde `moov` içindeki süreler dolu gelir; AVFoundation bunu boş bir
/// örnek tablosunun süresi sayıp parçaları arkasına ekler ve süre iki katına çıkar (ilk yarı boş).
/// Parçalı dosyalarda bu süreler 0 olmalıdır: mvhd/tkhd/mdhd süresi ve elst bölüm süresi yerinde sıfırlanır.
nonisolated enum MP4Onarici {
    @discardableResult
    static func parcaliSureleriSifirla(_ url: URL) -> Bool {
        guard let tutamac = try? FileHandle(forUpdating: url) else { return false }
        defer { try? tutamac.close() }
        // Üst düzey kutuları gez: moov'u ve ardından moof olup olmadığını bul.
        var konum: UInt64 = 0
        var moov: (konum: UInt64, boyut: Int)?
        var parcali = false
        for _ in 0..<64 {
            try? tutamac.seek(toOffset: konum)
            guard let baslik = try? tutamac.read(upToCount: 16), baslik.count >= 8 else { break }
            var boyut = UInt64(baslik.prefix(4).reduce(0) { $0 << 8 | UInt32($1) })
            let tur = String(decoding: baslik[4..<8], as: UTF8.self)
            if boyut == 1, baslik.count >= 16 { boyut = baslik[8..<16].reduce(0) { $0 << 8 | UInt64($1) } }
            if tur == "moov", boyut < 50_000_000 { moov = (konum, Int(boyut)) }
            if tur == "moof" { parcali = true; break }
            guard boyut >= 8 else { break }
            konum += boyut
        }
        guard parcali, let moov else { return false }
        try? tutamac.seek(toOffset: moov.konum)
        guard var veri = try? tutamac.read(upToCount: moov.boyut), veri.count == moov.boyut else { return false }
        sifirla(&veri, 8, veri.count)
        try? tutamac.seek(toOffset: moov.konum)
        try? tutamac.write(contentsOf: veri)
        return true
    }

    static func sifirla(_ b: inout Data, _ bas: Int, _ son: Int) {
        var i = bas
        func u32(_ j: Int) -> Int { Int(b[j]) << 24 | Int(b[j + 1]) << 16 | Int(b[j + 2]) << 8 | Int(b[j + 3]) }
        func sil(_ j: Int, _ n: Int) { guard j + n <= son else { return }; b.replaceSubrange(j..<(j + n), with: Data(count: n)) }
        while i + 8 <= son {
            let n = u32(i)
            guard n >= 8, i + n <= son else { return }
            let tur = String(decoding: b[(i + 4)..<(i + 8)], as: UTF8.self)
            let g = i + 8, surum = b[g]
            switch tur {
            case "mvhd", "mdhd": surum == 0 ? sil(g + 16, 4) : sil(g + 24, 8)
            case "tkhd": surum == 0 ? sil(g + 20, 4) : sil(g + 28, 8)
            case "elst":
                var j = g + 8
                for _ in 0..<min(u32(g + 4), 64) {
                    surum == 0 ? sil(j, 4) : sil(j, 8)
                    j += surum == 0 ? 12 : 20
                }
            case "moov", "trak", "mdia", "edts": sifirla(&b, g, i + n)
            default: break
            }
            i += n
        }
    }
}

// MARK: Altyazı

nonisolated struct AltyaziSatiri: Sendable, Hashable {
    var baslangic: Double
    var bitis: Double
    var metin: String
}

nonisolated enum Altyazi {
    /// WebVTT'yi ayrıştırır; YouTube otomatik altyazılarındaki kelime zaman etiketlerini ve kayan tekrarları temizler.
    static func vtt(_ metin: String) -> [AltyaziSatiri] {
        var sonuc: [AltyaziSatiri] = []
        var oncekiSatirlar: Set<String> = []
        let bloklar = metin.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for blok in bloklar {
            let satirlar = blok.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let zamanSirasi = satirlar.firstIndex(where: { $0.contains("-->") }) else { continue }
            let uclar = satirlar[zamanSirasi].components(separatedBy: "-->")
            guard uclar.count == 2, let bas = zaman(uclar[0]), let son = zaman(uclar[1].split(separator: " ").first.map(String.init) ?? "") else { continue }
            let govde = satirlar[(zamanSirasi + 1)...].map(temizle).filter { !$0.isEmpty }
            let yeni = govde.filter { !oncekiSatirlar.contains($0) }
            oncekiSatirlar = Set(govde)
            guard !yeni.isEmpty, son - bas > 0.05 else { continue }
            let metin = yeni.joined(separator: "\n")
            if let son0 = sonuc.last, son0.metin == metin { sonuc[sonuc.count - 1].bitis = son; continue }
            sonuc.append(AltyaziSatiri(baslangic: bas, bitis: son, metin: metin))
        }
        // Kayan altyazıda bir satır bir sonrakiyle çakışmasın.
        for i in sonuc.indices.dropLast() where sonuc[i].bitis > sonuc[i + 1].baslangic {
            sonuc[i].bitis = sonuc[i + 1].baslangic
        }
        return sonuc
    }

    /// SRT ayrıştırıcısı (kütüphanedeki .srt dosyalarını oynatıcıda göstermek için).
    static func srt(_ metin: String) -> [AltyaziSatiri] {
        metin.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").compactMap { blok in
            let satirlar = blok.split(separator: "\n").map(String.init)
            guard let i = satirlar.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let uclar = satirlar[i].components(separatedBy: "-->")
            guard uclar.count == 2, let bas = zaman(uclar[0]), let son = zaman(uclar[1]) else { return nil }
            let govde = satirlar[(i + 1)...].joined(separator: "\n")
            return govde.isEmpty ? nil : AltyaziSatiri(baslangic: bas, bitis: son, metin: govde)
        }
    }

    static func srtMetni(_ satirlar: [AltyaziSatiri]) -> String {
        satirlar.enumerated().map { i, s in "\(i + 1)\n\(srtZamani(s.baslangic)) --> \(srtZamani(s.bitis))\n\(s.metin)\n" }.joined(separator: "\n")
    }

    static func srtZamani(_ t: Double) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// "01:02:03.456", "02:03.456" ya da "00:00:01,000".
    static func zaman(_ metin: String) -> Double? {
        let temiz = metin.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parcalar = temiz.split(separator: ":").map { Double($0) }
        guard !parcalar.isEmpty, parcalar.allSatisfy({ $0 != nil }) else { return nil }
        return parcalar.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    static func temizle(_ satir: String) -> String {
        var s = satir.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (kod, harf) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&#39;", "'"), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: kod, with: harf)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
