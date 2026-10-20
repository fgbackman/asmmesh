// Bridge.swift — the seam between SwiftUI and the assembly core.
//
// 1. Hooks the core calls (ios_room_line, ios_select_room, ios_refresh, ios_status).
// 2. Stand-ins for the AppKit classes the core's prompts use. The core says
//    [NSAlert new], [[NSTextField alloc] initWithFrame:], runModal…, exactly as on the
//    Mac. These Objective-C classes answer under those names and show a
//    UIAlertController instead, waiting for the answer the way runModal does.

import UIKit

// MARK: - Hooks called from assembly (main thread)

@_cdecl("ios_room_line")
func iosRoomLine(_ roomID: UInt64, _ text: UnsafePointer<CChar>?, _ sys: Int32) {
    guard let text else { return }
    let s = String(cString: text)
    Mesh.shared.addLine(room: roomID, text: s, system: sys != 0)
}

@_cdecl("ios_select_room")
func iosSelectRoom(_ index: Int) {
    Mesh.shared.roomsChanged()
}

@_cdecl("ios_refresh")
func iosRefresh(_ what: Int) {
    switch what {
    case 1: Mesh.shared.roomsChanged()
    case 3: Mesh.shared.nameChanged()
    default: Mesh.shared.listsChanged()
    }
}

@_cdecl("ios_status")
func iosStatus(_ text: UnsafePointer<CChar>?) {
    guard let text else { return }
    Mesh.shared.status = String(cString: text)
}

// MARK: - Text field stand-ins (NSTextField, NSSecureTextField, NSComboBox)

@objc(NSTextField)
class AMTextField: NSObject {
    @objc var stringValue: NSString = "" {
        didSet { onChange?(stringValue as String) }
    }
    @objc var placeholderString: NSString?
    var onChange: ((String) -> Void)?
    var isSecure: Bool { false }
    var suggestions: [String] = []

    @objc init(frame: CGRect) { super.init() }
    override init() { super.init() }

    @objc func setCompletes(_ on: Bool) {}
    @objc func setEditable(_ on: Bool) {}
    @objc func setBezeled(_ on: Bool) {}
    @objc func setFont(_ f: AnyObject?) {}
    @objc func setTarget(_ t: AnyObject?) {}
    @objc func setAction(_ s: Selector?) {}
    @objc func addItemWithObjectValue(_ v: AnyObject) {
        if let s = v as? String { suggestions.append(s) }
    }
}

@objc(NSSecureTextField)
class AMSecureField: AMTextField {
    override var isSecure: Bool { true }
    @objc override init(frame: CGRect) { super.init(frame: frame) }
}

@objc(NSComboBox)
class AMComboBox: AMTextField {
    @objc override init(frame: CGRect) { super.init(frame: frame) }
}

// The Talk button: voice.s sets its title to "Talk" / "Stop".
@objc(AMTalkButton)
class AMTalkButton: NSObject {
    @objc func setTitle(_ t: NSString) {
        Mesh.shared.talkTitle = t as String
    }
}

// MARK: - NSAlert stand-in

@objc(NSAlert)
class AMAlert: NSObject {
    var message = ""
    var info = ""
    var buttons: [String] = []
    var field: AMTextField?

    @objc func setMessageText(_ s: NSString) { message = s as String }
    @objc func setInformativeText(_ s: NSString) { info = s as String }
    @objc func addButtonWithTitle(_ s: NSString) -> AnyObject? {
        buttons.append(s as String)
        return nil
    }
    @objc func setAccessoryView(_ v: AnyObject?) { field = v as? AMTextField }
    @objc func setAlertStyle(_ style: Int) {}
    @objc func setShowsHelp(_ on: Bool) {}
    @objc func window() -> AnyObject? { nil }
    @objc func layout() {}
    /// NSModalResponse: 1000 for the first button, 1001 the second, …
    @objc func runModal() -> Int {
        AlertRunner.run(title: message, message: info,
                        buttons: buttons.isEmpty ? ["OK"] : buttons, field: field)
    }
}

enum AlertRunner {
    private static let cancelWords: Set<String> = ["cancel", "not now", "deny", "no"]

    /// Shows the alert and keeps the main run loop turning until a button is tapped,
    /// like AppKit's runModal. Returns 1000 + the button's index.
    static func run(title: String, message: String, buttons: [String], field: AMTextField?) -> Int {
        guard let top = topViewController() else {
            // No screen to ask on (very early, or in the background): the safe answer.
            return buttons.count > 1 ? 1000 + buttons.count - 1 : 1000
        }
        var answer: Int?
        let ac = UIAlertController(title: title, message: message.isEmpty ? nil : message,
                                   preferredStyle: .alert)
        if let field {
            ac.addTextField { tf in
                tf.placeholder = field.placeholderString as String?
                tf.text = field.stringValue as String
                tf.isSecureTextEntry = field.isSecure
                tf.autocapitalizationType = field.isSecure ? .none : .sentences
                tf.autocorrectionType = .no
                tf.clearButtonMode = .whileEditing
            }
        }
        var usedCancel = false
        for (i, b) in buttons.enumerated() {
            var style: UIAlertAction.Style = .default
            if i > 0, !usedCancel, cancelWords.contains(b.lowercased()) {
                style = .cancel
                usedCancel = true
            }
            if b.lowercased().hasPrefix("delete") { style = .destructive }
            ac.addAction(UIAlertAction(title: b, style: style) { _ in
                if let field, let t = ac.textFields?.first?.text {
                    field.stringValue = t as NSString
                }
                answer = 1000 + i
            })
        }
        top.present(ac, animated: true)
        while answer == nil {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return answer ?? 1001
    }

    static func topViewController() -> UIViewController? {
        guard UIApplication.shared.applicationState != .background else { return nil }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
                ?? scenes.first?.windows.first,
              var vc = window.rootViewController else { return nil }
        while let next = vc.presentedViewController, !next.isBeingDismissed { vc = next }
        return vc
    }
}

// MARK: - Small helpers for reading C strings from the core

func cstr(_ p: UnsafePointer<CChar>?) -> String {
    guard let p else { return "" }
    return String(cString: p)
}

func cstr(_ v: Int) -> String {
    guard v != 0, let p = UnsafePointer<CChar>(bitPattern: v) else { return "" }
    return String(cString: p)
}
