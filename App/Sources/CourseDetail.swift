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
    @State var kind: CourseFileKind = .presentation
    @State private var files: [CourseFile] = []
    @State private var copied = false
    @State private var importing = false
    @State private var picked: PickedFile?
    @State private var importError: String?
    @State private var opening: UUID?
    @State private var preview: PreviewItem?

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
                if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
                if visible.isEmpty { Text(kind == .presentation ? "No presentations yet." : "No exercises yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 20) }
                else { VStack(spacing: 10) { ForEach(visible) { file in FileRow(file: file, opening: opening == file.id) { open(file) } } } }
            }.padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading).background(Style.canvas)
        .task {
            files = (try? await backend.files(courseID: course.id)) ?? []
            #if DEBUG
            // Screenshot hook: `-debugOpenFile pdf|pptx` previews the first file of that type.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-debugOpenFile"), args.indices.contains(i + 1), let file = files.first(where: { $0.fileType == args[i + 1] }) { kind = file.kind; open(file) }
            #endif
        }
        .sheet(item: $preview) { FilePreview(item: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.pickerTypes) { result in
            switch result {
            case .success(let url): importError = nil; picked = PickedFile(url: url)
            case .failure: importError = "Could not open that file."
            }
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
    let action: () -> Void
    var body: some View {
        Button(action: action) { row }.buttonStyle(PressableRow())
            .accessibilityHint("Opens a preview")
    }
    private var row: some View {
        HStack(spacing: 14) {
            let badge = Self.badge(file.fileType)
            Text(badge.label).font(.caption.bold()).foregroundStyle(.white).frame(width: 52, height: 44).background(badge.color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.title).font(.headline).lineLimit(2)
                Text(file.uploadedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if opening { ProgressView() }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
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
