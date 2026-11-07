import AppKit
import KeyboardShortcuts
import SwiftUI

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private var onFinish: (() -> Void)?
    private var observers: Array<any NSObjectProtocol> = []

    init() {
        let window = WelcomeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L.welcomeTitle
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: WelcomeView { [weak self] in self?.finish() }
                .environment(Permissions.shared)
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func show(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        if observers.isEmpty { followSystemSettings() }
        guard let window else { return }
        window.center()
        window.presentInFront()
    }

    func windowDidBecomeKey(_: Notification) {
        Permissions.shared.refresh()
    }

    private func followSystemSettings() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let handoff = app?.bundleIdentifier == "com.apple.systempreferences"
                MainActor.assumeIsolated {
                    if handoff { self?.window?.level = .normal }
                }
            })
        let app = NotificationCenter.default
        observers.append(
            app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.window?.level = .floating }
            })
    }

    func windowWillClose(_: Notification) {
        Preferences.shared.hasOnboarded = true
    }

    private func finish() {
        let action = onFinish
        onFinish = nil
        close()
        action?()
    }
}

private struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var step = Step.hello
    @Environment(Permissions.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step {
        case hello
        case permissions
        case done
    }

    var body: some View {
        ZStack {
            switch step {
            case .hello:
                HelloStep { advance(to: .permissions) }
                    .transition(page)
            case .permissions:
                PermissionsStep { advance(to: .done) }
                    .transition(page)
            case .done:
                DoneStep(onFinish: onFinish)
                    .transition(page)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 44)
        .padding(.bottom, 30)
        .frame(width: 480, height: 600)
        .background(WelcomeBackdrop())
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var page: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 48)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(x: -48)).combined(with: .scale(scale: 0.98))
        )
    }

    private func advance(to next: Step) {
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { step = next }
    }
}

private struct WelcomeBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : Float(context.date.timeIntervalSinceReferenceDate)
            let drift = { (phase: Float, amount: Float) in amount * sin(t * 0.35 + phase) }
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + drift(0, 0.08), 0], [1, 0],
                    [0, 0.5 + drift(1.3, 0.07)], [0.5 + drift(2.1, 0.1), 0.45 + drift(0.7, 0.08)], [1, 0.5 + drift(2.9, 0.07)],
                    [0, 1], [0.5 + drift(3.7, 0.08), 1], [1, 1],
                ],
                colors: palette
            )
        }
        .opacity(scheme == .dark ? 0.55 : 0.4)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var palette: Array<Color> {
        let blue = Color(red: 0.18, green: 0.43, blue: 0.98)
        let indigo = Color(red: 0.33, green: 0.31, blue: 0.86)
        let red = Color(red: 1, green: 0.27, blue: 0.23)
        let base = Color(nsColor: .windowBackgroundColor)
        return [blue, indigo, red, indigo, blue, indigo, base, base, base]
    }
}

private struct StepLayout<Hero: View, Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            hero
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 26)
            content
            Spacer(minLength: 20)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: 240)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled)
    }
}

private struct HelloStep: View {
    let next: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StepLayout(title: L.welcomeTitle, subtitle: L.welcomeSubtitle) {
            VStack(spacing: 30) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.82)
                    .opacity(shown || reduceMotion ? 1 : 0)
                    .accessibilityHidden(true)
                LensWeek()
            }
        } content: {
            EmptyView()
        } footer: {
            PrimaryButton(title: L.continueButton, action: next)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.1)) { shown = true }
        }
    }
}

private struct LensWeek: View {
    @State private var lens = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let days: Array<Date> = {
        let calendar = Calendar.current
        let today = Date().startOfDay
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return (0..<7).map { today.adding(days: $0 - offset) }
    }()

    private let size: CGFloat = 34
    private let gap: CGFloat = 10

