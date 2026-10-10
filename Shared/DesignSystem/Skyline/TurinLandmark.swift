import SwiftUI

/// Every drawn thing from Turin, named once.
///
/// This is the catalogue the compass rim, the map markers and the empty states
/// draw from. Each case knows its name in the reader's language, its proportions,
/// and how to draw itself on the cream stock or on the night plate.
enum TurinLandmark: String, CaseIterable, Identifiable, Sendable {
    case mole, superga, duomo, granMadre, palazzoMadama, portaPalatina, portaNuova
    case sanCarlo, rider, cappuccini, bridge, arcades, alps, bull

    var id: String { rawValue }

    /// The name as it is written on a plaque, in the reader's language.
    var name: String {
        switch self {
        case .mole: String(localized: "Mole Antonelliana")
        case .superga: String(localized: "Basilica di Superga")
        case .duomo: String(localized: "Duomo e Cappella della Sindone")
        case .granMadre: String(localized: "Gran Madre di Dio")
        case .palazzoMadama: String(localized: "Palazzo Madama")
        case .portaPalatina: String(localized: "Porta Palatina")
        case .portaNuova: String(localized: "Porta Nuova")
        case .sanCarlo: String(localized: "Piazza San Carlo")
        case .rider: String(localized: "Caval ëd Brons")
        case .cappuccini: String(localized: "Monte dei Cappuccini")
        case .bridge: String(localized: "Ponte Vittorio Emanuele I")
        case .arcades: String(localized: "Portici")
        case .alps: String(localized: "Alpes")
        case .bull: String(localized: "Touro")
        }
    }

    /// Width : height of the drawing's box.
    var aspect: CGFloat {
        switch self {
        case .mole: MoleDrawing.aspect
        case .superga: SupergaDrawing.aspect
        case .duomo: DuomoDrawing.aspect
        case .granMadre: GranMadreDrawing.aspect
        case .palazzoMadama: PalazzoMadamaDrawing.aspect
        case .portaPalatina: PortaPalatinaDrawing.aspect
        case .portaNuova: PortaNuovaDrawing.aspect
        case .sanCarlo: SanCarloDrawing.aspect
        case .rider: RiderDrawing.aspect
        case .cappuccini: CappucciniDrawing.aspect
        case .bridge: BridgeDrawing.aspect
        case .arcades: ArcadesDrawing.aspect
        case .alps: AlpsDrawing.aspect
        case .bull: BullProfileDrawing.aspect
        }
    }

    /// The drawing in the day or night inks.
    @ViewBuilder
    func view(night: Bool = false) -> some View {
        view(palette: .of(night: night))
    }

    /// The drawing in any palette: `.mono(_:)` for a silhouette.
    @ViewBuilder
    func view(palette: SkylinePalette) -> some View {
        switch self {
        case .mole: DrawnLandmark(MoleDrawing(), palette: palette)
        case .superga: DrawnLandmark(SupergaDrawing(), palette: palette)
        case .duomo: DrawnLandmark(DuomoDrawing(), palette: palette)
        case .granMadre: DrawnLandmark(GranMadreDrawing(), palette: palette)
        case .palazzoMadama: DrawnLandmark(PalazzoMadamaDrawing(), palette: palette)
        case .portaPalatina: DrawnLandmark(PortaPalatinaDrawing(), palette: palette)
        case .portaNuova: DrawnLandmark(PortaNuovaDrawing(), palette: palette)
        case .sanCarlo: DrawnLandmark(SanCarloDrawing(), palette: palette)
        case .rider: DrawnLandmark(RiderDrawing(), palette: palette)
        case .cappuccini: DrawnLandmark(CappucciniDrawing(), palette: palette)
        case .bridge: DrawnLandmark(BridgeDrawing(), palette: palette)
        case .arcades: DrawnLandmark(ArcadesDrawing(), palette: palette)
        case .alps: DrawnLandmark(AlpsDrawing(wide: true, seed: 1), palette: palette)
        case .bull: DrawnLandmark(BullProfileDrawing(), palette: palette)
        }
    }
}
