// macspanso/Views/MatchManagerView.swift
import SwiftUI

struct MatchManagerView: View {
    @ObservedObject var store: EspansoConfigStore
    @ObservedObject var processManager: EspansoProcessManager

    @State private var selectedMatchID: UUID? = nil
    @State private var showFileTree: Bool = false
    @State private var searchText: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            HSplitView {
                MatchListView(
                    store: store,
                    selectedMatchID: $selectedMatchID,
                    showFileTree: $showFileTree,
                    searchText: $searchText
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

                editorPanel
                    .frame(minWidth: 350)
            }

            // External edit banner — floats over the top
            if let changedURL = store.externallyChangedURL {
                ExternalEditBanner(
                    filename: changedURL.lastPathComponent,
                    onReload: { store.reloadFile(at: changedURL) },
                    onKeep: { store.dismissExternalChangeNotice() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: store.externallyChangedURL != nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNewMatch)) { _ in
            selectedMatchID = nil
        }
    }

    @ViewBuilder
    private var editorPanel: some View {
        if let id = selectedMatchID,
           let match = store.allMatches.first(where: { $0.id == id }),
           let file = store.file(containing: id) {
            MatchEditorForm(
                match: match,
                sourceFile: file,
                store: store,
                onSave: { selectedMatchID = $0.id },
                onCancel: {}
            )
        } else {
            // Empty state / new match form
            MatchEditorForm(
                match: EspansoMatch(),
                sourceFile: nil,
                store: store,
                onSave: { selectedMatchID = $0.id },
                onCancel: { selectedMatchID = nil }
            )
            .id("new")  // force re-init when triggered from menu bar
        }
    }
}
