import SwiftUI

struct EBLetter: Identifiable, Hashable {
    let id: String
    let arabic: String
    let name: String
    let spokenName: String
    let hint: String
    let joinsNext: Bool
    var forms: [String] {
        [arabic, joinsNext ? arabic + "ـ" : arabic,
         joinsNext ? "ـ" + arabic + "ـ" : "ـ" + arabic, "ـ" + arabic]
    }
}

struct EBExample: Identifiable {
    let arabic: String
    let reading: String
    var id: String { arabic }
}
struct EBCheck: Identifiable {
    let prompt: String
    let choices: [String]
    let answer: Int
    let explanation: String
    var id: String { prompt }
}
struct EBLesson: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let summary: String
    let explanation: String
    let examples: [EBExample]
    let checks: [EBCheck]
}

enum EBCurriculum {
    static let letters: [EBLetter] = [
        .init(id: "alif", arabic: "ا", name: "Elif", spokenName: "أَلِف", hint: "Dik çizgi. Hemze ile elifin görevini birbirinden ayırmayı sonraki derslerde öğreniyoruz.", joinsNext: false),
        .init(id: "ba", arabic: "ب", name: "Be", spokenName: "بَاء", hint: "Altında bir nokta vardır. Dudaklar kapanıp açılır.", joinsNext: true),
        .init(id: "ta", arabic: "ت", name: "Te", spokenName: "تَاء", hint: "Üstünde iki nokta vardır. Be ve se ile gövdesi benzerdir.", joinsNext: true),
        .init(id: "tha", arabic: "ث", name: "Se", spokenName: "ثَاء", hint: "Üstünde üç nokta vardır. Peltek sestir; dil ucu üst ön dişlere yaklaşır.", joinsNext: true),
        .init(id: "jim", arabic: "ج", name: "Cim", spokenName: "جِيم", hint: "Gövdesinin içinde bir nokta vardır. Hâ ve hı ile şekil ailesidir.", joinsNext: true),
        .init(id: "ha", arabic: "ح", name: "Hâ", spokenName: "حَاء", hint: "Noktasızdır. Boğazdan çıkan bu sesi he ile karıştırmayın.", joinsNext: true),
        .init(id: "kha", arabic: "خ", name: "Hı", spokenName: "خَاء", hint: "Üstünde bir nokta vardır. Kalın sesli harflerdendir.", joinsNext: true),
        .init(id: "dal", arabic: "د", name: "Dal", spokenName: "دَال", hint: "Noktasızdır. Kendisinden sonraki harfe bağlanmaz.", joinsNext: false),
        .init(id: "dhal", arabic: "ذ", name: "Zel", spokenName: "ذَال", hint: "Dalın üzerinde bir nokta vardır. Peltek sestir.", joinsNext: false),
        .init(id: "ra", arabic: "ر", name: "Ra", spokenName: "رَاء", hint: "Noktasız kıvrım. İnce veya kalın okunması bulunduğu duruma bağlıdır.", joinsNext: false),
        .init(id: "zay", arabic: "ز", name: "Ze", spokenName: "زَاي", hint: "Ranın üzerinde bir nokta vardır. Zel ile farklı bir harftir.", joinsNext: false),
        .init(id: "sin", arabic: "س", name: "Sin", spokenName: "سِين", hint: "Noktasız, dişli gövde. İnce sestir.", joinsNext: true),
        .init(id: "shin", arabic: "ش", name: "Şın", spokenName: "شِين", hint: "Sinin üzerinde üç nokta vardır.", joinsNext: true),
        .init(id: "sad", arabic: "ص", name: "Sad", spokenName: "صَاد", hint: "Geniş gövdeli, noktasız harf. Kalın sestir; sin ile karıştırmayın.", joinsNext: true),
        .init(id: "dad", arabic: "ض", name: "Dad", spokenName: "ضَاد", hint: "Sadın üzerinde bir nokta vardır. Mahrecini öğreticiyle çalışın.", joinsNext: true),
        .init(id: "tta", arabic: "ط", name: "Tı", spokenName: "طَاء", hint: "Dik çizgili, noktasız gövde. Kalın sestir.", joinsNext: true),
        .init(id: "zza", arabic: "ظ", name: "Zı", spokenName: "ظَاء", hint: "Tının üzerinde bir nokta vardır. Kalın ve peltek sestir.", joinsNext: true),
        .init(id: "ayn", arabic: "ع", name: "Ayn", spokenName: "عَيْن", hint: "Noktasızdır. Boğaz sesi; hemzeyle aynı değildir.", joinsNext: true),
        .init(id: "ghayn", arabic: "غ", name: "Gayn", spokenName: "غَيْن", hint: "Aynın üzerinde bir nokta vardır. Kalın sestir.", joinsNext: true),
        .init(id: "fa", arabic: "ف", name: "Fe", spokenName: "فَاء", hint: "Üstünde bir nokta. Alt dudak üst dişlere yaklaşır.", joinsNext: true),
        .init(id: "qaf", arabic: "ق", name: "Kaf", spokenName: "قَاف", hint: "Üstünde iki nokta vardır. Kalın sestir; kef ile karıştırmayın.", joinsNext: true),
        .init(id: "kaf", arabic: "ك", name: "Kef", spokenName: "كَاف", hint: "İnce sestir. Başta ve ortada şekli belirgin biçimde değişir.", joinsNext: true),
        .init(id: "lam", arabic: "ل", name: "Lâm", spokenName: "لَام", hint: "Uzun gövdeli harf. Elifle birleştiğinde lâmelif görünümü oluşur.", joinsNext: true),
        .init(id: "mim", arabic: "م", name: "Mim", spokenName: "مِيم", hint: "Küçük başlı gövde. Dudaklar kapanır.", joinsNext: true),
        .init(id: "nun", arabic: "ن", name: "Nun", spokenName: "نُون", hint: "Üstünde bir nokta. Sondaki çanağı be harfinden farklıdır.", joinsNext: true),
        .init(id: "he", arabic: "ه", name: "He", spokenName: "هَاء", hint: "Hâ harfinden farklıdır. Başta, ortada ve sonda görünümüne dikkat edin.", joinsNext: true),
        .init(id: "waw", arabic: "و", name: "Vav", spokenName: "وَاو", hint: "Küçük başlı kıvrım. Sonraki harfe bağlanmaz; uzatma görevi de olabilir.", joinsNext: false),
        .init(id: "ya", arabic: "ي", name: "Ye", spokenName: "يَاء", hint: "Altında iki nokta vardır. Uzatma görevi de olabilir.", joinsNext: true)
    ]
    static let lessons: [EBLesson] = [
        .init(id: 1, title: "Harflerle tanış", symbol: "ا ب ت", summary: "28 harf · sağdan sola okuma", explanation: "Arapça sağdan sola okunur. Önce harfin gövdesini, sonra noktalarını inceleyin. Birbirine benzeyen harfleri yan yana karşılaştırın. Lâmelif, lâm ile elifin birleşimidir; ayrı bir temel harf değildir.", examples: [.init(arabic: "ب ت ث", reading: "Bir, iki ve üç nokta"), .init(arabic: "ج ح خ", reading: "Noktanın yeri değişiyor"), .init(arabic: "لا", reading: "Lâm + elif")], checks: [.init(prompt: "Arapça hangi yönde okunur?", choices: ["Sağdan sola", "Soldan sağa", "Aşağıdan yukarı"], answer: 0, explanation: "Arapça satır sağdan sola takip edilir."), .init(prompt: "Altında bir nokta olan harf hangisi?", choices: ["ت", "ب", "ث"], answer: 1, explanation: "Be harfinin noktası alttadır."), .init(prompt: "Lâmelif nedir?", choices: ["Ayrı bir hareke", "Bir durak işareti", "Lâm ve elif birleşimi"], answer: 2, explanation: "لا, ل ve ا harflerinin birleşik yazımıdır.")]),
        .init(id: 2, title: "Harflerin birleşmesi", symbol: "بـ ـبـ ـب", summary: "Başta · ortada · sonda", explanation: "Harflerin görünümü kelimedeki konuma göre değişebilir. Elif, dal, zel, ra, ze ve vav kendilerinden sonraki harfe bağlanmaz. Yazıdaki bir boşluk her zaman yeni kelime başladığı anlamına gelmez.", examples: [.init(arabic: "بـ ـبـ ـب", reading: "Be: başta, ortada, sonda"), .init(arabic: "ا د ذ ر ز و", reading: "Sonraki harfe bağlanmayanlar"), .init(arabic: "بَاب", reading: "Ortadaki eliften sonra bağlantı kesilir")], checks: [.init(prompt: "Hangisi sonraki harfe bağlanmaz?", choices: ["ب", "م", "د"], answer: 2, explanation: "Dal sonraki harfe bağlanmaz."), .init(prompt: "ـبـ hangi konumun örneğidir?", choices: ["Ortada", "Tek başına", "Sadece sonda"], answer: 0, explanation: "İki yandaki bağlantı ortadaki görünümü gösterir."), .init(prompt: "Hangisi sonraki harfe bağlanabilir?", choices: ["و", "ل", "ر"], answer: 1, explanation: "Lâm sonraki harfe bağlanabilir.")]),
        .init(id: 3, title: "Üstün", symbol: "بَ", summary: "Harfin üstündeki kısa çizgi", explanation: "Üstün harfe kısa bir açık ünlü ekler. Sesi gereksiz uzatmadan okuyun. İnce ve kalın harflerin ses rengini dinleyerek ayırt edin; Latin harfleri yalnızca yardımcıdır.", examples: [.init(arabic: "بَ", reading: "Kısa üstün"), .init(arabic: "تَ", reading: "Te + üstün"), .init(arabic: "كَتَبَ", reading: "Üç kısa hece")], checks: [.init(prompt: "Üstünlü be hangisi?", choices: ["بُ", "بِ", "بَ"], answer: 2, explanation: "Üstün harfin üzerindeki kısa çizgidir."), .init(prompt: "Üstün nerede bulunur?", choices: ["Harfin üstünde", "Harfin altında", "Satır sonunda"], answer: 0, explanation: "Üstün, harfin üzerine yazılır."), .init(prompt: "Tek üstün tek başına uzun okutur mu?", choices: ["Her zaman", "Hayır", "Yalnız sonda"], answer: 1, explanation: "Üstün kısa sestir; uzatmayı ayrıca öğreniyoruz.")]),
        .init(id: 4, title: "Esre", symbol: "بِ", summary: "Harfin altındaki kısa çizgi", explanation: "Esre harfin altında bulunur ve kısa i yönünde bir ses verir. Nokta ile harekeyi ayırın: nokta harfi tanıtır, hareke okuyuşu belirler.", examples: [.init(arabic: "بِ", reading: "Be + esre"), .init(arabic: "مِ", reading: "Mim + esre"), .init(arabic: "بِسْمِ", reading: "Esreleri bulun")], checks: [.init(prompt: "Esreli mim hangisi?", choices: ["مَ", "مِ", "مُ"], answer: 1, explanation: "Esre harfin altındadır."), .init(prompt: "Esreyi hangi işaret gösterir?", choices: ["ِ", "ُ", "ّ"], answer: 0, explanation: "Alttaki kısa çizgi esredir."), .init(prompt: "Nokta ve hareke aynı şey midir?", choices: ["Evet", "Yalnız be harfinde", "Hayır"], answer: 2, explanation: "Nokta harfin kimliğini, hareke okunuşunu belirler.")]),
        .init(id: 5, title: "Ötre", symbol: "بُ", summary: "Dudakları yuvarlayarak kısa ses", explanation: "Ötre küçük vav biçimindeki işarettir. Dudakları yuvarlayarak kısa bir sesle okuyun. Aynı harfi üç harekeyle karşılaştırmak farkı duymanıza yardımcı olur.", examples: [.init(arabic: "بُ", reading: "Be + ötre"), .init(arabic: "نُ", reading: "Nun + ötre"), .init(arabic: "بَ بِ بُ", reading: "Üç harekeyi karşılaştırın")], checks: [.init(prompt: "Ötreli nun hangisi?", choices: ["نُ", "نَ", "نِ"], answer: 0, explanation: "Ötre üstteki küçük vav görünümündedir."), .init(prompt: "Ötrede dudaklar nasıl kullanılır?", choices: ["Tamamen kapanır", "Yuvarlanır", "Hiç hareket etmez"], answer: 1, explanation: "Ötrede dudakları yuvarlayın."), .init(prompt: "بَ بِ بُ sıralaması hangisidir?", choices: ["Esre, üstün, ötre", "Ötre, esre, üstün", "Üstün, esre, ötre"], answer: 2, explanation: "İşaretin yerine ve şekline bakın.")]),
        .init(id: 6, title: "Cezim", symbol: "بْ", summary: "Yeni ünlü eklemeden birleştir", explanation: "Cezimli harfin kendine ait kısa ünlüsü yoktur. Önceki harekeli harfe bağlayarak okuyun. Araya fazladan bir ünlü yerleştirmeyin.", examples: [.init(arabic: "اَبْ", reading: "Son harfe ünlü eklemeyin"), .init(arabic: "اِنْ", reading: "Esre ile başlayın"), .init(arabic: "قُلْ", reading: "Lâmı önceki sese bağlayın")], checks: [.init(prompt: "Cezimli be hangisi?", choices: ["بَ", "بْ", "بّ"], answer: 1, explanation: "Cezim, harfin üzerindeki küçük daire biçimli işarettir."), .init(prompt: "Cezimli harfe yeni ünlü eklenir mi?", choices: ["Hayır", "Her zaman", "Sadece sonunda"], answer: 0, explanation: "Harf önceki sesle birleştirilir."), .init(prompt: "قُلْ kelimesinde hangi harf cezimlidir?", choices: ["ق", "و", "ل"], answer: 2, explanation: "Cezim lâmın üzerindedir.")]),
        .init(id: 7, title: "Şedde", symbol: "بّ", summary: "Aynı harfi çift olarak oku", explanation: "Şedde aynı harfin iki kez okunmasını gösterir. İlki önceki sese bağlanır, ikincisi üzerindeki harekeyle okunur. Şeddeyi uzatma işaretiyle karıştırmayın.", examples: [.init(arabic: "اَبَّ", reading: "İlk be kapalı, ikinci be harekeli"), .init(arabic: "رَبِّ", reading: "Şeddeli be"), .init(arabic: "ثُمَّ", reading: "Şeddeli mim")], checks: [.init(prompt: "Şedde işareti hangisidir?", choices: ["ّ", "ْ", "ِ"], answer: 0, explanation: "Küçük şın dişlerini andıran işaret şeddedir."), .init(prompt: "رَبِّ kelimesinde hangi harf şeddelidir?", choices: ["ر", "ب", "ا"], answer: 1, explanation: "Şedde be harfinin üzerindedir."), .init(prompt: "Şedde neyi gösterir?", choices: ["Harf okunmaz", "Her zaman durulur", "Harf çift okunur"], answer: 2, explanation: "İlk ses cezimli, ikinci ses harekelidir.")]),
        .init(id: 8, title: "Med harfleri", symbol: "بَا بِي بُو", summary: "Kısa sesi doğal biçimde uzat", explanation: "Uygun harekeden sonra gelen harekesiz elif, vav veya ye uzatma görevi görür: üstünden sonra elif, ötre ardından vav, esre ardından ye. Her vav veya ye uzatma harfi değildir.", examples: [.init(arabic: "بَا", reading: "Üstün + elif"), .init(arabic: "بِي", reading: "Esre + ye"), .init(arabic: "بُو", reading: "Ötre + vav")], checks: [.init(prompt: "Üstünden sonra hangi harf med olabilir?", choices: ["م", "ا", "ت"], answer: 1, explanation: "Harekesiz elif, uygun üstünlü sesi uzatır."), .init(prompt: "بِي örneğinde hangi hareke vardır?", choices: ["Esre", "Ötre", "Üstün"], answer: 0, explanation: "Esreden sonra harekesiz ye gelmiştir."), .init(prompt: "Her vav mutlaka med midir?", choices: ["Evet", "Yalnız başta", "Hayır"], answer: 2, explanation: "Hareke ve bağlam birlikte değerlendirilir.")]),
        .init(id: 9, title: "Tenvin", symbol: "بً بٍ بٌ", summary: "Çift harekeyi tanı", explanation: "Tenvin çift hareke ile gösterilir ve geçişli okumada sona n sesi katar. Durulduğunda okuyuş değişebilir; durak dersinde bu ayrımı ayrıca çalışın.", examples: [.init(arabic: "بًا", reading: "İki üstün"), .init(arabic: "بٍ", reading: "İki esre"), .init(arabic: "بٌ", reading: "İki ötre")], checks: [.init(prompt: "İki esre hangisidir?", choices: ["بٌ", "بً", "بٍ"], answer: 2, explanation: "İki esre harfin altında iki çizgidir."), .init(prompt: "Geçişli okumada tenvin hangi sesi ekler?", choices: ["N", "M", "L"], answer: 0, explanation: "Temel tanımda tenvin sona n sesi ekler; tecvid kuralları bağlama göre öğrenilir."), .init(prompt: "Durunca okuyuş her zaman aynı mıdır?", choices: ["Evet", "Hayır", "Sadece ilk kelimede"], answer: 1, explanation: "Vakıf kuralları ayrıca uygulanır.")]),
        .init(id: 10, title: "Lâmelif ve hemze", symbol: "لا ء", summary: "Görünüm ile görevi ayırt et", explanation: "Lâm ile elif birlikte lâmelif şeklinde görünür. Hemze ayrı bir sestir; farklı taşıyıcılar üzerinde veya tek başına yazılabilir. Elif ile hemzeyi tek bir işaret gibi düşünmeyin.", examples: [.init(arabic: "لَا", reading: "Lâm + elif"), .init(arabic: "أَ إِ", reading: "Elif üzerindeki ve altındaki hemze"), .init(arabic: "ء", reading: "Tek başına hemze")], checks: [.init(prompt: "لا hangi iki harften oluşur?", choices: ["Lâm ve elif", "Lâm ve be", "Elif ve nun"], answer: 0, explanation: "Lâmelif bir birleşimdir."), .init(prompt: "Hemze hangisidir?", choices: ["و", "ء", "ي"], answer: 1, explanation: "ء hemze işaretidir."), .init(prompt: "إِ örneğinde hareke hangisidir?", choices: ["Ötre", "Üstün", "Esre"], answer: 2, explanation: "Alttaki kısa çizgi esredir.")]),
        .init(id: 11, title: "El takısını tanı", symbol: "الْقَمَر الشَّمْس", summary: "Kamerî ve şemsî harflere giriş", explanation: "El takısından sonra bazı harflerde lâm okunur, bazılarında sonraki harfe katılır. Kamerî örnekte lâmı duyarsınız; şemsî örnekte sonraki harfin şeddesine dikkat edin.", examples: [.init(arabic: "الْقَمَرُ", reading: "Kamerî: lâm okunur"), .init(arabic: "الشَّمْسُ", reading: "Şemsî: şeddeli şın"), .init(arabic: "النَّاسُ", reading: "Şemsî: şeddeli nun")], checks: [.init(prompt: "الْقَمَرُ örneğinde lâm okunur mu?", choices: ["Hayır", "Evet", "Yalnız dururken"], answer: 1, explanation: "Kaf kamerî harftir; lâm okunur."), .init(prompt: "الشَّمْسُ örneğinde şedde hangi harftedir?", choices: ["ش", "م", "س"], answer: 0, explanation: "Şın şemsî harftir."), .init(prompt: "النَّاسُ örneğinde hangi harf şeddelidir?", choices: ["س", "ل", "ن"], answer: 2, explanation: "Nun üzerindeki şeddeye dikkat edin.")]),
        .init(id: 12, title: "Durak ve Kur’an’a geçiş", symbol: "م ج لا", summary: "Yavaş oku · dinle · karşılaştır", explanation: "Durak işaretleri okuyuşa rehberlik eder. م gerekli duruşu, ج durulabilecek yeri gösterir. لا görülen yerde normalde durulmaz; nefes zorunluluğunda uygun yerden yeniden başlanır. İlk sûreleri bir öğreticiyle çalışın.", examples: [.init(arabic: "م", reading: "Gerekli duruş"), .init(arabic: "ج", reading: "Durulabilir"), .init(arabic: "لا", reading: "Normalde durulmaz")], checks: [.init(prompt: "ج durak işareti neyi gösterir?", choices: ["Her zaman uzat", "Harfi atla", "Durulabilir"], answer: 2, explanation: "ج, durmanın uygun olduğu yerlerdendir."), .init(prompt: "م durak işaretinde ne yapılır?", choices: ["Durulur", "Hızlanılır", "Geriye okunur"], answer: 0, explanation: "Bu işaret gerekli duruşu gösterir."), .init(prompt: "Yeni bir sûreyi çalışırken hangisi yararlıdır?", choices: ["Sadece hızlanmak", "Dinleyip öğreticiyle karşılaştırmak", "Harekeleri atlamak"], answer: 1, explanation: "Mahreç ve okuyuş, dinleme ve öğretici geri bildirimiyle gelişir.")])
    ]
}

