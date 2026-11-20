#if DEBUG
import Foundation
import SwiftData

/// Yalnızca Debug: `-coursesDemo` ile Derslerim ekranlarını (program, ödev/sınav, dersler) dar ekranda denetlemek için
/// 2 ders, derslikli 3 program saati ve gecikmiş/bugün/gelecek 3 ödev tohumlar. `-coursesSection=0|1|2` açılış bölümünü seçer.
enum CoursesDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-coursesDemo") }

    static func seedIfRequested(context: ModelContext, now: Date = .now) {
        guard isRequested else { return }
        guard ((try? context.fetchCount(FetchDescriptor<Assignment>(predicate: #Predicate { $0.title.contains("Demo ·") }))) ?? 0) == 0 else { return }

        let calendar = Calendar.current
        let math = Course(name: "Matematik", colorHex: Course.palette[0])
        // Uzun ad: dar ekranda sarma denetimi.
        let literature = Course(name: "Türk Dili ve Edebiyatı", colorHex: Course.palette[1])
        context.insert(math)
        context.insert(literature)

        // İkisi bugüne: Koç'un "Bugün" kartında da görünsün.
        let weekday = calendar.component(.weekday, from: now)
        context.insert(Lesson(courseID: math.id, weekday: weekday, startMinute: 9 * 60, durationMinutes: 40, room: "B-204"))
        context.insert(Lesson(courseID: literature.id, weekday: weekday, startMinute: 10 * 60 + 40, durationMinutes: 80, room: "Konferans Salonu"))
        context.insert(Lesson(courseID: math.id, weekday: weekday % 7 + 1, startMinute: 13 * 60 + 30, durationMinutes: 40, room: "Laboratuvar 2"))

        func date(_ dayOffset: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        context.insert(Assignment(title: "Demo · Türev problemleri", kind: .homework, dueDate: date(-2, hour: 17), courseID: math.id))
        context.insert(Assignment(title: "Demo · Şiir incelemesi sunumu", kind: .project, dueDate: date(0, hour: 17), courseID: literature.id))
        context.insert(Assignment(title: "Demo · Birinci dönem yazılısı", kind: .exam, dueDate: date(9, hour: 9), courseID: math.id))
        try? context.save()
    }
}
#endif
