// macspanso/Views/MatchEditorForm.swift
import SwiftUI

struct MatchEditorForm: View {
    let initialMatch: EspansoMatch
    let sourceFile: MatchFile?
    let store: EspansoConfigStore
    let onSave: (EspansoMatch) -> Void
    let onCancel: () -> Void

    @State private var draft: EspansoMatch
    @State private var useRegex: Bool
    @State private var isFormMatch: Bool
    @State private var validationErrors: [ValidationError] = []
    @State private var saveError: String? = nil
    @State private var showUnsavedAlert: Bool = false
    @State private var triggerEntryIDs: [UUID] = []
    @State private var savedTriggers: [String]? = nil

    init(
        match: EspansoMatch,
        sourceFile: MatchFile?,
        store: EspansoConfigStore,
        onSave: @escaping (EspansoMatch) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialMatch = match
        self.sourceFile = sourceFile
        self.store = store
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: match)
        _useRegex = State(initialValue: match.regex != nil)
        _isFormMatch = State(initialValue: match.form != nil)
        _triggerEntryIDs = State(initialValue: (match.triggers ?? []).map { _ in UUID() })
    }

    private var isNew: Bool { sourceFile == nil }
    private var isDirty: Bool { draft != initialMatch }
    private var canSave: Bool { validationErrors.isEmpty && isDirty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New Match" : "Edit Match")
                        .font(.headline)
                    if let file = sourceFile {
                        Text(file.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(.background)

            Divider()

            // Form body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    triggerSection
                    replacementSection
                    if !isFormMatch {
                        VariableBuilderView(vars: $draft.vars)
                    }
                    optionsSection
                }
                .padding(20)
            }

            // Error summary
            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            // Save bar
            HStack {
                Spacer()
                Button("Cancel") {
                    if isDirty {
                        showUnsavedAlert = true
                    } else {
                        onCancel()
                    }
                }
                .buttonStyle(.bordered)

                Button("Save Match") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .onChange(of: draft) { _ in revalidate() }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") { save() }
            Button("Discard", role: .destructive) { onCancel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save changes to \(draft.primaryTrigger)?")
        }
    }

    // MARK: - Sections

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Trigger", systemImage: "keyboard")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                TextField(useRegex ? "Regex pattern…" : "e.g. ::hello", text: triggerBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Picker("", selection: $useRegex) {
                    Text("Text").tag(false)
                    Text("Regex").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: useRegex) { regex in
                    if regex {
                        savedTriggers = draft.triggers  // preserve for restore
                        draft.regex = draft.trigger ?? draft.triggers?.first ?? ""
                        draft.trigger = nil
                        draft.triggers = nil
                        triggerEntryIDs = []
                    } else {
                        draft.trigger = draft.regex ?? ""
                        draft.regex = nil
                        if let saved = savedTriggers {
                            draft.triggers = saved
                            triggerEntryIDs = saved.map { _ in UUID() }
                            savedTriggers = nil
                        }
                    }
                }
            }

            // Alternate triggers (multi-trigger)
            if !useRegex {
                ForEach(Array(zip(triggerEntryIDs, (draft.triggers ?? []).indices)), id: \.0) { _, i in
                    HStack {
                        TextField("Alternate trigger…", text: Binding(
                            get: { draft.triggers?[i] ?? "" },
                            set: { if i < (draft.triggers?.count ?? 0) { draft.triggers?[i] = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            if i < (draft.triggers?.count ?? 0) {
                                draft.triggers?.remove(at: i)
                                triggerEntryIDs.remove(at: i)
                                if draft.triggers?.isEmpty == true { draft.triggers = nil }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if draft.triggers == nil {
                        // Promote single trigger to multi-trigger
                        var ts = draft.trigger.map { [$0] } ?? []
                        ts.append("")
                        draft.triggers = ts
                        draft.trigger = nil
                        triggerEntryIDs = ts.map { _ in UUID() }
                    } else {
                        draft.triggers?.append("")
                        triggerEntryIDs.append(UUID())
                    }
                } label: {
                    Label("Add alternate trigger", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            validationLabel(for: .emptyTrigger, message: "Trigger is required")
            validationLabel(for: .duplicateTrigger, message: "This trigger already exists")
        }
    }

    private var replacementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Replacement", systemImage: "text.alignleft")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Picker("", selection: $isFormMatch) {
                    Text("Text").tag(false)
                    Text("Form").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: isFormMatch) { wantsForm in
                    if wantsForm {
                        draft.form = draft.replace ?? ""
                        draft.replace = nil
                    } else {
                        draft.replace = draft.form ?? ""
                        draft.form = nil
                        draft.formFields = nil
                    }
                }
            }

            if isFormMatch {
                FormFieldsSection(
                    formTemplate: Binding(
                        get: { draft.form ?? "" },
                        set: { draft.form = $0.isEmpty ? nil : $0 }
                    ),
                    formFields: Binding(
                        get: { draft.formFields ?? [:] },
                        set: { draft.formFields = $0.isEmpty ? nil : $0 }
                    )
                )
            } else {
                TextEditor(text: Binding(
                    get: { draft.replace ?? "" },
                    set: { draft.replace = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))

                ForEach(unresolvedVarErrors, id: \.self) { varName in
                    Label("{{\(varName)}} is not declared as a variable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("Word boundary", isOn: Binding(
                get: { draft.word ?? false },
                set: { draft.word = $0 ? true : nil }
            ))
            Toggle("Propagate case", isOn: Binding(
                get: { draft.propagateCase ?? false },
                set: { draft.propagateCase = $0 ? true : nil }
            ))
        }
    }

    // MARK: - Helpers

    private var triggerBinding: Binding<String> {
        Binding(
            get: { draft.trigger ?? draft.regex ?? draft.triggers?.first ?? "" },
            set: { v in
                if useRegex { draft.regex = v }
                else if draft.triggers?.isEmpty == false { draft.triggers?[0] = v }
                else { draft.trigger = v }
            }
        )
    }

    private var unresolvedVarErrors: [String] {
        validationErrors.compactMap {
            if case .unresolvedVarReference(let name) = $0 { return name }
            return nil
        }
    }

    private func revalidate() {
        var errors = MatchValidator.validate(
            draft,
            existingMatches: store.allMatches.filter { $0.id != draft.id }
        )
        // In form mode, {{name}} placeholders refer to form fields, not vars — suppress false positives.
        if isFormMatch {
            errors = errors.filter { if case .unresolvedVarReference = $0 { return false }; return true }
        }
        validationErrors = errors
    }

    @ViewBuilder
    private func validationLabel(for error: ValidationError, message: String) -> some View {
        if validationErrors.contains(error) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func save() {
        revalidate()
        guard validationErrors.isEmpty else { return }
        do {
            if isNew {
                try store.add(draft)
            } else {
                try store.update(draft)
            }
            saveError = nil
            onSave(draft)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