struct EBReviewRecord: Codable {
    var attempts = 0
    var correct = 0
    var streak = 0
    var due = Date.distantPast
    mutating func answer(_ success: Bool, now: Date) {
        attempts += 1
        if success { correct += 1; streak += 1 } else { streak = 0 }
        let days = [1, 3, 7, 14, 30]
        due = success ? now.addingTimeInterval(Double(days[min(max(streak - 1, 0), days.count - 1)]) * 86400) : now.addingTimeInterval(600)
    }
}
struct EBProgress: Codable {
    var completedLessons: Set<Int> = []
    var letters: [String: EBReviewRecord] = [:]
    var dailyAnswers: [String: Int] = [:]
    var favoriteLetters: Set<String> = []
    var lastLesson = 1
}
@MainActor final class EBStudyStore: ObservableObject {
    @Published private(set) var progress: EBProgress
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = defaults.data(forKey: "elifba.progress.v1").flatMap { try? JSONDecoder().decode(EBProgress.self, from: $0) } ?? EBProgress()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: "elifba.progress.v1") }
    }
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    var todayAnswers: Int { progress.dailyAnswers[Self.dayKey(.now), default: 0] }
    var mastered: Int { progress.letters.values.filter { $0.streak >= 3 }.count }
    var reviewLetters: [EBLetter] {
        let records = progress.letters
        return EBCurriculum.letters.filter { (records[$0.id]?.due ?? .distantPast) <= .now }
            .sorted {
                func priority(_ letter: EBLetter) -> Int {
                    guard let record = records[letter.id] else { return 1 }
                    return record.streak == 0 ? 0 : record.streak + 1
                }
                let a = priority($0), b = priority($1)
                return a == b ? $0.id < $1.id : a < b
            }
    }
    func answer(letter: String, correct: Bool, now: Date = .now) {
        var item = progress.letters[letter] ?? EBReviewRecord()
        item.answer(correct, now: now); progress.letters[letter] = item
        progress.dailyAnswers[Self.dayKey(now), default: 0] += 1
        save()
    }
    func complete(_ lesson: Int) { progress.completedLessons.insert(lesson); progress.lastLesson = min(lesson + 1, EBCurriculum.lessons.count); save() }
    func favorite(_ letter: String) {
        if progress.favoriteLetters.contains(letter) { progress.favoriteLetters.remove(letter) } else { progress.favoriteLetters.insert(letter) }
        save()
    }
}

