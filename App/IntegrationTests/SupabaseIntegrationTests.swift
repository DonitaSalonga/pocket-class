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

private let joinCodeAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

/// Talks to the courses table directly so RLS is tested without the app's own role guards.
private func rawClient(email: String? = nil, password: String? = nil) async throws -> SupabaseClient {
    let client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey, options: .init(auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true)))
    if let email, let password { try await client.auth.signIn(email: email, password: password) }
    return client
}

private func signedUp(_ role: UserRole, name: String) async throws -> (backend: SupabaseBackend, email: String, password: String) {
    let client = backend()
    let credentials = account()
    try await client.signUp(email: credentials.email, password: credentials.password, name: name, role: role)
    return (client, credentials.email, credentials.password)
}

@Test func teacherCreatesListsCoursesAndGetsUniqueReadableCodes() async throws {
    let client = backend()
    let credentials = account()
    try await client.signUp(email: credentials.email, password: credentials.password, name: "Course Teacher", role: .teacher)
    let first = try await client.createCourse(name: "Biology", description: nil)
    let second = try await client.createCourse(name: "Chemistry", description: "Lab")
    let courses = try await client.myCourses()
    #expect(courses.contains(first) && courses.contains(second))
    #expect(first.joinCode.count == 6 && first.joinCode.allSatisfy { joinCodeAlphabet.contains($0) })
    #expect(second.joinCode.count == 6 && second.joinCode.allSatisfy { joinCodeAlphabet.contains($0) })
    #expect(first.joinCode != second.joinCode)
}

@Test func studentCannotCreateCourse() async throws {
    let student = try await signedUp(.student, name: "Course Student")
    await #expect(throws: (any Error).self) { try await student.backend.createCourse(name: "Biology", description: nil) }
    let raw = try await rawClient(email: student.email, password: student.password)
    let rows: [Course] = try await raw.from("courses").select().execute().value
    #expect(rows.isEmpty)
}

@Test func teachersCannotReadEachOthersCourses() async throws {
    let a = try await signedUp(.teacher, name: "Teacher A")
    let course = try await a.backend.createCourse(name: "Private Biology", description: nil)
    let b = try await signedUp(.teacher, name: "Teacher B")
    #expect(try await b.backend.myCourses().isEmpty)
    let raw = try await rawClient(email: b.email, password: b.password)
    let byID: [Course] = try await raw.from("courses").select().eq("id", value: course.id.uuidString).execute().value
    let byCode: [Course] = try await raw.from("courses").select().eq("join_code", value: course.joinCode).execute().value
    #expect(byID.isEmpty && byCode.isEmpty)
    #expect(try await a.backend.myCourses() == [course])
}

@Test func studentsAndSignedOutUsersCannotReadCourses() async throws {
    let teacher = try await signedUp(.teacher, name: "Readable Teacher")
    _ = try await teacher.backend.createCourse(name: "Biology", description: nil)
    let student = try await signedUp(.student, name: "Nosy Student")
    let studentRaw = try await rawClient(email: student.email, password: student.password)
    let seenByStudent: [Course] = try await studentRaw.from("courses").select().execute().value
    #expect(seenByStudent.isEmpty)
    let anon = try await rawClient()
    let seenByAnon: [Course] = (try? await anon.from("courses").select().execute().value) ?? []
    #expect(seenByAnon.isEmpty)
}

@Test func clientCannotForceOwnerOrJoinCode() async throws {
    struct Forged: Encodable { let name: String; let teacher_id: UUID; let join_code: String }
    let a = try await signedUp(.teacher, name: "Teacher A")
    let b = try await signedUp(.teacher, name: "Teacher B")
    let aID = try #require(await a.backend.currentUserID())
    let bID = try #require(await b.backend.currentUserID())
    let raw = try await rawClient(email: b.email, password: b.password)
    // Either the insert is refused or the server overrides both fields; never may the forged values stick.
    let forged: Course? = try? await raw.from("courses").insert(Forged(name: "Forged", teacher_id: aID, join_code: "AAAAAA")).select().single().execute().value
    if let forged { #expect(forged.teacherID == bID && forged.joinCode != "AAAAAA") }
    #expect(try await a.backend.myCourses().isEmpty)
    // Join Code is immutable and other Teachers' rows cannot be updated.
    let own = try await b.backend.createCourse(name: "Own", description: nil)
    _ = try? await raw.from("courses").update(["join_code": "BBBBBB"]).eq("id", value: own.id.uuidString).execute()
    #expect(try await b.backend.myCourses().first { $0.id == own.id }?.joinCode == own.joinCode)
    let theirs = try await a.backend.createCourse(name: "Theirs", description: nil)
    _ = try? await raw.from("courses").update(["name": "Hijacked"]).eq("id", value: theirs.id.uuidString).execute()
    #expect(try await a.backend.myCourses() == [theirs])
}
