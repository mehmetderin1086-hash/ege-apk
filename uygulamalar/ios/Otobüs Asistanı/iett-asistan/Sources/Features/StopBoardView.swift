import SwiftUI

/// Akıllı durak panosunun verisi: durağa uğrayan hatların tarifeden gelen sıradaki geçişi (kotasız), en yakın birkaç hat için canlı konum süresi (kotalı).
@Observable @MainActor final class BoardModel {
    var rows: [BoardRow] = []
    var notices: [String] = []
    var updated: Date?
    var loading = true
    var liveCount: Int { rows.filter(\.live).count }

    func refresh(stop: Durak, model: AppModel, extraLines: [String] = []) async {
        let now = Date()
        if model.isDemo { rows = Self.demoRows(now: now); notices = ["500T: Maç nedeniyle güzergâh değişikliği olabilir.", "14M: Kadıköy yönünde yoğunluk var."]; updated = now; loading = false; return }
        var seen = Set<String>(), entries: [RouteStore.Entry] = []
        for entry in await model.linesAtStop(stop.code) where seen.insert(entry.line + entry.direction).inserted { entries.append(entry) }
        entries = Array(entries.prefix(24))
        let day = IETTDates.dayType(now)
        var scheduled: [BoardRow] = []
        for entry in entries {
            // Sefer saatleri diskte 12 saat saklanır; ilk açılışta hat başına bir istek (kotasız servis).
            let trips = await model.timetable(line: entry.line)
            let times = Timetable.times(trips, dayType: day, direction: entry.direction)
            let route = await model.route(entry.line)
            var offset = 0
            if let route, let stops = route.stops[entry.direction], let index = route.stopIndex(code: stop.code, direction: entry.direction), let hat = model.line(entry.line) {
                let geometry = RouteGeometry(stops: stops)
                offset = Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length) ?? 0
            }
            guard let next = Timetable.upcoming(times, offset: offset, nowMinutes: Timetable.nowMinutes(now), count: 1).first else { continue }
            let arrivalDate = BoardFormat.date(minutes: next, on: now)
            scheduled.append(BoardRow(line: entry.line, direction: entry.direction, destination: route?.destination(entry.direction) ?? "", arrival: arrivalDate, live: false, atStop: false,
                                      planned: arrivalDate, origin: BoardFormat.date(minutes: next - offset, on: now)))
        }
        // Canlı: yalnız en yakın 3 hat (kota). Bunlar kotadan pay alır.
        let candidates = BoardFormat.liveCandidates(scheduled, now: now)
        model.boardLines = Set(candidates.map(\.line))
        var live: [BoardRow] = []
        for candidate in candidates {
            let buses = await model.buses(line: candidate.line)
            let etas = await model.etas(line: candidate.line, buses: buses.filter { $0.direction == candidate.direction }, stop: stop.coordinate, stopCode: stop.code)
            if let eta = etas.first {
                live.append(BoardRow(line: candidate.line, direction: candidate.direction, destination: candidate.destination, arrival: eta.asOf.addingTimeInterval(eta.minutes * 60), live: true, atStop: eta.state == .atStop))
            }
        }
        // Ek hatlar: güzergâh verisinde bu durak yok ama bazı seferleri uğruyor (kullanıcı ekler). Tarife dakikası bilinmez → yalnız canlı, kuş uçuşu süre.
        for line in extraLines.prefix(2) where !entries.contains(where: { $0.line == line }) {
            let buses = await model.buses(line: line)
            let route = await model.route(line)
            for eta in model.tracker.etas(buses: buses, stop: stop.coordinate, stopCode: stop.code).filter({ $0.minutes <= 60 }).prefix(2) {
                let direction = buses.first { $0.id == eta.id }?.direction ?? "G"
                live.append(BoardRow(line: line, direction: direction + "+" + eta.id, destination: route?.destination(direction) ?? "", arrival: eta.asOf.addingTimeInterval(eta.minutes * 60), live: true, atStop: eta.state == .atStop))
            }
        }
        rows = BoardFormat.merge(scheduled: scheduled, live: live, now: now)
        // Duyurular: bu duraktan geçen hatlar (kotasız servis).
        let lines = Set(entries.map(\.line))
        notices = ((try? await model.notices()) ?? []).filter { lines.contains($0.line) }.prefix(6).map { "\($0.line): \($0.message)" }
        updated = now; loading = false
    }

    static func demoRows(now: Date) -> [BoardRow] {
        let items: [(String, String, String, Double, Bool, Bool)] = [("500T", "G", "4.LEVENT METRO", 20, true, true), ("14M", "G", "KADIKÖY", 130, true, false), ("15F", "D", "BEYKOZ", 4 * 60 + 20, true, false),
                                                                      ("E-10", "G", "ÜSKÜDAR", 9 * 60, false, false), ("138", "D", "ÖMERLİ", 14 * 60, false, false), ("137", "G", "RİVA", 22 * 60, false, false),
                                                                      ("20D", "G", "MECİDİYEKÖY", 37 * 60, false, false), ("11A", "D", "ALTUNİZADE METROBÜS", 82 * 60, false, false), ("3", "G", "KADIKÖY", 95 * 60, false, false)]
        return items.enumerated().map { index, item in
            let arrival = now.addingTimeInterval(item.3)
            // Canlı satırlara örnek sapma: ikincisi 4 dk geç, üçüncüsü 4 dk erken, ilki zamanında.
            let shift: [Double] = [0, 4 * 60, -4 * 60]
            let planned = item.4 ? arrival.addingTimeInterval(-(index < shift.count ? shift[index] : 0)) : arrival
            return BoardRow(line: item.0, direction: item.1, destination: item.2, arrival: arrival, live: item.4, atStop: item.5, planned: planned, origin: planned.addingTimeInterval(-18 * 60))
        }
    }
}