struct ElifBaView: View {
    @StateObject private var store = EBStudyStore()
    @StateObject private var assessment = EBAssessmentStore()
    @State private var section = 0
    @State private var search = ""
    @State private var favoritesOnly = false
    @ObservedObject private var audio = AdhanPlayer.shared
    private let grid = [GridItem(.adaptive(minimum: 88), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("Çalışma bölümü", selection: $section) {
                    Text("Dersler").tag(0); Text("Harfler").tag(1); Text("Alıştırma").tag(2); Text("Gelişim").tag(3)
                }.pickerStyle(.segmented)
                if section == 0 { lessons }
                else if section == 1 { alphabet }
                else if section == 2 { practice }
                else { EBProgressOverview(store: store, assessment: assessment) }
                if audio.isPreparing { ProgressView("Stüdyo sesi hazırlanıyor…") }
                if audio.isPlaying || audio.isPreparing {
                    Button("Sesi durdur", systemImage: "stop.circle") { audio.stop() }
                }
                guidance
            }.padding(20).padding(.bottom, 28)
        }
        .background(Palette.background)
        .navigationTitle("Kur’an Öğreniyorum")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onDisappear { audio.stop() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ELİF BÂ · ADIM ADIM").font(.caption.weight(.semibold)).tracking(2)
            Text("İlk harften\nilk okuyuşa.").font(.system(.largeTitle, design: .serif).weight(.regular))
            Text("Dinle, incele, yaz ve kendini dene.").font(.body)
            HStack {
                Label("\(store.progress.completedLessons.count)/12 ders", systemImage: "book.closed")
                Spacer()
                Label("\(store.mastered)/28 harf", systemImage: "checkmark.seal")
            }.font(.subheadline)
            ProgressView(value: Double(store.progress.completedLessons.count), total: 12).tint(.white)
            Text("Günlük hedef · \(min(store.todayAnswers, 10))/10 harf sorusu").font(.footnote)
        }.foregroundStyle(.white).padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EzanDesign.heroGradient).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private var lessons: some View {
        VStack(spacing: 12) {
            if let next = EBCurriculum.lessons.first(where: { !store.progress.completedLessons.contains($0.id) }) {
                NavigationLink { EBLessonView(lesson: next, store: store) } label: {
                    Label("\(store.progress.completedLessons.isEmpty ? "Öğrenmeye başla" : "Kaldığın yerden devam et") · \(next.title)", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18).sekineCard(active: true)
                }.buttonStyle(.plain)
            }
            ForEach(EBCurriculum.lessons) { lesson in
                NavigationLink { EBLessonView(lesson: lesson, store: store) } label: {
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", lesson.id)).font(.title3.monospacedDigit()).foregroundStyle(Palette.gold)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lesson.title).font(.headline)
                            Text(lesson.summary).font(.subheadline).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: store.progress.completedLessons.contains(lesson.id) ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(Palette.accent)
                    }.padding(18).sekineCard()
                }.buttonStyle(.plain)
            }
        }
    }
    private var alphabet: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Harf adı veya Arapça harf ara", text: $search).textFieldStyle(.roundedBorder)
            Toggle("Yalnızca yıldızlı harfler", isOn: $favoritesOnly)
            Text("Bir harfe dokun: şeklini, birleşimini ve harekelerini keşfet.").font(.subheadline).foregroundStyle(Palette.textSecondary)
            let filtered = EBCurriculum.letters.filter {
                (search.isEmpty || $0.name.localizedStandardContains(search) || $0.arabic.contains(search)) && (!favoritesOnly || store.progress.favoriteLetters.contains($0.id))
            }
            if filtered.isEmpty { ContentUnavailableView("Harf bulunamadı", systemImage: "text.magnifyingglass", description: Text("Aramayı değiştirin veya yıldız filtresini kapatın.")) }
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(filtered) { letter in
                    NavigationLink { EBLetterView(letter: letter, store: store) } label: {
                        VStack(spacing: 6) {
                            EBArabic(text: letter.arabic, size: 58)
                            Text(letter.name).font(.subheadline)
                            if store.progress.favoriteLetters.contains(letter.id) { Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.gold) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 12).sekineCard()
                    }.buttonStyle(.plain).accessibilityLabel("\(letter.name) harfini öğren")
                }
            }.environment(\.layoutDirection, .rightToLeft)
            Text("Lâmelif ayrı bir harf değildir. Lâm ile elifin birleşimi 10. derste anlatılır.").font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
    private var practice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kısa çalış, sık tekrar et.").font(.title2)
            NavigationLink { EBReadingWorkshop(store: store, assessment: assessment) } label: {
                practiceCard("Okumaya geçiş atölyesi", detail: "Cezim · Şedde · Med · Tenvin · karşılaştır ve dene", icon: "book.pages")
            }
            NavigationLink { EBAssessmentView(store: assessment, lessons: EBCurriculum.lessons, title: "Genel değerlendirme") } label: {
                practiceCard("Genel değerlendirme", detail: "12 konu · 36 soru · eksiklerini gör", icon: "checklist")
            }
            NavigationLink { EBJoiningPracticeView(store: store) } label: {
                practiceCard("Birleşik şekilleri tanı", detail: "Başta · Ortada · Sonda · bağlantı kuralları", icon: "link")
            }
            NavigationLink { EBVowelPracticeView() } label: {
                practiceCard("Harekeleri ayırt et", detail: "Üstün · Esre · Ötre · 9 soruluk çalışma", icon: "textformat.abc")
            }
            NavigationLink { EBLetterFamiliesView(store: store) } label: {
                practiceCard("Benzer harfleri ayırt et", detail: "9 harf ailesi · noktaları karşılaştır · kısa test", icon: "square.grid.2x2")
            }
            Text("Doğru cevaplar 1, 3, 7, 14 ve 30 günlük tekrar aralıkları oluşturur. Yanlış cevaplanan harf 10 dakika sonra tekrar listesine girer. Yeni harfler de günlük çalışmaya katılır.").font(.body).lineSpacing(5)
            NavigationLink { EBQuizView(store: store, pool: store.reviewLetters, listening: false, prioritize: true) } label: {
                practiceCard("Bugünkü tekrar", detail: "\(store.reviewLetters.count) harf hazır · en fazla 10 soru", icon: "arrow.clockwise")
            }.disabled(store.reviewLetters.isEmpty)
            NavigationLink { EBQuizView(store: store, pool: EBCurriculum.letters, listening: false) } label: {
                practiceCard("Harfi tanı", detail: "Gördüğün harfin adını seç", icon: "character.book.closed")
            }
            NavigationLink { EBQuizView(store: store, pool: EBCurriculum.letters, listening: true) } label: {
                practiceCard("Dinle ve bul", detail: "Harf adını dinle, doğru şekli seç", icon: "ear")
            }
            Text("Bir harfte art arda 3 doğru cevap, ilerleme ekranında o harfi öğrenildi olarak işaretler. Bu, mahreç veya tecvid yeterlilik belgesi değildir.").font(.footnote).foregroundStyle(Palette.textSecondary)
        }.buttonStyle(.plain)
    }
    private func practiceCard(_ title: String, detail: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(Palette.textSecondary) }
            Spacer(); Image(systemName: "chevron.right")
        }.padding(20).sekineCard()
    }
    private var guidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dinleme rehberi").font(.headline)
            Text("Sesli örnekler yapay zekâ ile hazırlanır. Mahreç ve tecvid çalışmasını Diyanet’in öğretici okuyuşları ve bir Kur’an öğreticisiyle destekleyin. Uygulama sesinizi dinleyip doğruluk puanı vermez.").font(.footnote).lineSpacing(4)
            Link("Diyanet · Sesli Elif Bâ", destination: URL(string: "https://kuran.diyanet.gov.tr/elifba/")!)
            Link("Diyanet · Kur’an Öğreniyorum kitabı", destination: URL(string: "https://egitimhizmetleri.diyanet.gov.tr/Documents/ElifBa%20Kuran%20%C3%96%C4%9Freniyorum.pdf")!)
            Text("28 harfin adı, dersler ve ilerleme çevrimdışı kullanılabilir. Diğer sesli örneklerin ilk hazırlanması internet gerektirir; önbellekteki sesler tekrar indirilmeksizin oynatılır.").font(.footnote).foregroundStyle(Palette.textSecondary)
        }.padding(18).sekineCard()
    }
}

