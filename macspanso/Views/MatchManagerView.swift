// macspanso/Views/MatchManagerView.swift
import SwiftUI

struct MatchManagerView: View {
    @ObservedObject var store: EspansoConfigStore
    // Passed through to child views in later tasks (toolbar state indicator).
    @ObservedObject var processManager: EspansoProcessManager

    @State private var selectedMatchID: UUID? = nil
    @State private var isCreatingNew: Bool = false
    @State private var editorGeneration: Int = 0
    @State private var showFileTree: Bool = false
    @State private var searchText: String = ""

    var body: some View {
        // animation() on the ZStack drives both entry and exit transitions for
        // ExternalEditBanner; placing it on the banner itself only animates entry.
        ZStack(alignment: .top) {
            HSplitView {
                MatchListView(
                    store: store,
                    selectedMatchID: $selectedMatchID,
                    isCreatingNew: $isCreatingNew,
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
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.externallyChangedURL != nil)
        .onReceive(NotificationCenter.default.publisher(for: .focusNewMatch)) { _ in
            selectedMatchID = nil
            isCreatingNew = true
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
                onSave: { selectedMatchID = $0.id; editorGeneration += 1 },
                onCancel: {}
            )
            // Increment editorGeneration on save so SwiftUI re-inits the form,
            // resetting initialMatch and clearing the dirty flag.
            .id("\(id)-\(editorGeneration)")
        } else if isCreatingNew {
            MatchEditorForm(
                match: EspansoMatch(),
                sourceFile: nil,
                store: store,
                onSave: { selectedMatchID = $0.id; isCreatingNew = false },
                onCancel: { isCreatingNew = false }
            )
            .id("new")  // force re-init when triggered from menu bar
        } else {
            // Empty state — nothing selected
            VStack {
                Spacer()
                Text("Select a match or press + to create one")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
}
