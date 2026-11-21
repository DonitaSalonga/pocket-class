import Foundation
import Supabase
import Testing
@testable import Project2

/// Stands in for the Keychain, which is unavailable in the unsigned test host; sharing one instance simulates a relaunch.
final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

func backend(_ storage: MemoryStorage = MemoryStorage()) -> SupabaseBackend {
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

/// Shared signed-in session of a pool account. Never call `signOut` on it: that revokes every session of the user.
private func signedIn(_ account: PoolAccount) async throws -> PoolSession { try await TestAccounts.shared.session(account) }

@Test func userCannotChangeOwnRole() async throws {
    let student = try await signedIn(.studentA)
    await #expect(throws: (any Error).self) { try await student.backend.updateRole(.teacher) }
    #expect(try await student.backend.currentUser()?.role == .student)
}

@Test func userCannotReadAnotherUsersProfile() async throws {
    let first = try await signedIn(.studentA)
    let second = try await signedIn(.studentB)
    let firstID = try #require(await first.backend.currentUserID())
    let secondID = try #require(await second.backend.currentUserID())
    // Own profile is readable, so a nil for the other proves RLS, not a missing session.
    #expect(try await second.backend.profile(id: secondID)?.role == .student)
    #expect(try await second.backend.profile(id: firstID) == nil)
}

@Test func signInAndSignOutRoundTrip() async throws {
    let credentials = try await TestAccounts.shared.credentials(.outsider)
    let backend = backend()
    try await backend.signIn(email: credentials.email, password: credentials.password)
    try await backend.signOut()
    #expect(try await backend.currentUser() == nil)
    await #expect(throws: (any Error).self) { try await backend.signIn(email: credentials.email, password: "wrong-password") }
    try await backend.signIn(email: credentials.email, password: credentials.password)
    #expect(try await backend.currentUser()?.name == PoolAccount.outsider.name)
}

@Test func sessionRestoresOnRelaunch() async throws {
    let storage = MemoryStorage()
    let credentials = try await TestAccounts.shared.credentials(.studentB)
    let firstLaunch = backend(storage)
    try await firstLaunch.signIn(email: credentials.email, password: credentials.password)
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

/// Pool teachers keep their Courses between runs (no delete policy), so every Course gets a unique name.
private func unique(_ name: String) -> String { "\(name) \(UUID().uuidString.prefix(8))" }

@Test func teacherCreatesListsCoursesAndGetsUniqueReadableCodes() async throws {
    let teacher = try await signedIn(.teacherA)
    let first = try await teacher.backend.createCourse(name: unique("Biology"), description: nil)
    let second = try await teacher.backend.createCourse(name: unique("Chemistry"), description: "Lab")
    let courses = try await teacher.backend.myCourses()
    #expect(courses.contains(first) && courses.contains(second))
    #expect(first.joinCode.count == 6 && first.joinCode.allSatisfy { joinCodeAlphabet.contains($0) })
    #expect(second.joinCode.count == 6 && second.joinCode.allSatisfy { joinCodeAlphabet.contains($0) })
    #expect(first.joinCode != second.joinCode)
}

@Test func studentCannotCreateCourse() async throws {
    let student = try await signedIn(.studentA)
    await #expect(throws: (any Error).self) { try await student.backend.createCourse(name: "Biology", description: nil) }
    let raw = student.raw
    let rows: [Course] = try await raw.from("courses").select().execute().value
    #expect(rows.isEmpty)
}

@Test func teachersCannotReadEachOthersCourses() async throws {
    let a = try await signedIn(.teacherA)
    let course = try await a.backend.createCourse(name: unique("Private Biology"), description: nil)
    let b = try await signedIn(.teacherB)
    #expect(try await b.backend.myCourses().contains { $0.id == course.id } == false)
    let raw = b.raw
    let byID: [Course] = try await raw.from("courses").select().eq("id", value: course.id.uuidString).execute().value
    let byCode: [Course] = try await raw.from("courses").select().eq("join_code", value: course.joinCode).execute().value
    #expect(byID.isEmpty && byCode.isEmpty)
    #expect(try await a.backend.myCourses().contains(course))
}

@Test func studentsAndSignedOutUsersCannotReadCourses() async throws {
    let teacher = try await signedIn(.teacherA)
    _ = try await teacher.backend.createCourse(name: unique("Biology"), description: nil)
    let student = try await signedIn(.studentB)
    let studentRaw = student.raw
    let seenByStudent: [Course] = try await studentRaw.from("courses").select().execute().value
    #expect(seenByStudent.isEmpty)
    let anon = try await rawClient()
    let seenByAnon: [Course] = (try? await anon.from("courses").select().execute().value) ?? []
    #expect(seenByAnon.isEmpty)
}

@Test func clientCannotForceOwnerOrJoinCode() async throws {
    struct Forged: Encodable { let name: String; let teacher_id: UUID; let join_code: String }
    let a = try await signedIn(.teacherA)
    let b = try await signedIn(.teacherB)
    let aID = try #require(await a.backend.currentUserID())
    let bID = try #require(await b.backend.currentUserID())
    let raw = b.raw
    // Either the insert is refused or the server overrides both fields; never may the forged values stick.
    let forgedName = unique("Forged")
    let forged: Course? = try? await raw.from("courses").insert(Forged(name: forgedName, teacher_id: aID, join_code: "AAAAAA")).select().single().execute().value
    if let forged { #expect(forged.teacherID == bID && forged.joinCode != "AAAAAA") }
    #expect(try await a.backend.myCourses().contains { $0.name == forgedName } == false)
    // Join Code is immutable and other Teachers' rows cannot be updated.
    let own = try await b.backend.createCourse(name: unique("Own"), description: nil)
    _ = try? await raw.from("courses").update(["join_code": "BBBBBB"]).eq("id", value: own.id.uuidString).execute()
    #expect(try await b.backend.myCourses().first { $0.id == own.id }?.joinCode == own.joinCode)
    let theirs = try await a.backend.createCourse(name: unique("Theirs"), description: nil)
    _ = try? await raw.from("courses").update(["name": "Hijacked"]).eq("id", value: theirs.id.uuidString).execute()
    #expect(try await a.backend.myCourses().contains(theirs))
}

@Test func resetPasswordAcceptsUnknownWellFormedEmail() async throws {
    try await backend().resetPassword(email: "reset+\(UUID().uuidString.lowercased())@example.com")
}

@Test func studentJoinsCourseWithCodeAndSeesIt() async throws {
    let teacher = try await signedIn(.teacherA)
    let course = try await teacher.backend.createCourse(name: unique("Join Biology"), description: nil)
    let student = try await signedIn(.studentA)
    let joined = try await student.backend.joinCourse(code: " \(course.joinCode.lowercased()) ")
    #expect(joined == course)
    #expect(try await student.backend.myCourses().contains(course))
    // Joining twice is a no-op, not an error and not a second Roster row.
    #expect(try await student.backend.joinCourse(code: course.joinCode) == course)
    #expect(try await student.backend.myCourses().filter { $0.id == course.id }.count == 1)
    // The Teacher still lists own Courses: the courses and Roster policies must not recurse.
    #expect(try await teacher.backend.myCourses().contains(course))
}

@Test func wrongJoinCodeIsRefusedWithTypedError() async throws {
    let student = try await signedIn(.studentA)
    await #expect(throws: BackendError.invalidJoinCode) { try await student.backend.joinCourse(code: "ZZZZZZ") }
}

@Test func outsiderCannotReadCourseTheyDidNotJoin() async throws {
    let teacher = try await signedIn(.teacherA)
    let course = try await teacher.backend.createCourse(name: unique("Outsider Biology"), description: nil)
    let student = try await signedIn(.studentA)
    _ = try await student.backend.joinCourse(code: course.joinCode)
    let outsider = try await signedIn(.outsider)
    let rows: [Course] = try await outsider.raw.from("courses").select().eq("id", value: course.id.uuidString).execute().value
    #expect(rows.isEmpty)
    #expect(try await outsider.backend.myCourses().contains { $0.id == course.id } == false)
    let roster: [Membership] = try await outsider.raw.from("course_memberships").select().execute().value
    #expect(roster.contains { $0.courseID == course.id } == false)
}

@Test func teacherCannotJoinACourse() async throws {
    let teacher = try await signedIn(.teacherA)
    let course = try await teacher.backend.createCourse(name: unique("Teacher Join"), description: nil)
    await #expect(throws: BackendError.notAStudent) { try await teacher.backend.joinCourse(code: course.joinCode) }
    let other = try await signedIn(.teacherB)
    await #expect(throws: BackendError.notAStudent) { try await other.backend.joinCourse(code: course.joinCode) }
}

@Test func onlyTheCoursesTeacherSeesItsRoster() async throws {
    let teacher = try await signedIn(.teacherA)
    let course = try await teacher.backend.createCourse(name: unique("Roster Biology"), description: nil)
    let student = try await signedIn(.studentA)
    _ = try await student.backend.joinCourse(code: course.joinCode)
    let seenByTeacher: [Membership] = try await teacher.raw.from("course_memberships").select().eq("course_id", value: course.id.uuidString).execute().value
    #expect(seenByTeacher.count == 1)
    let otherTeacher = try await signedIn(.teacherB)
    let seenByOther: [Membership] = try await otherTeacher.raw.from("course_memberships").select().eq("course_id", value: course.id.uuidString).execute().value
    #expect(seenByOther.isEmpty)
}

private struct Membership: Decodable {
    let courseID: UUID
    enum CodingKeys: String, CodingKey { case courseID = "course_id" }
}
