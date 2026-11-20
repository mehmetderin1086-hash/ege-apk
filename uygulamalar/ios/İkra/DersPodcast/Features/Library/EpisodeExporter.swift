import Foundation
import SwiftData
import UIKit

// MARK: - Öneri 22 + #45: Markdown / PDF dışa aktarma (çalışma föyü)

enum EpisodeExporter {
    /// Föy: özet, notlarım, Cornell, kavramlar, formüller, slaytlar, transkript (başlıklar uygulamada o anı açar), quiz, kartlar.
    static func markdown(_ episode: Episode) -> String {
        StudySheetExport.markdown(StudySheetExport.input(for: episode))
    }

    static func writeMarkdown(_ episode: Episode) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(safeName(episode.title)).md")
        try markdown(episode).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Sayfalı PDF (A4); başlık ve not zamanları tıklanabilir `kocum://` bağlantılarıdır.
    static func writePDF(_ episode: Episode) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(safeName(episode.title)).pdf")
        try StudySheetExport.pdfData(sections: [markdown(episode)]).write(to: url)
        return url
    }

    /// Aynı föy; metin ana iş parçacığında toplanır, PDF dizgisi arka planda üretilir (arayüz donmaz).
    static func writePDFInBackground(_ episode: Episode) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(safeName(episode.title)).pdf")
        try await StudySheetExport.writePDF(sections: [markdown(episode)], to: url)
        return url
    }

    static func safeName(_ s: String) -> String {
        let name = String(s.map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }.prefix(60)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Bolum" : name
    }
}
