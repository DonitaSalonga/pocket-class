import Foundation
import Testing
@testable import Project2

private func account() -> (email: String, password: String) {
    ("test+\(UUID().uuidString.lowercased())@example.com", "Test-password-47!")
}

@Test func signupCreatesProfileRoleCannotChangeAndSessionRoundTrips() async throws {
    let backend = SupabaseBackend(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
    let credentials = account()
    try await backend.signUp(email: credentials.email, password: credentials.password, name: "Integration Teacher", role: .teacher)
    let user = try #require(await backend.currentUser())
    #expect(user.role == .teacher)
    await #expect(throws: (any Error).self) { try await backend.updateRole(.student) }
    try await backend.signOut()
    #expect(try await backend.currentUser() == nil)
    try await backend.signIn(email: credentials.email, password: credentials.password)
    #expect(try await backend.currentUser()?.role == .teacher)
}

@Test func userCannotReadAnotherUsersProfile() async throws {
    let backend = SupabaseBackend(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
    let first = account()
    try await backend.signUp(email: first.email, password: first.password, name: "First Student", role: .student)
    let otherID = try #require(await backend.currentUserID())
    try await backend.signOut()
    let second = account()
    try await backend.signUp(email: second.email, password: second.password, name: "Second Student", role: .student)
    #expect(try await backend.profile(id: otherID) == nil)
}
