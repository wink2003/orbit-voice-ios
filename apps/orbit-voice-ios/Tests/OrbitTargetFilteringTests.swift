import Foundation

@main
struct OrbitTargetFilteringTests {
    static func main() {
        let targets = ["viktoriia", "oleksii", "another"]
        let selectable = OrbitTargetFiltering.selectableTargetIds(targets, principalPersonId: "oleksandr")
        precondition(selectable == targets, "all server-authorized targets remain selectable")
        precondition(OrbitTargetFiltering.selectableTargetIds(targets, principalPersonId: "viktoriia") == ["oleksii", "another"], "principal is excluded only")
        precondition(OrbitTargetFiltering.selectableTargetIds([], principalPersonId: "oleksandr").isEmpty, "empty target list")
        print("OrbitTargetFilteringTests: PASS")
    }
}
