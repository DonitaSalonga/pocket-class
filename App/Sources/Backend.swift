import Foundation

enum EmailAddress {
    static func isValid(_ value: String) -> Bool {
        value.range(of: #"^[A-Z0-9a-z.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"#, options: .regularExpression) != nil
    }
}

enum PasswordResetOutcome { case invalidEmail, requested }

/// Refuses malformed emails without touching the backend. Backend errors are swallowed so the UI never reveals whether an account exists.
func requestPasswordReset(email: String, backend: any Backend) async -> PasswordResetOutcome {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard EmailAddress.isValid(email) else { return .invalidEmail }
    try? await backend.resetPassword(email: email)
    return .requested
}

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
    func joinCourse(code: String) async throws -> Course
}

enum BackendError: Error, LocalizedError { case invalidCredentials, duplicateEmail, notConfigured, roleIsImmutable, notATeacher, notAStudent, invalidJoinCode
    var errorDescription: String? { switch self { case .invalidCredentials: "Email or password is incorrect."; case .duplicateEmail: "An account with this email already exists."; case .notConfigured: "Supabase config is missing."; case .roleIsImmutable: "Account role cannot be changed."; case .notATeacher: "Only Teachers can create courses."; case .notAStudent: "Only Students can join courses."; case .invalidJoinCode: "Join Code is incorrect or no longer valid." } }
}

actor InMemoryBackend: Backend {
    fileprivate struct Account { let user: AppUser; let password: String }
    final class Store: @unchecked Sendable { fileprivate var accounts: [String: Account] = [:]; fileprivate var signedIn: UUID?; fileprivate var courses: [Course] = []; fileprivate var memberships: Set<String> = [] }
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
        guard let user = currentUser(), user.role == .teacher else { throw BackendError.notATeacher }
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var code: String
        repeat { code = String((0..<6).map { _ in alphabet.randomElement()! }) } while store.courses.contains { $0.joinCode == code }
        let course = Course(id: UUID(), teacherID: user.id, name: name, description: description, joinCode: code, createdAt: .now)
        store.courses.append(course)
        return course
    }
    func myCourses() -> [Course] {
        guard let user = currentUser() else { return [] }
        if user.role == .teacher { return store.courses.filter { $0.teacherID == user.id } }
        return store.courses.filter { store.memberships.contains("\(user.id):\($0.id)") }
    }
    func joinCourse(code: String) throws -> Course {
        guard let user = currentUser(), user.role == .student else { throw BackendError.notAStudent }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let course = store.courses.first(where: { $0.joinCode.uppercased() == normalized }) else { throw BackendError.invalidJoinCode }
        store.memberships.insert("\(user.id):\(course.id)")
        return course
    }
}
