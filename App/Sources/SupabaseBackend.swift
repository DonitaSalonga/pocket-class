import Foundation
import Supabase

final class SupabaseBackend: Backend, @unchecked Sendable {
    private let client: SupabaseClient
    /// `storage` holds the persisted session; tests pass their own because the default Keychain needs a signed host.
    init(url: URL, anonKey: String, storage: any AuthLocalStorage = AuthClient.Configuration.defaultLocalStorage) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: .init(auth: .init(storage: storage, emitLocalSessionAsInitialSession: true)))
    }
    func signUp(email: String, password: String, name: String, role: UserRole) async throws {
        _ = try await client.auth.signUp(email: email, password: password, data: ["name": .string(name), "role": .string(role.rawValue)])
    }
    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }
    func signOut() async throws { try await client.auth.signOut() }
    func currentUser() async throws -> AppUser? {
        guard let user = client.auth.currentSession?.user else { return nil }
        let profile: Profile = try await client.from("profiles").select().eq("id", value: user.id.uuidString).single().execute().value
        return AppUser(id: user.id, name: profile.name, email: user.email ?? "", role: profile.role)
    }
    func currentUserID() async throws -> UUID? { client.auth.currentSession?.user.id }
    func resetPassword(email: String) async throws { try await client.auth.resetPasswordForEmail(email) }
    func updateRole(_ role: UserRole) async throws {
        guard let id = try? await client.auth.user().id else { throw BackendError.invalidCredentials }
        try await client.from("profiles").update(["role": role.rawValue]).eq("id", value: id.uuidString).execute()
    }
    func profile(id: UUID) async throws -> AppUser? {
        guard let profile: Profile = try? await client.from("profiles").select().eq("id", value: id.uuidString).single().execute().value else { return nil }
        return AppUser(id: id, name: profile.name, email: "", role: profile.role)
    }
    func createCourse(name: String, description: String?) async throws -> Course {
        struct NewCourse: Encodable { let name: String; let description: String? }
        return try await client.from("courses").insert(NewCourse(name: name, description: description)).select().single().execute().value
    }
    func myCourses() async throws -> [Course] {
        return try await client.from("courses").select().order("created_at", ascending: false).execute().value
    }
    func joinCourse(code: String) async throws -> Course {
        struct JoinRequest: Encodable { let join_code_input: String }
        do {
            return try await client.rpc("join_course", params: JoinRequest(join_code_input: code)).execute().value
        } catch let error as PostgrestError {
            // Codes raised by join_course: P0001 wrong Join Code, 42501 caller is not a Student.
            switch error.code {
            case "P0001": throw BackendError.invalidJoinCode
            case "42501": throw BackendError.notAStudent
            default: throw error
            }
        }
    }
    func uploadFile(courseID: UUID, kind: CourseFileKind, title: String, data: Data, fileName: String) async throws -> CourseFile {
        try CourseFileValidation.validate(kind: kind, fileName: fileName, size: data.count)
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let path = CourseFileValidation.newStoragePath(courseID: courseID, fileName: fileName)
        try await client.storage.from("course-files").upload(path, data: data, options: .init(contentType: Self.mimeType(ext)))
        struct NewFile: Encodable { let course_id: UUID; let kind: String; let title: String; let storage_path: String; let file_type: String; let size: Int }
        return try await client.from("course_files").insert(NewFile(course_id: courseID, kind: kind.rawValue, title: title, storage_path: path, file_type: ext, size: data.count)).select().single().execute().value
    }
    func files(courseID: UUID) async throws -> [CourseFile] {
        try await client.from("course_files").select().eq("course_id", value: courseID.uuidString).order("uploaded_at", ascending: false).execute().value
    }
    func allFiles() async throws -> [CourseFile] {
        try await client.from("course_files").select().order("uploaded_at", ascending: false).execute().value
    }
    func renameFile(id: UUID, title: String) async throws -> CourseFile {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw BackendError.blankTitle }
        // RLS hides rows the caller does not own, so an unauthorized update matches zero rows instead of failing.
        let rows: [CourseFile] = try await client.from("course_files").update(["title": title]).eq("id", value: id.uuidString).select().execute().value
        guard let file = rows.first else { throw BackendError.fileNotFound }
        return file
    }
    /// Object first, then row. If the object removal fails nothing changed and the file stays listed, so the Teacher can retry.
    /// If the row delete fails after the object is gone, the row stays listed with no object; retrying removes the row, because removing a missing object is not an error.
    /// Removing the row first would risk the opposite: an orphaned object that nothing lists and nobody can delete.
    func deleteFile(_ file: CourseFile) async throws {
        _ = try await client.storage.from("course-files").remove(paths: [file.storagePath])
        let rows: [CourseFile] = try await client.from("course_files").delete().eq("id", value: file.id.uuidString).select().execute().value
        guard !rows.isEmpty else { throw BackendError.fileNotFound }
    }
    private static func mimeType(_ ext: String) -> String {
        switch ext { case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"; case "ppt": "application/vnd.ms-powerpoint"; case "key": "application/x-iwork-keynote-sffkey"; case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"; default: "application/pdf" }
    }
}

private struct Profile: Decodable { let name: String; let role: UserRole }
