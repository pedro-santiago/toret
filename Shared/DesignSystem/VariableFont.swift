import CoreText
import SwiftUI
import UIKit

/// Instantiates named positions on a variable font's design axes.
///
/// Both bundled families ship as single variable files, so one `Archivo.ttf`
/// covers every weight the interface uses *and* Archivo Narrow (the `wdth` axis
/// bottoms out at 62, which is exactly the Narrow width), and one
/// `LeagueSpartan.ttf` runs from Thin to Black on its `wght` axis — the poster
/// titles sit at the Black end.
enum VariableFont {
    /// Four-character axis tags, pre-resolved to the identifiers CoreText wants.
    enum Axis {
        static let weight = 0x7767_6874 // 'wght'
        static let width = 0x7764_7468  // 'wdth'
        static let opticalSize = 0x6F70_737A // 'opsz'
    }

    enum Family {
        static let archivo = "Archivo"
        static let spartan = "League Spartan"
    }

    /// A resolved font is cached — building one walks the axis tables, and the
    /// map screen alone asks for a couple of dozen per frame.
    @MainActor private static var cache: [Key: UIFont] = [:]

    private struct Key: Hashable {
        let family: String
        let size: CGFloat
        let axes: [Int: CGFloat]
        let italic: Bool
    }

    @MainActor
    static func font(
        family: String,
        size: CGFloat,
        axes: [Int: CGFloat],
        italic: Bool = false
    ) -> UIFont {
        let key = Key(family: family, size: size, axes: axes, italic: italic)
        if let hit = cache[key] { return hit }

        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ]
        if italic {
            attributes[.traits] = [
                UIFontDescriptor.TraitKey.symbolic: UIFontDescriptor.SymbolicTraits.traitItalic.rawValue,
            ]
        }

        let descriptor = UIFontDescriptor(fontAttributes: attributes)
        let resolved = UIFont(descriptor: descriptor, size: size)
        cache[key] = resolved
        return resolved
    }
}
