// macspanso/Views/QuickSwitcherView.swift
import AppKit
import SwiftUI

/// Spotlight-style fuzzy finder over all matches. Opens with ⌘P; type to filter,
/// arrow keys to navigate, Enter to select, Esc to dismiss. Searches against
/// trigger, label, and replacement preview.
struct QuickSwitcherView: View {
    @ObservedObject var store: EspansoConfigStore
    @Binding var isPresented: Bool
    let onSelect: (UUID) -> Void

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool

    private var filtered: [EspansoMatch] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(store.allMatches.prefix(50)) }
        return store.allMatches.filter { m in
            m.primaryTrigger.localizedCaseInsensitiveContains(q) ||
            (m.label ?? "").localizedCaseInsensitiveContains(q) ||
            m.replacementPreview.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to match…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit { selectHighlighted() }
                    .onChange(of: query) { _ in highlightedIndex = 0 }
            }
            .padding(14)

            Divider()

            if filtered.isEmpty {
                Text(query.isEmpty ? "No matches yet" : "No matches found")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, match in
                                QuickSwitcherRow(
                                    match: match,
                                    isHighlighted: index == highlightedIndex
                                )
                                .id(match.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectMatch(match) }
                                .onHover { hovering in
                                    if hovering { highlightedIndex = index }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: highlightedIndex) { idx in
                        guard filtered.indices.contains(idx) else { return }
                        withAnimation(.linear(duration: 0.05)) {
                            proxy.scrollTo(filtered[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 520)
        .onAppear {
            fieldFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func moveHighlight(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let count = filtered.count
        highlightedIndex = ((highlightedIndex + delta) % count + count) % count
    }

    private func selectHighlighted() {
        guard filtered.indices.contains(highlightedIndex) else { return }
        selectMatch(filtered[highlightedIndex])
    }

    private func selectMatch(_ match: EspansoMatch) {
        onSelect(match.id)
        isPresented = false
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: moveHighlight(by: -1); return nil    // up
            case 125: moveHighlight(by:  1); return nil    // down
            case 53:  isPresented = false;   return nil    // escape
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
    }
}

private struct QuickSwitcherRow: View {
    let match: EspansoMatch
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(match.primaryTrigger)
                        .font(.system(.body, design: .monospaced))
                    if let label = match.label, !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if match.form != nil {
                        kindBadge("form", color: .accentColor)
                    } else if match.regex != nil {
                        kindBadge("regex", color: .purple)
                    }
                }
                Text(match.replacementPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func kindBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
