import Foundation
import Observation

/// State behind the Join with code sheet: keeps the code uppercase and turns failures into a message the sheet can show.
@MainActor @Observable final class JoinCourseForm {
    var code = "" { didSet { if code != code.uppercased() { code = code.uppercased() } } }
    var error: String?
    var isSubmitting = false

    func submit(using backend: any Backend) async -> Course? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Enter a Join Code."; return nil }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let course = try await backend.joinCourse(code: trimmed)
            error = nil
            return course
        } catch let failure as BackendError {
            error = failure.errorDescription
        } catch {
            self.error = "Could not join the course. Check your connection and try again."
        }
        return nil
    }
}
