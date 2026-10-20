// SpinView.swift — the SPIN remote, set up as on the Mac: a profile per colour, each
// with a name, a switch, its devices and what each of the 19 gestures does.

import SwiftUI

private enum Spin {
    static func get(_ what: Int, _ i: Int = 0, _ s: Int = 0) -> Int { am_spin_get(what, i, s) }
    static func str(_ what: Int, _ i: Int = 0, _ s: Int = 0) -> String { cstr(am_spin_get(what, i, s)) }
    static func set(_ what: Int, _ i: Int = 0, _ s: Int = 0, value: Int = 0, text: String? = nil) {
        if let text {
            text.withCString { am_spin_set(what, i, s, value, $0) }
        } else {
            am_spin_set(what, i, s, value, nil)
        }
    }
    static func color(_ i: Int) -> Color {
        let v = get(2, i)
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
    static let commandAction = 17
}

struct SpinView: View {
    @State private var profile = 0
    @State private var name = ""
    @State private var devices = ""
    @State private var texts: [Int: String] = [:]
    @State private var version = 0          // bumped after every change, to re-read

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { _ in
            ScrollView {
                VStack(spacing: 12) {
                    statusCard
                    profilePicker
                    profileCard
                    SectionTitle(text: "Gestures")
                    gestures
                    Text("Double-tap the SPIN (or swipe left and right) to move between the profiles that are in use; the ring turns that profile's colour.")
                        .font(.caption).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 4)
                }
                .padding()
                .readableWidth()
            }
        }
        .background(Theme.bg)
        .navigationTitle("SPIN Remote")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    // MARK: pieces

    private var statusCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: Spin.get(14) != 0 ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Spin.get(14) != 0 ? Theme.green : Theme.dim)
                    Text(Spin.get(14) != 0 ? "SPIN linked" : "Wake the SPIN to link it")
                        .font(.subheadline)
                    Spacer()
                    let last = Spin.get(16)
                    if last >= 0 {
                        Text(Spin.str(7, 0, last)).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Toggle("Remote on", isOn: Binding(get: { Spin.get(13) == 0 },
                                                  set: { Spin.set(7, value: $0 ? 0 : 1); version += 1 }))
                Toggle("Test mode (gestures light up, nothing happens)",
                       isOn: Binding(get: { Spin.get(12) != 0 },
                                     set: { Spin.set(6, value: $0 ? 1 : 0); version += 1 }))
            }
            .tint(Theme.green)
        }
    }

    private var profilePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<Spin.get(0), id: \.self) { i in
                    Button {
                        profile = i
                        Spin.set(0, i)
                        load()
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Spin.color(i))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: profile == i ? 3 : 0))
                                .overlay {
                                    if Spin.get(15) == i {
                                        Image(systemName: "hand.point.up.fill").font(.caption).foregroundStyle(.black)
                                    }
                                }
                                .opacity(Spin.get(4, i) != 0 ? 1 : 0.35)
                            Text(title(i)).font(.caption2).lineLimit(1).frame(width: 64)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var profileCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use this profile", isOn: Binding(get: { Spin.get(4, profile) != 0 },
                                                         set: { Spin.set(1, profile, value: $0 ? 1 : 0); load() }))
                    .tint(Spin.color(profile))
                TextField("Name (\(Spin.str(1, profile)))", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { Spin.set(2, profile, text: name); load() }
                Text("Devices").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                TextField("Kitchen lamp, Desk lamp", text: $devices)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { Spin.set(3, profile, text: devices); load() }
                Text("Spin, the top button and swipes up and down act on these. Names as in “list devices”.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private var gestures: some View {
        VStack(spacing: 0) {
            ForEach(0..<Spin.get(6), id: \.self) { s in
                let action = Spin.get(10, profile, s)
                let lit = Spin.get(16) == s
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Spin.str(7, 0, s)).font(.subheadline)
                        Spacer()
                        Menu {
                            ForEach(0..<Spin.get(8), id: \.self) { a in
                                Button(Spin.str(9, a)) {
                                    Spin.set(4, profile, s, value: a)
                                    version += 1
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(Spin.str(9, action))
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                        }
                    }
                    if action == Spin.commandAction {
                        TextField("A command, e.g. good night", text: Binding(
                            get: { texts[s] ?? Spin.str(11, profile, s) },
                            set: { texts[s] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit {
                                Spin.set(5, profile, s, text: texts[s] ?? "")
                                version += 1
                            }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(lit ? Spin.color(profile).opacity(0.25) : .clear)
                if s < Spin.get(6) - 1 { Divider().overlay(Theme.bg) }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: helpers

    private func title(_ i: Int) -> String {
        let n = Spin.str(3, i)
        return n.isEmpty ? Spin.str(1, i).capitalized : n
    }

    private func load() {
        name = Spin.str(3, profile)
        devices = Spin.str(5, profile)
        texts = [:]
        version += 1
    }
}
