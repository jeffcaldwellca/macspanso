// macspanso/Views/FileTreeView.swift
import SwiftUI

struct FileTreeView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedMatchID: UUID?

    var body: some View {
        List(store.matchFiles, id: \.id) { file in
            Section {
                ForEach(file.matches, id: \.id) { match in
                    MatchRowView(match: match)
                        .tag(match.id)
                        .onTapGesture { selectedMatchID = match.id }
                        .foregroundStyle(file.isPackage ? .secondary : .primary)
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
