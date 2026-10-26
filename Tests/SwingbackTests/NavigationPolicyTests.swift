import Foundation
import Testing

@testable import Swingback

// Where the widget's web view may go (ADR 0034, decision 6): the widget's pages at the portal's origin, any
// frame inside them, and outside for what a person follows; nothing else.

@Suite struct NavigationPolicyTests {
    private let origin = "https://feedback.acme.com"

    private func decision(
        _ address: String,
        mainFrame: Bool = true,
        window: Bool = false,
        tap: Bool = false
    ) -> NavigationDecision {
        let request = NavigationRequest(url: URL(string: address)!, isMainFrame: mainFrame, opensWindow: window, followsTap: tap)
        return navigationDecision(request, origin: origin)
    }

    @Test func keepsTheWidgetsPagesInItsDocument() {
        #expect(decision("https://feedback.acme.com/widget") == .allow)
        #expect(decision("https://feedback.acme.com/widget/changelog?q=dark") == .allow)
        #expect(decision("https://FEEDBACK.acme.com:443/widget/posts/dark-mode") == .allow)
    }

    @Test func opensOutsideWhatAPersonFollowsOutOfTheWidget() {
        for address in ["https://feedback.acme.com/", "https://feedback.acme.com/widgets", "https://elsewhere.example/widget"] {
            #expect(decision(address, tap: true) == .openOutside(URL(string: address)!), "\(address)")
            #expect(decision(address) == .cancel, "\(address), which nobody followed")
        }
        #expect(decision("mailto:team@acme.com", tap: true) == .openOutside(URL(string: "mailto:team@acme.com")!))
        #expect(decision("http://feedback.acme.com/widget", tap: true) == .openOutside(URL(string: "http://feedback.acme.com/widget")!))
    }

    @Test func refusesWhatNoBrowserShouldOpen() {
        for address in ["javascript:alert(1)", "file:///etc/hosts", "myapp://settings", "data:text/html,hi"] {
            #expect(decision(address, tap: true) == .cancel, "\(address)")
            #expect(decision(address, window: true, tap: true) == .cancel, "\(address) in a window")
        }
    }

    @Test func letsFramesInsideTheWidgetLoad() {
        #expect(decision("https://challenges.cloudflare.com/turnstile", mainFrame: false) == .allow)
        #expect(decision("about:blank", mainFrame: false) == .allow)
        #expect(decision("myapp://settings", mainFrame: false) == .cancel)
    }

    @Test func opensANewWindowsWebAddressOutside() {
        let url = URL(string: "https://acme.com/docs")!
        #expect(decision("https://acme.com/docs", window: true) == .openOutside(url))
        #expect(decision("mailto:team@acme.com", window: true) == .cancel)
    }
}
