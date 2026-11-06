import AppKit
import SwiftUI

final class DaybarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector? =
                switch (key, flags.contains(.shift)) {
                case ("x", false): #selector(NSText.cut(_:))
                case ("c", false): #selector(NSText.copy(_:))
                case ("v", false): #selector(NSText.paste(_:))
                case ("a", false): #selector(NSText.selectAll(_:))
                case ("z", false): Selector(("undo:"))
                case ("z", true): Selector(("redo:"))
                default: nil
                }
            if let action, NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_: Any?) {}
}

final class PanelController: NSObject, NSWindowDelegate {
    let model = PanelModel()
    var onVisibilityChange: ((Bool) -> Void)?

    private let width: CGFloat = 380
    private let defaultHeight: CGFloat = 800
    private let minimumHeight: CGFloat = 520
    private var resizeStart: (height: CGFloat, mouse: CGFloat)?
    private var preferredHeight: CGFloat {
        let saved = Preferences.shared.panelHeight
        return saved > 0 ? CGFloat(saved) : defaultHeight
    }
    private let panel = DaybarPanel(
        contentRect: .zero,
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    private weak var anchor: NSStatusBarButton?
    private var anchoredOrigin: NSPoint = .zero
    private var isPositioning = false
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var previousApp: NSRunningApplication?

    override init() {
        super.init()
        build()
        model.onDismiss = { [weak self] in self?.close() }
        model.onResize = { [weak self] phase in self?.resize(phase) }
        model.onOpenSettings = { [weak self] in
            self?.close()
            SettingsWindowController.shared.show()
        }
    }

    var isVisible: Bool { panel.isVisible }

    private func build() {
        panel.setFrame(NSRect(x: 0, y: 0, width: width, height: preferredHeight), display: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self

        let glass = NSGlassEffectView()
        glass.cornerRadius = 24
        glass.style = .regular
        let root = PanelRootView()
            .environment(model)
            .environment(CalendarStore.shared)
            .environment(Preferences.shared)
            .environment(WeatherModel.shared)
            .environment(ContactsModel.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        glass.contentView = host
        panel.contentView = glass
    }

    func toggle(from button: NSStatusBarButton?) {
        if panel.isVisible {
            if model.isDetached, !panel.isKeyWindow {
                panel.makeKeyAndOrderFront(nil)
                return
            }
            close()
            return
        }
        show(from: button)
    }

    func show(_ occurrence: Occurrence, from button: NSStatusBarButton?) {
        if !panel.isVisible { show(from: button) }
        model.select(occurrence.start, scroll: true, animated: false)
        model.show(occurrence)
    }

    func show(from button: NSStatusBarButton?) {
        if let button { anchor = button }
        CalendarStore.shared.refreshAccess()
        WeatherModel.shared.refresh()
        model.prepareForOpen()
        if !model.isDetached { position() }
        let finalFrame = panel.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion, !model.isDetached {
            isPositioning = true
            panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 8), display: false)
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
        resignQuickAddFocus()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            if !reduceMotion, !model.isDetached {
                panel.animator().setFrame(finalFrame, display: true)
            }
        } completionHandler: {
            MainActor.assumeIsolated { self.isPositioning = false }
        }
        installMonitors()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        removeMonitors()
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                let othersVisible = NSApp.windows.contains { $0 !== self.panel && $0.isVisible && $0.canBecomeMain }
                if NSApp.isActive, !othersVisible {
                    self.previousApp?.activate()
                }
                self.previousApp = nil
                if self.model.isDetached {
                    self.model.isDetached = false
                    self.panel.level = .popUpMenu
                }
            }
        }
    }

    private func position() {
        isPositioning = true
        defer { isPositioning = false }
        let screen = anchor?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let height = min(preferredHeight, visible.height - 12)
        var x = visible.midX - width / 2
        var top = visible.maxY - 6
        if let anchor, let window = anchor.window {
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            x = rect.midX - width / 2
            top = rect.minY - 6
        }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        panel.setFrame(frame, display: false)
        anchoredOrigin = frame.origin
    }

    private func resize(_ phase: ResizePhase) {
        let mouse = NSEvent.mouseLocation.y
        switch phase {
        case .began:
            resizeStart = (panel.frame.height, mouse)
        case .changed:
            guard let start = resizeStart else { return }
            let screen = panel.screen ?? NSScreen.main
            let maximum = (screen.map { panel.frame.maxY - $0.visibleFrame.minY } ?? 1_200) - 8
            var height = min(max(start.height + (start.mouse - mouse), minimumHeight), maximum)
            if abs(height - defaultHeight) < 26 { height = min(defaultHeight, maximum) }
            guard height != panel.frame.height else { return }
            var frame = panel.frame
            frame.origin.y = frame.maxY - height
            frame.size.height = height
            isPositioning = true
            panel.setFrame(frame, display: true)
            isPositioning = false
            anchoredOrigin = frame.origin
        case .ended:
            resizeStart = nil
            Preferences.shared.panelHeight = abs(panel.frame.height - defaultHeight) < 1 ? 0 : Double(panel.frame.height)
        case .reset:
            Preferences.shared.panelHeight = 0
            var frame = panel.frame
            let height = min(defaultHeight, frame.maxY - (panel.screen?.visibleFrame.minY ?? 0) - 8)
            frame.origin.y = frame.maxY - height
            frame.size.height = height
            isPositioning = true
            panel.animator().setFrame(frame, display: true)
            isPositioning = false
            anchoredOrigin = frame.origin
        }
    }

    func windowDidBecomeKey(_: Notification) {
        guard model.input == .quickAdd, model.quickAddText.isEmpty else { return }
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp, .rightMouseDown].contains(event.type), event.window === panel {
            return
        }
        resignQuickAddFocus()
    }

    func windowDidMove(_: Notification) {
        guard panel.isVisible, !isPositioning, !model.isDetached else { return }
        let origin = panel.frame.origin
        if hypot(origin.x - anchoredOrigin.x, origin.y - anchoredOrigin.y) > 24 {
            model.isDetached = true
            panel.level = .floating
            onVisibilityChange?(false)
        }
    }

    private func installMonitors() {
        removeMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.isDetached else { return }
                self.close()
            }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let windowNumber = event.windowNumber
            let point = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self, windowNumber == self.panel.windowNumber else { return }
                self.resignFieldIfClickedAway(at: point)
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.characters ?? ""
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, windowNumber == self.panel.windowNumber else { return false }
                let editing = self.model.route == .home && self.model.input == .event
                if keyCode == 48, editing, flags.isDisjoint(with: [.command, .control, .option]) {
                    self.model.advanceEditorFocus(backward: flags.contains(.shift), fullKeyboardAccess: NSApp.isFullKeyboardAccessEnabled)
                    if self.model.editorFocus == .start || self.model.editorFocus == .end {
                        self.revealDateSegment()
                    }
                    return true
                }
                if keyCode == 53, editing, self.panel.firstResponder is NSText || self.panel.firstResponder is NSDatePicker {
                    self.panel.makeFirstResponder(nil)
                    return true
                }
                if keyCode == 53 {
                    let typing = self.model.route == .home && self.model.input == .quickAdd && self.panel.firstResponder is NSText
                    if !(typing && self.model.quickAddText.isEmpty) {
                        self.model.back()
                    }
                    if typing {
                        self.panel.makeFirstResponder(nil)
                    }
                    return true
                }
                return self.redirectTyping(characters, flags: flags)
            }
            return consumed ? nil : event
        }
    }

    private func revealDateSegment() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, let picker = self.panel.firstResponder as? NSDatePicker else { return }
            for (keyCode, scalar) in [(UInt16(124), NSRightArrowFunctionKey), (UInt16(123), NSLeftArrowFunctionKey)] {
                guard let unicode = UnicodeScalar(scalar) else { continue }
                let characters = String(Character(unicode))
                if let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: self.panel.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
                ) {
                    picker.keyDown(with: event)
                }
            }
        }
    }

    private func redirectTyping(_ characters: String, flags: NSEvent.ModifierFlags) -> Bool {
        guard model.route == .home, model.input == .quickAdd,
            flags.isDisjoint(with: [.command, .control, .function]),
            !(panel.firstResponder is NSText),
            let scalar = characters.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar),
            !(0xF700...0xF8FF).contains(scalar.value),
            !(model.quickAddText.isEmpty && characters.trimmingCharacters(in: .whitespaces).isEmpty)
        else { return false }
        guard let field = quickAddField(), panel.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
            return false
        }
        let end = NSRange(location: editor.string.utf16.count, length: 0)
        editor.setSelectedRange(end)
        editor.insertText(characters, replacementRange: end)
        return true
    }

    private func resignFieldIfClickedAway(at point: NSPoint) {
        guard model.route == .home, model.input != .event,
            let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor,
            let field = editor.delegate as? NSTextField
        else { return }
        let frame = field.convert(field.bounds, to: nil)
        if point.y < frame.minY - 10 || point.y > frame.maxY + 10 {
            panel.makeFirstResponder(nil)
        }
    }

    private func quickAddField() -> NSTextField? {
        func search(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable,
                (field.placeholderString ?? field.placeholderAttributedString?.string) == L.quickAddPlaceholder
            {
                return field
            }
            for subview in view.subviews {
                if let field = search(subview) { return field }
            }
            return nil
        }
        return panel.contentView.flatMap(search)
    }

    private func resignQuickAddFocus() {
        if panel.firstResponder is NSText { panel.makeFirstResponder(nil) }
        Task { [weak self] in
            for delay in [60, 180] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, self.model.input == .quickAdd, self.model.quickAddText.isEmpty,
                    self.panel.firstResponder is NSText, NSApp.currentEvent?.type != .keyDown
                else { return }
                self.panel.makeFirstResponder(nil)
            }
        }
    }

    private func removeMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        outsideMonitor = nil
        keyMonitor = nil
        clickMonitor = nil
    }
}
