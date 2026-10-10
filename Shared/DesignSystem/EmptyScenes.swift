import SwiftUI

// The drawings for the moments the app has nothing to list or something to say about
// itself: no saved fountains, no reports, no search results, no pins in view, location
// off, a long way from Turin, no street route, a catalogue that did not load.
//
// One family. Every scene is drawn in the same 220 × 150 box with the same few
// pieces: the sun behind (the poster's disc), the red dot off to one side, a heavy
// ground rule at y = 120, and one hero shape that says what happened. Strokes are 2.5
// or 3 pt black, fills are the nine inks, and nothing is blurred or shaded.
//
// They are shapes rather than generated images on purpose: a diffusion model cannot
// be told to keep a line weight, and these have to print exactly on `carta`, scale to
// any size from a 64 pt notice to a full page, and move a little.

/// What a scene is about. The copy and the wiring live with the screens; this is the
/// part the drawing needs.
enum EmptySceneArtKind: Hashable, Sendable, CaseIterable {
    case saved, feed, noResults, noPins, locationOff, outsideTurin, noStreetRoute, catalogueFailed

    /// Where the heroes stand. The street-route scene stands higher, because the river is
    /// what its line crosses and needs room.
    var groundY: CGFloat { self == .noStreetRoute ? 78 : EmptySceneBox.ground }
}

/// The design box every scene is drawn in.
enum EmptySceneBox {
    static let width: CGFloat = 220
    static let height: CGFloat = 150
    /// Where the heroes stand.
    static let ground: CGFloat = 120
    static let stroke: CGFloat = 2.5
}

struct EmptySceneArt: View {
    let kind: EmptySceneArtKind
    /// Draws the ground rule itself, for a miniature with no container around it.
    var drawsGround = false
    /// The distance to print on the "far from Turin" scene.
    var distanceLabel: String?
    /// Lets the scene move: a slow bob and a marching dash. Off for Reduce Motion
    /// and for anything that does not want a loop.
    var animates = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false
    @State private var march: CGFloat = 0

