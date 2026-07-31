import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var viewObject: viewObject

    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showCountdownsUnder1h") private var showCountdownsUnder1h = false
    @AppStorage("showLocalTransitCountdowns") private var showLocalTransitCountdowns = false
    @AppStorage("usUnits") private var usUnits = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 24)

                SettingsSectionTitle("Preferences")

                SettingsToggleRow(
                    title: "Show seconds",
                    description: "Show seconds in departure times, countdowns, and delay differences.",
                    isOn: $showSeconds
                )

                SettingsToggleRow(
                    title: "Show train countdowns under 1 hour",
                    description: "Show a live countdown for rail departures less than one hour away.",
                    isOn: $showCountdownsUnder1h
                )

                SettingsToggleRow(
                    title: "Show countdowns for local transit",
                    description: "Show live countdowns for metro, tram, bus, and other local departures.",
                    isOn: $showLocalTransitCountdowns
                )

                SettingsToggleRow(
                    title: "Use imperial units",
                    description: "Display distances in miles and feet instead of kilometres and metres.",
                    isOn: $usUnits
                )

                Divider()
                    .padding(.vertical, 16)

                SettingsSectionTitle("Map")

                Button {
                    viewObject.showLayerSelector = true
                } label: {
                    Label("Open map layer settings", systemImage: "square.3.layers.3d")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.tint)
            .padding(.bottom, 8)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
