import CoreGraphics
import SwiftUI
import Testing

@testable import Toret

/// The drawn Turin: every landmark has a name in all three languages, the compass
/// ring can reach every drawing, and nothing renders blank.
@Suite("Skyline")
@MainActor
struct SkylineTests {
    /// The catalog keys behind `TurinLandmark.name`, in the order of its cases.
    private static let keys: [(TurinLandmark, String)] = [
        (.mole, "Mole Antonelliana"), (.superga, "Basilica di Superga"),
        (.duomo, "Duomo e Cappella della Sindone"), (.granMadre, "Gran Madre di Dio"),
        (.palazzoMadama, "Palazzo Madama"), (.portaPalatina, "Porta Palatina"),
        (.portaNuova, "Porta Nuova"), (.sanCarlo, "Piazza San Carlo"),
        (.rider, "Caval ëd Brons"), (.cappuccini, "Monte dei Cappuccini"),
        (.bridge, "Ponte Vittorio Emanuele I"), (.arcades, "Portici"),
        (.alps, "Alpes"), (.bull, "Touro"),
    ]

    private func lproj(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("The table above lists every landmark exactly once")
    func tableIsComplete() {
        #expect(Set(Self.keys.map(\.0)) == Set(TurinLandmark.allCases))
        #expect(Self.keys.count == TurinLandmark.allCases.count)
    }

    @Test("Every landmark is named in all three languages", arguments: ["pt-BR", "en", "it"])
    func named(language: String) throws {
        let bundle = try lproj(language)
        for (landmark, key) in Self.keys {
            let text = bundle.localizedString(forKey: key, value: "⟂missing⟂", table: nil)
            #expect(text != "⟂missing⟂" && !text.isEmpty, "\(landmark) has no \(language) name")
        }
    }

    @Test("The names that differ by language are translated, not copied", arguments: [
        ("Alpes", "pt-BR", "Alpes"), ("Alpes", "en", "Alps"), ("Alpes", "it", "Alpi"),
        ("Touro", "en", "Bull"), ("Touro", "it", "Toro"),
        ("Portici", "pt-BR", "Pórticos"), ("Portici", "en", "Arcades"),
        ("Duomo e Cappella della Sindone", "en", "Cathedral and Chapel of the Shroud"),
    ])
    func translated(key: String, language: String, expected: String) throws {
        #expect(try lproj(language).localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    @Test("The current language gives every landmark a name")
    func currentNames() {
        for landmark in TurinLandmark.allCases { #expect(!landmark.name.isEmpty) }
        #expect(Set(TurinLandmark.allCases.map(\.name)).count == TurinLandmark.allCases.count)
    }

    // MARK: The ring

    @Test("Every landmark on the compass ring has a drawing")
    func ringMaps() {
        for landmark in Landmark.all(from: Catalogue.anchor) {
            #expect(TurinLandmark(landmark.key).aspect > 0)
            #expect(landmark.drawn == TurinLandmark(landmark.key))
            #expect(TurinLandmark.forRingName(landmark.name) == landmark.drawn)
        }
    }

    @Test("Each ring landmark draws the building it names")
    func ringIsTheRightBuilding() {
        #expect(TurinLandmark(.mole) == .mole)
        #expect(TurinLandmark(.superga) == .superga)
        #expect(TurinLandmark(.duomo) == .duomo)
        #expect(TurinLandmark(.cappuccini) == .cappuccini)
        #expect(TurinLandmark(.portePalatine) == .portaPalatina)
        #expect(TurinLandmark(.portaNuova) == .portaNuova)
        #expect(TurinLandmark(.alps) == .alps)
        #expect(TurinLandmark.forRingName("not a landmark") == nil)
    }

    // MARK: Proportions

    @Test("Aspect ratios are positive and sensible")
    func aspects() {
        for landmark in TurinLandmark.allCases {
            #expect(landmark.aspect > 0.3 && landmark.aspect < 4, "\(landmark) \(landmark.aspect)")
        }
        // The Mole is the tall one: taller than wide by a long way.
        #expect(TurinLandmark.mole.aspect < 0.5)
        #expect(TurinLandmark.arcades.aspect > 2.5)
    }

    // MARK: Rendering

    /// Fraction of a rendering's pixels that are not fully transparent.
    private func coverage<V: View>(of view: V, height: CGFloat = 120) -> Double {
        let renderer = ImageRenderer(content: view.frame(height: height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return 0 }
        let width = image.width, rows = image.height
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: rows))
        var drawn = 0
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 0 { drawn += 1 }
        return Double(drawn) / Double(width * rows)
    }

    @Test("Every landmark draws something, by day and by night", arguments: [false, true])
    func rendersNonEmpty(night: Bool) {
        for landmark in TurinLandmark.allCases {
            let share = coverage(of: landmark.view(night: night))
            #expect(share > 0.05, "\(landmark) night=\(night) covers \(share)")
        }
    }

    @Test("A silhouette still draws, in one colour")
    func mono() {
        for landmark in TurinLandmark.allCases {
            #expect(coverage(of: landmark.view(palette: .mono(.black))) > 0.05, "\(landmark)")
        }
    }

    @Test("The scenes, the bull and the devices render")
    func scenes() {
        #expect(coverage(of: TurinSkyline(style: .strip).frame(width: 360), height: 110) > 0.2)
        #expect(coverage(of: TurinSkyline(style: .horizon).frame(width: 360), height: 48) > 0.1)
        #expect(coverage(of: TurinBull(pose: .front)) > 0.2)
        #expect(coverage(of: TurinBull(pose: .profile)) > 0.2)
        #expect(coverage(of: PosterCornerTriangle(size: 120), height: 120) > 0.2)
        #expect(coverage(of: RiverStripes().frame(width: 200), height: 40) > 0.9)
    }

    // MARK: Determinism

    @Test("The same seed always draws the same city")
    func deterministic() {
        var a = SkylineRandom(seed: 5), b = SkylineRandom(seed: 5), c = SkylineRandom(seed: 6)
        let first = (0 ..< 6).map { _ in a.next() }
        #expect(first == (0 ..< 6).map { _ in b.next() })
        #expect(first != (0 ..< 6).map { _ in c.next() })
        var ranged = SkylineRandom(seed: 9)
        for _ in 0 ..< 200 {
            let v = ranged.value(in: 34 ... 62)
            #expect((34 ... 62).contains(v))
            #expect((2 ... 3).contains(ranged.int(in: 2 ... 3)))
        }
    }
}
