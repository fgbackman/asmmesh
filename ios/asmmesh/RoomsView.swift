// RoomsView.swift — the room list and one room's conversation.

import SwiftUI

struct RoomsView: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: UInt64?

    var body: some View {
        if sizeClass == .regular {
            // iPad: the room list stays in a sidebar beside the open room
            NavigationSplitView {
                RoomList(picked: $picked, split: true)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            } detail: {
                if let id = picked, mesh.rooms.contains(where: { $0.id == id }) {
                    NavigationStack { ChatView(roomID: id).id(id) }
                } else {
                    ContentUnavailableView("No Room Open", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Pick a room on the left."))
                        .background(Theme.bg)
                }
            }
            .onChange(of: mesh.rooms.first?.id, initial: true) { _, first in
                // rooms arrive after the mesh starts; open Main once they do
                if picked == nil { picked = first }
            }
        } else {
            NavigationStack {
                RoomList(picked: $picked, split: false)
                    .navigationDestination(for: UInt64.self) { id in
                        ChatView(roomID: id)
                    }
            }
        }
    }
}

struct RoomList: View {
    @EnvironmentObject var mesh: Mesh
    @Binding var picked: UInt64?
    let split: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card(padding: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.green)
                        Text(mesh.status.isEmpty ? "Starting Bluetooth…" : mesh.status)
                            .font(.footnote)
                            .foregroundStyle(Theme.dim)
                    }
                }
                ForEach(mesh.rooms) { room in
                    if split {
                        Button { picked = room.id } label: {
                            RoomCard(room: room, last: mesh.lines[room.id]?.last?.text,
                                     selected: picked == room.id, chevron: false)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: room.id) {
                            RoomCard(room: room, last: mesh.lines[room.id]?.last?.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.bg)
        .navigationTitle("Rooms")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { am_new_room() } label: { Image(systemName: "plus.circle.fill") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct RoomCard: View {
    let room: Room
    let last: String?
    var selected = false
    var chevron = true

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconBadge(symbol: room.kind.symbol, color: room.kind.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name).font(.headline)
                    Text(last ?? room.kind.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                if room.unread > 0 {
                    Text("\(room.unread)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.orange, in: Capsule())
                        .foregroundStyle(.black)
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
                }
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.orange, lineWidth: 2)
            }
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.dismiss) private var dismiss
    let roomID: UInt64
    @State private var inviting = false
    @FocusState private var typing: Bool

    private var room: Room? { mesh.rooms.first { $0.id == roomID } }
    private var lines: [Line] { mesh.lines[roomID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(lines) { line in
                            LineRow(line: line).id(line.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: lines.last?.id) { _, newID in
                    if let newID { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newID, anchor: .bottom) } }
                }
                .onAppear {
                    if let id = lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(Theme.bg)
        .navigationTitle(room?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let room, room.kind == .main || room.kind == .privateRoom {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { inviting = true } label: { Label("Invite…", systemImage: "person.badge.plus") }
                        if room.kind == .privateRoom {
                            Button(role: .destructive) {
                                mesh.select(room); am_leave_room(); dismiss()
                            } label: { Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right") }
                            Button(role: .destructive) {
                                mesh.select(room); am_delete_room()
                                if !mesh.rooms.contains(where: { $0.id == roomID }) { dismiss() }
                            } label: { Label("Delete for Everyone", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $inviting) {
            InviteSheet { person in
                inviting = false
                if let room { mesh.select(room) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { am_invite(person.id) }
            }
            .environmentObject(mesh)
            .presentationDetents([.medium, .large])
        }
        .onAppear { if let room { mesh.select(room) } }
    }

    private var inputBar: some View {
        let isHome = room?.kind == .home
        return HStack(spacing: 10) {
            if isHome {
                Button { mesh.talk() } label: {
                    Image(systemName: mesh.talking ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(mesh.talking ? Theme.red : Theme.cardHi, in: Circle())
                }
            }
            TextField(isHome ? "Kitchen lights off, batteries, sensors…" : "Message #\(room?.name ?? "")",
                      text: $mesh.input)
                .focused($typing)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { mesh.send() }
            Button { mesh.send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(mesh.input.isEmpty ? Theme.grey : Theme.orange, in: Circle())
            }
            .disabled(mesh.input.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }
}

struct LineRow: View {
    let line: Line
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: 36, alignment: .leading)
            Text(line.text)
                .font(line.system ? .callout : .body)
                .foregroundStyle(line.system ? Theme.dim : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InviteSheet: View {
    @EnvironmentObject var mesh: Mesh
    let pick: (Person) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if mesh.people.isEmpty {
                        Card { Text("Nobody on the mesh yet. Macs running asmmesh nearby appear here.").foregroundStyle(Theme.dim) }
                    }
                    ForEach(mesh.people) { p in
                        Button { pick(p) } label: { PersonCard(person: p) }.buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