struct EBArabic: View {
    let text: String
    var size: CGFloat = 48
    var body: some View {
        Text(text).font(.custom("Amiri-Regular", size: size, relativeTo: .title)).fontWeight(.regular)
            .lineSpacing(12).fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center).environment(\.layoutDirection, .rightToLeft)
    }
}

struct EBLetterView: View {
    let letter: EBLetter
    @ObservedObject var store: EBStudyStore
    @State private var showTrace = false
    @ObservedObject private var audio = AdhanPlayer.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    EBArabic(text: letter.arabic, size: 110).frame(maxWidth: .infinity)
                    Text(letter.name).font(.largeTitle.weight(.regular))
                    Button("Harf adını dinle", systemImage: "speaker.wave.2.fill") { EBLetterAudio.play(letter) }
                    Text(letter.hint).font(.body).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(22).sekineCard()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Kelimedeki görünümü").font(.title2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(zip(["Tek başına", "Başta", "Ortada", "Sonda"], letter.forms)), id: \.0) { title, form in
                            VStack { EBArabic(text: form, size: 52); Text(title).font(.subheadline) }.frame(maxWidth: .infinity).padding(12).sekineCard()
                        }
                    }
                    if !letter.joinsNext { Text("Bu harf kendisinden sonraki harfe bağlanmaz. Başta ve ortada bağlantı bu yüzden kesilir.").font(.footnote).foregroundStyle(Palette.textSecondary) }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Harekelerle karşılaştır").font(.title2)
                    let base = letter.id == "alif" ? "أ" : letter.arabic
                    ForEach(Array(zip(["Üstün", "Esre", "Ötre"], ["َ", "ِ", "ُ"])), id: \.0) { name, mark in
                        Button { audio.speakText(base + mark, language: "ar-SA") } label: {
                            HStack { Text(name); Spacer(); EBArabic(text: base + mark, size: 48); Spacer(); Image(systemName: "speaker.wave.2") }.padding(16).sekineCard()
                        }.buttonStyle(.plain).accessibilityLabel("\(letter.name), \(name), sesli örnek")
                    }
                }
                Button("Parmağınla yaz", systemImage: "pencil.tip.crop.circle") { showTrace = true }.buttonStyle(.borderedProminent)
                Button(store.progress.favoriteLetters.contains(letter.id) ? "Yıldızlılardan çıkar" : "Tekrar için yıldızla", systemImage: "star") { store.favorite(letter.id) }
                if audio.isPreparing { ProgressView("Ses hazırlanıyor…") }
                if audio.isPlaying || audio.isPreparing { Button("Sesi durdur") { audio.stop() } }
                Text("Latin harfli ad, telaffuzun tam karşılığı değildir. Sesler yapay zekâ örneğidir; doğru mahreci öğreticiyle çalışın.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background).navigationTitle(letter.name)
            .sheet(isPresented: $showTrace) { EBTraceView(letter: letter) }
            .onDisappear { audio.stop() }
    }
}

