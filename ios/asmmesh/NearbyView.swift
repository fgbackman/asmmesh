// NearbyView.swift — the radar, Bluetooth sensors, and everything else in range.

import SwiftUI

struct NearbyView: View {
    @EnvironmentObject var mesh: Mesh
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var naming: Sensor?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card(padding: 8) {
                        RadarView(people: mesh.people, devices: mesh.nearby)
                            .frame(height: sizeClass == .regular ? 460 : 300)
                    }
                    HStack(spacing: 10) {
                        QuickButton(title: "Batteries", symbol: "battery.75percent", color: Theme.green) {
                            mesh.home("batteries")
                        }
                        QuickButton(title: "Headphones here", symbol: "airpodspro", color: Theme.blue) {
                            mesh.home("headphones here")
                        }
                    }
                    Text("Answers appear in the Home room.")
                        .font(.caption).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    SectionTitle(text: "Bluetooth sensors")
                    if mesh.sensors.isEmpty {
                        Card {
                            Text("None heard yet. Switch on Bluetooth Sensors in Settings. Govee, SwitchBot and Xiaomi thermometers and BTHome devices (Shelly BLU buttons, door and motion sensors) show up here — no pairing.")
                                .font(.callout).foregroundStyle(Theme.dim)
                        }
                    }
                    ForEach(mesh.sensors) { s in
                        Card {
                            HStack(spacing: 14) {
                                IconBadge(symbol: s.reading.contains("°") ? "thermometer.medium" : "sensor.fill",
                                          color: s.named ? Theme.green : Theme.grey)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.label).font(.headline)
                                    Text(s.reading).font(.subheadline)
                                    Text("\(s.kind) · \(s.age)\(s.named ? "" : " · not named")")
                                        .font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Button(s.named ? "Rename" : "Name") {
                                    newName = s.named ? s.label : ""
                                    naming = s
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    SectionTitle(text: "Around you")
                    ForEach(mesh.nearby.prefix(40)) { d in
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.right")
                                .foregroundStyle(d.rssi > -65 ? Theme.green : (d.rssi > -80 ? Theme.orange : Theme.grey))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name.isEmpty ? (d.maker.isEmpty ? "Unnamed device" : d.maker) : d.name)
                                    .font(.subheadline.weight(.semibold))
                                let detail = [d.name.isEmpty ? "" : d.maker, d.what].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !detail.isEmpty {
                                    Text(detail).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(d.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .navigationTitle("Nearby")
            .alert("Name this sensor", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("e.g. Bedroom", text: $newName)
                Button("Save") {
                    if let s = naming {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { mesh.home("name sensor \(s.id + 1) \(name)") }
                    }
                    naming = nil
                }
                Button("Cancel", role: .cancel) { naming = nil }
            } message: {
                Text("Then use it in Home and in rules, like “when bedroom gets above 78 turn on the fan”.")
            }
        }
    }
}

struct QuickButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 32)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Rings and a turning sweep. Green: people in direct range, placed by signal; amber:
/// people reached through others, further out per hop; grey specks: other Bluetooth devices.
struct RadarView: View {
    let people: [Person]
    let devices: [NearDevice]

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 12
                for k in 1...4 {
                    let rr = r * CGFloat(k) / 4
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                               with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                let t = tl.date.timeIntervalSinceReferenceDate
                let a = CGFloat(t.truncatingRemainder(dividingBy: 4) / 4 * 2 * .pi)
                var sweep = Path()
                sweep.move(to: c)
                sweep.addArc(center: c, radius: r, startAngle: .radians(Double(a) - 0.5), endAngle: .radians(Double(a)), clockwise: false)
                sweep.closeSubpath()
                ctx.fill(sweep, with: .color(Theme.green.opacity(0.10)))

                for d in devices.prefix(60) {
                    let dist = r * min(1, max(0.15, CGFloat(-d.rssi - 30) / 70))
                    let ang = angle(for: d.name + d.maker + String(d.id))
                    let p = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                             with: .color(.white.opacity(0.25)))
                }
                for p in people {
                    let near = p.hops <= 1 && p.age <= 120
                    let dist: CGFloat = near ? r * min(0.6, max(0.18, CGFloat(-(p.rssi == 0 ? -60 : p.rssi) - 30) / 70))
                                             : r * min(0.95, 0.55 + CGFloat(p.hops) * 0.12)
                    let ang = angle(for: p.fingerprint)
                    let pt = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist)
                    let col = p.age > 120 ? Theme.grey : (near ? Theme.green : Theme.orange)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(col))
                    ctx.draw(Text(p.name).font(.caption2.weight(.semibold)).foregroundColor(.white),
                             at: CGPoint(x: pt.x, y: pt.y - 16))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Theme.orange))
            }
        }
    }

    private func angle(for key: String) -> CGFloat {
        var h: UInt32 = 2166136261
        for b in key.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return CGFloat(h % 3600) / 3600 * 2 * .pi
    }
}
