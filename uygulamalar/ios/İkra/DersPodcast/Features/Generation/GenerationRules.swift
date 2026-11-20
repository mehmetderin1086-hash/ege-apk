import Foundation

/// #1: sunucuya giden ayarlar. İstemci sınırları kırpar (zod aşılırsa 400); eski sunucuda (podcast2 yok)
/// seri ve yönergeler kullanıcı talimatının ardına eklenip toplam 500 karaktere kırpılır.
nonisolated enum ServerSettings {
    static let maxCustomInstructions = 500
    static let maxDirectives = 8, maxDirectiveLength = 800
    static let maxPreviousTitles = 30, maxTitleLength = 160
    static let maxKeyPoints = 12, maxKeyPointLength = 300

    /// Sınır sunucudaki gibi UTF-16 birimiyle ölçülür (`ServerText`).
    static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard trimmed.utf16.count > limit else { return trimmed }
        let cut = ServerText.prefix(trimmed, limit)
        // Kelime ortasında kesme (çok kısa kalmıyorsa).
        if let space = cut.lastIndex(of: " "), cut[..<space].utf16.count > limit * 3 / 4 {
            return String(cut[..<space])
        }
        return cut
    }

    static func prepare(_ settings: PodcastSettings, podcast2: Bool) -> PodcastSettings {
        var s = settings
        s.customInstructions = s.customInstructions.map { clip($0, maxCustomInstructions) }.flatMap { $0.isEmpty ? nil : $0 }
        s.directives = s.directives.map { clip($0, maxDirectiveLength) }.filter { !$0.isEmpty }.prefix(maxDirectives).map { $0 }
        if var series = s.series {
            series.name = clip(series.name, 120)
            series.previousTitles = series.previousTitles.suffix(maxPreviousTitles).map { clip($0, maxTitleLength) }
            series.previousKeyPoints = series.previousKeyPoints.suffix(maxKeyPoints).map { clip($0, maxKeyPointLength) }
            s.series = series
        }
        if var guest = s.guest {
            guest.name = ServerText.prefix(guest.name.trimmingCharacters(in: .whitespacesAndNewlines), 20)
            s.guest = guest.voice == s.hostA.voice || !s.engine.supportsGuest || guest.name.isEmpty ? nil : guest
        }
        guard !podcast2 else { return s }
        // Eski sunucu: yalnız customInstructions anlaşılır. Kullanıcının talimatı önce gelir (kaybolmasın).
        let notes = [s.customInstructions, s.series.map(seriesNote)].compactMap { $0 } + s.directives
        let merged = notes.filter { !$0.isEmpty }.joined(separator: " ")
        s.customInstructions = merged.isEmpty ? nil : clip(merged, maxCustomInstructions)
        s.directives = []
        s.series = nil
        s.guest = nil
        s.mixedFormat = false
        return s
    }

    /// Eski sunucu için seri notu (podcast2'de sunucu bunu `series`'ten kendisi kurar).
    static func seriesNote(_ series: SeriesContext) -> String {
        let previous = series.previousTitles.isEmpty ? "yok (bu ilk bölüm)"
            : series.previousTitles.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "; ")
        let first = series.index <= 1
        let last = series.index >= series.total
        return "Bu bölüm \"\(series.name)\" serisinin \(series.index)/\(series.total). bölümü. Önceki bölümler: \(previous). "
            + (first ? "Seriyi kısaca tanıt." : "Tanışmayı çok kısa tut, gerektiğinde önceki bölümlere atıf yap ve onları tekrar anlatma.")
            + (last ? " Bu serinin son bölümü; sonunda tüm seriyi kısaca toparla." : " Sonunda bir sonraki bölüme merak uyandıran kısa bir köprü kur.")
    }
}

