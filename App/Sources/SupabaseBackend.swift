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
        guard let user = try await currentUser(), user.role == .teacher else { return [] }
        return try await client.from("courses").select().order("created_at", ascending: false).execute().value
    }
}

private struct Profile: Decodable { let name: String; let role: UserRole }
