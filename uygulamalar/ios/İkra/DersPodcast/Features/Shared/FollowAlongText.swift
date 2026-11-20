import SwiftUI
import UserNotifications

/// Okurken takip: konuşulan kelime sarı vurgulu, okunmuş kısım koyu, kalan kısım soluk.
/// Kelime zamanları, zamanı bilinen parçaların (altyazı satırı) içinde karakter uzunluğuyla dağıtılır;
/// sesin sessizlikleri biliniyorsa yalnızca konuşulan süreye dağıtılır (duraklarda vurgu ilerlemez).
nonisolated enum FollowAlong {
    struct Word: Hashable, Sendable { var range: Range<String.Index>; var from: Double; var to: Double }
    /// Zamanı bilinen parça: metnin sıradaki `words` kelimesi [start, end] arasında söylenir.
    /// `times` (kelime başlama zamanları, sn) varsa ve sayısı `words` ile tutuyorsa kelimeler doğrudan bunlarla eşlenir.
    struct Span: Hashable, Sendable {
        var start: Double
        var end: Double
        var words: Int
        var times: [Double]? = nil
        /// Satır başka bir konuşmacıya (öğrenci) ait: kelimeleri ayrı renkte gösterilir.
        var student: Bool = false
    }
    /// Seste ölçülmüş sessizlik (sn).
    struct Pause: Hashable, Sendable, Codable { var start: Double; var end: Double }

    /// Kelimelerin metin içindeki aralıkları ve 0…1 arasında başlangıç/bitiş payları.
    static func words(in text: String) -> [Word] {
        var spans: [(Range<String.Index>, Double)] = []
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex else { break }
            let start = i
            while i < text.endIndex, !text[i].isWhitespace { i = text.index(after: i) }
            let word = text[start..<i]
            // Ağırlık: harf sayısı + noktalama sonrası duraklama.
            var weight = Double(word.count) + 1
            if let last = word.last, ".!?".contains(last) { weight += 4 } else if let last = word.last, ",;:".contains(last) { weight += 2 }
            spans.append((start..<i, weight))
        }
        let total = spans.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        var acc = 0.0
        return spans.map { span in
            let from = acc / total
            acc += span.1
            return Word(range: span.0, from: from, to: acc / total)
        }
    }

    /// `progress` (0…1) anında okunan kelimenin sırası.
    static func current(_ words: [Word], progress: Double) -> Int? {
        guard !words.isEmpty, progress >= 0 else { return nil }
        if progress >= 1 { return words.count - 1 }
        var lo = 0, hi = words.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if words[mid].from <= progress { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// `link`: kelime sırasına bağlantı verir (dokunarak atla kipi); nil = bağlantısız.
    /// `students`: kelime başına "öğrenci konuşması" bayrağı (`studentWords`); işaretli kelimeler `studentColor` ile gösterilir.
    static func attributed(_ text: String, words: [Word], current: Int?, highlight: Color, readColor: Color, upcoming: Color,
                           students: [Bool] = [], studentColor: Color = studentColor, studentUpcoming: Color = studentColor.opacity(0.5),
                           link: ((Int) -> URL?)? = nil) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for (i, w) in words.enumerated() {
            if cursor < w.range.lowerBound { out.append(AttributedString(String(text[cursor..<w.range.lowerBound]))) }
            var piece = AttributedString(String(text[w.range]))
            if let current, i == current {
                piece.backgroundColor = highlight
                piece.foregroundColor = .black
            } else {
                let read = (current.map { i < $0 } ?? false)
                if students.indices.contains(i), students[i] {
                    piece.foregroundColor = read ? studentColor : studentUpcoming
                } else {
                    piece.foregroundColor = read ? readColor : upcoming
                }
            }
            if let url = link?(i) { piece.link = url }
            out.append(piece)
            cursor = w.range.upperBound
        }
        if cursor < text.endIndex { out.append(AttributedString(String(text[cursor...]))) }
        return out
    }

    static let highlight = Color(red: 0.97, green: 0.85, blue: 0.42)
    /// Öğrenci konuşmasının rengi.
    static let studentColor = Theme.goldInk
}

