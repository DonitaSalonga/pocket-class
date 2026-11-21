import SwiftUI

enum Initials {
    /// First letters of the first two words, uppercase ("Pool studentA" is "PS").
    static func of(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

enum LoadState { case loading, loaded, failed }

/// Centered message for empty and error states; `retry` adds a Try again button.
struct StatusView: View {
    let icon: String
    let title: String
    var detail: String?
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Style.green.opacity(0.6))
            Text(title).font(.headline)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let retry { Button("Try again", action: retry).font(.subheadline.bold()).foregroundStyle(Style.green).padding(.horizontal, 18).padding(.vertical, 10).background(.white, in: Capsule()).padding(.top, 6) }
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

struct LoadingView: View {
    let label: String
    var body: some View {
        VStack(spacing: 12) { ProgressView().tint(Style.green); Text(label).font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 30).accessibilityElement(children: .combine)
    }
}

struct OfflineBanner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "wifi.slash").font(.footnote.bold()).foregroundStyle(Style.green).padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).background(Style.green.opacity(0.1), in: Capsule())
    }
}
