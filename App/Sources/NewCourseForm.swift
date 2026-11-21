import Foundation
import Observation

/// State behind the New Course sheet: validates the name and turns failures into a message the sheet can show.
@MainActor @Observable final class NewCourseForm {
    var name = ""
    var description = ""
    var error: String?
    var isSubmitting = false

    func submit(using backend: any Backend) async -> Course? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Enter a course name."; return nil }
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let course = try await backend.createCourse(name: trimmed, description: note.isEmpty ? nil : note)
            error = nil
            return course
        } catch let failure as BackendError {
            error = failure.errorDescription
        } catch {
            self.error = "Could not create the course. Check your connection and try again."
        }
        return nil
    }
}
