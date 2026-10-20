// SettingsView.swift — connect home services, the mesh passphrase, and a switch for
// every integration (all off until you turn them on, as on the Mac).

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mesh: Mesh
    @State private var showSpin = UserDefaults.standard.bool(forKey: "spin")   // "-spin YES"

    // Mac-only switches: FM radio (a transmitter on the headphone jack, an RTL-SDR
    // stick) and the web gateway (it fetches pages with curl).
    private let macOnly: Set<Int> = [15, 16]

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
                        ConnectRow(title: "Nanoleaf", subtitle: "Hold its power button 5 s, then tap", symbol: "hexagon.fill", color: Theme.green) { am_pair_nano() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "Refresh home devices", subtitle: "Ask every connected service again", symbol: "arrow.clockwise", color: Theme.grey) { am_refresh_home() }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    SectionTitle(text: "Remote")
                    NavigationLink(isActive: $showSpin) {
                        SpinView()
                    } label: {
                        HStack(spacing: 14) {
                            IconBadge(symbol: "dial.medium.fill", color: Theme.orange, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SPIN remote").font(.headline).foregroundStyle(.primary)
                                Text("Profiles, devices and what each gesture does").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    SectionTitle(text: "Share")
                    VStack(spacing: 0) {
                        ConnectRow(title: "Files on Wi-Fi", subtitle: "A web page other phones open: asmmesh's folder in Files", symbol: "folder.fill", color: Theme.blue) { mesh.home("files") }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "AirDrop a file", subtitle: "Pick files, then share them", symbol: "airplayaudio", color: Theme.purple) { am_airdrop() }
                        Divider().overlay(Theme.bg)
                        ConnectRow(title: "Webhook", subtitle: "An address Shortcuts or IFTTT can post into a room", symbol: "link", color: Theme.grey) { mesh.home("webhook") }
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
                    Text("asmmesh for iPhone and iPad · the same mesh as your Macs")
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
