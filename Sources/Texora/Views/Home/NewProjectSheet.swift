import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [ProjectTemplate] = ProjectTemplate.loadAll()
    @State private var selected: ProjectTemplate?
    @State private var name = ""
    @State private var prompt = ""

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New project")
                .font(.serif(26))
                .foregroundStyle(theme.textColor)
                .padding(.bottom, 18)

            label("Name")
            PlainField(placeholder: "My paper", text: $name, fontSize: 14, onSubmit: create)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surfaceColor))
                .padding(.bottom, 18)

            label("Template")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(templates) { t in templateCard(t) }
                }
                .padding(2)
            }
            .frame(height: 250)
            .padding(.bottom, 16)

            label("Ask Claude to set it up (optional)")
            TextField("", text: $prompt, prompt: Text("A 6-page conference paper on forecast correction with a results table").foregroundStyle(theme.mutedColor), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textColor)
                .lineLimit(2...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surfaceColor))
                .padding(.bottom, 20)

            HStack {
                Text("Saved in \((model.settings.projectsFolder as NSString).abbreviatingWithTildeInPath)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.mutedColor)
                Spacer()
                PillButton(title: "Cancel") { dismiss() }
                PillButton(title: "Create project", prominent: true, action: create)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(theme.bgColor)
        .onAppear {
            prompt = model.newProjectPrompt
            model.newProjectPrompt = ""
            if selected == nil { selected = templates.first }
            if name.isEmpty { name = suggestedName(from: prompt) }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryColor).padding(.bottom, 6)
    }

    private func templateCard(_ t: ProjectTemplate) -> some View {
        let isSel = selected?.id == t.id
        return Button { selected = t } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: t.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accentColor)
                Text(t.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textColor)
                Text(t.summary).font(.system(size: 11.5)).foregroundStyle(theme.mutedColor).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(theme.surfaceColor))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSel ? theme.accentColor : theme.borderColor.opacity(0.5), lineWidth: isSel ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func suggestedName(from p: String) -> String {
        let words = p.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? "Untitled paper" : words.prefix(1).uppercased() + words.dropFirst()
    }

    private func create() {
        guard let t = selected ?? templates.first else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
        model.createProject(name: n.isEmpty ? "Untitled paper" : n, template: t, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