    private var todayIndex: Int {
        days.firstIndex { $0.isToday } ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: gap) {
                ForEach(days, id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .frame(width: size)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            ZStack(alignment: .leading) {
                GlassEffectContainer(spacing: gap * 0.5) {
                    ZStack(alignment: .leading) {
                        HStack(spacing: gap) {
                            ForEach(days, id: \.self) { _ in
                                Circle()
                                    .fill(.clear)
                                    .frame(width: size, height: size)
                                    .glassEffect(.regular, in: .circle)
                            }
                        }
                        Circle()
                            .fill(.clear)
                            .frame(width: size, height: size)
                            .glassEffect(.regular.tint(lens == todayIndex ? .red : .accentColor), in: .circle)
                            .offset(x: CGFloat(lens) * (size + gap))
                    }
                }
                HStack(spacing: gap) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        Text("\(day.dayNumber)")
                            .font(.system(size: 13.5, weight: index == lens ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(index == lens ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                lens = todayIndex
                return
            }
            try? await Task.sleep(for: .milliseconds(650))
            let path = Array(0...6) + Array((todayIndex...6).reversed())
            for index in path.dropFirst() {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.42, bounce: 0.22)) { lens = index }
                try? await Task.sleep(for: .milliseconds(index == todayIndex ? 0 : 230))
            }
        }
    }
}

private struct PermissionsStep: View {
    let next: () -> Void
    @Environment(Permissions.self) private var permissions

    var body: some View {
        let ready = permissions.status(of: .calendars) == .granted
        StepLayout(title: L.permissionsTitle, subtitle: L.permissionsSubtitle) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 18))
                .accessibilityHidden(true)
        } content: {
            PermissionList()
                .padding(.top, 26)
        } footer: {
            VStack(spacing: 10) {
                PrimaryButton(title: L.continueButton, enabled: ready, action: next)
                Text(L.calendarRequiredHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .opacity(ready ? 0 : 1)
                    .animation(Motion.content, value: ready)
            }
        }
    }
}

private struct DoneStep: View {
    let onFinish: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var message: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
            return L.doneBody(shortcut.description)
        }
        return L.doneBodyNoShortcut
    }

    var body: some View {
        StepLayout(title: L.doneTitle, subtitle: message) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.primary.opacity(0.18))
                        .frame(width: 18, height: 5)
                }
                Image(nsImage: MenuBarIcon.item(day: Date().dayNumber, meeting: nil, live: false))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.35)).interactive(), in: .capsule)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .scaleEffect(pulse ? 1.45 : 1)
                            .opacity(pulse ? 0 : 0.7)
                    }
                ForEach(0..<2, id: \.self) { _ in
                    Circle()
                        .fill(.primary.opacity(0.18))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
            .accessibilityHidden(true)
        } content: {
            EmptyView()
        } footer: {
            PrimaryButton(title: L.openDaybar, action: onFinish)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.4)) { pulse = true }
        }
    }
}

struct PermissionList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(PermissionKind.allCases) { kind in
                PermissionRow(kind: kind)
                if kind != PermissionKind.allCases.last {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    @Environment(Permissions.self) private var permissions

    var body: some View {
        let status = permissions.status(of: kind)
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if kind == .calendars {
                        Text(L.permissionRequired)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(.primary.opacity(0.08), in: .capsule)
                    }
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            control(status)
                .transition(.blurReplace)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(.smooth(duration: 0.3), value: status)
        .animation(.smooth(duration: 0.3), value: permissions.requesting)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func control(_ status: PermissionStatus) -> some View {
        if permissions.requesting == kind {
            ProgressView()
                .controlSize(.small)
                .frame(height: 24)
        } else {
            switch status {
            case .granted:
                Label(L.permissionAllowed, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: status)
            case .undetermined:
                Button(L.allowButton) {
                    Task { await permissions.request(kind) }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            case .denied:
                Button(L.openSettingsButton) {
                    permissions.openSettings(for: kind)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var title: String {
        switch kind {
        case .calendars: L.permissionCalendars
        case .reminders: L.permissionReminders
        case .contacts: L.permissionContacts
        case .location: L.permissionLocation
        }
    }

    private var detail: String {
        switch kind {
        case .calendars: L.permissionCalendarsDetail
        case .reminders: L.permissionRemindersDetail
        case .contacts: L.permissionContactsDetail
        case .location: L.permissionLocationDetail
        }
    }

    private var symbol: String {
        switch kind {
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle.fill"
        case .location: "location.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .calendars: .red
        case .reminders: .orange
        case .contacts: .gray
        case .location: .blue
        }
    }
}
