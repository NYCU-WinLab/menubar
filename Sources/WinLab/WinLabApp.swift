import AppKit
import SwiftUI

@main
struct WinLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item is AppKit (StatusMenu); SwiftUI owns Settings.
        Settings {
            SettingsView()
                .environment(delegate.model)
                .environment(delegate.updater)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = Updater()
    private var statusMenu: StatusMenu?
    private var bentoWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.updater = updater
        model.notifier.requestPermission()
        model.start()
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
        if ProcessInfo.processInfo.environment["WINLAB_OPEN_MENU"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(4))
                menu.open()
            }
        }
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
