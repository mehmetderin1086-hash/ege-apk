import Foundation

enum QuestionFormat: String, Codable, CaseIterable, Identifiable {
    case mixed = "Karışık", visual = "Görsel", text = "Metin", listening = "Dinleme", ordering = "Sıralama", matching = "Eşleştirme", pronunciation = "Söyle ve dene"
    var id: String { rawValue }
    var databaseFilter: String { switch self { case .mixed: return ""; case .visual: return "visual"; case .text: return "text"; case .listening: return "listening"; case .ordering: return "ordering"; case .matching: return "matching"; case .pronunciation: return "pronunciation" } }
    func accepts(_ question: Question) -> Bool {
        switch self {
        case .mixed: return true
        case .visual: return question.visual != nil
        case .text: return question.visual == nil && question.activity == nil
        case .listening: return question.activity?.kind == .listening
        case .ordering: return question.activity?.kind == .ordering
        case .matching: return question.activity?.kind == .matching
        case .pronunciation: return question.activity?.kind == .pronunciation
        }
    }
    var instructions: String {
        switch self {
        case .mixed: return "Paket beş soruluksa en az iki soruyu görsel veriden çözülen tablo/grafik/şekil/resim sorusu olarak tasarla; diğerleri metin olabilir. Görsel türlerini çeşitlendir."
        case .visual: return "Bu istekte HER soruda geçerli visual nesnesi zorunludur. Sorular görselde verilen veriden çözülmeli; yalnız metin sorusu kabul edilmez. Beşlik pakette konuya uygun en az üç farklı görsel türü kullan."
        case .text: return "Bu istek yalnız çoktan seçmeli metin sorusu içindir. visual veya activity gönderme."
        case .listening: return "HER soru activity.kind=listening olan, dinlediğini anlama sorusu olmalıdır. Cevap ses metninden çıkarılmalı."
        case .ordering: return "HER soru activity.kind=ordering olan, dört öğeyi sıralama sorusu olmalıdır."
        case .pronunciation: return "HER soru activity.kind=pronunciation olan kısa yabancı dil söyleme alıştırması olmalıdır. Seçilen dil belirtilmemişse İngilizce kullan."
        case .matching: return "HER soru activity.kind=matching olan, dört çifti bire bir eşleştirme sorusu olmalıdır."
        }
    }
}

enum QuestionVisualKind: String, Codable, CaseIterable {
    case table, barChart, lineChart, diagram, image
    var title: String {
        switch self {
        case .table: return "Tablo"
        case .barChart: return "Sütun grafik"
        case .lineChart: return "Çizgi grafik"
        case .diagram: return "Şekil"
        case .image: return "Resim"
        }
    }
    var icon: String {
        switch self {
        case .table: return "tablecells"
        case .barChart: return "chart.bar.fill"
        case .lineChart: return "chart.xyaxis.line"
        case .diagram: return "square.on.circle"
        case .image: return "photo"
        }
    }
}

struct QuestionVisual: Codable, Equatable {
    let kind: QuestionVisualKind
    let title: String
    let summary: String
    var columns: [String]? = nil
    var rows: [[String]]? = nil
    var labels: [String]? = nil
    var values: [Double]? = nil
    var unit: String? = nil
    var elements: [VisualElement]? = nil
    var imageID: String? = nil

