import Foundation

@main
struct OrbitAzureSpeechStatsTests {
    static func main() {
        let json = #"""
        {"status":"ok","provider":"azure_speech","currency":"USD","costUsd":0,"billing":"free_tier","updatedAt":"2026-11-10T20:00:00.123Z",
         "periodStart":"2026-11-01T00:00:00.000Z","resetsAt":"2026-12-01T00:00:00.000Z",
         "tasks":[
          {"taskId":"speech.interpreter","policyVersion":3,"calls":4,"tier":{"name":"F0","enforcement":"hard_stop","limits":{"token_issues":20}},"usage":{"stt_seconds":0,"tts_characters":0,"token_issues":5},"remaining":{"token_issues":15}},
          {"taskId":"speech.voice_fallback","policyVersion":1,"calls":1,"tier":{"name":"F0","enforcement":"hard_stop","limits":{"stt_seconds":7200,"tts_characters":100000}},"usage":{"stt_seconds":3600,"tts_characters":25000,"token_issues":1},"remaining":{"stt_seconds":3600,"tts_characters":75000}},
          {"taskId":"speech.other","policyVersion":null,"calls":0,"tier":null,"usage":{},"remaining":null}]}
        """#
        let stats = try! JSONDecoder().decode(AzureSpeechStats.self, from: Data(json.utf8))
        precondition(stats.status == "ok" && stats.costUsd == 0 && stats.tasks.count == 3)
        // Interpreter: one capped dimension (tokens), fraction 5/20.
        let interpreter = AzureSpeechLabels.rows(stats.tasks[0])
        precondition(interpreter.count == 1 && interpreter[0].title == "Сесії (токени)" && interpreter[0].value == "5 із 20")
        precondition(abs((interpreter[0].fraction ?? -1) - 0.25) < 0.0001)
        // Fallback line: STT in hours/minutes and TTS characters.
        let fallback = AzureSpeechLabels.rows(stats.tasks[1])
        precondition(fallback.count == 2)
        precondition(fallback.contains { $0.title == "Розпізнавання мови" && $0.value == "1 год 0 хв із 2 год 0 хв" })
        precondition(fallback.contains { $0.title == "Озвучення (символи)" && $0.value == "25000 із 100000" })
        // Unknown task without a rule: no rows, no crash; labels fall back to ids.
        precondition(AzureSpeechLabels.rows(stats.tasks[2]).isEmpty && AzureSpeechLabels.task("speech.other") == "speech.other")
        precondition(AzureSpeechLabels.task("speech.interpreter") == "Перекладач" && AzureSpeechLabels.task("speech.voice_fallback") == "Резервна голосова лінія")
        // Unavailable payload from an older/failing backend must not decode into a card.
        precondition((try? JSONDecoder().decode(AzureSpeechStats.self, from: Data(#"{"status":"unavailable","error":"x"}"#.utf8))) == nil)
        print("Azure speech stats tests: PASS")
    }
}
