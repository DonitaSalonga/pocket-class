import Foundation
import Supabase
import Testing
@testable import Project2

/// Stands in for the Keychain, which is unavailable in the unsigned test host; sharing one instance simulates a relaunch.
private final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

private func backend(_ storage: MemoryStorage = MemoryStorage()) -> SupabaseBackend {
    SupabaseBackend(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey, storage: storage)
}

private func account() -> (email: String, password: String) {
    ("test+\(UUID().uuidString.lowercased())@example.com", "Test-password-47!")
}

@Test func signupCreatesProfileWithChosenRole() async throws {
    let backend = backend()
    let credentials = account()
    try await backend.signUp(email: credentials.email, password: credentials.password, name: "Integration Teacher", role: .teacher)
    let user = try #require(await backend.currentUser())
    #expect(user.role == .teacher)
    #expect(user.name == "Integration Teacher")
    #expect(user.email == credentials.email)
}

@Test func userCannotChangeOwnRole() async throws {
    let backend = backend()
    let credentials = account()
    try await backend.signUp(email: credentials.email, password: credentials.password, name: "Role Student", role: .student)
    await #expect(throws: (any Error).self) { try await backend.updateRole(.teacher) }
    #expect(try await backend.currentUser()?.role == .student)
}

@Test func userCannotReadAnotherUsersProfile() async throws {
    let backend = backend()
    let first = account()
    try await backend.signUp(email: first.email, password: first.password, name: "First Student", role: .student)
    let firstID = try #require(await backend.currentUserID())
    try await backend.signOut()
    let second = account()
    try await backend.signUp(email: second.email, password: second.password, name: "Second Student", role: .student)
    let secondID = try #require(await backend.currentUserID())
    // Own profile is readable, so a nil for the other proves RLS, not a missing session.
    #expect(try await backend.profile(id: secondID)?.name == "Second Student")
    #expect(try await backend.profile(id: firstID) == nil)
}

@Test func signInAndSignOutRoundTrip() async throws {
    let backend = backend()
    let credentials = account()
    try await backend.signUp(email: credentials.email, password: credentials.password, name: "Round Trip", role: .teacher)
    try await backend.signOut()
    #expect(try await backend.currentUser() == nil)
    await #expect(throws: (any Error).self) { try await backend.signIn(email: credentials.email, password: "wrong-password") }
    try await backend.signIn(email: credentials.email, password: credentials.password)
    #expect(try await backend.currentUser()?.name == "Round Trip")
}

@Test func sessionRestoresOnRelaunch() async throws {
    let storage = MemoryStorage()
    let credentials = account()
    let firstLaunch = backend(storage)
    try await firstLaunch.signUp(email: credentials.email, password: credentials.password, name: "Relaunch", role: .student)
    let before = try #require(await firstLaunch.currentUser())
    let nextLaunch = backend(storage)
    #expect(try await nextLaunch.currentUser() == before)
}
