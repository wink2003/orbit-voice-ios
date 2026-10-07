import Foundation

struct Boom: Error {}

@main
struct OrbitSourceStateTests {
    static func main() {
        let unavailable: (Error) -> Bool = { $0 is OrbitHTTPFailure }
        let empty: ([Int]) -> Bool = { $0.isEmpty }

        precondition(OrbitSourceStateBuilder.resolve(result: .success([]), isEmpty: empty, previous: .loading, isUnavailable: unavailable) == .empty, "empty")
        precondition(OrbitSourceStateBuilder.resolve(result: .success([1]), isEmpty: empty, previous: .loading, isUnavailable: unavailable) == .loaded([1], stale: false), "loaded")
        precondition(OrbitSourceStateBuilder.resolve(result: .failure(OrbitHTTPFailure.unavailable(status: 403)), isEmpty: empty, previous: .loaded([1], stale: false), isUnavailable: unavailable) == .unavailable, "403 is unavailable, not stale")
        precondition(OrbitSourceStateBuilder.resolve(result: .failure(Boom()), isEmpty: empty, previous: .loaded([1], stale: false), isUnavailable: unavailable) == .loaded([1], stale: true), "failed refresh keeps stale data")
        precondition(OrbitSourceStateBuilder.resolve(result: .failure(Boom()), isEmpty: empty, previous: .loading, isUnavailable: unavailable).value == nil, "failed first load has no value")
        if case .failed = OrbitSourceStateBuilder.resolve(result: .failure(Boom()), isEmpty: empty, previous: .loading, isUnavailable: unavailable) {} else { preconditionFailure("failed state") }

        precondition(OrbitHTTPFailure.classify(status: 403) == .unavailable(status: 403), "403")
        precondition(OrbitHTTPFailure.classify(status: 404) == .unavailable(status: 404), "404")
        precondition(OrbitHTTPFailure.classify(status: 500) == nil, "500 is a real error")
        precondition(OrbitHTTPFailure.classify(status: 401) == nil, "401 is a real error")

        let now = Date(timeIntervalSince1970: 1_000_000)
        precondition(OrbitFreshness.label(from: nil, now: now) == nil, "no fabricated freshness")
        precondition(OrbitFreshness.label(from: now.addingTimeInterval(-30), now: now) == "щойно", "just now")
        precondition(OrbitFreshness.label(from: now.addingTimeInterval(-600), now: now) == "10 хв тому", "minutes")
        precondition(OrbitFreshness.label(from: now.addingTimeInterval(-7200), now: now) == "2 год тому", "hours")
        precondition(OrbitFreshness.label(from: now.addingTimeInterval(-172_800), now: now) == "2 дн. тому", "days")
        print("OrbitSourceStateTests passed")
    }
}
