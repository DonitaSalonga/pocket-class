import Foundation

enum UserRole: String, Codable, CaseIterable { case teacher, student }
struct AppUser: Equatable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let role: UserRole
}

protocol Backend: Sendable {
    func signUp(email: String, password: String, name: String, role: UserRole) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    func currentUser() async throws -> AppUser?
    func resetPassword(email: String) async throws
}

enum BackendError: Error, LocalizedError { case invalidCredentials, notConfigured
    var errorDescription: String? { switch self { case .invalidCredentials: "Email or password is incorrect."; case .notConfigured: "Supabase config is missing." } }
}

actor InMemoryBackend: Backend {
    private struct Account { let user: AppUser; let password: String }
    private var accounts: [String: Account] = [:]
    private var signedIn: UUID?

    func signUp(email: String, password: String, name: String, role: UserRole) throws {
        let key = email.lowercased()
        guard accounts[key] == nil else { throw BackendError.invalidCredentials }
        let user = AppUser(id: UUID(), name: name, email: key, role: role)
        accounts[key] = Account(user: user, password: password)
        signedIn = user.id
    }
    func signIn(email: String, password: String) throws {
        guard let account = accounts[email.lowercased()], account.password == password else { throw BackendError.invalidCredentials }
        signedIn = account.user.id
    }
    func signOut() { signedIn = nil }
    func currentUser() -> AppUser? { accounts.values.first { $0.user.id == signedIn }?.user }
    func resetPassword(email: String) throws {}
}
