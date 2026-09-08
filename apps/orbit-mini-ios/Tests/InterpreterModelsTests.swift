import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
struct InterpreterModelsTests {
    static func main() {
        expect(InterpreterDirection.ukrainianToGerman.sourceLanguage == "uk-UA", "UA source mapping")
        expect(InterpreterDirection.ukrainianToGerman.targetLanguage == "de", "DE target mapping")
        expect(InterpreterDirection.germanToUkrainian.sourceLanguage == "de-DE", "DE source mapping")
        expect(InterpreterDirection.germanToUkrainian.targetLanguage == "uk", "UA target mapping")
        expect(Set(InterpreterDirection.allCases.map(\.rawValue)) == ["uk-UA-to-de-DE", "de-DE-to-uk-UA"], "direction allowlist")
        print("InterpreterModelsTests: PASS")
    }
}
