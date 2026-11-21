import Foundation
import Supabase
@testable import PocketClass

/// Reusable Supabase accounts so test runs do not hit the auth sign-up rate limit.
/// Passwords live outside the repo in `~/.config/pocket-class/test-accounts.env` (created on first use, mode 600).
enum PoolAccount: String, CaseIterable {
    case teacherA, teacherB, studentA, studentB, outsider
    var role: UserRole { rawValue.hasPrefix("teacher") ? .teacher : .student }
    var email: String { "pool-\(rawValue.lowercased())@example.com" }
    var name: String { "Pool \(rawValue)" }
}

struct PoolCredentials { let email: String; let password: String }

/// One signed-in app backend and one raw client per account per run, shared by all tests, to stay under the sign-in rate limit.
struct PoolSession { let backend: SupabaseBackend; let raw: SupabaseClient; let email: String; let password: String }

actor TestAccounts {
    static let shared = TestAccounts()
    private var passwords: [String: String]?
    private var sessions: [PoolAccount: PoolSession] = [:]

    func credentials(_ account: PoolAccount) async throws -> PoolCredentials {
        let session = try await session(account)
        return PoolCredentials(email: session.email, password: session.password)
    }

    func session(_ account: PoolAccount) async throws -> PoolSession {
        if let existing = sessions[account] { return existing }
        let email = account.email, password = try password(for: account)
        let client = backend()
        do { try await client.signIn(email: email, password: password) }
        catch {
            // First run, or a sign-up that raced another test: an "already registered" failure is fine as long as the sign-in below works.
            try? await client.signUp(email: email, password: password, name: account.name, role: account.role)
            do { try await client.signIn(email: email, password: password) }
            catch { throw PoolError.cannotSignIn(email) }
        }
        let raw = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey, options: .init(auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true)))
        try await raw.auth.signIn(email: email, password: password)
        // Another test may have filled the cache while this one awaited; keep the first so every test shares it.
        if let existing = sessions[account] { return existing }
        let session = PoolSession(backend: client, raw: raw, email: email, password: password)
        sessions[account] = session
        return session
    }

    private func password(for account: PoolAccount) throws -> String {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()).appending(path: ".config/pocket-class/test-accounts.env")
        if passwords == nil {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            passwords = Dictionary(text.split(separator: "\n").compactMap { line in
                line.split(separator: "=", maxSplits: 1).map(String.init).nilIfNotPair
            }, uniquingKeysWith: { _, last in last })
        }
        let key = account.rawValue
        if let existing = passwords?[key] { return existing }
        let created = "Pw-\(UUID().uuidString)-a1!"
        passwords?[key] = created
        let body = (passwords ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return created
    }
}

enum PoolError: Error, CustomStringConvertible {
    case cannotSignIn(String)
    var description: String {
        switch self { case .cannotSignIn(let email): "Cannot sign in \(email). If ~/.config/pocket-class/test-accounts.env was lost, delete that user in the Supabase dashboard and rerun." }
    }
}

private extension Array where Element == String {
    var nilIfNotPair: (String, String)? { count == 2 ? (self[0], self[1]) : nil }
}