private enum LED {
    static let background = Color(red: 0.02, green: 0.025, blue: 0.04)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.12)
    static let dim = Color(red: 1.0, green: 0.90, blue: 0.62)          // ikincil yazı: açık krem
    static let line = Color(red: 0.75, green: 0.60, blue: 0.20)        // ayraç çizgileri
    static let green = Color(red: 0.45, green: 1.0, blue: 0.62)
    static let late = Color(red: 1.0, green: 0.50, blue: 0.42)
    static let early = Color(red: 0.45, green: 0.95, blue: 1.0)
}

/// Akıllı durak ekranı: koyu LED panel, hat etiketleri, kalan süre geri sayımı, kayan duyuru bandı, otomatik sayfa dönüşü.
struct StopBoardView: View {
    var kiosk = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("board.stop") private var stopCode = 0
    /// Arka plan: 0 siyah, 1 koyu gri, 2 gri, 3 çelik gri.
    @AppStorage("board.bg") private var background = 1
    /// Ek hatlar: "durakKodu|HAT" girdileri boşlukla ayrılır.
    @AppStorage("board.extra") private var extraRaw = ""
    @State private var addingLine = false
    @State private var newLine = ""
    @State private var board = BoardModel()
    @State private var page = 0
    @State private var picking = false
    @State private var kioskOn = false
    @State private var controls = true
    private let rowsPerPage = 6
    static let backgrounds: [(name: String, color: Color)] = [
        ("Siyah", Color(red: 0.02, green: 0.025, blue: 0.04)), ("Koyu gri", Color(red: 0.17, green: 0.18, blue: 0.20)),
        ("Gri", Color(red: 0.27, green: 0.28, blue: 0.30)), ("Çelik gri", Color(red: 0.31, green: 0.34, blue: 0.39)),
    ]

    private var extraLines: [String] { extraRaw.split(separator: " ").compactMap { $0.hasPrefix("\(stopCode)|") ? String($0.dropFirst("\(stopCode)|".count)) : nil } }
    private func setExtra(_ lines: [String]) {
        let others = extraRaw.split(separator: " ").filter { !$0.hasPrefix("\(stopCode)|") }.map(String.init)
        extraRaw = (others + lines.map { "\(stopCode)|\($0)" }).joined(separator: " ")
    }

