// Mesh.swift — what the screens show, read from the assembly core.

import SwiftUI
import AVFoundation

struct Line: Identifiable {
    let id: Int
    let time: String
    let text: String
    let system: Bool
}

enum RoomKind {
    case main, home, web, news, privateRoom

    var symbol: String {
        switch self {
        case .main: return "globe"
        case .home: return "house.fill"
        case .web: return "safari.fill"
        case .news: return "newspaper.fill"
        case .privateRoom: return "lock.fill"
        }
    }
    var color: Color {
        switch self {
        case .main: return Theme.blue
        case .home: return Theme.orange
        case .web: return Theme.grey
        case .news: return Theme.yellow
        case .privateRoom: return Theme.purple
        }
    }
    var subtitle: String {
        switch self {
        case .main: return "Everyone on the mesh"
        case .home: return "Lights, locks and scenes"
        case .web: return "Pages through a Mac with internet"
        case .news: return "Headlines from Macs with internet"
        case .privateRoom: return "Invite-only"
        }
    }
}

struct Room: Identifiable, Equatable {
    let id: UInt64
    let index: Int
    let name: String
    let unread: Int
    let mine: Bool
    var kind: RoomKind {
        if index == 0 { return .main }
        switch id {
        case 1: return .home
        case 2: return .web
        case 3: return .news
        default: return .privateRoom
        }
    }
}

struct Person: Identifiable, Equatable {
    let id: Int          // index on the core's list
    let name: String
    let fingerprint: String
    let hops: Int
    let rssi: Int
    let age: Int
    var whereText: String {
        if age > 120 { return "away" }
        if hops <= 1 { return rssi != 0 ? "nearby · \(rssi) dBm" : "nearby" }
        return "\(hops) hops"
    }
}

struct Sensor: Identifiable, Equatable {
    let id: Int
    let label: String
    let reading: String
    let age: String
    let kind: String
    let named: Bool
    let rssi: Int
}

struct NearDevice: Identifiable, Equatable {
    let id: Int
    let name: String
    let maker: String
    let what: String
    let rssi: Int
    let age: Int
}

/// A row of the scanner's list: everything around, as in the Mac's Mesh Scanner.
struct ScanRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let kind: String
    let signal: String
    let last: String
}

struct QRText: Identifiable {
    let id = UUID()
    let text: String
}

struct Service: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var on: Bool
}

final class Mesh: ObservableObject {
    static let shared = Mesh()

    @Published var rooms: [Room] = []
    @Published var current = 0
    @Published var lines: [UInt64: [Line]] = [:]
    @Published var people: [Person] = []
    @Published var status = ""
    @Published var nick = ""
    @Published var myFingerprint = ""
    @Published var sensors: [Sensor] = []
    @Published var nearby: [NearDevice] = []
    @Published var scan: [ScanRow] = []
    @Published var services: [Service] = []
    @Published var input = ""
    @Published var talkTitle = "Talk"
    @Published var qrText: QRText?
    @Published var pickingFiles = false
    var talking: Bool { talkTitle.contains("Stop") }

    private var started = false
    private var nextLine = 0
    private var listsPending = false
    private var timer: Timer?
    private let field = AMTextField()
    private let talkButton = AMTalkButton()

    // MARK: start

