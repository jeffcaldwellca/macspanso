// macspanso/Views/MatchManagerView.swift
import SwiftUI

private enum AppTab { case matches, about }

struct MatchManagerView: View {
    @ObservedObject var store: EspansoConfigStore
    @ObservedObject var processManager: EspansoProcessManager

    @State private var selectedTab: AppTab = .matches
    @State private var selectedMatchIDs: Set<UUID> = []
    @State private var isCreatingNew: Bool = false
    @State private var editorGeneration: Int = 0
    @State private var showFileTree: Bool = false
    @State private var searchText: String = ""
    @State private var showQuickSwitcher: Bool = false

    /// When the user has exactly one match selected, the editor shows it. Multi-selection
    /// shows a bulk-action panel instead — see `editorPanel`.
    private var singleSelectedMatchID: UUID? {
        selectedMatchIDs.count == 1 ? selectedMatchIDs.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNewMatch)) { _ in
            selectedTab = .matches
            selectedMatchIDs = []
            isCreatingNew = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAbout)) { _ in
            selectedTab = .about
        }
        .background(
            Button("Quick Switcher") { showQuickSwitcher = true }
                .keyboardShortcut("p", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showQuickSwitcher) {
            QuickSwitcherView(store: store, isPresented: $showQuickSwitcher) { id in
                selectedTab = .matches
                isCreatingNew = false
                selectedMatchIDs = [id]
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(label: "Matches", systemImage: "list.bullet", selected: selectedTab == .matches) {
                selectedTab = .matches
            }
            TabBarButton(label: "About", systemImage: "info.circle", selected: selectedTab == .about) {
                selectedTab = .about
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .matches:
            matchesContent
        case .about:
            AboutView(
                matchDirectory: store.matchDirectory,
                store: store,
                processManager: processManager
            )
        }
    }

    private var matchesContent: some View {
        // animation() on the ZStack drives both entry and exit transitions for
        // ExternalEditBanner; placing it on the banner itself only animates entry.
        ZStack(alignment: .top) {
            HSplitView {
                MatchListView(
                    store: store,
                    selectedMatchIDs: $selectedMatchIDs,
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
    }

    // MARK: - Editor panel

    @ViewBuilder
    private var editorPanel: some View {
        if selectedMatchIDs.count > 1 {
            BulkActionPanel(
                store: store,
                selectedIDs: $selectedMatchIDs
            )
        } else if let id = singleSelectedMatchID,
           let match = store.allMatches.first(where: { $0.id == id }),
           let file = store.file(containing: id) {
            MatchEditorForm(
                match: match,
                sourceFile: file,
                store: store,
                onSave: { selectedMatchIDs = [$0.id]; editorGeneration += 1 },
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
                onSave: { selectedMatchIDs = [$0.id]; isCreatingNew = false },
                onCancel: { isCreatingNew = false }
            )
            .id("new")  // force re-init when triggered from menu bar
        } else if store.allMatches.isEmpty {
            EmptyStateView(store: store) { newMatchID in
                selectedMatchIDs = [newMatchID]
            }
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

private struct BulkActionPanel: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedIDs: Set<UUID>
    @State private var actionError: String?

    private var selectedMatches: [EspansoMatch] {
        store.allMatches.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("\(selectedIDs.count) matches selected")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(store.writableFiles, id: \.url) { file in
                        Button(file.displayName) { moveAll(to: file.url) }
                    }
                } label: {
                    Label("Move to…", systemImage: "folder")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.writableFiles.isEmpty)

                Button(role: .destructive) {
                    deleteAll()
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button("Clear Selection") {
                    selectedIDs = []
                }
                .buttonStyle(.bordered)
            }

            if let err = actionError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Divider().padding(.horizontal, 60)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedMatches.prefix(50)) { match in
                        Text(match.primaryTrigger)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if selectedMatches.count > 50 {
                        Text("…and \(selectedMatches.count - 50) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func deleteAll() {
        let ids = selectedIDs
        var firstError: String?
        for id in ids {
            do { try store.delete(matchID: id) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        selectedIDs = []
        actionError = firstError
    }

    private func moveAll(to url: URL) {
        let ids = selectedIDs
        var firstError: String?
        for id in ids {
            do { try store.move(matchID: id, to: url) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        actionError = firstError
    }
}

private struct EmptyStateView: View {
    @ObservedObject var store: EspansoConfigStore
    let onCreated: (UUID) -> Void
    @State private var creationError: String?

    private struct Example: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbol: String
        let make: () -> EspansoMatch
    }

    private var examples: [Example] {
        [
            Example(
                title: "Email signature",
                subtitle: "::sig → Best,\\nJeff",
                symbol: "signature",
                make: { EspansoMatch(trigger: "::sig", replace: "Best,\nJeff") }
            ),
            Example(
                title: "Current date",
                subtitle: "::today → 2026-05-05",
                symbol: "calendar",
                make: {
                    EspansoMatch(
                        trigger: "::today",
                        replace: "{{d}}",
                        vars: [EspansoVar(name: "d", type: .date, params: ["format": .string("%Y-%m-%d")])]
                    )
                }
            ),
            Example(
                title: "Clipboard paste",
                subtitle: "::clip → pastes clipboard",
                symbol: "doc.on.clipboard",
                make: {
                    EspansoMatch(
                        trigger: "::clip",
                        replace: "{{c}}",
                        vars: [EspansoVar(name: "c", type: .clipboard)]
                    )
                }
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("No matches yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Pick a starter below, or press ⌘N to create your own.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                ForEach(examples) { example in
                    Button {
                        create(example)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: example.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Color.accentColor)
                            Text(example.title)
                                .font(.callout)
                                .fontWeight(.medium)
                            Text(example.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 140, height: 100)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let err = creationError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func create(_ example: Example) {
        let match = example.make()
        do {
            try store.add(match)
            onCreated(match.id)
        } catch {
            creationError = error.localizedDescription
        }
    }
}

// MARK: - TabBarButton

private struct TabBarButton: View {
    let label: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.primary.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
