import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            EditorSettings().tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }
            LaTeXSettings().tabItem { Label("LaTeX", systemImage: "function") }
            ClaudeSettings().tabItem { Label("Claude", systemImage: "sparkles") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 620, height: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Projects") {
                LabeledContent("Projects folder") {
                    HStack {
                        Text((settings.projectsFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let u = panel.url { settings.projectsFolder = u.path }
                        }
                    }
                }
                Text("New projects and imported ZIPs are saved here.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Saving and compiling") {
                Toggle("Save automatically while typing", isOn: $settings.autoSave)
                Toggle("Recompile automatically after saving", isOn: $settings.autoCompile)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Text") {
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $settings.editorFontSize, in: 11...22, step: 1).frame(width: 200)
                        Text("\(Int(settings.editorFontSize)) pt").monospacedDigit().frame(width: 44)
                    }
                }
                Toggle("Wrap long lines", isOn: $settings.lineWrap)
            }
            Section("Keys") {
                Toggle("Vim key bindings", isOn: $settings.vimMode)
                Text("⌘B recompile · ⌘K ask Claude about the selection · ⌘L send the selection to chat · ⌘/ comment · ⌘I italic · ⇧⌘B bold · ⌘-click jump to PDF")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LaTeXSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var installer = TinyTeXInstaller()
    @State private var refresh = 0

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Engine") {
                Picker("Default engine", selection: $settings.defaultEngine) {
                    ForEach(TexEngine.allCases) { e in Text(e.label).tag(e) }
                }
                Text("pdfLaTeX is the fastest and what most conference templates expect. Each project can override this from the status bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Installed tools") {
                toolRow("TinyTeX", path: TinyTeXInstaller.isInstalled ? ToolLocator.tinyTeXBin : nil)
                toolRow("latexmk", path: app.tools.find("latexmk"))
                toolRow("pdflatex", path: app.tools.find("pdflatex"))
                toolRow("biber", path: app.tools.find("biber"))
                toolRow("Tectonic", path: app.tools.find("tectonic"))
                if !TinyTeXInstaller.isInstalled || installer.isInstalling {
                    HStack {
                        Button(installer.isInstalling ? "Installing…" : "Install TinyTeX") {
                            Task { await installer.install(tools: app.tools); refresh += 1 }
                        }
                        .disabled(installer.isInstalling)
                        if let step = installer.step { ProgressView().controlSize(.small); Text(step).font(.caption) }
                    }
                    Text("Downloads about 100 MB from yihui.org/tinytex and installs into ~/Library/TinyTeX. No admin password needed. Missing packages are added automatically when a compile needs them.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Install common packages") { Task { await installer.install(tools: app.tools); refresh += 1 } }
                        .disabled(installer.isInstalling)
                }
                if !installer.log.isEmpty {
                    DisclosureGroup("Installer output") {
                        ScrollView {
                            Text(installer.log).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                    }
                }
            }
            .id(refresh)
            Section("Advanced") {
                TextField("Custom TeX bin folder", text: $settings.texBinOverride, prompt: Text("/Library/TeX/texbin"))
            }
        }
        .formStyle(.grouped)
    }

    private func toolRow(_ name: String, path: String?) -> some View {
        LabeledContent(name) {
            if let path {
                Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(.green).lineLimit(1).truncationMode(.middle)
            } else {
                Text("Not installed").foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var version: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Claude Code") {
                LabeledContent("Status") {
                    if let path = app.tools.find("claude", override: settings.claudePathOverride) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(version ?? "Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text((path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not found. Install Claude Code, then sign in with `claude` in Terminal.").foregroundStyle(.secondary)
                    }
                }
                TextField("Custom path", text: $settings.claudePathOverride, prompt: Text("~/.local/bin/claude"))
                Text("Texora uses the Claude Code installed on this Mac and your existing sign-in. No API key is stored in the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Model") {
                Picker("Model", selection: $settings.claudeModel) {
                    ForEach(ClaudeModel.allCases) { m in Text(m.label).tag(m) }
                }
                Text("Auto uses your Claude Code default.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Access") {
                Picker("Claude can work in", selection: $settings.claudeAccess) {
                    ForEach(ClaudeAccess.allCases) { a in Text(a.label).tag(a) }
                }
                Toggle("Allow running Python and other scripts in the project", isOn: $settings.allowScripts)
                Text(settings.claudeAccess == .project
                     ? "Claude can read and edit everything inside the project folder and run the LaTeX tools. Anything outside the folder is blocked."
                     : "Claude can read, write and run commands anywhere on this Mac without asking. Use with care.")
                    .font(.caption).foregroundStyle(settings.claudeAccess == .project ? Color.secondary : Color.orange)
            }
        }
        .formStyle(.grouped)
        .task {
            if let path = app.tools.find("claude", override: settings.claudePathOverride) {
                let r = await ProcessRunner.run(path, ["--version"], env: app.tools.environment)
                version = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

private struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Darken the PDF preview in dark themes", isOn: $settings.pdfDarkMode)
                .padding(16)
            Divider()
            ThemePickerList()
                .background(theme.elevatedColor)
        }
    }
}
