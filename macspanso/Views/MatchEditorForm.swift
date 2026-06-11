// macspanso/Views/MatchEditorForm.swift
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var destinationURL: URL? = nil
    @State private var regexTestInput: String = ""

    private static let lastDestinationKey = "macspanso.lastDestinationFilePath"

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
                    if isNew { destinationSection }
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

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Save to", systemImage: "folder")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                Picker("", selection: destinationBinding) {
                    ForEach(store.writableFiles, id: \.url) { file in
                        Text(file.displayName).tag(Optional(file.url))
                    }
                    if store.writableFiles.isEmpty {
                        Text("base.yml").tag(Optional(defaultDestination))
                    }
                }
                .labelsHidden()

                Button {
                    promptForNewFile()
                } label: {
                    Label("New File…", systemImage: "doc.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear { hydrateDestination() }
    }

    private var defaultDestination: URL {
        store.matchDirectory.appendingPathComponent("base.yml")
    }

    private var destinationBinding: Binding<URL?> {
        Binding(
            get: { destinationURL ?? defaultDestination },
            set: { destinationURL = $0 }
        )
    }

    private func hydrateDestination() {
        guard destinationURL == nil else { return }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: Self.lastDestinationKey) {
            let candidate = URL(fileURLWithPath: path)
            if store.writableFiles.contains(where: { $0.url == candidate }) {
                destinationURL = candidate
                return
            }
        }
        if let base = store.writableFiles.first(where: { $0.displayName == "base.yml" }) {
            destinationURL = base.url
        } else {
            destinationURL = store.writableFiles.first?.url ?? defaultDestination
        }
    }

    private func promptForNewFile() {
        let panel = NSSavePanel()
        panel.directoryURL = store.matchDirectory
        panel.allowedContentTypes = [.yaml]
        panel.nameFieldStringValue = "untitled.yml"
        panel.message = "Create a new espanso match file"
        if panel.runModal() == .OK, let url = panel.url {
            // Coerce the extension; espanso requires .yml.
            let coerced = url.pathExtension == "yml" ? url : url.deletingPathExtension().appendingPathExtension("yml")
            destinationURL = coerced
        }
    }

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
                        savedTriggers = TriggerModeTransition.toRegex(&draft)
                        triggerEntryIDs = []
                    } else {
                        TriggerModeTransition.toText(&draft, restoring: savedTriggers)
                        triggerEntryIDs = (draft.triggers ?? []).map { _ in UUID() }
                        savedTriggers = nil
                    }
                }
            }

            // Alternate triggers (multi-trigger). Up/down arrows reorder; the first
            // trigger is the "primary" and renders in the main field above.
            if !useRegex {
                let triggerCount = draft.triggers?.count ?? 0
                ForEach(Array(zip(triggerEntryIDs, (draft.triggers ?? []).indices)), id: \.0) { _, i in
                    HStack(spacing: 4) {
                        Button {
                            moveTrigger(from: i, to: i - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(i == 0)
                        .help("Move up")

                        Button {
                            moveTrigger(from: i, to: i + 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(i == triggerCount - 1)
                        .help("Move down")

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

            if useRegex { regexTesterSection }
        }
    }

    private var regexTesterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Test input")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextField("Type something the pattern should match…", text: $regexTestInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            regexTestResult
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var regexTestResult: some View {
        let pattern = draft.regex ?? ""
        if pattern.isEmpty || regexTestInput.isEmpty {
            EmptyView()
        } else if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(regexTestInput.startIndex..., in: regexTestInput)
            let matches = regex.matches(in: regexTestInput, range: range)
            if matches.isEmpty {
                Label("No match", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("\(matches.count) match\(matches.count == 1 ? "" : "es")",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                ForEach(Array(matches.enumerated()), id: \.offset) { idx, m in
                    if let r = Range(m.range, in: regexTestInput) {
                        Text("[\(idx)] \(String(regexTestInput[r]))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Invalid regex pattern", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
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
                validationLabel(for: .emptyFormTemplate, message: "Form template is required")
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

            previewSection
        }
    }

    private var previewSection: some View {
        let preview = MatchExpander.preview(of: draft)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "eye")
                Text("Preview")
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

            Text(preview.isEmpty ? "—" : preview)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(preview.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .textSelection(.enabled)

            if previewHasUnexecutedVars {
                Label("Shell, script, and random values are placeholders in preview.",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var previewHasUnexecutedVars: Bool {
        (draft.vars ?? []).contains { v in
            v.type == .shell || v.type == .script || v.type == .random
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

    private func moveTrigger(from source: Int, to destination: Int) {
        guard var triggers = draft.triggers else { return }
        guard triggers.indices.contains(source), triggers.indices.contains(destination)
        else { return }
        triggers.swapAt(source, destination)
        draft.triggers = triggers
        triggerEntryIDs.swapAt(source, destination)
    }

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
            existingMatches: store.allMatches.filter { $0.id != draft.id },
            globalVarNames: Set(store.globalVarNames)
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
        var matchToSave = draft
        // Silently strip empty strings from dropdown option lists before writing to disk.
        if let fields = matchToSave.formFields, !fields.isEmpty {
            var cleaned: [String: FormField] = [:]
            for (name, field) in fields {
                guard field.isDropdown else { cleaned[name] = field; continue }
                var f = field
                f.values = (f.values ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if !(f.values?.isEmpty ?? true) { cleaned[name] = f }
            }
            matchToSave.formFields = cleaned.isEmpty ? nil : cleaned
        }
        do {
            if isNew {
                let target = destinationURL ?? defaultDestination
                try store.add(matchToSave, to: target)
                UserDefaults.standard.set(target.path, forKey: Self.lastDestinationKey)
            } else {
                try store.update(matchToSave)
            }
            saveError = nil
            onSave(matchToSave)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
