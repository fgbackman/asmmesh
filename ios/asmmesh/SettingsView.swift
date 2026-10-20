// SettingsView.swift — connect home services, the mesh passphrase, and a switch for
// every integration (all off until you turn them on, as on the Mac).

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mesh: Mesh

    // Mac-only switches (FM radio, web gateway, webhook, files page) aren't shown here.
    private let macOnly: Set<Int> = [15, 16, 21, 22]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    SectionTitle(text: "Connect")
                    VStack(spacing: 0) {
                        ConnectRow(title: "Hue Bridge", subtitle: "Press its button, then tap", symbol: "lightbulb.fill", color: Theme.orange) { am_pair_hue() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "SmartThings", subtitle: "Paste a personal access token", symbol: "square.grid.2x2.fill", color: Theme.blue) { am_connect_st() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "Home Assistant", subtitle: "Address and long-lived token", symbol: "house.circle.fill", color: Theme.purple) { am_connect_ha() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "LIFX", subtitle: "Cloud token", symbol: "lightbulb.led.fill", color: Theme.red) { am_connect_lifx() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "Govee", subtitle: "API key", symbol: "light.strip.2.fill", color: Color(red: 0.39, green: 0.82, blue: 1)) { am_connect_govee() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "Refresh home devices", subtitle: "Ask every connected service again", symbol: "arrow.clockwise", color: Theme.grey) { am_refresh_home() }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    SectionTitle(text: "Privacy")
                    ConnectRow(title: "Mesh passphrase", subtitle: "Encrypts rooms and commands between devices that share it", symbol: "key.fill", color: Theme.yellow) { am_mesh_pass() }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    SectionTitle(text: "Services")
                    ForEach(mesh.services.filter { !macOnly.contains($0.id) }) { s in
                        Card(padding: 14) {
                            HStack(spacing: 14) {
                                IconBadge(symbol: s.symbol, color: s.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.headline)
                                    Text(s.subtitle).font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(get: { s.on }, set: { mesh.setService(s, on: $0) }))
                                    .labelsHidden()
                                    .tint(Theme.green)
                            }
                        }
                    }
                    Text("asmmesh for iPhone · the same mesh as your Macs")
                        .font(.caption).foregroundStyle(Theme.dim)
                        .padding(.top, 8)
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .navigationTitle("Settings")
            .onAppear { mesh.loadServices() }
        }
    }
}

struct ConnectRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(symbol: symbol, color: color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
