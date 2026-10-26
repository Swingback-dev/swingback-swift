import Foundation
import WebKit

#if canImport(UIKit)
    import SafariServices
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// The widget in a web view, speaking to it as its app (ADR 0034, decision 6): the message handler the widget
// looks for (`webkit.messageHandlers.swingbackHost`), whose messages count from the main frame on the
// portal's canonical origin alone; what the app says, posted in the page to that origin; the navigation
// policy; and links out, opened in Safari's view (or the system's app for them). The web view keeps the
// default data store, which keeps the widget's session across launches (decision 8).

@MainActor
final class WidgetWebView: NSObject {
    let webView: WKWebView
    let settings: WidgetSettings
    /// Whether the widget's first page is on screen.
    private(set) var loaded = false
    var onLoaded: (@MainActor () -> Void)?
    /// Opens a link outside the widget in the tests' stead.
    var opener: (@MainActor (URL) -> Void)?
    private let session: WidgetSession
    private let proxy = MessageProxy()

    init(settings: WidgetSettings, token: SwingbackTokenProvider?, pendingLogout: Bool, emit: @escaping @MainActor (SwingbackEvent) -> Void) {
        self.settings = settings
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(proxy, contentWorld: .page, name: bridgeName)
        #if os(iOS)
            configuration.allowsInlineMediaPlayback = true
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        session = WidgetSession(
            send: { [weak webView] message in
                // In the page's own world, to the portal's origin: what the widget counts as its app's.
                webView?.callAsyncJavaScript(
                    "window.postMessage(JSON.parse(message), origin)",
                    arguments: ["message": message.json, "origin": settings.origin],
                    in: nil,
                    in: .page,
                    completionHandler: nil
                )
            },
            token: token,
            emit: emit,
            pendingLogout: pendingLogout
        )
        super.init()
        proxy.target = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
            if #available(iOS 16.4, macOS 13.3, *) { webView.isInspectable = true }
        #endif
        #if os(iOS)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #endif
    }

    /// Loads a page of the widget, as a new document.
    func load(_ page: SwingbackPage) {
        guard let url = settings.url(of: page) else { return }
        webView.load(URLRequest(url: url))
    }

    /// Shows a page of the widget: in its document when it's ready, else as a new one.
    func show(_ page: SwingbackPage) {
        if !session.navigate(to: page.path) {
            session.detach()
            load(page)
        }
    }

    /// Says who the app's user is again, to a widget that is ready (one that isn't asks at its `ready`).
    func identify() async {
        await session.identify()
    }

    /// Ends the widget's session, a guest's too: now, or first thing at its next `ready`.
    func logout() async {
        await session.logout()
    }

    /// The widget is closed for good: its handler goes, which the content controller would keep.
    func close() {
        session.detach()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: bridgeName, contentWorld: .page)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, originOf(message.frameInfo.securityOrigin) == settings.origin,
            let text = message.body as? String, let widgetMessage = WidgetMessage(json: text)
        else { return }
        if case .openURL(let url) = widgetMessage {
            openOutside(url)
            return
        }
        session.receive(widgetMessage)
    }

    /// Opens an address outside the widget: a web address in Safari's view, any other in the system's app for it.
    func openOutside(_ url: URL) {
        if let opener {
            opener(url)
            return
        }
        let scheme = url.scheme?.lowercased()
        #if canImport(UIKit)
            if scheme == "http" || scheme == "https", let presenter = webView.window?.rootViewController?.topmostPresented {
                presenter.present(SFSafariViewController(url: url), animated: true)
            } else {
                UIApplication.shared.open(url)
            }
        #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }

    private func decide(_ action: WKNavigationAction, opensWindow: Bool) -> NavigationDecision {
        guard let url = action.request.url else { return .cancel }
        let request = NavigationRequest(
            url: url,
            isMainFrame: action.targetFrame?.isMainFrame ?? true,
            opensWindow: opensWindow,
            followsTap: action.navigationType == .linkActivated
        )
        return navigationDecision(request, origin: settings.origin)
    }
}

extension WidgetWebView: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        switch decide(navigationAction, opensWindow: navigationAction.targetFrame == nil) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .openOutside(let url):
            decisionHandler(.cancel)
            openOutside(url)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A new document: the one the session spoke to is gone.
        session.detach()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !loaded else { return }
        loaded = true
        onLoaded?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        session.detach()
        webView.reload()
    }
}

extension WidgetWebView: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // No window of its own: a link to one opens outside, where a person asked for it.
        if case .openOutside(let url) = decide(navigationAction, opensWindow: true) { openOutside(url) }
        return nil
    }

    #if os(macOS)
        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
        ) {
            // The images a post or a comment takes.
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = false
            panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
        }
    #endif
}

/// The origin a frame's security origin names (`scheme://host[:port]`, the default port left out).
@MainActor
func originOf(_ origin: WKSecurityOrigin) -> String {
    let scheme = origin.protocol.lowercased()
    let host = origin.host.lowercased()
    let named = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    let defaultPort = scheme == "https" ? 443 : 80
    return origin.port == 0 || origin.port == defaultPort ? "\(scheme)://\(named)" : "\(scheme)://\(named):\(origin.port)"
}

/// The message handler the content controller keeps: the widget's own object would keep itself, through it.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WidgetWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}

#if canImport(UIKit)
    extension UIViewController {
        /// The view controller on top of what this one presents: where Safari's view goes.
        var topmostPresented: UIViewController {
            presentedViewController?.topmostPresented ?? self
        }
    }
#endif
