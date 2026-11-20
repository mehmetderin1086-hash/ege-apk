import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DersPodcastWidgets: WidgetBundle {
    var body: some Widget {
        GenerationLiveActivity()
        BookmarkControl()
        SkipBack15Control()
        NextChapterControl()
        ResumeControl()
    }
}
