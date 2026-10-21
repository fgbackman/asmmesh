// FindView.swift — finding someone on the mesh: an arrow and a distance.
//
// Three ways, best first:
//   Ultra Wideband  iPhone 11 and later, on both phones, within about 10 m: precise.
//   GPS + compass   any iPhone, outdoors: gets you within 5–10 m.
//   Bluetooth sweep any iPhone, indoors too: turn slowly around; your body blocks the signal
//                   behind you, so it's strongest facing them. Rough, for the last stretch.
// Nothing is shared until the other person says yes, and it stops by itself after 15 minutes.
// The messages ride the mesh sealed for the two of you (seek.s): one byte says what it is.

import SwiftUI
import CoreLocation
import NearbyInteraction

private enum SeekOp: UInt8 {
    case ask = 1        // may I find you?             [1]
    case yes = 2        // yes: we both share           [2]
    case stop = 3       // no, or stop sharing          [3]
    case loc = 4        // where I am                   [4] lat f64, lon f64, accuracy f32
    case token = 5      // my Ultra Wideband token      [5] part, parts, bytes…
}

final class Finder: NSObject, ObservableObject, CLLocationManagerDelegate, NISessionDelegate {
    static let shared = Finder()
    static let minutes = 15

    struct Peer: Equatable { let id: UInt64; let name: String }

    @Published var asking: Peer?         // someone wants to find you: Share / Not Now
    @Published var target: Peer?         // who you're finding (and sharing with)
    @Published var showing = false       // the Find screen is up
    @Published var waiting = false       // asked them, no answer yet
    @Published var declined = false
    @Published var until: Date?          // sharing stops then

    @Published var heading: Double?      // which way the phone's top points, degrees from north
    @Published var mine: CLLocation?
    @Published var theirs: CLLocation?
    @Published var theirsAt: Date?
    @Published var rssi: Int?            // dBm, while they're in direct Bluetooth range
    @Published var uwbDistance: Float?
    @Published var uwbAngle: Double?     // radians, to the right of the phone's top
    @Published var uwbAt: Date?
    @Published var cameraAssist = false
    @Published var sweeping = false
    @Published var sweepBearing: Double? // degrees from north
    @Published var sweepAt: Date?
    @Published var sweepCovered = 0.0    // degrees turned so far

    private let lm = CLLocationManager()
    private var ni: NISession?
    private var parts: [Int: Data] = [:]
    private var samples: [(heading: Double, rssi: Int)] = []
    private var sweepStarted = Date()
    private var timer: Timer?
    private var lastLocSent = Date.distantPast

