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
    case main, home, web, news, bitchat, bitchatChat, privateRoom

    var symbol: String {
        switch self {
        case .main: return "globe"
        case .home: return "house.fill"
        case .web: return "safari.fill"
        case .news: return "newspaper.fill"
        case .bitchat: return "antenna.radiowaves.left.and.right"
        case .bitchatChat: return "lock.shield.fill"
        case .privateRoom: return "lock.fill"
        }
    }
    var color: Color {
        switch self {
        case .main: return Theme.blue
        case .home: return Theme.orange
        case .web: return Theme.grey
        case .news: return Theme.yellow
        case .bitchat: return Theme.orange
        case .bitchatChat: return Theme.orange
        case .privateRoom: return Theme.purple
        }
    }
    var subtitle: String {
        switch self {
        case .main: return "Everyone on the mesh"
        case .home: return "Lights, locks and scenes"
        case .web: return "Pages through a Mac with internet"
        case .news: return "Headlines from Macs with internet"
        case .bitchat: return "Public chat with bitchat phones"
        case .bitchatChat: return "Private bitchat chat, end-to-end encrypted"
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
    var listed = false   // others nearby can see it and ask to join (only rooms you made)
    var kind: RoomKind {
        if index == 0 { return .main }
        switch id {
        case 1: return .home
        case 2: return .web
        case 3: return .news
        case 4: return .bitchat
        case 5...12: return .bitchatChat            // bc_ble.s: BCPM_FIRST.. (local, never saved)
        default: return .privateRoom
        }
    }
}

/// Someone else's listed room you aren't in
struct ListedRoom: Identifiable, Equatable {
    let id: UInt64       // the room's id
    let name: String
    let owner: String
    let asked: Bool
    let away: Bool       // owner not heard from lately (phone locked): an ask waits for them
}

/// Someone asking to be let into one of your listed rooms
struct JoinRequest: Identifiable, Equatable {
    let id: Int          // place in the core's queue
    let who: String
    let room: String
}

/// Someone heard on bitchat (bc_ble.s): never invited or found; a private chat with them
/// is its own room (Noise, end-to-end), opened with "bitchat chat <hexID>".
struct BitchatPerson: Identifiable, Equatable {
    let id: Int
    let name: String
    let line: String         // "bitchat · 1a2b 3c4d 5e6f 7a8b · nearby", with a warning if needed
    let hexID: String        // their peer id, 16 hex digits
}

struct Person: Identifiable, Equatable {
    let id: Int          // index on the core's list
    let name: String
    let fingerprint: String
    let hops: Int
    let rssi: Int
    let age: Int
    var blocked = false
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
    let via: String                 // "Bluetooth", "Bluetooth (paired)", "Wi-Fi", "Internet"
    var bluetooth: Bool { via.hasPrefix("Bluetooth") }
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

/// The chess game, as the core has it (ch_mesh.s)
struct Chess: Equatable {
    var state = 0            // 0 none, 2 playing, 3 over
    var room = -1
    var black = false        // we play black: the board turned round
    var pieces = [Int](repeating: 0, count: 128)
    var last = -1
    var status = ""
    var moves = ""
    var opponent = ""
}

/// The Ninefold game, as the core has it (nf_mesh.s)
struct Game: Equatable {
    struct Player: Equatable, Hashable { let name: String; let words: Int; let score: Int }
    var state = 0            // 0 none, 1 lobby, 2 starting, 3 playing, 4 checking, 5 scored
    var room = -1
    var tiles: [String] = []
    var status = ""
    var mine: [String] = []
    var players: [Player] = []
    var results: [String] = []
    var host = false
    var left = 0
    var last = ""            // the answer to the last word typed
    var playing: Bool { state == 3 }
}

final class Mesh: ObservableObject {
    static let shared = Mesh()

    @Published var rooms: [Room] = []
    @Published var listed: [ListedRoom] = []
    @Published var joinRequests: [JoinRequest] = []
    /// people you've invited (by key fingerprint) since the app opened: People shows a check
    @Published var invited: Set<String> = []
    @Published var current = 0
    @Published var lines: [UInt64: [Line]] = [:]
    @Published var people: [Person] = []
    @Published var bitchatPeople: [BitchatPerson] = []
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
    @Published var game = Game()
    @Published var showGame = false      // the game full screen (GameScreen)
    @Published var chess = Chess()
    @Published var showChess = false     // the board full screen (ChessScreen)
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
                          unread: am_room_unread(i), mine: am_room_mine(i) != 0,
                          listed: am_room_listed(i) != 0))
        }
        if r != rooms { rooms = r }
        listedNow()
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
                            age: am_node_info(i, 2), blocked: am_blk_node(i) != 0))
        }
        if p != people { people = p }
        var b: [BitchatPerson] = []
        var line = [CChar](repeating: 0, count: 128)
        for k in 0..<am_bc_count() {
            am_bc_line(k, &line)
            b.append(BitchatPerson(id: k, name: cstr(am_bc_nick(k)), line: String(cString: line),
                                   hexID: String(cString: am_bc_hexid(k))))
        }
        if b != bitchatPeople { bitchatPeople = b }
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
                                last: String(cString: am_scan_cell(i, 108)),            // 'l'
                                via: String(cString: am_scan_cell(i, 118))))            // 'v'
        }
        if rows != scan { scan = rows }
        listedNow()
    }

    /// Other people's listed rooms (they go quiet after two minutes) and asks to join ours
    func listedNow() {
        var l: [ListedRoom] = []
        for k in 0..<am_ad_count() {
            l.append(ListedRoom(id: am_ad_id(k), name: cstr(am_ad_info(k, 0)),
                                owner: cstr(am_ad_info(k, 1)), asked: am_ad_asked(k) != 0,
                                away: am_ad_away(k) != 0))
        }
        if l != listed { listed = l }
        var j: [JoinRequest] = []
        for i in 0..<am_jr_count() {
            j.append(JoinRequest(id: i, who: cstr(am_jr_info(i, 0)), room: cstr(am_jr_info(i, 1))))
        }
        if j != joinRequests { joinRequests = j }
    }

    /// Ask the owner of a listed room to let you in
    func askToJoin(_ room: ListedRoom) {
        for k in 0..<am_ad_count() where am_ad_id(k) == room.id {
            _ = am_ad_ask(k)
            break
        }
        listedNow()
    }

    /// Let In / Not Now
    func answer(_ req: JoinRequest, letIn: Bool) {
        _ = am_jr_answer(req.id, letIn ? 1 : 0)
        listedNow()
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
        coreLater { text.withCString { am_send($0) } }   // a command may ask something
    }

    // MARK: Ninefold (nf_mesh.s)

    func gameChanged() {
        var g = Game()
        g.state = am_nf_state()
        g.room = am_nf_room()
        if g.state != 0 && g.room >= 0 {
            var buf = [CChar](repeating: 0, count: 1200)
            _ = am_nf_tiles(&buf)
            g.tiles = Array(String(cString: buf)).map(String.init)
            _ = am_nf_status(&buf, 1200)
            g.status = String(cString: buf)
            _ = am_nf_mine(&buf, 1200)
            g.mine = String(cString: buf).split(separator: " ").map(String.init)
            _ = am_nf_players(&buf, 1200)
            g.players = String(cString: buf).split(separator: "\n").map { row in
                let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                return Game.Player(name: f.first ?? "?", words: Int(f.count > 1 ? f[1] : "") ?? 0,
                                   score: Int(f.count > 2 ? f[2] : "") ?? 0)
            }
            var k = 0
            while am_nf_result(k, &buf, 1200) > 0 {
                g.results.append(String(cString: buf)); k += 1
            }
            g.host = am_nf_host() != 0
            if let p = am_nf_last() { g.last = String(cString: p) }
            g.left = am_nf_left()
        }
        if g != game { game = g }
        if g.state == 0 && showGame { showGame = false }        // the game room went
    }

    func chessChanged() {
        var c = Chess()
        c.state = am_ch_state()
        c.room = am_ch_room()
        if c.state != 0 {
            c.black = am_ch_me() != 0
            for sq in 0..<128 where sq & 0x88 == 0 { c.pieces[sq] = am_ch_piece(sq) }
            c.last = am_ch_last()
            var buf = [CChar](repeating: 0, count: 2048)
            _ = am_ch_status(&buf, 600)
            c.status = String(cString: buf)
            _ = am_ch_moves(&buf, 2048)
            c.moves = String(cString: buf)
            if let p = am_ch_opponent() { c.opponent = String(cString: p) }
        }
        if c != chess { chess = c }
        if c.state == 0 && showChess { showChess = false }
    }

    /// Typed into the game room as if by keyboard: a word, "start", "shuffle"
    func gameSay(_ text: String) {
        guard game.room >= 0 else { return }
        am_select_room(game.room)
        coreLater { text.withCString { am_send($0) } }
    }

    // MARK: Hue bridges (hue.s)

    struct HueBridge: Identifiable, Hashable { let id: Int; let name: String; let host: String; let paired: Bool }

    /// The bridges known, numbered as Home's "hue bridges" numbers them (1-4)
    func hueBridges() -> [HueBridge] {
        (0..<4).compactMap { b in
            let host = String(cString: am_hue_host(b))
            guard !host.isEmpty else { return nil }
            return HueBridge(id: b + 1, name: String(cString: am_hue_name(b)), host: host, paired: am_hue_paired(b) != 0)
        }
    }

    // MARK: what you typed, and suggestions (term_hist.s)

    struct Suggestion: Hashable { let word: String; let more: Bool }

    /// Home's commands that match what's typed (none outside Home, none once it's a whole one)
    func suggestions(for text: String) -> [Suggestion] {
        guard !text.isEmpty else { return [] }
        let n = text.withCString { am_sg_count($0) }
        var list: [Suggestion] = []
        for i in 0..<max(0, n) {
            guard let w = am_sg_word(i) else { continue }
            let word = String(cString: w)
            if word == text || word + " " == text { continue }
            list.append(Suggestion(word: word, more: am_sg_more(i) != 0))
        }
        return list
    }

    func complete(_ s: Suggestion) {
        input = s.word + (s.more ? " " : "")
        am_hist_reset()
    }

    /// The last lines typed, newest first, each once
    func recent(_ most: Int = 15) -> [String] {
        var seen = Set<String>(), list: [String] = []
        var k = 0
        while list.count < most, let p = am_hist_line(k) {
            let line = String(cString: p)
            if seen.insert(line).inserted { list.append(line) }
            k += 1
        }
        return list
    }

    func historyUp() {
        if let p = input.withCString({ am_hist_prev($0) }) { input = String(cString: p) }
    }

    func historyDown() {
        if let p = am_hist_next() { input = String(cString: p) }
    }

    func home(_ command: String) {
        coreLater { command.withCString { am_home($0) } }
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
