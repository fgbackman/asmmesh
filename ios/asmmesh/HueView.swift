// HueView.swift — Settings › Philips Hue: the bridges (up to four), pairing them, adding
// one by its address, and adding lights by the serial printed on the bulb. Everything is
// done by the same Home commands the Mac takes ("pair hue", "add hue light 1A2B3C on 2",
// "hue bridge 192.168.1.20", "forget hue bridge 2"), so what the core says shows in Home.

import SwiftUI

struct HueView: View {
    @EnvironmentObject var mesh: Mesh
    @State private var bridges: [Mesh.HueBridge] = []
    @State private var serials = ""
    @State private var address = ""
    @State private var target = 1               // which bridge new lights go to
    @State private var forgetting: Mesh.HueBridge?
    @State private var sent: String?
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var paired: [Mesh.HueBridge] { bridges.filter(\.paired) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionTitle(text: "Bridges")
                if bridges.isEmpty {
                    Card {
                        Text("No Hue Bridge found yet. Make sure Hue is switched on in Settings and this iPhone is on the bridge's Wi-Fi, or add one by its address below.")
                            .font(.callout).foregroundStyle(Theme.dim)
                    }
                }
                ForEach(bridges) { b in
                    Card(padding: 14) {
                        HStack(spacing: 14) {
                            IconBadge(symbol: "lightbulb.fill", color: b.paired ? Theme.orange : Theme.grey, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(b.id). \(b.name)").font(.headline)
                                Text(b.paired ? "\(b.host) · connected" : "\(b.host) · press its button, then Pair")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button(role: .destructive) { forgetting = b } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if bridges.contains(where: { !$0.paired }) {
                    wideButton("Pair", symbol: "link") { run("pair hue") }
                }

                SectionTitle(text: "Add a bridge by its address")
                Card(padding: 14) {
                    HStack(spacing: 10) {
                        TextField("192.168.1.20", text: $address)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") { run("hue bridge \(address)"); address = "" }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Text("An old round (v1) bridge, or one this iPhone can't find by itself (iOS limits searching the network). Your router lists its address.")
                    .font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                SectionTitle(text: "Add lights")
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        if paired.count > 1 {
                            Picker("To bridge", selection: $target) {
                                ForEach(paired) { b in Text("\(b.id). \(b.name)").tag(b.id) }
                            }
                        }
                        HStack(spacing: 10) {
                            TextField("Serial, e.g. 1A2B3C", text: $serials)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Button("Add") { add(serials); serials = "" }
                                .disabled(paired.isEmpty || serials.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Button { add("") } label: {
                            Label("Search for new lights", systemImage: "magnifyingglass")
                        }
                        .disabled(paired.isEmpty)
                    }
                }
                Text("The serial is the 6 letters and digits printed on the bulb or its label (up to 10, spaces between). Keep the light on and near the bridge; about a minute later Home says what was found.")
                    .font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if let sent {
                    Text("Sent “\(sent)”: see Home for the answer.")
                        .font(.caption).foregroundStyle(Theme.green)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }
            .padding()
            .readableWidth()
        }
        .background(Theme.bg)
        .navigationTitle("Philips Hue")
        .onAppear(perform: load)
        .onReceive(tick) { _ in load() }
        .confirmationDialog("Forget this Hue Bridge?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { b in
            Button("Forget \(b.name)", role: .destructive) { run("forget hue bridge \(b.id)") }
        } message: { _ in
            Text("Its lights and rooms leave the lists. If it's still on the network it will be found again, unpaired.")
        }
    }

    private func wideButton(_ title: String, symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func load() {
        bridges = mesh.hueBridges()
        if !paired.contains(where: { $0.id == target }), let first = paired.first { target = first.id }
    }

    private func add(_ text: String) {
        let what = text.trimmingCharacters(in: .whitespaces)
        var command = what.isEmpty ? "add hue lights" : "add hue light \(what)"
        if paired.count > 1 { command += " on \(target)" }
        run(command)
    }

    private func run(_ command: String) {
        mesh.home(command)
        sent = command
        coreLater(after: 1.5) { load() }
    }
}
