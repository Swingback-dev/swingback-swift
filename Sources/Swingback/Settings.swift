import Foundation

// What a portal says of its widget to an SDK (ADR 0034, decision 7): its canonical address, which the widget
// is loaded from and messages count from, its accent, its look, the reader's language and the words of its
// controls. The portal serves it at /widget/settings.json; the SDK reads it once a process, and does without
// it (these defaults, the portal's address as the app gave it) when the portal doesn't answer.

/// Where a portal serves its settings for the SDKs.
let settingsPath = "/widget/settings.json"

/// How long the SDK waits for the settings before it does without them.
let settingsTimeout: TimeInterval = 5

struct WidgetSettings: Equatable, Sendable {
    enum Position: String, Sendable { case left, right }
    enum Theme: String, Sendable { case system, light, dark }
    struct Accent: Equatable, Sendable {
        var color: String
        var foreground: String
    }
    struct Labels: Equatable, Sendable {
        var open: String
        var close: String
        var loading: String
    }

    /// The portal's canonical origin (`https://host[:port]`): where the widget is loaded from, and the one
    /// its messages count from.
    var origin: String
    /// The workspace's accent, or nil for the portal's own colors.
    var accent: Accent?
    var position: Position
    var theme: Theme
    /// The reader's language, as the portal chose it (one of the seven), or nil.
    var language: String?
    var labels: Labels

    /// The page's address on the portal.
    func url(of page: SwingbackPage) -> URL? {
        URL(string: origin + page.path)
    }

    /// What the SDK assumes of a portal that hasn't said.
    static func defaults(origin: String) -> WidgetSettings {
        WidgetSettings(
            origin: origin,
            accent: nil,
            position: .right,
            theme: .system,
            language: nil,
            labels: Labels(open: "Feedback", close: "Close", loading: "Loading")
        )
    }

    /// The settings a portal answered, each field checked; what isn't usable takes its default.
    static func read(_ data: Data, origin: String) -> WidgetSettings {
        var settings = defaults(origin: origin)
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let document) = value else {
            return settings
        }
        if case .string(let address)? = document["portal_url"] {
            settings.origin = originOf(address) ?? origin
        }
        if case .object(let accent)? = document["accent"], case .string(let color)? = accent["color"],
            case .string(let foreground)? = accent["foreground"], isColor(color), isColor(foreground)
        {
            settings.accent = Accent(color: color, foreground: foreground)
        }
        if case .string(let raw)? = document["position"], let position = Position(rawValue: raw) {
            settings.position = position
        }
        if case .string(let raw)? = document["theme"], let theme = Theme(rawValue: raw) {
            settings.theme = theme
        }
        if case .string(let language)? = document["language"],
            language.range(of: "^[a-z]{2}$", options: .regularExpression) != nil
        {
            settings.language = language
        }
        if case .object(let labels)? = document["labels"] {
            settings.labels = Labels(
                open: label(labels["open"], or: settings.labels.open),
                close: label(labels["close"], or: settings.labels.close),
                loading: label(labels["loading"], or: settings.labels.loading)
            )
        }
        return settings
    }
}

private func isColor(_ text: String) -> Bool {
    text.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
}

private func label(_ value: JSONValue?, or fallback: String) -> String {
    guard case .string(let text)? = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.utf16.count <= 40
    else { return fallback }
    return text
}

/// The origin of an http or https address (`scheme://host[:port]`, the default port left out), or nil.
func originOf(_ address: String) -> String? {
    guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
        let rawHost = url.host(percentEncoded: false), !rawHost.isEmpty
    else { return nil }
    let lowered = rawHost.lowercased()
    let host = lowered.contains(":") ? "[\(lowered)]" : lowered
    let defaultPort = scheme == "https" ? 443 : 80
    guard let port = url.port, port != defaultPort else { return "\(scheme)://\(host)" }
    return "\(scheme)://\(host):\(port)"
}

/// The portals' settings this process asked for: one request a portal, asked again only when it didn't answer.
@MainActor
final class SettingsCache {
    static let shared = SettingsCache()

    private var asked: [String: Task<WidgetSettings?, Never>] = [:]

    /// A portal's settings, or its defaults when it doesn't answer in time.
    func settings(of origin: String, session: URLSession = .shared) async -> WidgetSettings {
        let task: Task<WidgetSettings?, Never>
        if let existing = asked[origin] {
            task = existing
        } else {
            task = Task { await askSettings(origin, session: session) }
            asked[origin] = task
        }
        if let settings = await task.value { return settings }
        if asked[origin] == task { asked[origin] = nil }
        return .defaults(origin: origin)
    }

    /// Forgets what was asked (the tests ask again).
    func forget() {
        asked = [:]
    }
}

/// A portal's settings, asked of it, or nil when it doesn't answer in time or answers something else.
func askSettings(_ origin: String, session: URLSession) async -> WidgetSettings? {
    guard let url = URL(string: origin + settingsPath) else { return nil }
    var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: settingsTimeout)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpShouldHandleCookies = false
    guard let (data, response) = try? await session.data(for: request),
        let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
    else { return nil }
    return .read(data, origin: origin)
}
