import Foundation

enum EmailAddress {
    static func isValid(_ value: String) -> Bool {
        value.range(of: #"^[A-Z0-9a-z.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"#, options: .regularExpression) != nil
    }
}

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
    func currentUserID() async throws -> UUID?
    func resetPassword(email: String) async throws
    func updateRole(_ role: UserRole) async throws
    func profile(id: UUID) async throws -> AppUser?
}

enum BackendError: Error, LocalizedError { case invalidCredentials, duplicateEmail, notConfigured, roleIsImmutable
    var errorDescription: String? { switch self { case .invalidCredentials: "Email or password is incorrect."; case .duplicateEmail: "An account with this email already exists."; case .notConfigured: "Supabase config is missing."; case .roleIsImmutable: "Account role cannot be changed." } }
}

actor InMemoryBackend: Backend {
    fileprivate struct Account { let user: AppUser; let password: String }
    final class Store: @unchecked Sendable { fileprivate var accounts: [String: Account] = [:]; fileprivate var signedIn: UUID? }
    private let store: Store
    init(store: Store = Store()) { self.store = store }

    func signUp(email: String, password: String, name: String, role: UserRole) throws {
        let key = email.lowercased()
        guard store.accounts[key] == nil else { throw BackendError.duplicateEmail }
        let user = AppUser(id: UUID(), name: name, email: key, role: role)
        store.accounts[key] = Account(user: user, password: password)
        store.signedIn = user.id
    }
    func signIn(email: String, password: String) throws {
        guard let account = store.accounts[email.lowercased()], account.password == password else { throw BackendError.invalidCredentials }
        store.signedIn = account.user.id
    }
    func signOut() { store.signedIn = nil }
    func currentUser() -> AppUser? { store.accounts.values.first { $0.user.id == store.signedIn }?.user }
    func currentUserID() -> UUID? { store.signedIn }
    func resetPassword(email: String) throws {}
    func updateRole(_ role: UserRole) throws { throw BackendError.roleIsImmutable }
    func profile(id: UUID) -> AppUser? { store.accounts.values.first { $0.user.id == id }?.user }
}
