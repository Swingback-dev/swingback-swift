import Foundation
import Testing

@testable import Swingback

// This package's copy of the protocol, held to its files (sdks/protocol, ADR 0034): the version, the
// bridge's name, the pages, the limits, every message of the widget's to read and to ignore, and what this
// package says to it.

@Suite struct ProtocolTests {
    @Test func isTheFilesVersionSourceBridgeAndLimits() throws {
        let file = try protocolFile("widget-protocol.json")
        #expect(protocolVersion == file["version"] as? Int)
        #expect(messageSource == file["source"] as? String)
        let limits = try #require(file["limits"] as? [String: Any])
        #expect(tokenMaxLength == limits["tokenMaxLength"] as? Int)
        let channels = try #require(file["channels"] as? [String: Any])
        let ios = try #require(channels["ios"] as? [String: Any])
        #expect(ios["bridge"] as? String == "webkit.messageHandlers.\(bridgeName)")
    }

    @Test func pagesAreTheFiles() throws {
        let pages = try #require(try protocolFile("widget-protocol.json")["pages"] as? [String: String])
        #expect(SwingbackPage.feedback.path == pages["feedback"])
        #expect(SwingbackPage.roadmap.path == pages["roadmap"])
        #expect(SwingbackPage.changelog.path == pages["changelog"])
        #expect(SwingbackPage.new.path == pages["new"])
        #expect(SwingbackPage.post("dark-mode").path == pages["post"]?.replacingOccurrences(of: "{slug}", with: "dark-mode"))
        #expect(SwingbackPage.board("ideas").path == pages["board"]?.replacingOccurrences(of: "{slug}", with: "ideas"))
    }

    @Test func escapesASlugAsTheJavaScriptSDKDoes() {
        #expect(SwingbackPage.board("a b/c").path == "/widget/boards/a%20b%2Fc")
        #expect(SwingbackPage.post("café").path == "/widget/posts/caf%C3%A9")
        #expect(SwingbackPage.post("").path == "/widget")
    }

    @Test func readsEveryMessageOfTheWidgetsAsTheFileSays() throws {
        let fixtures = try #require(try protocolFile("fixtures.json")["toHost"] as? [String: Any])
        let accept = try #require(fixtures["accept"] as? [[String: Any]])
        var types: Set<String> = []
        for fixture in accept {
            let message = try #require(fixture["message"])
            let reads = try #require(fixture["reads"] as? [String: Any])
            let type = try #require(reads["type"] as? String)
            types.insert(type)
            let expected: WidgetMessage? =
                switch type {
                case "ready": .ready(version: reads["version"] as? Int ?? -1)
                case "identified": .identified
                case "signed-out": .signedOut
                case "error": .error(code: reads["code"] as? String ?? "")
                case "open-url": (reads["url"] as? String).flatMap(URL.init(string:)).map(WidgetMessage.openURL)
                default: nil
                }
            let text = try jsonText(message)
            #expect(WidgetMessage(json: text) == expected, "\(text)")
        }
        let toHost = try #require(try protocolFile("widget-protocol.json")["toHost"] as? [String: Any])
        #expect(types == Set(toHost.keys))
    }

    @Test func ignoresWhatTheWidgetNeverSays() throws {
        let fixtures = try #require(try protocolFile("fixtures.json")["toHost"] as? [String: Any])
        let reject = try #require(fixtures["reject"] as? [Any])
        for message in reject {
            let text = try jsonText(message)
            #expect(WidgetMessage(json: text) == nil, "\(text)")
        }
        #expect(WidgetMessage(json: "{not json") == nil)
    }

    @Test func saysToTheWidgetOnlyWhatItReads() throws {
        let fixtures = try #require(try protocolFile("fixtures.json")["toWidget"] as? [String: Any])
        let accept = try #require(fixtures["accept"] as? [[String: Any]])
        let read = try accept.map { try jsonValue(try #require($0["message"])) }
        let pages: [SwingbackPage] = [.feedback, .roadmap, .changelog, .new, .post("dark-mode"), .board("ideas")]
        let said: [HostMessage] =
            [.identify(token: "a.b.c"), .identify(token: nil), .logout] + pages.map { .navigate(path: $0.path) }
        for message in said {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(message.json.utf8))
            #expect(read.contains(value), "\(message.json)")
        }
        let toWidget = try #require(try protocolFile("widget-protocol.json")["toWidget"] as? [String: Any])
        let types = Set(said.map { message in
            switch message {
            case .identify: "identify"
            case .logout: "logout"
            case .navigate: "navigate"
            }
        })
        #expect(types == Set(toWidget.keys))
    }
}
