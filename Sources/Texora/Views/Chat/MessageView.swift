import SwiftUI

struct MessageView: View {
    @Environment(\.theme) private var theme
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user: UserMessage(message: message)
        case .assistant: AssistantMessage(message: message)
        case .notice: NoticeMessage(text: message.text)
        }
    }
}

private struct UserMessage: View {
    @Environment(\.theme) private var theme
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let label = message.contextLabel {
                HStack(spacing: 4) {
                    Image(systemName: message.fromPopup ? "sparkles" : "text.quote").font(.system(size: 9))
                    Text(label).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedColor)
            }
            if !message.attachments.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(message.attachments, id: \.self) { a in Chip(icon: "paperclip", text: (a as NSString).lastPathComponent) }
                }
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textColor)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 32)
    }
}

private struct AssistantMessage: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let message: ChatMessage
    @State private var showAllActivities = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.activities.isEmpty { activities }
            if message.text.isEmpty && message.isStreaming {
                TypingDots()
            } else if !message.text.isEmpty {
                if message.isError {
                    NoticeMessage(text: message.text)
                } else {
                    MarkdownText(text: message.text)
                }
            }
            if !message.isStreaming && !message.changedFiles.isEmpty { changes }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            if hovering && !message.isStreaming && !message.text.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(theme.mutedColor)
                        .frame(width: 22, height: 22).hoverHighlight(radius: 5)
                }
                .buttonStyle(.plain)
                .help("Copy reply")
            }
        }
    }

    private var activities: some View {
        let all = message.activities
        let shown = showAllActivities || all.count <= 4 ? all : Array(all.suffix(3))
        return VStack(alignment: .leading, spacing: 4) {
            if !showAllActivities && all.count > 4 {
                Button { showAllActivities = true } label: {
                    Text("+\(all.count - 3) earlier steps").font(.system(size: 11.5)).foregroundStyle(theme.mutedColor)
                }
                .buttonStyle(.plain)
            }
            ForEach(shown) { a in
                HStack(spacing: 7) {
                    Group {
                        if !a.done && message.isStreaming {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: a.failed ? "exclamationmark.circle" : a.icon)
                                .font(.system(size: 10.5))
                                .foregroundStyle(a.failed ? theme.warningColor : theme.mutedColor)
                        }
                    }
                    .frame(width: 14)
                    Text(a.text)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(a.detail ?? a.text)
            }
        }
        .padding(.vertical, 2)
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: message.undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(message.undone ? theme.mutedColor : theme.successColor)
                    .font(.system(size: 12))
                Text(message.undone ? "Changes undone" : "Changed \(message.changedFiles.count) file\(message.changedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textColor)
                Spacer()
                if !message.undone {
                    Button("Undo") { ws.chat.undo(messageID: message.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.accentColor)
                }
                if let after = message.after, let entry = ws.history.entries.first(where: { $0.id == after }) {
                    Button("Diff") { ws.diffEntry = entry }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.accentColor)
                }
            }
            ForEach(message.changedFiles) { f in
                Button { if ws.files.contains(f.path) { ws.open(f.path) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: FileKind(path: f.path, isDirectory: false).icon)
                            .font(.system(size: 10.5)).foregroundStyle(theme.mutedColor).frame(width: 14)
                        Text(f.path).font(.system(size: 12)).foregroundStyle(theme.secondaryColor).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("+\(f.added)").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.successColor)
                        Text("−\(f.removed)").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.dangerColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surfaceColor.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.borderColor.opacity(0.7), lineWidth: 1))
        .opacity(message.undone ? 0.7 : 1)
    }
}

private struct NoticeMessage: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warningColor).font(.system(size: 12))
            Text(text).font(.system(size: 12.5)).foregroundStyle(theme.textColor).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.warningColor.opacity(0.1)))
    }
}

struct TypingDots: View {
    @Environment(\.theme) private var theme
    @State private var phase = 0.0
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(theme.mutedColor)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 5 - Double(i) * 0.7)))
                }
            }
        }
        .frame(height: 16)
    }
}
