import SwiftUI

/// Ajustes.
///
/// The one setting that matters is the first one: whether the needle is allowed
/// to follow you out of the app onto the lock screen and the home screen. Its
/// caption changes with it, so the consequence of the switch is legible before
/// you flip it rather than after.
struct SettingsScreen: View {
    @Environment(ToretModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Toret · Torino")
                        DisplayText(
                            "Ajustes", size: 40, leading: 1,
                            tracking: Typo.tracking(-0.015, at: 40)
                        )
                        .padding(.top, 8)
                        LozengeTicks().padding(.top, 16)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                    section("Bússola") {
                        SettingsToggle(
                            title: "Bússola sempre visível",
                            note: model.compassAlwaysVisible
                                ? "Na tela bloqueada e no widget"
                                : "Só dentro do app",
                            isOn: $model.compassAlwaysVisible
                        )
                        SettingsToggle(
                            title: "Avisar ao passar perto",
                            note: "Uma notificação quando houver água a menos de 100 m",
                            isOn: $model.proximityAlerts
                        )
                    }

                    section("Dados") {
                        SpecRow(label: "Origem", value: "Comune di Torino")
                        SpecRow(label: "Verificação", value: "Comunidade")
                        SpecRow(label: "Fontes catalogadas", value: "\(model.fountains.count)")
                    }

                    section("Sobre") {
                        SpecRow(label: "Idioma da interface", value: "Português (Brasil)")
                        SpecRow(label: "Topônimos", value: "Italiano")
                        SpecRow(label: "Versão", value: "1.0")
                    }

                    colophon
                }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.paper)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Typo.narrow(9.5))
                .tracking(Typo.tracking(0.14, at: 9.5))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .padding(.bottom, 6)
            VStack(spacing: 0) { content() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
    }

    private var colophon: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArcadeCornice(height: 11, stroke: Palette.ink.opacity(0.18))
            Text("Toret leva o nome dos touros de ferro fundido que dão água a Turim desde o século XIX. Na interface eles são chamados de fontes.")
                .font(Typo.ui(12.5))
                .lineHeight(1.6, font: Typo.uiInterface(12.5))
                .foregroundStyle(Palette.ink.opacity(0.55))
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
    }
}

struct SettingsToggle: View {
    let title: String
    let note: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typo.ui(15, 500))
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .font(Typo.ui(12))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.green)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
        }
    }
}
