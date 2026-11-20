import KagitKit
import PDFKit
import SwiftUI

/// Belge ekranı “Öğretmen” kipi: ✓ ✗ ½ ? damgaları, puan düğmeleri, hazır yorumlar, canlı toplam, öğrenci adlandırma.
struct OgretmenCubugu: View {
    let oturum: BelgeOturumu

    enum Arac: Equatable {
        case yok
        case damga(OgretmenDamga.Tur)
        case puan(Double)
        case yorum(String)
    }

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var arac: Arac = .yok
    @State private var eksi = false
    @State private var yerlesen = 0
    @State private var ozelAcik = false
    @State private var ozelMetin = ""
    @State private var ogrenciAcik = false

    private var toplam: Double {
        _ = yerlesen; _ = oturum.geriAlinabilir; _ = oturum.yinelenebilir
        guard let b = oturum.belge else { return 0 }
        return PuanOkuyucu.toplam(b)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Toplam: \(BicimYardimci.sayi(toplam))", systemImage: "sum")
                    .font(.headline.monospacedDigit()).foregroundStyle(.red)
                Spacer()
                Button { toplamiYaz() } label: { Label("İlk sayfaya yaz", systemImage: "square.and.pencil") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { ogrenciAcik = true } label: { Label("Öğrenci", systemImage: "person.crop.circle.badge.checkmark") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OgretmenDamga.Tur.allCases) { t in
                        secim(arac == .damga(t)) { arac = arac == .damga(t) ? .yok : .damga(t) } icerik: { damgaSimgesi(t) }
                    }
                    Divider().frame(height: 24)
                    secim(eksi) { eksi.toggle() } icerik: { Text("−").font(.title3.bold()) }
                    ForEach([1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10], id: \.self) { p in
                        let d = eksi ? -p : p
                        secim(arac == .puan(d)) { arac = arac == .puan(d) ? .yok : .puan(d) } icerik: {
                            Text(eksi ? "−\(Int(p))" : "+\(Int(p))").font(.callout.bold().monospacedDigit())
                        }
                    }
                    secim(arac == .puan(0.5) || arac == .puan(-0.5)) { let d = eksi ? -0.5 : 0.5; arac = arac == .puan(d) ? .yok : .puan(d) } icerik: {
                        Text(eksi ? "−½" : "+½").font(.callout.bold())
                    }
                    secim(false) { ozelAcik = true } icerik: { Text("Özel").font(.callout) }
                }
                .padding(.horizontal, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(depo.yorumlar, id: \.self) { y in
                        Button { arac = arac == .yorum(y) ? .yok : .yorum(y) } label: {
                            Text(y).font(.callout).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(arac == .yorum(y) ? Color.red.opacity(0.2) : Color(.secondarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            Text(ipucu).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .onAppear { baglan() }
        .onChange(of: arac) { _, _ in baglan() }
        .onDisappear { oturum.dokunusIsleyici = nil }
        .alert("Özel puan", isPresented: $ozelAcik) {
            TextField("Örn. 2,5 ya da -1", text: $ozelMetin).keyboardType(.numbersAndPunctuation)
            Button("Seç") {
                if let d = Double(ozelMetin.replacingOccurrences(of: ",", with: ".")) { arac = .puan(d) }
                ozelMetin = ""
            }
            Button("Vazgeç", role: .cancel) { ozelMetin = "" }
        }
        .sheet(isPresented: $ogrenciAcik) { OgrenciSecimi(oturum: oturum) }
    }

    private var ipucu: String {
        switch arac {
        case .yok: "Bir damga, puan ya da yorum seçin; sonra kâğıda dokunun."
        case .damga(let t): "“\(t.ad)” damgası için kâğıda dokunun."
        case .puan(let d): "\(d >= 0 ? "+" : "−")\(BicimYardimci.sayi(abs(d))) puanı için kâğıda dokunun."
        case .yorum(let y): "“\(y)” için kâğıda dokunun."
        }
    }

    @ViewBuilder private func damgaSimgesi(_ t: OgretmenDamga.Tur) -> some View {
        switch t {
        case .dogru: Image(systemName: "checkmark").font(.title3.bold()).foregroundStyle(.green)
        case .yanlis: Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.red)
        case .yarim: Text("½").font(.title3.bold()).foregroundStyle(.orange)
        case .soru: Text("?").font(.title3.bold()).foregroundStyle(.orange)
        }
    }

    private func secim<I: View>(_ secili: Bool, _ eylem: @escaping () -> Void, @ViewBuilder icerik: () -> I) -> some View {
        Button(action: eylem) {
            icerik().frame(minWidth: 38, minHeight: 34).padding(.horizontal, 6)
                .background(secili ? Color.accentColor.opacity(0.25) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(secili ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Yerleştirme

    private func baglan() {
        guard arac != .yok else { oturum.dokunusIsleyici = nil; return }
        let secilen = arac
        oturum.dokunusIsleyici = { sayfa, nokta in
            let a: PDFAnnotation
            let ad: String
            switch secilen {
            case .yok: return
            case .damga(let t): a = OgretmenDamga.damga(t, merkez: nokta); ad = t.ad
            case .puan(let d): a = OgretmenDamga.puanEtiketi(d, merkez: nokta); ad = "Puan"
            case .yorum(let y): a = OgretmenDamga.yorum(y, merkez: nokta); ad = "Yorum"
            }
            oturum.aciklamaEkle(a, sayfa, ad: ad)
            yerlesen += 1
            depo.notlandirildi(oturum.oge)
        }
    }

    /// Belgedeki puan toplamını ilk sayfaya yazar (varsa günceller). Geri alınabilir.
    private func toplamiYaz() {
        guard let b = oturum.belge, let s = b.page(at: 0) else { return }
        let yeni = OgretmenDamga.toplamEtiketi(PuanOkuyucu.toplam(b), sayfa: s)
        if let eski = OgretmenDamga.toplamKutusu(s) {
            oturum.degistir("Toplam", yap: { s.removeAnnotation(eski); s.addAnnotation(yeni) },
                            geriAl: { s.removeAnnotation(yeni); s.addAnnotation(eski) })
        } else {
            oturum.aciklamaEkle(yeni, s, ad: "Toplam")
        }
        depo.notlandirildi(oturum.oge)
        yerlesen += 1
    }
}

/// Sınıf listesinden öğrenci seçip dosyayı “No Ad Soyad” olarak adlandırır.
struct OgrenciSecimi: View {
    let oturum: BelgeOturumu
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var arama = ""
    @State private var ileti: Ileti?

    var body: some View {
        NavigationStack {
            List {
                ForEach(depo.siniflar) { s in
                    let liste = s.ogrenciler.filter { arama.isEmpty || TurkceMetin.anahtar($0.tamAd).contains(TurkceMetin.anahtar(arama)) }
                    if !liste.isEmpty {
                        Section(s.ad) {
                            ForEach(liste) { o in
                                Button { adlandir(o) } label: {
                                    HStack {
                                        Text(o.no).foregroundStyle(.secondary).font(.callout.monospacedDigit()).frame(width: 52, alignment: .leading)
                                        Text(o.ad)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $arama, prompt: "Öğrenci ara")
            .overlay {
                if depo.siniflar.isEmpty {
                    ContentUnavailableView("Sınıf listesi yok", systemImage: "person.3", description: Text("Ayarlar › Öğretmen › Sınıf listeleri bölümünden ekleyin."))
                }
            }
            .navigationTitle("Öğrenci seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .iletiGoster($ileti)
        }
    }

    private func adlandir(_ o: Ogrenci) {
        Task {
            guard await oturum.kaydet() else { return }
            let eski = oturum.oge
            do {
                let ad = o.tamAd
                try await kitaplik.yenidenAdlandir(eski, ad)
                let yeniURL = eski.url.deletingLastPathComponent().appendingPathComponent(TurkceMetin.dosyaAdi(ad)).appendingPathExtension(eski.uzanti)
                depo.yolDegisti(eski.yol, (eski.ustYol as NSString).appendingPathComponent(yeniURL.lastPathComponent))
                kapat()
                if let yeni = kitaplik.oge(url: yeniURL) {
                    // Belge yeni adla yeniden açılır (oturum eski yola bağlıydı).
                    yon.acikBelge = nil
                    try? await Task.sleep(for: .milliseconds(450))
                    yon.ac(yeni, kip: .ogretmen)
                }
            } catch {
                ileti = Ileti(error)
            }
        }
    }
}
