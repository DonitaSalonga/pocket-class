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
enum CourseFileKind: String, Codable, Sendable { case presentation, exercise }
struct CourseFile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let courseID: UUID
    let kind: CourseFileKind
    let title: String
    let storagePath: String
    let fileType: String
    let size: Int
    let uploadedAt: Date
    enum CodingKeys: String, CodingKey { case id, title, size, kind; case courseID = "course_id"; case storagePath = "storage_path"; case fileType = "file_type"; case uploadedAt = "uploaded_at" }
}

enum CourseFileValidation {
    /// Lowercase because Postgres renders UUIDs that way and the storage policy compares the first segment as text.
    static func newStoragePath(courseID: UUID, fileName: String) -> String {
        "\(courseID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(URL(fileURLWithPath: fileName).pathExtension.lowercased())"
    }
    static func validate(kind: CourseFileKind, fileName: String, size: Int) throws {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let allowed = kind == .presentation ? ["pptx", "ppt", "key", "pdf"] : ["pdf", "docx", "pptx"]
        guard allowed.contains(ext) else { throw BackendError.unsupportedFileType }
        guard size <= 50 * 1024 * 1024 else { throw BackendError.fileTooLarge }
    }
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
    func uploadFile(courseID: UUID, kind: CourseFileKind, title: String, data: Data, fileName: String) async throws -> CourseFile
    func files(courseID: UUID) async throws -> [CourseFile]
    func allFiles() async throws -> [CourseFile]
    /// Local file URL for a Course file. Served from the on-device cache when present, so opened files work offline.
    func download(file: CourseFile) async throws -> URL
    /// Changes only the title (trimmed, never blank) and returns the updated file.
    func renameFile(id: UUID, title: String) async throws -> CourseFile
    /// Removes the stored object and the row, so the file disappears for everyone.
    func deleteFile(_ file: CourseFile) async throws
}

/// Downloaded files live in Caches (the system may purge them) as `<file id>/<title>.<ext>`, so Quick Look and the share sheet show the title.
struct FileCache: Sendable {
    let directory: URL
    static let shared = FileCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CourseFiles"))

