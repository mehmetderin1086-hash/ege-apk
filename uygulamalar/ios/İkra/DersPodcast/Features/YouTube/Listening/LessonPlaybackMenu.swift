import SwiftData
import SwiftUI

/// Oynatma menüsü: sessizlikleri atla, uyku zamanlayıcısı, döngü, Odakla izle. Kontrol çubuğunda tek simge
/// (dar ekranda düğme sayısı artmasın diye hepsi menüde).
struct LessonPlaybackMenu: View {
    var player: VideoPlayerModel
    var lessonID: UUID
    var courseID: UUID?
    @Environment(\.modelContext) private var context

    private var focus: FocusTimer { FocusTimer.shared }
    private var focusOnThisLesson: Bool { focus.isRunning && focus.episodeID == lessonID }
    private var anythingOn: Bool { player.loop != nil || player.sleep != nil || (player.skipSilence && player.canSkipSilence) || focusOnThisLesson }

    var body: some View {
        Menu {
            if player.canSkipSilence {
                Toggle(isOn: Binding(get: { player.skipSilence }, set: { player.skipSilence = $0 })) {
                    Label("Sessizlikleri atla", systemImage: "waveform.badge.minus")
                }
            }
            Menu("Uyku zamanlayıcısı", systemImage: "moon.zzz") {
                if player.sleep != nil {
                    Button("Kapat", systemImage: "xmark", role: .destructive) { player.cancelSleep() }
                }
                ForEach(LessonSleep.minuteOptions, id: \.self) { minutes in
                    Button("\(minutes) dakika sonra") { player.setSleep(minutes: minutes) }
                }
                Button("Bu bölüm bitince") { player.setSleepEndOfChapter() }
            }
            if player.loop != nil {
                Button("Döngüyü kapat", systemImage: "repeat.circle", role: .destructive) { player.clearLoop() }
            }
            Menu("Odakla izle", systemImage: "scope") {
                if focusOnThisLesson {
                    Button("Odağı bitir", systemImage: "stop.circle", role: .destructive) {
                        focus.finish(context: context, completed: focus.phase == .focus && focus.remaining == 0)
                    }
                } else {
                    ForEach(FocusTimer.presets) { preset in
                        Button("\(preset.name) dakika") { startFocus(preset) }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .symbolVariant(anythingOn ? .fill : .none)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(anythingOn ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityLabel("Oynatma seçenekleri")
    }

    /// Odak oturumunu bu derse bağlar ve başlatır (zamanlayıcı çalışıyorsa yalnızca bağlar). Ders `LessonListeningHooks` ile
    /// odak başlayınca çalar, molada durur.
    private func startFocus(_ preset: FocusTimer.Preset) {
        // Süresi dolmuş ama henüz kapanmamış oturum (uygulama arka plandayken biten) önce kendi dersine yazılsın.
        if focus.isRunning, focus.remaining == 0 { focus.finish(context: context, completed: true) }
        focus.courseID = courseID
        focus.episodeID = lessonID
        if !focus.isRunning {
            focus.preset = preset
            focus.start(.focus)
        }
        if focus.phase == .focus { player.play() }
    }
}

/// Etkin döngüyü ve uyku zamanlayıcısını gösteren ince şerit (yalnızca biri etkinse görünür).
struct LessonPlaybackStatusRow: View {
    var player: VideoPlayerModel

    var body: some View {
        if player.loop != nil || player.sleep != nil {
            // Kalan uyku süresi yazısı dakikada birkaç kez tazelenir.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                // Sarmalı düzen: dar ekranda iki şerit alt alta geçer, metin kesilmez.
                WrapLayout(spacing: 8, lineSpacing: 4) {
                    if let loop = player.loop {
                        chip("Döngü \(TranscriptFormat.timestamp(loop.start))–\(TranscriptFormat.timestamp(loop.end))", systemImage: "repeat",
                             tint: .green, label: "Döngüyü kapat") { player.clearLoop() }
                    }
                    if let sleep = player.sleep {
                        chip(sleepText(sleep), systemImage: "moon.zzz", tint: Theme.blueInk, label: "Uyku zamanlayıcısını kapat") { player.cancelSleep() }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
        }
    }

    private func sleepText(_ sleep: LessonSleep) -> String {
        if let remaining = player.sleepRemaining { return "Uyku \(max(1, Int((remaining / 60).rounded(.up)))) dk" }
        return "Bölüm sonunda dur"
    }

    private func chip(_ text: String, systemImage: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(text).lineLimit(1).minimumScaleFactor(0.75)
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
