// macspanso/Views/LogViewer.swift
import SwiftUI

/// Live tail of espanso's log via `espanso log`. Refreshes every few seconds while
/// open and auto-scrolls to the newest line whenever the line count changes. Errors
/// and warnings are highlighted so they're spottable in long output.
struct LogViewer: View {
    let processManager: EspansoProcessManager

    @State private var lines: [String] = []
    @State private var isLoading = true
    @State private var refreshTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private let maxLines = 400
    private let refreshSeconds: TimeInterval = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Espanso Log")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if isLoading && lines.isEmpty {
                ProgressView("Reading log…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No log entries")
                        .foregroundStyle(.secondary)
                    Text("Espanso may not be running yet, or `espanso log` returned nothing.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 1)
                                    .id(idx)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: lines.count) { _ in
                        if !lines.isEmpty {
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(lines.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 720, height: 480)
        .task {
            await load()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") {
            return .red
        }
        if lower.contains("warn") {
            return .orange
        }
        return .primary
    }

    private func load() async {
        let output = await processManager.run("log")
        let trimmed = output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        await MainActor.run {
            // Keep at most maxLines so the scroll view doesn't drown in history.
            self.lines = Array(trimmed.suffix(maxLines))
            self.isLoading = false
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await load()
            }
        }
    }
}
