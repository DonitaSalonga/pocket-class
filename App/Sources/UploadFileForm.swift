import Foundation
import Observation

/// State behind the Upload sheet: checks title, type and size before reading the file or calling the backend.
@MainActor @Observable final class UploadFileForm {
    var kind: CourseFileKind
    var title: String
    var error: String?
    var isUploading = false

    init(kind: CourseFileKind = .presentation, title: String = "") { self.kind = kind; self.title = title }

    /// `size` comes from the file's metadata so an oversize file is never loaded into memory.
    func submit(courseID: UUID, fileName: String, size: Int, load: () throws -> Data, using backend: any Backend) async -> CourseFile? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Enter a title."; return nil }
        isUploading = true
        defer { isUploading = false }
        do {
            try CourseFileValidation.validate(kind: kind, fileName: fileName, size: size)
            let file = try await backend.uploadFile(courseID: courseID, kind: kind, title: trimmed, data: try load(), fileName: fileName)
            error = nil
            return file
        } catch let failure as BackendError {
            error = failure.errorDescription
        } catch {
            self.error = "Could not upload the file. Check your connection and try again."
        }
        return nil
    }
}

/// Real per-Course counts for the badge on a Course card.
struct CourseFileCounts {
    let files: [CourseFile]
    func label(for courseID: UUID) -> String {
        let mine = files.filter { $0.courseID == courseID }
        let presentations = mine.filter { $0.kind == .presentation }.count, exercises = mine.count - presentations
        return "\(presentations) Presentation\(presentations == 1 ? "" : "s") · \(exercises) Exercise\(exercises == 1 ? "" : "s")"
    }
}