/// Zaman aralığı bilinen bir metni çalan sese göre kelime kelime vurgular.
struct FollowAlongText: View {
    var text: String
    var start: Double
    var end: Double
    var time: Double
    var font: Font = .body
    var spans: [FollowAlong.Span] = []
    var pauses: [FollowAlong.Pause] = []
    var link: ((Int) -> URL?)? = nil

    var body: some View {
        let timing = FollowAlong.Timing(text: text, start: start, end: end, spans: spans, pauses: pauses)
        Text(FollowAlong.attributed(text, words: timing.words, current: timing.current(at: time),
                                    highlight: FollowAlong.highlight, readColor: .primary, upcoming: .secondary.opacity(0.55),
                                    students: timing.students, link: link))
            .font(font)   // animasyon yok: nitelikli metin geçişi vurgu kutusunu kelimeden kaydırıyordu
    }
}

/// Cihaz sesiyle (AVSpeechSynthesizer) okunan metin: gerçek okunan aralık vurgulanır.
struct SpokenText: View {
    var text: String
    var speech: SpeechOut
    var font: Font = .body

    var body: some View {
        if speech.isSpeaking, speech.spokenText == text, let range = speech.spokenRange, let r = Range(range, in: text) {
            let words = FollowAlong.words(in: text)
            let index = words.firstIndex { $0.range.overlaps(r) || $0.range.lowerBound >= r.lowerBound }
            Text(FollowAlong.attributed(text, words: words, current: index, highlight: FollowAlong.highlight,
                                        readColor: .primary, upcoming: .secondary.opacity(0.55)))
                .font(font)
        } else {
            Text(text).font(font)
        }
    }
}

