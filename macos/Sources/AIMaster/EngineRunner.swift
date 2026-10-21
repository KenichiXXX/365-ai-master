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

    static func run(locale: String, tools: [String]) throws -> EngineResult {
        guard let url = engineURL() else { throw EngineError.missing }
        let process = Process()
        process.executableURL = url
        process.arguments = ["snapshot", "--json", "--locale", locale, "--tools", tools.joined(separator: ",")]
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
              snapshot.schema == 1, snapshot.error == nil else { throw EngineError.badJSON }
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return EngineResult(snapshot: snapshot, json: String(decoding: pretty, as: UTF8.self))
    }
}
