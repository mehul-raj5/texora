import SwiftUI

/// Small floating "✦ Ask Claude ⌘K" button shown next to a selection.
struct AskPill: View {
    @Environment(\.theme) private var theme
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("✦").foregroundStyle(theme.accentColor)
                Text("Ask Claude").foregroundStyle(theme.textColor)
                Text("⌘K").foregroundStyle(theme.mutedColor).font(.system(size: 11))
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(theme.elevatedColor))
            .overlay(Capsule().stroke(hovering ? theme.accentColor : theme.borderColor, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

/// The popup that opens on a highlighted passage: type what should change, Claude edits the source.
struct AskClaudeOverlay: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let request: AskRequest

    private let width: CGFloat = 400

    var body: some View {
        GeometryReader { geo in
            let x = min(max(request.anchor.minX, 12), max(12, geo.size.width - width - 12))
            let below = request.anchor.maxY + 10
            let y = below + 280 > geo.size.height ? max(12, request.anchor.minY - 290) : below
            AskClaudeCard(request: request)
                .frame(width: width)
                .debugOverlay("ask")
                .padding(.leading, x)
                .padding(.top, y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

private struct AskClaudeCard: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let request: AskRequest
    @State private var instruction = ""
    @FocusState private var focused: Bool

    private let chips = ["Improve wording", "Fix grammar", "Make concise", "More formal", "Explain this", "Turn into a table"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quote
            if let replyID = request.replyID {
                ReplyStatus(replyID: replyID)
            } else {
                inputArea
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.elevatedColor))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .onAppear { focused = true }
        .onExitCommand { close() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("✦").foregroundStyle(theme.accentColor)
            Text("Ask Claude").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textColor)
            Text(locationLabel).font(.system(size: 11.5)).foregroundStyle(theme.mutedColor).lineLimit(1)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.mutedColor)
                    .frame(width: 22, height: 22).hoverHighlight(radius: 6)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    private var locationLabel: String {
        var parts: [String] = []
        if request.source == .pdf, let p = request.page { parts.append("PDF p.\(p + 1)") }
        if let path = request.path { parts.append((path as NSString).lastPathComponent) }
        if let a = request.fromLine, let b = request.toLine { parts.append(a == b ? "L\(a)" : "L\(a)–\(b)") }
        return parts.joined(separator: " · ")
    }

    private var quote: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.accentColor.opacity(0.6)).frame(width: 2)
            Text(request.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12, design: request.source == .editor ? .monospaced : .default))
                .foregroundStyle(theme.secondaryColor)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $instruction, prompt: Text("What should change?").foregroundStyle(theme.mutedColor), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit { submit(instruction) }
                Button { submit(instruction) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(instruction.isEmpty ? theme.mutedColor : theme.bgColor)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(instruction.isEmpty ? theme.surfaceColor : theme.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceColor))

            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button { submit(chip) } label: {
                        Text(chip)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.secondaryColor)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Capsule().stroke(theme.borderColor, lineWidth: 1))
                            .contentShape(Capsule())
                            .hoverHighlight(radius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            if ws.chat.isRunning, request.replyID == nil {
                Text("Claude is finishing another request. Yours will start when it's done.")
                    .font(.system(size: 11.5)).foregroundStyle(theme.warningColor)
            }
        }
    }

    private func submit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !ws.chat.isRunning else { return }
        ws.submitAsk(t)
    }

    private func close() {
        ws.ask = nil
        ws.pdf.clearSelection()
    }
}

private struct ReplyStatus: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let replyID: UUID

    var body: some View {
        if let msg = ws.chat.messages.first(where: { $0.id == replyID }) {
            VStack(alignment: .leading, spacing: 10) {
                if msg.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(ws.chat.statusText ?? msg.activities.last?.text ?? "Working…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.secondaryColor)
                            .lineLimit(1)
                    }
                    if !msg.text.isEmpty {
                        Text(msg.text).font(.system(size: 12.5)).foregroundStyle(theme.textColor).lineLimit(4)
                    }
                    Button("Stop") { ws.chat.stop() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryColor)
                } else {
                    if !msg.text.isEmpty {
                        ScrollView {
                            MarkdownText(text: msg.text, fontSize: 12.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if !msg.changedFiles.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: msg.undone ? "arrow.uturn.backward" : "checkmark.circle.fill")
                                .foregroundStyle(msg.undone ? theme.mutedColor : theme.successColor)
                            Text(msg.undone ? "Undone" : "Changed " + msg.changedFiles.map { ($0.path as NSString).lastPathComponent }.joined(separator: ", "))
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryColor).lineLimit(1)
                        }
                    }
                    HStack(spacing: 8) {
                        if !msg.changedFiles.isEmpty && !msg.undone {
                            PillButton(title: "Undo", systemImage: "arrow.uturn.backward") { ws.chat.undo(messageID: msg.id) }
                        }
                        PillButton(title: "Open in chat", systemImage: "bubble.left") {
                            ws.chatVisible = true
                            ws.ask = nil
                        }
                        Spacer()
                        PillButton(title: "Done", prominent: true) {
                            ws.ask = nil
                            ws.pdf.clearSelection()
                        }
                    }
                }
            }
        }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
