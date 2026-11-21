import SwiftUI

@main struct Project2App: App {
    var body: some Scene { WindowGroup { RootView().preferredColorScheme(.light) } }
}

private enum Style {
    static let green = Color(red: 37 / 255, green: 77 / 255, blue: 67 / 255)
    static let canvas = Color(red: 246 / 255, green: 244 / 255, blue: 252 / 255)
}

private struct RootView: View {
    private let backend: any Backend = SupabaseBackend(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
    @State private var user: AppUser?
    @State private var mode = false
    @State private var tab = 0
    var body: some View {
        Group {
            if let user { TabView(selection: $tab) {
                courses(user).tabItem { Label("Courses", systemImage: "square.grid.2x2.fill") }.tag(0)
                profile(user).tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }.tag(1)
            }.tint(Style.green) } else { AuthView(backend: backend) { user = $0 } }
        }
        .task { user = try? await backend.currentUser() }
    }
    private func courses(_ user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Good morning,").foregroundStyle(.secondary)
            Text(user.name).font(.largeTitle.bold())
            Text("Your courses").font(.title2.bold()).padding(.top, 10)
            Spacer()
            Text("Your courses will appear here.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
            Button(user.role == .teacher ? "+ New Course" : "Join with code") {}.buttonStyle(PrimaryButton())
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Style.canvas)
    }
    private func profile(_ user: AppUser) -> some View {
        VStack(spacing: 16) {
            Text(user.name.split(separator: " ").compactMap(\.first).map(String.init).joined()).font(.title.bold()).foregroundStyle(Style.green).frame(width: 88, height: 88).background(Style.green.opacity(0.12), in: Circle()).padding(.top, 80)
            Text(user.name).font(.title2.bold()); Text(user.role.rawValue.capitalized).foregroundStyle(.secondary)
            Button("Sign out") { Task { try? await backend.signOut(); self.user = nil } }.buttonStyle(PrimaryButton())
            Spacer()
        }.padding(24).frame(maxWidth: .infinity).background(Style.canvas)
    }
}

private struct AuthView: View {
    let backend: any Backend
    let onSignedIn: (AppUser?) -> Void
    @State private var signup = true
    @State private var role: UserRole = .teacher
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 220 / 255, green: 213 / 255, blue: 1), Color(red: 246 / 255, green: 233 / 255, blue: 1), Style.canvas], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                Text(signup ? "Create your account" : "Welcome back").font(.largeTitle.bold()).padding(.top, 80)
                Text(signup ? "Join your classroom and keep learning." : "Sign in to continue.").foregroundStyle(.secondary)
                if signup { TextField("Full name", text: $name).textContentType(.name).textInputAutocapitalization(.words).fieldStyle() }
                TextField("Email address", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().fieldStyle()
                SecureField("Password", text: $password).textContentType(signup ? .newPassword : .password).fieldStyle()
                if signup {
                    Text("I am a").font(.headline)
                    HStack { roleCard(.teacher); roleCard(.student) }
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button(signup ? "Create account" : "Sign in") { submit() }.buttonStyle(PrimaryButton())
                Button(signup ? "Already have an account? Sign in" : "New here? Create account") { signup.toggle() }.frame(maxWidth: .infinity).foregroundStyle(Style.green)
            }.padding(24) }
        }
    }
    private func roleCard(_ value: UserRole) -> some View {
        Button { role = value } label: {
            VStack(spacing: 12) { Image(systemName: value == .teacher ? "person.crop.rectangle.stack" : "graduationcap").font(.title2); Text(value.rawValue.capitalized).font(.headline) }
                .foregroundStyle(role == value ? Style.green : .secondary).frame(maxWidth: .infinity).padding(.vertical, 24).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(role == value ? Style.green : .clear, lineWidth: 2))
        }.accessibilityAddTraits(role == value ? .isSelected : [])
    }
    private func submit() { Task {
        do {
            if signup { try await backend.signUp(email: email, password: password, name: name, role: role) }
            else { try await backend.signIn(email: email, password: password) }
            onSignedIn(try await backend.currentUser())
        } catch { self.error = error.localizedDescription }
    } }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(Style.green, in: RoundedRectangle(cornerRadius: 16)).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.14), value: configuration.isPressed) }
}
private extension View { func fieldStyle() -> some View { padding(16).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 15)) } }
