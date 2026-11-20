import AppIntents
import SwiftUI
import WidgetKit

// #19: Denetim Merkezi / kilit ekranı denetimleri. Intent'ler `Shared/PlaybackIntents.swift` içinde;
// iş uygulama sürecinde (AudioPlaybackIntent) yürür — cihazda doğrulanmalı.

struct BookmarkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.derspodcast.control.bookmark") {
            ControlWidgetButton(action: BookmarkPlaybackIntent()) {
                Label("İşaretle", systemImage: "bookmark.fill")
            }
        }
        .displayName("Podcast'te işaretle")
        .description("Çalan podcast'te şu anki yere yer imi koyar.")
    }
}

struct SkipBack15Control: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.derspodcast.control.back15") {
            ControlWidgetButton(action: SkipBack15Intent()) {
                Label("15 sn geri", systemImage: "gobackward.15")
            }
        }
        .displayName("Podcast: 15 sn geri")
        .description("Çalan podcast'i 15 saniye geri alır.")
    }
}

struct NextChapterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.derspodcast.control.nextChapter") {
            ControlWidgetButton(action: NextChapterIntent()) {
                Label("Sonraki konu", systemImage: "forward.end")
            }
        }
        .displayName("Podcast: sonraki konu")
        .description("Çalan podcast'te sonraki konuya geçer.")
    }
}

struct ResumeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.derspodcast.control.resume") {
            ControlWidgetButton(action: ResumePlaybackIntent()) {
                Label("Sürdür", systemImage: "play.circle")
            }
        }
        .displayName("Podcast'i sürdür")
        .description("Son dinlediğin podcast'i kaldığı yerden çalar.")
    }
}
