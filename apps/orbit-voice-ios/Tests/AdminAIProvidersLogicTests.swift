import Foundation

@main
struct AdminAIProvidersLogicTests {
    static func main() {
        let ok = AIProviderState(provider: "openrouter", open: false, openedAt: nil, lastStatus: nil)
        let stopped = AIProviderState(provider: "openrouter", open: true, openedAt: Date(), lastStatus: 402)
        let auth = AIProviderState(provider: "openrouter", open: true, openedAt: Date(), lastStatus: 401)
        precondition(AdminAIProvidersLogic.title("openrouter") == "OpenRouter")
        precondition(AdminAIProvidersLogic.title("x") == "x")
        precondition(AdminAIProvidersLogic.statusText(ok) == "Працює")
        precondition(AdminAIProvidersLogic.statusText(stopped).contains("402"))
        precondition(AdminAIProvidersLogic.statusText(auth).contains("ключ"))
        precondition(AdminAIProvidersLogic.attention([ok]) == nil)
        precondition(AdminAIProvidersLogic.attention([stopped])?.contains("Старт") == true)
        let json = Data("{\"provider\":\"openrouter\",\"open\":true,\"opened_at\":\"2026-11-15T10:00:00Z\",\"last_status\":402}".utf8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(AIProviderState.self, from: json)
        precondition(decoded.open && decoded.lastStatus == 402 && decoded.openedAt != nil)
        let closed = try! decoder.decode(AIProviderState.self, from: Data("{\"provider\":\"openrouter\",\"open\":false,\"opened_at\":null,\"last_status\":null}".utf8))
        precondition(!closed.open && closed.openedAt == nil)
        print("AdminAIProvidersLogicTests: ok")
    }
}
