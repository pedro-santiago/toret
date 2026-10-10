import SwiftUI
import Testing
import WidgetKit

@testable import Toret

/// Draws every widget family to a PNG so the design can be looked at.
///
/// Runs only when `TORET_RENDER_DIR` is set (pass it to xcodebuild as
/// `TEST_RUNNER_TORET_RENDER_DIR=/some/dir`); an ordinary test run skips it. The
/// frames are the iPhone 17 Pro widget sizes, and the stock behind each one is the
/// same `carta` the widget draws as its container background.
@Suite("Widget renders")
@MainActor
struct WidgetRenderTests {
    private var directory: URL? {
        ProcessInfo.processInfo.environment["TORET_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func render<V: View>(
        _ name: String, size: CGSize, background: Color, @ViewBuilder _ view: () -> V
    ) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let framed = view()
            .frame(width: size.width, height: size.height)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)
            .background(Color(white: 0.5))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else {
            Issue.record("\(name): nothing rendered")
            return
        }
        try png.write(to: directory.appending(path: "\(name).png"))
    }

    private let live = FixResolver.Resolution(origin: Catalogue.anchor, provenance: .live)

    private func reading(
        _ resolution: FixResolver.Resolution? = nil, source: FountainSource = .nearest,
        saved: Set<String> = [], community: [String: CommunitySummary] = [:]
    ) -> WidgetReading {
        WidgetReading.make(
            source: source, saved: saved, resolution: resolution ?? live, community: community
        )
    }

    @Test("Home screen")
    func home() throws {
        let nearest = reading()
        let reported = reading(community: [
            nearest.featured!.id: CommunitySummary(
                state: .running, latestDate: .now, average: 4.5, ratingCount: 2, reportCount: 2
            ),
        ])
        try render("small", size: .init(width: 170, height: 170), background: Palette.carta) {
            SmallFountainView(reading: nearest)
        }
        try render("small-reported", size: .init(width: 170, height: 170), background: Palette.carta) {
            SmallFountainView(reading: reported)
        }
        try render("small-centre", size: .init(width: 170, height: 170), background: Palette.carta) {
            SmallFountainView(reading: reading(.init(origin: Catalogue.anchor, provenance: .centre(denied: true))))
        }
        try render("small-empty", size: .init(width: 170, height: 170), background: Palette.carta) {
            SmallFountainView(reading: reading(source: .saved))
        }
        try render("medium", size: .init(width: 364, height: 170), background: Palette.carta) {
            MediumFountainView(reading: nearest)
        }
        try render("medium-outside", size: .init(width: 364, height: 170), background: Palette.carta) {
            MediumFountainView(reading: reading(.init(
                origin: Catalogue.anchor, provenance: .outsideTurin(kilometres: 9400)
            )))
        }
        try render("large", size: .init(width: 364, height: 382), background: Palette.carta) {
            LargeFountainView(reading: reported)
        }
        let outside = reading(.init(origin: Catalogue.anchor, provenance: .outsideTurin(kilometres: 9400)))
        let centre = reading(.init(origin: Catalogue.anchor, provenance: .centre(denied: false)))
        try render("small-outside", size: .init(width: 170, height: 170), background: Palette.carta) {
            SmallFountainView(reading: outside)
        }
        try render("large-centre", size: .init(width: 364, height: 382), background: Palette.carta) {
            LargeFountainView(reading: centre)
        }
        try render("medium-approx", size: .init(width: 364, height: 170), background: Palette.carta) {
            MediumFountainView(reading: reading(.init(origin: Catalogue.anchor, provenance: .approximate)))
        }
    }

    @Test("Lock Screen")
    func lock() throws {
        let nearest = reading()
        let outside = reading(.init(origin: Catalogue.anchor, provenance: .outsideTurin(kilometres: 9400)))
        try render("lock-circular", size: .init(width: 76, height: 76), background: Color(white: 0.25)) {
            LockCircularView(reading: nearest).foregroundStyle(.white).padding(8)
        }
        try render("lock-rectangular", size: .init(width: 172, height: 76), background: Color(white: 0.25)) {
            LockRectangularView(reading: nearest).foregroundStyle(.white).padding(.horizontal, 10)
        }
        try render("lock-circular-outside", size: .init(width: 76, height: 76), background: Color(white: 0.25)) {
            LockCircularView(reading: outside).foregroundStyle(.white).padding(8)
        }
        try render("lock-rectangular-outside", size: .init(width: 172, height: 76), background: Color(white: 0.25)) {
            LockRectangularView(reading: outside).foregroundStyle(.white).padding(.horizontal, 10)
        }
    }

    @Test("Live Activity")
    func walk() throws {
        let attributes = WalkActivityAttributes(
            fountainID: "1", fountainName: "Via della Consolata", zone: "Aurora"
        )
        let walking = WalkActivityAttributes.ContentState(
            remaining: 240, toNextTurn: 60, instruction: "Vire à direita na Via Po",
            minutes: 3, bearing: 300, heading: 20, arrived: false
        )
        var arrived = walking
        arrived.arrived = true
        arrived.remaining = 0
        try render("walk", size: .init(width: 364, height: 118), background: Palette.notte) {
            WalkLockScreenView(attributes: attributes, state: walking)
        }
        try render("walk-arrived", size: .init(width: 364, height: 118), background: Palette.notte) {
            WalkLockScreenView(attributes: attributes, state: arrived)
        }
    }
}
