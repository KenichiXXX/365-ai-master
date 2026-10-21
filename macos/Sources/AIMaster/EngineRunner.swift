import Foundation

enum EngineError: Error { case missing, failed(Int32), badJSON }

struct EngineResult {
    let snapshot: Snapshot
    let json: String
}

struct EngineRunner {
    static func engineURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["AIMASTER_ENGINE"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.url(forResource: "365engine", withExtension: nil)
    }

    static var contentURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("365AIMaster/content.json")
    }

    static func snapshotArguments(locale: String, tools: [String], content: URL = contentURL) -> [String] {
        var arguments = ["snapshot", "--json", "--locale", locale, "--tools", tools.joined(separator: ",")]
        if FileManager.default.fileExists(atPath: content.path) { arguments += ["--content", content.path] }
        return arguments
    }

    // The engine owns the self-report allowlist and rejects log-detectable cards.
    static func markTried(id: String) throws -> Bool {
        guard let url = engineURL() else { throw EngineError.missing }
        let process = Process()
        process.executableURL = url
        process.arguments = ["mark-tried", id]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EngineError.failed(process.terminationStatus) }
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Bool],
              let ok = response["ok"] else { throw EngineError.badJSON }
        return ok
    }

    static func run(locale: String, tools: [String]) throws -> EngineResult {
        guard let url = engineURL() else { throw EngineError.missing }
        let process = Process()
        process.executableURL = url
        process.arguments = snapshotArguments(locale: locale, tools: tools)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try decode(data, status: process.terminationStatus)
    }

    static func decode(_ data: Data, status: Int32) throws -> EngineResult {
        guard status == 0 else { throw EngineError.failed(status) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              [1, 2, 3].contains(snapshot.schema), snapshot.error == nil else { throw EngineError.badJSON }
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return EngineResult(snapshot: snapshot, json: String(decoding: pretty, as: UTF8.self))
    }
}
