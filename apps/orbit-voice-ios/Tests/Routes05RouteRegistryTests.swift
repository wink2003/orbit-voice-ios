import Foundation

@main
struct Routes05RouteRegistryTests {
    static func main() {
        precondition(Routes05RouteRegistry.all.count == 32, "ROUTES 05 manifest must contain 32 routes")
        precondition(Set(Routes05RouteRegistry.all.map(\.id)).count == 32, "route IDs must be unique")
        precondition(Routes05RouteRegistry.all.allSatisfy { !$0.owner.isEmpty }, "every route needs an owner")
        precondition(Routes05RouteRegistry.descriptor(for: "inbox")?.owner == "SchoolInboxView")
        precondition(Routes05RouteRegistry.descriptor(for: "unknown")?.owner == "Routes05UnavailableView")
        print("Routes05RouteRegistryTests passed")
    }
}
