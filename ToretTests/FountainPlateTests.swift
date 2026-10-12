import CoreLocation
import SwiftUI
import Testing

@testable import Toret

private func fountain(
    _ id: String, kind: FountainKind = .toret, zone: String? = "Centro",
    state: WaterState = .unknown
) -> Fountain {
    let entry = CatalogueEntry(
        id: id, lat: 45.07, lon: 7.68, kind: kind, name: nil, street: "Via Test",
        zone: zone, ref: nil, wheelchair: nil, bottle: nil, dog: nil, seasonal: nil, checked: nil
    )
    let summary = CommunitySummary(
        state: state, latestDate: state == .unknown ? nil : .now,
        average: nil, ratingCount: 0, reportCount: state == .unknown ? 0 : 1
    )
    return Fountain(entry: entry, community: summary, from: Catalogue.anchor)
}

@Suite("Fountain plates")
struct FountainPlateTests {
    @Test("The same fountain always gets the same plate")
    func stable() {
        for entry in Catalogue.entries.prefix(60) {
            let a = FountainPlateSpec(id: entry.id, kind: entry.kind, zone: entry.zone)
            let b = FountainPlateSpec(id: entry.id, kind: entry.kind, zone: entry.zone)
            #expect(a == b)
        }
    }

    @Test("The hash is fixed, not seeded per launch")
    func fixedHash() {
        var rng = PlateRandom("421310659")
        var again = PlateRandom("421310659")
        #expect(rng.next() == again.next())
        // FNV-1a of the empty string is the offset basis, then one SplitMix step.
        var empty = PlateRandom("")
        var other = PlateRandom("x")
        #expect(empty.next() != other.next())
    }

    @Test("Neighbours differ")
    func neighboursDiffer() {
        // A hundred fountains in the same zone and of the same kind: very few
        // plates may repeat exactly.
        let specs = (0 ..< 100).map { FountainPlateSpec(id: String(421_310_000 + $0 * 7), kind: .toret, zone: "Cenisia") }
        #expect(Set(specs).count >= 99)
        #expect(Set(specs.map(\.variant)).count == FountainPlateSpec.variantCounts[.toret])
        #expect(Set(specs.map(\.stripes)).count == 3)
        #expect(Set(specs.map(\.mirrored)).count == 2)
    }

    @Test("Every real fountain gets a valid spec")
    func catalogue() {
        #expect(Catalogue.entries.count > 700)
        var seen = Set<FountainPlateSpec>()
        for entry in Catalogue.entries {
            let spec = FountainPlateSpec(id: entry.id, kind: entry.kind, zone: entry.zone)
            seen.insert(spec)
            #expect(spec.kind == entry.kind)
            #expect((0 ..< (FountainPlateSpec.variantCounts[entry.kind] ?? 0)).contains(spec.variant))
            #expect((2 ... 4).contains(spec.stripes))
            #expect((0.4 ... 0.6).contains(spec.subjectX))
            #expect((0.1 ... 0.9).contains(spec.sunX) && (0.1 ... 0.5).contains(spec.sunY))
            #expect((0.1 ... 0.35).contains(spec.sunRadius))
            #expect((0.02 ... 0.06).contains(spec.dotRadius))
            #expect((0.05 ... 0.95).contains(spec.dotX) && (0.05 ... 0.35).contains(spec.dotY))
            #expect((0.2 ... 0.8).contains(spec.backdropX))
            #expect((0.8 ... 1.0).contains(spec.backdropScale))
        }
        // The plates are all different from one another, by id.
        #expect(seen.count == Catalogue.entries.count)
    }

