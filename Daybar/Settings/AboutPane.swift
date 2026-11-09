import AppKit
import SwiftUI

struct AboutPane: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        Form {
            if updater.isAvailable {
                Section {
                    updates
                } header: {
                    hero
                }
                Section { links }
            } else {
                Section {
                    links
                } header: {
                    hero
                }
            }
            Section {
                LinkRow(
                    title: "KeyboardShortcuts", detail: "Sindre Sorhus", symbol: "keyboard",
                    address: "https://github.com/sindresorhus/KeyboardShortcuts")
                LinkRow(title: "Sparkle", detail: "Sparkle Project", symbol: "sparkles", address: "https://sparkle-project.org")
            } header: {
                Text(L.acknowledgments)
            } footer: {
                VStack(spacing: 2) {
                    Text(Self.info("NSHumanReadableCopyright"))
                    Text(L.openSourceFooter)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .onAppear { updater.refresh() }
    }

    private var hero: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(Self.info("CFBundleDisplayName"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
            Text(L.aboutTagline)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(L.aboutVersion(Self.version, Self.info("CFBundleVersion")))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 16)
    }

    @ViewBuilder private var updates: some View {
        @Bindable var updater = updater
        TimelineView(.everyMinute) { _ in
            LabeledContent {
                Button(L.checkForUpdates) { updater.checkForUpdates(nil) }
                    .disabled(!updater.canCheck)
            } label: {
                Text(L.updatesTitle)
                Text(updater.lastCheck.map { L.lastChecked($0.formatted(.relative(presentation: .named))) } ?? L.neverChecked)
            }
        }
        Toggle(L.automaticUpdates, isOn: $updater.automaticallyChecks)
    }

    @ViewBuilder private var links: some View {
        LinkRow(title: L.developer, detail: "Firat Ciftci", symbol: "person.crop.circle", address: "https://firatciftci.com")
        LinkRow(title: L.sourceCode, detail: L.github, symbol: "chevron.left.forwardslash.chevron.right", address: Self.repository)
        LinkRow(
            title: L.releaseNotes, detail: Self.version, symbol: "doc.text", address: "\(Self.repository)/releases/tag/v\(Self.version)")
        LinkRow(title: L.reportProblem, detail: nil, symbol: "exclamationmark.bubble", address: "\(Self.repository)/issues/new/choose")
        LinkRow(title: L.license, detail: L.licenseName, symbol: "checkmark.seal", address: "\(Self.repository)/blob/main/LICENSE")
    }

    private static let repository = "https://github.com/firatciftci/daybar"

    private static var version: String { info("CFBundleShortVersionString") }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

private struct LinkRow: View {
    let title: String
    let detail: String?
    let symbol: String
    let address: String

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }
                    Spacer(minLength: 12)
                    if let detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(address)
        }
    }
}