nonisolated extension FollowAlong {
    /// Bir metnin kelime zamanları: her kelimenin başlama anı (sn).
    struct Timing: Sendable {
        let words: [Word]
        let times: [Double]
        /// Kelime başına öğrenci bayrağı (öğrenci parçası yoksa boş).
        let students: [Bool]

        init(text: String, start: Double, end: Double, spans: [Span] = [], pauses: [Pause] = []) {
            words = FollowAlong.words(in: text)
            times = FollowAlong.startTimes(words, in: text, start: start, end: end, spans: spans, pauses: pauses)
            students = FollowAlong.studentWords(wordCount: words.count, spans: spans)
        }

        /// `time` anında söylenen kelime; ilk kelimeden önce (ör. baştaki sessizlik) nil.
        func current(at time: Double) -> Int? {
            guard let first = times.first, time >= first else { return nil }
            var lo = 0, hi = times.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if times[mid] <= time { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        /// Okunan yerin metin içindeki konumu (0…1): sayfa kaydırması vurguyla aynı yeri izlesin.
        func textProgress(at time: Double) -> Double {
            guard let i = current(at: time) else { return 0 }
            let next = i + 1 < times.count ? times[i + 1] : times[i]
            let within = next > times[i] ? min(max((time - times[i]) / (next - times[i]), 0), 1) : 1
            return words[i].from + (words[i].to - words[i].from) * within
        }
    }

    /// Metnin kelimelerinin parçalara (altyazı satırlarına) bölünmesi: kelimeler parçalara sayıca orantılı dağıtılır
    /// (kelime sayısı toplamla tam tutarsa birebir). `exact`: parçanın kelime zamanları bu gruba birebir uyuyor.
    /// Kullanılabilir parça yoksa boş. Zamanlama (`startTimes`) ve öğrenci renklendirmesi (`studentWords`) aynı bölmeyi kullanır.
    static func spanGroups(wordCount: Int, spans: [Span]) -> [(range: Range<Int>, span: Span, exact: Bool)] {
        let usable = spans.filter { $0.words > 0 && $0.end >= $0.start }.sorted { $0.start < $1.start }
        let total = usable.reduce(0) { $0 + $1.words }
        guard total > 0, wordCount > 0 else { return [] }
        var groups: [(range: Range<Int>, span: Span, exact: Bool)] = []
        var cumulative = 0, lower = 0
        for (k, span) in usable.enumerated() {
            cumulative += span.words
            let upper = k == usable.count - 1
                ? wordCount
                : min(wordCount, Int((Double(cumulative) * Double(wordCount) / Double(total)).rounded()))
            if upper > lower {
                // Kelime zamanları yalnızca sayılar birebir tutuyorsa kullanılır (metin düzeltilmiş/temizlenmiş olabilir).
                let exact = span.times?.count == span.words && upper - lower == span.words
                groups.append((lower..<upper, span, exact))
            }
            lower = max(lower, upper)
        }
        return groups
    }

    /// Kelime başına "öğrenci konuşması" bayrağı: öğrenci parçasının kelime aralığı. Öğrenci parçası yoksa boş dizi.
    static func studentWords(wordCount: Int, spans: [Span]) -> [Bool] {
        guard spans.contains(where: \.student) else { return [] }
        var flags = [Bool](repeating: false, count: wordCount)
        for group in spanGroups(wordCount: wordCount, spans: spans) where group.span.student {
            for i in group.range { flags[i] = true }
        }
        return flags
    }

    /// Kelimelerin başlama zamanları (sn).
    /// Parçalar verilirse kelimeler parçalara sayıca bölünür (metinle tam tutmazsa orantılı) ve her parça kendi süresine dağıtılır.
    /// Sessizlikler verilirse yalnızca konuşulan süre kullanılır; duraklar ölçüldüğü için noktalama payı eklenmez.
    static func startTimes(_ words: [Word], in text: String, start: Double, end: Double,
                           spans: [Span] = [], pauses: [Pause] = []) -> [Double] {
        guard !words.isEmpty else { return [] }
        let measured = !pauses.isEmpty
        let weights = words.map { w -> Double in
            let token = text[w.range]
            var weight = Double(token.count) + 1
            if !measured, let last = token.last {
                if ".!?".contains(last) { weight += 4 } else if ",;:".contains(last) { weight += 2 }
            }
            return weight
        }

        let found = spanGroups(wordCount: words.count, spans: spans)
        let groups: [(range: Range<Int>, start: Double, end: Double, times: [Double]?)] = found.isEmpty
            ? [(0..<words.count, start, end, nil)]
            : found.map { ($0.range, $0.span.start, $0.span.end, $0.exact ? $0.span.times : nil) }

        var times = [Double](repeating: start, count: words.count)
        for group in groups {
            if let exact = group.times {
                for (k, i) in group.range.enumerated() { times[i] = exact[k] }
                continue
            }
            let pieces = voicedPieces(from: group.start, to: group.end, pauses: pauses)
            let voiced = pieces.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            let sum = group.range.reduce(0.0) { $0 + weights[$1] }
            var acc = 0.0
            for i in group.range {
                times[i] = locate(sum > 0 ? voiced * acc / sum : 0, in: pieces)
                acc += weights[i]
            }
        }
        // Kelime zamanları azalmaz (ikili arama sıralı dizi ister; ölçülmüş zamanlarda küçük sapmalar olabilir).
        for i in times.indices.dropFirst() where times[i] < times[i - 1] { times[i] = times[i - 1] }
        return times
    }

    /// [from, to] aralığının sessizlikler çıkarılmış (konuşulan) parçaları. Ölçüm şüpheliyse (neredeyse hepsi sessiz) aralığın tamamı.
    static func voicedPieces(from: Double, to: Double, pauses: [Pause]) -> [ClosedRange<Double>] {
        guard to > from else { return [from...from] }
        var pieces: [ClosedRange<Double>] = []
        var cursor = from
        // Sessizlikler başlangıca göre sıralı: aralıkla çakışan ilk sessizliği ikili aramayla bul.
        var lo = 0, hi = pauses.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pauses[mid].end <= from { lo = mid + 1 } else { hi = mid }
        }
        var i = lo
        while i < pauses.count, pauses[i].start < to {
            let p = pauses[i]
            if p.start > cursor { pieces.append(cursor...p.start) }
            cursor = max(cursor, p.end)
            i += 1
        }
        if cursor < to { pieces.append(cursor...to) }
        let voiced = pieces.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        return voiced >= (to - from) * 0.2 ? pieces : [from...to]
    }

    /// Vurgunun bakacağı an: oynatıcı zamanı 0,1 sn'lik tiklerle geldiği için vurgu ortalama bir tik geride kalıyordu;
    /// bir tik kadar (oynatma hızıyla ölçeklenmiş) öne alınır. Göz okurken sesin hafif önünde olmayı yadırgamaz, gerisini yadırgar.
    static func readingTime(_ time: Double, rate: Double) -> Double {
        time + 0.1 * min(max(rate, 0.5), 3)
    }

    /// DEBUG `-logSync`: oynatıcı zamanı ve vurgulanan kelime (ses–yazı eşleşmesini gerçek kelime zamanlarıyla ölçmek için).
    static func logSync(time: Double, text: String, timing: Timing, reading: Double) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-logSync"), let i = timing.current(at: reading) else { return }
        print(String(format: "SYNC %.2f %d ", time, i) + text[timing.words[i].range])
        #endif
    }

    /// Konuşulan süre içindeki `offset` saniyenin gerçek zamanı.
    private static func locate(_ offset: Double, in pieces: [ClosedRange<Double>]) -> Double {
        var remaining = offset
        for piece in pieces {
            let length = piece.upperBound - piece.lowerBound
            if remaining <= length { return piece.lowerBound + remaining }
            remaining -= length
        }
        return pieces.last?.upperBound ?? 0
    }
}

