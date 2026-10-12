import SwiftUI
import UniformTypeIdentifiers

struct ChatPanel: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            ThemedDivider()
            ChatMessages()
            ChatInput()
        }
        .background(theme.bgColor)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(theme.accentColor.opacity(0.06))
                    .overlay(Text("Drop files to attach").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.accentColor))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if !ws.chat.pendingAttachments.contains(url) { ws.chat.pendingAttachments.append(url) }
                    }
                }
            }
            return true
        }
    }
}

private struct ChatHeader: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 4) {
            Menu {
                Button("New chat") { ws.chat.newChat() }
                if !ws.chat.chats.isEmpty {
                    Divider()
                    ForEach(ws.chat.chats.prefix(20)) { c in
                        Button {
                            ws.chat.select(chatID: c.id)
                        } label: {
                            if c.id == ws.chat.activeChatID { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                        }
                    }
                }
                if let active = ws.chat.activeChatID {
                    Divider()
                    Button("Delete this chat", role: .destructive) { ws.chat.deleteChat(active) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(ws.chat.activeChat?.title ?? "New chat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.mutedColor)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            Menu {
                Picker("Model", selection: $settings.claudeModel) {
                    ForEach(ClaudeModel.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(settings.claudeModel.label).font(.system(size: 12))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(theme.secondaryColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Claude model")
            IconButton(systemName: "square.and.pencil", help: "New chat", size: 13) { ws.chat.newChat() }
            IconButton(systemName: "sidebar.right", help: "Hide chat (⌥⌘C)", size: 13) { ws.chatVisible = false }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
    }
}

private struct ChatMessages: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if ws.chat.messages.isEmpty {
                        ChatEmptyState()
                    }
                    ForEach(ws.chat.messages) { m in
                        MessageView(message: m).id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.automatic)
            .onChange(of: ws.chat.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: ws.chat.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: ws.chat.messages.last?.activities.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

private struct ChatEmptyState: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    private var suggestions: [String] {
        var s = ["Tighten the abstract", "Check grammar and typos in the introduction", "Make the related work section more concise",
                 "Suggest a better title"]
        if !ws.compiler.errors.isEmpty { s.insert("Fix the compile errors", at: 0) }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("✦").font(.system(size: 24)).foregroundStyle(theme.accentColor)
            Text("Ask Claude about your project")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textColor)
            Text("Claude can read and edit every file here, compile to check its work, and use data or files you drop in. Highlight text in the code or PDF to ask about a specific passage.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(suggestions, id: \.self) { s in
                    Button { ws.chat.send(text: s == "Fix the compile errors" ? ws.fixErrorsPrompt() : s) } label: {
                        HStack {
                            Text(s).font(.system(size: 12.5)).foregroundStyle(theme.textColor)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(theme.mutedColor)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surfaceColor))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 20)
    }
}

private struct ChatInput: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var chat = ws.chat
        VStack(alignment: .leading, spacing: 8) {
            if ws.chat.isRunning {
                HStack(spacing: 8) {
                    ShimmerSpark()
                    Text(ws.chat.statusText ?? "Working…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryColor)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                if !ws.chat.pendingAttachments.isEmpty || ws.chatSelection != nil {
                    FlowLayout(spacing: 6) {
                        if let sel = ws.chatSelection {
                            Chip(icon: "text.quote",
                                 text: "\((sel.path as NSString).lastPathComponent) · \(sel.fromLine == sel.toLine ? "L\(sel.fromLine)" : "L\(sel.fromLine)–\(sel.toLine)")") {
                                ws.chatSelection = nil
                            }
                        }
                        ForEach(ws.chat.pendingAttachments, id: \.self) { url in
                            Chip(icon: "paperclip", text: url.lastPathComponent) {
                                ws.chat.pendingAttachments.removeAll { $0 == url }
                            }
                        }
                    }
                }
                TextField("", text: $chat.draft,
                          prompt: Text("Message Claude…").foregroundStyle(theme.mutedColor), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1...10)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            chat.draft += "\n"
                            return .handled
                        }
                        send()
                        return .handled
                    }
                HStack(spacing: 6) {
                    IconButton(systemName: "paperclip", help: "Attach files (copied into chatattachments/)", size: 13) { pickFiles() }
                    if ws.selection != nil && ws.chatSelection == nil {
                        Button {
                            ws.chatSelection = ws.selection
                        } label: {
                            Label("Add selection", systemImage: "text.quote")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.secondaryColor)
                        }
                        .buttonStyle(.plain)
                        .help("Include the text selected in the editor (⌘L)")
                    }
                    Spacer()
                    if ws.chat.isRunning {
                        Button { ws.chat.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.bgColor)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(theme.textColor))
                        }
                        .buttonStyle(.plain)
                        .help("Stop")
                    } else {
                        let empty = ws.chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ws.chat.pendingAttachments.isEmpty
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(empty ? theme.mutedColor : theme.bgColor)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(empty ? theme.elevatedColor : theme.accentColor))
                        }
                        .buttonStyle(.plain)
                        .disabled(empty)
                        .help("Send (↩)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surfaceColor))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? theme.accentColor.opacity(0.5) : theme.borderColor.opacity(0.6), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in focused = true }
    }

    private func send() {
        let text = ws.chat.draft
        let attachments = ws.chat.pendingAttachments
        guard !ws.chat.isRunning else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        var context: ChatController.Context?
        if let sel = ws.chatSelection {
            let range = sel.fromLine == sel.toLine ? "line \(sel.fromLine)" : "lines \(sel.fromLine)–\(sel.toLine)"
            context = .init(label: "\(sel.path) · \(range)",
                            text: "The user is referring to this selection from \(sel.path), \(range):\n```latex\n\(sel.text)\n```")
        } else if let path = ws.activePath {
            context = .init(label: nil, text: "(The user currently has \(path) open in the editor, cursor at line \(ws.cursorLine).)")
        }
        if ws.chat.send(text: text, context: context, attachments: attachments) != nil {
            ws.chat.draft = ""
            ws.chat.pendingAttachments = []
            ws.chatSelection = nil
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach files for Claude (they're copied into the project's chatattachments folder)"
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            for u in panel.urls where !ws.chat.pendingAttachments.contains(u) { ws.chat.pendingAttachments.append(u) }
        }
    }
}

struct Chip: View {
    @Environment(\.theme) private var theme
    var icon: String
    var text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11.5)).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(theme.secondaryColor)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(theme.elevatedColor))
    }
}

/// Pulsing spark shown while Claude works.
struct ShimmerSpark: View {
    @Environment(\.theme) private var theme
    @State private var on = false
    var body: some View {
        Text("✦")
            .font(.system(size: 13))
            .foregroundStyle(theme.accentColor)
            .opacity(on ? 1 : 0.35)
            .scaleEffect(on ? 1.1 : 0.9)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
