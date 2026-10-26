import Foundation

// What the SDK says to the widget, and when (ADR 0034, decisions 3 and 5), as the JavaScript SDK's
// WidgetSession says it: at each `ready`, the token of the app's signed-in user, or nil for nobody; a
// sign-out asked for while no widget listened goes first; one request at a time, each waiting for its answer,
// since the widget handles them as they come. Nothing here touches a web view: a test speaks for the widget.

/// What the widget did, or that the app's sheet opened or closed.
public enum SwingbackEvent: Equatable, Sendable {
    /// The widget can take requests, in this version of the protocol.
    case ready(version: Int)
    /// The widget signed the app's user in.
    case identified
    /// The widget has nobody signed in now.
    case signedOut
    /// The widget couldn't do what was asked: one of the widget's error codes, or `token_unavailable` when
    /// the token couldn't be had.
    case error(code: String)
    case open
    case close
}

/// Where the SDK gets the identity token of the app's signed-in user, or nil for nobody: from the app's
/// server, never from the app itself, which holds no identity secret.
public typealias SwingbackTokenProvider = @Sendable () async throws -> String?

/// How long a request waits for the widget's answer before the next one goes.
let answerTimeout: Duration = .seconds(15)

@MainActor
final class WidgetSession {
    private let send: @MainActor (HostMessage) -> Void
    private let token: SwingbackTokenProvider?
    private let emit: @MainActor (SwingbackEvent) -> Void
    private let timeout: Duration
    /// The protocol of the widget's document, once it said it was ready; nil until then.
    private(set) var version: Int?
    /// Each document's ready starts a generation: what an earlier one asked stops there.
    private var generation = 0
    private var pendingLogout: Bool
    private var queue: Task<Void, Never>?
    private var waiter: Waiter?

    init(
        send: @escaping @MainActor (HostMessage) -> Void,
        token: SwingbackTokenProvider?,
        emit: @escaping @MainActor (SwingbackEvent) -> Void,
        pendingLogout: Bool = false,
        timeout: Duration = answerTimeout
    ) {
        self.send = send
        self.token = token
        self.emit = emit
        self.pendingLogout = pendingLogout
        self.timeout = timeout
    }

    /// A message of the widget's (its frame and origin already checked).
    func receive(_ message: WidgetMessage) {
        switch message {
        case .openURL:
            // Not an answer: the app opens the link itself.
            return
        case .ready(let version):
            generation += 1
            self.version = version
            // An answer the previous document owed will not come.
            settle()
            emit(.ready(version: version))
            let generation = self.generation
            enqueue { await self.start(generation) }
        case .identified:
            emit(.identified)
            settle()
        case .signedOut:
            emit(.signedOut)
            settle()
        case .error(let code):
            emit(.error(code: code))
            settle()
        }
    }

    /// Says who the app's user is again (another user, or nobody): now, or at the widget's next `ready`.
    func identify() async {
        guard version != nil else { return }
        let generation = self.generation
        await enqueue { await self.identify(as: generation) }.value
    }

    /// Ends the widget's session, a guest's too: now, or first thing at its next `ready`.
    func logout() async {
        guard version != nil else {
            pendingLogout = true
            return
        }
        let generation = self.generation
        await enqueue { await self.ask(.logout, generation: generation) }.value
    }

    /// Shows a page of the widget in its document; false when it can't (not ready, or version 0).
    func navigate(to path: String) -> Bool {
        guard let version, version >= 1 else { return false }
        send(.navigate(path: path))
        return true
    }

    /// The widget's document is gone: nothing to speak to until the next `ready`.
    func detach() {
        generation += 1
        version = nil
        settle()
    }

    private func start(_ generation: Int) async {
        if pendingLogout {
            pendingLogout = false
            await ask(.logout, generation: generation)
        }
        await identify(as: generation)
    }

    private func identify(as generation: Int) async {
        guard let token else { return }
        let value: String?
        do {
            value = try await token()
        } catch {
            emit(.error(code: "token_unavailable"))
            return
        }
        if let value, value.isEmpty || value.utf16.count > tokenMaxLength {
            emit(.error(code: "token_unavailable"))
            return
        }
        // A newer document took over while the token came: its own `ready` asks again.
        guard generation == self.generation else { return }
        // A widget of version 0 takes no nil: it is left as it is.
        if value == nil, (version ?? 0) < 1 { return }
        await ask(.identify(token: value), generation: generation)
    }

    private func ask(_ message: HostMessage, generation: Int) async {
        guard generation == self.generation else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = Waiter(continuation)
            self.waiter = waiter
            let timeout = self.timeout
            waiter.timer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                if self?.waiter === waiter { self?.waiter = nil }
                waiter.resume()
            }
            send(message)
        }
    }

    private func settle() {
        let waiter = self.waiter
        self.waiter = nil
        waiter?.resume()
    }

    @discardableResult
    private func enqueue(_ task: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = queue
        let next = Task { @MainActor in
            await previous?.value
            await task()
        }
        queue = next
        return next
    }
}

/// A request's wait for its answer, ended once: by the answer, the next document or the timeout.
@MainActor
private final class Waiter {
    private var continuation: CheckedContinuation<Void, Never>?
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        timer?.cancel()
        timer = nil
        continuation?.resume()
        continuation = nil
    }
}