    private var stop: Durak? { stopCode != 0 ? model.stop(code: stopCode) : nil }

    var body: some View {
        ZStack {
            Self.backgrounds[min(max(background, 0), 3)].color.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                arrivalsTicker
                columnHeader
                rowsView
                Spacer(minLength: 0)
                ticker
                footer
            }
            .padding(.horizontal, 16).padding(.top, kiosk ? 8 : 0)
            if kiosk && controls {
                VStack { HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(LED.dim) }.padding() }; Spacer() }
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(kiosk ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !kiosk {
                ToolbarItem(placement: .topBarLeading) { Button { picking = true } label: { Label("Durak seç", systemImage: "mappin.and.ellipse") } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Arka plan", selection: $background) { ForEach(Array(Self.backgrounds.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) } }
                    } label: { Label("Arka plan", systemImage: "paintpalette.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { newLine = ""; addingLine = true } label: { Label("Hat ekle", systemImage: "plus") }
                        ForEach(extraLines, id: \.self) { line in Button(role: .destructive) { setExtra(extraLines.filter { $0 != line }) } label: { Label("\(line) kaldır", systemImage: "minus.circle") } }
                    } label: { Label("Ek hatlar", systemImage: "plus.circle.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button { kioskOn = true } label: { Label("Tam ekran", systemImage: "arrow.up.left.and.arrow.down.right") } }
                ToolbarItem(placement: .topBarTrailing) { if let stop { ShareIconButton(label: "Panoyu paylaş") { ShareBuilder.board(stop, rows: board.rows) } } }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .statusBarHidden(kiosk)
        .persistentSystemOverlays(kiosk ? .hidden : .automatic)
        .onTapGesture { if kiosk { withAnimation { controls.toggle() } } }
        .alert("Hat ekle", isPresented: $addingLine) {
            TextField("Hat kodu (ör. 11R)", text: $newLine).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button("Ekle") {
                let code = newLine.trimmingCharacters(in: .whitespaces).uppercased()
                if !code.isEmpty, model.line(code) != nil, !extraLines.contains(code) { setExtra(extraLines + [code]) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Güzergâh verisinde bu durağı olmayan ama bazı seferleri uğrayan hat. Yalnız canlı araç yaklaşınca görünür.") }
        .sheet(isPresented: $picking) { BoardStopPicker { stopCode = $0.code; picking = false } }
        .fullScreenCover(isPresented: $kioskOn) { StopBoardView(kiosk: true) }
        .onAppear { if kiosk { UIApplication.shared.isIdleTimerDisabled = true } }
        .onDisappear { if kiosk { UIApplication.shared.isIdleTimerDisabled = false } }
        .task(id: stopCode) { await chooseDefaultStop() }
        .task {
            #if DEBUG
            if !kiosk, ProcessInfo.processInfo.arguments.contains("-kiosk") { try? await Task.sleep(for: .milliseconds(1200)); kioskOn = true }
            #endif
        }
        .task(id: "\(stopCode)\(kioskOn)\(extraRaw)") {
            guard !kioskOn || kiosk, let stop = stop else { return }
            while !Task.isCancelled {
                await board.refresh(stop: stop, model: model, extraLines: extraLines)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task {
            // Sayfa dönüşü: 7'den fazla satır varsa 6 sn'de bir kayar.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                let count = BoardFormat.pages(board.rows, size: rowsPerPage).count
                if count > 1 { withAnimation(.easeInOut(duration: 0.6)) { page = (page + 1) % count } } else { page = 0 }
            }
        }
        .task(id: controls) { if kiosk && controls { try? await Task.sleep(for: .seconds(4)); withAnimation { controls = false } } }
    }

    private func chooseDefaultStop() async {
        guard stopCode == 0 else { return }
        if let first = model.favoriteStops.first { stopCode = first; return }
        if let first = model.favorites.first { stopCode = first.stopCode; return }
        if let here = model.location?.coordinate, let nearest = model.nearestStops(to: here, limit: 1, within: 2000).first { stopCode = nearest.stop.code; return }
        if model.isDemo { stopCode = 1 }
    }

    // MARK: Parçalar
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BoardFormat.upper(stop?.name ?? "DURAK SEÇ")).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(LED.amber).lineLimit(2).minimumScaleFactor(0.6)
                Text([stop.map { "NO \($0.code)" }, stop?.district].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(LED.dim)
                if let direction = stop?.direction, !direction.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: fold(direction).contains("son durak") ? "flag.checkered" : "arrow.right.circle.fill")
                        Text(fold(direction).contains("son durak") ? "SON DURAK" : "YÖN: \(BoardFormat.upper(direction))")
                    }.font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(LED.amber)
                }
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(context.date, format: .dateTime.hour().minute().second().locale(Locale(identifier: "tr_TR"))).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(LED.amber)
                    Text(BoardFormat.upper(context.date.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "tr_TR"))))).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(LED.dim)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(LED.line.opacity(0.7)).frame(height: 1) }
    }

