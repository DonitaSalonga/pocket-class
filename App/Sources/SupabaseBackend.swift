import Foundation
import Supabase

final class SupabaseBackend: Backend, @unchecked Sendable {
    private let client: SupabaseClient
    private var signedInID: UUID?
    init(url: URL, anonKey: String) { client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey) }
    func signUp(email: String, password: String, name: String, role: UserRole) async throws {
        let response = try await client.auth.signUp(email: email, password: password, data: ["name": .string(name), "role": .string(role.rawValue)])
        signedInID = response.user.id
        if let session = response.session { _ = try await client.auth.setSession(accessToken: session.accessToken, refreshToken: session.refreshToken) }
    }
    func signIn(email: String, password: String) async throws {
        let response = try await client.auth.signIn(email: email, password: password)
        signedInID = response.user.id
        _ = try await client.auth.setSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
    }
    func signOut() async throws { try await client.auth.signOut(); signedInID = nil }
    func currentUser() async throws -> AppUser? {
        let user = client.auth.currentSession?.user
        guard let id = user?.id ?? signedInID else { return nil }
        let profile: Profile = try await client.from("profiles").select().eq("id", value: id.uuidString).single().execute().value
        return AppUser(id: id, name: profile.name, email: user?.email ?? "", role: profile.role)
    }
    func currentUserID() async throws -> UUID? { client.auth.currentSession?.user.id ?? signedInID }
    func resetPassword(email: String) async throws { try await client.auth.resetPasswordForEmail(email) }
    func updateRole(_ role: UserRole) async throws {
        guard let id = try? await client.auth.user().id else { throw BackendError.invalidCredentials }
        try await client.from("profiles").update(["role": role.rawValue]).eq("id", value: id.uuidString).execute()
    }
    func profile(id: UUID) async throws -> AppUser? {
        guard let profile: Profile = try? await client.from("profiles").select().eq("id", value: id.uuidString).single().execute().value else { return nil }
        return AppUser(id: id, name: profile.name, email: "", role: profile.role)
    }
}

private struct Profile: Decodable { let name: String; let role: UserRole }
