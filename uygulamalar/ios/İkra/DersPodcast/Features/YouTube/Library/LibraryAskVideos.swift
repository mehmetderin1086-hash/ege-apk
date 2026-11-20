import Foundation

/// #39: Kütüphane geneli Sor'a video derslerinin transkriptini sunucu sınırlarına sığdırarak hazırlar.
nonisolated enum LibraryAskPayload {
    static let maxVideos = 40
    static let maxParagraphsPerVideo = 600
    static let maxParagraphCharacters = 3000
    /// Sunucu sınırı 400.000; paylaşım payı bırakılır.
    static let maxTotalCharacters = 380_000

    /// 600'den fazla paragraf varsa bitişik paragrafları birleştirir (ilk paragrafın zamanı kalır); her parça ≤ 3000 karakter.
    static func compact(_ paragraphs: [TranscriptParagraph]) -> [LibraryAskVideoParagraph] {
        let clean = paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let group = max(1, Int((Double(clean.count) / Double(maxParagraphsPerVideo)).rounded(.up)))
        var out: [LibraryAskVideoParagraph] = []
        var index = 0
        while index < clean.count {
            let slice = clean[index..<min(clean.count, index + group)]
            let text = slice.map(\.text).joined(separator: " ")
            out.append(LibraryAskVideoParagraph(start: max(0, slice[slice.startIndex].start), text: String(text.prefix(maxParagraphCharacters))))
            index += group
        }
        return out
    }

    /// En yeni derslerden başlayarak toplam karakter bütçesine sığanları alır.
    static func videos(from lessons: [(id: UUID, title: String, paragraphs: [TranscriptParagraph])]) -> [LibraryAskVideo] {
        var budget = maxTotalCharacters
        var out: [LibraryAskVideo] = []
        for lesson in lessons {
            guard out.count < maxVideos, budget > 200 else { break }
            var kept: [LibraryAskVideoParagraph] = []
            for paragraph in compact(lesson.paragraphs) {
                guard budget > 0 else { break }
                let text = String(paragraph.text.prefix(budget))
                budget -= text.count
                kept.append(LibraryAskVideoParagraph(start: paragraph.start, text: text))
            }
            guard !kept.isEmpty else { continue }
            out.append(LibraryAskVideo(id: lesson.id.uuidString.lowercased(), title: String(lesson.title.prefix(300)), paragraphs: kept))
        }
        return out
    }

    /// Ders anlık görüntülerinden (transkript çözme ana iş parçacığı dışında) gönderilecek videolar.
    @concurrent
    static func build(_ snapshots: [LessonSnapshot]) async -> [LibraryAskVideo] {
        let decoded = snapshots.prefix(maxVideos).compactMap { snap -> (id: UUID, title: String, paragraphs: [TranscriptParagraph])? in
            guard let data = snap.transcriptData, let transcript = try? JSONDecoder().decode(VideoTranscript.self, from: data) else { return nil }
            return (snap.id, snap.title, transcript.paragraphs)
        }
        return videos(from: decoded)
    }
}
