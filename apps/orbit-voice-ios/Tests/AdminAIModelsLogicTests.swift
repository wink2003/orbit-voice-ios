import Foundation

@main
struct AdminAIModelsLogicTests {
    static func main() {
        precondition(AdminAIModelsLogic.taskTitle("school.intelligence") == "School: аналіз листів")
        precondition(AdminAIModelsLogic.taskTitle("x.y") == "x.y")
        precondition(AdminAIModelsLogic.priceText(inPerM: 0, outPerM: 0) == "безкоштовно")
        precondition(AdminAIModelsLogic.priceText(inPerM: nil, outPerM: 1) == "ціна невідома")
        precondition(AdminAIModelsLogic.priceText(inPerM: 2, outPerM: 10) == "$2.00 / $10.00 за 1M")
        precondition(AdminAIModelsLogic.priceText(inPerM: 0.0399, outPerM: 0.0784) == "$0.0399 / $0.0784 за 1M")
        precondition(AdminAIModelsLogic.per1000Text(nil) == nil)
        precondition(AdminAIModelsLogic.per1000Text(0) == "$0 за 1000 викликів")
        precondition(AdminAIModelsLogic.per1000Text(2.5279) == "$2.53 за 1000 викликів")
        precondition(AdminAIModelsLogic.message(forError: "benchmark_required").contains("порівняння"))
        precondition(AdminAIModelsLogic.message(forError: "weird") == "Не вдалося виконати. Спробуйте ще раз.", "unknown codes never leak raw server text")
        precondition(AdminAIModelsLogic.errorCode(from: Data("{\"error\":\"proposal_expired\"}".utf8)) == "proposal_expired")
        precondition(AdminAIModelsLogic.errorCode(from: Data("nope".utf8)) == nil)

        // Server payload shapes (camelCase keys, fractional-second dates are never decoded as Date).
        let overviewJSON = """
        {"tasks":[{"taskId":"school.calendar_relevance","policyVersion":3,"fallbackMode":"safe_automatic","reason":"x","since":"2026-11-15T00:00:00.000Z","switchable":true,
          "primary":{"bindingId":"openrouter.glm-5-3-flash","providerId":"openrouter","model":"z-ai/glm-5.3-flash","name":"GLM","inPerM":0.0399,"outPerM":0.0784},
          "fallbacks":[{"bindingId":"openrouter.particle-1-free","providerId":"openrouter","model":"particle-ai/particle-1:free","name":"Particle","inPerM":0,"outPerM":0}],
          "usage7d":{"calls":100,"ok":57,"cost":0.1234,"p95":18002}}],
         "candidates":[{"id":"z-ai/glm-5.3-flash","name":"GLM","inPerM":0.0399,"outPerM":0.0784,"context":200000,"free":false,"structured":true}],
         "lastJob":{"id":"abc","status":"done","startedAt":"2026-11-15T10:00:00.123Z","models":["z-ai/glm-5.3-flash"],"results":[{"model":"z-ai/glm-5.3-flash","pass":true,"rel":"22/24","intel":"3/3","validRate":1,"seconds":49,"costUsd":0.000535,"costPer1000":0.0198,"capped":false,"errors":{}}],"error":null},
         "supportedTasks":["school.calendar_relevance"]}
        """
        let overview = try! JSONDecoder().decode(AIModelsOverview.self, from: Data(overviewJSON.utf8))
        precondition(overview.tasks.count == 1 && overview.tasks[0].switchable)
        precondition(AdminAIModelsLogic.chainText(primary: overview.tasks[0].primary, fallbacks: overview.tasks[0].fallbacks) == "z-ai/glm-5.3-flash → particle-ai/particle-1:free")
        precondition(AdminAIModelsLogic.usageText(overview.tasks[0].usage7d) == "100 викликів · 57% успішно · $0.123 · p95 18 с")
        precondition(AdminAIModelsLogic.usageText(AIModelUsage(calls: 0, ok: 0, cost: 0, p95: nil)) == "за 7 днів викликів не було")
        precondition(AdminAIModelsLogic.passingModels(overview.lastJob) == ["z-ai/glm-5.3-flash"])
        precondition(AdminAIModelsLogic.passingModels(nil).isEmpty)
        precondition(AdminAIModelsLogic.resultText(overview.lastJob!.results[0]) == "проходить · події 22/24 · листи 3/3 · 49 с · $0.0198 за 1000 викликів")
        precondition(overview.candidates[0].free == false)

        let proposalJSON = """
        {"id":"p1","taskId":"school.intelligence","expiresAt":"2026-11-15T10:10:00.000Z","current":{"primary":"a","fallbacks":["b"],"policyVersion":3},
         "proposed":[{"model":"z-ai/glm-5.3-flash","name":"GLM","inPerM":0.0399,"outPerM":0.0784,"costPer1000":null}],"summary":"rel 22/24"}
        """
        let proposal = try! JSONDecoder().decode(AIModelProposal.self, from: Data(proposalJSON.utf8))
        precondition(proposal.proposed[0].costPer1000 == nil && proposal.current.policyVersion == 3)
        print("AdminAIModelsLogicTests: ok")
    }
}
