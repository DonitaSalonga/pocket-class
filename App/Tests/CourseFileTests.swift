import Testing
import Foundation
@testable import Project2

@Test func teacherUploadsAndListsCourseFilesNewestFirst() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "secret", name: "Teacher", role: .teacher)
    let course = try await backend.createCourse(name: "Science", description: nil)
    let first = try await backend.uploadFile(courseID: course.id, kind: .presentation, title: "First", data: Data([1]), fileName: "first.pdf")
    let second = try await backend.uploadFile(courseID: course.id, kind: .exercise, title: "Second", data: Data([2]), fileName: "second.docx")
    #expect(try await backend.files(courseID: course.id).map(\.id) == [second.id, first.id])
}

@Test func invalidCourseFilesAreRefusedBeforeStoreChanges() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "secret", name: "Teacher", role: .teacher)
    let course = try await backend.createCourse(name: "Science", description: nil)
    await #expect(throws: BackendError.unsupportedFileType) { try await backend.uploadFile(courseID: course.id, kind: .presentation, title: "Bad", data: Data([1]), fileName: "bad.docx") }
    await #expect(throws: BackendError.fileTooLarge) { try await backend.uploadFile(courseID: course.id, kind: .exercise, title: "Big", data: Data(count: 50 * 1024 * 1024 + 1), fileName: "big.pdf") }
    #expect(try await backend.files(courseID: course.id).isEmpty)
}

@Test func anotherTeacherCannotReadOrWriteCourseFiles() async throws {
    let store = InMemoryBackend.Store()
    let first = InMemoryBackend(store: store)
    try await first.signUp(email: "one@example.com", password: "secret", name: "One", role: .teacher)
    let course = try await first.createCourse(name: "Science", description: nil)
    let second = InMemoryBackend(store: store)
    try await second.signUp(email: "two@example.com", password: "secret", name: "Two", role: .teacher)
    await #expect(throws: BackendError.notATeacher) { try await second.uploadFile(courseID: course.id, kind: .presentation, title: "Private", data: Data([1]), fileName: "x.pdf") }
    await #expect(throws: BackendError.notATeacher) { try await second.files(courseID: course.id) }
}

@Test func eachListAcceptsOnlyItsOwnTypesAndExactly50MB() throws {
    try CourseFileValidation.validate(kind: .presentation, fileName: "Deck.KEY", size: 50 * 1024 * 1024)
    for name in ["a.pptx", "a.ppt", "a.pdf"] { try CourseFileValidation.validate(kind: .presentation, fileName: name, size: 1) }
    for name in ["a.pdf", "a.docx", "a.pptx"] { try CourseFileValidation.validate(kind: .exercise, fileName: name, size: 1) }
    #expect(throws: BackendError.unsupportedFileType) { try CourseFileValidation.validate(kind: .exercise, fileName: "a.key", size: 1) }
    #expect(throws: BackendError.unsupportedFileType) { try CourseFileValidation.validate(kind: .presentation, fileName: "a.docx", size: 1) }
    #expect(throws: BackendError.unsupportedFileType) { try CourseFileValidation.validate(kind: .exercise, fileName: "noextension", size: 1) }
}

/// Counts uploads so a test can prove a refused file never reached the backend.
private actor UploadSpy: Backend {
    private(set) var uploads = 0
    func signUp(email: String, password: String, name: String, role: UserRole) async throws {}
    func signIn(email: String, password: String) async throws {}
    func signOut() async throws {}
    func currentUser() async throws -> AppUser? { nil }
    func currentUserID() async throws -> UUID? { nil }
    func resetPassword(email: String) async throws {}
    func updateRole(_ role: UserRole) async throws {}
    func profile(id: UUID) async throws -> AppUser? { nil }
    func createCourse(name: String, description: String?) async throws -> Course { throw BackendError.notConfigured }
    func myCourses() async throws -> [Course] { [] }
    func uploadFile(courseID: UUID, kind: CourseFileKind, title: String, data: Data, fileName: String) async throws -> CourseFile {
        uploads += 1
        return CourseFile(id: UUID(), courseID: courseID, kind: kind, title: title, storagePath: "p", fileType: "pdf", size: data.count, uploadedAt: .now)
    }
}

@MainActor @Test func oversizeFileIsRefusedBeforeReadingOrUploading() async {
    let spy = UploadSpy()
    let form = UploadFileForm(kind: .exercise, title: "Big")
    var loaded = false
    let file = await form.submit(courseID: UUID(), fileName: "big.pdf", size: 50 * 1024 * 1024 + 1, load: { loaded = true; return Data() }, using: spy)
    #expect(file == nil)
    #expect(form.error == "Files must be 50 MB or smaller.")
    #expect(!loaded)
    #expect(await spy.uploads == 0)
}

@MainActor @Test func wrongTypeAndBlankTitleAreRefusedBeforeUploading() async {
    let spy = UploadSpy()
    let wrongType = UploadFileForm(kind: .presentation, title: "Notes")
    #expect(await wrongType.submit(courseID: UUID(), fileName: "notes.docx", size: 10, load: { Data([1]) }, using: spy) == nil)
    #expect(wrongType.error == "This file type is not supported for this list.")
    let blank = UploadFileForm(kind: .presentation, title: "   ")
    #expect(await blank.submit(courseID: UUID(), fileName: "deck.pdf", size: 10, load: { Data([1]) }, using: spy) == nil)
    #expect(blank.error == "Enter a title.")
    #expect(await spy.uploads == 0)
}

@MainActor @Test func validFileUploadsWithTrimmedTitle() async {
    let spy = UploadSpy()
    let form = UploadFileForm(kind: .exercise, title: "  Worksheet 1 ")
    let file = await form.submit(courseID: UUID(), fileName: "w.pdf", size: 1, load: { Data([1]) }, using: spy)
    #expect(file?.title == "Worksheet 1" && file?.kind == .exercise)
    #expect(form.error == nil)
    #expect(await spy.uploads == 1)
}

@Test func courseCardCountsPresentationsAndExercisesPerCourse() async throws {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "teacher@example.com", password: "secret", name: "Teacher", role: .teacher)
    let science = try await backend.createCourse(name: "Science", description: nil)
    let art = try await backend.createCourse(name: "Art", description: nil)
    for (kind, name) in [(CourseFileKind.presentation, "a.pdf"), (.presentation, "b.pptx"), (.exercise, "c.docx")] {
        _ = try await backend.uploadFile(courseID: science.id, kind: kind, title: name, data: Data([1]), fileName: name)
    }
    let counts = CourseFileCounts(files: try await backend.allFiles())
    #expect(counts.label(for: science.id) == "2 Presentations · 1 Exercise")
    #expect(counts.label(for: art.id) == "0 Presentations · 0 Exercises")
}