    /// Üstte kayan şerit: sıradaki araçlar, kalan süre ve varış saatiyle (15 sn'de bir tazelenir).
    @ViewBuilder private var arrivalsTicker: some View {
        if !board.rows.isEmpty {
            HStack(spacing: 8) {
                Text("SIRADAKİLER").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 4).background(LED.amber, in: .rect(cornerRadius: 5))
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    MarqueeText(text: BoardFormat.ticker(board.rows, now: context.date)).foregroundStyle(LED.amber)
                }
            }
            .padding(.vertical, 7).overlay(alignment: .bottom) { Rectangle().fill(LED.line.opacity(0.6)).frame(height: 1) }
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("HAT").frame(width: 92, alignment: .leading)
            Text("GÜZERGÂH")
            Spacer()
            Text("SÜRE")
        }
        .font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(LED.dim).padding(.vertical, 8)
    }

    private var rowsView: some View {
        let pages = BoardFormat.pages(board.rows, size: rowsPerPage)
        let current = pages.isEmpty ? [] : pages[min(page, pages.count - 1)]
        return Group {
            if board.loading && board.rows.isEmpty {
                VStack(spacing: 12) { ProgressView().tint(LED.amber); Text("SEFER BİLGİSİ ALINIYOR…").font(.callout.monospaced()).foregroundStyle(LED.amber) }.frame(maxWidth: .infinity).padding(.top, 60)
            } else if board.rows.isEmpty {
                Text(stop == nil ? "SOL ÜSTTEN DURAK SEÇ" : "YAKINDA SEFER YOK").font(.title3.monospaced().weight(.bold)).foregroundStyle(LED.amber).frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        ForEach(current) { row in boardRow(row, now: context.date) }
                    }
                    .id(page)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
                if pages.count > 1 {
                    HStack(spacing: 6) { ForEach(0..<pages.count, id: \.self) { Circle().fill($0 == page ? LED.amber : LED.line.opacity(0.6)).frame(width: 9, height: 9) } }.padding(.top, 8)
                }
            }
        }
    }

    private func boardRow(_ row: BoardRow, now: Date) -> some View {
        let text = BoardFormat.text(row, now: now)
        let urgent = row.arrival.timeIntervalSince(now) <= 45 || text == "DURAKTA"
        let blink = Int(now.timeIntervalSinceReferenceDate) % 2 == 0
        return HStack(spacing: 12) {
            Text(row.line).font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(.black)
                .frame(width: 92, height: 46).background(LED.amber, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 0) {
                Text(BoardFormat.upper(row.destination)).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(LED.amber).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 4) { Image(systemName: row.live ? "dot.radiowaves.left.and.right" : "clock").font(.system(size: 13)); Text(row.live ? "CANLI" : "TARİFE").font(.system(size: 13, weight: .bold, design: .monospaced)) }.foregroundStyle(row.live ? LED.green : LED.dim)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(text).font(.system(size: urgent ? 24 : 32, weight: .heavy, design: .monospaced)).foregroundStyle(row.live ? LED.green : LED.amber)
                    .opacity(urgent && !blink ? 0.6 : 1).contentTransition(.numericText())
                let tone = BoardFormat.punctuality(row)?.tone
                ForEach(Array(BoardFormat.detailLines(row, now: now).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 14, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(tone == .late ? LED.late : tone == .early ? LED.early : tone == .good ? LED.green : LED.dim)
                }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(Color.white.opacity(background == 0 ? 0.04 : 0.08), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.line), \(row.destination), \(text), \(row.live ? "canlı" : "tarife")")
    }

    private var ticker: some View {
        Group {
            if !board.notices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.black).padding(6).background(LED.amber, in: .circle)
                    MarqueeText(text: BoardFormat.upper(board.notices.joined(separator: "     ●     "))).foregroundStyle(LED.amber)
                }
                .padding(.vertical, 6).overlay(alignment: .top) { Rectangle().fill(LED.line.opacity(0.7)).frame(height: 1) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("CANLI \(board.liveCount)").foregroundStyle(LED.green)
            Text("TARİFE \(board.rows.count - board.liveCount)").foregroundStyle(LED.amber)
            if board.liveCount == 0 { Text(model.liveError == nil ? "ARAÇ YOK" : "SERVİS SINIRLI").foregroundStyle(LED.late) }
            Spacer()
            if let updated = board.updated { Text("GÜNCELLEME \(updated.formatted(date: .omitted, time: .shortened))") }
            Text("KOTA \(model.quotaRemaining)")
        }
        .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(LED.dim).padding(.vertical, 8)
    }
}

