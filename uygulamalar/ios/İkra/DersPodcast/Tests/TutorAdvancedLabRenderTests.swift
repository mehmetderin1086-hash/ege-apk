import SwiftUI
import Testing
import UIKit
@testable import Ikra

@Suite(.serialized) @MainActor struct TutorAdvancedLabRenderTests {
    @Test(arguments: TutorAdvancedExperiment.allCases)
    func labControlsRenderAtPhoneWidth(_ mode: TutorAdvancedExperiment) async throws {
        let content = TutorAdvancedLabContent(mode: mode).padding(16).frame(width: 390)
            .background(Color.white).environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: content)
        let desired = host.sizeThatFits(in: CGSize(width: 390, height: 9000))
        #expect(desired.height > 250 && desired.height < 9000)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: ceil(desired.height)))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.backgroundColor = .white
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let imageData = try #require(image.pngData())
        #expect(imageData.count > 10000)
        let index = TutorAdvancedExperiment.allCases.firstIndex(of: mode) ?? 0
        try imageData.write(to: URL.documentsDirectory.appending(path: "advanced-lab-\(index + 21).png"))
    }
}
