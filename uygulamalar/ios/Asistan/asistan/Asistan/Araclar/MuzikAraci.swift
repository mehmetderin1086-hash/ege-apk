import Foundation
import FoundationModels
import MediaPlayer

/// Sistem müzik oynatıcısı (Apple Music / Müzik uygulaması) denetimi + şarkı arama ve çalma.
/// Arama Apple'ın herkese açık iTunes arama servisiyle yapılır; sonuç mesajda 30 sn yasal önizleme + Apple Music bağlantısı olarak gösterilir.
nonisolated struct MuzikAraci: Tool {
    let name = "muzik"
    let description = "Müzik: 'ara' (sorgu: şarkı/sanatçı; Apple Music'te bulur, kullanıcıya dinlenebilir önizleme ve Apple Music bağlantısı gösterir), 'cal' (sorgu: şarkıyı Apple Music'te çalar; abonelikle kullanıcı orada çevrimdışı indirebilir), 'oynat', 'duraklat', 'sonraki', 'onceki', 'karistir', 'calan'. Yalnız çalma/dinleme/önizleme içindir; şarkı/klip indirme istekleri indirmeler aracıyla ('ekle', tur: audio/video) yapılır."

    @Generable
    struct Arguments {
        @Guide(description: "'ara', 'cal', 'oynat', 'duraklat', 'sonraki', 'onceki', 'karistir', 'calan'") var islem: String
        @Guide(description: "ara/cal için şarkı, sanatçı ya da ikisi; diğerlerinde boş") var sorgu: String
    }

    struct Parca: Decodable, Sendable {
        let trackId: Int
        let trackName: String
        let artistName: String
        let collectionName: String?
        let trackViewUrl: String?
        let previewUrl: String?
        let releaseDate: String?
    }
    private struct Yanit: Decodable { let results: [Parca] }

    /// iTunes arama (Türkiye mağazası); sonuçlar popülerliğe göre sıralı gelir.
    static func ara(_ sorgu: String, adet: Int = 5) async throws -> [Parca] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: sorgu), .init(name: "entity", value: "song"), .init(name: "country", value: "tr"), .init(name: "limit", value: String(adet))]
        let (veri, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(Yanit.self, from: veri).results
    }

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.lowercased()
        if islem == "ara" || islem == "cal" || islem == "çal" {
            let s = a.sorgu.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return "Şarkı ya da sanatçı adı ver." }
            let sonuc = try await Self.ara(s, adet: islem == "ara" ? 6 : 1)
            guard let ilk = sonuc.first else { return "Apple Music'te '\(s)' bulunamadı." }
            await MainActor.run {
                let onizleme = sonuc.compactMap { p in p.previewUrl.flatMap(URL.init(string:)).map { MedyaOgesi(tur: .ses, url: $0, ad: "\(p.trackName) – \(p.artistName) (30 sn önizleme)") } }
                if !onizleme.isEmpty { EkDefteri.ortak.ekle(MesajEki(tur: .medya(onizleme))) }
                let baglantilar = sonuc.compactMap(\.trackViewUrl)
                if !baglantilar.isEmpty { EkDefteri.ortak.ekle(MesajEki(tur: .kaynaklar(baglantilar))) }
            }
            if islem == "ara" {
                return "Apple Music sonuçları (popülerlik sırasıyla):\n" + sonuc.enumerated().map { "\($0.offset + 1). \($0.element.trackName) – \($0.element.artistName)" + ($0.element.collectionName.map { " (\($0))" } ?? "") }.joined(separator: "\n")
                    + "\nKullanıcı mesajdaki kartta 30 sn önizlemeleri dinleyebilir; tam şarkı için 'cal' kullan."
            }
            // Arama sürerken kullanıcı durdurduysa müzik sonradan çalmaya başlamasın.
            try Task.checkCancellation()
            await MainActor.run {
                let p = MPMusicPlayerController.systemMusicPlayer
                p.setQueue(with: [String(ilk.trackId)]); p.play()
            }
            return "Apple Music'te çalınıyor: \(ilk.trackName) – \(ilk.artistName). Apple Music aboneliği varsa kullanıcı Müzik uygulamasında şarkıyı kitaplığa ekleyip çevrimdışı indirebilir; abonelik yoksa kartta 30 sn önizleme ve Apple Music bağlantısı var."
        }
        return await MainActor.run {
            let p = MPMusicPlayerController.systemMusicPlayer
            switch islem {
            case "oynat": p.play(); return "Müzik oynatılıyor."
            case "duraklat": p.pause(); return "Müzik duraklatıldı."
            case "sonraki": p.skipToNextItem(); return "Sonraki parçaya geçildi."
            case "onceki", "önceki": p.skipToPreviousItem(); return "Önceki parçaya geçildi."
            case "karistir", "karıştır": p.shuffleMode = .songs; p.play(); return "Karıştırma açık, oynatılıyor."
            case "calan", "çalan":
                guard let o = p.nowPlayingItem else { return "Şu an bir şey çalmıyor." }
                return "Çalan: \(o.title ?? "?")\(o.artist.map { " – \($0)" } ?? "")."
            default: return "Bilinmeyen işlem: \(a.islem)."
            }
        }
    }
}
