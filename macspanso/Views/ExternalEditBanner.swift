// macspanso/Views/ExternalEditBanner.swift
import SwiftUI

struct ExternalEditBanner: View {
    let filename: String
    let onReload: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.accentColor)
            Text("\(filename) changed externally")
                .font(.callout)
            Spacer()
            Button("Reload", action: onReload)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Keep Mine", action: onKeep)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
