import XCTest

/// Erişilebilirlik denetimleri için ortak kaydırma yardımcısı.
/// Sekme çubuğunun arkasında kalan satır erişilebilirlik ağacında yine "ekranda" sayılır;
/// bu yüzden yalnız `isHittable` beklemek yetmez, satırın tümü gerçek görünür alana getirilir.
enum GorunurAlan {
    enum Sonuc: Equatable {
        /// Satırın tümü görünür alanda ve dokunulabilir.
        case tumuGorunur
        /// Satır görünür alandan uzun; üst kenarı görünür alanın üstüne hizalandı.
        case ustHizali
        /// Satır kaydırmayla görünür alana getirilemedi.
        case getirilemedi
    }

    /// Sekme içeriğinin gerçekten çizildiği bölge: gezinme çubuğu ve arama alanının altından,
    /// içeriğin kırpıldığı kenara (sekme çubuğunun 8 pt üstü, SekmeIcerigiAlani) kadar.
    static func icerikBolgesi(_ app: XCUIApplication) -> CGRect {
        let window = app.frame
        let navigation = app.navigationBars.firstMatch
        let bar = app.tabBars.firstMatch
        var top = navigation.exists ? max(window.minY, navigation.frame.maxY) : window.minY
        let search = app.searchFields.firstMatch
        if search.exists, search.frame.intersects(window), search.frame.maxY < bar.frame.minY {
            top = max(top, search.frame.maxY)
        }
        let bottom = bar.exists ? min(window.maxY, bar.frame.minY - 8) : window.maxY
        return CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
    }

    /// Satırların getirileceği bölge: içerik bölgesinin her kenarından 4 pt içeride.
    static func sinirlar(_ app: XCUIApplication) -> CGRect {
        icerikBolgesi(app).insetBy(dx: 0, dy: 4)
    }

    /// Kontrast denetimi metni ekran pikselleriyle ölçer. Sekme içeriği kenarında kırpılan ya da
    /// kaydırılınca gezinme/arama çubuğunun altına giren metin tam çizilmediği için ölçüm o metnin
    /// kontrastını değil boşluğu veya sistem çubuğunu görür. Yalnız bu durumdaki kontrast bulgusu
    /// yok sayılır; şu koşulların hepsi gerekir:
    /// - öğe bilinir ve bir metindir (`staticText`); düğme, arama alanı ve görsel hiç muaf değildir,
    /// - metin kaydırılan sekme içeriğindedir (scrollView, collectionView ya da table),
    /// - aynı etiketli bir öğe gezinme, sekme ya da araç çubuğunda yoktur: çubuk öğeleri konumları
    ///   gereği hep içerik bölgesinin dışında kalır, bu yüzden konuma bakılarak muaf tutulamaz,
    /// - metin `korunan` çerçeveyle (denetlenen hedef satır) kesişmez,
    /// - metnin çerçevesi içerik bölgesinin dışına taşar.
    /// Bu bir kapsam açığıdır: kenarda kalan metnin kontrastı o ekranın denetiminde ölçülmemiş olur.
    static func kenardaKalanMetinKontrasti(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication,
                                           korunan: CGRect? = nil) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element, element.exists,
              element.elementType == .staticText, !element.label.isEmpty else { return false }
        let frame = element.frame
        // Yalnız kenarları değen komşu satır hedefe ait sayılmaz.
        if let korunan, case let ortak = frame.intersection(korunan), !ortak.isNull, ortak.width > 1, ortak.height > 1 {
            return false
        }
        let bolge = icerikBolgesi(app)
        guard frame.minY < bolge.minY - 0.5 || frame.maxY > bolge.maxY + 0.5 else { return false }
        let ayniEtiket = NSPredicate(format: "label == %@", element.label)
        let cubukta = [app.navigationBars, app.tabBars, app.toolbars].contains {
            $0.descendants(matching: .any).matching(ayniEtiket).firstMatch.exists
        }
        let icerikte = [app.scrollViews, app.collectionViews, app.tables].contains {
            $0.descendants(matching: .staticText).matching(ayniEtiket).firstMatch.exists
        }
        guard !cubukta, icerikte else { return false }
        print("AUDIT_KENARDA|\(element.label)|\(frame)|bolge=\(bolge)")
        return true
    }

    /// Satırı tümüyle görünür alana kaydırır. Satır görünür alandan uzunsa üst kenarını
    /// görünür alanın üstüne hizalar; denetim satırın görünen kısmında yine çalıştırılabilir.
    static func satiriGoster(_ row: XCUIElement, in app: XCUIApplication, etiket: String = "ATTRIBUTION") -> Sonuc {
        for _ in 0..<16 {
            let region = sinirlar(app)
            guard row.exists else {
                surukle(app, region: region, mesafe: -region.height * 0.35)
                continue
            }
            let rect = row.frame
            if rect.width > 0, rect.height > 0, region.contains(rect), row.isHittable { return .tumuGorunur }
            if rect.height > region.height {
                print("\(etiket)_ROW_TOO_TALL|\(rect)|viewport=\(region)")
                return ustKenariHizala(row, in: app)
            }
            // Satır üstte kesiliyorsa içerik aşağı, altta kesiliyorsa yukarı kaydırılır;
            // en az 40 pt sürüklenir, yoksa dokunma eşiği kaydırmayı yutar.
            let mesafe = rect.minY < region.minY
                ? min(max(region.minY - rect.minY + 12, 40), region.height * 0.7)
                : -min(max(rect.maxY - region.maxY + 12, 40), region.height * 0.7)
            surukle(app, region: region, mesafe: mesafe)
        }
        return .getirilemedi
    }

    /// Görünür alandan uzun satırın üst kenarını görünür alanın üstüne (en çok 40 pt aşağısına) getirir.
    private static func ustKenariHizala(_ row: XCUIElement, in app: XCUIApplication) -> Sonuc {
        for _ in 0..<10 {
            let region = sinirlar(app)
            let fark = row.frame.minY - region.minY
            if fark >= 0, fark <= 40 { return .ustHizali }
            // Fark pozitifse satır aşağıda kalmıştır; içerik yukarı kaydırılır. Dokunma eşiği
            // için 15 pt pay eklenir ve en az 25 pt sürüklenir.
            let hedef = fark < 0 ? -fark + 15 : -(fark - 15)
            let mesafe = (hedef < 0 ? -1 : 1) * min(max(abs(hedef), 25), region.height * 0.7)
            surukle(app, region: region, mesafe: mesafe)
        }
        return .getirilemedi
    }

    /// Görünür alanın ortasında yavaş sürükleme; sonda beklenerek savrulma engellenir.
    /// Pozitif mesafe içeriği aşağı (öncekine), negatif mesafe yukarı (sonrakine) taşır.
    private static func surukle(_ app: XCUIApplication, region: CGRect, mesafe: CGFloat) {
        let yarim = abs(mesafe) / 2
        let from = CGPoint(x: region.midX, y: region.midY - (mesafe > 0 ? yarim : -yarim))
        let to = CGPoint(x: region.midX, y: region.midY + (mesafe > 0 ? yarim : -yarim))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
    }
}
