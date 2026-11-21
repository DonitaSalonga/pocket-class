import Foundation
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
