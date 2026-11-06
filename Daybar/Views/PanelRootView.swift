import EventKit
import SwiftUI

struct PanelRootView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(PanelModel.self) private var model
    @Environment(Preferences.self) private var prefs

    var body: some View {
        Group {
            switch store.access {
            case .granted:
                MainPanel()
            case .unknown, .denied:
                AccessView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.metrics, Metrics(compact: prefs.compact))
        .animation(Motion.navigate, value: prefs.compact)
        .task(id: model.openCount) {
            while !Task.isCancelled {
                model.now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct MainPanel: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 380

    var body: some View {
        let push = NavigationPush(model: model, width: width, reduceMotion: reduceMotion)
        VStack(spacing: 0) {
            TopBar()
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ZStack(alignment: .top) {
                switch model.route {
                case .home:
                    HomeView()
                        .transition(push)
                case .detail(let occurrence):
                    EventDetailView(occurrence: occurrence)
                        .id(occurrence.id)
                        .transition(push)
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        }
        .animation(Motion.navigate, value: model.route)
        .overlay(alignment: .bottom) { ResizeHandle() }
        .modifier(Confirmations())
    }
}

private struct NavigationPush: Transition {
    let model: PanelModel
    let width: CGFloat
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let forward = model.forward
        let (offset, opacity): (CGFloat, Double) =
            switch phase {
            case .identity: (0, 1)
            case .willAppear: forward ? (width, 1) : (-width * 0.3, 0)
            case .didDisappear: forward ? (-width * 0.3, 0) : (width, 1)
            }
        content
            .offset(x: reduceMotion ? 0 : offset)
            .opacity(reduceMotion ? (phase.isIdentity ? 1 : 0) : opacity)
    }
}

private struct Confirmations: ViewModifier {
    @Environment(PanelModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .confirmationDialog(
                model.deleteRequest.map { L.deleteConfirmTitle($0.title) } ?? "",
                isPresented: Binding(get: { model.deleteRequest != nil }, set: { if !$0 { model.deleteRequest = nil } }),
                titleVisibility: .visible,
                presenting: model.deleteRequest
            ) { occurrence in
                if occurrence.isRecurring {
                    Button(L.deleteThisEvent, role: .destructive) { model.delete(occurrence, span: .thisEvent) }
                    Button(L.deleteFutureEvents, role: .destructive) { model.delete(occurrence, span: .futureEvents) }
                } else {
                    Button(L.deleteEvent, role: .destructive) { model.delete(occurrence, span: .thisEvent) }
                }
                Button(L.cancel, role: .cancel) { model.deleteRequest = nil }
            } message: { occurrence in
                Text(occurrence.isRecurring ? L.deleteRecurringMessage : L.deleteMessage(occurrence.calendarTitle))
            }
            .confirmationDialog(
                model.draft.isNew ? L.discardNewTitle : L.discardEditTitle,
                isPresented: $model.askDiscard,
                titleVisibility: .visible
            ) {
                Button(model.draft.isNew ? L.discardNewButton : L.discardEditButton, role: .destructive) {
                    model.finishEditing(saved: nil)
                }
                Button(L.keepEditing, role: .cancel) {}
            }
            .confirmationDialog(L.saveSpanTitle, isPresented: $model.askSaveSpan, titleVisibility: .visible) {
                Button(L.saveThisEvent) { model.save(.thisEvent) }
                Button(L.saveFutureEvents) { model.save(.futureEvents) }
                Button(L.cancel, role: .cancel) {}
            }
    }
}

private struct ResizeHandle: View {
    @Environment(PanelModel.self) private var model
    @State private var dragging = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 8)
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: .bottom))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !dragging {
                            dragging = true
                            model.onResize?(.began)
                        }
                        model.onResize?(.changed)
                    }
                    .onEnded { _ in
                        dragging = false
                        model.onResize?(.ended)
                    }
            )
            .onTapGesture(count: 2) { model.onResize?(.reset) }
            .accessibilityHidden(true)
    }
}

