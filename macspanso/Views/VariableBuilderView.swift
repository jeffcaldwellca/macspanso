// macspanso/Views/VariableBuilderView.swift
import SwiftUI

struct VariableBuilderView: View {
    @Binding var vars: [EspansoVar]?
    @State private var showTypePicker = false

    private var varList: [EspansoVar] { vars ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(varList.indices, id: \.self) { i in
                VarCardView(
                    variable: Binding(
                        get: { varList[i] },
                        set: { vars?[i] = $0 }
                    ),
                    onDelete: {
                        vars?.remove(at: i)
                        if vars?.isEmpty == true { vars = nil }
                    }
                )
            }

            Button {
                showTypePicker = true
            } label: {
                Label("Add variable", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .sheet(isPresented: $showTypePicker) {
                VarTypePickerSheet { type in
                    let newVar = EspansoVar(name: "var\((varList.count + 1))", type: type)
                    if vars == nil { vars = [] }
                    vars?.append(newVar)
                    showTypePicker = false
                }
            }
        }
    }
}

struct VarCardView: View {
    @Binding var variable: EspansoVar
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("name", text: $variable.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 160)

                Text(variable.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Type-specific param fields
            paramFields
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    @ViewBuilder
    private var paramFields: some View {
        switch variable.type {
        case .date:
            paramTextField(key: "format", placeholder: "%Y-%m-%d", label: "Format")
        case .shell:
            paramTextField(key: "cmd", placeholder: "date +%s", label: "Command")
        case .script:
            paramTextField(key: "args", placeholder: "python3 /path/to/script.py", label: "Args (space-separated)")
        case .random:
            randomChoicesField
        case .echo:
            paramTextField(key: "echo", placeholder: "static value", label: "Value")
        case .clipboard, .form, .match:
            EmptyView()
        }
    }

    private func paramTextField(key: String, placeholder: String, label: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: Binding(
                get: {
                    guard case .string(let v) = variable.params?[key] else { return "" }
                    return v
                },
                set: { v in
                    if variable.params == nil { variable.params = [:] }
                    variable.params?[key] = .string(v)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }
    }

    private var randomChoicesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choices (one per line)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: {
                    guard case .array(let arr) = variable.params?["choices"] else { return "" }
                    return arr.joined(separator: "\n")
                },
                set: { text in
                    let choices = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                    if variable.params == nil { variable.params = [:] }
                    variable.params?["choices"] = .array(choices)
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 60)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
        }
    }
}

struct VarTypePickerSheet: View {
    let onSelect: (VarType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let descriptions: [VarType: String] = [
        .date:      "Current date/time with a strftime format",
        .clipboard: "Current clipboard contents",
        .shell:     "Output of a shell command",
        .script:    "Output of a script file",
        .random:    "Random choice from a list",
        .form:      "Form field (for use inside a form match)",
        .echo:      "A static string value",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Variable")
                .font(.headline)
                .padding(16)

            Divider()

            ForEach(VarType.allCases, id: \.self) { type in
                Button {
                    onSelect(type)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(descriptions[type] ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .imageScale(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.05))
                Divider()
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .padding(16)
        }
        .frame(width: 320)
    }
}
