// macspanso/Views/MatchListView.swift
import SwiftUI

enum MatchListSort: String, CaseIterable, Identifiable {
    case fileOrder, triggerAsc, triggerDesc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fileOrder:    return "File order"
        case .triggerAsc:   return "Trigger A → Z"
        case .triggerDesc:  return "Trigger Z → A"
        }
    }
}

enum MatchListFilter: String, CaseIterable, Identifiable {
    case all, text, form, regex, hasVars
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return "All"
        case .text:     return "Text"
        case .form:     return "Form"
        case .regex:    return "Regex"
        case .hasVars:  return "Vars"
        }
    }
    func matches(_ m: EspansoMatch) -> Bool {
        switch self {
        case .all:     return true
        case .text:    return m.regex == nil && m.form == nil
        case .form:    return m.form != nil
        case .regex:   return m.regex != nil
        case .hasVars: return !(m.vars ?? []).isEmpty
        }
    }
}

struct MatchListView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var selectedMatchIDs: Set<UUID>
    @Binding var isCreatingNew: Bool
    @Binding var showFileTree: Bool
    @Binding var searchText: String
    @State private var deleteError: String?
    @State private var duplicateError: String?
    @AppStorage("macspanso.listSort") private var sortRaw: String = MatchListSort.fileOrder.rawValue
    @State private var filter: MatchListFilter = .all

    private var singleSelectedMatchID: UUID? {
        selectedMatchIDs.count == 1 ? selectedMatchIDs.first : nil
    }

    private var sort: MatchListSort {
        MatchListSort(rawValue: sortRaw) ?? .fileOrder
    }

    private var filteredMatches: [EspansoMatch] {
        var results = store.allMatches.filter(filter.matches)
        if !searchText.isEmpty {
            results = results.filter {
                $0.primaryTrigger.localizedCaseInsensitiveContains(searchText) ||
                $0.replacementPreview.localizedCaseInsensitiveContains(searchText) ||
                ($0.label ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sort {
        case .fileOrder:
            return results
        case .triggerAsc:
            return results.sorted { $0.primaryTrigger.localizedCompare($1.primaryTrigger) == .orderedAscending }
        case .triggerDesc:
            return results.sorted { $0.primaryTrigger.localizedCompare($1.primaryTrigger) == .orderedDescending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !showFileTree {
                filterBar
            }
            Divider()

            if showFileTree {
                FileTreeView(store: store, selectedMatchIDs: $selectedMatchIDs)
            } else {
                flatList
            }

            Divider()
            toolbar
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Pieces

    private var searchBar: some View {
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
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MatchListFilter.allCases) { f in
                    FilterChip(
                        label: f.label,
                        selected: filter == f
                    ) {
                        filter = f
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button {
                selectedMatchIDs = []
                isCreatingNew = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("New match")

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .help(selectedMatchIDs.count > 1 ? "Delete \(selectedMatchIDs.count) matches" : "Delete selected match")
            .disabled(selectedMatchIDs.isEmpty)
            .alert("Delete Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .alert("Duplicate Failed", isPresented: Binding(
                get: { duplicateError != nil },
                set: { if !$0 { duplicateError = nil } }
            )) {
                Button("OK") { duplicateError = nil }
            } message: {
                Text(duplicateError ?? "")
            }

            Menu {
                ForEach(MatchListSort.allCases) { option in
                    Button {
                        sortRaw = option.rawValue
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort matches")

            Spacer()

            Text(countLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

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

    private var countLabel: String {
        let total = store.allMatches.count
        let shown = filteredMatches.count
        if shown == total {
            return "\(total) match\(total == 1 ? "" : "es")"
        } else {
            return "\(shown) of \(total)"
        }
    }

    private var flatList: some View {
        List(filteredMatches, id: \.id, selection: $selectedMatchIDs) { match in
            MatchRowView(match: match)
                .contextMenu { rowContextMenu(for: match.id) }
        }
        .listStyle(.sidebar)
        .background(
            // Hidden button so ⌘D works even when the row context menu is closed.
            Button("Duplicate") { duplicateSelected() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(singleSelectedMatchID == nil)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private func rowContextMenu(for matchID: UUID) -> some View {
        Button("Duplicate") {
            selectedMatchIDs = [matchID]
            duplicateSelected()
        }
        .keyboardShortcut("d", modifiers: .command)

        moveToMenu(for: matchID)

        Button("Delete", role: .destructive) {
            do {
                try store.delete(matchID: matchID)
                selectedMatchIDs.remove(matchID)
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func moveToMenu(for matchID: UUID) -> some View {
        let currentFile = store.file(containing: matchID)
        let candidates = store.writableFiles.filter { $0.url != currentFile?.url }
        if !candidates.isEmpty {
            Menu("Move to") {
                ForEach(candidates, id: \.url) { file in
                    Button(file.displayName) {
                        do {
                            try store.move(matchID: matchID, to: file.url)
                        } catch {
                            duplicateError = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func duplicateSelected() {
        guard let id = singleSelectedMatchID else { return }
        do {
            let copy = try store.duplicate(matchID: id)
            selectedMatchIDs = [copy.id]
        } catch {
            duplicateError = error.localizedDescription
        }
    }

    private func deleteSelected() {
        let ids = selectedMatchIDs
        var firstError: String?
        for id in ids {
            do { try store.delete(matchID: id) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        selectedMatchIDs = []
        if let err = firstError { deleteError = err }
    }
}

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.3),
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

struct MatchRowView: View {
    let match: EspansoMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(match.primaryTrigger)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if match.form != nil {
                    Text("form")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if match.regex != nil {
                    Text("regex")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            Text(match.replacementPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
