import SwiftUI

/// Ders ekranındaki ek araçların ortak bağlamı: ders, transkript, oynatıcı ve transkript değişince kaydetme.
struct LessonContext {
    let lesson: VideoLesson
    let transcript: VideoTranscript
    let player: VideoPlayerModel
    /// Transkript değişti (ör. terim düzeltme): ekrana ve kayda yansıt.
    let update: (VideoTranscript) -> Void
    /// Ders Stüdyosu'nu tümüyle kapatır (üretilen bölüm kütüphanede açılırken); yoksa nil.
    var closeStudio: (() -> Void)?
}

/// Ders ekranından açılan sayfalar.
enum LessonSheet: Identifiable, Hashable {
    // Çalışma araçları
    case quiz(chapter: Int?)
    case explain(time: Double)
    case teacherSummary
    case examPrep
    case exam
    case studyExport
    case feynman(chapter: Int?)
    case prereq
    case compare
    case worksheet
    case timedNotes
    case slides
    case dub
    case ankiExport
    // Dinleme ve metin
    case terms
    // Kütüphane ve dosyalar
    case course
    case frameText
    case subtitledVideo
    case offlineVideo

    var id: String { String(describing: self) }
}

/// "Çalış" menüsü: öğrenme araçları.
struct LessonStudyMenu: View {
    var open: (LessonSheet) -> Void
    /// Dokunulduğu anda okunur (gövde her oynatıcı tikinde yeniden çizilmesin).
    var currentChapter: () -> Int?
    @AppStorage(StudyPrefs.chapterQuizKey) private var autoQuiz = false

    var body: some View {
        Menu {
            // En çok kullanılanlar üstte; diğer araçlar "Tüm araçlar" altında.
            Button("Yazılıya hazırlan", systemImage: "pencil.and.list.clipboard") { open(.examPrep) }
            Button("Bölüm quiz'i", systemImage: "checklist") { open(.quiz(chapter: currentChapter())) }
            Button("Zamanlı not al", systemImage: "note.text") { open(.timedNotes) }
            Button("Çalışma kâğıdı (PDF)", systemImage: "doc.on.clipboard") { open(.worksheet) }
            Menu("Tüm araçlar", systemImage: "square.grid.2x2") {
                Section("Kendini dene") {
                    Toggle("Her bölüm sonunda quiz", systemImage: "pause.circle", isOn: $autoQuiz)
                    Button("ÖSYM tarzı deneme", systemImage: "doc.text.magnifyingglass") { open(.exam) }
                    Button("Feynman: kendi cümlelerinle anlat", systemImage: "person.wave.2") { open(.feynman(chapter: currentChapter())) }
                    Button("Ön bilgi kontrolü", systemImage: "list.bullet.clipboard") { open(.prereq) }
                }
                Section("Tekrar") {
                    Button("Öğretmenin sesinden özet", systemImage: "waveform.badge.magnifyingglass") { open(.teacherSummary) }
                    Button("Kavram ve formülleri Çalış'a aktar", systemImage: "square.and.arrow.down.on.square") { open(.studyExport) }
                    Button("Başka bir videoyla karşılaştır", systemImage: "rectangle.split.2x1") { open(.compare) }
                }
                Section("Çıktılar") {
                    Button("Slayt destesi", systemImage: "rectangle.on.rectangle") { open(.slides) }
                    Button("Türkçe dublaj", systemImage: "speaker.wave.2.bubble") { open(.dub) }
                    Button("Anki / CSV", systemImage: "tablecells") { open(.ankiExport) }
                }
            }
        } label: {
            Label("Çalış", systemImage: "graduationcap")
        }
    }
}

/// Araçlar menüsüne eklenen ders ve dosya öğeleri.
struct LessonMoreItems: View {
    var open: (LessonSheet) -> Void

    var body: some View {
        Section {
            Button("Derse bağla ve etiketler", systemImage: "folder.badge.gearshape") { open(.course) }
            Button("Terim düzeltme", systemImage: "character.cursor.ibeam") { open(.terms) }
            Button("Karelerdeki yazılar", systemImage: "text.viewfinder") { open(.frameText) }
            Button("Videoyu çevrimdışı indir", systemImage: "arrow.down.circle") { open(.offlineVideo) }
            Button("Türkçe altyazılı video", systemImage: "captions.bubble.fill") { open(.subtitledVideo) }
        }
    }
}

/// Seçilen sayfanın görünümü.
struct LessonSheetHost: View {
    var sheet: LessonSheet
    var context: LessonContext

    var body: some View {
        page.modifier(LessonSheetPresenceModifier())
    }

    @ViewBuilder
    private var page: some View {
        switch sheet {
        case .quiz(let chapter): ChapterQuizView(context: context, chapter: chapter)
        case .explain(let time): ExplainView(context: context, time: time)
        case .teacherSummary: TeacherSummaryView(context: context)
        case .examPrep: LessonExamPrepView(context: context)
        case .exam: LessonExamView(context: context)
        case .studyExport: StudyExportView(context: context)
        case .feynman(let chapter): LessonFeynmanView(context: context, chapter: chapter)
        case .prereq: PrereqView(context: context)
        case .compare: CompareLessonsView(context: context)
        case .worksheet: WorksheetView(context: context)
        case .timedNotes: TimedNotesView(context: context)
        case .slides: LessonSlidesView(context: context)
        case .dub: DubbingView(context: context)
        case .ankiExport: AnkiExportView(context: context)
        case .terms: TermCorrectionView(context: context)
        case .course: LessonCourseView(context: context)
        case .frameText: FrameTextView(context: context)
        case .subtitledVideo: SubtitledVideoView(context: context)
        case .offlineVideo: OfflineVideoView(context: context)
        }
    }
}
