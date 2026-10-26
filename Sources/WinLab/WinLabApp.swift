import AppKit
import SwiftUI

/// An AppKit app: the menu bar item is an NSStatusItem with an NSMenu, and
/// settings live in StatusMenu's window. (A SwiftUI App would open its
/// Settings scene by itself at launch.)
@main
@MainActor
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = Updater()
    private var statusMenu: StatusMenu?
    private var bentoWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        model.updater = updater
        model.notifier.requestPermission()
        model.start()
        StatusMenu.makeSettings = { [model, updater] in
            SettingsWindow.controller(model: model, updater: updater)
        }
        let menu = StatusMenu(model: model, updater: updater)
        menu.openBento = { [weak self] id in self?.openBento(id) }
        statusMenu = menu
        Hotkeys.shared.handler = { [model] action in
            Task { @MainActor in
                switch action {
                case .togglePause: await model.togglePause()
                case .skip: await model.skip()
                case .volumeUp: await model.nudgeVolume(1)
                case .volumeDown: await model.nudgeVolume(-1)
                case .openDoor:
                    await model.openDoor()
                    if let toast = model.toast { model.notifier.post(id: "door", title: "門禁", body: toast) }
                case .openPortal: model.openPortal()
                }
            }
        }
        Hotkeys.shared.install()
        // Development: WINLAB_OPEN_MENU=1 opens the menu by itself, for
        // screenshots without touching the mouse.
        if ProcessInfo.processInfo.environment["WINLAB_OPEN_SETTINGS"] != nil {
            StatusMenu.openSettings()
        }
        if ProcessInfo.processInfo.environment["WINLAB_OPEN_MENU"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(4))
                menu.open()
            }
        }
    }

    /// A menu bar app has no menu bar of its own, so ⌘V, ⌘C, ⌘A and ⌘Z have
    /// nowhere to go in text fields. This menu is never shown; it routes
    /// those keys to the field being edited.
    static func editMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "結束 WinLab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(app)
        let edit = NSMenuItem()
        let menu = NSMenu(title: "編輯")
        menu.addItem(withTitle: "還原", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷貝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = menu
        main.addItem(edit)
        let window = NSMenuItem()
        window.submenu = NSMenu(title: "視窗")
        window.submenu?.addItem(withTitle: "關閉", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(window)
        return main
    }

    /// A small window for one bento order.
    func openBento(_ id: String) {
        bentoWindow?.close()
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = model.bentoDetail[id]?.restaurant.name ?? "便當"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: BentoOrderView(orderId: id) { [weak window] in window?.close() }
                .environment(model)
        )
        window.center()
        bentoWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