nonisolated extension FollowAlong {
    /// Okunan yerin ekranda duracağı yükseklik oranı (üst üçte bir).
    static let readingLine = 0.35
    /// Bu bant içinde kaldıkça kaydırma yapılmaz (titreme ve kullanıcıyla çekişme olmasın).
    static let bandTop = 0.16, bandBottom = 0.55

    /// Okunan nokta ekranın `onScreen` yüksekliğindeyken (0 = üst) kaydırma gerekir mi ve ne kadar?
    /// Döner: nil (gerek yok) ya da içerik ofsetine eklenecek fark.
    /// Kural: normal okumada sayfa YALNIZCA AŞAĞI kayar (okunan yer ekranın alt kısmına inince %35'e getirilir).
    /// Okunan yer ekranda ve üst yarıdaysa dokunulmaz — yeni paragraf başında sayfa geri (yukarı) gitmez.
    /// Yukarı kaydırma yalnızca okunan yer ekranın tamamen dışındaysa (ör. geri sarma) yapılır.
    static func scrollDelta(onScreen: Double, viewport: Double, force: Bool = false) -> Double? {
        guard viewport > 0 else { return nil }
        let offScreen = onScreen < 0 || onScreen > viewport
        guard offScreen || onScreen > viewport * bandBottom else { return nil }
        let delta = onScreen - readingLine * viewport
        return abs(delta) < 2 ? nil : delta
    }

    /// Yeni ofset: kaydırma sınırlarına (en üst … en alt) sıkıştırılır.
    static func clampOffset(_ value: Double, minOffset: Double, maxOffset: Double) -> Double {
        min(max(value, minOffset), max(minOffset, maxOffset))
    }
}

