import Foundation
import WebKit

#if canImport(UIKit)
    import UIKit
#endif

// The widget in a native app (ADR 0034): configured once with the portal's address and where the app gets
// its user's identity token, then shown in a sheet (`present(from:)`, `.swingbackFeedback(isPresented:)`) or
// in a view (`SwingbackWidget`). Every widget on screen asks for a token at each `ready`, and is told when the
// app's user changes (`identify()`) or signs out (`logout()`).

/// The feedback widget of your Swingback portal, in your app.
@MainActor
public enum Swingback {
    /// Sets the widget up: call it once, when your app starts.
    ///
    /// - Parameters:
    ///   - portal: Your portal's address, as **Settings → Widget** shows it, such as
    ///     `https://feedback.example.com`.
    ///   - token: Gives the signed-in user's identity token, which your server signs, or nil when nobody is
    ///     signed in. It is asked each time the widget opens. Throw when it can't be had: the widget then
    ///     says `token_unavailable`.
    ///   - onEvent: What the widget did, and when its sheet opened and closed.
    public static func configure(
        portal: URL,
        token: @escaping SwingbackTokenProvider,
        onEvent: (@MainActor (SwingbackEvent) -> Void)? = nil
    ) {
        guard let origin = originOf(portal.absoluteString) else {
            assertionFailure("Swingback: the portal \(portal) isn't an http or https address")
            return
        }
        Widgets.shared.configuration = Widgets.Configuration(origin: origin, token: token, onEvent: onEvent)
    }

    /// Signs your user in again: call it when your user signs in, or another one does. A widget on screen
    /// asks for a token now; one that opens later asks anyway.
    public static func identify() async {
        for widget in Widgets.shared.live {
            await widget.identify()
        }
    }

    /// Ends the widget's session, a guest's too, and forgets the portal's cookies: call it when your user
    /// signs out.
    public static func logout() async {
        let widgets = Widgets.shared
        let live = widgets.live
        for widget in live {
            await widget.logout()
        }
        // No widget to tell: the next one signs out first, whatever the cookies' fate.
        if live.isEmpty { widgets.pendingLogout = true }
        await widgets.forgetCookies()
    }

    #if canImport(UIKit)
        /// Shows the widget in a sheet over `presenter`, on one of its pages.
        ///
        /// - Parameters:
        ///   - title: The sheet's title: the portal's word for the widget by default, your own words, or none.
        ///   - showsBar: Whether the sheet has its bar, the title and the close button: without it, a swipe down
        ///     closes the sheet.
        public static func present(
            from presenter: UIViewController,
            page: SwingbackPage = .feedback,
            title: SwingbackTitle = .portal,
            showsBar: Bool = true
        ) {
            presenter.present(SwingbackSheetController(page: page, title: title, showsBar: showsBar), animated: true)
        }
    #endif
}

/// The widgets on screen, and what they share: the configuration, and a sign-out no widget heard yet.
@MainActor
final class Widgets {
    struct Configuration {
        /// The portal's origin as the app gave it, whose settings name the canonical one.
        var origin: String
        var token: SwingbackTokenProvider
        var onEvent: (@MainActor (SwingbackEvent) -> Void)?
    }

    static let shared = Widgets()

    var configuration: Configuration?
    var pendingLogout = false
    private let widgets = NSHashTable<WidgetWebView>.weakObjects()

    var live: [WidgetWebView] {
        widgets.allObjects
    }

    func emit(_ event: SwingbackEvent) {
        configuration?.onEvent?(event)
    }

    /// A widget for the portal's settings, which takes the sign-out none heard yet.
    func make(settings: WidgetSettings) -> WidgetWebView {
        let widget = WidgetWebView(
            settings: settings,
            token: configuration?.token,
            pendingLogout: pendingLogout,
            emit: { [weak self] event in self?.emit(event) }
        )
        pendingLogout = false
        widgets.add(widget)
        return widget
    }

    /// The portal's cookies in the default store (its session, a guest's, the reader's choices): at the
    /// address the app gave and at the canonical one.
    func forgetCookies() async {
        guard let configuration else { return }
        var hosts: Set<String> = []
        for origin in [configuration.origin, await SettingsCache.shared.settings(of: configuration.origin).origin] {
            if let host = URL(string: origin)?.host(percentEncoded: false)?.lowercased() { hosts.insert(host) }
        }
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.allCookies() {
            let domain = cookie.domain.lowercased()
            if hosts.contains(domain) || hosts.contains(where: { "." + $0 == domain }) {
                await store.deleteCookie(cookie)
            }
        }
    }
}
