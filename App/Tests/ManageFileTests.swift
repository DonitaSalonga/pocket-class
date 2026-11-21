import Testing
import Foundation
@testable import Project2

private func teacherWithFile() async throws -> (store: InMemoryBackend.Store, backend: InMemoryBackend, course: Course, file: CourseFile) {
    let store = InMemoryBackend.Store()
    let backend = InMemoryBackend(store: store)
    try await backend.signUp(email: "teacher@example.com", password: "secret", name: "Teacher", role: .teacher)
    let course = try await backend.createCourse(name: "Science", description: nil)
    let file = try await backend.uploadFile(courseID: course.id, kind: .exercise, title: "Old", data: Data([1]), fileName: "a.pdf")
    return (store, backend, course, file)
}

@Test func teacherRenamesFileWithTrimmedTitleAndNothingElseChanges() async throws {
    let (_, backend, course, file) = try await teacherWithFile()
    let renamed = try await backend.renameFile(id: file.id, title: "  New title ")
    #expect(renamed.title == "New title")
    #expect(renamed == CourseFile(id: file.id, courseID: file.courseID, kind: file.kind, title: "New title", storagePath: file.storagePath, fileType: file.fileType, size: file.size, uploadedAt: file.uploadedAt))
    #expect(try await backend.files(courseID: course.id).map(\.title) == ["New title"])
}

@Test func blankTitleIsRefusedAndKeepsTheOldTitle() async throws {
    let (_, backend, course, file) = try await teacherWithFile()
    await #expect(throws: BackendError.blankTitle) { try await backend.renameFile(id: file.id, title: " \n ") }
    #expect(try await backend.files(courseID: course.id).map(\.title) == ["Old"])
}

@Test func teacherDeletesFile() async throws {
    let (_, backend, course, file) = try await teacherWithFile()
    try await backend.deleteFile(file)
    #expect(try await backend.files(courseID: course.id).isEmpty)
    #expect(try await backend.allFiles().isEmpty)
}

@Test func anotherTeacherAndStudentsCannotRenameOrDeleteFiles() async throws {
    let (store, owner, course, file) = try await teacherWithFile()
    let other = InMemoryBackend(store: store)
    try await other.signUp(email: "two@example.com", password: "secret", name: "Two", role: .teacher)
    let student = InMemoryBackend(store: store)
    try await student.signUp(email: "student@example.com", password: "secret", name: "Student", role: .student)
    for outsider in [other, student] {
        await #expect(throws: BackendError.notATeacher) { try await outsider.renameFile(id: file.id, title: "Hijacked") }
        await #expect(throws: BackendError.notATeacher) { try await outsider.deleteFile(file) }
    }
    try await owner.signIn(email: "teacher@example.com", password: "secret") // the store holds one signed-in user
    #expect(try await owner.files(courseID: course.id).map(\.title) == ["Old"])
}

@Test func renamingOrDeletingAMissingFileFails() async throws {
    let (_, backend, _, file) = try await teacherWithFile()
    try await backend.deleteFile(file)
    await #expect(throws: BackendError.fileNotFound) { try await backend.renameFile(id: file.id, title: "Late") }
    await #expect(throws: BackendError.fileNotFound) { try await backend.deleteFile(file) }
}

@MainActor @Test func renameFormShowsMessageForBlankTitleAndReturnsRenamedFile() async throws {
    let (_, backend, _, file) = try await teacherWithFile()
    let form = RenameFileForm(file: file)
    form.title = "   "
    #expect(await form.submit(using: backend) == nil)
    #expect(form.error == "Enter a title.")
    form.title = " Week 1 "
    #expect(await form.submit(using: backend)?.title == "Week 1")
    #expect(form.error == nil)
}
