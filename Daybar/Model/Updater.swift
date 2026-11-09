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

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    override private init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
