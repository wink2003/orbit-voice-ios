import Foundation

@main
struct AdminStagingCleanupLogicTests {
    static func main() {
        precondition(AdminStagingCleanupLogic.message(forError: "nothing_to_prune").hasPrefix("Нічого прибирати"))
        precondition(AdminStagingCleanupLogic.message(forError: "plan_changed").contains("План змінився"))
        precondition(AdminStagingCleanupLogic.message(forError: "refused").contains("реліз"))
        precondition(AdminStagingCleanupLogic.message(forError: nil) == "Не вдалося виконати очищення.")
        precondition(AdminStagingCleanupLogic.message(forError: "weird") == "Не вдалося виконати очищення.", "unknown codes never leak raw server text")
        precondition(AdminStagingCleanupLogic.categoryTitle("oci-staging") == "Образи релізів (OCI)")
        precondition(AdminStagingCleanupLogic.categoryTitle("x") == "x")
        precondition(AdminStagingCleanupLogic.bytesText(0) == "0 МБ")
        precondition(AdminStagingCleanupLogic.bytesText(5 * 1_048_576) == "5 МБ")
        precondition(AdminStagingCleanupLogic.bytesText(1.84 * 1_073_741_824) == "1.84 ГБ")
        precondition(AdminStagingCleanupLogic.summary(count: 25, bytes: 1.84 * 1_073_741_824) == "25 каталогів · 1.84 ГБ")
        precondition(AdminStagingCleanupLogic.summary(count: 1, bytes: 1_048_576) == "1 каталог · 1 МБ")
        precondition(AdminStagingCleanupLogic.summary(count: 3, bytes: 0) == "3 каталоги · 0 МБ")
        precondition(AdminStagingCleanupLogic.errorCode(from: Data("{\"error\":\"plan_changed\"}".utf8)) == "plan_changed")
        precondition(AdminStagingCleanupLogic.errorCode(from: Data("not json".utf8)) == nil)
        print("AdminStagingCleanupLogicTests passed")
    }
}
