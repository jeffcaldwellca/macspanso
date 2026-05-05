// macspanso/Views/FileTreeView.swift
import SwiftUI

struct FileTreeView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedMatchIDs: Set<UUID>
    @State private var actionError: String?

    private var conflictingFileURLs: Set<URL> {
        Set(store.triggerConflicts().flatMap { $0.occurrences.map(\.fileURL) })
    }

    var body: some View {
        // Use List(selection:) so rows highlight correctly on macOS.
        // Package matches get no .tag, preventing them from being selected
        // (allMatches excludes package files, so the editor panel can't display them).
        List(store.matchFiles, id: \.id, selection: $selectedMatchIDs) { file in
            Section {
                ForEach(file.matches, id: \.id) { match in
                    MatchRowView(match: match)
                        .foregroundStyle(file.isPackage ? .secondary : .primary)
                        // Only non-package matches get a selection tag
                        .ifLet(!file.isPackage) { $0.tag(match.id) }
                        .contextMenu {
                            if !file.isPackage {
                                Button("Duplicate") { duplicate(matchID: match.id) }
                                moveToMenu(for: match.id, currentURL: file.url)
                                Button("Delete", role: .destructive) { delete(matchID: match.id) }
                            }
                        }
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
                    if conflictingFileURLs.contains(file.url) {
                        Image(systemName: "exclamationmark.2")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                            .help("Has triggers also defined in another file")
                    }
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
        .alert("Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func moveToMenu(for matchID: UUID, currentURL: URL) -> some View {
        let candidates = store.writableFiles.filter { $0.url != currentURL }
        if !candidates.isEmpty {
            Menu("Move to") {
                ForEach(candidates, id: \.url) { file in
                    Button(file.displayName) { move(matchID: matchID, to: file.url) }
                }
            }
        }
    }

    private func move(matchID: UUID, to url: URL) {
        do {
            try store.move(matchID: matchID, to: url)
            selectedMatchIDs = [matchID]
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func duplicate(matchID: UUID) {
        do {
            let copy = try store.duplicate(matchID: matchID)
            selectedMatchIDs = [copy.id]
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func delete(matchID: UUID) {
        do {
            try store.delete(matchID: matchID)
            selectedMatchIDs.remove(matchID)
        } catch {
            actionError = error.localizedDescription
        }
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
