import Testing
import Foundation
@testable import PocketClass

/// The in-memory store holds one signed-in user, so tests switch accounts with `signIn`.
private func scene() async throws -> (backend: InMemoryBackend, course: Course) {
    let backend = InMemoryBackend()
    try await backend.signUp(email: "s@example.com", password: "secret", name: "S", role: .student)
    try await backend.signUp(email: "o@example.com", password: "secret", name: "O", role: .teacher)
    try await backend.signUp(email: "t@example.com", password: "secret", name: "T", role: .teacher)
    return (backend, try await backend.createCourse(name: "Science", description: nil))
}

@Test func regeneratedJoinCodeReplacesTheOldOne() async throws {
    let (backend, course) = try await scene()
    let newCode = try await backend.regenerateJoinCode(courseID: course.id)
    #expect(newCode != course.joinCode)
    #expect(newCode.count == 6)
    #expect(try await backend.myCourses().first?.joinCode == newCode)
    try await backend.signIn(email: "s@example.com", password: "secret")
    await #expect(throws: BackendError.invalidJoinCode) { try await backend.joinCourse(code: course.joinCode) }
    #expect(try await backend.joinCourse(code: newCode).id == course.id)
}

@Test func onlyTheOwningTeacherCanRegenerateOrDelete() async throws {
    let (backend, course) = try await scene()
    for email in ["o@example.com", "s@example.com"] {
        try await backend.signIn(email: email, password: "secret")
        await #expect(throws: BackendError.notATeacher) { try await backend.regenerateJoinCode(courseID: course.id) }
        await #expect(throws: BackendError.notATeacher) { try await backend.deleteCourse(course) }
    }
    try await backend.signIn(email: "t@example.com", password: "secret")
    #expect(try await backend.myCourses().map(\.id) == [course.id])
    #expect(try await backend.myCourses().first?.joinCode == course.joinCode)
}

@Test func deletingACourseRemovesRosterAndFiles() async throws {
    let (backend, course) = try await scene()
    _ = try await backend.uploadFile(courseID: course.id, kind: .exercise, title: "Sheet", data: Data([1]), fileName: "sheet.pdf")
    try await backend.signIn(email: "s@example.com", password: "secret")
    _ = try await backend.joinCourse(code: course.joinCode)
    #expect(try await backend.myCourses().count == 1)
    try await backend.signIn(email: "t@example.com", password: "secret")
    try await backend.deleteCourse(course)
    #expect(try await backend.myCourses().isEmpty)
    #expect(try await backend.allFiles().isEmpty)
    #expect(await backend.hasNoRowsFor(courseID: course.id))
    try await backend.signIn(email: "s@example.com", password: "secret")
    #expect(try await backend.myCourses().isEmpty)
    await #expect(throws: BackendError.invalidJoinCode) { try await backend.joinCourse(code: course.joinCode) }
}

@Test func deletingACourseClearsItsCachedFilesOnThisDevice() async throws {
    let cache = FileCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())"))
    let teacher = InMemoryBackend(cache: cache)
    try await teacher.signUp(email: "t@example.com", password: "secret", name: "T", role: .teacher)
    let course = try await teacher.createCourse(name: "Science", description: nil)
    let file = try await teacher.uploadFile(courseID: course.id, kind: .exercise, title: "Sheet", data: Data([1]), fileName: "sheet.pdf")
    let url = try await teacher.download(file: file)
    try await teacher.deleteCourse(course)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