/// Okuma takipçisi: çalan satırın ekrandaki ölçülen çerçevesine göre sayfayı mutlak ofsetle kaydırır.
/// Satır çizilmemişse (ileri sarma) kimlikle yaklaşır; ölçüm gelince düzeltir. Kullanıcı kaydırınca 4 sn bekler.
@Observable
final class ReadingFollower {
    var position = ScrollPosition()
    /// Çalan satırın, kaydırma görünümünün koordinat uzayındaki çerçevesi (yalnızca çalan satır bildirir).
    var currentFrame: CGRect?
    var currentRow: Int?
    var offset: Double = 0
    var minOffset: Double = 0
    var maxOffset: Double = 0
    var viewport: Double = 0
    var pausedUntil = Date.distantPast
    private var lastRow: Int?
    private var lastIDScroll: Int?
    /// Satır değişiminin zamanı: ölçüm gelmeden kimlikle kaydırmak için kısa bir süre beklenir
    /// (açılışta ve paragraf geçişinde sayfanın aşağı-yukarı sekmesini önler).
    private var rowChangedAt = Date.distantPast

    nonisolated static let space = "readingScroll"

    func userScrolled() { pausedUntil = .now.addingTimeInterval(4) }

    func geometry(_ g: ScrollGeometry) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-logScroll") {
            print("SCROLLGEO x=\(g.contentOffset.x) y=\(Int(g.contentOffset.y)) content=\(Int(g.contentSize.width))x\(Int(g.contentSize.height)) container=\(Int(g.containerSize.width)) insets=\(g.contentInsets.leading),\(g.contentInsets.trailing)")
        }
        #endif
        offset = g.contentOffset.y
        minOffset = -g.contentInsets.top
        maxOffset = g.contentSize.height + g.contentInsets.bottom - g.containerSize.height
        viewport = g.containerSize.height
    }

    /// Her oynatma tikinde çağrılır.
    func follow(row: Int, progress: Double, playing: Bool) {
        guard playing, Date.now >= pausedUntil else { lastRow = row; return }
        let rowChanged = row != lastRow
        if rowChanged { rowChangedAt = .now }
        lastRow = row
        guard let frame = currentFrame, currentRow == row else {
            // Satır henüz ölçülmedi: önce kısa süre ölçümü bekle (genelde hemen gelir); gelmezse (satır çizilmemiş,
            // ör. ileri sarma) kimlikle yaklaş — bir kez; ölçüm gelince aşağıdaki yol düzeltir.
            guard Date.now.timeIntervalSince(rowChangedAt) > 0.8 else { return }
            if lastIDScroll != row {
                lastIDScroll = row
                withAnimation(.smooth(duration: 0.4)) { position.scrollTo(id: row, anchor: UnitPoint(x: 0.5, y: FollowAlong.readingLine)) }
            }
            return
        }
        lastIDScroll = nil
        let onScreen = frame.minY + min(1, max(0, progress)) * frame.height
        guard let delta = FollowAlong.scrollDelta(onScreen: onScreen, viewport: viewport, force: rowChanged) else { return }
        let target = FollowAlong.clampOffset(offset + delta, minOffset: minOffset, maxOffset: maxOffset)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-logScroll") {
            print("FOLLOW row=\(row) p=\(String(format: "%.3f", progress)) minY=\(Int(frame.minY)) h=\(Int(frame.height)) onScreen=\(Int(onScreen)) vp=\(Int(viewport)) delta=\(Int(delta)) offset=\(Int(offset)) target=\(Int(target)) changed=\(rowChanged)")
        }
        #endif
        guard abs(target - offset) > 1 else { return }
        // x her zaman 0: kimlikle kaydırma yatay konumu da değiştirebiliyordu; ikisi sırayla çalışınca
        // içerik sağa sola oynuyordu.
        withAnimation(.smooth(duration: 0.45)) { position.scrollTo(point: CGPoint(x: 0, y: target)) }
    }
}

extension View {
    /// Kaydırma görünümüne takipçiyi bağlar: konum bağlama, geometri ve kullanıcı kaydırması.
    func readingFollower(_ follower: ReadingFollower) -> some View {
        modifier(ReadingFollowerModifier(follower: follower))
    }

    /// Çalan satıra eklenir: çerçevesini takipçiye bildirir.
    func reportsReadingFrame(row: Int, to follower: ReadingFollower, isCurrent: Bool) -> some View {
        modifier(ReadingFrameReporter(row: row, follower: follower, isCurrent: isCurrent))
    }
}

