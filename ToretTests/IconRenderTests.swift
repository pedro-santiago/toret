import SwiftUI
import Testing

@testable import Toret

/// Renders the app icon variants to PNG for `tools/make-icon.sh`.
///
/// The test does nothing unless `TORET_ICON_OUT` names a directory, so an
/// ordinary test run never touches the asset catalogue. It lives in the test
/// target because `ImageRenderer` needs a running app host and the host already
/// has the design system compiled in.
@Suite("Icon rendering")
@MainActor
struct IconRenderTests {
    nonisolated private static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["TORET_ICON_OUT"].map { URL(fileURLWithPath: $0) }
    }

    @Test("Renders the three icon variants at 1024", .enabled(if: outputDirectory != nil))
    func render() throws {
        let directory = try #require(Self.outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for variant in AppIconArt.Variant.allCases {
            let renderer = ImageRenderer(
                content: AppIconArt(variant: variant).frame(width: 1024, height: 1024)
            )
            renderer.scale = 1
            renderer.isOpaque = true
            let image = try #require(renderer.uiImage)
            let data = try #require(image.pngData())
            try data.write(to: directory.appending(path: variant.fileName))
        }
    }

    @Test("Every variant has its own file name")
    func fileNames() {
        let names = AppIconArt.Variant.allCases.map(\.fileName)
        #expect(Set(names).count == names.count)
    }
}
