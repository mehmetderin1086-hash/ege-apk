import Foundation

enum ActivityKind: String, Codable, CaseIterable {
    case listening, ordering, matching, pronunciation
    var title: String { switch self { case .listening: return "Dinleme"; case .ordering: return "Sıralama"; case .matching: return "Eşleştirme"; case .pronunciation: return "Söyle ve dene" } }
    var icon: String { switch self { case .listening: return "headphones"; case .ordering: return "list.number"; case .matching: return "arrow.left.arrow.right"; case .pronunciation: return "waveform.and.mic" } }
}
struct ActivityResponse: Codable, Equatable { let indices: [Int]; var spokenText: String? = nil }
struct QuestionActivity: Codable, Equatable {
    let kind: ActivityKind
    let title: String
    var transcript: String? = nil
    var language: String? = nil
    var items: [String]? = nil
    var left: [String]? = nil
    var right: [String]? = nil
    var solution: [Int]? = nil
    static let languages = ["tr-TR","en-US","de-DE","fr-FR","es-ES","ar-SA"]
    var isInteractive: Bool { kind == .ordering || kind == .matching }
    var needsResponse: Bool { isInteractive || kind == .pronunciation }
    var isValid: Bool {
        func labels(_ list: [String]?, maxLength: Int) -> Bool {
            guard let list, list.count == 4 else { return false }
            return list.allSatisfy { (1...maxLength).contains($0.trimmingCharacters(in:.whitespacesAndNewlines).count) }
                && Set(list.map(Question.normalized)).count == 4
        }
        guard (1...80).contains(title.trimmingCharacters(in:.whitespacesAndNewlines).count) else { return false }
        switch kind {
        case .listening, .pronunciation:
            guard let transcript, let language else { return false }
            return (kind == .listening ? 20...1200 : 2...160).contains(transcript.trimmingCharacters(in:.whitespacesAndNewlines).count) && Self.languages.contains(language) && (kind != .pronunciation || language != "tr-TR")
                && items == nil && left == nil && right == nil && solution == nil
        case .ordering:
            return labels(items,maxLength:35) && validPermutation(solution) && transcript == nil && language == nil && left == nil && right == nil
        case .matching:
            return labels(left,maxLength:55) && labels(right,maxLength:55) && validPermutation(solution) && transcript == nil && language == nil && items == nil
        }
    }
    private func validPermutation(_ indices: [Int]?) -> Bool { indices?.count == 4 && Set(indices ?? []) == Set(0..<4) }
    func accepts(_ response: ActivityResponse) -> Bool {
        if kind == .pronunciation { return response.indices.isEmpty && response.spokenText.map { !VoiceAnswerResolver.clean($0).isEmpty && $0.count <= 300 } == true }
        return isInteractive && validPermutation(response.indices)
    }
    func isCorrect(_ response: ActivityResponse) -> Bool {
        guard accepts(response) else { return false }
        if kind == .pronunciation { return VoiceAnswerResolver.clean(response.spokenText ?? "") == VoiceAnswerResolver.clean(transcript ?? "") }
        return response.indices == solution
    }
    func describe(_ response: ActivityResponse) -> String {
        guard accepts(response) else { return "Yanıtlanmadı" }
        if kind == .pronunciation { return response.spokenText ?? "" }
        if kind == .ordering { return response.indices.map { items![$0] }.joined(separator:" → ") }
        return (0..<4).map { "\(left![$0]) ↔ \(right![response.indices[$0]])" }.joined(separator:" · ")
    }
    var solutionText: String { if kind == .pronunciation { return transcript ?? "" }; return solution.map { describe(.init(indices:$0)) } ?? "" }
    // Four compatibility choices are stored for existing records; these are not the interactive UI.
    var canonicalOptions: [String] {
        if kind == .pronunciation { return ["Hedef ifade anlaşıldı","İfade farklı anlaşıldı","Eksik ifade","Farklı kelimeler"] }
        guard isValid, let solution else { return [] }
        return (0..<4).map { shift in
            let order = Array(solution.dropFirst(shift)) + Array(solution.prefix(shift))
            if kind == .ordering { return order.map { items![$0] }.joined(separator:" → ") }
            return order.enumerated().map { "\($0.offset+1)→\($0.element+1)" }.joined(separator:" · ")
        }
    }
    func shuffled() -> Self {
        guard isValid, isInteractive else { return self }
        var copy = self
        let order = Array(0..<4).shuffled()
        if kind == .ordering {
            copy.items = order.map { items![$0] }
            copy.solution = solution!.map { order.firstIndex(of:$0)! }
        } else {
            let rightOrder = Array(0..<4).shuffled()
            copy.left = order.map { left![$0] }; copy.right = rightOrder.map { right![$0] }
            copy.solution = order.map { rightOrder.firstIndex(of:solution![$0])! }
        }
        return copy
    }
    var contextForModel: String { (try? JSONEncoder().encode(self)).map { String(decoding:$0,as:UTF8.self) } ?? "" }
    static func requiresAudio(_ text: String) -> Bool {
        ["dinlediğin metne göre","ses kaydına göre","dinleme parçasına göre"].contains { Question.normalized(text).contains(Question.normalized($0)) }
    }
    static let prompt = """
    Yeni soru türleri için isteğe bağlı activity alanı kullan; aynı soruda visual ve activity birlikte OLAMAZ.
    Dinleme: "activity":{"kind":"listening","title":"Dinle ve yanıtla","language":"en-US","transcript":"Mina takes the train to school every morning. On rainy days she carries a blue umbrella."}. Soru Türkçe olabilir; cevap yalnız duyulan metinden çıkarılmalı. 20-1200 karakterlik kısa özgün anlatı, diyalog veya yabancı dil parçası yaz; şarkı sözü veya ünlü bir kişinin sesini taklit etme. Metin sorunun text alanında tekrar edilmez. Başlık cevabı ele vermesin. Desteklenen diller: tr-TR,en-US,de-DE,fr-FR,es-ES,ar-SA. Dinleme sorusunda dört seçenek, answer ve dört optionExplanations alanı yine gereklidir.
    Sıralama: "activity":{"kind":"ordering","title":"Küçükten büyüğe sırala","items":["30","10","40","20"],"solution":[1,3,0,2]}. Tam dört kısa öğe, her öğe en fazla 35 karakter. solution, items dizisinin 0 tabanlı indekslerinden oluşan tek doğru sıradır. Sıralama kuralı soruda açık olmalı; eşitlik veya birden fazla geçerli sıra olmasın. Öğeleri doğru sırada gönderme.
    Eşleştirme: "activity":{"kind":"matching","title":"Sözcükleri eşleştir","left":["Cat","Book","Water","Sun"],"right":["Güneş","Kedi","Su","Kitap"],"solution":[1,3,2,0]}. Tam dört farklı sol ve dört farklı sağ öğe; her biri en fazla 55 karakter. solution[i], left[i] için doğru right indeksidir. Bire bir, tek anlamlı eşleşmeler kur; her sağ öğe tam bir kez kullanılır.
    Yabancı dil söyleme alıştırması: "activity":{"kind":"pronunciation","title":"İngilizce ifade çalışması","language":"en-US","transcript":"Good morning"}. 2-160 karakterlik kısa, özgün yabancı dil ifadesi. text alanında kullanıcıdan ifadeyi söylemesini iste. İfade baştan gösterilir ve dinlenebilir. Bu tür, konuşmanın hedef kelimelerle eşleşmesini kontrol eder; aksan/tek ses için bilimsel bir puan verdiğini iddia etme. options/answer/optionExplanations gerekmez, istemci doldurur.
    Sıralama ve eşleştirmede options, answer, optionExplanations uyumluluk alanlarını istemci otomatik doldurur; bu üç alanı göndermeyebilirsin. Her türde text, explanation, category, difficulty zorunludur. Açıklamada doğru sıralama/eşleşme ve nedeni açık olsun. Anlamsal doğruluğu ve solution indekslerini göndermeden kontrol et. Diğer türlerin alanlarını activity içine koyma; HTML, URL, ses dosyası veya base64 gönderme.
    """
}
extension Question {
    var correctAnswerText: String { activity?.needsResponse == true ? activity!.solutionText : options[answer] }
    func replacingActivity(_ value: QuestionActivity) -> Question {
        guard value.needsResponse else { var q = self; q.activity = value; return q }
        return Question(text:text,options:value.canonicalOptions,answer:0,explanation:explanation,category:category,difficulty:difficulty,
                        optionExplanations:[String(explanation.prefix(500)),"Bu düzen doğru çözümle uyuşmuyor.","Bu düzen doğru çözümle uyuşmuyor.","Bu düzen doğru çözümle uyuşmuyor."],modelID:modelID,reviewedBy:reviewedBy,activity:value,study:study)
    }
}
