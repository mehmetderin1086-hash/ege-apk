import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Fotoğraf düzeltme ekranı: döndürme (90° adımlarla) ve kırpma.
/// Eğri çekilmiş kapak/künye fotoğraflarında OCR başarısını belirgin artırır.
struct ImageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data
    let onDone: (Data) -> Void

    @State private var rotation = 0
    /// Kırpma dikdörtgeni, 0-1 aralığında oransal değerler (görüntüden bağımsız)
    @State private var cropRect = CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92)
    @State private var displayImage: CGImage?
    @State private var isRendering = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    ZStack {
                        if let displayImage {
                            let frame = fittedRect(
                                imageSize: CGSize(
                                    width: displayImage.width, height: displayImage.height
                                ),
                                in: geometry.size
                            )

                            Image(decorative: displayImage, scale: 1)
                                .resizable()
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)

                            cropOverlay(in: frame)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                Text("Köşeleri sürükleyerek kırpın; gerekirse döndürün. Yalnızca kitap kalacak şekilde kırpmak OCR'ı iyileştirir.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 24) {
                    Button {
                        rotation = (rotation + 270) % 360
                        reload()
                    } label: {
                        Label("Sola", systemImage: "rotate.left")
                    }

                    Button {
                        rotation = (rotation + 90) % 360
                        reload()
                    } label: {
                        Label("Sağa", systemImage: "rotate.right")
                    }

                    Button {
                        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    } label: {
                        Label("Tümü", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)
            }
            .navigationTitle("Fotoğrafı Düzelt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(isRendering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        // 12 MP fotoğrafın döndür/kırp/kodla işi arayüzü dondurmasın
                        let data = imageData, angle = rotation, crop = cropRect
                        isRendering = true
                        Task { @MainActor in
                            let result = await Task.detached(priority: .userInitiated) {
                                Self.renderResult(data, rotation: angle, cropRect: crop)
                            }.value
                            if let result { onDone(result) }
                            dismiss()
                        }
                    }
                    .disabled(isRendering)
                }
            }
            // Render sürerken kapatılan düzenleyici sonradan kapağı değiştirmesin
            .interactiveDismissDisabled(isRendering)
            .task { reload() }
        }
    }

    // MARK: - Kırpma çerçevesi

    private func cropOverlay(in frame: CGRect) -> some View {
        let rect = CGRect(
            x: frame.minX + cropRect.minX * frame.width,
            y: frame.minY + cropRect.minY * frame.height,
            width: cropRect.width * frame.width,
            height: cropRect.height * frame.height
        )

        return ZStack {
            Rectangle()
                .strokeBorder(KitapTema.vurgu, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            handle(at: CGPoint(x: rect.minX, y: rect.minY), frame: frame, isTopLeft: true)
            handle(at: CGPoint(x: rect.maxX, y: rect.maxY), frame: frame, isTopLeft: false)
        }
    }

    private func handle(at point: CGPoint, frame: CGRect, isTopLeft: Bool) -> some View {
        Circle()
            .fill(KitapTema.vurgu)
            .frame(width: 26, height: 26)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let relativeX = min(max((value.location.x - frame.minX) / frame.width, 0), 1)
                        let relativeY = min(max((value.location.y - frame.minY) / frame.height, 0), 1)

                        if isTopLeft {
                            let maxX = cropRect.maxX - 0.1
                            let maxY = cropRect.maxY - 0.1
                            let newX = min(relativeX, maxX)
                            let newY = min(relativeY, maxY)
                            cropRect = CGRect(
                                x: newX, y: newY,
                                width: cropRect.maxX - newX,
                                height: cropRect.maxY - newY
                            )
                        } else {
                            let newMaxX = max(relativeX, cropRect.minX + 0.1)
                            let newMaxY = max(relativeY, cropRect.minY + 0.1)
                            cropRect = CGRect(
                                x: cropRect.minX, y: cropRect.minY,
                                width: newMaxX - cropRect.minX,
                                height: newMaxY - cropRect.minY
                            )
                        }
                    }
            )
            .accessibilityLabel(isTopLeft ? "Sol üst kırpma köşesi" : "Sağ alt kırpma köşesi")
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Görüntü işlemleri

    private func reload() {
        let data = imageData
        let angle = rotation
        Task.detached(priority: .userInitiated) {
            guard let base = ImageTransform.decode(data) else { return }
            let rotated = ImageTransform.rotate(base, degrees: angle) ?? base
            let preview = ImageTransform.downscale(rotated, maxPixel: 1400) ?? rotated
            // Hızlı art arda döndürmede eski açının önizlemesi yenisini ezmesin
            await MainActor.run { if angle == rotation { displayImage = preview } }
        }
    }

    nonisolated private static func renderResult(_ imageData: Data, rotation: Int, cropRect: CGRect) -> Data? {
        guard let base = ImageTransform.decode(imageData) else { return nil }
        let rotated = ImageTransform.rotate(base, degrees: rotation) ?? base
        guard let cropped = ImageTransform.crop(rotated, to: cropRect) else { return nil }
        return ImageTransform.encodePNG(cropped)
    }
}

/// Görüntü dönüşümleri (döndür, kırp, ölçekle) — ekrandan bağımsız, test edilebilir.
nonisolated enum ImageTransform {
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // EXIF yönü uygulanır: dikey çekilen kamera fotoğrafı düzenleyicide yan yatmış açılmaz
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard orientation != 1,
              let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Oransal dikdörtgene göre kırpar (0-1 aralığında; y ekseni üstten).
    static func crop(_ image: CGImage, to relative: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rect = CGRect(
            x: (relative.minX * width).rounded(),
            y: (relative.minY * height).rounded(),
            width: (relative.width * width).rounded(),
            height: (relative.height * height).rounded()
        )
        guard rect.width >= 1, rect.height >= 1 else { return image }
        return image.cropping(to: rect) ?? image
    }

    /// 90° adımlarla döndürür.
    static func rotate(_ image: CGImage, degrees: Int) -> CGImage? {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return image }

        let swapsAxes = normalized == 90 || normalized == 270
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(normalized) * .pi / 180)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width), height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    static func downscale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }
        let scale = CGFloat(maxPixel) / CGFloat(longest)
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
