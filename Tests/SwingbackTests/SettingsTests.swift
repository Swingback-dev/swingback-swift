import Foundation
import Testing

@testable import Swingback

// What the SDK reads of a portal's settings (ADR 0034, decision 7): the protocol file's example, as the
// JavaScript SDK reads it, and what it does with a document it can't use.

@Suite struct SettingsTests {
    @Test func readsTheFilesExampleAsTheFileSays() throws {
        let example = try #require(try protocolFile("fixtures.json")["settings"] as? [String: Any])
        let document = try #require(example["document"])
        let reads = try #require(example["reads"] as? [String: Any])
        let settings = WidgetSettings.read(Data(try jsonText(document).utf8), origin: "https://acme.example.com")
        let accent = try #require(reads["accent"] as? [String: String])
        let labels = try #require(reads["labels"] as? [String: String])
        #expect(settings.origin == reads["origin"] as? String)
        #expect(settings.accent == WidgetSettings.Accent(color: accent["color"] ?? "", foreground: accent["foreground"] ?? ""))
        #expect(settings.position.rawValue == reads["position"] as? String)
        #expect(settings.theme.rawValue == reads["theme"] as? String)
        #expect(settings.language == reads["language"] as? String)
        #expect(
            settings.labels
                == WidgetSettings.Labels(open: labels["open"] ?? "", close: labels["close"] ?? "", loading: labels["loading"] ?? "")
        )
    }

    @Test func keepsTheDefaultsOfWhatItCantUse() {
        let origin = "https://acme.example.com"
        let defaults = WidgetSettings.defaults(origin: origin)
        #expect(WidgetSettings.read(Data("[]".utf8), origin: origin) == defaults)
        #expect(WidgetSettings.read(Data("not json".utf8), origin: origin) == defaults)
        let odd = """
            {"portal_url": "ftp://elsewhere", "accent": {"color": "red", "foreground": "#ffffff"}, "position": "top",
             "theme": "sepia", "language": "fra", "labels": {"open": " ", "close": 42, "loading": "\(String(repeating: "x", count: 41))"}}
            """
        #expect(WidgetSettings.read(Data(odd.utf8), origin: origin) == defaults)
    }

    @Test func namesAnAddressesOrigin() {
        #expect(originOf("HTTPS://Feedback.Acme.com:443/widget?x=1") == "https://feedback.acme.com")
        #expect(originOf("http://acme.localhost:3180/") == "http://acme.localhost:3180")
        #expect(originOf("http://[::1]:8080") == "http://[::1]:8080")
        #expect(originOf("ftp://acme.example.com") == nil)
        #expect(originOf("acme.example.com") == nil)
    }

    @Test func pagesAreAtTheCanonicalOrigin() {
        let settings = WidgetSettings.defaults(origin: "https://feedback.acme.com")
        #expect(settings.url(of: .changelog)?.absoluteString == "https://feedback.acme.com/widget/changelog")
    }
}
