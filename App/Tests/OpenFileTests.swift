import Testing
import Foundation
@testable import Project2

private func tempCache() -> FileCache { FileCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())")) }

/// Teacher uploads one file to a Course that `student` has joined; returns the shared store, the teacher backend and the file.
private func courseWithFile(store: InMemoryBackend.Store, cache: FileCache, data: Data = Data("hello".utf8)) async throws -> (teacher: InMemoryBackend, course: Course, file: CourseFile) {
    let teacher = InMemoryBackend(store: store, cache: cache)
    try await teacher.signUp(email: "t@example.com", password: "secret", name: "T", role: .teacher)
    let course = try await teacher.createCourse(name: "Science", description: nil)
    let file = try await teacher.uploadFile(courseID: course.id, kind: .presentation, title: "Week 1: Intro/Cells", data: data, fileName: "intro.pdf")
    return (teacher, course, file)
}

@Test func downloadReturnsLocalFileWithTheUploadedBytes() async throws {
    let (teacher, _, file) = try await courseWithFile(store: .init(), cache: tempCache())
    let url = try await teacher.download(file: file)
    #expect(url.isFileURL)
    #expect(url.pathExtension == "pdf")
    #expect(try Data(contentsOf: url) == Data("hello".utf8))
}

@Test func secondOpenUsesTheCachedCopy() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, _, file) = try await courseWithFile(store: store, cache: tempCache())
    let first = try await teacher.download(file: file)
    let second = try await teacher.download(file: file)
    #expect(first == second)
    #expect(store.downloadCount == 1)
}

@Test func cachedCopySurvivesBackendFailure() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, _, file) = try await courseWithFile(store: store, cache: tempCache())
    let url = try await teacher.download(file: file)
    store.offline = true
    #expect(try await teacher.download(file: file) == url)
}

@Test func failureWithoutCachedCopyThrows() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, _, file) = try await courseWithFile(store: store, cache: tempCache())
    store.offline = true
    await #expect(throws: (any Error).self) { try await teacher.download(file: file) }
}

@Test func rosterStudentListsAndDownloadsButOutsiderCannot() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, course, file) = try await courseWithFile(store: store, cache: tempCache())
    let student = InMemoryBackend(store: store, cache: tempCache())
    try await student.signUp(email: "s@example.com", password: "secret", name: "S", role: .student)
    #expect(try await student.files(courseID: course.id).isEmpty)
    await #expect(throws: BackendError.fileUnavailable) { try await student.download(file: file) }
    _ = try await student.joinCourse(code: course.joinCode)
    #expect(try await student.files(courseID: course.id).map(\.id) == [file.id])
    #expect(try await student.download(file: file).isFileURL)
    _ = teacher
}

@Test func cacheNamesTheFileAfterItsTitleWithoutPathSeparators() async throws {
    let (teacher, _, file) = try await courseWithFile(store: .init(), cache: tempCache())
    let url = try await teacher.download(file: file)
    #expect(url.lastPathComponent == "Week 1: Intro-Cells.pdf")
}
