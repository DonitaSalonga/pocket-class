import SwiftUI
import UniformTypeIdentifiers

/// A file chosen in the Files picker; its security scope is only opened while its size or bytes are read.
private struct PickedFile: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var size: Int {
        guard url.startAccessingSecurityScopedResource() else { return 0 }
        defer { url.stopAccessingSecurityScopedResource() }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    func data() throws -> Data {
        guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        defer { url.stopAccessingSecurityScopedResource() }
        return try Data(contentsOf: url)
    }
}

struct CourseDetail: View {
    let course: Course
    let teacher: Bool
    let backend: any Backend
    let onUploaded: (CourseFile) -> Void
    let onLeave: () -> Void
    var onChanged: () -> Void = {}
    @State var kind: CourseFileKind = .presentation
    @State private var files: [CourseFile] = []
    @State private var copied = false
    @State private var importing = false
    @State private var picked: PickedFile?
    @State private var importError: String?
    @State private var opening: UUID?
    @State private var preview: PreviewItem?
    @State private var showingRoster = debugFlag("-debugOpenRoster")
    @State private var confirmingLeave = debugFlag("-debugConfirmLeave")
    @State private var leaveError: String?
    @State private var renaming: CourseFile?
    @State private var deleting: CourseFile?
    @State private var manageError: String?

    private static let pickerTypes = (["pptx", "ppt", "key", "docx"].compactMap { UTType(filenameExtension: $0) }) + [.pdf]
    private var visible: [CourseFile] { files.filter { $0.kind == kind } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(course.name).font(.largeTitle.bold())
                if teacher {
                    Text("Join Code").font(.headline)
                    HStack { Text(course.joinCode).font(.system(.title, design: .monospaced).bold()); Spacer(); Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = course.joinCode; copied = true }.buttonStyle(.borderedProminent).tint(Style.green) }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(spacing: 10) { chip("Presentations", .presentation); chip("Exercises", .exercise) }
                if teacher { Button("Upload") { importing = true }.buttonStyle(PrimaryButton()).accessibilityIdentifier("uploadButton") }
                if teacher { Button("Roster") { showingRoster = true }.buttonStyle(PrimaryButton()) }
                else { Button("Leave Course", role: .destructive) { confirmingLeave = true }.buttonStyle(PrimaryButton()) }
                if let leaveError { Text(leaveError).font(.footnote).foregroundStyle(.red) }
                if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
                if let manageError { Text(manageError).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("manageError") }
                if visible.isEmpty { Text(kind == .presentation ? "No presentations yet." : "No exercises yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 20) }
                else { VStack(spacing: 10) { ForEach(visible) { file in FileRow(file: file, opening: opening == file.id, onOpen: { open(file) }, onRename: teacher ? { renaming = file } : nil, onDelete: teacher ? { deleting = file } : nil) } } }
            }.padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading).background(Style.canvas)
        .task {
            files = (try? await backend.files(courseID: course.id)) ?? []
            #if DEBUG
            // Screenshot hook: `-debugOpenFile pdf|pptx` previews the first file of that type.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-debugOpenFile"), args.indices.contains(i + 1), let file = files.first(where: { $0.fileType == args[i + 1] }) { kind = file.kind; open(file) }
            // Screenshot hook: `-debugManage rename|delete` opens that action for the first file.
            if let i = args.firstIndex(of: "-debugManage"), args.indices.contains(i + 1), let first = visible.first {
                if args[i + 1] == "rename" { renaming = first } else { deleting = first }
            }
            #endif
        }
        .sheet(item: $preview) { FilePreview(item: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.pickerTypes) { result in
            switch result {
            case .success(let url): importError = nil; picked = PickedFile(url: url)
            case .failure: importError = "Could not open that file."
            }
        }
        .sheet(isPresented: $showingRoster) { RosterView(course: course, backend: backend) }
        .confirmationDialog("Leave \(course.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Course", role: .destructive) { Task { do { try await backend.leaveCourse(courseID: course.id); onLeave() } catch { leaveError = error.localizedDescription } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You will lose access to this course and its files.") }
        .sheet(item: $renaming) { file in
            RenameSheet(form: RenameFileForm(file: file), backend: backend) { renamed in
                if let index = files.firstIndex(where: { $0.id == renamed.id }) { files[index] = renamed }
                renaming = nil
            }
        }
        .confirmationDialog("Delete this file?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { file in
            Button("Delete", role: .destructive) { Task { await delete(file) } }
            Button("Cancel", role: .cancel) {}
        } message: { file in
            Text("“\(file.title)” will be removed for everyone. This cannot be undone.")
        }
        .sheet(item: $picked) { file in
            UploadSheet(course: course, file: file, kind: kind, backend: backend) { uploaded in
                files.insert(uploaded, at: 0); kind = uploaded.kind; onUploaded(uploaded); picked = nil
            }
        }
    }

    private func open(_ file: CourseFile) {
        guard opening == nil else { return }
        opening = file.id; importError = nil
        Task {
            defer { opening = nil }
            do { preview = PreviewItem(title: file.title, url: try await backend.download(file: file)) }
            catch { importError = "Could not open \"\(file.title)\". Check your connection and try again." }
        }
    }

    private func delete(_ file: CourseFile) async {
        do { try await backend.deleteFile(file); manageError = nil; files.removeAll { $0.id == file.id }; onChanged() }
        catch let failure as BackendError { manageError = failure.errorDescription }
        catch { manageError = "Could not delete the file. Check your connection and try again." }
    }

    private func chip(_ title: String, _ value: CourseFileKind) -> some View {
        Button { kind = value } label: {
            Text(title).font(.subheadline.bold()).foregroundStyle(kind == value ? .white : Style.green).padding(.horizontal, 16).padding(.vertical, 10)
                .background(kind == value ? Style.green : .white, in: Capsule())
        }.accessibilityAddTraits(kind == value ? .isSelected : [])
    }
}

private struct FileRow: View {
    let file: CourseFile
    let opening: Bool
    let onOpen: () -> Void
    /// Nil for Students: the "…" menu only exists when the Teacher can manage the file.
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    let badge = Self.badge(file.fileType)
                    Text(badge.label).font(.caption.bold()).foregroundStyle(.white).frame(width: 52, height: 44).background(badge.color, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                        Text(file.uploadedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if opening { ProgressView() }
                }.contentShape(Rectangle())
            }.buttonStyle(PressableRow()).accessibilityHint("Opens a preview")
            if let onRename, let onDelete {
                Menu {
                    Button("Rename", systemImage: "pencil", action: onRename)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis").font(.headline).foregroundStyle(.secondary).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("More actions for \(file.title)").accessibilityIdentifier("fileMenu")
            }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
    private static func badge(_ type: String) -> (label: String, color: Color) {
        switch type {
        case "pdf": ("PDF", Color(red: 192 / 255, green: 57 / 255, blue: 43 / 255))
        case "docx": ("DOCX", Color(red: 43 / 255, green: 108 / 255, blue: 176 / 255))
        case "key": ("KEY", Color(red: 137 / 255, green: 120 / 255, blue: 180 / 255))
        default: ("PPT", Color(red: 191 / 255, green: 137 / 255, blue: 54 / 255))
        }
    }
}

/// Rows scale slightly while pressed so a tap feels acknowledged before the download finishes.
private struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct UploadSheet: View {
    let course: Course
    let file: PickedFile
    let backend: any Backend
    let onUploaded: (CourseFile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var form: UploadFileForm
    init(course: Course, file: PickedFile, kind: CourseFileKind, backend: any Backend, onUploaded: @escaping (CourseFile) -> Void) {
        self.course = course; self.file = file; self.backend = backend; self.onUploaded = onUploaded
        _form = State(initialValue: UploadFileForm(kind: kind, title: file.url.deletingPathExtension().lastPathComponent))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("Kind", selection: $form.kind) { Text("Presentation").tag(CourseFileKind.presentation); Text("Exercise").tag(CourseFileKind.exercise) }.pickerStyle(.segmented) }
                Section { TextField("Title", text: $form.title); Text(file.name).font(.footnote).foregroundStyle(.secondary) }
                if let error = form.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("uploadError") } }
                if form.isUploading { Section { HStack(spacing: 12) { ProgressView(); Text("Uploading…") } } }
            }
            .navigationTitle("Upload file").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(form.isUploading) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { Task { if let uploaded = await form.submit(courseID: course.id, fileName: file.name, size: file.size, load: file.data, using: backend) { onUploaded(uploaded) } } }.disabled(form.isUploading)
                }
            }
        }.interactiveDismissDisabled(form.isUploading)
    }
}

