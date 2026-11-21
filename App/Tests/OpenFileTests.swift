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

@Test func deletingAFileRemovesItsCachedCopy() async throws {
    let cache = tempCache()
    let (teacher, _, file) = try await courseWithFile(store: .init(), cache: cache)
    let url = try await teacher.download(file: file)
    try await teacher.deleteFile(file)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
}

@Test func renamedFileKeepsItsCachedCopyOffline() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, _, file) = try await courseWithFile(store: store, cache: tempCache())
    _ = try await teacher.download(file: file)
    let renamed = try await teacher.renameFile(id: file.id, title: "Renamed")
    store.offline = true
    let url = try await teacher.download(file: renamed)
    #expect(url.lastPathComponent == "Renamed.pdf")
    #expect(try Data(contentsOf: url) == Data("hello".utf8))
}

@Test func leavingACourseClearsItsCachedFilesOnThisDevice() async throws {
    let store = InMemoryBackend.Store()
    let (_, course, file) = try await courseWithFile(store: store, cache: tempCache())
    let student = InMemoryBackend(store: store, cache: tempCache())
    try await student.signUp(email: "s@example.com", password: "secret", name: "S", role: .student)
    _ = try await student.joinCourse(code: course.joinCode)
    let url = try await student.download(file: file)
    try await student.leaveCourse(courseID: course.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func removedStudentsCachedFilesAreClearedWhenCoursesRefresh() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, course, file) = try await courseWithFile(store: store, cache: tempCache())
    let student = InMemoryBackend(store: store, cache: tempCache())
    try await student.signUp(email: "s@example.com", password: "secret", name: "S", role: .student)
    let studentID = try #require(await student.currentUserID())
    _ = try await student.joinCourse(code: course.joinCode)
    let url = try await student.download(file: file)
    // Backends sharing a store share the signed-in user, so switch to the Teacher and back.
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.removeStudent(courseID: course.id, studentID: studentID)
    #expect(FileManager.default.fileExists(atPath: url.path))
    try await student.signIn(email: "s@example.com", password: "secret")
    #expect(try await student.myCourses().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

/// Student with a cached copy of `file`; the Teacher then changes the Course behind their back.
private func cachedStudent(_ store: InMemoryBackend.Store) async throws -> (teacher: InMemoryBackend, student: InMemoryBackend, course: Course, file: CourseFile, url: URL) {
    let (teacher, course, file) = try await courseWithFile(store: store, cache: tempCache())
    let student = InMemoryBackend(store: store, cache: tempCache())
    try await student.signUp(email: "s@example.com", password: "secret", name: "S", role: .student)
    _ = try await student.joinCourse(code: course.joinCode)
    let url = try await student.download(file: file)
    return (teacher, student, course, file, url)
}

@Test func fileListRefreshClearsCachedCopiesOfDeletedFilesAndKeepsTheRest() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, course, file, url) = try await cachedStudent(store)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    let other = try await teacher.uploadFile(courseID: course.id, kind: .exercise, title: "Sheet", data: Data("x".utf8), fileName: "sheet.pdf")
    try await student.signIn(email: "s@example.com", password: "secret")
    let otherURL = try await student.download(file: other)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.deleteFile(file)
    try await student.signIn(email: "s@example.com", password: "secret")
    _ = try await student.files(courseID: course.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(FileManager.default.fileExists(atPath: otherURL.path))
}

@Test func allFilesRefreshClearsCachedCopiesOfDeletedFiles() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, _, file, url) = try await cachedStudent(store)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.deleteFile(file)
    try await student.signIn(email: "s@example.com", password: "secret")
    #expect(try await student.allFiles().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func deletedCourseCachedFilesAreClearedWhenCoursesRefresh() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, course, _, url) = try await cachedStudent(store)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.deleteCourse(course)
    try await student.signIn(email: "s@example.com", password: "secret")
    #expect(try await student.myCourses().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func failedRefreshKeepsEveryCachedCopy() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, course, file, url) = try await cachedStudent(store)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.deleteFile(file)
    try await student.signIn(email: "s@example.com", password: "secret")
    store.offline = true
    await #expect(throws: (any Error).self) { try await student.myCourses() }
    await #expect(throws: (any Error).self) { try await student.files(courseID: course.id) }
    await #expect(throws: (any Error).self) { try await student.allFiles() }
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func offlineRefreshFailsButLastSnapshotStaysAvailable() async throws {
    let store = InMemoryBackend.Store()
    let (_, student, course, file, _) = try await cachedStudent(store)
    #expect(try await student.myCourses().map(\.id) == [course.id])
    #expect(try await student.files(courseID: course.id).map(\.id) == [file.id])
    store.offline = true
    await #expect(throws: (any Error).self) { try await student.files(courseID: course.id) }
    #expect(await student.cachedCourses()?.map(\.id) == [course.id])
    #expect(await student.cachedFiles(courseID: course.id)?.map(\.id) == [file.id])
}

@Test func onlyRowsWithACachedCopyOpenOffline() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, course, file, url) = try await cachedStudent(store)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    let other = try await teacher.uploadFile(courseID: course.id, kind: .exercise, title: "Sheet", data: Data("x".utf8), fileName: "sheet.pdf")
    try await student.signIn(email: "s@example.com", password: "secret")
    _ = try await student.files(courseID: course.id)
    store.offline = true
    #expect(await student.hasCachedCopy(file))
    #expect(try await student.download(file: file) == url)
    #expect(await !student.hasCachedCopy(other))
    await #expect(throws: (any Error).self) { try await student.download(file: other) }
}

@Test func snapshotIsClearedWhenTheStudentLeavesOrSignsOut() async throws {
    let store = InMemoryBackend.Store()
    let (_, student, course, _, _) = try await cachedStudent(store)
    _ = try await student.myCourses(); _ = try await student.files(courseID: course.id)
    try await student.leaveCourse(courseID: course.id)
    #expect(await student.cachedFiles(courseID: course.id) == nil)
    _ = try await student.joinCourse(code: course.joinCode)
    _ = try await student.myCourses(); _ = try await student.files(courseID: course.id)
    #expect(await student.cachedCourses() != nil)
    try await student.signOut()
    #expect(await student.cachedCourses() == nil)
    #expect(await student.cachedFiles(courseID: course.id) == nil)
}

@Test func snapshotIsClearedWhenRemovedFromTheRosterOrTheCourseIsDeleted() async throws {
    let store = InMemoryBackend.Store()
    let (teacher, student, course, _, _) = try await cachedStudent(store)
    let studentID = try #require(await student.currentUserID())
    _ = try await student.myCourses(); _ = try await student.files(courseID: course.id)
    try await teacher.signIn(email: "t@example.com", password: "secret")
    try await teacher.removeStudent(courseID: course.id, studentID: studentID)
    try await student.signIn(email: "s@example.com", password: "secret")
    #expect(try await student.myCourses().isEmpty)
    #expect(await student.cachedFiles(courseID: course.id) == nil)
    #expect(await student.cachedCourses()?.isEmpty == true)
}
