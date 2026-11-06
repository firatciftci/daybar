import AppKit
import SwiftUI

struct MeetingLink: Hashable {
    enum Service: String, Hashable {
        case zoom
        case teams
        case meet
        case webex
        case facetime
        case other

        var name: String {
            switch self {
            case .zoom: "Zoom"
            case .teams: "Teams"
            case .meet: "Meet"
            case .webex: "Webex"
            case .facetime: "FaceTime"
            case .other: "Call"
            }
        }

        var assetName: String? {
            switch self {
            case .zoom: "GlyphZoom"
            case .teams: "GlyphTeams"
            case .meet: "GlyphGoogleMeet"
            case .webex: "GlyphWebex"
            case .facetime, .other: nil
            }
        }

        var image: Image {
            if let assetName { return Image(assetName) }
            return Image(systemName: "video.fill")
        }

        var nsImage: NSImage? {
            if let assetName { return NSImage(named: assetName) }
            return NSImage(systemSymbolName: "video.fill", accessibilityDescription: name)
        }
    }

    let service: Service
    let url: URL

    private static let patterns: Array<(Service, NSRegularExpression)> = {
        let raw: Array<(Service, String)> = [
            (.zoom, #"https?://(?:[a-z0-9-]+\.)?zoom(?:gov)?\.(?:us|com)/(?:j|my|w|s|wc/join)/[^\s"<>)\]]+"#),
            (.teams, #"https?://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet|v2)/[^\s"<>)\]]+"#),
            (.meet, #"https?://meet\.google\.com/[a-z]{3,4}-[a-z]{3,4}-[a-z]{3,4}(?:\?[^\s"<>)\]]*)?"#),
            (.webex, #"https?://(?:[a-z0-9-]+\.)?webex\.com/(?:meet|join|[a-z0-9-]+/j\.php|wbxmjs)[^\s"<>)\]]*"#),
            (.facetime, #"https?://facetime\.apple\.com/join[^\s"<>)\]]+"#),
        ]
        return raw.compactMap { service, pattern in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (service, $0) }
        }
    }()

    static func detect(in sources: Array<String?>) -> Self? {
        for source in sources {
            guard let source, !source.isEmpty else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for (service, regex) in patterns {
                guard let match = regex.firstMatch(in: source, range: range),
                    let swiftRange = Range(match.range, in: source)
                else { continue }
                let trimmed = String(source[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;>"))
                if let url = URL(string: trimmed) {
                    return Self(service: service, url: url)
                }
            }
        }
        return nil
    }

    var nativeURL: URL? {
        switch service {
        case .zoom:
            guard isInstalled(scheme: "zoommtg") else { return nil }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let parts = url.pathComponents
            guard let index = parts.firstIndex(of: "j"), index + 1 < parts.count else { return nil }
            var native = URLComponents()
            native.scheme = "zoommtg"
            native.host = url.host ?? "zoom.us"
            native.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[index + 1])]
            if let pwd = components?.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            native.queryItems = items
            return native.url
        case .teams:
            guard isInstalled(scheme: "msteams") else { return nil }
            return URL(string: url.absoluteString.replacingOccurrences(of: "https://", with: "msteams://"))
        default:
            return nil
        }
    }

    func join() {
        NSWorkspace.shared.open(nativeURL ?? url)
    }

    private func isInstalled(scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }
}
