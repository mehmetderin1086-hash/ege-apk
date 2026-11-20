import SwiftUI
import Photos
import VisionKit

/// Giriş çubuğunda gönderilmeyi bekleyen görsel ek (fotoğraf ya da taranmış belge sayfası).
struct GorselEk: Identifiable, Equatable {
    enum Tur { case foto, sayfa }
    let id = UUID()
    var resim: UIImage
    var tur: Tur = .foto
    /// Taranmış sayfalarda yazı okunabilsin diye daha büyük gönderilir.
    var kenar: CGFloat { tur == .sayfa ? 1800 : 1280 }
}

/// "+" sayfasındaki seçimler; sayfa kapandıktan sonra çalışır (üst üste sunum çakışmasın diye).
enum EkEylemi: Equatable {
    case kamera, barkod, fotoSec, belgeTara, dosya, baglanti, dosyalarim, donustur, arsiv, atolye, dosyaKasasi
    case sonFotolar([String])
}

/// "+" ile açılan ek sayfası: son fotoğraflar şeridi, dört büyük eylem ve diğer dosya işleri.
struct EkSayfasi: View {
    let kalanYer: Int
    let sec: (EkEylemi) -> Void
    @State private var son = SonFotograflar()
    @State private var secilenler: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sonFotoSeridi
                    HStack(spacing: 10) {
                        buyukEylem("Fotoğraf çek", "camera", .kamera)
                        buyukEylem("Fotoğraf seç", "photo.on.rectangle", .fotoSec)
                        if VNDocumentCameraViewController.isSupported { buyukEylem("Belge tara", "doc.viewfinder", .belgeTara) }
                        buyukEylem("Dosya", "doc.badge.plus", .dosya, etiket: "Ofis, PDF, metin veya kod ekle")
                    }
                    VStack(spacing: 0) {
                        satir("Büyük dosya yükle · Dosya kasası", "externaldrive", .dosyaKasasi)
                            .accessibilityIdentifier("ek-dosya-kasasi")
                        satir("Ürün barkodu okut", "barcode.viewfinder", .barkod)
                        satir("Bağlantı indir", "arrow.down.circle", .baglanti)
                        satir("Dosyalarımda ara", "folder.badge.questionmark", .dosyalarim)
                        satir("Dosyayı başka biçime dönüştür", "arrow.triangle.2.circlepath", .donustur)
                        satir("ZIP oluştur veya RAR aç", "archivebox", .arsiv)
                        satir("Araştırma, kod ve görsel atölyesi", "sparkles", .atolye, ayirici: false)
                    }
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 14))
                }
                .padding(16)
            }
            .navigationTitle("Ekle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { sec(.sonFotolar([])) } }
                if !secilenler.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle (\(secilenler.count))") { sec(.sonFotolar(secilenler)) }.accessibilityIdentifier("son-foto-ekle")
                    }
                }
            }
        }
        .task { await son.yukle() }
    }

    @ViewBuilder private var sonFotoSeridi: some View {
        switch son.izin {
        case .authorized, .limited:
            if !son.ogeler.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Son fotoğraflar").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(son.ogeler) { o in kucukResim(o) }
                        }
                    }
                    .frame(height: 92)
                    .accessibilityIdentifier("son-fotograflar")
                }
            }
        case .notDetermined:
            Button { Task { await son.izinIste() } } label: {
                Label("Son fotoğrafları burada göster", systemImage: "photo.stack").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).accessibilityIdentifier("son-foto-izin")
        default:
            EmptyView()
        }
    }

    private func kucukResim(_ o: SonFotograflar.Oge) -> some View {
        let sira = secilenler.firstIndex(of: o.id)
        return Button {
            if let sira { secilenler.remove(at: sira) } else if secilenler.count < kalanYer { secilenler.append(o.id) }
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let r = o.kucuk { Image(uiImage: r).resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                }
                .frame(width: 88, height: 88).clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: sira == nil ? 0 : 3))
                if let sira {
                    Text("\(sira + 1)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Color.accentColor, in: Circle()).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sira == nil ? "Son fotoğraf" : "Son fotoğraf, \(sira! + 1). seçili")
        .accessibilityAddTraits(sira == nil ? [] : .isSelected)
    }

    private func buyukEylem(_ ad: String, _ simge: String, _ e: EkEylemi, etiket: String? = nil) -> some View {
        Button { sec(e) } label: {
            VStack(spacing: 6) {
                Image(systemName: simge).font(.system(size: 22))
                Text(ad).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled((e == .kamera || e == .fotoSec || e == .belgeTara) && kalanYer <= 0)
        .accessibilityLabel(etiket ?? ad)
    }

    private func satir(_ ad: String, _ simge: String, _ e: EkEylemi, ayirici: Bool = true) -> some View {
        VStack(spacing: 0) {
            Button { sec(e) } label: {
                Label(ad, systemImage: simge).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ayirici { Divider().padding(.leading, 48) }
        }
    }
}

/// Fotoğraf arşivindeki son görüntüler (küçük resimler + seçilince tam boy).
@Observable
final class SonFotograflar {
    struct Oge: Identifiable { let id: String; var kucuk: UIImage? }
    var izin: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var ogeler: [Oge] = []
    static let adet = 24

    func izinIste() async {
        izin = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await yukle()
    }

    func yukle() async {
        guard izin == .authorized || izin == .limited, ogeler.isEmpty else { return }
        let s = PHFetchOptions()
        s.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        s.fetchLimit = Self.adet
        let sonuc = PHAsset.fetchAssets(with: .image, options: s)
        var varliklar: [PHAsset] = []
        sonuc.enumerateObjects { a, _, _ in varliklar.append(a) }
        ogeler = varliklar.map { Oge(id: $0.localIdentifier) }
        for (i, a) in varliklar.enumerated() {
            guard !Task.isCancelled else { return }   // sayfa kapandı
            let r = await Self.resim(a, kenar: 240, kucuk: true)
            if i < ogeler.count { ogeler[i].kucuk = r }
        }
    }

    /// Seçilen kimliklerin tam boy görüntüleri (seçim sırasıyla).
    static func tamBoy(_ kimlikler: [String]) async -> [UIImage] {
        guard !kimlikler.isEmpty else { return [] }
        let sonuc = PHAsset.fetchAssets(withLocalIdentifiers: kimlikler, options: nil)
        var varlik: [String: PHAsset] = [:]
        sonuc.enumerateObjects { a, _, _ in varlik[a.localIdentifier] = a }
        var cikti: [UIImage] = []
        for k in kimlikler { if let a = varlik[k], let r = await resim(a, kenar: 2048) { cikti.append(r) } }
        return cikti
    }

    /// Sonuç kapanışı sistem kuyruğunda çağrılır: ana aktöre bağlı olmamalı (Swift 6 varsayılan yalıtım tuzağı).
    nonisolated static func resim(_ a: PHAsset, kenar: CGFloat, kucuk: Bool = false) async -> UIImage? {
        nonisolated(unsafe) let varlik = a
        return await withCheckedContinuation { (devam: CheckedContinuation<UIImage?, Never>) in
            let o = PHImageRequestOptions()
            // .fastFormat ve .highQualityFormat tek geri çağrı verir (.opportunistic iki kez çağırıp devamı bozardı).
            o.deliveryMode = kucuk ? .fastFormat : .highQualityFormat
            o.resizeMode = .fast
            o.isNetworkAccessAllowed = !kucuk   // küçük resim için iCloud indirmesi bekletilmez
            PHImageManager.default().requestImage(for: varlik, targetSize: CGSize(width: kenar, height: kenar), contentMode: .aspectFit, options: o) { @Sendable r, _ in
                devam.resume(returning: r)
            }
        }
    }
}

/// VisionKit belge tarayıcısı: kenar algılama, perspektif düzeltme, çok sayfa.
struct BelgeTarayici: UIViewControllerRepresentable {
    /// Yalnız sığacak kadar sayfa çözülür (her sayfa tam çözünürlükte bellekte büyük yer tutar).
    var sinir: Int = .max
    let bitti: ([UIImage]) -> Void
    @Environment(\.dismiss) private var kapat

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let v = VNDocumentCameraViewController()
        v.delegate = context.coordinator
        return v
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let ana: BelgeTarayici
        init(_ ana: BelgeTarayici) { self.ana = ana }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            ana.bitti((0..<min(scan.pageCount, max(0, ana.sinir))).map { scan.imageOfPage(at: $0) })
            ana.kapat()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { ana.kapat() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { ana.kapat() }
    }
}

/// Giriş çubuğunun üstündeki ek önizleme şeridi: dokun → düzenle, çarpı → kaldır.
struct EkSeridi: View {
    @Binding var ekler: [GorselEk]
    let duzenle: (GorselEk) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ekler) { e in
                        Button { duzenle(e) } label: {
                            Image(uiImage: e.resim).resizable().scaledToFill().frame(width: 64, height: 64).clipped().clipShape(.rect(cornerRadius: 10))
                                .contentShape(.rect(cornerRadius: 10))
                                .overlay(alignment: .bottomLeading) {
                                    if e.tur == .sayfa { Image(systemName: "doc.text.fill").font(.caption2).padding(4).foregroundStyle(.white).shadow(radius: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(e.tur == .sayfa ? "Taranan sayfa, düzenle" : "Eklenen fotoğraf, düzenle")
                        .accessibilityIdentifier("ek-onizleme")
                        .overlay(alignment: .topTrailing) {
                            Button { ekler.removeAll { $0.id == e.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).offset(x: 14, y: -14)
                            .accessibilityLabel(e.tur == .sayfa ? "Sayfayı kaldır" : "Fotoğrafı kaldır").accessibilityIdentifier("ek-kaldir")
                        }
                    }
                }
                .padding(.top, 16).padding(.horizontal, 20).padding(.trailing, 14)
            }
            Text(ekler.count == 1 ? (ekler.first?.tur == .sayfa ? "Sayfa eklendi" : "Fotoğraf eklendi") :"\(ekler.count) görsel eklendi · düzenlemek için dokun")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 20)
        }
    }
}
