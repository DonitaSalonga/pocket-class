import Foundation
import Supabase

final class SupabaseBackend: Backend, @unchecked Sendable {
    private let client: SupabaseClient
    init(url: URL, anonKey: String) { client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey) }
    func signUp(email: String, password: String, name: String, role: UserRole) async throws {
        try await client.auth.signUp(email: email, password: password, data: ["name": .string(name), "role": .string(role.rawValue)])
    }
    func signIn(email: String, password: String) async throws { try await client.auth.signIn(email: email, password: password) }
    func signOut() async throws { try await client.auth.signOut() }
    func currentUser() async throws -> AppUser? {
        guard let user = try? await client.auth.user() else { return nil }
        let profile: Profile = try await client.from("profiles").select().eq("id", value: user.id.uuidString).single().execute().value
        return AppUser(id: user.id, name: profile.name, email: user.email ?? "", role: profile.role)
    }
    func resetPassword(email: String) async throws { try await client.auth.resetPasswordForEmail(email) }
}

private struct Profile: Decodable { let name: String; let role: UserRole }
