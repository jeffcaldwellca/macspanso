// macspanso/Views/FormFieldsSection.swift
import SwiftUI

/// The replacement section shown when a match is in "Form" mode.
/// Combines the template editor with per-placeholder field configuration.
struct FormFieldsSection: View {
    @Binding var formTemplate: String
    @Binding var formFields: [String: FormField]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            templateEditor
            if placeholderNames.isEmpty {
                Text("Form fields will appear here once you add a [[placeholder]] to the template above.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                fieldCards
            }
        }
    }

    // MARK: - Template editor

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Template")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $formTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
                    .onChange(of: formTemplate) { _ in pruneOrphanedFields() }
                if formTemplate.isEmpty {
                    Text("e.g. Hello [[name]], your email is [[email]]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            Text("Type [[placeholder]] anywhere in the template to create a fill-in field. Each placeholder becomes a configurable field below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Field cards

    private var fieldCards: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Form Fields")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(placeholderNames, id: \.self) { name in
                FormFieldCard(
                    name: name,
                    field: Binding(
                        get: { formFields[name] ?? .textDefault },
                        set: { newValue in
                            if newValue == .textDefault {
                                formFields.removeValue(forKey: name)
                            } else {
                                formFields[name] = newValue
                            }
                        }
                    )
                )
            }
        }
    }

    // MARK: - Helpers

    /// Placeholder names found in the template, in appearance order, deduplicated.
    /// Espanso form syntax uses [[name]], not {{name}} (which is for variable references).
    private var placeholderNames: [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[([a-zA-Z_][a-zA-Z0-9_]*)\]\]"#
        ) else { return [] }
        let ns = formTemplate as NSString
        let full = NSRange(location: 0, length: ns.length)
        var seen = Set<String>()
        return regex.matches(in: formTemplate, range: full).compactMap { m -> String? in
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { return nil }
            let name = ns.substring(with: r)
            return seen.insert(name).inserted ? name : nil
        }
    }

    /// Drop formFields entries for placeholders removed from the template.
    private func pruneOrphanedFields() {
        let active = Set(placeholderNames)
        for key in Array(formFields.keys) where !active.contains(key) {
            formFields.removeValue(forKey: key)
        }
    }
}

// MARK: - FormFieldCard

struct FormFieldCard: View {
    let name: String
    @Binding var field: FormField
    /// Stable row identities for dropdown options — see VariableBuilderView.
    @State private var optionIDs: [UUID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("[[\(name)]]")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                Picker("", selection: Binding(
                    get: { field.isDropdown },
                    set: { switchToDropdown($0) }
                )) {
                    Text("Text").tag(false)
                    Text("Dropdown").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if field.isDropdown {
                dropdownConfig
            } else {
                textConfig
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    // MARK: - Text config

    private var textConfig: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("optional", text: Binding(
                    get: { field.default ?? "" },
                    set: { field.default = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
            Toggle("Multiline", isOn: Binding(
                get: { field.multiline ?? false },
                set: { field.multiline = $0 ? true : nil }
            ))
            .font(.callout)
        }
    }

    // MARK: - Dropdown config

    private var dropdownConfig: some View {
        VStack(alignment: .leading, spacing: 4) {
            let values = field.values ?? []
            ForEach(Array(zip(optionIDs, values.indices)), id: \.0) { _, i in
                HStack {
                    TextField("option", text: Binding(
                        get: { i < (field.values?.count ?? 0) ? field.values![i] : "" },
                        set: { v in
                            if field.values == nil { field.values = [] }
                            if i < field.values!.count { field.values![i] = v }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        guard (field.values?.count ?? 0) > 1 else { return }
                        field.values?.remove(at: i)
                        optionIDs.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled((field.values?.count ?? 0) <= 1)
                }
            }

            Button {
                if field.values == nil { field.values = [""] }
                field.values?.append("")
                optionIDs.append(UUID())
            } label: {
                Label("Add option", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .onAppear { syncOptionIDs() }
        .onChange(of: (field.values ?? []).count) { _ in syncOptionIDs() }
    }

    private func syncOptionIDs() {
        let count = (field.values ?? []).count
        if optionIDs.count != count {
            optionIDs = (0..<count).map { _ in UUID() }
        }
    }

    // MARK: - Mode switching

    private func switchToDropdown(_ dropdown: Bool) {
        if dropdown {
            field = .dropdown(field.values ?? [""])
        } else {
            field = FormField(default: field.default, multiline: nil)
        }
    }
}
