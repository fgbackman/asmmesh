import SwiftUI

// Fivefold (ff_mesh.s): guess a five-letter word in six tries. Amber is the right letter in
// the right place, blue is in the word somewhere else, dark is not in it. Today's word alone,
// a race (the same word for everyone in a room) or a duel (each picks the other's word).

/// Fivefold's colours: 0 not in it, 1 elsewhere, 2 right place, 3 sent (no answer yet)
enum FiveColour {
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.18)
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let dark = Color(red: 0.23, green: 0.23, blue: 0.24)
    static let sent = Color(red: 0.35, green: 0.35, blue: 0.37)
    static let empty = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let key = Color(red: 0.43, green: 0.43, blue: 0.45)

    static func of(_ c: Int) -> Color {
        switch c { case 0: return dark; case 1: return blue; case 2: return amber; case 3: return sent
        default: return empty }
    }
}

/// The full-screen game
struct FivefoldScreen: View {
    @EnvironmentObject var mesh: Mesh
    @State private var typed = ""
    @State private var why = ""
    @State private var shake = 0

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        let f = mesh.fivefold
        NavigationStack {
            VStack(spacing: 12) {
                Text(f.status)
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                if !why.isEmpty {
                    Text(why).font(.footnote).foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                grid(f)
                if !f.others.isEmpty {
                    Text(f.others)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 4)
                keyboard(f)
            }
            .padding()
            .background(Theme.bg)
            .navigationTitle(title(f))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { mesh.showFivefold = false } }
                if f.state == 3 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { coreLater { am_home("fivefold share") } } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private func title(_ f: Fivefold) -> String {
        switch f.mode { case 2: return "Fivefold Race"; case 3: return "Fivefold Duel"; default: return "Fivefold" }
    }

    // six rows of five; the first empty row shows what's being typed
    private func grid(_ f: Fivefold) -> some View {
        let typingRow = (0..<6).first { r in f.cells[r * 5] == 0 } ?? -1
        return VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { c in
                        let cell = f.cells[r * 5 + c]
                        if cell != 0 {
                            tile(letter: cell >> 8, colour: cell & 0xFF)
                        } else if r == typingRow, c < typed.count, f.state == 2 {
                            let ch = typed[typed.index(typed.startIndex, offsetBy: c)]
                            tile(letter: Int(ch.asciiValue ?? 32), colour: 5)
                        } else {
                            tile(letter: 0, colour: 4)
                        }
                    }
                }
                .modifier(Shake(amount: r == typingRow ? CGFloat(shake) : 0))
            }
        }
        .frame(maxWidth: 340)
    }

    private func tile(letter: Int, colour: Int) -> some View {
        let s = letter > 0 ? String(UnicodeScalar(UInt8(letter))).uppercased() : ""
        return Text(s)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(colour == 5 ? FiveColour.empty : FiveColour.of(colour)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(colour >= 4 ? Color(white: colour == 5 ? 0.55 : 0.28) : .clear, lineWidth: 2))
            .animation(.easeInOut(duration: 0.25), value: colour)
    }

    private func keyboard(_ f: Fivefold) -> some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 5) {
                    if i == 2 { wideKey("Enter") { enter() } }
                    ForEach(Array(rows[i]), id: \.self) { ch in
                        let k = f.keys[Int(ch.asciiValue! - 97)]
                        Button { type(ch) } label: {
                            Text(String(ch).uppercased())
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(k == 3 ? FiveColour.key : FiveColour.of(k)))
                        }
                        .buttonStyle(.plain)
                    }
                    if i == 2 { wideKey("\u{232B}") { if !typed.isEmpty { typed.removeLast() } } }
                }
            }
        }
        .disabled(f.state == 3)
    }

    private func wideKey(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 58, height: 46)
                .background(RoundedRectangle(cornerRadius: 5).fill(FiveColour.key))
        }
        .buttonStyle(.plain)
    }

    private func type(_ ch: Character) {
        why = ""
        if typed.count < 5 { typed.append(ch) }
    }

    private func enter() {
        let word = typed
        guard !word.isEmpty else { return }
        coreLater {
            let r = word.withCString { am_ff_try($0) }
            if r < 0 {
                if let p = am_ff_why(r) {
                    why = String(cString: p).replacingOccurrences(of: "\u{00B7} ", with: "")
                }
                withAnimation(.linear(duration: 0.3)) { shake += 1 }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                typed = ""
                why = ""
            }
            Mesh.shared.fivefoldChanged()
        }
    }
}

/// A row shakes when its guess didn't count
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

/// Rooms › Fivefold: today's word, a race or a duel
struct FivefoldSheet: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 1
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Play", selection: $mode) {
                        Text("Today").tag(1)
                        Text("Race").tag(2)
                        Text("Duel").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Text(explain).font(.footnote).foregroundStyle(Theme.dim)
                }
                if mode != 1 {
                    Section(mode == 2 ? "Race with" : "Duel with") {
                        if mesh.people.isEmpty {
                            Text("Nobody on the mesh yet. People running asmmesh nearby appear here.")
                                .foregroundStyle(Theme.dim)
                        }
                        ForEach(mesh.people) { p in
                            Button { pick(p.name) } label: {
                                HStack {
                                    Text(p.name).foregroundStyle(.primary)
                                    Text(p.whereText).font(.caption).foregroundStyle(Theme.dim)
                                    Spacer()
                                    if picked.contains(p.name) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fivefold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == 1 ? "Play" : "Invite") { start() }
                        .disabled(mode != 1 && picked.isEmpty)
                }
            }
        }
    }

    private var explain: String {
        switch mode {
        case 2: return "Everyone gets the same word. You see each other\u{2019}s colours as you go, never the letters."
        case 3: return "Each of you picks a five-letter word for the other. Both are sealed until the end, then every answer is checked."
        default: return "Today\u{2019}s word, the same for everyone. Six tries. Share your squares (never the word) afterwards."
        }
    }

    private func pick(_ name: String) {
        if mode == 3 { picked = [name]; return }
        if picked.contains(name) { picked.remove(name) } else if picked.count < 7 { picked.insert(name) }
    }

    private func start() {
        dismiss()
        if mode == 1 {
            coreLater(after: 0.4) { am_ff_solo() }
            return
        }
        let line = (mode == 2 ? "fivefold race with " : "fivefold duel with ") + picked.sorted().joined(separator: ", ")
        coreLater(after: 0.4) {
            line.withCString { am_home($0) }
            Mesh.shared.roomsChanged()
        }
    }
}
