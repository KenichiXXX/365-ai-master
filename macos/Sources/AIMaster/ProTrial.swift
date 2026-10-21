import Foundation

@MainActor
final class ProTrial {
    static let duration: TimeInterval = 14 * 86400
    static let storageKey = "proTrial"

    enum ExpiryReason: String, Codable { case deadline, clockRollback, corrupt }
    enum Status: Equatable {
        case eligible
        case active(until: Date)
        case expired(ExpiryReason)
    }

    private struct State: Codable {
        var consumed: Bool
        var start: TimeInterval
        var end: TimeInterval
        var maximumObserved: TimeInterval
        var expired: Bool
        var reason: ExpiryReason?

        var valid: Bool {
            consumed && start.isFinite && end.isFinite && maximumObserved.isFinite
                && end == start + ProTrial.duration && maximumObserved >= start
                && expired == (reason != nil)
        }
    }

    let clock: () -> Date
    private let read: () -> Data?
    private let write: (Data) -> Void

    init(clock: @escaping () -> Date = Date.init, read: @escaping () -> Data?, write: @escaping (Data) -> Void) {
        self.clock = clock
        self.read = read
        self.write = write
    }

    convenience init(defaults: UserDefaults) {
        self.init(read: {
            guard let value = defaults.object(forKey: Self.storageKey) else { return nil }
            return value as? Data ?? Data()
        }, write: { defaults.set($0, forKey: Self.storageKey) })
    }

    @discardableResult
    func evaluate() -> Status {
        guard let data = read() else { return .eligible }
        let now = clock().timeIntervalSince1970
        guard var state = try? JSONDecoder().decode(State.self, from: data), state.valid else {
            save(State(consumed: true, start: now, end: now + Self.duration,
                       maximumObserved: now, expired: true, reason: .corrupt))
            return .expired(.corrupt)
        }
        if state.expired { return .expired(state.reason!) }
        let reason: ExpiryReason? = now < state.maximumObserved ? .clockRollback : now >= state.end ? .deadline : nil
        state.maximumObserved = max(now, state.maximumObserved)
        if let reason {
            state.expired = true
            state.reason = reason
            save(state)
            return .expired(reason)
        }
        save(state)
        return .active(until: Date(timeIntervalSince1970: state.end))
    }

    @discardableResult
    func start() -> Status {
        let status = evaluate()
        guard status == .eligible else { return status }
        let now = clock().timeIntervalSince1970
        let state = State(consumed: true, start: now, end: now + Self.duration, maximumObserved: now, expired: false)
        save(state)
        return .active(until: Date(timeIntervalSince1970: state.end))
    }

    private func save(_ state: State) {
        // The state contains only finite timestamps and enums validated at the storage boundary.
        write(try! JSONEncoder().encode(state))
    }
}
