import Foundation
import Observation
import Sparkle

@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    var isAvailable: Bool { controller != nil }

    override private init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        canCheck = controller?.updater.canCheckForUpdates ?? false
        lastCheck = controller?.updater.lastUpdateCheckDate
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
