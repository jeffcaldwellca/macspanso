// macspanso/Views/ViewStubs.swift
// Stubs for views that are implemented in later tasks.
// Tasks 9, 10, 12, 13 replace these.
import SwiftUI

struct ExternalEditBanner: View {
    let filename: String
    let onReload: () -> Void
    let onKeep: () -> Void
    var body: some View { EmptyView() }
}

struct MatchEditorForm: View {
    let match: EspansoMatch
    let sourceFile: MatchFile?
    @ObservedObject var store: EspansoConfigStore
    let onSave: (EspansoMatch) -> Void
    let onCancel: () -> Void
    var body: some View { Text("Editor coming soon") }
}
