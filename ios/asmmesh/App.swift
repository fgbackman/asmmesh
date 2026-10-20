// App.swift — asmmesh for iPhone: four tabs over the same mesh as the Macs.

import SwiftUI

enum Theme {
    static let bg = Color(red: 0.07, green: 0.075, blue: 0.08)
    static let card = Color(red: 0.135, green: 0.14, blue: 0.15)
    static let cardHi = Color(red: 0.18, green: 0.185, blue: 0.2)
    static let dim = Color(white: 0.62)
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let purple = Color(red: 0.75, green: 0.35, blue: 0.95)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.04)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let grey = Color(red: 0.6, green: 0.6, blue: 0.62)
}

@main
struct AsmmeshApp: App {
    @StateObject private var mesh = Mesh.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mesh)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
                .fontDesign(.rounded)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var mesh: Mesh

    var body: some View {
        TabView {
            RoomsView()
                .tabItem { Label("Rooms", systemImage: "bubble.left.and.bubble.right.fill") }
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2.fill") }
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "dot.radiowaves.left.and.right") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .onAppear {
            // after the first frame, so a prompt (Keychain, Bluetooth) has a screen to sit on
            DispatchQueue.main.async { mesh.start() }
        }
    }
}

// MARK: - Shared pieces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
