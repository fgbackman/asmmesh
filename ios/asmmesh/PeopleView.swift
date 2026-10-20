// PeopleView.swift — you, and everyone the mesh has heard from.

import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var mesh: Mesh

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        HStack(spacing: 14) {
                            IconBadge(symbol: "iphone", color: Theme.orange, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mesh.nick.isEmpty ? "…" : mesh.nick).font(.title3.weight(.bold))
                                Text("Your key \(mesh.myFingerprint)")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button("Rename") { am_change_name() }
                                .buttonStyle(.bordered)
                        }
                    }
                    SectionTitle(text: "On the mesh")
                    if mesh.people.isEmpty {
                        Card {
                            Text("Nobody yet. Macs and phones running asmmesh within Bluetooth range show up here; messages hop through them to reach everyone else.")
                                .font(.callout)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    ForEach(mesh.people) { p in
                        PersonCard(person: p) {
                            Button {
                                am_select_room(0)        // from Main: a room for the two of you
                                am_invite(p.id)
                            } label: {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .background(Theme.cardHi, in: Circle())
                            }
                        }
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .navigationTitle("People")
        }
    }
}

struct PersonCard<Accessory: View>: View {
    let person: Person
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(person.age > 120 ? Theme.grey : (person.hops <= 1 ? Theme.green : Theme.orange))
                    Text(String(person.name.prefix(1)).uppercased())
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.headline)
                    Text("\(person.whereText) · \(person.fingerprint)")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                accessory
            }
        }
    }
}

extension PersonCard where Accessory == EmptyView {
    init(person: Person) {
        self.person = person
        self.accessory = EmptyView()
    }
}
