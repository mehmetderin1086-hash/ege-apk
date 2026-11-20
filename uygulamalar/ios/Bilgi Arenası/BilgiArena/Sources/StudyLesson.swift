import Foundation
import SwiftUI

struct StudyLesson: Codable, Equatable, Hashable {
    let exam: String
    var lesson: String? = nil
    var isValid: Bool { StudyCatalog.exams.contains(exam) && (lesson == nil || (1...60).contains(lesson!.trimmingCharacters(in:.whitespacesAndNewlines).count)) }
    var title: String { exam + (lesson.map { " · "+$0 } ?? " · Tüm dersler") }
    func matches(_ other: StudyLesson?) -> Bool { guard let other else { return false }; return exam == other.exam && (lesson == nil || lesson == other.lesson) }
}
enum StudyCatalog {
    static let exams = ["TYT","AYT","KPSS","LGS"]
    static func lessons(_ exam: String) -> [String] {
        switch exam {
        case "TYT": return ["Türkçe","Matematik","Geometri","Fizik","Kimya","Biyoloji","Tarih","Coğrafya","Felsefe","Din Kültürü"]
        case "AYT": return ["Türk Dili ve Edebiyatı","Matematik","Geometri","Fizik","Kimya","Biyoloji","Tarih","Coğrafya","Felsefe Grubu","Din Kültürü"]
        case "KPSS": return ["Türkçe","Matematik","Tarih","Coğrafya","Vatandaşlık"]
        case "LGS": return ["Türkçe","Matematik","Fen Bilimleri","T.C. İnkılap Tarihi","İngilizce","Din Kültürü"]
        default: return []
        }
    }
    static func daily(_ offset: Int) -> StudyLesson {
        let list = exams.flatMap { exam in lessons(exam).map { StudyLesson(exam:exam,lesson:$0) } }
        return list[max(0,offset)%list.count]
    }
}
struct StudyLessonPicker: View {
    @Binding var selection: StudyLesson?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Sınav ve ders").font(.subheadline.bold())
            Picker("Sınav",selection:Binding(get:{ selection?.exam ?? "" },set:{ selection = $0.isEmpty ? nil : StudyLesson(exam:$0) })) {
                Text("Tüm sınavlar").tag(""); ForEach(StudyCatalog.exams,id:\.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("studyExam")
            if let selected = selection {
                Picker("Ders",selection:Binding(get:{ selection?.lesson ?? "" },set:{ selection = StudyLesson(exam:selected.exam,lesson:$0.isEmpty ? nil : $0) })) {
                    Text("Tüm dersler").tag(""); ForEach(StudyCatalog.lessons(selected.exam),id:\.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("studyLesson")
            }
        }.tint(aqua)
    }
}
