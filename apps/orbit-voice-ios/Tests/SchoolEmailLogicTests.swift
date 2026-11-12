import Foundation

@main
struct SchoolEmailLogicTests {
    static func main() {
        precondition(SchoolEmailLogic.sourceTitle("schulmanager") == "Schulmanager")
        precondition(SchoolEmailLogic.sourceTitle("Email") == "Email")
        precondition(SchoolEmailLogic.sourceTitle("other") == "other")

        precondition(SchoolEmailLogic.domainPattern(for: "Frau.A@School.DE") == "@school.de")
        precondition(SchoolEmailLogic.domainPattern(for: " a@b.de ") == "@b.de")
        for bad in ["", "noat", "a@", "a@nodot", "a@.de", "a@de.", "a b@c.de", "a@@b.de"] { precondition(SchoolEmailLogic.domainPattern(for: bad) == nil, bad) }
        precondition(SchoolEmailLogic.exactPattern(for: "Frau.A@School.DE") == "frau.a@school.de")
        precondition(SchoolEmailLogic.exactPattern(for: "a b@c.de") == nil)
        precondition(SchoolEmailLogic.exactPattern(for: "nonsense") == nil)

        precondition(SchoolEmailLogic.decisionSummary(status: "approved", released: 3, rejected: 0, failed: 0) == "Дозволено. Додано листів: 3.")
        precondition(SchoolEmailLogic.decisionSummary(status: "approved", released: 0, rejected: 0, failed: 2).contains("Не вдалося забрати з пошти: 2"))
        precondition(SchoolEmailLogic.decisionSummary(status: "approved", released: 0, rejected: 0, failed: 0) == "Дозволено.")
        precondition(SchoolEmailLogic.decisionSummary(status: "blocked", released: 0, rejected: 4, failed: 0) == "Заблоковано. Відхилено листів: 4.")
        precondition(SchoolEmailLogic.decisionSummary(status: "blocked", released: 0, rejected: 0, failed: 0) == "Заблоковано.")

        precondition(SchoolEmailLogic.statusLine(enabled: false, configured: true, lastError: nil) == "Вимкнено")
        precondition(SchoolEmailLogic.statusLine(enabled: true, configured: false, lastError: nil) == "Скриньку ще не підключено")
        precondition(SchoolEmailLogic.statusLine(enabled: true, configured: true, lastError: "NONEXISTENT").contains("NONEXISTENT"))
        precondition(SchoolEmailLogic.statusLine(enabled: true, configured: true, lastError: nil) == "Працює")
        print("school email logic tests passed")
    }
}
