// macspanso/Views/AboutView.swift
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    private var year: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                identity
                Divider().padding(.horizontal, 40)
                description
                Divider().padding(.horizontal, 40)
                licenseSection
                Divider().padding(.horizontal, 40)
                linksSection
            }
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private var identity: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("macspanso")
                .font(.system(size: 28, weight: .bold))
            HStack(spacing: 6) {
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                Text("(\(build))")
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
        }
        .padding(.bottom, 28)
    }

    private var description: some View {
        Text("A friendly macOS interface for the espanso text expander.\nCreate, edit, and organise your text shortcuts without touching YAML.")
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("License", systemImage: "doc.text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(mitLicense)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private var linksSection: some View {
        HStack(spacing: 16) {
            LinkButton(
                label: "GitHub",
                systemImage: "arrow.up.right.square",
                url: URL(string: "https://github.com/jeffcaldwellca/macspanso")!
            )
            LinkButton(
                label: "espanso.org",
                systemImage: "arrow.up.right.square",
                url: URL(string: "https://espanso.org")!
            )
        }
        .padding(.top, 24)
    }

    // MARK: - License text

    private var mitLicense: String {
        """
        MIT License

        Copyright (c) \(year) macspanso contributors

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }
}

// MARK: - LinkButton

private struct LinkButton: View {
    let label: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: systemImage)
                .font(.callout)
        }
        .buttonStyle(.bordered)
    }
}
