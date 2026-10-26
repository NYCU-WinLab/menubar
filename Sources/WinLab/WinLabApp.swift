import AppKit
import SwiftUI

@main
struct WinLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(delegate.model)
                .environment(delegate.updater)
        } label: {
            MenuBarLabel()
                .environment(delegate.model)
        }
        .menuBarExtraStyle(.window)

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.updater = updater
        model.notifier.requestPermission()
        model.start()
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
    }
}

/// The menu bar item: an icon, and the song title when one plays.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.showTitleInMenuBar) private var showTitle = true
    @AppStorage(Pref.menuBarTitleWidth) private var width = 160

    var body: some View {
        let music = model.music
        let playing = music?.current != nil && music?.paused == false && music?.state == .playing
        HStack(spacing: 4) {
            if playing {
                Image(systemName: "music.note")
            } else if let mascot = Self.mascot {
                Image(nsImage: mascot)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            if showTitle, playing, let title = music?.current?.track.title {
                Text(Self.truncate(title, width: width))
            }
        }
    }

    /// The WinLab mascot, drawn in the menu bar's color (bundled app only).
    static let mascot: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuIcon")
        image?.isTemplate = true
        return image
    }()

    /// MenuBarExtra ignores frame limits, so cut the text itself (about 7 pt
    /// per Latin character, 13 per CJK one).
    static func truncate(_ text: String, width: Int) -> String {
        var used = 0.0
        var out = ""
        for ch in text {
            used += ch.unicodeScalars.first.map { $0.value > 0x2E80 ? 13 : 7 } ?? 7
            if used > Double(width) { return out.trimmingCharacters(in: .whitespaces) + "…" }
            out.append(ch)
        }
        return out
    }
}
