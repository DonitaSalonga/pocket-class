import Foundation
import Testing
@testable import Project2

@Test func teacherCreatesAndListsOwnCoursesWithReadableUniqueCodes() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let first = try await backend.createCourse(name: "Biology", description: nil)
    let second = try await backend.createCourse(name: "Chemistry", description: "Lab")
    #expect(try await backend.myCourses().count == 2)
    #expect(first.joinCode.count == 6 && first.joinCode.allSatisfy { "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".contains($0) })
    #expect(first.joinCode != second.joinCode)
}

@Test func studentCannotCreateCourseAndCannotListCourses() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "student@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    await #expect(throws: BackendError.notATeacher) { try await backend.createCourse(name: "Biology", description: nil) }
    #expect(try await backend.myCourses().isEmpty)
}

@Test func teachersCannotSeeEachOthersCourses() async throws {
    let store = InMemoryBackend.Store()
    let a = InMemoryBackend(store: store)
    try await a.signUp(email: "a@example.com", password: "correct horse", name: "Teacher A", role: .teacher)
    _ = try await a.createCourse(name: "Biology", description: nil)
    try await a.signOut()
    let b = InMemoryBackend(store: store)
    try await b.signUp(email: "b@example.com", password: "correct horse", name: "Teacher B", role: .teacher)
    #expect(try await b.myCourses().isEmpty)
}

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

private actor FailingBackend: Backend {
    func signUp(email: String, password: String, name: String, role: UserRole) throws {}
    func signIn(email: String, password: String) throws {}
    func signOut() throws {}
    func currentUser() throws -> AppUser? { nil }
    func currentUserID() throws -> UUID? { nil }
    func resetPassword(email: String) throws {}
    func updateRole(_ role: UserRole) throws {}
    func profile(id: UUID) throws -> AppUser? { nil }
    func createCourse(name: String, description: String?) throws -> Course { throw URLError(.notConnectedToInternet) }
    func myCourses() throws -> [Course] { [] }
    func joinCourse(code: String) throws -> Course { throw URLError(.notConnectedToInternet) }
    func roster(courseID: UUID) throws -> [RosterStudent] { [] }
    func removeStudent(courseID: UUID, studentID: UUID) throws {}
    func leaveCourse(courseID: UUID) throws {}
}

@MainActor @Test func newCourseWithBlankNameShowsErrorAndCreatesNothing() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let form = NewCourseForm()
    form.name = "   "
    #expect(await form.submit(using: backend) == nil)
    #expect(form.error == "Enter a course name.")
    #expect(try await backend.myCourses().isEmpty)
}

@MainActor @Test func newCourseTrimsNameAndClearsError() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "correct horse", name: "Jordan Lee", role: .teacher)
    let form = NewCourseForm()
    form.error = "old"
    form.name = "  Biology "
    #expect(await form.submit(using: backend)?.name == "Biology")
    #expect(form.error == nil)
}

@MainActor @Test func newCourseShowsBackendRefusalForStudent() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "student@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    let form = NewCourseForm()
    form.name = "Biology"
    #expect(await form.submit(using: backend) == nil)
    #expect(form.error == "Only Teachers can create courses.")
}

