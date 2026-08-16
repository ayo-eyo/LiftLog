import Testing
@testable import LiftLog

@Suite("RussianPlural.form")
struct RussianPluralTests {
    @Test(
        "выбирает верную форму множественного числа",
        arguments: [
            (1, "подход"), (2, "подхода"), (3, "подхода"), (4, "подхода"),
            (5, "подходов"), (0, "подходов"), (11, "подходов"), (12, "подходов"),
            (14, "подходов"), (21, "подход"), (22, "подхода"), (25, "подходов"),
            (101, "подход"), (111, "подходов"),
        ]
    )
    func picksCorrectForm(count: Int, expected: String) {
        #expect(RussianPlural.form(count, "подход", "подхода", "подходов") == expected)
    }
}