private struct RosterView: View {
    let course: Course
    let backend: any Backend
    @Environment(\.dismiss) private var dismiss
    @State private var students: [RosterStudent] = []
    @State private var selected: RosterStudent?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let error { ContentUnavailableView("Roster unavailable", systemImage: "person.2", description: Text(error)) }
                else if students.isEmpty { ContentUnavailableView("No students yet", systemImage: "person.2") }
                else { List(students) { student in HStack { VStack(alignment: .leading, spacing: 4) { Text(student.name).font(.headline); Text("Joined \(student.joinedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) } ; Spacer(); Button("Remove", role: .destructive) { selected = student }.buttonStyle(.borderless) } } }
            }
            .navigationTitle("Roster").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove \(selected?.name ?? "student")?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                Button("Remove Student", role: .destructive) { guard let selected else { return }; Task { do { try await backend.removeStudent(courseID: course.id, studentID: selected.studentID); students.removeAll { $0.id == selected.id }; self.selected = nil } catch { self.error = error.localizedDescription } } }
                Button("Cancel", role: .cancel) { selected = nil }
            } message: { Text("They will lose access to this course and its files.") }
            .task { do { students = try await backend.roster(courseID: course.id) } catch { self.error = error.localizedDescription } }
        }
    }
}

private struct RenameSheet: View {
    let form: RenameFileForm
    let backend: any Backend
    let onRenamed: (CourseFile) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var form = form
        NavigationStack {
            Form {
                Section { TextField("Title", text: $form.title).accessibilityIdentifier("renameTitle") }
                if let error = form.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("renameError") } }
            }
            .navigationTitle("Rename file").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if let renamed = await form.submit(using: backend) { onRenamed(renamed) } } }.disabled(form.isSaving)
                }
            }
        }.presentationDetents([.medium])
    }
}
