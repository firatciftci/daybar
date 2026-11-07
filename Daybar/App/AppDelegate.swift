import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.k, modifiers: [.option, .command]))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PanelController?
    private var menuBar: MenuBarController?
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let panel = PanelController()
        let menuBar = MenuBarController(panel: panel)
        self.panel = panel
        self.menuBar = menuBar
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak menuBar] in
            menuBar?.togglePanel()
        }
        WeatherModel.shared.refresh()
        IntentSupport.start()
        Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherModel.shared.refresh() }
        }
        if !Preferences.shared.hasOnboarded || CalendarStore.shared.access != .granted {
            let welcome = WelcomeWindowController()
            self.welcome = welcome
            welcome.show { [weak self, weak menuBar] in
                self?.welcome = nil
                menuBar?.togglePanel()
            }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        menuBar?.togglePanel()
        return false
    }

    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.settingsMenu, action: #selector(Self.openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }
}

func trackChanges(_ body: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in trackChanges(body) }
    }
}
