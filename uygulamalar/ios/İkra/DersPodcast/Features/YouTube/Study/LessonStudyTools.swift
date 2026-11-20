import SwiftData
import SwiftUI
import UIKit

// Ders çalışma araçlarının ortak parçaları ve bölüm sonu quiz tetikleyicisi.
// Görünümler: LessonQuizViews (#18 #23 #26), LessonExplainView (#19), LessonFeynmanViews (#25 #27),
// LessonTeacherSummary (#20), LessonTimedNotes (#22), LessonExportViews (#24 #28 #34 #37), LessonDubbing (#35).

enum StudyPrefs {
    /// "Bölüm sonunda quiz": bölüm bitince video durur ve 3 soru sorulur.
    static let chapterQuizKey = "lesson.chapterQuizAuto"
}

// MARK: - Ortak kabuk ve durumlar

/// Çalışma sayfası kabuğu: başlık + "Kapat".
struct StudySheet<Content: View>: View {
    var title: String
    /// Açıkken sayfa aşağı çekilerek kapatılamaz (süren sınav gibi, kapanınca emeğin kaybolduğu durumlar).
    var guardDismiss = false
    /// Verilirse "Kapat" sayfayı doğrudan kapatmak yerine bunu çağırır (onay sormak için).
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { if let onClose { onClose() } else { dismiss() } }
                    }
                }
        }
        .interactiveDismissDisabled(guardDismiss)
        .debugNarrowScreen()
    }
}

/// Ağ çağrısı beklenirken: ilerleme göstergesi + (isteğe bağlı) vazgeç.
struct StudyLoadingView: View {
    var message: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let onCancel { Button("Vazgeç", action: onCancel).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Hata + "Tekrar dene".
struct StudyErrorView: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).font(.callout).multilineTextAlignment(.center)
            if let retry { Button("Tekrar dene", action: retry).buttonStyle(.borderedProminent) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

enum StudyError {
    /// Kullanıcıya gösterilecek metin; iptal sessizce yutulur (nil).
    static func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
        return (error as? APIError)?.message ?? error.localizedDescription
    }
}

/// Sunucu çağrısının durumu.
enum StudyPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension LessonContext {
    /// Dersin metninin bittiği an (işlenen aralığın sonu).
    var contentEnd: Double {
        TranscriptFormat.chaptersEnd(videoDuration: transcript.video.duration > 0 ? transcript.video.duration : lesson.duration,
                                     transcript: transcript)
    }

    var sortedChapters: [VideoChapter] { transcript.chapters.sorted { $0.start < $1.start } }

    /// Çalışma araçları açılınca video susar (ses ya da sunucu cevabıyla çakışmasın).
    func pausePlayback() {
        if player.isPlaying { player.pause() }
    }