    var isValid: Bool {
        guard (1...80).contains(title.trimmingCharacters(in:.whitespacesAndNewlines).count), (8...600).contains(summary.count) else { return false }
        switch kind {
        case .table:
            guard let columns, let rows, (2...5).contains(columns.count), (1...8).contains(rows.count),
                  labels == nil, values == nil, unit == nil, elements == nil, imageID == nil else { return false }
            return Set(columns.map(Question.normalized)).count == columns.count && columns.allSatisfy { Self.text($0,limit:45) }
                && rows.allSatisfy { $0.count == columns.count && $0.allSatisfy { Self.text($0,limit:90) } }
        case .barChart, .lineChart:
            guard let labels, let values, (2...8).contains(labels.count), labels.count == values.count,
                  columns == nil, rows == nil, elements == nil, imageID == nil else { return false }
            return Set(labels.map(Question.normalized)).count == labels.count && labels.allSatisfy { Self.text($0,limit:30) }
                && values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && (unit == nil || unit!.count <= 35)
        case .diagram:
            guard let elements, (1...16).contains(elements.count), columns == nil, rows == nil, labels == nil, values == nil, unit == nil, imageID == nil else { return false }
            return elements.allSatisfy(\.isValid)
        case .image:
            guard let imageID, QuestionPhotoCatalog.items.contains(where:{ $0.id == imageID }),
                  columns == nil, rows == nil, labels == nil, values == nil, unit == nil, elements == nil else { return false }
            return true
        }
    }
    private static func text(_ value: String, limit: Int) -> Bool { (1...limit).contains(value.trimmingCharacters(in:.whitespacesAndNewlines).count) }
    var accessibleData: String {
        switch kind {
        case .table:
            return (rows ?? []).map { row in zip(columns ?? [],row).map { "\($0): \($1)" }.joined(separator:", ") }.joined(separator:"; ")
        case .barChart, .lineChart:
            return zip(labels ?? [],values ?? []).map { "\($0): \($1.formatted(.number.precision(.fractionLength(0...2)))) \(unit ?? "")" }.joined(separator:"; ")
        case .diagram: return summary
        case .image: return QuestionPhotoCatalog.items.first { $0.id == imageID }?.description ?? summary
        }
    }
    var contextForModel: String {
        let json = (try? JSONEncoder().encode(self)).map { String(decoding:$0,as:UTF8.self) } ?? ""
        return json + (kind == .image ? "\nKatalog konusu: \(QuestionPhotoCatalog.items.first { $0.id == imageID }?.subject ?? "")" : "")
    }
    static func requiresVisual(_ text: String) -> Bool {
        let text = Question.normalized(text)
        return ["aşağıdaki tabloda","tabloya gore","tabloya göre","grafige gore","grafiğe göre","grafikteki","sekildeki","şekildeki","resimdeki","gorseldeki","görseldeki","yukarıdaki grafik"].contains { text.contains(Question.normalized($0)) }
    }
    static let prompt = """
    Soruların bir bölümünde visual alanı kullan. Görsel, soruyu çözmek için gerekli veri içersin; yalnız süs veya emojili metin olmasın. Tablo/grafik verisi özgün bir alıştırma olabilir; gerçek istatistik diye sunma. Uydurulmuş ölçüm, grafik veya deney verisinin başlığını mutlaka “Örnek” ile başlat. Kontrol grubu sorularında deneyin amacı, değişkeni ve normal koşulu açıkça belirt; yalnız ışık/karanlık verilmesinden kontrol grubu çıkarma. Birimler ve etiketler açık, bütün sayısal veriler tutarlı olsun. Başlık ve summary cevabı söylemesin; summary yalnız görülen veriyi/şekli tarif etsin. Şema türleri:
    Tablo: "visual":{"kind":"table","title":"Ölçüm tablosu","summary":"Üç örneğin ölçümleri verilmiştir.","columns":["Örnek","Kütle (g)"],"rows":[["K","12"],["L","18"],["M","9"]]}.
    Grafik: "visual":{"kind":"barChart","title":"Deney ölçümleri","summary":"Üç örneğin ölçüm değerleri karşılaştırılıyor.","labels":["K","L","M"],"values":[12,18,9],"unit":"gram"}. Zaman/sıra verisinde kind="lineChart" da kullanılabilir. 2-8 farklı etiket, aynı sayıda sonlu değer; açıklama ve doğru cevap bu veriden hesaplanmalı.
    Şekil: "visual":{"kind":"diagram","title":"Geometrik şekil","summary":"Kenarları 8 cm ve 5 cm olarak verilen dikdörtgen.","elements":[{"shape":"rectangle","x":50,"y":50,"width":60,"height":45},{"shape":"text","x":50,"y":17,"label":"8 cm"},{"shape":"text","x":89,"y":50,"label":"5 cm"}]}.
    Koordinatlar 0-100 aralığındadır, x/y merkezdir. shape: circle, rectangle, triangle, point, line, arrow, text. Kapalı şekillerde width/height ve tüm sınırlar 0-100 içinde; line/arrow için endX/endY; text için kısa label gereklidir. En fazla 16 öğe. Çizim ölçekli değilse summary içinde belirt; şekilden ölçüm tahmin ettirme.
    Resim: "visual":{"kind":"image","title":"Görseli incele","summary":"Çalışma görselini inceleyerek cevapla.","imageID":"violin"}. Yalnız çevrimdışı katalog: violin=keman ve yay, bicycle=yan görünüş şehir bisikleti, leaf=yeşil yaprak. Soruyu bu sabit içerikle tutarlı kur; görünmeyen küçük ayrıntıları veya kişileri sorma. URL, base64, SVG, HTML, Markdown resim veya uydurma imageID kullanma.
    Her visual nesnesine yalnız kendi türünün alanlarını ekle. Diğer sorularda visual alanını hiç gönderme. Görsel gerektiren soru, visual olmadan geçerli değildir.
    """
}

enum VisualShape: String, Codable { case circle, rectangle, triangle, point, line, arrow, text }
enum VisualColor: String, Codable { case mint, blue, gold, pink, violet }
struct VisualElement: Codable, Equatable {
    let shape: VisualShape
    let x: Double
    let y: Double
    var width: Double? = nil
    var height: Double? = nil
    var endX: Double? = nil
    var endY: Double? = nil
    var label: String? = nil
    var color: VisualColor? = nil
    var isValid: Bool {
        func position(_ value: Double) -> Bool { value.isFinite && (0...100).contains(value) }
        guard position(x), position(y), label == nil || (1...40).contains(label!.trimmingCharacters(in:.whitespacesAndNewlines).count) else { return false }
        switch shape {
        case .circle, .rectangle, .triangle:
            guard let width, let height else { return false }
            return width.isFinite && height.isFinite && (2...95).contains(width) && (2...95).contains(height)
                && x-width/2 >= 0 && x+width/2 <= 100 && y-height/2 >= 0 && y+height/2 <= 100 && endX == nil && endY == nil
        case .line, .arrow:
            guard let endX, let endY else { return false }
            return position(endX) && position(endY) && (endX != x || endY != y) && width == nil && height == nil
        case .text: return label != nil && width == nil && height == nil && endX == nil && endY == nil
        case .point: return width == nil && height == nil && endX == nil && endY == nil
        }
    }
}

struct QuestionPhoto: Identifiable {
    let id: String
    let asset: String
    let subject: String
    let description: String
}
enum QuestionPhotoCatalog {
    static let items = [
        QuestionPhoto(id:"violin",asset:"QuestionViolin",subject:"Keman ve yay",description:"Kahverengi ahşap gövdeli, uzun saplı, dört telli bir çalgı ve yanında yay görünüyor."),
        QuestionPhoto(id:"bicycle",asset:"QuestionBicycle",subject:"Şehir bisikleti",description:"Yandan görülen, iki tekerleği, pedalları, zinciri ve gidonu olan bir taşıt."),
        QuestionPhoto(id:"leaf",asset:"QuestionLeaf",subject:"Yeşil yaprak",description:"Açık zeminde tek yeşil yaprak; ortada ana damar ve ondan ayrılan ince damarlar görülüyor.")
    ]
}
