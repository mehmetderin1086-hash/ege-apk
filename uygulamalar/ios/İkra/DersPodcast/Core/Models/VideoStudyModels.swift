import Foundation
import SwiftData

/// Takip edilen YouTube kanalı ya da oynatma listesi: yeni video gelince bildirim (isteğe bağlı otomatik işleme).
@Model
final class FollowedChannel {
    var id: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var lastChecked: Date?
    /// Daha önce görülen video kimlikleri (yeni olanı ayırmak için).
    var knownVideoIDs: [String] = []
    var autoProcess: Bool = false
    var courseID: UUID?
    var createdAt: Date = Date.now

    init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}

/// Video dersine zaman damgalı not (isteğe bağlı fotoğraf; dosya ders klasöründe).
@Model
final class TimedNote {
    var id: UUID = UUID()
    var lessonID: UUID = UUID()
    var time: Double = 0
    var text: String = ""
    var photoFileName: String?
    var createdAt: Date = Date.now

    init(lessonID: UUID, time: Double, text: String) {
        self.lessonID = lessonID
        self.time = time
        self.text = text
    }
}
