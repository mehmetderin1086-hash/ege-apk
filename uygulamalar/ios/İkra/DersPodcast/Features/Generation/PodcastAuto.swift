import Foundation

/// Tek dokunuşla podcast: süre belgeye göre seçilir, anlatım okul yazılısına göre yönlendirilir.
nonisolated enum PodcastAuto {
    static let autoDurationKey = "podcast.autoDuration", schoolExamKey = "podcast.schoolExam"
    /// Süre belgeye göre seçilsin (varsayılan açık).
    static var autoDuration: Bool { UserDefaults.standard.object(forKey: autoDurationKey) as? Bool ?? true }
    /// Anlatım okul yazılısına dönük olsun (varsayılan açık).
    static var schoolExam: Bool { UserDefaults.standard.object(forKey: schoolExamKey) as? Bool ?? true }

    /// Kaynakların yaklaşık metin uzunluğu: PDF'te sayfa başına ~1800, fotoğrafta ~1200 karakter varsayılır.
    static func characters(_ sources: [ImportedSource]) -> Int {
        sources.reduce(0) { total, source in
            switch source.kind {
            case .text(let text): total + text.count
            case .pdf(_, let pages): total + (source.pageRange.map { $0.count } ?? pages) * 1800
            case .image: total + 1200
            }
        }
    }
    /// Belge uzunluğuna uygun bölüm süresi (dakika): kısa nota kısa tekrar, uzun üniteye bölümlere ayrılmış uzun anlatım.
    static func duration(characters: Int) -> Int {
        switch characters {
        case ..<3_000: 5
        case ..<9_000: 10
        case ..<18_000: 15
        case ..<30_000: 20
        case ..<55_000: 30
        case ..<90_000: 45
        default: 60
        }
    }
    static func duration(_ sources: [ImportedSource]) -> Int { duration(characters: characters(sources)) }

    /// Senaryo yönergesi: kaynağa sadık, sohbetsiz, yazılıda çıkabilecek sorularla.
    static let schoolDirective = "OKUL YAZILISINA HAZIRLIK: Dinleyici lise öğrencisi ve okul yazılısına çalışıyor. Yalnız kaynaktaki bilgiyi anlat; kaynakta olmayan bilgi, örnek, tarih ya da sayı ekleme. Selamlaşma, uzun giriş, espri ve konu dışı sohbet yapma; ilk cümleden konuya gir. Tanımları, sınıflandırmaları ve neden-sonuç ilişkilerini kaynaktaki terimlerle ver. Her ana başlığın sonunda \"yazılıda şöyle sorulabilir\" diyerek bir ya da iki açık uçlu soru sor ve kâğıda yazılacak kısa cevabı söyle. Bölümün sonunda en önemli noktaları numaralayarak özetle."
}
