// App.swift — asmmesh for iPhone and iPad: four tabs over the same mesh as the Macs.

import SwiftUI
import UniformTypeIdentifiers
import CoreImage

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
    // "-tab 2" on the command line opens on that tab (for screenshots)
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        TabView(selection: $tab) {
            RoomsView()
                .tabItem { Label("Rooms", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(0)
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2.fill") }
                .tag(1)
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "dot.radiowaves.left.and.right") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .onAppear {
            // after the first frame, so a prompt (Keychain, Bluetooth) has a screen to sit on
            DispatchQueue.main.async { mesh.start() }
        }
        .sheet(item: $mesh.qrText) { qr in
            QRSheet(text: qr.text)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $mesh.pickingFiles, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty { shareFiles(urls) }
        }
    }

    /// The share sheet (AirDrop first in its row) for files picked anywhere.
    private func shareFiles(_ urls: [URL]) {
        // copies in tmp: the picked files' access ends when the picker's block returns
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        var copies: [URL] = []
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let dest = tmp.appendingPathComponent(u.lastPathComponent)
            if (try? FileManager.default.copyItem(at: u, to: dest)) != nil { copies.append(dest) }
        }
        guard !copies.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let top = AlertRunner.topViewController() else { return }
            let vc = UIActivityViewController(activityItems: copies, applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = top.view
            vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            top.present(vc, animated: true)
        }
    }
}

/// Files on Wi-Fi's address, to scan with another phone's camera.
struct QRSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let img = qrImage(text) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                Text("Scan it with another phone's camera on the same Wi-Fi.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                Button { UIPasteboard.general.string = text } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Files on Wi-Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func qrImage(_ s: String) -> UIImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(s.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Shared pieces

extension View {
    /// On iPad, keeps a column of cards at a comfortable width instead of edge to edge.
    func readableWidth(_ width: CGFloat = 720) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

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
