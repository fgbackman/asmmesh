// ChessView.swift — chess on the iPhone: the board full screen (tap a piece of yours, its
// moves light up, tap one to play it), the status and the moves so far, Resign and Offer
// Draw; and the sheet that starts a game with someone on the mesh. The core (ch_mesh.s)
// checks every move and sends it; this only shows the game and passes taps on.

import SwiftUI

struct ChessScreen: View {
    @EnvironmentObject var mesh: Mesh
    @State private var picked: Int?
    @State private var targets: Set<Int> = []
    @State private var confirmResign = false

    var body: some View {
        let c = mesh.chess
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(c.status)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    board(c)
                    if !c.moves.isEmpty {
                        Text(c.moves)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if c.state == 2 {
                        HStack(spacing: 12) {
                            Button(role: .destructive) { confirmResign = true } label: {
                                Label("Resign", systemImage: "flag.fill").frame(maxWidth: .infinity)
                            }
                            Button { coreLater { am_ch_say("draw") } } label: {
                                Label("Offer Draw", systemImage: "equal.circle").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle(c.opponent.isEmpty ? "Chess" : "Chess with \(c.opponent)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { mesh.showChess = false } }
            }
            .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
                Button("Resign", role: .destructive) { coreLater { am_ch_say("resign") } }
            }
        }
    }

    /// The 8×8 board from our side: rank 8 on top for white, rank 1 for black
    private func board(_ c: Chess) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        square(c, c.black ? row * 16 + (7 - col) : (7 - row) * 16 + col)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func square(_ c: Chess, _ sq: Int) -> some View {
        let dark = ((sq >> 4) + (sq & 7)) % 2 == 0
        let last = c.last >= 0 && (sq == c.last & 0xFF || sq == (c.last >> 8) & 0xFF)
        let colour = squareColour(sq, dark: dark, last: last)
        return Button { tap(sq) } label: {
            ZStack {
                colour
                Self.piece(c.pieces[sq])
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(sq) + " " + Self.pieceName(c.pieces[sq]))
    }

    private func squareColour(_ sq: Int, dark: Bool, last: Bool) -> Color {
        if picked == sq { return Color(red: 0.96, green: 0.96, blue: 0.41) }
        if targets.contains(sq) { return Color(red: 0.73, green: 0.79, blue: 0.27) }
        if last { return dark ? Color(red: 0.67, green: 0.64, blue: 0.23) : Color(red: 0.80, green: 0.82, blue: 0.42) }
        return dark ? Color(red: 0.46, green: 0.59, blue: 0.34) : Color(red: 0.93, green: 0.93, blue: 0.82)
    }

    private func tap(_ sq: Int) {
        if let from = picked, targets.contains(sq) {
            picked = nil; targets = []
            coreLater { _ = am_ch_move(from, sq) }
            return
        }
        var out = [UInt8](repeating: 0, count: 32)
        let n = am_ch_targets(sq, &out)
        if n > 0 { picked = sq; targets = Set(out.prefix(n).map { Int($0) }) } else { picked = nil; targets = [] }
    }

    /// The solid figure for both sides (U+FE0E: as text, never the pawn's emoji), white with
    /// a dark outline or black with a light one, and a drop shadow
    @ViewBuilder static func piece(_ p: Int) -> some View {
        let g = glyph(p)
        if !g.isEmpty {
            let black = p & 8 != 0
            let edge: Color = black ? Color(white: 0.85) : Color(white: 0.08)
            Text(g)
                .font(.system(size: 36, weight: .black))
                .minimumScaleFactor(0.4)
                .foregroundStyle(black ? Color.black : Color.white)
                .shadow(color: edge, radius: 0, x: 1, y: 0)      // an outline, from four sides
                .shadow(color: edge, radius: 0, x: -1, y: 0)
                .shadow(color: edge, radius: 0, x: 0, y: 1)
                .shadow(color: edge, radius: 0, x: 0, y: -1)
                .shadow(color: .black.opacity(0.55), radius: 3, x: 1.5, y: 2.5)
        }
    }

    static func glyph(_ p: Int) -> String {
        let solid = ["", "\u{265F}", "\u{265E}", "\u{265D}", "\u{265C}", "\u{265B}", "\u{265A}", ""][p & 7]
        return solid.isEmpty ? "" : solid + "\u{FE0E}"
    }
    static func name(_ sq: Int) -> String {
        String(UnicodeScalar(UInt8(97 + (sq & 7)))) + String((sq >> 4) + 1)
    }
    static func pieceName(_ p: Int) -> String {
        let kinds = ["empty", "pawn", "knight", "bishop", "rook", "queen", "king"]
        let k = p & 7
        if k == 0 || k == 7 { return "empty" }
        return (p & 8 != 0 ? "black " : "white ") + kinds[k]
    }
}

/// Start a game with someone on the mesh (with a bitchat person: "chess" in your chat)
struct ChessSheet: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Person?
    @State private var black = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Play with") {
                    if mesh.people.isEmpty {
                        Text("Nobody on the mesh yet. People running asmmesh nearby appear here.")
                            .foregroundStyle(Theme.dim)
                    }
                    ForEach(mesh.people) { p in
                        Button { picked = p } label: {
                            HStack {
                                Text(p.name).foregroundStyle(.primary)
                                Text(p.whereText).font(.caption).foregroundStyle(Theme.dim)
                                Spacer()
                                if picked?.id == p.id { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                            }
                        }
                    }
                }
                Section {
                    Picker("You play", selection: $black) {
                        Text("White").tag(false)
                        Text("Black").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Every move is checked on both phones, and only the two of you see the game. To play someone on bitchat, type chess in your private chat with them: they type their moves back.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Play Chess")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        guard let p = picked else { return }
                        let line = "chess with \(p.name)" + (black ? " black" : "")
                        dismiss()
                        coreLater(after: 0.4) {
                            line.withCString { am_home($0) }
                            Mesh.shared.roomsChanged()
                        }
                    }
                    .disabled(picked == nil)
                }
            }
        }
    }
}