private struct ReadingFollowerModifier: ViewModifier {
    @Bindable var follower: ReadingFollower

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(ReadingFollower.space))
            // Çapa yatayda ortalı: SwiftUI içerik yeniden ölçülünce kaydırma konumunu satırın sol üst köşesine
            // göre koruyordu ve içeriği kenar boşluğu kadar (10 nokta) yana kaydırıyordu → ekran sağa sola oynuyordu.
            .scrollPosition($follower.position, anchor: .top)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: ScrollGeometrySnapshot.self) { ScrollGeometrySnapshot($0) } action: { _, g in follower.geometry(g.geometry) }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .tracking || phase == .decelerating { follower.userScrolled() }
            }
    }
}

/// ScrollGeometry Equatable değil; karşılaştırma için sarmalayıcı.
private struct ScrollGeometrySnapshot: Equatable {
    var geometry: ScrollGeometry
    init(_ g: ScrollGeometry) { geometry = g }
    static func == (a: Self, b: Self) -> Bool {
        a.geometry.contentOffset == b.geometry.contentOffset && a.geometry.contentSize == b.geometry.contentSize
            && a.geometry.containerSize == b.geometry.containerSize && a.geometry.contentInsets == b.geometry.contentInsets
    }
}

private struct ReadingFrameReporter: ViewModifier {
    var row: Int
    var follower: ReadingFollower
    var isCurrent: Bool

    func body(content: Content) -> some View {
        // Her satıra bağlıdır (görünüm kimliği değişmesin); yalnızca çalan satır bildirir.
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ReadingFollower.space)) } action: { frame in
            guard isCurrent else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-logScroll") {
                print("ROWFRAME f=\(ObjectIdentifier(follower).hashValue % 1000) row=\(row) minX=\(frame.minX) width=\(frame.width) minY=\(Int(frame.minY))")
            }
            #endif
            follower.currentRow = row
            follower.currentFrame = frame
        }
    }
}

/// Transkript okuma yazı boyutu (tüm uygulamada ortak).
enum ReadingSize {
    static let key = "reading.textSize"
    static let defaultSize: Double = 22
    static let options: [(String, Double)] = [("Normal", 17), ("Büyük", 22), ("Çok büyük", 27), ("Dev", 32)]
}

/// "Aa" düğmesi: okuma yazı boyutu seçimi.
struct ReadingSizeMenu: View {
    @AppStorage(ReadingSize.key) private var size = ReadingSize.defaultSize
    /// Etiketin en küçük dokunma kenarı; nil = simge kadar (eski düzen).
    var minTarget: CGFloat? = nil

    var body: some View {
        Menu {
            Picker("Okuma yazısı", selection: $size) {
                ForEach(ReadingSize.options, id: \.1) { Text($0.0).tag($0.1) }
            }
        } label: {
            Image(systemName: "textformat.size").foregroundStyle(.secondary)
                .frame(minWidth: minTarget, minHeight: minTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Okuma yazı boyutu")
    }
}

/// Bildirim izni isteklerinin tek kapısı (hata ayıklama demosunda sistem uyarısı ekranı kapatmasın).
enum NotificationGate {
    static func request(_ center: UNUserNotificationCenter, options: UNAuthorizationOptions) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-followDemo") { return false }
        // Ekran denetimi: `-noNotifyPrompt` ile sistem izin uyarısı sayfaları örtmesin (izin sorulmaz).
        if ProcessInfo.processInfo.arguments.contains("-noNotifyPrompt") { return false }
        // Birim testleri sırasında sistem izin uyarısı açılıp simülatörde asılı kalmasın.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #endif
        return (try? await center.requestAuthorization(options: options)) ?? false
    }
}

/// Okuma modu alt çubuğu: süre solda, hız sağda (ikisi de küçülebilir), düğmeler ortada sabit.
/// Sabit genişlikli parçalar dar ekranda (Ekran Büyütme, büyük yazı) çubuğu ekrandan taşırıp
/// tüm sayfayı genişletiyordu; bu düzen her genişliğe sığar.
struct ReaderTransportBar: View {
    var timeText: String
    var progress: Double
    var isPlaying: Bool
    var rateText: String
    var rates: [Double]
    var back: () -> Void
    var toggle: () -> Void
    var forward: () -> Void
    var setRate: (Double) -> Void
    /// İleri atlama süresi (simge ve etiket); podcast 15, ders videosu varsayılan 30.
    var skipSeconds: Double = 30
    /// Hız menüsü yazımı (podcast `rateText`: "1,25×"); nil = "%g×".
    var rateLabel: ((Double) -> String)? = nil
    /// Seçili hız (menüde onay imi); nil = im yok.
    var currentRate: Double? = nil