/// Küresel tur/sahne indeksleri (`script.flatScenes` sırası = stitch sırası = `TimedTurn.id`).
nonisolated enum ScriptEditing {
    static func allTurns(_ script: PodcastScript) -> [ScriptTurn] {
        script.flatScenes.flatMap(\.scene.turns)
    }

    /// Küresel tur indeksi → (küresel sahne, sahne içi tur).
    static func locate(_ globalTurn: Int, in script: PodcastScript) -> (scene: Int, turn: Int)? {
        guard globalTurn >= 0 else { return nil }
        var offset = 0
        for (sceneIndex, item) in script.flatScenes.enumerated() {
            let count = item.scene.turns.count
            if globalTurn < offset + count { return (sceneIndex, globalTurn - offset) }
            offset += count
        }
        return nil
    }

    /// Küresel sahne → (konu, konu içi sahne).
    static func chapterAndScene(_ globalScene: Int, in script: PodcastScript) -> (chapter: Int, scene: Int)? {
        var offset = 0
        for (ci, chapter) in script.chapters.enumerated() {
            if globalScene < offset + chapter.scenes.count { return (ci, globalScene - offset) }
            offset += chapter.scenes.count
        }
        return nil
    }

    /// Düzeltilmiş turları senaryoya yazar (yalnız metin ve stil; konuşmacı korunur).
    static func applyFixes(_ fixes: [FixedTurn], to script: PodcastScript) -> PodcastScript {
        var result = script
        for fix in fixes {
            guard let (scene, turn) = locate(fix.index, in: script),
                  let (ci, si) = chapterAndScene(scene, in: script) else { continue }
            let text = fix.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            var chapters = result.chapters
            var turns = chapters[ci].scenes[si].turns
            turns[turn].text = text
            if let style = fix.style, !style.isEmpty { turns[turn].style = style }
            chapters[ci].scenes[si].turns = turns
            result.chapters = chapters
        }
        return result
    }

    /// Bir sahnenin turlarını değiştirir.
    static func replacingScene(_ globalScene: Int, with turns: [ScriptTurn], in script: PodcastScript) -> PodcastScript {
        guard let (ci, si) = chapterAndScene(globalScene, in: script), !turns.isEmpty else { return script }
        var result = script
        var chapters = result.chapters
        chapters[ci].scenes[si].turns = turns
        result.chapters = chapters
        return result
    }

    /// Küresel sahne → (konu başlığı, konu içi sıra): sahneyi düzenlenmiş başka bir senaryoya taşımak için.
    static func sceneKey(_ globalScene: Int, in script: PodcastScript) -> (title: String, scene: Int)? {
        guard let (ci, si) = chapterAndScene(globalScene, in: script) else { return nil }
        return (script.chapters[ci].title, si)
    }

    /// (konu başlığı, konu içi sıra) → küresel sahne; konu yoksa ya da sahne sayısı yetmiyorsa nil.
    static func globalScene(title: String, scene: Int, in script: PodcastScript) -> Int? {
        var offset = 0
        for chapter in script.chapters {
            if chapter.title == title { return chapter.scenes.indices.contains(scene) ? offset + scene : nil }
            offset += chapter.scenes.count
        }
        return nil
    }

    /// "Cilala" sonucu: sahne, istekten önce alınan (konu başlığı, konu içi sıra) anahtarıyla yeniden bulunur.
    /// Konu kaybolduysa ya da sahne bu arada değiştiyse sonuç atılır (nil); küresel indeks kaymış olabilir.
    static func applyingPolish(_ turns: [ScriptTurn], key: (title: String, scene: Int), original: ScriptScene,
                               in script: PodcastScript) -> (script: PodcastScript, scene: Int)? {
        guard !turns.isEmpty, let index = globalScene(title: key.title, scene: key.scene, in: script),
              script.flatScenes[safe: index]?.scene == original else { return nil }
        var result = replacingScene(index, with: turns, in: script)
        if var quality = result.quality {
            quality.weakScenes.removeAll { $0.scene == index }
            result.quality = quality
        }
        return (result, index)
    }

    /// #2: yeniden denenen konunun sunucudaki yeni senaryodaki karşılığı. Sunucu konuyu yine yazamadıysa
    /// (`chapterErrors` aynı plan indeksini taşıyorsa) nil. Önce başlıkla eşlenir; başlık değiştiyse plan sırası,
    /// yazılamayan öbür konular düşülerek senaryo sırasına çevrilir (`fresh` yalnız yazılabilmiş konuları içerir).
    /// Bu yolla bulunan konu yerelde zaten varsa (yanlış eşleşme: yerel düzenlemeleri ezerdi) kullanılmaz.
    static func retriedChapter(for error: ChapterError, in fresh: PodcastScript, local: PodcastScript) -> ScriptChapter? {
        let errors = fresh.quality?.chapterErrors ?? []
        guard !errors.contains(where: { $0.index == error.index }) else { return nil }
        if let byTitle = fresh.chapters.first(where: { $0.title == error.title }) { return byTitle }
        let position = error.index - errors.filter { $0.index < error.index }.count
        guard let candidate = fresh.chapters[safe: position],
              !local.chapters.contains(where: { $0.title == candidate.title }) else { return nil }
        return candidate
    }

    /// Düzeltilen turların sorunları `fixedAt` ile işaretlenir; öbürleri olduğu gibi kalır (tur sayısı değişmediği
    /// için indeksleri geçerlidir).
    static func markingFixed(_ issues: [ScriptIssue]?, turns: Set<Int>, at date: Date = .now) -> [ScriptIssue]? {
        issues?.map { issue in
            var i = issue
            if i.fixedAt == nil, turns.contains(i.index) { i.fixedAt = date }
            return i
        }
    }

    /// Sunucunun kelime sayımına yakın (harf/rakam dizileri).
    static func wordCount(_ script: PodcastScript) -> Int {
        allTurns(script).reduce(0) { $0 + $1.text.split { !($0.isLetter || $0.isNumber) }.count }
    }

    /// Kelime sayısı ve tahmini süre yerel senaryodan yeniden hesaplanır (sunucunun dakika/kelime oranı korunur).
    static func rescaled(_ script: PodcastScript) -> PodcastScript {
        guard var quality = script.quality else { return script }
        let words = wordCount(script)
        guard words != quality.words else { return script }
        if quality.words > 0 {
            quality.estimatedMinutes = (quality.estimatedMinutes * Double(words) / Double(quality.words) * 10).rounded() / 10
        }
        quality.words = words
        var result = script
        result.quality = quality
        return result
    }

    /// #2: sunucuda yeniden yazılan konu, önizlemede düzenlenmiş olabilecek yerel senaryoya yerleşir.
    /// Sunucudan yalnız `chapterErrors` ile yeni konunun zayıf sahneleri alınır (sunucu düzeninin küresel indeksleri
    /// yerelle uyuşmaz); yerel zayıf sahneler konu başlığıyla yeniden eşlenir; kelime ve süre yerelden hesaplanır.
    static func mergeRetriedChapter(_ chapter: ScriptChapter, serverIndex: Int, into local: PodcastScript,
                                    fresh: PodcastScript) -> PodcastScript {
        let localWeak = (local.quality?.weakScenes ?? []).compactMap { w in sceneKey(w.scene, in: local).map { (key: $0, reasons: w.reasons) } }
        var script = local
        var chapters = script.chapters
        if let existing = chapters.firstIndex(where: { $0.title == chapter.title }) {
            chapters[existing] = chapter
        } else {
            chapters.insert(chapter, at: min(max(serverIndex, 0), chapters.count))
        }
        script.chapters = chapters
        var weak = localWeak.filter { $0.key.title != chapter.title }.compactMap { item in
            globalScene(title: item.key.title, scene: item.key.scene, in: script).map { WeakScene(scene: $0, reasons: item.reasons) }
        }
        for w in fresh.quality?.weakScenes ?? [] {
            guard let key = sceneKey(w.scene, in: fresh), key.title == chapter.title,
                  let index = globalScene(title: key.title, scene: key.scene, in: script) else { continue }
            weak.append(WeakScene(scene: index, reasons: w.reasons))
        }
        if var quality = local.quality ?? fresh.quality {
            quality.weakScenes = weak.sorted { $0.scene < $1.scene }
            quality.chapterErrors = fresh.quality?.chapterErrors ?? []
            script.quality = quality
        }
        return rescaled(script)
    }

    /// Senaryonun dayandığı kaynak sayfaları (konu ve tur etiketleri; 1 tabanlı, sıralı).
    static func referencedPages(_ script: PodcastScript) -> [Int] {
        var pages = Set(script.chapters.flatMap { $0.sourcePages ?? [] })
        for turn in allTurns(script) { if let p = turn.sourcePage { pages.insert(p) } }
        return pages.filter { $0 > 0 }.sorted()
    }
}