    /// Sayfayı kapatıp videoyu verilen ana götürür.
    func resume(at time: Double) {
        player.seek(to: max(0, time))
        player.play()
    }
}

// MARK: - Quiz bileşenleri

/// Çoktan seçmeli sorunun şıkları. `reveal` açıksa doğru/yanlış renklenir; kapalıysa yalnızca seçim gösterilir.
struct QuizChoices: View {
    var question: StudyQuestion
    var selected: Int?
    var reveal: Bool
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                Button { onSelect(index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(StudyQuizRules.letter(index)).font(.subheadline.bold()).frame(minWidth: 20)
                        Text(choice).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if reveal, index == question.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if reveal, index == selected {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(fill(index), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(stroke(index), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(reveal)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }
    }

    private func fill(_ index: Int) -> Color {
        if reveal {
            if index == question.answer { return .green.opacity(0.15) }
            if index == selected { return .red.opacity(0.15) }
        } else if index == selected {
            return Color.accentColor.opacity(0.18)
        }
        return Color(.secondarySystemBackground)
    }

    private func stroke(_ index: Int) -> Color {
        if reveal {
            if index == question.answer { return .green }
            if index == selected { return .red }
        } else if index == selected {
            return .accentColor
        }
        return .clear
    }
}

/// Cevap sonrası açıklama.
struct QuizExplanation: View {
    var question: StudyQuestion
    var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(selected == question.answer ? "Doğru" : "Doğru cevap: \(StudyQuizRules.letter(question.answer))",
                  systemImage: selected == question.answer ? "checkmark.seal.fill" : "lightbulb.fill")
                .font(.subheadline.bold())
                .foregroundStyle(selected == question.answer ? .green : .orange)
            if !question.explanation.isEmpty {
                Text(question.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let time = question.time {
                Text("Anlatıldığı yer: \(TranscriptFormat.timestamp(time))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Küçük yardımcılar

/// Madde işaretli kısa liste (sığmazsa satır kırar).
struct StudyBulletList: View {
    var items: [String]
    var symbol = "circle.fill"
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 6)).foregroundStyle(tint)
                    Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Satır kıran etiket yerleşimi (anahtar terimler).
struct StudyFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// Anahtar terim etiketleri.
struct StudyTags: View {
    var terms: [String]

    var body: some View {
        StudyFlowLayout {
            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                Text(term)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - Bölüm sonunda quiz (#18)

nonisolated enum ChapterQuizTiming {
    /// Çalma sırasında bölümün bittiği an yakalandıysa o bölümün sırası. İki yoklama arası `maxStep` sn'den büyükse
    /// kullanıcı atlamıştır (sayılmaz). Sınır, bölümün bitişinden `lead` sn önce sayılır (video hemen susar).
    /// `minLength`'ten kısa bölümler (ve boş sınırlar) atlanır.
    static func finishedChapter(previous: Double, current: Double, chapters: [VideoChapter], end: Double,
                                maxStep: Double = 3, lead: Double = 0.3, minLength: Double = 60) -> Int? {
        guard current > previous, current - previous <= maxStep else { return nil }
        let sorted = chapters.sorted { $0.start < $1.start }
        for index in sorted.indices {
            guard let range = StudyText.chapterRange(sorted, index: index, end: end), range.duration >= minLength else { continue }
            let boundary = range.end - lead
            if previous < boundary, current >= boundary { return index }
        }
        return nil
    }
}

/// Ders ekranının üstünde açık çalışma sayfası sayısı (quiz, açık bir sayfanın üstüne binmesin).
@MainActor
enum LessonSheetPresence {
    static var open = 0
}

struct LessonSheetPresenceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { LessonSheetPresence.open += 1 }
            .onDisappear { LessonSheetPresence.open = max(0, LessonSheetPresence.open - 1) }
    }
}

/// Ders ekranına bağlı: ayar açıksa bölüm bitince video durur ve quiz sayfası açılır.
/// Konum izlemesi gövdede değil bir görevde (yoklama) yapılır; oynatıcının her tikinde ders ekranı yeniden çizilmez.
struct ChapterQuizTrigger: ViewModifier {
    var context: LessonContext?
    var present: (LessonSheet) -> Void
    @AppStorage(StudyPrefs.chapterQuizKey) private var enabled = false
    @State private var offered: Set<Int> = []

    func body(content: Content) -> some View {
        content
            .task(id: TriggerKey(enabled: enabled, hasContext: context != nil)) {
                guard enabled, let context else { return }
                await watch(context)
            }
            #if DEBUG
            // Simülatörde sayfaları denetlemek için: -lessonSheet=quiz|exam|explain|studyExport|teacherSummary|feynman|prereq|compare|worksheet|timedNotes|slides|dub|ankiExport
            .task(id: context != nil) {
                guard context != nil, let name = DebugArg.value("lessonSheet"), let sheet = Self.debugSheet(name) else { return }
                try? await Task.sleep(for: .seconds(1.5))
                present(sheet)
            }
            #endif
    }

    #if DEBUG
    private static func debugSheet(_ name: String) -> LessonSheet? {
        switch name {
        case "quiz": .quiz(chapter: 0)
        case "exam": .exam
        case "examPrep": .examPrep
        case "explain": .explain(time: 60)
        case "studyExport": .studyExport
        case "teacherSummary": .teacherSummary
        case "feynman": .feynman(chapter: nil)
        case "prereq": .prereq
        case "compare": .compare
        case "worksheet": .worksheet
        case "timedNotes": .timedNotes
        case "slides": .slides
        case "dub": .dub
        case "ankiExport": .ankiExport
        default: nil
        }
    }
    #endif

    private struct TriggerKey: Hashable { var enabled: Bool; var hasContext: Bool }

    /// Bölüm sınırı geçildiğinde koşullar uygun değilse (başka sayfa açık, uygulama arka planda) sınır tüketilmez:
    /// `pending` olarak bekler ve koşullar sağlanınca (sınırın ~15 sn ötesine kadar) sunulur.
    private func watch(_ context: LessonContext) async {
        let chapters = context.sortedChapters
        guard !chapters.isEmpty else { return }
        let end = context.contentEnd
        var previous = context.player.currentTime
        var pending: (index: Int, boundary: Double)?
        // En düşük sunum derinliği = ders ekranının kendi seviyesi; üstüne çıkan her sayfa (paylaşım, uyarı, kare kapağı) engeller.
        var baseDepth = Self.presentationDepth()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            let now = context.player.currentTime
            defer { previous = now }
            let depth = Self.presentationDepth()
            baseDepth = min(baseDepth, depth)
            if pending == nil, let index = ChapterQuizTiming.finishedChapter(previous: previous, current: now, chapters: chapters, end: end),
               !offered.contains(index), let range = StudyText.chapterRange(chapters, index: index, end: end) {
                pending = (index, range.end)
            }
            guard let candidate = pending else { continue }
            // Kullanıcı sınırdan uzaklaştıysa (geri sardı ya da çok ileri gitti) bekleyen quiz düşer.
            if now < candidate.boundary - 5 || now > candidate.boundary + 15 {
                pending = nil
                continue
            }
            // Video doğal sonunda oynatıcı yoklamadan önce durmuş olabilir: sona yakınsa yine say.
            guard context.player.isPlaying || now >= end - 0.6 else { continue }
            guard UIApplication.shared.applicationState == .active, LessonSheetPresence.open == 0, depth <= baseDepth else { continue }
            offered.insert(candidate.index)
            pending = nil
            context.player.pause()
            present(.quiz(chapter: candidate.index))
        }
    }

    /// Ekranda üst üste kaç sunum (sheet, uyarı, tam ekran) var.
    private static func presentationDepth() -> Int {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        var depth = 0
        while let next = controller?.presentedViewController {
            depth += 1
            controller = next
        }
        return depth
    }

}