    static var hasUWB: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.headingFilter = 2
    }

    // MARK: asking and answering

    /// Ask someone to share where they are
    func find(id: UInt64, name: String) {
        if target != nil && target?.id != id { stop() }
        target = Peer(id: id, name: name)
        showing = true
        if until != nil { return }          // sharing with them already
        waiting = true
        declined = false
        startSensors()
        send([SeekOp.ask.rawValue, UInt8(Finder.minutes)])
    }

    /// Share / Not Now, to someone who asked
    func answer(share: Bool) {
        guard let p = asking else { return }
        asking = nil
        guard share else {
            send([SeekOp.stop.rawValue], to: p.id)
            return
        }
        if target != nil && target?.id != p.id { stop() }
        target = p
        startSharing()
        send([SeekOp.yes.rawValue])
        showing = true
    }

    /// Stop sharing (both ways) and close
    func stop() {
        if target != nil { send([SeekOp.stop.rawValue]) }
        end()
    }

    /// What came over the mesh (seek.s)
    func receive(from id: UInt64, name: String, data: Data) {
        guard let op = data.first.flatMap(SeekOp.init(rawValue:)) else { return }
        switch op {
        case .ask:
            if target?.id == id && waiting {            // we both asked: that's a yes
                waiting = false
                startSharing()
                send([SeekOp.yes.rawValue])
            } else if target?.id == id && until != nil {
                send([SeekOp.yes.rawValue])             // still sharing: say so again
            } else {
                asking = Peer(id: id, name: name)
            }
        case .yes:
            guard target?.id == id else { return }
            waiting = false
            startSharing()
        case .stop:
            if asking?.id == id { asking = nil }
            guard target?.id == id else { return }
            if waiting { waiting = false; declined = true; stopSensors(); return }
            end()
        case .loc:
            guard target?.id == id, until != nil, data.count >= 21 else { return }
            let lat = Double(bitPattern: data.le64(at: 1))
            let lon = Double(bitPattern: data.le64(at: 9))
            let acc = Double(Float(bitPattern: data.le32(at: 17)))
            guard lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return }
            theirs = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                altitude: 0, horizontalAccuracy: max(acc, 1), verticalAccuracy: -1,
                                timestamp: Date())
            theirsAt = Date()
        case .token:
            guard target?.id == id, until != nil, data.count > 3 else { return }
            let part = Int(data[1]), count = Int(data[2])
            guard count > 0, count <= 16, part < count else { return }
            parts[part] = data.subdata(in: 3..<data.count)
            if parts.count == count {
                var all = Data()
                for i in 0..<count { if let p = parts[i] { all.append(p) } }
                parts = [:]
                if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: all) {
                    runUWB(with: token)
                }
            }
        }
    }

    // MARK: sharing

    private func startSharing() {
        until = Date().addingTimeInterval(TimeInterval(Finder.minutes * 60))
        startSensors()
        lastLocSent = .distantPast
        sendToken()
    }

    private func end() {
        stopSensors()
        ni?.invalidate()
        ni = nil
        target = nil
        until = nil
        waiting = false
        declined = false
        showing = false
        theirs = nil
        theirsAt = nil
        uwbDistance = nil
        uwbAngle = nil
        uwbAt = nil
        sweepBearing = nil
        sweeping = false
        parts = [:]
    }

    private func startSensors() {
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { lm.startUpdatingHeading() }
        if timer == nil {
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func stopSensors() {
        lm.stopUpdatingLocation()
        lm.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
    }

    /// Twice a second: time's up?, our location out every 2 s, their signal, the sweep
    private func tick() {
        if let u = until, Date() > u { stop(); return }
        if until != nil, let m = mine, Date().timeIntervalSince(lastLocSent) >= 2,
           Date().timeIntervalSince(m.timestamp) < 15 {
            var b: [UInt8] = [SeekOp.loc.rawValue]
            b.appendLE(m.coordinate.latitude.bitPattern)
            b.appendLE(m.coordinate.longitude.bitPattern)
            b.appendLE(Float(m.horizontalAccuracy).bitPattern)
            send(b)
            lastLocSent = Date()
        }
        rssi = nil
        if let t = target {
            let i = am_node_index(t.id)
            if i >= 0, am_node_info(i, 0) <= 1, am_node_info(i, 2) < 10 {
                let dbm = am_node_info(i, 1)
                if dbm < 0 { rssi = dbm }
            }
        }
        if sweeping { sweepSample() }
    }

    private func send(_ bytes: [UInt8], to id: UInt64? = nil) {
        guard let to = id ?? target?.id else { return }
        _ = bytes.withUnsafeBufferPointer { am_seek_send(to, $0.baseAddress, $0.count) }
    }

    // MARK: Ultra Wideband

    private func sendToken() {
        guard Finder.hasUWB else { return }
        if ni == nil {
            let s = NISession()
            s.delegate = self
            ni = s
        }
        guard let token = ni?.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        let size = 90                                   // what fits in one sealed packet
        let count = (data.count + size - 1) / size
        guard count <= 16 else { return }
        for i in 0..<count {
            let chunk = data.subdata(in: (i * size)..<min(data.count, (i + 1) * size))
            send([SeekOp.token.rawValue, UInt8(i), UInt8(count)] + [UInt8](chunk))
        }
    }

    private func runUWB(with peer: NIDiscoveryToken) {
        guard Finder.hasUWB else { return }
        if ni == nil {
            let s = NISession()
            s.delegate = self
            ni = s
        }
        let config = NINearbyPeerConfiguration(peerToken: peer)
        let caps = NISession.deviceCapabilities
        if !caps.supportsDirectionMeasurement && caps.supportsCameraAssistance {
            config.isCameraAssistanceEnabled = true     // newer iPhones point with the camera's help
            cameraAssist = true
        }
        ni?.run(config)
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let o = nearbyObjects.first else { return }
        DispatchQueue.main.async {
            if let d = o.distance { self.uwbDistance = d; self.uwbAt = Date() }
            if let h = o.horizontalAngle {
                self.uwbAngle = Double(h)
            } else if let v = o.direction {
                self.uwbAngle = Double(atan2(v.x, -v.z))
            }
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                 reason: NINearbyObject.RemovalReason) {
        DispatchQueue.main.async {
            self.uwbAngle = nil
            if reason == .peerEnded { self.uwbDistance = nil }
        }
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let c = session.configuration { session.run(c) }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        DispatchQueue.main.async {
            if self.ni === session { self.ni = nil }
            self.uwbAngle = nil
            self.uwbDistance = nil
            if self.until != nil { self.sendToken() }   // start over: they'll answer with theirs
        }
    }

    // MARK: Bluetooth sweep

    func startSweep() {
        samples = []
        sweepCovered = 0
        sweepStarted = Date()
        sweeping = true
    }

    private func sweepSample() {
        guard let h = heading, let r = rssi else {
            if Date().timeIntervalSince(sweepStarted) > 40 { finishSweep() }
            return
        }
        samples.append((h, r))
        var bins = Set<Int>()
        for s in samples { bins.insert(Int(s.heading / 30) % 12) }
        sweepCovered = Double(bins.count * 30)
        if bins.count >= 11 || Date().timeIntervalSince(sweepStarted) > 40 { finishSweep() }
    }

    /// The direction the signal was strongest: each 30° slice's average, then a weighted
    /// circular mean of the best slices
    private func finishSweep() {
        sweeping = false
        var sum = [Double](repeating: 0, count: 12), n = [Double](repeating: 0, count: 12)
        for s in samples {
            let b = Int(s.heading / 30) % 12
            sum[b] += Double(s.rssi)
            n[b] += 1
        }
        let avg = (0..<12).compactMap { n[$0] > 0 ? ($0, sum[$0] / n[$0]) : nil }
        guard avg.count >= 6, let lo = avg.map(\.1).min(), let hi = avg.map(\.1).max(), hi - lo >= 3 else {
            sweepBearing = nil
            return
        }
        var x = 0.0, y = 0.0
        for (b, a) in avg where a >= hi - 3 {
            let w = a - lo + 1
            let r = (Double(b) * 30 + 15) * .pi / 180
            x += w * sin(r)
            y += w * cos(r)
        }
        sweepBearing = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        sweepAt = Date()
    }

    // MARK: Location and compass

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last, l.horizontalAccuracy >= 0 { mine = l }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        guard h.headingAccuracy >= 0 else { return }
        heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }

    // MARK: What to show

    enum Way { case uwb, gps, sweep, near, none }

    struct Reading {
        var way: Way
        var arrow: Double?          // radians, clockwise from the phone's top
        var metres: Double?
        var note: String
    }

    var reading: Reading {
        let now = Date()
        if let d = uwbDistance, let at = uwbAt, now.timeIntervalSince(at) < 3 {
            if let a = uwbAngle {
                return Reading(way: .uwb, arrow: a, metres: Double(d), note: "Precise \u{00B7} Ultra Wideband")
            }
            return Reading(way: .uwb, arrow: gpsArrow, metres: Double(d),
                           note: cameraAssist ? "Precise distance \u{00B7} hold the phone up and move it slowly side to side for the arrow"
                                              : "Precise distance \u{00B7} turn slowly for the arrow")
        }
        if let m = mine, let t = theirs, let at = theirsAt, now.timeIntervalSince(at) < 60 {
            let dist = m.distance(from: t)
            let fuzz = max(m.horizontalAccuracy, t.horizontalAccuracy)
            if dist > fuzz || sweepArrow == nil {
                return Reading(way: .gps, arrow: dist > fuzz * 0.7 ? gpsArrow : nil, metres: dist,
                               note: dist > fuzz * 0.7
                                   ? "GPS \u{00B7} \u{00B1}\(Int(fuzz.rounded())) m"
                                   : "Within GPS accuracy (\u{00B1}\(Int(fuzz.rounded())) m): turn around to find them by Bluetooth")
            }
        }
        if let a = sweepArrow {
            return Reading(way: .sweep, arrow: a, metres: rssiMetres, note: "Bluetooth sweep \u{00B7} rough; sweep again as you get closer")
        }
        if rssiMetres != nil {
            return Reading(way: .near, arrow: nil, metres: rssiMetres,
                           note: "In Bluetooth range \u{00B7} tap Turn Around to find which way")
        }
        if until != nil {
            return Reading(way: .none, arrow: nil, metres: nil,
                           note: mine == nil ? "Finding where you are\u{2026}" : "Waiting for where they are\u{2026}")
        }
        return Reading(way: .none, arrow: nil, metres: nil, note: "")
    }

    /// GPS: the bearing to them, turned by which way the phone points
    private var gpsArrow: Double? {
        guard let m = mine, let t = theirs, let h = heading else { return nil }
        return (bearing(from: m.coordinate, to: t.coordinate) - h) * .pi / 180
    }

    private var sweepArrow: Double? {
        guard let b = sweepBearing, let at = sweepAt, Date().timeIntervalSince(at) < 90, let h = heading else { return nil }
        return (b - h) * .pi / 180
    }

    /// Very rough: -59 dBm at 1 m, the signal falling off as in a room
    private var rssiMetres: Double? {
        guard let r = rssi else { return nil }
        return pow(10, (-59 - Double(r)) / 25)
    }

    private func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// The core hands finder messages here (seek.s → ios_ui.s _seek_in)
@_cdecl("ios_seek_in")
func iosSeekIn(_ from: UInt64, _ nick: UnsafePointer<CChar>?, _ data: UnsafePointer<UInt8>?, _ len: Int) {
    guard let data, len > 0 else { return }
    Finder.shared.receive(from: from, name: nick.map { String(cString: $0) } ?? "?",
                          data: Data(bytes: data, count: len))
}

private extension Data {
    func le64(at i: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(self[startIndex + i + k]) << (8 * UInt64(k)) }
        return v
    }
    func le32(at i: Int) -> UInt32 {
        var v: UInt32 = 0
        for k in 0..<4 { v |= UInt32(self[startIndex + i + k]) << (8 * UInt32(k)) }
        return v
    }
}

private extension Array where Element == UInt8 {
    mutating func appendLE(_ v: UInt64) { for k in 0..<8 { append(UInt8((v >> (8 * UInt64(k))) & 0xff)) } }
    mutating func appendLE(_ v: UInt32) { for k in 0..<4 { append(UInt8((v >> (8 * UInt32(k))) & 0xff)) } }
}

// MARK: - The Find screen

struct FindView: View {
    @ObservedObject var finder = Finder.shared

    var body: some View {
        let name = finder.target?.name ?? ""
        let r = finder.reading
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                if finder.waiting {
                    ProgressView().controlSize(.large)
                    Text("Asked \(name) to share where they are\u{2026}")
                        .multilineTextAlignment(.center)
                    Text("They need asmmesh open to answer.").font(.footnote).foregroundStyle(Theme.dim)
                } else if finder.declined {
                    Image(systemName: "hand.raised.fill").font(.system(size: 48)).foregroundStyle(Theme.dim)
                    Text("\(name) didn\u{2019}t share where they are.")
                } else {
                    ZStack {
                        Circle().stroke(Theme.cardHi, lineWidth: 10)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 110, weight: .bold))
                            .foregroundStyle(r.way == .uwb ? Theme.green : (r.way == .sweep ? Theme.orange : Theme.blue))
                            .rotationEffect(.radians(r.arrow ?? 0))
                            .opacity(r.arrow == nil ? 0.2 : 1)
                            .animation(.easeOut(duration: 0.3), value: r.arrow)
                    }
                    .frame(width: 240, height: 240)
                    Text(distanceText(r.metres))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(r.note)
                        .font(.callout).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                    Button {
                        finder.startSweep()
                    } label: {
                        Label(finder.sweeping ? "Turn slowly all the way round\u{2026} \(Int(finder.sweepCovered))\u{00B0}"
                                              : "Turn Around to Find (Bluetooth)",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(finder.sweeping || finder.rssi == nil || finder.heading == nil)
                    if finder.rssi == nil && !finder.sweeping {
                        Text("The sweep needs them in Bluetooth range.").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
                if let u = finder.until {
                    Text("Sharing where you are with \(name) until \(u, style: .time). Both of you need asmmesh open.")
                        .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                Button(role: .destructive) { finder.stop() } label: {
                    Text(finder.until == nil && !finder.waiting ? "Close" : "Stop Sharing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(finder.until == nil && !finder.waiting ? Theme.grey : Theme.red)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Find \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hide") { finder.showing = false }
                }
            }
        }
    }

    private func distanceText(_ m: Double?) -> String {
        guard let m else { return "\u{2014}" }
        if m < 1 { return "here" }
        if m < 20 { return String(format: "%.0f m", m) }
        if m < 1000 { return "\(Int((m / 5).rounded()) * 5) m" }
        return String(format: "%.1f km", m / 1000)
    }
}
