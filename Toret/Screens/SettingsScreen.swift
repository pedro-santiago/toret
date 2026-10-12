import CoreLocation
import SwiftUI
import UserNotifications

/// Where Ajustes sends you. The privacy and support pages are published from
/// `docs/privacy` and `docs/support`; until they are hosted at these addresses
/// the two links open a page that does not exist yet.
enum ExternalLinks {
    static let privacy = URL(string: "https://toret.deepdive.dev.br/privacy/")!
    static let support = URL(string: "https://toret.deepdive.dev.br/support/")!
    static let openStreetMapCopyright = URL(string: "https://www.openstreetmap.org/copyright")!
    static let openMeteo = URL(string: "https://open-meteo.com/")!
}

/// The version the bundle says it is, never a number typed into a view.
enum AppInfo {
    static func versionLine(from info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// The words for each permission, kept apart so they can be tested.
enum PermissionCopy {
    static func location(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: String(localized: "Sempre")
        case .authorizedWhenInUse: String(localized: "Ao usar o app")
        case .denied: String(localized: "Desligada")
        case .restricted: String(localized: "Bloqueada neste aparelho")
        case .notDetermined: String(localized: "Ainda não perguntada")
        @unknown default: String(localized: "Desconhecida")
        }
    }

    static func precision(_ accuracy: CLAccuracyAuthorization) -> String {
        accuracy == .fullAccuracy ? String(localized: "Precisa") : String(localized: "Aproximada")
    }

    static func notifications(_ status: UNAuthorizationStatus?) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: String(localized: "Permitidas")
        case .denied: String(localized: "Desligadas")
        case .notDetermined: String(localized: "Ainda não perguntadas")
        case nil: String(localized: "Verificando")
        @unknown default: String(localized: "Desconhecidas")
        }
    }

    /// Whether the status is something only the iOS Settings app can change.
    static func needsSettings(_ status: CLAuthorizationStatus) -> Bool {
        status == .denied || status == .authorizedWhenInUse
    }
}

/// Ajustes.
///
/// Plain rows under heavy rules. The one setting that matters is the first:
/// whether the needle is allowed to follow you out of the app onto the lock screen
/// and the home screen. Its caption changes with it, so the consequence of the
/// switch is legible before you flip it rather than after.
struct SettingsScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var notifications: UNAuthorizationStatus?

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    PosterTitle(localized: "AJUS\nTES", size: 104)
                        .padding(.top, 14)
                    Text(String(localized: "Gratuito, sem anúncios, sem conta e sem rastreamento."))
                        .font(Typo.ui(17, 500))
                        .lineHeight(1.35, font: Typo.uiInterface(17, 500))
                        .foregroundStyle(Palette.inchiostro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)

                group(String(localized: "Bússola e avisos")) {
                    SettingsToggle(
                        title: String(localized: "Bússola sempre visível"),
                        note: model.compassAlwaysVisible
                            ? String(localized: "Na tela bloqueada e no widget")
                            : String(localized: "Só dentro do app"),
                        isOn: $model.compassAlwaysVisible
                    )
                    SettingsToggle(
                        title: String(localized: "Avisar ao passar perto"),
                        note: String(localized: "Uma notificação quando houver uma fonte a menos de 100 m. Ela não diz se a água está correndo."),
                        isOn: $model.proximityAlerts
                    )
                }

                group(String(localized: "Permissões")) {
                    SpecRow(
                        label: String(localized: "Localização"),
                        value: PermissionCopy.location(location.authorization)
                    )
                    if location.authorization == .authorizedAlways
                        || location.authorization == .authorizedWhenInUse {
                        SpecRow(
                            label: String(localized: "Precisão"),
                            value: PermissionCopy.precision(location.accuracy)
                        )
                    }
                    SpecRow(
                        label: String(localized: "Notificações"),
                        value: PermissionCopy.notifications(notifications)
                    )
                    SecondaryButton(title: String(localized: "Abrir Ajustes do iOS")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .padding(.top, 18)
                }

                group(String(localized: "Dados")) {
                    SpecRow(
                        label: String(localized: "Fontes no catálogo"),
                        value: model.fountains.count.formatted()
                    )
                    paragraph(String(localized: "As posições vêm do OpenStreetMap. O estado da água vem só de relatos da comunidade, com data. O Toret não mede nem garante a água."))
                    LinkRow(
                        title: String(localized: "© OpenStreetMap contributors (ODbL)"),
                        url: ExternalLinks.openStreetMapCopyright
                    )
                    LinkRow(
                        title: String(localized: "Dados do tempo por Open-Meteo.com (CC BY 4.0)"),
                        url: ExternalLinks.openMeteo
                    )
                }

                group(String(localized: "Ajuda e privacidade")) {
                    LinkRow(title: String(localized: "Política de privacidade"), url: ExternalLinks.privacy)
                    LinkRow(title: String(localized: "Suporte e contato"), url: ExternalLinks.support)
                }

                group(String(localized: "Sobre")) {
                    SpecRow(label: String(localized: "Versão"), value: AppInfo.versionLine())
                    paragraph(String(localized: "Toret leva o nome dos touros de ferro fundido que dão água a Turim desde o século XIX. Aqui, todas as fontes públicas de beber da cidade são chamadas de fontes. A sua localização fica no aparelho."))
                }

                // The arcade closes the page the way it closes a pavement.
                ArcadeStrip(bays: 9)
                    .frame(height: 64)
                    .padding(.horizontal, 22)
                    .padding(.top, 36)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.carta)
        .task { await refreshNotifications() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await refreshNotifications() } }
        }
        .onChange(of: model.proximityAlerts) {
            // The system prompt is answered a moment after the switch is flipped.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await refreshNotifications()
            }
        }
    }

    private func refreshNotifications() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// A heavy rule, the group's name in poster type, and its rows.
    @ViewBuilder
    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterRule(weight: .heavy)
            Text(title)
                .font(Typo.display(24, 800))
                .foregroundStyle(Palette.inchiostro)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 32)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Typo.ui(14))
            .lineHeight(1.5, font: Typo.uiInterface(14))
            .foregroundStyle(Palette.ink(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { PosterRule(weight: .light) }
    }
}

/// A switch with the title and what it will do, in one row.
struct SettingsToggle: View {
    let title: String
    let note: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typo.ui(16, 700))
                    .foregroundStyle(Palette.inchiostro)
                Text(note)
                    .font(Typo.ui(13))
                    .foregroundStyle(Palette.ink(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(PosterToggleStyle())
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { PosterRule(weight: .light) }
    }
}

/// A row that opens a web page. Blue is the interactive ink, so a link is blue
/// and underlined and nothing else in the app is.
struct LinkRow: View {
    let title: String
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            Text(title)
                .font(Typo.ui(15, 700))
                .foregroundStyle(Palette.blu)
                .underline()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { PosterRule(weight: .light) }
        .accessibilityHint(String(localized: "Abre no navegador"))
        .accessibilityAddTraits(.isLink)
    }
}
