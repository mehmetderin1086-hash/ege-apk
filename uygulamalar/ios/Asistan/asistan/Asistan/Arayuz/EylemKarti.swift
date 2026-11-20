import SwiftUI
import EventKit
import EventKitUI

/// Telefonda sorulmadan yapılan işin kartı: kanıt + geri alma yolu (onay yerine).
/// Aç her türde; Düzenle tek kimlikli takvimde; Geri al takvim/hatırlatıcı/alarm/zamanlayıcıda 10 dakika.
/// SMS ve aramada yalnız Aç (iOS gönderilen mesajı ya da yapılmış aramayı geri almaya izin vermez).
struct EylemKarti: View {
    let kayit: EylemKaydi
    @Environment(\.openURL) private var openURL
    @State private var durumMetni: String?
    @State private var geriAlindi = false
    @State private var calisiyor = false
    @State private var duzenle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: EylemKaydi.simge(kayit.tur)).font(.title2).frame(width: 36).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kayit.baslik).font(.callout.weight(.medium)).lineLimit(2)
                    if !kayit.ozet.isEmpty { Text(kayit.ozet).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                if let a = kayit.acAdresi, let u = URL(string: a) {
                    Button("Aç", systemImage: "arrow.up.forward.app") { openURL(u) }
                        .accessibilityIdentifier("eylem-ac")
                }
                if kayit.duzenlenebilir && !geriAlindi {
                    Button("Düzenle", systemImage: "pencil") { duzenle = true }
                        .accessibilityIdentifier("eylem-duzenle")
                }
                Spacer(minLength: 0)
                geriAlBolumu
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
        .modifier(EylemKartZemini())
        .accessibilityElement(children: .contain).accessibilityIdentifier("eylem-karti")
        .sheet(isPresented: $duzenle) {
            if let id = kayit.kimlikler.first { EtkinlikDuzenleyici(kimlik: id) { duzenle = false }.ignoresSafeArea() }
        }
        // Live açılmadan önce bütün sunumlar kapanır.
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in duzenle = false }
        .task(id: kayit.id) {
            // Uygulama yeniden açılınca ya da balon yeniden çizilince: daha önce geri alındıysa öyle kalsın.
            if EylemGeriAlici.geriAlindiMi(kayit.id) { geriAlindi = true; durumMetni = "Geri alındı" }
        }
    }

    @ViewBuilder private var geriAlBolumu: some View {
        if let durumMetni {
            Text(durumMetni).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("eylem-durum")
        } else if kayit.yalnizAc {
            EmptyView()
        } else if kayit.kimlikler.isEmpty {
            Text("Geri alınamaz").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("eylem-geri-alinamaz")
        } else {
            // 10 dakikadan eski kayıt (sohbet geçmişi) kalıcı "Süre doldu" etiketi ve sürekli zamanlayıcı taşımaz.
            // Süre ekranda dolarsa zamanlayıcı bitiş anında son kez çizer ve durur.
            TimelineView(.explicit(Self.zamanCizelgesi(kayit))) { ctx in
                if kayit.geriAlinabilir(simdi: ctx.date) {
                    HStack(spacing: 6) {
                        Text("\(max(1, Int((kayit.kalanSure(simdi: ctx.date) / 60).rounded(.up)))) dk").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        Button {
                            geriAl()
                        } label: {
                            if calisiyor { ProgressView().controlSize(.small) } else { Label(EylemKaydi.dugmeMetni(kayit), systemImage: "arrow.uturn.backward") }
                        }
                        .disabled(calisiyor)
                        .accessibilityLabel(EylemKaydi.dugmeMetni(kayit))
                        .accessibilityIdentifier("eylem-geri-al")
                    }
                } else if ctx.date.timeIntervalSince(kayit.zaman) < EylemKaydi.geriAlmaSuresi + 30 {
                    Text("Süre doldu").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Şimdi, bitişe kadar 15 sn arayla ve bitiş anı; süre zaten dolmuşsa boş (kart hiçbir şey çizmez).
    static func zamanCizelgesi(_ kayit: EylemKaydi, simdi: Date = .now) -> [Date] {
        let kalan = kayit.kalanSure(simdi: simdi)
        guard kalan > 0 else { return [] }
        let adim = 15.0
        var d = stride(from: 0.0, to: kalan, by: adim).map { simdi.addingTimeInterval($0) }
        d.append(simdi.addingTimeInterval(kalan))
        return d
    }

    private func geriAl() {
        guard !calisiyor else { return }
        calisiyor = true
        let k = kayit
        Task {
            let s = await EylemGeriAlici.geriAl(k)
            calisiyor = false
            if case .tamam = s { geriAlindi = true } else if case .kismen = s { geriAlindi = true }
            withAnimation(.easeOut(duration: 0.2)) { durumMetni = EylemGeriAlici.metin(s, tur: k.tur) }
        }
    }
}

/// MesajEkleri'ndeki `KartZemini` ile aynı biçim (o dosyada private).
private struct EylemKartZemini: ViewModifier {
    @Environment(\.colorScheme) private var sema
    func body(content: Content) -> some View {
        content.padding(12)
            .background(Color(uiColor: .secondarySystemBackground).opacity(sema == .dark ? 0.9 : 0.85), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

/// Tek takvim etkinliğini sistem düzenleyicisinde açar. Etkinlik bulunamazsa (silinmiş, izin yok, önizleme) bilgi gösterir.
struct EtkinlikDuzenleyici: UIViewControllerRepresentable {
    let kimlik: String
    let bitti: () -> Void

    func makeCoordinator() -> Koordinator { Koordinator(bitti: bitti) }

    func makeUIViewController(context: Context) -> UIViewController {
        let depo = EKEventStore()
        let durum = EKEventStore.authorizationStatus(for: .event)
        guard kimlik != EylemKaydi.onizlemeKimligi, durum == .fullAccess, let e = depo.event(withIdentifier: kimlik) else {
            return UIHostingController(rootView: EtkinlikYokGorunumu(kapat: bitti))
        }
        let c = EKEventEditViewController()
        c.eventStore = depo
        c.event = e
        c.editViewDelegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIViewController, context: Context) {}

    final class Koordinator: NSObject, EKEventEditViewDelegate {
        let bitti: () -> Void
        init(bitti: @escaping () -> Void) { self.bitti = bitti }
        /// Sistem çağırır: nonisolated, iş ana aktöre geçer (Swift 6 çalışma zamanı denetimi).
        nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            Task { @MainActor in self.bitti() }
        }
    }
}

private struct EtkinlikYokGorunumu: View {
    let kapat: () -> Void
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Etkinlik bulunamadı", systemImage: "calendar.badge.exclamationmark",
                                   description: Text("Silinmiş olabilir ya da takvim izni kapalı."))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat", action: kapat) } }
        }
    }
}