    @Test("Every kind and every neighbourhood has a plate")
    func coverage() {
        for kind in [FountainKind.toret, .fountain, .bubbler, .refill] {
            #expect(FountainPlateSpec.variantCounts[kind, default: 0] >= 3)
            for variant in 0 ..< FountainPlateSpec.variantCounts[kind, default: 0] {
                #expect(UIImage(named: FountainPlateSpec.assetName(kind: kind, variant: variant)) != nil)
            }
        }
        let zones = Set(Catalogue.entries.compactMap(\.zone))
        #expect(zones.count == 35)
        #expect(FountainPlateSpec.backdrops.count == 35)
        for zone in zones {
            #expect(FountainPlateSpec.backdrops[zone] != nil)
        }
        // Zone-less fountains still get a backdrop.
        #expect(Catalogue.entries.contains { $0.zone == nil })
        // All of the backdrops are in use somewhere in the city.
        let used = Set(FountainPlateSpec.backdrops.values)
        for backdrop in PlateBackdrop.all { #expect(used.contains(backdrop)) }
    }

    @Test("The plate does not depend on the water")
    func ignoresWaterState() {
        // The spec is built from id, kind and zone alone; the model's `Fountain`
        // initialiser must give the same plate whatever the community has said.
        let plates = WaterState.allCases.map { FountainPlateSpec(fountain("77", state: $0)) }
        #expect(Set(plates).count == 1)
        #expect(FountainPlateSpec(fountain("77", state: .running)) == FountainPlateSpec(id: "77", kind: .toret, zone: "Centro"))
    }

    @Test("A fountain keeps its plate when the person walks")
    func ignoresDistance() {
        let near = fountain("9001")
        let far = near.relocated(to: CLLocationCoordinate2D(latitude: 45.2, longitude: 7.9))
        #expect(near.distance != far.distance)
        #expect(FountainPlateSpec(near) == FountainPlateSpec(far))
    }

    @Test("Kind chooses the subject")
    func kindPicksSubject() {
        for kind in [FountainKind.toret, .fountain, .bubbler, .refill] {
            let spec = FountainPlateSpec(id: "5", kind: kind, zone: nil)
            #expect(spec.assetName.hasPrefix("plate-\(kind.rawValue)-"))
        }
    }

    @Test("No pairing prints a blue dot, which is the running mark")
    func noBlueDot() {
        for pairing in PlatePairing.allCases {
            #expect(PlateInks.of(pairing, night: false).dot != Palette.blu)
            #expect(PlateInks.of(pairing, night: true).dot != Palette.blu)
        }
    }

    @MainActor
    @Test("Plates are rendered once and then cached")
    func caching() {
        let spec = FountainPlateSpec(id: "42424242", kind: .refill, zone: "Aurora")
        let size = CGSize(width: 44, height: 44)
        #expect(!PlateCache.isCached(for: spec, size: size, night: false, topInset: 0, scale: 3))
        let first = PlateCache.image(for: spec, size: size, night: false, topInset: 0, scale: 3)
        #expect(first != nil)
        #expect(PlateCache.isCached(for: spec, size: size, night: false, topInset: 0, scale: 3))
        #expect(PlateCache.image(for: spec, size: size, night: false, topInset: 0, scale: 3) === first)
    }

    @MainActor
    @Test("A plate renders at every size we use, day and night")
    func renders() throws {
        let spec = FountainPlateSpec(id: "421310659", kind: .toret, zone: "Cenisia")
        for night in [false, true] {
            for size in [CGSize(width: 52, height: 52), CGSize(width: 393, height: 360), CGSize(width: 800, height: 300)] {
                let renderer = ImageRenderer(content: FountainPlate(spec: spec, night: night).frame(width: size.width, height: size.height))
                renderer.scale = 1
                #expect(renderer.uiImage != nil)
            }
        }
    }

    /// Writes a contact sheet of varied fountains when `TORET_PLATE_OUT` names a
    /// directory: the way to look at the family of prints.
    @MainActor
    @Test("Contact sheet", .enabled(if: ProcessInfo.processInfo.environment["TORET_PLATE_OUT"] != nil))
    func contactSheet() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TORET_PLATE_OUT"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Every fourth fountain by position in the file keeps all kinds and zones in play.
        var picked: [CatalogueEntry] = []
        for kind in [FountainKind.toret, .fountain, .bubbler, .refill] {
            let ofKind = Catalogue.entries.filter { $0.kind == kind }
            let take = kind == .toret ? 12 : kind == .fountain ? 12 : 6
            picked += stride(from: 0, to: ofKind.count, by: max(1, ofKind.count / take)).prefix(take).map { ofKind[$0] }
        }
        let tile = CGSize(width: 300, height: 280)
        let columns = 6
        let rows = (picked.count + columns - 1) / columns
        let grid = VStack(spacing: 8) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < picked.count {
                            let entry = picked[index]
                            FountainPlate(spec: FountainPlateSpec(id: entry.id, kind: entry.kind, zone: entry.zone))
                                .frame(width: tile.width, height: tile.height)
                        } else {
                            Color.clear.frame(width: tile.width, height: tile.height)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        try #require(image.pngData()).write(to: directory.appending(path: "sheet.png"))
        for (name, spec) in [("hero", picked[2]), ("night", picked[14])] {
            let night = name == "night"
            let one = FountainPlate(spec: FountainPlateSpec(id: spec.id, kind: spec.kind, zone: spec.zone), night: night)
                .frame(width: 393, height: 360)
            let r = ImageRenderer(content: one)
            r.scale = 2
            try #require(r.uiImage?.pngData()).write(to: directory.appending(path: "\(name).png"))
        }
        // Small sizes: the row thumbnail.
        let strip = HStack(spacing: 8) {
            ForEach(Array(picked.prefix(12).enumerated()), id: \.offset) { _, entry in
                FountainPlate(spec: FountainPlateSpec(id: entry.id, kind: entry.kind, zone: entry.zone))
                    .frame(width: 52, height: 52)
                    .overlay(Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2))
            }
        }
        .padding(8).background(Palette.carta)
        let sr = ImageRenderer(content: strip)
        sr.scale = 3
        try #require(sr.uiImage?.pngData()).write(to: directory.appending(path: "thumbs.png"))
    }
}
