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

    // The engine accepts self-report only for manual or currently unsupported validators.
    static func markTried(id: String) throws -> Bool {
        try actionCommand(["mark-tried", id])
    }

    static func actionCommand(_ arguments: [String]) throws -> Bool {
        guard let url = engineURL() else { throw EngineError.missing }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
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

    static func run(locale: String, tools: [String], scan: EngineScan = EngineScan()) throws -> EngineResult {
        guard let url = engineURL() else { throw EngineError.missing }
        let (data, status) = try scan.run(executable: url, arguments: snapshotArguments(locale: locale, tools: tools))
        return try decode(data, status: status)
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

final class EngineScan: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func run(executable: URL, arguments: [String]) throws -> (Data, Int32) {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        process = child
        do { try child.run() }
        catch { process = nil; lock.unlock(); throw error }
        lock.unlock()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        lock.lock()
        process = nil
        let discard = cancelled
        lock.unlock()
        guard !discard else { throw CancellationError() }
        return (data, child.terminationStatus)
    }
}
