import Foundation
import Testing
@testable import Project2

@Test func teacherCreatesAndListsOwnCoursesWithReadableUniqueCodes() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let first = try await backend.createCourse(name: "Biology", description: nil)
    let second = try await backend.createCourse(name: "Chemistry", description: "Lab")
    #expect(await backend.myCourses().count == 2)
    #expect(first.joinCode.count == 6 && first.joinCode.allSatisfy { "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".contains($0) })
    #expect(first.joinCode != second.joinCode)
}

@Test func studentCannotCreateCourseAndCannotListCourses() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "student@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    await #expect(throws: BackendError.notATeacher) { try await backend.createCourse(name: "Biology", description: nil) }
    #expect(await backend.myCourses().isEmpty)
}

@Test func teachersCannotSeeEachOthersCourses() async throws {
    let store = InMemoryBackend.Store()
    let a = InMemoryBackend(store: store)
    try await a.signUp(email: "a@example.com", password: "correct horse", name: "Teacher A", role: .teacher)
    _ = try await a.createCourse(name: "Biology", description: nil)
    try await a.signOut()
    let b = InMemoryBackend(store: store)
    try await b.signUp(email: "b@example.com", password: "correct horse", name: "Teacher B", role: .teacher)
    #expect(await b.myCourses().isEmpty)
}

@Test func signOutClearsSession() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    #expect(try await backend.currentUser()?.role == .teacher)
    await #expect(throws: BackendError.roleIsImmutable) { try await backend.updateRole(.student) }
    try await backend.signOut()
    #expect(try await backend.currentUser() == nil)
}

@Test func signupKeepsRoleAndDuplicateEmailIsRefused() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    #expect(try await backend.currentUser()?.role == .teacher)
    await #expect(throws: BackendError.duplicateEmail) {
        try await backend.signUp(email: "teacher@example.com", password: "another password", name: "Changed", role: .student)
    }
}

@Test func sessionRestoresAfterBackendRecreation() async throws {
    let store = InMemoryBackend.Store()
    let firstLaunch = InMemoryBackend(store: store)
    try await firstLaunch.signUp(email: "student@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    let nextLaunch = InMemoryBackend(store: store)
    #expect(try await nextLaunch.currentUser()?.role == .student)
}

@Test func wrongPasswordIsRefused() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    await #expect(throws: BackendError.invalidCredentials) {
        try await backend.signIn(email: "teacher@example.com", password: "wrong")
    }
    #expect(try await backend.currentUser()?.role == .teacher)
}

@Test func signInAfterSignOutRestoresUser() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    try await backend.signOut()
    try await backend.signIn(email: "teacher@example.com", password: "correct horse")
    #expect(try await backend.currentUser()?.name == "Jordan Lee")
}

private actor FailingBackend: Backend {
    func signUp(email: String, password: String, name: String, role: UserRole) throws {}
    func signIn(email: String, password: String) throws {}
    func signOut() throws {}
    func currentUser() throws -> AppUser? { nil }
    func currentUserID() throws -> UUID? { nil }
    func resetPassword(email: String) throws {}
    func updateRole(_ role: UserRole) throws {}
    func profile(id: UUID) throws -> AppUser? { nil }
    func createCourse(name: String, description: String?) throws -> Course { throw URLError(.notConnectedToInternet) }
    func myCourses() throws -> [Course] { [] }
}

@MainActor @Test func newCourseWithBlankNameShowsErrorAndCreatesNothing() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let form = NewCourseForm()
    form.name = "   "
    #expect(await form.submit(using: backend) == nil)
    #expect(form.error == "Enter a course name.")
    #expect(await backend.myCourses().isEmpty)
}

@MainActor @Test func newCourseTrimsNameAndClearsError() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let form = NewCourseForm()
    form.error = "old"
    form.name = "  Biology "
    #expect(await form.submit(using: backend)?.name == "Biology")
    #expect(form.error == nil)
}

@MainActor @Test func newCourseShowsBackendRefusalForStudent() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "student@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    let form = NewCourseForm()
    form.name = "Biology"
    #expect(await form.submit(using: backend) == nil)
    #expect(form.error == "Only Teachers can create courses.")
}

@MainActor @Test func newCourseShowsGenericErrorForUnexpectedFailure() async throws {
    let form = NewCourseForm()
    form.name = "Biology"
    #expect(await form.submit(using: FailingBackend()) == nil)
    #expect(form.error == "Could not create the course. Check your connection and try again.")
}

@Test func resetPasswordAcceptsWellFormedEmail() async throws {
    let backend = InMemoryBackend()
    try await backend.resetPassword(email: "unknown@example.com")
}


private actor SpyBackend: Backend {
    var resetCalls: [String] = []
    let resetError: Error?
    init(resetError: Error? = nil) { self.resetError = resetError }
    func signUp(email: String, password: String, name: String, role: UserRole) async throws {}
    func signIn(email: String, password: String) async throws {}
    func signOut() async throws {}
    func currentUser() async throws -> AppUser? { nil }
    func currentUserID() async throws -> UUID? { nil }
    func resetPassword(email: String) async throws {
        resetCalls.append(email)
        if let resetError { throw resetError }
    }
    func updateRole(_ role: UserRole) async throws {}
    func profile(id: UUID) async throws -> AppUser? { nil }
    func createCourse(name: String, description: String?) async throws -> Course { throw BackendError.notATeacher }
    func myCourses() async throws -> [Course] { [] }
}

@Test func malformedEmailIsRefusedWithoutCallingBackend() async {
    let backend = SpyBackend()
    for email in ["", "   ", "not-an-email", "a@b", "a b@example.com"] {
        #expect(await requestPasswordReset(email: email, backend: backend) == .invalidEmail)
    }
    #expect(await backend.resetCalls.isEmpty)
}

@Test func wellFormedEmailIsRequestedAndTrimmed() async {
    let backend = SpyBackend()
    #expect(await requestPasswordReset(email: " teacher@example.com ", backend: backend) == .requested)
    #expect(await backend.resetCalls == ["teacher@example.com"])
}

@Test func backendFailureStillGivesNeutralOutcome() async {
    let backend = SpyBackend(resetError: BackendError.invalidCredentials)
    #expect(await requestPasswordReset(email: "ghost@example.com", backend: backend) == .requested)
}
