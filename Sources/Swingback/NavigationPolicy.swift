import Foundation

// Where the widget's web view may go (ADR 0034, decision 6): its document stays on the widget's pages at the
// portal's canonical origin; a frame inside it (the captcha) loads what it loads; every other address a
// person follows opens outside, in Safari's view or the system's app for it, and nothing else does. The
// widget itself hands the app its links out (`open-url`): this is what holds when it doesn't.

/// What the web view is asked to load.
struct NavigationRequest: Equatable, Sendable {
    var url: URL
    /// Whether it would replace the widget's own document (not a frame inside it).
    var isMainFrame: Bool
    /// Whether it asks for a new window (`target="_blank"`, `window.open`).
    var opensWindow: Bool
    /// Whether a person asked for it (a link they activated), not the page alone.
    var followsTap: Bool
}

enum NavigationDecision: Equatable, Sendable {
    case allow
    case cancel
    /// Not in the widget: Safari's view for a web address, the system's app for a mail or a phone address.
    case openOutside(URL)
}

/// The schemes a link that leaves the widget may open outside.
private let outsideSchemes: Set<String> = ["http", "https", "mailto", "tel"]

/// The schemes a frame inside the widget may load.
private let frameSchemes: Set<String> = ["http", "https", "about", "blob", "data"]

/// Whether a path is one of the widget's pages: `/widget`, or under it.
func isWidgetPath(_ path: String) -> Bool {
    path == "/widget" || path.hasPrefix("/widget/")
}

/// What the web view does with a request, the widget's portal at `origin`.
func navigationDecision(_ request: NavigationRequest, origin: String) -> NavigationDecision {
    let scheme = request.url.scheme?.lowercased() ?? ""
    let leaves = request.followsTap && outsideSchemes.contains(scheme)
    if request.opensWindow {
        return leaves || webAddress(request.url.absoluteString) != nil ? .openOutside(request.url) : .cancel
    }
    if !request.isMainFrame {
        return frameSchemes.contains(scheme) ? .allow : .cancel
    }
    if originOf(request.url.absoluteString) == origin, isWidgetPath(request.url.path(percentEncoded: true)) {
        return .allow
    }
    return leaves ? .openOutside(request.url) : .cancel
}
