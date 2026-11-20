import SwiftUI

/// Çalış sekmesindeki ek araçlar. Ham değer `-openTool=<ad>` hata ayıklama argümanıyla da kullanılır.
enum ToolKind: String, CaseIterable, Identifiable {
    case mockExams, grades, absences, countdowns, questionLog, questionTimer
    case habits, goals, todos, journal, revisions, reading, badges, heatMap
    case cardBrowser, cardCreate, typeReview, matchGame
    case mentalMath, speedRead, schulte, digitSpan, breathing
    case calculator, units, periodicTable, whiteboard, quotes

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case exam = "Sınav ve notlar", routine = "Alışkanlık ve hedef", cards = "Kartlarım", brain = "Zihin antrenmanı", utility = "Pratik araçlar"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .mockExams, .grades, .absences, .countdowns, .questionLog, .questionTimer: .exam
        case .habits, .goals, .todos, .journal, .revisions, .reading, .badges, .heatMap: .routine
        case .cardBrowser, .cardCreate, .typeReview, .matchGame: .cards
        case .mentalMath, .speedRead, .schulte, .digitSpan, .breathing: .brain
        case .calculator, .units, .periodicTable, .whiteboard, .quotes: .utility
        }
    }

    var title: String {
        switch self {
        case .mockExams: "Deneme takibi"
        case .grades: "Not ortalaması"
        case .absences: "Devamsızlık"
        case .countdowns: "Sınav geri sayımı"
        case .questionLog: "Soru takibi"
        case .questionTimer: "Soru kronometresi"
        case .habits: "Alışkanlıklar"
        case .goals: "Hedefler"
        case .todos: "Öncelik matrisi"
        case .journal: "Öğrenme günlüğü"
        case .revisions: "Konu tekrar takvimi"
        case .reading: "Okuma takibi"
        case .badges: "Rozetler"
        case .heatMap: "Çalışma haritası"
        case .cardBrowser: "Kartlarım"
        case .cardCreate: "Kart ekle / içe aktar"
        case .typeReview: "Yazarak tekrar"
        case .matchGame: "Eşleştirme oyunu"
        case .mentalMath: "Zihinden işlem"
        case .speedRead: "Hızlı okuma"
        case .schulte: "Schulte tablosu"
        case .digitSpan: "Sayı hafızası"
        case .breathing: "Nefes egzersizi"
        case .calculator: "Hesap makinesi"
        case .units: "Birim çevirici"
        case .periodicTable: "Periyodik tablo"
        case .whiteboard: "Çizim tahtası"
        case .quotes: "Motivasyon duvarı"
        }
    }

    var symbol: String {
        switch self {
        case .mockExams: "chart.line.uptrend.xyaxis"
        case .grades: "percent"
        case .absences: "person.fill.xmark"
        case .countdowns: "hourglass"
        case .questionLog: "pencil.and.list.clipboard"
        case .questionTimer: "stopwatch"
        case .habits: "checkmark.circle"
        case .goals: "target"
        case .todos: "square.grid.2x2"
        case .journal: "book.closed"
        case .revisions: "arrow.triangle.2.circlepath"
        case .reading: "books.vertical"
        case .badges: "medal"
        case .heatMap: "square.grid.3x3.fill"
        case .cardBrowser: "rectangle.stack"
        case .cardCreate: "rectangle.stack.badge.plus"
        case .typeReview: "keyboard"
        case .matchGame: "puzzlepiece"
        case .mentalMath: "plus.forwardslash.minus"
        case .speedRead: "text.word.spacing"
        case .schulte: "number.square"
        case .digitSpan: "brain"
        case .breathing: "wind"
        case .calculator: "function"
        case .units: "arrow.left.arrow.right"
        case .periodicTable: "atom"
        case .whiteboard: "pencil.tip.crop.circle"
        case .quotes: "quote.bubble"
        }
    }

    var color: Color {
        switch group {
        case .exam: .red
        case .routine: .green
        case .cards: Theme.blueInk
        case .brain: Theme.blueInk
        case .utility: Theme.goldInk
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .mockExams: MockExamsView()
        case .grades: GradesView()
        case .absences: AbsencesView()
        case .countdowns: CountdownsView()
        case .questionLog: QuestionLogView()
        case .questionTimer: QuestionTimerView()
        case .habits: HabitsView()
        case .goals: GoalsView()
        case .todos: TodoMatrixView()
        case .journal: JournalView()
        case .revisions: RevisionPlanView()
        case .reading: ReadingView()
        case .badges: BadgesView()
        case .heatMap: StudyHeatMapView()
        case .cardBrowser: CardBrowserView()
        case .cardCreate: CardCreateView()
        case .typeReview: TypeReviewView()
        case .matchGame: MatchGameView()
        case .mentalMath: MentalMathView()
        case .speedRead: SpeedReadView()
        case .schulte: SchulteView()
        case .digitSpan: DigitSpanView()
        case .breathing: BreathingView()
        case .calculator: CalculatorView()
        case .units: UnitConverterView()
        case .periodicTable: PeriodicTableView()
        case .whiteboard: WhiteboardView()
        case .quotes: QuotesView()
        }
    }

    /// Kutucuktaki sayı: bugün bekleyen iş.
    var badge: Int {
        switch self {
        case .revisions: RevisionPlanView.dueCount
        case .habits: JSONStore<Habit>("habits").items.filter { !$0.days.contains(DayKey.key()) }.count
        case .todos: JSONStore<TodoItem>("todos").items.filter { !$0.done && $0.urgent && $0.important }.count
        default: 0
        }
    }
}
