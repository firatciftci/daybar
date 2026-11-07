import AppKit

final class MenuBarController: NSObject {
    private let panel: PanelController
    private let store = CalendarStore.shared
    private let prefs = Preferences.shared
    private let item: NSStatusItem
    private var meeting: Occurrence?
    private var renderedKey = ""
    private var timer: Timer?
    private var hiddenMeetings: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hiddenMeetingIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hiddenMeetingIDs") }
    }

    init(panel: PanelController) {
        self.panel = panel
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        item.autosaveName = "DaybarDate"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        panel.onVisibilityChange = { [weak self] visible in
            self?.item.button?.highlight(visible)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        trackChanges { [weak self] in
            self?.refresh()
        }
    }

    func togglePanel() {
        panel.toggle(from: item.button)
    }

    private func refresh() {
        _ = store.revision
        _ = prefs.showMeetingIcon
        _ = prefs.meetingLeadMinutes
        let now = Date()
        meeting = upcomingMeeting(now: now)
        let live = meeting?.isLive(at: now) ?? false
        let service = meeting?.meeting?.service
        let next = nextEvent(now: now)
        let label = next.map { countdown(for: $0, now: now) } ?? ""
        let key = "\(now.dayNumber)|\(service?.name ?? "")|\(live)|\(label)"
        if key != renderedKey, let button = item.button {
            renderedKey = key
            button.image = MenuBarIcon.item(day: now.dayNumber, meeting: service, live: live)
            button.attributedTitle = NSAttributedString(string: label, attributes: [.font: Self.titleFont])
            button.imagePosition = label.isEmpty ? .imageOnly : .imageLeading
        }
        var tip = Fmt.longDay(now)
        if let next {
            tip = "\(next.title)\n\(Fmt.timeRange(next.start, next.end))\n\n\(tip)"
        }
        if let meeting, let link = meeting.meeting {
            tip = "\(L.joinTooltip(meeting.title, link.service.name))\n\(status(of: meeting, now: now))\n\n\(tip)"
        }
        item.button?.toolTip = tip
        item.button?.setAccessibilityLabel(label.isEmpty ? Fmt.longDay(now) : "\(Fmt.longDay(now)), \(label)")
    }

    private static let titleFont: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 0)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [
                [NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]
            ]
        ])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }()

    private func nextEvent(now: Date) -> Occurrence? {
        _ = prefs.showNextEvent
        _ = prefs.nextEventMinutes
        guard prefs.showNextEvent else { return nil }
        let horizon =
            prefs.nextEventMinutes > 0 ? now.addingTimeInterval(TimeInterval(prefs.nextEventMinutes * 60)) : now.startOfDay.adding(days: 1)
        var pool = store.occurrences(on: now)
        pool.append(contentsOf: store.occurrences(on: now.adding(days: 1)))
        var seen: Set<String> = []
        let timed = pool.filter { occurrence in
            !occurrence.isAllDay && !occurrence.isDeclined && occurrence.birthday == nil && occurrence.end > now
                && occurrence.start < horizon
                && seen.insert(occurrence.id).inserted
        }
        let upcoming = timed.filter { $0.start > now }.sorted { $0.start < $1.start }
        let live = timed.filter { $0.start <= now }.max { $0.start < $1.start }
        if let soon = upcoming.first, soon.start.timeIntervalSince(now) <= 5 * 60 { return soon }
        return live ?? upcoming.first
    }

    private func countdown(for occurrence: Occurrence, now: Date) -> String {
        let title = Self.truncated(occurrence.title, width: 150)
        if occurrence.start > now {
            return L.menuBarStartsIn(title, Fmt.duration(occurrence.start.timeIntervalSince(now)))
        }
        return L.menuBarTimeLeft(title, Fmt.duration(occurrence.end.timeIntervalSince(now)))
    }

    private static func truncated(_ text: String, width: CGFloat) -> String {
        func measure(_ string: String) -> CGFloat { NSAttributedString(string: string, attributes: [.font: titleFont]).size().width }
        guard measure(text) > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty, measure(String(characters) + "…") > width {
            characters.removeLast()
        }
        return String(characters).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func upcomingMeeting(now: Date) -> Occurrence? {
        guard prefs.showMeetingIcon else { return nil }
        let lead = TimeInterval(prefs.meetingLeadMinutes * 60)
        let hidden = hiddenMeetings
        var pool = store.occurrences(on: now)
        pool.append(contentsOf: store.occurrences(on: now.adding(days: 1)))
        let candidates = pool.filter { occurrence in
            occurrence.meeting != nil && !occurrence.isAllDay && !occurrence.isDeclined && !hidden.contains(occurrence.id)
                && occurrence.end > now && occurrence.start.addingTimeInterval(-lead) <= now
        }
        return candidates.min { a, b in
            abs(a.start.timeIntervalSince(now)) < abs(b.start.timeIntervalSince(now))
        }
    }

    private func status(of occurrence: Occurrence, now: Date) -> String {
        occurrence.isLive(at: now) ? L.liveNow : L.startsIn(Fmt.duration(occurrence.start.timeIntervalSince(now)))
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if meeting != nil, let x = pointerOffset(in: sender), x < MenuBarIcon.meetingWidth + MenuBarIcon.gap / 2 {
            showMeetingMenu(from: sender)
            return
        }
        if event?.type == .rightMouseUp {
            popUp(utilityMenu(), from: sender)
            return
        }
        panel.toggle(from: sender)
    }

    private func pointerOffset(in button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let mouse = NSEvent.mouseLocation
        guard frame.insetBy(dx: -2, dy: -4).contains(mouse) else { return nil }
        let imageX = button.cell.map { $0.imageRect(forBounds: button.bounds).minX } ?? (frame.width - (button.image?.size.width ?? 0)) / 2
        return mouse.x - frame.minX - imageX
    }

    private func showMeetingMenu(from button: NSStatusBarButton) {
        guard let meeting, let link = meeting.meeting else { return }
        let now = Date()
        let menu = NSMenu()
        let show = menu.addItem(withTitle: meeting.title, action: #selector(showMeeting), keyEquivalent: "")
        show.target = self
        show.subtitle = "\(status(of: meeting, now: now)), \(Fmt.timeRange(meeting.start, meeting.end))"
        show.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        menu.addItem(.separator())
        let join = menu.addItem(withTitle: L.joinService(link.service.name), action: #selector(joinMeeting), keyEquivalent: "")
        join.target = self
        let glyph = link.service.nsImage?.copy() as? NSImage
        glyph?.size = NSSize(width: 16, height: 16)
        glyph?.isTemplate = true
        join.image = glyph
        let copy = menu.addItem(withTitle: L.copyLink, action: #selector(copyMeetingLink), keyEquivalent: "")
        copy.target = self
        copy.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        menu.addItem(.separator())
        let hide = menu.addItem(withTitle: L.hideForEvent, action: #selector(hideMeeting), keyEquivalent: "")
        hide.target = self
        hide.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        popUp(menu, from: button)
    }

    @objc private func joinMeeting() {
        meeting?.meeting?.join()
    }

    @objc private func showMeeting() {
        guard let meeting else { return }
        panel.show(meeting, from: item.button)
    }

    @objc private func copyMeetingLink() {
        guard let url = meeting?.meeting?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func hideMeeting() {
        guard let meeting else { return }
        let cutoff = Date().addingTimeInterval(-2 * 86_400).timeIntervalSinceReferenceDate
        var hidden = hiddenMeetings.filter { id in
            id.split(separator: "|").last.flatMap { Double($0) }.map { $0 > cutoff } ?? false
        }
        hidden.insert(meeting.id)
        hiddenMeetings = hidden
        refresh()
    }

    @objc private func openCalendarApp() {
        store.openInCalendar(nil)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel()
    }

    private func utilityMenu() -> NSMenu {
        let menu = NSMenu()
        let about = menu.addItem(withTitle: L.about, action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(.separator())
        let calendar = menu.addItem(withTitle: L.openCalendar, action: #selector(openCalendarApp), keyEquivalent: "")
        calendar.target = self
        let settings = menu.addItem(withTitle: L.settingsMenu, action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func popUp(_ menu: NSMenu, from button: NSStatusBarButton) {
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
        button.highlight(panel.isVisible)
    }
}
