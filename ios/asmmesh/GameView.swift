// GameView.swift — Ninefold on the iPhone: the board above the game room's conversation, the
// card on the room list, and the sheet that starts a game. The core (nf_mesh.s) has the game
// and decides everything; these only show it and type into the game room for you.

import SwiftUI

/// Above the game room's conversation: the status, the tiles, your words, the results
struct GameBoard: View {
    @EnvironmentObject var mesh: Mesh

    var body: some View {
        let g = mesh.game
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill").foregroundStyle(Theme.orange)
                Text(g.status)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            switch g.state {
            case 1: lobby(g)
            case 2, 3, 4: board(g)
            case 5: results(g)
            default: EmptyView()
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder private func lobby(_ g: Game) -> some View {
        Text(g.host ? "When everyone you invited has joined, start the game. More people: Invite… in the \u{22EF} menu."
                    : "Waiting for the host to start the game.")
            .font(.callout)
        if g.host {
            Button { mesh.gameSay("start") } label: {
                Label("Start Game", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
        }
    }

    @ViewBuilder private func board(_ g: Game) -> some View {
        let typed = mesh.input.uppercased()
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { col in
                        tile(g, row * 3 + col, typed)
                    }
                }
            }
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        if !g.last.isEmpty {
            Text(g.last).font(.callout.weight(.semibold))
                .foregroundStyle(g.last.hasPrefix("\u{2713}") ? Theme.green : Theme.dim)
                .frame(maxWidth: .infinity)
        }
        HStack(spacing: 10) {
            Button { coreLater { nf_shuffle() } } label: { Label("Shuffle", systemImage: "shuffle") }
            Button { if !mesh.input.isEmpty { mesh.input.removeLast() } } label: {
                Label("Delete", systemImage: "delete.left")
            }
            .disabled(mesh.input.isEmpty)
            Button { mesh.input = "" } label: { Label("Clear", systemImage: "xmark.circle") }
                .disabled(mesh.input.isEmpty)
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .frame(maxWidth: .infinity)
        if !g.mine.isEmpty {
            Text("Yours (\(g.mine.count)): " + g.mine.joined(separator: " "))
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.dim)
                .lineLimit(4)
        }
        if g.players.count > 1 {
            Text(g.players.map { "\($0.name) \($0.words)" }.joined(separator: " \u{00B7} "))
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
    }

    /// One tile: tap it to type its letter; dimmed once the word typed uses it
    private func tile(_ g: Game, _ i: Int, _ typed: String) -> some View {
        let letter = i < g.tiles.count ? g.tiles[i] : " "
        let nth = g.tiles.prefix(i + 1).filter { $0 == letter }.count     // the nth tile of its letter
        let used = typed.filter { String($0) == letter }.count >= nth
        let centre = i == 4
        return Button {
            if g.playing && !used { mesh.input += letter.lowercased() }
        } label: {
            Text(letter)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(centre ? Color.black : Color.primary)
                .background(centre ? Theme.orange : Theme.cardHi,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(used || !g.playing ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(centre ? "\(letter), the centre letter" : letter)
    }

    @ViewBuilder private func results(_ g: Game) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(g.results.enumerated()), id: \.offset) { k, line in
                    Text(line)
                        .font(k == 0 ? .callout.weight(.semibold) : .footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 220)
        let over = g.results.last?.hasPrefix("Game over") ?? false
        if over {
            Button { mesh.gameSay("start") } label: {
                Label("Play Again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
        } else if g.host {
            Button { mesh.gameSay("start") } label: {
                Label("Next Round Now", systemImage: "forward.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// The game, full screen: comes up by itself (a game made or joined, every round)
struct GameScreen: View {
    @EnvironmentObject var mesh: Mesh
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView { GameBoard() }
                .background(Theme.bg)
                .safeAreaInset(edge: .bottom) { if mesh.game.playing { wordBar } }
                .navigationTitle("Ninefold")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { mesh.showGame = false }
                    }
                }
                .onChange(of: mesh.game.playing, initial: true) { _, on in typing = on }
        }
    }

    private var wordBar: some View {
        HStack(spacing: 10) {
            TextField("Type a word", text: $mesh.input)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { submit() }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { submit() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(mesh.input.isEmpty ? Theme.grey : Theme.orange, in: Circle())
            }
            .disabled(mesh.input.isEmpty)
        }
        .padding()
        .background(Theme.bg)
    }

    private func submit() {
        let word = mesh.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        mesh.input = ""
        mesh.gameSay(word)
        typing = true
    }
}

/// On the room list while a game is on: what it's doing, and the way in
struct GameCard: View {
    let game: Game
    let name: String

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                IconBadge(symbol: "square.grid.3x3.fill", color: Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(game.status).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Start a game: who to invite, how many rounds, how long, the family filter
struct NinefoldSheet: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<Int> = []
    @State private var rounds = 3
    @State private var minutes = 4
    @State private var family = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    if mesh.people.isEmpty {
                        Text("Nobody on the mesh yet. People running asmmesh nearby appear here.")
                            .foregroundStyle(Theme.dim)
                    }
                    ForEach(mesh.people) { p in
                        Button {
                            if picked.contains(p.id) { picked.remove(p.id) } else if picked.count < 11 { picked.insert(p.id) }
                        } label: {
                            HStack {
                                Text(p.name).foregroundStyle(.primary)
                                Text(p.whereText).font(.caption).foregroundStyle(Theme.dim)
                                Spacer()
                                if picked.contains(p.id) { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                            }
                        }
                    }
                }
                Section("Game") {
                    Stepper("\(rounds) round\(rounds == 1 ? "" : "s")", value: $rounds, in: 1...5)
                    Picker("Minutes a round", selection: $minutes) {
                        Text("2 min").tag(2)
                        Text("4 min").tag(4)
                        Text("8 min").tag(8)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Family filter", isOn: $family)
                }
                Section {
                    Text("Nine letters; words of 4 to 9 letters, each using the centre one. Everyone\u{2019}s words stay hidden until the round ends, and only the people you invite see the game.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Play Ninefold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { create() }.disabled(picked.isEmpty)
                }
            }
        }
    }

    private func create() {
        let ids = picked.sorted()
        let r = rounds, m = minutes, f = family ? 1 : 0
        dismiss()
        coreLater(after: 0.4) {
            ids.withUnsafeBufferPointer { _ = am_nf_new($0.baseAddress, ids.count, r, m, f) }
            Mesh.shared.roomsChanged()
            Mesh.shared.gameChanged()
        }
    }
}
