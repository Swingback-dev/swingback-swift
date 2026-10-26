import Foundation

// What the widget and its host say to each other (ADR 0034): this package's copy of
// sdks/protocol/widget-protocol.json, which ProtocolTests holds it to, with the messages of fixtures.json.
// The widget finds an iOS or macOS app by its message handler (`webkit.messageHandlers.swingbackHost`) and
// says its messages to it as JSON text; the app posts its own in the page, to the portal's origin.

/// The version of the protocol this package speaks.
let protocolVersion = 1

/// What every message of the protocol carries, both ways.
let messageSource = "swingback"

/// The longest identity token the widget takes.
let tokenMaxLength = 16384

/// The name of the message handler the widget looks for in an app's web view.
let bridgeName = "swingbackHost"

/// A page of the widget: a section, or a post or a board by its slug.
public enum SwingbackPage: Hashable, Sendable {
    /// The posts (the default).
    case feedback
    case roadmap
    case changelog
    /// The form for a new post.
    case new
    /// A post, by the slug in its address.
    case post(String)
    /// A board, by its slug.
    case board(String)

    /// The page's path on the portal, its slug escaped; a post or a board without a slug is the feedback.
    var path: String {
        switch self {
        case .feedback: "/widget"
        case .roadmap: "/widget/roadmap"
        case .changelog: "/widget/changelog"
        case .new: "/widget/new"
        case .post(let slug): slug.isEmpty ? "/widget" : "/widget/posts/\(componentEscaped(slug))"
        case .board(let slug): slug.isEmpty ? "/widget" : "/widget/boards/\(componentEscaped(slug))"
        }
    }
}

/// What JavaScript's encodeURIComponent leaves as it is (the JavaScript SDK's escaping of a slug).
private let componentCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
)

private func componentEscaped(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: componentCharacters) ?? text
}

/// What the widget says to its host: `open-url` to an app only, a link that leaves it, to open outside.
enum WidgetMessage: Equatable, Sendable {
    case ready(version: Int)
    case identified
    case signedOut
    case error(code: String)
    case openURL(URL)

    /// A message of the widget's from its JSON text, or nil for anything else.
    init?(json text: String) {
        guard let data = text.data(using: .utf8),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object(let message) = value,
            message["source"] == .string(messageSource)
        else { return nil }
        switch message["type"] {
        case .string("ready"):
            // A widget that names no version speaks version 0.
            switch message["version"] {
            case nil: self = .ready(version: 0)
            case .integer(let version)? where version >= 0: self = .ready(version: version)
            default: return nil
            }
        case .string("identified"):
            self = .identified
        case .string("signed-out"):
            self = .signedOut
        case .string("error"):
            guard case .string(let code)? = message["code"] else { return nil }
            self = .error(code: code)
        case .string("open-url"):
            guard case .string(let raw)? = message["url"], let url = webAddress(raw) else { return nil }
            self = .openURL(url)
        default:
            return nil
        }
    }
}

/// An address to open in a browser, as the JavaScript SDK reads one: http or https with a host, neither a
/// space nor a control character, and no backslash before the path.
func webAddress(_ raw: String) -> URL? {
    guard raw.range(of: #"^https?://[^/?#\\\s]+(?:[/?#]\S*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
        !raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
        let url = URL(string: raw),
        let host = url.host(percentEncoded: false), !host.isEmpty
    else { return nil }
    return url
}

/// What a host says to the widget: sign its user in (nil: nobody is signed in), sign out, show a page.
enum HostMessage: Equatable, Sendable {
    case identify(token: String?)
    case logout
    case navigate(path: String)

    /// The message as it is posted to the widget, JSON text.
    var json: String {
        var message: [String: Any] = ["source": messageSource]
        switch self {
        case .identify(let token):
            message["type"] = "identify"
            message["token"] = token ?? NSNull()
        case .logout:
            message["type"] = "logout"
        case .navigate(let path):
            message["type"] = "navigate"
            message["path"] = path
        }
        let data = (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// A JSON value as the protocol's messages carry them, an integer told from another number.
enum JSONValue: Decodable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}