private struct HomeView: View {
    @Environment(PanelModel.self) private var model
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(spacing: 0) {
            if prefs.showQuickAdd || model.input != .quickAdd {
                InputSlot(input: model.input)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(3)
            }
            ZStack(alignment: .top) {
                Group {
                    switch layout {
                    case .month:
                        CalendarListLayout(style: .month)
                    case .week:
                        CalendarListLayout(style: .week)
                    case .day:
                        DayTimelineLayout()
                    case .upNext:
                        UpNextView()
                    }
                }
                .id(layout)
                .transition(.opacity.animation(Motion.content))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .zIndex(1)
        }
        .animation(Motion.navigate, value: prefs.showQuickAdd)
        .onChange(of: prefs.showQuickAdd) { _, shown in
            if !shown { model.quickAddText = "" }
        }
    }

    private var layout: PanelMode {
        model.mode == .upNext && model.input != .quickAdd ? .week : model.mode
    }
}

struct LowerPane<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(PanelModel.self) private var model

    var body: some View {
        let browsing = model.input == .quickAdd
        ZStack(alignment: .top) {
            content
                .opacity(browsing ? 1 : 0)
                .allowsHitTesting(browsing)
                .accessibilityHidden(!browsing)
            switch model.input {
            case .search:
                SearchResults()
                    .transition(swap)
            case .event:
                EventForm()
                    .id(model.draft.id)
                    .transition(swap)
            case .quickAdd:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var swap: AnyTransition {
        .opacity.combined(with: .offset(y: 10)).animation(Motion.content)
    }
}

private struct InputSlot: View {
    let input: InputMode
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: 6) {
                switch input {
                case .quickAdd:
                    QuickAddBar(glass: glass)
                case .search:
                    SearchField()
                        .inputCapsule(in: glass)
                case .event:
                    EventTitleField()
                        .inputCapsule(in: glass)
                }
            }
        }
    }
}