    private var moving: Bool { animates && !reduceMotion }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            if drawsGround {
                // The whole foot, for a miniature with no container: the rule over the river,
                // under the hero so a line that crosses the river stays on top of it.
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.inchiostro).frame(height: 3)
                    RiverStripes(bands: 3)
                }
                .frame(width: EmptySceneBox.width, height: EmptySceneBox.height - kind.groundY)
                .offset(y: kind.groundY)
            }
            hero
        }
        .frame(width: EmptySceneBox.width, height: EmptySceneBox.height, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { startMotion() }
        .onDisappear { stopMotion() }
    }

    // MARK: Motion

    private func startMotion() {
        guard moving else { return }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { bob = true }
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { march = -15 }
    }

    private func stopMotion() {
        withAnimation(nil) { bob = false; march = 0 }
    }

    /// A gentle vertical drift, in points, for the pieces that float.
    private func drift(_ amount: CGFloat, reversed: Bool = false) -> CGFloat {
        guard moving else { return 0 }
        return (bob != reversed ? 1 : -1) * amount
    }

    // MARK: The sun and the dot

    @ViewBuilder private var backdrop: some View {
        switch kind {
        case .locationOff, .outsideTurin, .noStreetRoute:
            // These carry their own sun.
            EmptyView()
        default:
            SunDisc().frame(width: 92, height: 92).position(x: 150, y: 56)
            dot(x: 204, y: 17)
        }
    }

    private func dot(x: CGFloat, y: CGFloat, size: CGFloat = 14) -> some View {
        Circle().fill(Palette.rosso).frame(width: size, height: size).position(x: x, y: y)
    }

    // MARK: Heroes

    @ViewBuilder private var hero: some View {
        switch kind {
        case .saved: saved
        case .feed: feed
        case .noResults: noResults
        case .noPins: noPins
        case .locationOff: locationOff
        case .outsideTurin: outsideTurin
        case .noStreetRoute: noStreetRoute
        case .catalogueFailed: catalogueFailed
        }
    }

    private var ground: CGFloat { kind.groundY }

    /// The toret under the Alps, with an empty diamond (the save mark) hovering over it.
    private var saved: some View {
        let alps = TurinLandmark.alps
        let alpsHeight: CGFloat = 62
        return ZStack(alignment: .topLeading) {
            alps.view()
                .frame(width: alpsHeight * alps.aspect, height: alpsHeight)
                .position(x: alpsHeight * alps.aspect / 2 - 22, y: ground - alpsHeight / 2)
            ToretFigure(kind: .toret, state: .unknown)
                .frame(width: 100 * ToretFigure.aspect, height: 100)
                .position(x: 132, y: ground - 50)
            Diamond()
                .stroke(Palette.inchiostro, lineWidth: EmptySceneBox.stroke + 0.5)
                .background(Diamond().fill(Palette.cartaChiara))
                .frame(width: 30, height: 30)
                .position(x: 172, y: 40 + drift(3))
        }
    }

    /// Two speech bubbles round the bull, the city's emblem: people about to say something.
    /// (Not the Mole: the Relatos header already has one standing beside its title.)
    private var feed: some View {
        let height: CGFloat = 100
        return ZStack(alignment: .topLeading) {
            TurinBull(pose: .front)
                .frame(width: height * BullFrontDrawing.aspect, height: height)
                .position(x: 118, y: ground - height / 2)
            speech(diameter: 50).position(x: 52, y: 54 + drift(3))
            speech(diameter: 36, flipped: true).position(x: 186, y: 96 + drift(3, reversed: true))
        }
    }

    /// A round bubble with a tail and three dots: someone is typing.
    private func speech(diameter d: CGFloat, flipped: Bool = false) -> some View {
        ZStack {
            Circle().fill(Palette.cartaChiara)
            Circle().strokeBorder(Palette.inchiostro, lineWidth: EmptySceneBox.stroke)
            HStack(spacing: d * 0.07) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(Palette.inchiostro).frame(width: d * 0.11, height: d * 0.11)
                }
            }
        }
        .frame(width: d, height: d)
        .overlay(alignment: flipped ? .bottomTrailing : .bottomLeading) {
            Triangle().fill(Palette.inchiostro)
                .frame(width: d * 0.3, height: d * 0.26)
                .rotationEffect(.degrees(flipped ? 160 : 200))
                .offset(x: (flipped ? -1 : 1) * d * 0.02, y: d * 0.18)
        }
    }

    /// A magnifier with nothing in it, and the empty ring that means "nobody has said".
    private var noResults: some View {
        ZStack(alignment: .topLeading) {
            Circle().strokeBorder(Palette.inchiostro.opacity(0.55), lineWidth: 4)
                .frame(width: 40, height: 40)
                .position(x: 164, y: ground - 24)
            ZStack {
                // The handle first, so the lens sits over its root.
                Rectangle().fill(Palette.inchiostro)
                    .frame(width: 9, height: 36)
                    .offset(y: 46)
                    .rotationEffect(.degrees(-45))
                    .offset(x: 6, y: 0)
                Circle().fill(Palette.cartaChiara).frame(width: 62, height: 62)
                Circle().strokeBorder(Palette.inchiostro, lineWidth: 5).frame(width: 62, height: 62)
            }
            .position(x: 88, y: 62 + drift(3))
        }
    }

    /// A little map: a cell of the grid with one empty ring in it and a dashed arrow
    /// leaving it, towards the nearest fountain.
    private var noPins: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Rectangle().fill(Palette.cartaChiara)
                Path { path in
                    for step in 1 ... 2 {
                        let x = CGFloat(step) * 100 / 3
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: 84))
                        let y = CGFloat(step) * 84 / 3
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: 100, y: y))
                    }
                }
                .stroke(Palette.inchiostro.opacity(0.22), lineWidth: 1.5)
                .frame(width: 100, height: 84)
                Circle().strokeBorder(Palette.inchiostro.opacity(0.55), lineWidth: 3.5)
                    .frame(width: 22, height: 22)
                Rectangle().strokeBorder(Palette.inchiostro, lineWidth: EmptySceneBox.stroke)
            }
            .frame(width: 100, height: 84)
            .position(x: 78, y: 70)

            DashedLine(from: CGPoint(x: 112, y: 54), to: CGPoint(x: 150, y: 28))
                .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 3, dash: [8, 7], dashPhase: march))
            Triangle().fill(Palette.inchiostro)
                .frame(width: 16, height: 18)
                .rotationEffect(.degrees(55))
                .position(x: 154, y: 25)
        }
    }

    /// The sun as a compass disc, its needle struck through: no position to point from.
    private var locationOff: some View {
        ZStack(alignment: .topLeading) {
            SunDisc().frame(width: 104, height: 104).position(x: 110, y: 64)
            // The bar goes under the needle: a strike through a disc that still shows what
            // it was, with a margin of stock round the bar so it reads as cut through.
            Rectangle().fill(Palette.carta).frame(width: 150, height: 14)
                .rotationEffect(.degrees(-45)).position(x: 110, y: 64)
            Rectangle().fill(Palette.rosso).frame(width: 150, height: 8)
                .rotationEffect(.degrees(-45)).position(x: 110, y: 64)
            Triangle().fill(Palette.inchiostro)
                .frame(width: 40, height: 62)
                .rotationEffect(.degrees(-30))
                .position(x: 106, y: 62)
            Triangle().fill(Palette.rosso)
                .frame(width: 26, height: 24)
                .overlay { Triangle().stroke(Palette.inchiostro, lineWidth: 2) }
                .position(x: 182, y: ground - 14 + drift(2))
        }
    }

    /// You, a dot at the left; Turin, a Mole under a sun at the right; a dashed line
    /// between them and the distance written over it.
    private var outsideTurin: some View {
        let mole = TurinLandmark.mole
        let height: CGFloat = 92
        return ZStack(alignment: .topLeading) {
            SunDisc().frame(width: 66, height: 66).position(x: 178, y: 50)
            mole.view()
                .frame(width: height * mole.aspect, height: height)
                .position(x: 190, y: ground - height / 2)
            DashedLine(from: CGPoint(x: 26, y: 104), to: CGPoint(x: 164, y: 90))
                .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 3, dash: [8, 7], dashPhase: march))
            Circle().fill(Palette.inchiostro).frame(width: 16, height: 16).position(x: 26, y: 104)
            Circle().strokeBorder(Palette.inchiostro, lineWidth: 2.5).frame(width: 28, height: 28).position(x: 26, y: 104)
            if let distanceLabel {
                Text(distanceLabel)
                    .font(Typo.display(19, 800))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .background(Palette.carta)
                    .position(x: 92, y: 80)
            }
            dot(x: 128, y: 22)
        }
    }

    /// A straight dashed line across the river, from you to a fountain nobody has reported on:
    /// the app is pointing, not routing.
    private var noStreetRoute: some View {
        ZStack(alignment: .topLeading) {
            SunDisc().frame(width: 74, height: 74).position(x: 118, y: 40)
            Circle().strokeBorder(Palette.inchiostro.opacity(0.7), lineWidth: 4)
                .background(Circle().fill(Palette.carta))
                .frame(width: 30, height: 30)
                .position(x: 176, y: 62)
            DashedLine(from: CGPoint(x: 26, y: 134), to: CGPoint(x: 168, y: 76))
                .stroke(Palette.carta, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
            DashedLine(from: CGPoint(x: 26, y: 134), to: CGPoint(x: 168, y: 76))
                .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 3.5, dash: [9, 7], dashPhase: march))
            Circle().fill(Palette.inchiostro).frame(width: 15, height: 15).position(x: 26, y: 134)
            Circle().strokeBorder(Palette.carta, lineWidth: 3).frame(width: 15, height: 15).position(x: 26, y: 134)
            dot(x: 20, y: 22)
        }
    }

    /// A column snapped off short, a dry cracked bowl, and the red triangle of "dry".
    private var catalogueFailed: some View {
        ZStack(alignment: .topLeading) {
            // The stump of the column, with a ragged top.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 6, y: -8)); path.addLine(to: CGPoint(x: 11, y: 0))
                path.addLine(to: CGPoint(x: 17, y: -6)); path.addLine(to: CGPoint(x: 24, y: 2))
                path.addLine(to: CGPoint(x: 24, y: 52)); path.addLine(to: CGPoint(x: 0, y: 52))
                path.closeSubpath()
            }
            .fill(Palette.salviaScura)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 6, y: -8)); path.addLine(to: CGPoint(x: 11, y: 0))
                    path.addLine(to: CGPoint(x: 17, y: -6)); path.addLine(to: CGPoint(x: 24, y: 2))
                    path.addLine(to: CGPoint(x: 24, y: 52)); path.addLine(to: CGPoint(x: 0, y: 52))
                    path.closeSubpath()
                }
                .stroke(Palette.inchiostro, lineWidth: EmptySceneBox.stroke)
            }
            .frame(width: 24, height: 52)
            .position(x: 96, y: 72 - 26 + 8)

            // The bowl: a lower half-disc with a straight rim.
            ZStack(alignment: .top) {
                HalfDisc().fill(Palette.cartaScura)
                    .frame(width: 116, height: 58).rotationEffect(.degrees(180))
                HalfDisc().stroke(Palette.inchiostro, lineWidth: EmptySceneBox.stroke + 0.5)
                    .frame(width: 116, height: 58).rotationEffect(.degrees(180))
                // The crack, a zigzag from the rim down through the belly.
                Path { path in
                    path.move(to: CGPoint(x: 62, y: 2))
                    path.addLine(to: CGPoint(x: 52, y: 20)); path.addLine(to: CGPoint(x: 64, y: 32))
                    path.addLine(to: CGPoint(x: 54, y: 46)); path.addLine(to: CGPoint(x: 60, y: 56))
                }
                .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 3, lineJoin: .miter))
                .frame(width: 116, height: 58)
                Rectangle().fill(Palette.inchiostro).frame(width: 128, height: 7)
            }
            .frame(width: 128, height: 62)
            .position(x: 96, y: 88)

            Triangle().fill(Palette.rosso)
                .overlay { Triangle().stroke(Palette.inchiostro, lineWidth: 2.5) }
                .frame(width: 30, height: 27)
                .position(x: 162, y: 63 + drift(2))
        }
    }
}

/// A straight line between two points, as a shape so its dash can march.
struct DashedLine: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// The scene at a smaller size, for the places that are a notice rather than a page:
/// the box is scaled as a whole, so the strokes thin with it.
struct EmptySceneMini: View {
    let kind: EmptySceneArtKind
    var height: CGFloat = 64
    var distanceLabel: String?

    var body: some View {
        let scale = height / EmptySceneBox.height
        EmptySceneArt(kind: kind, drawsGround: true, distanceLabel: distanceLabel, animates: false)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: EmptySceneBox.width * scale, height: height, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

#Preview("Empty scenes") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(EmptySceneArtKind.allCases, id: \.self) { kind in
                EmptySceneArt(kind: kind, drawsGround: true, distanceLabel: "9.400 km")
            }
        }
        .padding()
    }
    .background(Palette.carta)
}