@MainActor @Test func newCourseShowsGenericErrorForUnexpectedFailure() async throws {
    let form = NewCourseForm()
    form.name = "Biology"
    #expect(await form.submit(using: FailingBackend()) == nil)
    #expect(form.error == "Could not create the course. Check your connection and try again.")
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
    func createCourse(name: String, description: String?) async throws -> Course { throw BackendError.notATeacher }
    func myCourses() async throws -> [Course] { [] }
    func joinCourse(code: String) async throws -> Course { throw BackendError.invalidJoinCode }
    func roster(courseID: UUID) async throws -> [RosterStudent] { [] }
    func removeStudent(courseID: UUID, studentID: UUID) async throws {}
    func leaveCourse(courseID: UUID) async throws {}
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

/// One Teacher with a Course and a Student on the same store; both backends share it like two devices share a server.
private func teacherCourseAndStudent() async throws -> (course: Course, student: InMemoryBackend, otherStudent: InMemoryBackend, teacher: InMemoryBackend) {
    let store = InMemoryBackend.Store()
    let teacher = InMemoryBackend(store: store)
    try await teacher.signUp(email: "t@example.com", password: "correct horse", name: "Teacher", role: .teacher)
    let course = try await teacher.createCourse(name: "Biology", description: nil)
    let student = InMemoryBackend(store: store)
    try await student.signUp(email: "s@example.com", password: "correct horse", name: "Mia Chen", role: .student)
    let otherStudent = InMemoryBackend(store: store)
    try await otherStudent.signUp(email: "o@example.com", password: "correct horse", name: "Outsider", role: .student)
    try await teacher.signIn(email: "t@example.com", password: "correct horse")
    return (course, student, otherStudent, teacher)
}

@Test func studentJoinsWithCodeIgnoringCaseAndSpacesAndSeesCourse() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    let joined = try await setup.student.joinCourse(code: "  \(setup.course.joinCode.lowercased()) \n")
    #expect(joined == setup.course)
    #expect(try await setup.student.myCourses() == [setup.course])
}

@Test func wrongJoinCodeIsRefusedWithTypedError() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    await #expect(throws: BackendError.invalidJoinCode) { try await setup.student.joinCourse(code: "ZZZZZZ") }
    #expect(try await setup.student.myCourses().isEmpty)
}

@Test func joiningTwiceIsANoOp() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    _ = try await setup.student.joinCourse(code: setup.course.joinCode)
    let again = try await setup.student.joinCourse(code: setup.course.joinCode)
    #expect(again == setup.course)
    #expect(try await setup.student.myCourses().count == 1)
}

@Test func teacherCanViewRosterRemoveStudentAndStudentCanLeave() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    _ = try await setup.student.joinCourse(code: setup.course.joinCode)
    let studentID = try #require(await setup.student.currentUserID())
    try await setup.teacher.signIn(email: "t@example.com", password: "correct horse")
    let roster = try await setup.teacher.roster(courseID: setup.course.id)
    #expect(roster.map(\.name) == ["Mia Chen"])
    #expect(roster.first?.joinedAt != .distantPast)
    try await setup.teacher.removeStudent(courseID: setup.course.id, studentID: studentID)
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    #expect(try await setup.student.myCourses().isEmpty)
    _ = try await setup.student.joinCourse(code: setup.course.joinCode)
    try await setup.student.leaveCourse(courseID: setup.course.id)
    #expect(try await setup.student.myCourses().isEmpty)
}

@Test func teacherCannotJoinACourse() async throws {
    let setup = try await teacherCourseAndStudent()
    await #expect(throws: BackendError.notAStudent) { try await setup.teacher.joinCourse(code: setup.course.joinCode) }
}

@Test func studentWhoDidNotJoinDoesNotSeeCourse() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    _ = try await setup.student.joinCourse(code: setup.course.joinCode)
    try await setup.otherStudent.signIn(email: "o@example.com", password: "correct horse")
    #expect(try await setup.otherStudent.myCourses().isEmpty)
}

@MainActor @Test func joinFormUppercasesAndTrimsCodeAndShowsWrongCodeError() async throws {
    let setup = try await teacherCourseAndStudent()
    try await setup.student.signIn(email: "s@example.com", password: "correct horse")
    let form = JoinCourseForm()
    form.code = "zzzzzz"
    #expect(form.code == "ZZZZZZ")
    #expect(await form.submit(using: setup.student) == nil)
    #expect(form.error == "Join Code is incorrect or no longer valid.")
    form.code = "  \(setup.course.joinCode.lowercased()) "
    #expect(await form.submit(using: setup.student) == setup.course)
    #expect(form.error == nil)
}

@MainActor @Test func joinFormAsksForCodeWhenBlankAndShowsGenericErrorOnFailure() async throws {
    let form = JoinCourseForm()
    form.code = "   "
    #expect(await form.submit(using: FailingBackend()) == nil)
    #expect(form.error == "Enter a Join Code.")
    form.code = "ABC234"
    #expect(await form.submit(using: FailingBackend()) == nil)
    #expect(form.error == "Could not join the course. Check your connection and try again.")
}
