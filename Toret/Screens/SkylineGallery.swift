import SwiftUI

/// Every drawn landmark, big and small, on the cream stock and on the night plate,
/// with the thin scenes and the poster devices: the contact sheet the library is
/// judged on. Debug only: open it with `-toret-screen skyline`, or one page of it
/// with `-toret-skyline <0...5>`.
#if DEBUG
struct SkylineGallery: View {
    private let page: Int?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-toret-skyline"),
           arguments.indices.contains(flag + 1), let value = Int(arguments[flag + 1]) {
            page = value
        } else {
            page = nil
        }
    }

    private static let first: [TurinLandmark] = [.mole, .superga, .duomo, .granMadre, .palazzoMadama, .portaPalatina]
    private static let second: [TurinLandmark] = [.portaNuova, .sanCarlo, .rider, .cappuccini, .bridge, .arcades, .alps, .bull]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(pages, id: \.self) { index in
                    content(index)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Palette.carta)
        .ignoresSafeArea()
    }

    private var pages: [Int] { page.map { [$0] } ?? Array(0 ... 5) }

    @ViewBuilder
    private func content(_ index: Int) -> some View {
        switch index {
        case 0: big(Self.first, night: false, height: 170)
        case 1: big(Self.second, night: false, height: 110)
        case 2: big(Self.first, night: true, height: 170)
        case 3: big(Self.second, night: true, height: 110)
        case 4: small
        default: scenes
        }
    }

    private func big(_ landmarks: [TurinLandmark], night: Bool, height: CGFloat) -> some View {
        let columns = [GridItem(.flexible(), alignment: .bottom), GridItem(.flexible(), alignment: .bottom)]
        return LazyVGrid(columns: columns, spacing: 22) {
            ForEach(landmarks) { landmark in
                VStack(spacing: 6) {
                    landmark.view(night: night).frame(height: height)
                    Text(landmark.name)
                        .font(Typo.ui(11, 600))
                        .foregroundStyle(night ? Palette.carta : Palette.inchiostro)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 64).padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 800, alignment: .top)
        .background(night ? Palette.notte : Palette.carta)
    }

    private var small: some View {
        VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { night in
                let columns = Array(repeating: GridItem(.flexible(), alignment: .bottom), count: 4)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(TurinLandmark.allCases) { landmark in
                        landmark.view(night: night).frame(height: night ? 28 : 40)
                    }
                }
                .padding(20).padding(.top, night ? 12 : 56)
                .frame(maxWidth: .infinity, minHeight: 400, alignment: .top)
                .background(night ? Palette.notte : Palette.carta)
            }
        }
        .frame(minHeight: 800)
    }

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            TurinSkyline(style: .strip, seed: 1)
            TurinSkyline(style: .strip, highlight: .granMadre, seed: 4)
            TurinSkyline(style: .horizon, seed: 1)
            TurinSkyline(style: .horizon, seed: 2)
            HStack(spacing: 16) {
                RedDot()
                PosterCornerTriangle(size: 110)
                TurinBull(pose: .front).frame(height: 70)
            }
            RiverStripes().frame(height: 36)
            PosterBand(fill: Palette.cartaScura) {
                Text("PosterBand").font(Typo.display(22, 800)).padding(16)
            }
            PosterFooter("Torino")
            VStack(alignment: .leading, spacing: 14) {
                TurinSkyline(style: .strip, night: true, highlight: .mole, seed: 3)
                TurinSkyline(style: .horizon, night: true, seed: 2)
                PosterFooter("Torino", color: Palette.carta)
            }
            .padding(16).background(Palette.notte)
        }
        .padding(.horizontal, 20).padding(.top, 60)
        .frame(maxWidth: .infinity, minHeight: 800, alignment: .top)
    }
}

/// Opens the gallery full screen. A no-op outside debug builds.
struct SkylineGalleryHook: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) { SkylineGallery() }
    }
}
#else
struct SkylineGalleryHook: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View { content }
}
#endif