    func start() {
        guard !started else { return }
        started = true
        field.onChange = { [weak self] s in self?.input = s }
        g_field = Unmanaged.passRetained(field).toOpaque()
        g_talkbtn = Unmanaged.passRetained(talkButton).toOpaque()
        am_set_device_name(UIDevice.current.name)     // gethostname() says "localhost" here
        am_start()
        let t = Timer(timeInterval: 0.1, repeats: true) { _ in am_tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        roomsChanged()
        nameChanged()
        listsNow()
        loadServices()
    }

    // MARK: from the core

    func addLine(room: UInt64, text: String, system: Bool) {
        var time = ""
        var body = text
        if text.count > 10, text[text.index(text.startIndex, offsetBy: 2)] == ":" {
            time = String(text.prefix(5))                 // HH:MM
            body = String(text.dropFirst(10))             // after "HH:MM:SS  "
        }
        nextLine += 1
        var list = lines[room] ?? []
        list.append(Line(id: nextLine, time: time, text: body, system: system))
        if list.count > 600 { list.removeFirst(list.count - 600) }
        lines[room] = list
    }

    func roomsChanged() {
        var r: [Room] = []
        for i in 0..<am_room_count() {
            r.append(Room(id: am_room_id(i), index: i, name: cstr(am_room_name(i)),
                          unread: am_room_unread(i), mine: am_room_mine(i) != 0))
        }
        if r != rooms { rooms = r }
        let c = am_cur_room()
        if c != current { current = c }
    }

    func nameChanged() {
        nick = cstr(am_nick())
        var buf = [CChar](repeating: 0, count: 16)
        am_node_fp(-1, &buf)
        myFingerprint = String(cString: buf)
    }

    /// People, nearby, sensors and status change many times a second; redraw at most 3 times.
    func listsChanged() {
        guard !listsPending else { return }
        listsPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { [weak self] in
            self?.listsPending = false
            self?.listsNow()
        }
    }

    private func listsNow() {
        status = cstr(am_status())
        var p: [Person] = []
        var buf = [CChar](repeating: 0, count: 16)
        for i in 0..<am_node_count() {
            am_node_fp(i, &buf)
            p.append(Person(id: i, name: cstr(am_node_nick(i)), fingerprint: String(cString: buf),
                            hops: am_node_info(i, 0), rssi: am_node_info(i, 1),
                            age: am_node_info(i, 2)))
        }
        if p != people { people = p }
        var s: [Sensor] = []
        for i in 0..<am_sensor_count() {
            let label = cstr(am_sensor_info(i, 0))
            let reading = cstr(am_sensor_info(i, 1))
            let age = cstr(am_sensor_info(i, 2))
            s.append(Sensor(id: i, label: label, reading: reading, age: age,
                            kind: cstr(am_sensor_info(i, 3)), named: am_sensor_info(i, 4) != 0,
                            rssi: am_sensor_info(i, 5)))
        }
        if s != sensors { sensors = s }
        var n: [NearDevice] = []
        for i in 0..<am_near_count() {
            let age = am_near_info(i, 4)
            if age > 120 { continue }
            n.append(NearDevice(id: i, name: cstr(am_near_info(i, 0)), maker: cstr(am_near_info(i, 1)),
                                what: cstr(am_near_info(i, 2)), rssi: am_near_info(i, 3), age: age))
        }
        n.sort { $0.rssi > $1.rssi }
        if n != nearby { nearby = n }
        var rows: [ScanRow] = []
        for i in 0..<am_scan_count() {
            rows.append(ScanRow(id: i, name: String(cString: am_scan_cell(i, 110)),     // 'n'
                                kind: String(cString: am_scan_cell(i, 107)),            // 'k'
                                signal: String(cString: am_scan_cell(i, 115)),          // 's'
                                last: String(cString: am_scan_cell(i, 108))))           // 'l'
        }
        if rows != scan { scan = rows }
    }

    func loadServices() {
        var list: [Service] = []
        for i in 0..<am_svc_count() {
            let rgb = am_svc_field(i, 4)
            let c = Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                          blue: Double(rgb & 255) / 255)
            list.append(Service(id: i, title: cstr(am_svc_field(i, 1)), subtitle: cstr(am_svc_field(i, 2)),
                                symbol: cstr(am_svc_field(i, 3)), color: c, on: am_svc_on(i) != 0))
        }
        services = list
    }

    // MARK: to the core

    func select(_ room: Room) {
        if let i = rooms.firstIndex(where: { $0.id == room.id }) {
            am_select_room(rooms[i].index)
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        text.withCString { am_send($0) }
    }

    func home(_ command: String) {
        command.withCString { am_home($0) }
    }

    func setService(_ s: Service, on: Bool) {
        am_svc_set(s.id, on ? 1 : 0)
        loadServices()
    }

    func talk() {
        if !talking {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .measurement,
                                     options: [.defaultToSpeaker, .allowBluetooth])
            try? session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        am_talk()
    }
}
