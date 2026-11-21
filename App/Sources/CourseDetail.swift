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
                else { VStack(spacing: 10) { ForEach(visible) { FileRow(file: $0) } } }
            }.padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading).background(Style.canvas)
        .task { files = (try? await backend.files(courseID: course.id)) ?? [] }
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

    private func chip(_ title: String, _ value: CourseFileKind) -> some View {
        Button { kind = value } label: {
            Text(title).font(.subheadline.bold()).foregroundStyle(kind == value ? .white : Style.green).padding(.horizontal, 16).padding(.vertical, 10)
                .background(kind == value ? Style.green : .white, in: Capsule())
        }.accessibilityAddTraits(kind == value ? .isSelected : [])
    }
}

private struct FileRow: View {
    let file: CourseFile
    var body: some View {
        HStack(spacing: 14) {
            let badge = Self.badge(file.fileType)
            Text(badge.label).font(.caption.bold()).foregroundStyle(.white).frame(width: 52, height: 44).background(badge.color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.title).font(.headline).lineLimit(2)
                Text(file.uploadedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.05), radius: 8, y: 3)
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
