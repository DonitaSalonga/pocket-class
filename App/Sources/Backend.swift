import Foundation

enum UserRole: String, Codable, CaseIterable { case teacher, student }
struct AppUser: Equatable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let role: UserRole
}
struct Course: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let teacherID: UUID
    let name: String
    let description: String?
    let joinCode: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, name, description; case teacherID = "teacher_id"; case joinCode = "join_code"; case createdAt = "created_at" }
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
    func createCourse(name: String, description: String?) async throws -> Course
    func myCourses() async throws -> [Course]
}

enum BackendError: Error, LocalizedError { case invalidCredentials, duplicateEmail, notConfigured, roleIsImmutable
    var errorDescription: String? { switch self { case .invalidCredentials: "Email or password is incorrect."; case .duplicateEmail: "An account with this email already exists."; case .notConfigured: "Supabase config is missing."; case .roleIsImmutable: "Account role cannot be changed." } }
}

actor InMemoryBackend: Backend {
    fileprivate struct Account { let user: AppUser; let password: String }
    final class Store: @unchecked Sendable { fileprivate var accounts: [String: Account] = [:]; fileprivate var signedIn: UUID?; fileprivate var courses: [Course] = [] }
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
    func createCourse(name: String, description: String?) throws -> Course {
        guard let user = currentUser(), user.role == .teacher else { throw BackendError.invalidCredentials }
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var code: String
        repeat { code = String((0..<6).map { _ in alphabet.randomElement()! }) } while store.courses.contains { $0.joinCode == code }
        let course = Course(id: UUID(), teacherID: user.id, name: name, description: description, joinCode: code, createdAt: .now)
        store.courses.append(course)
        return course
    }
    func myCourses() -> [Course] { guard let user = currentUser(), user.role == .teacher else { return [] }; return store.courses.filter { $0.teacherID == user.id } }
}