struct EBTraceView: View {
    let letter: EBLetter
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Şeklin üzerinden parmağınla geç.").font(.title3)
                Text("Serbest yazma alanı · otomatik puanlama yok").font(.footnote).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 24).fill(Palette.card)
                        EBArabic(text: letter.arabic, size: 210).foregroundStyle(Palette.textSecondary.opacity(0.22))
                        Canvas { context, size in
                            for points in strokes + [current] {
                                guard let first = points.first else { continue }
                                var path = Path(); path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                                for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
                                context.stroke(path, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            }
                        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            current.append(CGPoint(x: min(1, max(0, value.location.x / max(1, geometry.size.width))), y: min(1, max(0, value.location.y / max(1, geometry.size.height)))))
                        }.onEnded { _ in if !current.isEmpty { strokes.append(current); current = [] } })
                    }
                }.frame(height: 340).accessibilityLabel("\(letter.name) serbest yazma alanı")
                HStack { Button("Geri al", systemImage: "arrow.uturn.backward") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty); Spacer(); Button("Temizle", systemImage: "eraser") { strokes = []; current = [] } }
                Text("Noktalara ve gövdeye dikkat et. Bu alan harfin şeklini çalışmak içindir; yazım sırasını veya doğruluğunu değerlendirmez.").font(.body).lineSpacing(5)
                Spacer()
            }.padding(24).background(Palette.background).navigationTitle("\(letter.name) · Yazma")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}

