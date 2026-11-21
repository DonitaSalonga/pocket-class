import Testing
@testable import Project2

@Test func initialsAreUppercaseAndLimitedToTwoLetters() {
    #expect(Initials.of("Pool studentA") == "PS")
    #expect(Initials.of("ana  cruz") == "AC")
    #expect(Initials.of("Maria de la Cruz") == "MD")
    #expect(Initials.of("rivera") == "R")
    #expect(Initials.of("  ") == "")
}