private struct TopBar: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store

    var body: some View {
        ZStack {
            if model.route == .home, model.input == .event {
                EventEditingBar()
                    .transition(.opacity.animation(Motion.content))
            } else {
                navigationBar
                    .transition(.opacity.animation(Motion.content))
            }
        }
        .frame(height: 32)
        .background {
            if model.route != .home {
                Button("") { model.compose() }
                    .keyboardShortcut("n", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                Button("") { model.toggleSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            if case .detail(let occurrence) = model.route, store.event(for: occurrence)?.calendar?.allowsContentModifications == true {
                Button("") { model.deleteRequest = occurrence }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            if case .home = model.route {
                ModeSwitcher()
            } else {
                GlassCircleButton(symbol: "chevron.left", help: L.back) {
                    model.back()
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    switch model.route {
                    case .home:
                        GlassCircleButton(symbol: "plus", help: L.newEventHelp) {
                            model.compose()
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        GlassCircleButton(
                            symbol: "magnifyingglass", help: model.input == .search ? L.closeSearch : L.searchHelp,
                            active: model.input == .search
                        ) {
                            model.toggleSearch()
                        }
                        .keyboardShortcut("f", modifiers: .command)
                        CalendarSetsMenu()
                    case .detail(let occurrence):
                        if store.event(for: occurrence)?.calendar?.allowsContentModifications == true, occurrence.birthday == nil {
                            Button(L.edit) { model.edit(occurrence) }
                                .buttonStyle(.glass)
                                .controlSize(.large)
                                .keyboardShortcut("e", modifiers: .command)
                                .help(L.editEvent)
                        }
                    }
                    if model.isDetached {
                        GlassCircleButton(symbol: "xmark", help: L.close) {
                            model.onDismiss?()
                        }
                    }
                    if case .detail(let occurrence) = model.route {
                        EventActionsMenu(occurrence: occurrence)
                    } else {
                        MoreMenu()
                    }
                }
            }
        }
    }
}

private struct ModeSwitcher: View {
    @Environment(PanelModel.self) private var model
    @State private var dragX: CGFloat?
    @State private var lifted = false
    @State private var pressed: PanelMode?

    private let modes = PanelMode.allCases
    private let segment = CGSize(width: 40, height: 28)

    private var selectedIndex: Int {
        modes.firstIndex(of: model.mode) ?? 0
    }

    private func index(at x: CGFloat) -> Int {
        min(max(Int((x / segment.width).rounded(.down)), 0), modes.count - 1)
    }

    var body: some View {
        let maxCenter = segment.width * (CGFloat(modes.count) - 0.5)
        let center = dragX.map { min(max($0, segment.width / 2), maxCenter) } ?? segment.width * (CGFloat(selectedIndex) + 0.5)
        let lens = lifted ? CGSize(width: segment.width * 1.3, height: segment.height * 1.32) : segment
        let active = dragX.map(index(at:)) ?? selectedIndex
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    Image(systemName: mode.symbol)
                        .accessibilityLabel(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(index == active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .opacity(pressed == mode ? 0.5 : 1)
                        .animation(Motion.fade, value: active)
                        .animation(Motion.fade, value: pressed)
                        .frame(width: segment.width, height: segment.height)
                        .contentShape(.rect)
                        .help(mode.title)
                }
            }
            .zIndex(1)
            Color.clear
                .frame(width: lens.width, height: lens.height)
                .glassEffect(lifted ? .clear : .regular, in: .capsule)
                .background {
                    Capsule()
                        .fill(.black.opacity(lifted ? 0.32 : 0))
                        .blur(radius: 5)
                        .offset(y: 2.5)
                        .mask {
                            Rectangle()
                                .padding(-24)
                                .overlay { Capsule().blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                }
                .offset(x: center - lens.width / 2)
                .allowsHitTesting(false)
                .zIndex(lifted ? 2 : 0)
        }
        .frame(width: segment.width * CGFloat(modes.count), height: segment.height)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragX != nil {
                        dragX = value.location.x
                    } else if index(at: value.startLocation.x) == selectedIndex || abs(value.translation.width) > 4 {
                        pressed = nil
                        withAnimation(Motion.lift) {
                            lifted = true
                            dragX = value.location.x
                        }
                    } else if pressed == nil {
                        pressed = modes[index(at: value.startLocation.x)]
                    }
                }
                .onEnded { value in
                    let target = modes[index(at: dragX ?? value.location.x)]
                    pressed = nil
                    if dragX != nil {
                        withAnimation(Motion.select) {
                            dragX = nil
                            lifted = false
                            model.mode = target
                        }
                    } else {
                        select(target)
                    }
                }
        )
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .accessibilityRepresentation {
            Picker(L.viewMonth, selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(modes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .background {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                Button("") { select(mode) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private func select(_ target: PanelMode) {
        guard target != model.mode else { return }
        withAnimation(Motion.lift) {
            lifted = true
            model.mode = target
        } completion: {
            guard dragX == nil else { return }
            withAnimation(Motion.select) { lifted = false }
        }
    }
}

private struct GlassMenuLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .accessibilityHidden(true)
            .font(.system(size: 12.5, weight: .semibold))
    }
}

private struct MoreMenu: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Menu {
            Button(L.newEvent, systemImage: "plus") { model.compose() }
            Button(L.openCalendar, systemImage: "calendar") { store.openInCalendar(nil) }
            Divider()
            Toggle(L.compactLayout, systemImage: "rectangle.compress.vertical", isOn: $prefs.compact)
            Divider()
            Button(L.settingsMenu, systemImage: "gearshape") { model.onOpenSettings?() }
            Button(L.quit, systemImage: "power") { NSApp.terminate(nil) }
        } label: {
            GlassMenuLabel(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(GlassCircleStyle())
        .fixedSize()
        .help(L.moreActions)
    }
}

private struct EventActionsMenu: View {
    let occurrence: Occurrence
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store

    var body: some View {
        let editable = store.event(for: occurrence)?.calendar?.allowsContentModifications == true
        Menu {
            if let meeting = occurrence.meeting {
                Button(L.joinService(meeting.service.name), systemImage: "video") { meeting.join() }
                Button(L.copyLink, systemImage: "link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meeting.url.absoluteString, forType: .string)
                }
                Divider()
            }
            if let url = occurrence.birthday?.contactURL {
                Button(L.showContact, systemImage: "person.crop.circle") { NSWorkspace.shared.open(url) }
            }
            if editable, occurrence.birthday == nil {
                Button(L.edit, systemImage: "pencil") { model.edit(occurrence) }
            }
            Button(L.duplicate, systemImage: "plus.square.on.square") {
                if let copy = store.duplicate(occurrence) {
                    model.show(Occurrence(copy))
                }
            }
            Button(L.openInCalendar, systemImage: "calendar") { store.openInCalendar(occurrence) }
            if editable {
                Divider()
                Button(L.deleteEvent, systemImage: "trash", role: .destructive) {
                    model.deleteRequest = occurrence
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        } label: {
            GlassMenuLabel(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(GlassCircleStyle())
        .fixedSize()
        .help(L.moreActions)
    }
}