/// #47: tahmini maliyet (USD). Fiyatlar `CostEstimate` ile aynı varsayımlar.
nonisolated enum GenerationCost {
    /// Yalnız Chirp HD sesi sayılır ("Claude + Chirp"te de ses Chirp'tir); senaryo ve okunuş hazırlığı için Claude ek ücret sayılmaz.
    static func estimate(engine: SpeechEngine, characters: Int) -> Double {
        let voice = engine.voicedBy == .chirp ? Double(characters) / 1_000_000 * 30 : 0
        return (voice * 10_000).rounded() / 10_000
    }
}

/// #3: bölüm oluşmadan önce de geçerli üretim aşamaları ve oranları.
nonisolated enum GenerationPhaseMath {
    /// Bütün üretim boyunca oran: hazırlık → yükleme → senaryo → seslendirme → birleştirme.
    static func overall(script: ScriptProgress?, uploading: Bool = false, voicedDone: Int? = nil, voicedTotal: Int? = nil, mixing: Bool = false) -> Double {
        if mixing { return 0.97 }
        if let total = voicedTotal, total > 0 { return 0.45 + 0.5 * Double(min(voicedDone ?? 0, total)) / Double(total) }
        if let script { return 0.05 + 0.40 * script.fraction }
        return uploading ? 0.04 : 0.02
    }
}
