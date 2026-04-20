// macspanso/Views/FileTreeView.swift
import SwiftUI

struct FileTreeView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedMatchID: UUID?

    var body: some View {
        // Use List(selection:) so rows highlight correctly on macOS.
        // Package matches get no .tag, preventing them from being selected
        // (allMatches excludes package files, so the editor panel can't display them).
        List(store.matchFiles, id: \.id, selection: $selectedMatchID) { file in
            Section {
                ForEach(file.matches, id: \.id) { match in
                    MatchRowView(match: match)
                        .foregroundStyle(file.isPackage ? .secondary : .primary)
                        // Only non-package matches get a selection tag
                        .ifLet(!file.isPackage) { $0.tag(match.id) }
                }
                if file.matches.isEmpty && file.parseError == nil {
                    Text("No matches")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                if let error = file.parseError {
                    Label("Parse error: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                HStack {
                    if file.isPackage {
                        Image(systemName: "lock")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    Text(file.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if file.parseError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                    }
                }
                .contextMenu {
                    Button("Open in Editor") {
                        NSWorkspace.shared.open(file.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - View helper

private extension View {
    /// Conditionally applies a modifier. Used to apply .tag only when the condition is true.
    @ViewBuilder
    func ifLet(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
