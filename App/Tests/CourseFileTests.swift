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
