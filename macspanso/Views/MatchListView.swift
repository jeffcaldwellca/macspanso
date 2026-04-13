// macspanso/Views/MatchListView.swift
import SwiftUI

struct MatchListView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedMatchID: UUID?
    @Binding var showFileTree: Bool
    @Binding var searchText: String
    @State private var deleteError: String?

    private var filteredMatches: [EspansoMatch] {
        guard !searchText.isEmpty else { return store.allMatches }
        return store.allMatches.filter {
            $0.primaryTrigger.localizedCaseInsensitiveContains(searchText) ||
            $0.replacementPreview.localizedCaseInsensitiveContains(searchText) ||
            ($0.label ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search matches…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List or tree
            if showFileTree {
                FileTreeView(store: store, selectedMatchID: $selectedMatchID)
            } else {
                flatList
            }

            Divider()

            // Toolbar
            HStack(spacing: 4) {
                Button {
                    selectedMatchID = nil
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New match")

                Button {
                    guard let id = selectedMatchID else { return }
                    do {
                        try store.delete(matchID: id)
                        selectedMatchID = nil
                    } catch {
                        deleteError = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .help("Delete selected match")
                .disabled(selectedMatchID == nil)
                .alert("Delete Failed", isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )) {
                    Button("OK") { deleteError = nil }
                } message: {
                    Text(deleteError ?? "")
                }

                Spacer()

                Button {
                    withAnimation { showFileTree.toggle() }
                } label: {
                    Label("Files", systemImage: showFileTree ? "folder.fill" : "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(showFileTree ? "Show flat list" : "Show file tree")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var flatList: some View {
        List(filteredMatches, id: \.id, selection: $selectedMatchID) { match in
            MatchRowView(match: match)
        }
        .listStyle(.sidebar)
    }
}

struct MatchRowView: View {
    let match: EspansoMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.primaryTrigger)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Text(match.replacementPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