/// Kayan yazı bandı (duyurular).
struct MarqueeText: View {
    let text: String
    @State private var width: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let total = width + geo.size.width
                let x = geo.size.width - (context.date.timeIntervalSinceReferenceDate * 55).truncatingRemainder(dividingBy: max(total, 1))
                Text(text).font(.system(size: 22, weight: .bold, design: .monospaced)).fixedSize()
                    .background(GeometryReader { Color.clear.preference(key: MarqueeWidthKey.self, value: $0.size.width) })
                    .offset(x: x)
            }
        }
        .onPreferenceChange(MarqueeWidthKey.self) { width = $0 }
        .frame(height: 32).clipped()
    }
}
private struct MarqueeWidthKey: PreferenceKey { static let defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) } }

/// Pano durağı seçici: takip ettiğin duraklar, yakınındakiler, arama.
struct BoardStopPicker: View {
    let onPick: (Durak) -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    let starred = model.favoriteStopList
                    if !starred.isEmpty { Section("Favori duraklarım") { ForEach(starred) { row($0) } } }
                    let mine = Array(Set(model.favorites.map(\.stopCode))).compactMap { model.stop(code: $0) }.filter { !model.isFavoriteStop($0.code) }
                    if !mine.isEmpty { Section("Takip ettiğin duraklar") { ForEach(mine) { row($0) } } }
                    if let here = model.location?.coordinate { Section("Yakınımda") { ForEach(model.nearestStops(to: here, limit: 12, within: 1500), id: \.stop.id) { row($0.stop) } } }
                } else {
                    ForEach(model.searchStops(query, near: model.location?.coordinate, limit: 30)) { row($0) }
                }
            }
            .searchable(text: $query, prompt: "Durak ara").navigationTitle("Pano durağı").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
    private func row(_ stop: Durak) -> some View {
        Button { onPick(stop) } label: {
            VStack(alignment: .leading, spacing: 4) { Text(stop.name).font(.title3.weight(.bold)); if !stop.district.isEmpty { Text(stop.district).font(.subheadline).foregroundStyle(.secondary) }; DirectionTag(text: stop.direction, large: false) }
        }.buttonStyle(.plain)
    }
}