struct EBLessonView: View {
    let lesson: EBLesson
    @ObservedObject var store: EBStudyStore
    @State private var answers: [String: Int] = [:]
    @State private var showCheck = false
    @ObservedObject private var audio = AdhanPlayer.shared
    private var allCorrect: Bool { lesson.checks.allSatisfy { answers[$0.id] == $0.answer } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("DERS \(lesson.id) / 12").font(.caption).tracking(2).foregroundStyle(Palette.gold)
                Text(lesson.title).font(.largeTitle.weight(.regular))
                EBArabic(text: lesson.symbol, size: 54).frame(maxWidth: .infinity).padding(20).sekineCard()
                Text(lesson.explanation).font(.system(size: 21, weight: .regular)).lineSpacing(8)
                Button("Ders anlatımını dinle", systemImage: "speaker.wave.2") { audio.speakTurkish(text: lesson.title + ". " + lesson.explanation, title: lesson.title) }
                Text("İncele ve tekrar et").font(.title2)
                ForEach(lesson.examples) { example in
                    VStack(spacing: 12) {
                        EBArabic(text: example.arabic, size: 54).frame(maxWidth: .infinity)
                        Text(example.reading).font(.body)
                        if (3...11).contains(lesson.id) {
                            Button("Sesli örnek", systemImage: "play.circle") { audio.speakText(example.arabic, language: "ar-SA") }
                        }
                    }.padding(20).sekineCard()
                }
                if lesson.id <= 2 {
                    NavigationLink("Harfleri tek tek incele") { ElifBaAlphabetLesson(store: store) }
                }
                if audio.isPreparing { ProgressView("Ses hazırlanıyor…") }
                if audio.isPlaying || audio.isPreparing { Button("Sesi durdur") { audio.stop() } }
                Toggle("Kendimi denemeye hazırım", isOn: $showCheck)
                if showCheck {
                    ForEach(lesson.checks) { check in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(check.prompt).font(.headline)
                            ForEach(Array(check.choices.enumerated()), id: \.offset) { index, option in
                                Button {
                                    answers[check.id] = index
                                    if allCorrect { store.complete(lesson.id) }
                                } label: {
                                    HStack {
                                        Text(option).font(.title3).padding(.vertical, 8)
                                        Spacer()
                                        if answers[check.id] == index { Image(systemName: index == check.answer ? "checkmark.circle.fill" : "xmark.circle.fill") }
                                    }.padding(.horizontal, 14).background(answers[check.id] == index ? Palette.accent.opacity(0.14) : Palette.card, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).disabled(answers[check.id] == check.answer)
                            }
                            if let answer = answers[check.id] {
                                Text(answer == check.answer ? "Doğru. " + check.explanation : "Bir daha dene. " + check.explanation).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            }
                        }.padding(18).sekineCard()
                    }
                    if allCorrect {
                        Label("Ders tamamlandı", systemImage: "checkmark.seal.fill").font(.title2).foregroundStyle(Palette.accent)
                        if let next = EBCurriculum.lessons.first(where: { $0.id == lesson.id + 1 }) {
                            NavigationLink("Sonraki ders: \(next.title)") { EBLessonView(lesson: next, store: store) }.buttonStyle(.borderedProminent)
                        } else {
                            NavigationLink("Fâtiha’yı aç") { SurahReaderView(surah: QuranAndLibraryView.popularSurahs[0]) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }.padding(20).padding(.bottom, 20)
        }.background(Palette.background).navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
            .onDisappear { audio.stop() }
    }
}

private struct ElifBaAlphabetLesson: View {
    @ObservedObject var store: EBStudyStore
    var body: some View {
        List(EBCurriculum.letters) { letter in
            NavigationLink { EBLetterView(letter: letter, store: store) } label: {
                HStack { Text(letter.name); Spacer(); EBArabic(text: letter.arabic, size: 44) }
            }
        }.navigationTitle("28 harfi tanı")
    }
}

struct EBQuestion: Identifiable {
    let letter: EBLetter
    let options: [EBLetter]
    var formIndex = 0
    var id: String { letter.id }
    static func make(pool: [EBLetter], prioritize: Bool = false, familyOnly: Bool = false, formPractice: Bool = false) -> [EBQuestion] {
        (prioritize ? Array(pool.prefix(10)).shuffled() : Array(pool.shuffled().prefix(10))).map { target in
            let others = (familyOnly ? pool : EBCurriculum.letters).filter { $0.id != target.id }.shuffled().prefix(3)
            return EBQuestion(letter: target, options: (Array(others) + [target]).shuffled(), formIndex: formPractice ? Int.random(in: 1...3) : 0)
        }
    }
}
struct EBQuizView: View {
    @ObservedObject var store: EBStudyStore
    let pool: [EBLetter]
    let listening: Bool
    var prioritize = false
    var familyOnly = false
    var formPractice = false
    @State private var mistakes: [EBLetter] = []
    @State private var questions: [EBQuestion] = []
    @State private var index = 0
    @State private var selected: String?
    @State private var correctCount = 0
    @State private var started = false
    @ObservedObject private var audio = AdhanPlayer.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if index < questions.count {
                    let question = questions[index]
                    Text("Soru \(index + 1) / \(questions.count)").font(.headline)
                    ProgressView(value: Double(index), total: Double(questions.count))
                    if listening {
                        Image(systemName: "ear.badge.waveform").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(Palette.accent)
                        Text("Harf adını dinle ve şeklini seç.").font(.title2)
                        Button("Soruyu dinle", systemImage: "speaker.wave.2.fill") { EBLetterAudio.play(question.letter) }.buttonStyle(.borderedProminent)
                    } else {
                        EBArabic(text: question.letter.forms[question.formIndex], size: 110).accessibilityIdentifier("elifbaTarget-" + question.letter.id).frame(maxWidth: .infinity).padding(20).sekineCard()
                        if formPractice {
                            Text(["Tek başına", "Başta", "Ortada", "Sonda"][question.formIndex] + " görünen harfi tanı").font(.headline)
                        }
                        Text("Bu harfin adı nedir?").font(.title2)
                    }
                    ForEach(question.options) { option in
                        Button {
                            guard selected == nil else { return }
                            selected = option.id
                            let correct = option.id == question.letter.id
                            if correct { correctCount += 1 }
                            else if !mistakes.contains(where: { $0.id == question.letter.id }) { mistakes.append(question.letter) }
                            store.answer(letter: question.letter.id, correct: correct)
                            audio.stop()
                        } label: {
                            HStack {
                                if listening { EBArabic(text: option.arabic, size: 48) } else { Text(option.name).font(.title3) }
                                Spacer()
                                if selected != nil && option.id == question.letter.id { Image(systemName: "checkmark.circle.fill") }
                                else if selected == option.id { Image(systemName: "xmark.circle.fill") }
                            }.padding(18).frame(maxWidth: .infinity).background(selected == option.id ? Palette.accent.opacity(0.18) : Palette.card, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).disabled(selected != nil).accessibilityIdentifier("elifbaOption-" + option.id)
                    }
                    if selected != nil {
                        Text(selected == question.letter.id ? "Doğru!" : "Doğru cevap: \(question.letter.name)").font(.title3)
                        Text(question.letter.hint).font(.body).lineSpacing(5)
                        if formPractice && !question.letter.joinsNext {
                            Text("Bu harf sonraki harfe bağlanmaz; kelimenin ortasında olsa da bağlantı kesilir.").font(.body)
                        }
                        Button(index + 1 == questions.count ? "Sonucu gör" : "Sonraki soru") { audio.stop(); index += 1; selected = nil }.buttonStyle(.borderedProminent)
                    }
                    if audio.isPreparing { ProgressView("Ses hazırlanıyor…") }
                } else if started {
                    Image(systemName: "checkmark.seal").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    Text(questions.isEmpty ? "Tekrarların tamam!" : "Çalışma tamamlandı").font(.largeTitle)
                    Text("\(correctCount) / \(questions.count) doğru").font(.title)
                    Text("Cevapların kaydedildi. Yanlış yaptığın harfler tekrar planında öne alınır.").multilineTextAlignment(.center)
                    if !mistakes.isEmpty {
                        Text("Tekrar edilecek harfler: " + mistakes.map(\.name).joined(separator: ", ")).font(.body)
                        Button("Yanlış yaptıklarımı çalış (\(mistakes.count))") { retryMistakes() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("elifbaRetryMistakes")
                    }
                    Button("Yeni çalışma") { begin() }.buttonStyle(.borderedProminent).disabled(pool.isEmpty)
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle(formPractice ? "Birleşik şekil testi" : (familyOnly ? "Benzer harf testi" : (listening ? "Dinle ve bul" : "Harfi tanı")))
            .onAppear { if !started { begin() } }.onDisappear { audio.stop() }
    }
    private func begin() {
        questions = EBQuestion.make(pool: prioritize ? store.reviewLetters : pool, prioritize: prioritize, familyOnly: familyOnly, formPractice: formPractice)
        resetRound()
    }
    private func resetRound() { index = 0; selected = nil; correctCount = 0; mistakes = []; started = true }
    private func retryMistakes() {
        let targets = Set(mistakes.map(\.id))
        questions = questions.filter { targets.contains($0.letter.id) }.shuffled()
        resetRound()
    }
}

@MainActor enum EBLetterAudio {
    static func play(_ letter: EBLetter) {
        if let url = Bundle.main.url(forResource: letter.id, withExtension: "mp3", subdirectory: "ElifBaAudio") {
            AdhanPlayer.shared.playLocalOrRemoteFile(url: url, title: letter.name + " · Elif Bâ", subtitle: "Yapay zekâ sesli harf örneği", rate: AdhanPlayer.shared.studioRate)
        } else {
            AdhanPlayer.shared.speakText(letter.spokenName, language: "ar-SA")
        }
    }
}


struct EBLetterFamily: Identifiable {
    let id: String
    let title: String
    let letterIDs: [String]
    var letters: [EBLetter] { letterIDs.compactMap { id in EBCurriculum.letters.first { $0.id == id } } }
    static let all: [EBLetterFamily] = [
        .init(id: "ba", title: "Be · Te · Se", letterIDs: ["ba", "ta", "tha"]),
        .init(id: "jim", title: "Cim · Hâ · Hı", letterIDs: ["jim", "ha", "kha"]),
        .init(id: "dal", title: "Dal · Zel", letterIDs: ["dal", "dhal"]),
        .init(id: "ra", title: "Ra · Ze", letterIDs: ["ra", "zay"]),
        .init(id: "sin", title: "Sin · Şın", letterIDs: ["sin", "shin"]),
        .init(id: "sad", title: "Sad · Dad", letterIDs: ["sad", "dad"]),
        .init(id: "tta", title: "Tı · Zı", letterIDs: ["tta", "zza"]),
        .init(id: "ayn", title: "Ayn · Gayn", letterIDs: ["ayn", "ghayn"]),
        .init(id: "fa", title: "Fe · Kaf", letterIDs: ["fa", "qaf"])
    ]
}

struct EBLetterFamiliesView: View {
    @ObservedObject var store: EBStudyStore
    var body: some View {
        List {
            Section {
                Text("Önce gövdeyi, sonra noktanın yerini ve sayısını karşılaştır. Harfin adını dinle; ardından aynı ailedeki harflerle çalış.").font(.body)
            }
            ForEach(EBLetterFamily.all) { family in
                NavigationLink { EBLetterFamilyView(store: store, family: family) } label: {
                    HStack {
                        Text(family.title).font(.headline)
                        Spacer()
                        EBArabic(text: family.letters.map(\.arabic).joined(separator: " "), size: 34)
                    }.padding(.vertical, 8)
                }.accessibilityIdentifier("elifbaFamily-" + family.id)
            }
        }.navigationTitle("Benzer harfler")
    }
}

struct EBLetterFamilyView: View {
    @ObservedObject var store: EBStudyStore
    let family: EBLetterFamily
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    ForEach(family.letters) { letter in
                        VStack {
                            EBArabic(text: letter.arabic, size: 74)
                            Text(letter.name).font(.title3)
                        }.frame(maxWidth: .infinity)
                    }
                }.environment(\.layoutDirection, .rightToLeft).padding().sekineCard()
                ForEach(family.letters) { letter in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(letter.name).font(.title2)
                        Text(letter.hint).font(.body).lineSpacing(5)
                        Button { EBLetterAudio.play(letter) } label: {
                            Label(letter.name + " harfini dinle", systemImage: "speaker.wave.2.fill")
                        }.buttonStyle(.bordered)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).sekineCard()
                }
                NavigationLink("Bu harflerle çalış") {
                    EBQuizView(store: store, pool: family.letters, listening: false, familyOnly: true)
                }.buttonStyle(.borderedProminent)
                NavigationLink("Dinleyerek ayırt et") {
                    EBQuizView(store: store, pool: family.letters, listening: true, familyOnly: true)
                }.buttonStyle(.bordered)
                Text("Dinleme örnekleri yapay zekâ ile hazırlanmıştır. Seslerin mahrecini bir öğreticiyle pekiştirin.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background).navigationTitle(family.title)
            .onDisappear { AdhanPlayer.shared.stop() }
    }
}


// Vowel recognition has its own progress; it does not mark letter mastery.
enum EBVowel: String, CaseIterable, Codable, Identifiable {
    case fatha, kasra, damma
    var id: String { rawValue }
    var name: String { switch self { case .fatha: return "Üstün"; case .kasra: return "Esre"; case .damma: return "Ötre" } }
    var mark: String { switch self { case .fatha: return "َ"; case .kasra: return "ِ"; case .damma: return "ُ" } }
    var explanation: String {
        switch self {
        case .fatha: return "Üstün, harfin üzerindeki kısa çizgidir. Kısa bir açık ünlüyle okunur."
        case .kasra: return "Esre, harfin altındaki kısa çizgidir. Kısa i yönünde bir ses verir."
        case .damma: return "Ötre, harfin üzerindeki küçük vav biçimindeki işarettir. Dudaklar yuvarlanır."
        }
    }
    func text(for letter: EBLetter) -> String { (letter.id == "alif" ? "أ" : letter.arabic) + mark }
}
struct EBVowelQuestion: Identifiable {
    let id = UUID()
    let letter: EBLetter
    let vowel: EBVowel
    var text: String { vowel.text(for: letter) }
    static func make() -> [EBVowelQuestion] {
        EBVowel.allCases.flatMap { vowel in
            EBCurriculum.letters.shuffled().prefix(3).map { EBVowelQuestion(letter: $0, vowel: vowel) }
        }.shuffled()
    }
}
struct EBVowelScore: Codable {
    var attempts = 0
    var correct = 0
}
@MainActor final class EBVowelStore: ObservableObject {
    @Published private(set) var scores: [String: EBVowelScore]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scores = defaults.data(forKey: "elifba.vowels.v1").flatMap { try? JSONDecoder().decode([String: EBVowelScore].self, from: $0) } ?? [:]
    }
    func record(_ vowel: EBVowel, correct: Bool) {
        var score = scores[vowel.rawValue] ?? EBVowelScore()
        score.attempts += 1
        if correct { score.correct += 1 }
        scores[vowel.rawValue] = score
        if let data = try? JSONEncoder().encode(scores) { defaults.set(data, forKey: "elifba.vowels.v1") }
    }
}
struct EBVowelPracticeView: View {
    @StateObject private var store = EBVowelStore()
    @State private var letterID = "ba"
    private var letter: EBLetter { EBCurriculum.letters.first { $0.id == letterID } ?? EBCurriculum.letters[1] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Aynı harf, üç hareke").font(.title2)
                Text("Harfin noktaları aynı kalır. Üstündeki veya altındaki harekenin yerini ve şeklini karşılaştır.").font(.body)
                Picker("Çalışılacak harf", selection: $letterID) {
                    ForEach(EBCurriculum.letters) { letter in Text(letter.name + " · " + letter.arabic).tag(letter.id) }
                }.pickerStyle(.menu)
                HStack {
                    ForEach(EBVowel.allCases) { vowel in
                        VStack(spacing: 8) {
                            EBArabic(text: vowel.text(for: letter), size: 62)
                            Text(vowel.name).font(.headline)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding().sekineCard()
                ForEach(EBVowel.allCases) { vowel in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vowel.explanation).font(.body).lineSpacing(4)
                        Button { AdhanPlayer.shared.speakText(vowel.text(for: letter), language: "ar-SA") } label: {
                            Label(vowel.name + " örneğini dinle", systemImage: "speaker.wave.2.fill")
                        }.buttonStyle(.bordered)
                        if let score = store.scores[vowel.rawValue], score.attempts > 0 {
                            Text("Çalışmalarım: \(score.correct) / \(score.attempts) doğru").font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }.padding().sekineCard()
                }
                NavigationLink("İstenen harekeli harfi bul") { EBVowelQuizView(store: store, chooseForm: true) }.buttonStyle(.bordered)
                NavigationLink("9 soruluk hareke testi") { EBVowelQuizView(store: store) }.buttonStyle(.borderedProminent)
                Text("Sesler yapay zekâ örneğidir; ilk dinleme internet gerektirebilir. Bu test hareke işaretini tanımayı ölçer, telaffuzunu değerlendirmez.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background).navigationTitle("Harekeleri ayırt et")
            .onDisappear { AdhanPlayer.shared.stop() }
    }
}
struct EBVowelQuizView: View {
    @ObservedObject var store: EBVowelStore
    var chooseForm = false
    @State private var questions = EBVowelQuestion.make()
    @State private var index = 0
    @State private var answer: EBVowel?
    @State private var mistakes: [EBVowelQuestion] = []
    @State private var correctCount = 0
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if index < questions.count {
                    let question = questions[index]
                    Text("Soru \(index + 1) / \(questions.count)").font(.headline)
                    ProgressView(value: Double(index), total: Double(questions.count))
                    if chooseForm {
                        Text(question.letter.name + " harfinin " + question.vowel.name.lowercased() + " işaretli hâlini seç.")
                            .font(.title2).accessibilityIdentifier("vowelTarget-" + question.vowel.rawValue)
                    } else {
                        EBArabic(text: question.text, size: 110).padding(20).frame(maxWidth: .infinity).sekineCard()
                            .accessibilityIdentifier("vowelTarget-" + question.vowel.rawValue)
                        Text("Bu harfin harekesi hangisi?").font(.title2)
                    }
                    ForEach(EBVowel.allCases) { vowel in
                        Button {
                            guard answer == nil else { return }
                            answer = vowel
                            let correct = vowel == question.vowel
                            if correct { correctCount += 1 } else { mistakes.append(question) }
                            store.record(question.vowel, correct: correct)
                        } label: {
                            HStack {
                                if chooseForm { EBArabic(text: vowel.text(for: question.letter), size: 54).frame(maxWidth: .infinity) }
                                else { Text(vowel.name).font(.title3); Spacer() }
                                if answer != nil && vowel == question.vowel { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                                else if answer == vowel { Image(systemName: "xmark.circle.fill") }
                            }.foregroundStyle(Palette.textPrimary).padding(16).sekineCard()
                        }.buttonStyle(.plain).frame(maxWidth: .infinity)
                            .allowsHitTesting(answer == nil).accessibilityIdentifier("vowelOption-" + vowel.rawValue)
                    }
                    if let answer {
                        Text(answer == question.vowel ? "Doğru!" : "Doğru cevap: " + question.vowel.name).font(.title3)
                        Text(question.vowel.explanation).font(.body)
                        Button(index + 1 == questions.count ? "Sonucu gör" : "Sonraki soru") { index += 1; self.answer = nil }
                            .buttonStyle(.borderedProminent).tint(Color(red: 0.12, green: 0.38, blue: 0.25))
                    }
                } else {
                    Text("Hareke çalışması tamamlandı").font(.largeTitle)
                    Text("\(correctCount) / \(questions.count) doğru").font(.title)
                    Text("Hareke ilerlemen kaydedildi.").font(.body)
                    if !mistakes.isEmpty {
                        Button("Yanlışları tekrar çalış (\(mistakes.count))") { reset(mistakes) }
                            .buttonStyle(.borderedProminent).tint(Color(red: 0.12, green: 0.38, blue: 0.25)).accessibilityIdentifier("vowelRetry")
                    }
                    Button("Yeni çalışma") { reset(EBVowelQuestion.make()) }.buttonStyle(.bordered)
                }
            }.padding(24).padding(.bottom, 100)
        }.id(index).background(Palette.background).navigationTitle("Hareke testi")
    }
    private func reset(_ next: [EBVowelQuestion]) { questions = next; index = 0; answer = nil; mistakes = []; correctCount = 0 }
}


struct EBJoiningPracticeView: View {
    @ObservedObject var store: EBStudyStore
    @State private var letterID = "ba"
    private var letter: EBLetter { EBCurriculum.letters.first { $0.id == letterID } ?? EBCurriculum.letters[1] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Harf aynı, görünümü değişiyor").font(.title2)
                Text("Bağlantı çizgilerine bakarak harfi tanı. Noktalar, harfin kimliğini ayırt etmene yardım eder.").font(.body)
                Picker("Karşılaştırılacak harf", selection: $letterID) {
                    ForEach(EBCurriculum.letters) { letter in Text(letter.name + " · " + letter.arabic).tag(letter.id) }
                }.pickerStyle(.menu)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(0..<4) { index in
                        VStack {
                            EBArabic(text: letter.forms[index], size: 64)
                            Text(["Tek başına", "Başta", "Ortada", "Sonda"][index]).font(.headline)
                        }.frame(maxWidth: .infinity).padding().sekineCard()
                    }
                }
                Text(letter.joinsNext ? "Bu harf kendisinden sonraki harfe bağlanabilir." : "Bu harf kendisinden sonraki harfe bağlanmaz. Başta ve ortada bağlantı kesilir.").font(.body)
                Text("Sonraki harfe bağlanmayan altı harf").font(.headline)
                EBArabic(text: "ا د ذ ر ز و", size: 42).frame(maxWidth: .infinity)
                Text("Elif · Dal · Zel · Ra · Ze · Vav").font(.body)
                NavigationLink("Birleşik şekil testine başla") {
                    EBQuizView(store: store, pool: EBCurriculum.letters, listening: false, formPractice: true)
                }.buttonStyle(.borderedProminent)
                Text("Çizgiler bağlantıyı göstermek içindir; bu örnekler kelime değildir.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background).navigationTitle("Birleşik şekiller")
    }
}


struct EBAssessmentQuestion: Identifiable {
    let lessonID: Int
    let check: EBCheck
    var id: String { "\(lessonID):\(check.id)" }
    static func make(lessons: [EBLesson]) -> [Self] {
        lessons.flatMap { lesson in lesson.checks.map { Self(lessonID: lesson.id, check: $0) } }.shuffled()
    }
}
struct EBAssessmentSession: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let title: String
    let correct: Int
    let total: Int
}
struct EBAssessmentProgress: Codable {
    var scores: [Int: EBVowelScore] = [:]
    var sessions: [EBAssessmentSession] = []
}
@MainActor final class EBAssessmentStore: ObservableObject {
    @Published private(set) var progress: EBAssessmentProgress
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = defaults.data(forKey: "elifba.assessment.v1").flatMap { try? JSONDecoder().decode(EBAssessmentProgress.self, from: $0) } ?? EBAssessmentProgress()
    }
    func record(lessonID: Int, correct: Bool) {
        var score = progress.scores[lessonID] ?? EBVowelScore()
        score.attempts += 1
        if correct { score.correct += 1 }
        progress.scores[lessonID] = score
        save()
    }
    func finish(title: String, correct: Int, total: Int) {
        guard total > 0 else { return }
        progress.sessions.insert(.init(date: .now, title: title, correct: correct, total: total), at: 0)
        progress.sessions = Array(progress.sessions.prefix(20))
        save()
    }
    var recommendedLessons: [EBLesson] {
        EBCurriculum.lessons.filter {
            guard let score = progress.scores[$0.id] else { return false }
            return score.attempts > 0 && Double(score.correct) / Double(score.attempts) < 0.8
        }.sorted {
            let a = progress.scores[$0.id]!, b = progress.scores[$1.id]!
            let ar = Double(a.correct) / Double(a.attempts), br = Double(b.correct) / Double(b.attempts)
            return ar == br ? $0.id < $1.id : ar < br
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: "elifba.assessment.v1") }
    }
}
struct EBAssessmentView: View {
    @ObservedObject var store: EBAssessmentStore
    let lessons: [EBLesson]
    let title: String
    @State private var questions: [EBAssessmentQuestion] = []
    @State private var index = 0
    @State private var selected: Int?
    @State private var mistakes: [EBAssessmentQuestion] = []
    @State private var correctCount = 0
    @State private var started = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if index < questions.count {
                    let question = questions[index]
                    Text("Soru \(index + 1) / \(questions.count)").font(.headline)
                    ProgressView(value: Double(index), total: Double(questions.count))
                    Text(EBCurriculum.lessons.first { $0.id == question.lessonID }?.title ?? "").font(.subheadline).foregroundStyle(Palette.textSecondary)
                    Text(question.check.prompt).font(.title2).accessibilityIdentifier("assessmentPrompt")
                    ForEach(Array(question.check.choices.enumerated()), id: \.offset) { choice, text in
                        Button {
                            guard selected == nil else { return }
                            selected = choice
                            let correct = choice == question.check.answer
                            if correct { correctCount += 1 } else { mistakes.append(question) }
                            store.record(lessonID: question.lessonID, correct: correct)
                        } label: {
                            HStack {
                                Text(text).font(.title2)
                                Spacer()
                                if selected != nil && choice == question.check.answer { Image(systemName: "checkmark.circle.fill") }
                                else if selected == choice { Image(systemName: "xmark.circle.fill") }
                            }.padding(16).frame(maxWidth: .infinity).sekineCard()
                        }.buttonStyle(.plain).disabled(selected != nil).accessibilityIdentifier("assessmentOption-\(choice)")
                    }
                    if let selected {
                        Text(selected == question.check.answer ? "Doğru!" : "Doğru cevap: " + question.check.choices[question.check.answer]).font(.headline)
                        Text(question.check.explanation).font(.body).lineSpacing(5)
                        Button(index + 1 == questions.count ? "Sonucu gör" : "Sonraki soru") {
                            index += 1; self.selected = nil
                            if index == questions.count { store.finish(title: title, correct: correctCount, total: questions.count) }
                        }.buttonStyle(.borderedProminent)
                    }
                } else if started {
                    Text("Değerlendirme tamamlandı").font(.largeTitle)
                    Text("\(correctCount) / \(questions.count) doğru").font(.title)
                    Text("Sonucun ve konu bazındaki çalışmaların Gelişim bölümüne kaydedildi.").font(.body)
                    if !mistakes.isEmpty {
                        Text("Tekrar edilecek konular").font(.headline)
                        ForEach(lessons.filter { lesson in mistakes.contains { $0.lessonID == lesson.id } }) { lesson in
                            Text("• " + lesson.title).font(.body)
                        }
                        Button("Yanlış soruları tekrar çalış (\(mistakes.count))") { begin(mistakes.shuffled()) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("assessmentRetry")
                    }
                    Button("Yeni değerlendirme") { begin(EBAssessmentQuestion.make(lessons: lessons)) }.buttonStyle(.bordered)
                }
            }.padding(24).padding(.bottom, 100)
        }.id(index).background(Palette.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onAppear { if !started { begin(EBAssessmentQuestion.make(lessons: lessons)) } }
    }
    private func begin(_ next: [EBAssessmentQuestion]) {
        questions = next; index = 0; selected = nil; mistakes = []; correctCount = 0; started = true
    }
}
struct EBReadingWorkshop: View {
    @ObservedObject var store: EBStudyStore
    @ObservedObject var assessment: EBAssessmentStore
    private var lessons: [EBLesson] { EBCurriculum.lessons.filter { [6, 7, 8, 9].contains($0.id) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("İşaretin okuyuşa etkisini karşılaştır").font(.title2)
                Text("Cezim yeni ünlü eklemez; şedde harfi çift okutur; med uygun sesi uzatır; tenvin geçişli okumada sona n sesi katar.").font(.body).lineSpacing(5)
                ForEach(lessons) { lesson in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(lesson.title).font(.title2)
                        EBArabic(text: lesson.symbol, size: 48).frame(maxWidth: .infinity)
                        Text(lesson.explanation).font(.body).lineSpacing(5)
                        NavigationLink("\(lesson.title) dersini incele") { EBLessonView(lesson: lesson, store: store) }
                        NavigationLink("\(lesson.title) · 3 soruyla dene") {
                            EBAssessmentView(store: assessment, lessons: [lesson], title: lesson.title + " çalışması")
                        }.buttonStyle(.bordered).accessibilityIdentifier("workshopQuiz-\(lesson.id)")
                    }.padding(20).sekineCard()
                }
                NavigationLink("Karışık 12 soruluk değerlendirme") { EBAssessmentView(store: assessment, lessons: lessons, title: "Okumaya geçiş değerlendirmesi") }
                    .buttonStyle(.borderedProminent)
                Text("Bu çalışma işaret ve kural bilgisini ölçer. Doğru okuyuşu dinleme ve öğretici geri bildirimiyle pekiştir.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background).navigationTitle("Okumaya geçiş")
    }
}
struct EBProgressOverview: View {
    @ObservedObject var store: EBStudyStore
    @ObservedObject var assessment: EBAssessmentStore
    @State private var vowelScores: [String: EBVowelScore] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Çalışma yolculuğun").font(.title2)
            Text("\(store.progress.completedLessons.count) ders tamamlandı · bugün \(store.todayAnswers) harf sorusu cevaplandı.").font(.body)
            if !assessment.recommendedLessons.isEmpty {
                Text("Tekrar önerileri").font(.headline)
                ForEach(Array(assessment.recommendedLessons.prefix(4))) { lesson in
                    NavigationLink { EBLessonView(lesson: lesson, store: store) } label: {
                        Label(lesson.title + " konusunu pekiştir", systemImage: "arrow.clockwise")
                    }.buttonStyle(.bordered)
                }
            } else {
                Text("Değerlendirme çözdükçe tekrar önerilerin burada görünür.").font(.body).foregroundStyle(Palette.textSecondary)
            }
            Text("Konu bazında doğru / toplam").font(.headline)
            ForEach(EBCurriculum.lessons) { lesson in
                HStack {
                    Text(lesson.title)
                    Spacer()
                    if let score = assessment.progress.scores[lesson.id] { Text("\(score.correct) / \(score.attempts)").monospacedDigit() }
                    else { Text("Henüz çözülmedi").foregroundStyle(Palette.textSecondary) }
                }.font(.subheadline)
            }
            if !vowelScores.isEmpty {
                Text("Hareke çalışmaları").font(.headline)
                ForEach(EBVowel.allCases) { vowel in
                    if let score = vowelScores[vowel.rawValue] { Text("\(vowel.name): \(score.correct) / \(score.attempts) doğru") }
                }
            }
            if !assessment.progress.sessions.isEmpty {
                Text("Son çalışmalar").font(.headline)
                ForEach(Array(assessment.progress.sessions.prefix(5))) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.headline)
                        Text("\(session.correct) / \(session.total) doğru · " + session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Text("Puanlar alıştırma sonuçlarıdır; mahreç veya tecvid yeterliliği göstermez.").font(.footnote).foregroundStyle(Palette.textSecondary)
        }.padding(18).sekineCard()
            .onAppear { vowelScores = EBVowelStore().scores }
    }
}
