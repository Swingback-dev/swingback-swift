#if os(macOS)
    import Foundation
    import Testing
    import WebKit

    @testable import Swingback

    // The widget's web view with a real WebKit (ADR 0034, decision 6): a page that speaks for the widget, at
    // the portal's origin, says "ready" to the message handler and answers what the app posts in the page.
    // The page is a string loaded at that origin's address: nothing leaves the machine.

    /// What the widget page does: what a version 1 widget says, and what it heard, kept for the test.
    private let widgetPage = """
        <!doctype html><html><body>
        <script>
          window.said = 0;
          const say = (message) => {
            window.said += 1;
            webkit.messageHandlers.swingbackHost.postMessage(JSON.stringify({ source: "swingback", ...message }));
          };
          window.heard = [];
          window.addEventListener("message", (event) => {
            if (event.source !== window || event.origin !== location.origin || event.data?.source !== "swingback") return;
            window.heard.push(event.data);
            if (event.data.type === "identify") say({ type: event.data.token ? "identified" : "signed-out" });
            if (event.data.type === "logout") say({ type: "signed-out" });
          });
          // A frame inside the page can't speak for it.
          const frame = document.createElement("iframe");
          frame.srcdoc = "<script>webkit.messageHandlers.swingbackHost.postMessage(" +
            "JSON.stringify({ source: 'swingback', type: 'error', code: 'from_a_frame' }))<\\/script>";
          document.body.append(frame);
          say({ type: "ready", version: 1 });
          say({ type: "open-url", url: "https://acme.example.com/posts/dark-mode" });
        </script>
        </body></html>
        """

    @MainActor
    @Suite(.serialized) struct WebViewTests {
        @Test func signsTheAppsUserInWhenTheWidgetIsReadyAndTakesItsLinks() async throws {
            var events: [SwingbackEvent] = []
            var opened: [URL] = []
            let settings = WidgetSettings.defaults(origin: "https://acme.example.com")
            let widget = WidgetWebView(settings: settings, token: { "a.b.c" }, pendingLogout: false) { events.append($0) }
            widget.opener = { opened.append($0) }
            widget.webView.loadHTMLString(widgetPage, baseURL: URL(string: "https://acme.example.com/widget"))
            await eventually { events.count >= 2 }
            #expect(events == [.ready(version: 1), .identified])
            #expect(opened == [URL(string: "https://acme.example.com/posts/dark-mode")!])
            let heard = try await widget.webView.evaluateJavaScript("JSON.stringify(window.heard)") as? String
            #expect(heard == #"[{"source":"swingback","token":"a.b.c","type":"identify"}]"#)

            await widget.logout()
            #expect(events.last == .signedOut)
            #expect(!events.contains(.error(code: "from_a_frame")))
            widget.close()
        }

        @Test func takesNoMessageFromAnotherOrigin() async throws {
            var events: [SwingbackEvent] = []
            let settings = WidgetSettings.defaults(origin: "https://feedback.acme.com")
            let widget = WidgetWebView(settings: settings, token: { "a.b.c" }, pendingLogout: false) { events.append($0) }
            // The page loads where the policy would never let it: what it says still counts for nothing.
            widget.webView.navigationDelegate = nil
            widget.webView.loadHTMLString(widgetPage, baseURL: URL(string: "https://elsewhere.example/widget"))
            await eventually { !widget.webView.isLoading }
            await settled()
            // It said "ready" and handed a link, which nobody took, and heard nothing.
            #expect(try await widget.webView.evaluateJavaScript("window.said") as? Int == 2)
            #expect(try await widget.webView.evaluateJavaScript("window.heard.length") as? Int == 0)
            #expect(events == [])
            widget.close()
        }
    }
#endif
