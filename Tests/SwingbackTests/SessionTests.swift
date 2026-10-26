import Foundation
import Testing

@testable import Swingback

// What the SDK says to the widget, and when (ADR 0034, decisions 3 and 5), as the JavaScript SDK's
// session tests say it. The widget is a stand-in that records what it is told and answers when the test says.

@MainActor
private final class Rig {
    var said: [HostMessage] = []
    var events: [SwingbackEvent] = []
    var session: WidgetSession!

    init(
        pendingLogout: Bool = false,
        timeout: Duration = .seconds(15),
        token: SwingbackTokenProvider? = { "a.b.c" }
    ) {
        session = WidgetSession(
            send: { [unowned self] message in said.append(message) },
            token: token,
            emit: { [unowned self] event in events.append(event) },
            pendingLogout: pendingLogout,
            timeout: timeout
        )
    }

    func widget(_ message: WidgetMessage) {
        session.receive(message)
    }
}

/// Counts the calls of a token provider, which the session calls off the main actor.
private actor Counter {
    private(set) var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

@MainActor
@Suite struct SessionTests {
    @Test func signsTheAppsUserInAtEachReadyWithAFreshToken() async {
        let counter = Counter()
        let rig = Rig(token: { "token-\(await counter.next())" })
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        #expect(rig.said == [.identify(token: "token-1")])
        rig.widget(.identified)
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 2 }
        #expect(rig.said.last == .identify(token: "token-2"))
        #expect(rig.events == [.ready(version: 1), .identified, .ready(version: 1)])
    }

    @Test func saysNobodyIsSignedInToAWidgetOfVersionOneOnly() async {
        let one = Rig(token: { nil })
        one.widget(.ready(version: 1))
        await eventually { one.said.count == 1 }
        #expect(one.said == [.identify(token: nil)])
        let zero = Rig(token: { nil })
        zero.widget(.ready(version: 0))
        await settled()
        #expect(zero.said == [])
    }

    @Test func saysNothingWithoutATokenProviderAndReportsOneThatFails() async {
        let none = Rig(token: nil)
        none.widget(.ready(version: 1))
        await settled()
        #expect(none.said == [])
        struct Down: Error {}
        let failing = Rig(token: { throw Down() })
        failing.widget(.ready(version: 1))
        await eventually { failing.events.count == 2 }
        #expect(failing.said == [])
        #expect(failing.events.last == .error(code: "token_unavailable"))
        let odd = Rig(token: { String(repeating: "x", count: 16385) })
        odd.widget(.ready(version: 1))
        await eventually { odd.events.count == 2 }
        #expect(odd.said == [])
        #expect(odd.events.last == .error(code: "token_unavailable"))
    }

    @Test func signsOutFirstAtTheNextReadyWhenAskedBeforeThenWaitsForTheAnswer() async {
        let rig = Rig()
        await rig.session.logout()
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        #expect(rig.said == [.logout])
        rig.widget(.signedOut)
        await eventually { rig.said.count == 2 }
        #expect(rig.said.last == .identify(token: "a.b.c"))
        let pending = Rig(pendingLogout: true)
        pending.widget(.ready(version: 1))
        await eventually { pending.said.count == 1 }
        #expect(pending.said == [.logout])
    }

    @Test func asksOneThingAtATime() async {
        let rig = Rig()
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        Task { await rig.session.logout() }
        Task { await rig.session.identify() }
        await settled()
        #expect(rig.said == [.identify(token: "a.b.c")])
        rig.widget(.identified)
        await eventually { rig.said.count == 2 }
        #expect(rig.said.last == .logout)
        rig.widget(.signedOut)
        await eventually { rig.said.count == 3 }
        #expect(rig.said.last == .identify(token: "a.b.c"))
    }

    @Test func goesOnWhenAnAnswerDoesntCome() async {
        let rig = Rig(timeout: .milliseconds(30))
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        await rig.session.logout()
        #expect(rig.said.last == .logout)
    }

    @Test func dropsWhatAnEarlierDocumentAskedOnceANewOneIsReady() async {
        let rig = Rig()
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        Task { await rig.session.logout() }
        await settled()
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 2 }
        await settled()
        #expect(rig.said == [.identify(token: "a.b.c"), .identify(token: "a.b.c")])
    }

    @Test func showsAPageInTheSameDocumentOnlyOnAWidgetOfVersionOneOnceReady() async {
        let rig = Rig()
        #expect(!rig.session.navigate(to: "/widget/changelog"))
        rig.widget(.ready(version: 0))
        #expect(!rig.session.navigate(to: "/widget/changelog"))
        rig.widget(.ready(version: 1))
        #expect(rig.session.navigate(to: "/widget/changelog"))
        #expect(rig.said.contains(.navigate(path: "/widget/changelog")))
        rig.session.detach()
        #expect(!rig.session.navigate(to: "/widget/roadmap"))
    }

    @Test func takesALinkTheWidgetHandsTheAppForNoAnswer() async {
        let rig = Rig()
        rig.widget(.ready(version: 1))
        await eventually { rig.said.count == 1 }
        Task { await rig.session.logout() }
        await settled()
        rig.widget(.openURL(URL(string: "https://acme.example.com/posts/dark-mode")!))
        await settled()
        #expect(rig.said == [.identify(token: "a.b.c")])
        #expect(rig.events == [.ready(version: 1)])
        rig.widget(.identified)
        await eventually { rig.said.count == 2 }
        #expect(rig.said.last == .logout)
    }
}