    private var timeLabel: some View {
        Text(timeText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var buttons: some View {
        // Atlama düğmeleri 44×44; aralık küçüldüğü için toplam genişlik (ve tek/iki satır kararı) aynı kalır.
        HStack(spacing: 2) {
            Button(action: back) { Image(systemName: "gobackward.15").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("15 saniye geri")
            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44))
            }
            .accessibilityLabel(isPlaying ? "Duraklat" : "Oynat")
            Button(action: forward) {
                Image(systemName: "goforward.\(Int(skipSeconds))").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("\(Int(skipSeconds)) saniye ileri")
        }
    }

    private var rateMenu: some View {
        Menu {
            ForEach(rates, id: \.self) { r in
                let text = rateLabel?(r) ?? String(format: "%g×", r)
                Button { setRate(r) } label: {
                    if let currentRate, abs(r - currentRate) < 0.01 { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
        } label: {
            Text(rateText)
                .font(.caption.bold())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        }
        .accessibilityLabel("Oynatma hızı")
    }

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: min(1, max(0, progress.isFinite ? progress : 0)))
                .tint(.accentColor)
            // Tek satıra sığarsa: süre · düğmeler · hız. Sığmazsa (dar ekran, Düğme Şekilleri, büyük yazı) iki satır.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    // Ortak en az genişlik: karar her saniye değişen süre yazısına bağlı olmasın (düzen gidip gelmesin).
                    timeLabel.frame(minWidth: 58, maxWidth: .infinity, alignment: .leading)
                    buttons.fixedSize()
                    rateMenu.frame(minWidth: 58, maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 6) {
                    HStack {
                        timeLabel
                        Spacer(minLength: 8)
                        rateMenu
                    }
                    buttons.fixedSize()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(.bar)
    }
}

extension View {
    /// Sayfa genişliğini ekrana sabitler: bir alt görünüm sığmasa bile sayfanın geri kalanı taşmaz.
    func pinnedToScreenWidth() -> some View {
        containerRelativeFrame(.horizontal)
    }
}

/// Yalnızca Debug: `-ad=değer` biçimindeki başlatma argümanını okur (ekran taraması için sayfa/sekme açma).
enum DebugArg {
    static func value(_ name: String) -> String? {
        #if DEBUG
        let prefix = "-\(name)="
        return ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        #else
        return nil
        #endif
    }
}

extension View {
    /// Kaydırılan içeriği görünür genişliğe kilitler: içerik ekrandan genişleyemez, yatay kayamaz.
    func lockedToScrollWidth() -> some View {
        containerRelativeFrame(.horizontal)
    }
}

extension View {
    /// Liste satırını görünür genişlik eksi kenar boşluğuna kilitler. Tembel listede bir satır ara ara
    /// tam genişlikte ölçülünce liste genişleyip ortalanıyor, tüm kartlar 10 nokta sola kayıyordu.
    func rowWidthLocked(horizontalPadding: CGFloat) -> some View {
        containerRelativeFrame(.horizontal) { width, _ in max(0, width - horizontalPadding * 2) }
    }
}
