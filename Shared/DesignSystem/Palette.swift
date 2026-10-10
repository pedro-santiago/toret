import SwiftUI

/// The Turin travel-poster palette.
///
/// Printed flat, a few inks on cream stock: black for the type and the rules,
/// sun-yellow, rosso, a river blue, and the grey-green of the Alps. There are no
/// gradients and no shadows anywhere in the app, so every colour here is a
/// finished ink and nothing is ever blended into another.
///
/// The three water states are the poster's own shapes in the poster's own
/// colours — blue circle (running), yellow half-disc (weak), red triangle (dry),
/// an empty ring (nobody has said). See ``StateMark``.
enum Palette {
    // MARK: Stock and ink

    /// Cream stock. Every daytime screen is printed on it.
    static let carta = Color(hex: 0xF0E3BF)
    /// Stock in shadow — the second tone for panels printed on `carta`.
    static let cartaScura = Color(hex: 0xE3D3A5)
    /// Stock, lifted — a plate sitting on `carta`.
    static let cartaChiara = Color(hex: 0xF7EDD0)
    /// Black ink: type, rules, frames, the needle.
    static let inchiostro = Color(hex: 0x16130F)

    // MARK: The three inks

    /// The sun, and weak flow. Only ever a fill, never text: it does not reach
    /// contrast on cream.
    static let sole = Color(hex: 0xE9B33B)
    /// The red dot and the rooftops. Dry, and every warning.
    static let rosso = Color(hex: 0xB7301F)
    /// The river. Water that is running, and the one interactive colour.
    static let blu = Color(hex: 0x2C61A0)

    // MARK: The Alps

    static let salvia = Color(hex: 0x8CA48F)
    static let salviaScura = Color(hex: 0x5C7864)
    /// Ochre façades, for the skyline.
    static let facciata = Color(hex: 0xD9C79A)

    // MARK: Night

    /// The night plate: the compass, the lock screen. Blue-black, not black.
    static let notte = Color(hex: 0x12161C)
    static let notteChiara = Color(hex: 0x1D232B)
    /// The sun at night is the moon: the same disc, a paler ink.
    static let luna = Color(hex: 0xF1D98A)

    // MARK: Water state

    /// Running.
    static let corrente = blu
    /// Weak flow.
    static let debole = sole
    /// Dry.
    static let secca = rosso
    /// Nobody has reported. Neutral ink, drawn as an outline.
    static let ignota = inchiostro.opacity(0.55)

    /// Night-legible counterparts: the blue lifts, the red lifts, the yellow stays.
    static let correnteNotte = Color(hex: 0x6FA2DD)
    static let deboleNotte = sole
    static let seccaNotte = Color(hex: 0xE2705C)
    static let ignotaNotte = carta.opacity(0.6)

    // MARK: Ink at opacity

    static func ink(_ opacity: Double) -> Color { inchiostro.opacity(opacity) }
    static func paper(_ opacity: Double) -> Color { carta.opacity(opacity) }

    // MARK: Cartography

    /// Multiplied over Apple's basemap so the streets print on cream stock.
    static let mapWash = Color(hex: 0xF3E8C8)

    // MARK: - Legacy names
    //
    // The first version of the app was drawn in plaster and shutter green. These
    // keep old call sites compiling, mapped onto the poster inks; each is being
    // migrated to the names above and then removed.

    static let paper = carta
    static let paperRaised = cartaChiara
    static let canvas = cartaScura
    static let routeCanvas = cartaScura
    static let ink = inchiostro
    static let night = notte
    static let nightLock = notte
    static let green = blu
    static let terracotta = rosso
    static let ocre = sole
    static let stone = ignota
    static let stoneNight = ignotaNotte
    static let sage = correnteNotte
    static let sand = sole
    static let clay = seccaNotte
    static let brass = sole
    static func sage(_ opacity: Double) -> Color { correnteNotte.opacity(opacity) }
    static let plateHighlight = cartaChiara
    static let plateMid = carta
    static let plateShadow = cartaScura
    static let plateStone = facciata
    static let plateStoneDeep = cartaScura
    static let gridFine = cartaScura
    static let gridCoarse = facciata
    static let street = cartaChiara
    static let streetEdge = facciata
    static let riverCore = blu.opacity(0.25)
    static let riverBank = blu.opacity(0.3)
    static let riverEdge = blu.opacity(0.4)
    static let park = salvia.opacity(0.45)
    static let parkEdge = salvia
    static let block = cartaChiara
    static let blockEdge = facciata
    static let routeGrid = cartaScura
}

extension Color {
    /// 0xRRGGBB literal, the way a palette is written down.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
