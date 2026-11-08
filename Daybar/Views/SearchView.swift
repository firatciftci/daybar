import SwiftUI

struct SearchField: View {
    let glass: Namespace.ID
    @Environment(PanelModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .accessibilityHidden(true)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(L.searchPlaceholder, text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit {
                    if let first = CalendarStore.shared.search(model.searchQuery).first {
                        model.show(first)
                    }
                }
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L.clearSearch)
                .accessibilityLabel(L.clearSearch)
                .transition(.opacity)
            }
        }
        .inputCapsule(in: glass, focused: focused) { focused = true }
        .animation(Motion.fade, value: model.searchQuery.isEmpty)
        .task {
            try? await Task.sleep(for: .milliseconds(30))
            focused = true
        }
    }
}

struct SearchResults: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store

    var body: some View {
        let query = model.searchQuery.trimmingCharacters(in: .whitespaces)
        let results = store.search(model.searchQuery)
        Group {
            if query.isEmpty {
                ContentUnavailableView {
                    Label(L.search, systemImage: "magnifyingglass")
                } description: {
                    Text(L.searchHint)
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                let groups = grouped(results)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(groups, id: \.day) { group in
                                DayHeader(date: group.day, forecast: nil, allowsCompose: false)
                                    .id(group.day)
                                ForEach(group.items) { occurrence in
                                    AgendaEventRow(occurrence: occurrence, day: group.day)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.never)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .onChange(of: model.scrollRequest) { _, request in
                        guard let request else { return }
                        let target = groups.min { abs($0.day.timeIntervalSince(request.day)) < abs($1.day.timeIntervalSince(request.day)) }
                        if let target {
                            withAnimation(Motion.navigate) { proxy.scrollTo(target.day, anchor: .top) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grouped(_ results: Array<Occurrence>) -> Array<(day: Date, items: Array<Occurrence>)> {
        var groups: Array<(day: Date, items: Array<Occurrence>)> = []
        for occurrence in results {
            let day = occurrence.start.startOfDay
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(occurrence)
            } else {
                groups.append((day, [occurrence]))
            }
        }
        return groups
    }
}

struct AccessView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label(L.accessTitle, systemImage: "calendar")
        } description: {
            Text(store.access == .denied ? L.accessDeniedBody : L.accessBody)
        } actions: {
            if store.access == .denied {
                Button(L.openSystemSettings) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                Button(L.accessButton) {
                    Task { await store.requestAccess() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }
}