    func url(for file: CourseFile) -> URL {
        let title = file.title.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent(file.id.uuidString).appendingPathComponent("\(title).\(file.fileType)")
    }
    func clear() { try? FileManager.default.removeItem(at: directory) }
    func remove(_ file: CourseFile) { try? FileManager.default.removeItem(at: url(for: file).deletingLastPathComponent()) }
    /// Cached copy if present, else `fetch` and keep it. A fetch failure with no copy propagates.
    func open(_ file: CourseFile, fetch: () async throws -> Data) async throws -> URL {
        let url = url(for: file)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // A rename changes the file name but not the id, so keep the copy instead of downloading it again.
        if let old = try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).first, (try? FileManager.default.moveItem(at: old, to: url)) != nil { return url }
        let data = try await fetch()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum BackendError: Error, LocalizedError { case invalidCredentials, duplicateEmail, notConfigured, roleIsImmutable, notATeacher, notAStudent, invalidJoinCode, unsupportedFileType, fileTooLarge, fileUnavailable, blankTitle, fileNotFound
    var errorDescription: String? { switch self { case .invalidCredentials: "Email or password is incorrect."; case .duplicateEmail: "An account with this email already exists."; case .notConfigured: "Supabase config is missing."; case .roleIsImmutable: "Account role cannot be changed."; case .notATeacher: "Only Teachers can create courses."; case .notAStudent: "Only Students can join courses."; case .invalidJoinCode: "Join Code is incorrect or no longer valid."; case .unsupportedFileType: "This file type is not supported for this list."; case .fileTooLarge: "Files must be 50 MB or smaller."; case .fileUnavailable: "This file is not available."; case .blankTitle: "Enter a title."; case .fileNotFound: "This file no longer exists, or you cannot change it." } }
}

extension Backend {
    func uploadFile(courseID: UUID, kind: CourseFileKind, title: String, data: Data, fileName: String) async throws -> CourseFile { throw BackendError.notConfigured }
    func files(courseID: UUID) async throws -> [CourseFile] { [] }
    func allFiles() async throws -> [CourseFile] { [] }
    func download(file: CourseFile) async throws -> URL { throw BackendError.notConfigured }
    func renameFile(id: UUID, title: String) async throws -> CourseFile { throw BackendError.notConfigured }
    func deleteFile(_ file: CourseFile) async throws { throw BackendError.notConfigured }
}

actor InMemoryBackend: Backend {
    fileprivate struct Account { let user: AppUser; let password: String }
    final class Store: @unchecked Sendable { fileprivate var accounts: [String: Account] = [:]; fileprivate var signedIn: UUID?; fileprivate var courses: [Course] = []; fileprivate var memberships: Set<String> = []; fileprivate var files: [CourseFile] = []; fileprivate var blobs: [UUID: Data] = [:]
        /// Test hooks: `offline` makes uncached downloads fail; `downloadCount` counts fetches that reached the store.
        var offline = false; private(set) var downloadCount = 0
        fileprivate func fetch(_ id: UUID) throws -> Data { if offline { throw URLError(.notConnectedToInternet) }; downloadCount += 1; return blobs[id] ?? Data() } }
    private let store: Store
    private let cache: FileCache
    init(store: Store = Store(), cache: FileCache = .shared) { self.store = store; self.cache = cache }

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
    func uploadFile(courseID: UUID, kind: CourseFileKind, title: String, data: Data, fileName: String) async throws -> CourseFile {
        try CourseFileValidation.validate(kind: kind, fileName: fileName, size: data.count)
        guard let user = currentUser(), user.role == .teacher, store.courses.contains(where: { $0.id == courseID && $0.teacherID == user.id }) else { throw BackendError.notATeacher }
        let file = CourseFile(id: UUID(), courseID: courseID, kind: kind, title: title, storagePath: CourseFileValidation.newStoragePath(courseID: courseID, fileName: fileName), fileType: URL(fileURLWithPath: fileName).pathExtension.lowercased(), size: data.count, uploadedAt: .now)
        store.files.append(file); store.blobs[file.id] = data; return file
    }
    func files(courseID: UUID) async throws -> [CourseFile] {
        // Like RLS, a Student off the Roster sees nothing rather than an error.
        if let user = currentUser(), user.role == .student { return isMember(user, courseID) ? store.files.filter { $0.courseID == courseID }.sorted { $0.uploadedAt > $1.uploadedAt } : [] }
        guard let user = currentUser(), user.role == .teacher, store.courses.contains(where: { $0.id == courseID && $0.teacherID == user.id }) else { throw BackendError.notATeacher }
        return store.files.filter { $0.courseID == courseID }.sorted { $0.uploadedAt > $1.uploadedAt }
    }
    func allFiles() async throws -> [CourseFile] {
        guard let user = currentUser(), user.role == .teacher else { return [] }
        let mine = Set(store.courses.filter { $0.teacherID == user.id }.map(\.id))
        return store.files.filter { mine.contains($0.courseID) }.sorted { $0.uploadedAt > $1.uploadedAt }
    }
    private func isMember(_ user: AppUser, _ courseID: UUID) -> Bool { store.memberships.contains("\(user.id):\(courseID)") }
    func download(file: CourseFile) async throws -> URL {
        guard let user = currentUser(), user.role == .student ? isMember(user, file.courseID) : store.courses.contains(where: { $0.id == file.courseID && $0.teacherID == user.id }) else { throw BackendError.fileUnavailable }
        return try await cache.open(file) { try store.fetch(file.id) }
    }
    func renameFile(id: UUID, title: String) async throws -> CourseFile {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw BackendError.blankTitle }
        guard let index = store.files.firstIndex(where: { $0.id == id }) else { throw BackendError.fileNotFound }
        try requireOwner(of: store.files[index])
        let old = store.files[index]
        store.files[index] = CourseFile(id: old.id, courseID: old.courseID, kind: old.kind, title: title, storagePath: old.storagePath, fileType: old.fileType, size: old.size, uploadedAt: old.uploadedAt)
        return store.files[index]
    }
    func deleteFile(_ file: CourseFile) async throws {
        guard let stored = store.files.first(where: { $0.id == file.id }) else { throw BackendError.fileNotFound }
        try requireOwner(of: stored)
        store.files.removeAll { $0.id == file.id }
        cache.remove(file)
    }
    private func requireOwner(of file: CourseFile) throws {
        guard let user = currentUser(), user.role == .teacher, store.courses.contains(where: { $0.id == file.courseID && $0.teacherID == user.id }) else { throw BackendError.notATeacher }
    }
}
