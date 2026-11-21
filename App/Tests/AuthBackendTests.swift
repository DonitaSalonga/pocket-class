import Testing
@testable import Project2

@Test func signOutClearsSession() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    #expect(try await backend.currentUser()?.role == .teacher)
    try await backend.signOut()
    #expect(try await backend.currentUser() == nil)
}

@Test func wrongPasswordIsRefused() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    await #expect(throws: BackendError.invalidCredentials) {
        try await backend.signIn(email: "teacher@example.com", password: "wrong")
    }
    #expect(try await backend.currentUser()?.role == .teacher)
}
