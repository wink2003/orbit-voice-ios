import Foundation

// Per-block state for dashboards: one failing source must not blank the others.
nonisolated enum OrbitSourceState<Value> {
    case loading
    case loaded(Value, stale: Bool)
    case empty
    case unavailable
    case failed(String)

    var value: Value? {
        if case let .loaded(value, _) = self { return value }
        return nil
    }

    var isStale: Bool {
        if case let .loaded(_, stale) = self { return stale }
        return false
    }
}

nonisolated extension OrbitSourceState: Equatable where Value: Equatable {}

nonisolated enum OrbitSourceStateBuilder {
    // `isEmpty` decides empty vs loaded; `previous` keeps old data (marked stale) when a refresh fails.
    static func resolve<Value>(
        result: Result<Value, Error>,
        isEmpty: (Value) -> Bool,
        previous: OrbitSourceState<Value>,
        isUnavailable: (Error) -> Bool
    ) -> OrbitSourceState<Value> {
        switch result {
        case let .success(value):
            return isEmpty(value) ? .empty : .loaded(value, stale: false)
        case let .failure(error):
            if isUnavailable(error) { return .unavailable }
            if let old = previous.value { return .loaded(old, stale: true) }
            return .failed(error.localizedDescription)
        }
    }
}

nonisolated enum OrbitHTTPFailure: Error, Equatable {
    case unavailable(status: Int)

    static func classify(status: Int) -> OrbitHTTPFailure? {
        (status == 403 || status == 404) ? .unavailable(status: status) : nil
    }
}

nonisolated enum OrbitFreshness {
    // Returns nil when there is no timestamp, so callers never fabricate "just updated".
    static func label(from date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 90 { return "щойно" }
        if seconds < 3600 { return "\(Int(seconds / 60)) хв тому" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) год тому" }
        return "\(Int(seconds / 86400)) дн. тому"
    }
}
