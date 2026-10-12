import SwiftUI

struct HistoryView: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.mutedColor)
                Spacer()
                Button { ws.promptCheckpoint() } label: {
                    Label("Checkpoint", systemImage: "flag").font(.system(size: 11.5)).foregroundStyle(theme.secondaryColor)
                }
                .buttonStyle(.plain)
                .help("Name the current version")
            }
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .frame(height: 28)
            if ws.history.entries.isEmpty {
                Text("Every save, Claude edit and restore is recorded here, so you can always go back.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.mutedColor)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: []) {
                        ForEach(groups, id: \.0) { day, entries in
                            Text(day)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.mutedColor)
                                .padding(.leading, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(entries) { e in HistoryRow(entry: e) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.never)
            }
        }
        .task { await ws.history.reload() }
    }

    private var groups: [(String, [HistoryEntry])] {
        let cal = Calendar.current
        var out: [(String, [HistoryEntry])] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMM"
        for e in ws.history.entries {
            let label: String
            if cal.isDateInToday(e.date) { label = "Today" }
            else if cal.isDateInYesterday(e.date) { label = "Yesterday" }
            else { label = fmt.string(from: e.date) }
            if out.last?.0 == label { out[out.count - 1].1.append(e) } else { out.append((label, [e])) }
        }
        return out
    }
}

private struct HistoryRow: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let entry: HistoryEntry

    var body: some View {
        Button { ws.diffEntry = entry } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(iconColor.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.replacingOccurrences(of: "✦ ", with: "").replacingOccurrences(of: "⚑ ", with: ""))
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                        if !entry.files.isEmpty {
                            Text("\(entry.files.count) file\(entry.files.count == 1 ? "" : "s")")
                            Text("+\(entry.added)").foregroundStyle(theme.successColor.opacity(0.9))
                            Text("−\(entry.removed)").foregroundStyle(theme.dangerColor.opacity(0.9))
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .hoverHighlight(selected: ws.diffEntry?.id == entry.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("View Changes") { ws.diffEntry = entry }
            Button("Restore Project to This Version") { confirmRestore() }
            if !entry.files.isEmpty {
                Menu("Restore File") {
                    ForEach(entry.files) { f in Button(f.path) { ws.restoreFile(f.path, to: entry) } }
                }
            }
        }
    }

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = "Restore the project to this version?"
        alert.informativeText = "Your current files are saved in History first, so you can undo this."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { ws.restoreProject(to: entry) }
    }

    private var icon: String {
        switch entry.kind {
        case .claude: return "sparkles"
        case .user: return "pencil"
        case .restore: return "arrow.uturn.backward"
        case .created: return "plus"
        case .checkpoint: return "flag.fill"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .claude: return theme.accentColor
        case .user: return theme.secondaryColor
        case .restore: return theme.warningColor
        case .created: return theme.successColor
        case .checkpoint: return theme.successColor
        }
    }
}

// MARK: - Diff viewer

struct DiffRow: Identifiable {
    enum Kind { case same, added, removed, changed, gap }
    let id: Int
    let kind: Kind
    let leftNo: Int?
    let left: String?
    let rightNo: Int?
    let right: String?
    var hidden = 0
}

enum LineDiff {
    /// Side-by-side rows with unchanged runs collapsed to `context` lines around changes.
    static func rows(old: String, new: String, context: Int = 3) -> [DiffRow] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        var full: [DiffRow] = []
        var i = 0, j = 0, id = 0
        while i < a.count || j < b.count {
            var dels: [Int] = [], adds: [Int] = []
            while i < a.count && removed.contains(i) { dels.append(i); i += 1 }
            while j < b.count && inserted.contains(j) { adds.append(j); j += 1 }
            if !dels.isEmpty || !adds.isEmpty {
                for k in 0..<max(dels.count, adds.count) {
                    let l = k < dels.count ? dels[k] : nil
                    let r = k < adds.count ? adds[k] : nil
                    let kind: DiffRow.Kind = (l != nil && r != nil) ? .changed : (l != nil ? .removed : .added)
                    full.append(DiffRow(id: id, kind: kind, leftNo: l.map { $0 + 1 }, left: l.map { a[$0] },
                                        rightNo: r.map { $0 + 1 }, right: r.map { b[$0] }))
                    id += 1
                }
                continue
            }
            if i < a.count && j < b.count {
                full.append(DiffRow(id: id, kind: .same, leftNo: i + 1, left: a[i], rightNo: j + 1, right: b[j]))
                id += 1; i += 1; j += 1
            } else { break }
        }
        // Collapse long unchanged stretches.
        var keep = [Bool](repeating: false, count: full.count)
        for (idx, r) in full.enumerated() where r.kind != .same {
            for k in max(0, idx - context)...min(full.count - 1, idx + context) { keep[k] = true }
        }
        var out: [DiffRow] = []
        var hiddenRun = 0
        for (idx, r) in full.enumerated() {
            if keep[idx] || full.count <= 2 * context + 1 {
                if hiddenRun > 0 { out.append(DiffRow(id: -idx, kind: .gap, leftNo: nil, left: nil, rightNo: nil, right: nil, hidden: hiddenRun)); hiddenRun = 0 }
                out.append(r)
            } else {
                hiddenRun += 1
            }
        }
        if hiddenRun > 0 { out.append(DiffRow(id: -full.count - 1, kind: .gap, leftNo: nil, left: nil, rightNo: nil, right: nil, hidden: hiddenRun)) }
        return out
    }
}

