import Testing
@testable import Project2

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

@Test func resetPasswordAcceptsWellFormedEmail() async throws {
    let backend = InMemoryBackend()
    try await backend.resetPassword(email: "unknown@example.com")
}

@Test func resetPasswordRejectsMalformedEmailBeforeBackendCall() {
    #expect(EmailAddress.isValid("not-an-email") == false)
}
