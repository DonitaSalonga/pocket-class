import Foundation
import Observation

/// State behind the Rename sheet: starts from the current title and shows why a rename was refused.
@MainActor @Observable final class RenameFileForm {
    let file: CourseFile
    var title: String
    var error: String?
    var isSaving = false

    init(file: CourseFile) { self.file = file; title = file.title }

    func submit(using backend: any Backend) async -> CourseFile? {
        isSaving = true
        defer { isSaving = false }
        do {
            let renamed = try await backend.renameFile(id: file.id, title: title)
            error = nil
            return renamed
        } catch let failure as BackendError {
            error = failure.errorDescription
        } catch {
            self.error = "Could not rename the file. Check your connection and try again."
        }
        return nil
    }
}
