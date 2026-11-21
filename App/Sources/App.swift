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
    @State private var tab = 0
    @State private var coursesList: [Course] = []
    @State private var showingNewCourse = false
    @State private var selectedCourse: Course?
    var body: some View {
        Group {
            if let user {
                VStack(spacing: 12) {
                    Group { tab == 0 ? AnyView(courses(user)) : AnyView(profile(user)) }
                    HStack(spacing: 8) {
                        tabButton("Courses", icon: "square.grid.2x2.fill", index: 0)
                        tabButton("Profile", icon: "person.crop.circle.fill", index: 1)
                    }.padding(6).background(.white, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 16, y: 5).padding(.bottom, 8)
                }.background(Style.canvas.ignoresSafeArea())
            } else { AuthView(backend: backend) { user = $0 } }
        }
        .sheet(isPresented: $showingNewCourse) { NewCourseSheet { name, description in
            do { let course = try await backend.createCourse(name: name, description: description); coursesList.insert(course, at: 0); showingNewCourse = false }
            catch { }
        } }
        .sheet(item: $selectedCourse) { course in CourseDetail(course: course, teacher: user?.role == .teacher) }
        .task {
            #if DEBUG
            // Live-check hook: `-debugEmail x -debugPassword y [-debugTab profile]` signs in without typing.
            let arguments = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } }
            if let email = value("-debugEmail"), let password = value("-debugPassword") {
                try? await backend.signIn(email: email, password: password)
                tab = value("-debugTab") == "profile" ? 1 : 0
            }
            #endif
            user = try? await backend.currentUser()
            coursesList = (try? await backend.myCourses()) ?? []
        }
    }
    private func courses(_ user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) { Text("Good morning,").foregroundStyle(.secondary); Text(user.name).font(.largeTitle.bold()) }
                Spacer()
                avatar(user, size: 48)
            }.padding(.top, 50)
            Text("Your courses").font(.title2.bold()).padding(.top, 10)
            if coursesList.isEmpty { Spacer(); Text("Your courses will appear here.").foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer() }
            else { ScrollView { VStack(spacing: 14) { ForEach(Array(coursesList.enumerated()), id: \.element.id) { index, course in Button { selectedCourse = course } label: { CourseCard(course: course, index: index) }.buttonStyle(.plain) } } } }
            Button(user.role == .teacher ? "+ New Course" : "Join with code") { if user.role == .teacher { showingNewCourse = true } }.buttonStyle(PrimaryButton()).disabled(user.role != .teacher).opacity(user.role == .teacher ? 1 : 0.72)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Style.canvas)
    }
    private func profile(_ user: AppUser) -> some View {
        VStack(spacing: 16) {
            avatar(user, size: 88).padding(.top, 80)
            Text(user.name).font(.title2.bold()); Text(user.role.rawValue.capitalized).foregroundStyle(.secondary)
            Button("Sign out") { Task { try? await backend.signOut(); self.user = nil } }.buttonStyle(PrimaryButton())
            Spacer()
        }.padding(24).frame(maxWidth: .infinity).background(Style.canvas)
    }
    private func avatar(_ user: AppUser, size: CGFloat) -> some View {
        Text(user.name.split(separator: " ").compactMap(\.first).map(String.init).joined()).font(.headline.bold()).foregroundStyle(Style.green).frame(width: size, height: size).background(Style.green.opacity(0.12), in: Circle()).accessibilityLabel("Profile avatar")
    }
    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: { Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(tab == index ? .white : .secondary).padding(.horizontal, 19).padding(.vertical, 13).background(tab == index ? Style.green : .clear, in: Capsule()) }.accessibilityLabel(title)
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

private struct CourseCard: View {
    let course: Course
    let index: Int
    private let colors: [Color] = [.init(red: 37/255, green: 77/255, blue: 67/255), .init(red: 191/255, green: 137/255, blue: 54/255), .init(red: 137/255, green: 120/255, blue: 180/255)]
    var body: some View { let color = colors[index % colors.count]
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(course.name).font(.title2.bold()); Spacer(); Text(String(format: "%02d", index + 1)).font(.system(size: 50, weight: .black, design: .rounded)).opacity(0.18) }
            Text("0 Presentations · 0 Exercises").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.2), in: Capsule())
        }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(color, in: RoundedRectangle(cornerRadius: 24)).shadow(color: color.opacity(0.2), radius: 12, y: 6)
    }
}

private struct NewCourseSheet: View {
    let create: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    var body: some View { NavigationStack { Form { TextField("Course name", text: $name); TextField("Description (optional)", text: $description) }
        .navigationTitle("New Course").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { await create(name, description.isEmpty ? nil : description) } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
    } }
}

private struct CourseDetail: View {
    let course: Course
    let teacher: Bool
    @State private var copied = false
    var body: some View { VStack(alignment: .leading, spacing: 20) {
        Text(course.name).font(.largeTitle.bold())
        if teacher { Text("Join Code").font(.headline); HStack { Text(course.joinCode).font(.system(.title, design: .monospaced).bold()); Spacer(); Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = course.joinCode; copied = true }.buttonStyle(.borderedProminent).tint(Style.green) }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18)) }
        Spacer()
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Style.canvas).navigationTitle("Course") }
}

private extension View { func fieldStyle() -> some View { padding(16).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 15)) } }
