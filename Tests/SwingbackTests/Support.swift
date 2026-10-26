import Foundation

@testable import Swingback

// What the tests share: the protocol's files (sdks/protocol, which this package's copy is held to) and a
// way to wait for what the main actor's tasks do.

/// The protocol's folder: beside this package in the repository (sdks/protocol), or inside it where a
/// release copied it (protocol/).
private let protocolFolder: URL = {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let beside = package.deletingLastPathComponent().appendingPathComponent("protocol")
    let inside = package.appendingPathComponent("protocol")
    return FileManager.default.fileExists(atPath: beside.path) ? beside : inside
}()

/// One of the protocol's JSON files, as JSONSerialization reads it.
func protocolFile(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: protocolFolder.appendingPathComponent(name))
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return document
}

/// A value of a JSON file as JSON text.
func jsonText(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
}

/// A value of a JSON file as this package reads JSON.
func jsonValue(_ value: Any) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(try jsonText(value).utf8))
}

/// Waits until `condition` holds, two seconds at most.
@MainActor
func eventually(_ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Lets what the main actor's tasks would do happen, when the test expects nothing more.
func settled() async {
    try? await Task.sleep(for: .milliseconds(50))
}
