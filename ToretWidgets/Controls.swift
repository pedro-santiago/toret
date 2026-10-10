import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, the Lock Screen's two buttons, and the Action Button.
///
/// Controls are drawn by the system from an icon and a title, so the poster's
/// vocabulary reaches them as two template images: the needle in its ring, and the
/// needle on a path.

struct NearestControl: ControlWidget {
    static let kind = "toret.control.compass"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenCompassIntent()) {
                Label("Fonte mais próxima", image: "ControlNeedle")
            }
        }
        .displayName("Fonte mais próxima")
        .description("Abre a bússola apontando para a água mais perto de você.")
    }
}

struct RouteControl: ControlWidget {
    static let kind = "toret.control.route"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RouteToNearestIntent()) {
                Label("Rota até a fonte", image: "ControlRoute")
            }
        }
        .displayName("Rota até a fonte")
        .description("Traça a rota a pé até a fonte mais próxima.")
    }
}