struct DiffView: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let entry: HistoryEntry
    @State private var selectedFile: String?
    @State private var rows: [DiffRow] = []
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textColor).lineLimit(1)
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.files.count) file\(entry.files.count == 1 ? "" : "s") · +\(entry.added) −\(entry.removed)")
                        .font(.system(size: 12)).foregroundStyle(theme.mutedColor)
                }
                Spacer()
                if let f = selectedFile {
                    PillButton(title: "Restore this file", systemImage: "arrow.uturn.backward") {
                        ws.restoreFile(f, to: entry); dismiss()
                    }
                }
                PillButton(title: "Restore project here", systemImage: "clock.arrow.circlepath") {
                    ws.restoreProject(to: entry); dismiss()
                }
                PillButton(title: "Done", prominent: true) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            ThemedDivider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(entry.files) { f in
                            Button { selectedFile = f.path } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: FileKind(path: f.path, isDirectory: false).icon)
                                        .font(.system(size: 11)).foregroundStyle(theme.mutedColor).frame(width: 14)
                                    Text(f.path).font(.system(size: 12.5)).foregroundStyle(theme.textColor).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text("+\(f.added)").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.successColor)
                                    Text("−\(f.removed)").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.dangerColor)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                                .hoverHighlight(selected: selectedFile == f.path)
                            }
                            .buttonStyle(.plain)
                        }
                        if entry.files.isEmpty {
                            Text("No file changes in this entry.").font(.system(size: 12.5)).foregroundStyle(theme.mutedColor).padding(10)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 260)
                .background(theme.sidebarColor)
                ThemedDivider(vertical: true)
                diffBody
            }
        }
        .frame(width: 1100, height: 720)
        .background(theme.bgColor)
        .onAppear { if selectedFile == nil { selectedFile = entry.files.first?.path } }
        .onChange(of: selectedFile) { load() }
        .task { load() }
    }

    @ViewBuilder
    private var diffBody: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            Text(selectedFile == nil ? "Select a file" : "No text changes to show (binary file or identical).")
                .font(.system(size: 13)).foregroundStyle(theme.mutedColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical]) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { r in DiffRowView(row: r) }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func load() {
        guard let file = selectedFile else { rows = []; return }
        loading = true
        let service = ws.historyService
        let commit = entry.id
        Task {
            let result = await Task.detached { () -> [DiffRow] in
                let parent = service.parent(of: commit)
                let old = parent.flatMap { service.content(of: file, at: $0) } ?? ""
                let new = service.content(of: file, at: commit) ?? ""
                if old.utf8.count > 2_000_000 || new.utf8.count > 2_000_000 { return [] }
                return LineDiff.rows(old: old, new: new)
            }.value
            rows = result
            loading = false
        }
    }
}

private struct DiffRowView: View {
    @Environment(\.theme) private var theme
    let row: DiffRow

    var body: some View {
        if row.kind == .gap {
            Text("⋯ \(row.hidden) unchanged line\(row.hidden == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.mutedColor)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(theme.surfaceColor.opacity(0.5))
        } else {
            HStack(spacing: 0) {
                side(no: row.leftNo, text: row.left, tint: (row.kind == .removed || row.kind == .changed) ? theme.dangerColor : nil)
                ThemedDivider(vertical: true)
                side(no: row.rightNo, text: row.right, tint: (row.kind == .added || row.kind == .changed) ? theme.successColor : nil)
            }
        }
    }

    private func side(no: Int?, text: String?, tint: Color?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(no.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.mutedColor)
                .frame(width: 38, alignment: .trailing)
            Text(text ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1.5)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.map { $0.opacity(text == nil ? 0.04 : 0.13) } ?? .clear)
    }
}

// MARK: - Export

struct ExportSheet: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export project").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.textColor)
            Text("Creates a ZIP of the whole project: every .tex, .bib, style, figure and data file. Build files are left out.")
                .font(.system(size: 12.5)).foregroundStyle(theme.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Include the compiled PDF", isOn: $options.includePDF)
                Toggle("Include the .bbl file (needed by arXiv)", isOn: $options.includeBbl)
                Toggle("Include files you attached in chat (chatattachments/)", isOn: $options.includeChatAttachments)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
            .foregroundStyle(theme.textColor)
            let count = ExportService.exportFiles(root: ws.root, options: options).count
            Text("\(count) project file\(count == 1 ? "" : "s") will be included.")
                .font(.system(size: 12)).foregroundStyle(theme.mutedColor)
            HStack {
                PillButton(title: "Export PDF only…", systemImage: "doc.richtext") { dismiss(); ws.exportPDF() }
                Spacer()
                PillButton(title: "Cancel") { dismiss() }
                PillButton(title: "Export ZIP…", prominent: true) {
                    let o = options
                    dismiss()
                    DispatchQueue.main.async { ws.performExport(options: o) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(theme.bgColor)
    }
}
