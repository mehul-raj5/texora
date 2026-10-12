import SwiftUI

/// Mini window icon showing a theme's background, sidebar, text and accent colours.
struct ThemeSwatch: View {
    var theme: Theme
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: theme.bg))
            HStack(spacing: 0) {
                Rectangle().fill(Color(hex: theme.sidebar)).frame(width: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color(hex: theme.text)).frame(width: 15, height: 2.5)
                    Capsule().fill(Color(hex: theme.accent)).frame(width: 9, height: 2.5)
                }
                .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(width: 34, height: 26)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct AutoSwatch: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(hex: "#F4F4F2"))
            Rectangle().fill(Color(hex: "#1E1E22"))
        }
        .frame(width: 34, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// The theme list shown from the sun button and in Settings.
struct ThemePickerList: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(swatch: AnyView(AutoSwatch()), title: "Auto", subtitle: "Follows your Mac", checked: themes.mode == .auto) {
                    themes.mode = themes.mode == .auto ? .fixed : .auto
                }
                header("Light")
                ForEach(Themes.light) { t in themeRow(t) }
                header("Dark")
                ForEach(Themes.dark) { t in themeRow(t) }
            }
            .padding(8)
        }
        .scrollIndicators(.never)
    }

    private func themeRow(_ t: Theme) -> some View {
        row(swatch: AnyView(ThemeSwatch(theme: t)), title: t.name, subtitle: nil, checked: themes.isSelected(t)) {
            themes.select(t)
        }
    }

    private func header(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(theme.mutedColor)
            .padding(.leading, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func row(swatch: AnyView, title: String, subtitle: String?, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                swatch
                Text(title).font(.system(size: 13.5)).foregroundStyle(theme.textColor)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(theme.mutedColor)
                }
                Spacer()
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.textColor)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
            .hoverHighlight(radius: 8)
        }
        .buttonStyle(.plain)
    }
}

/// The sun/moon toolbar button. Click opens the picker.
struct ThemeButton: View {
    @Environment(\.theme) private var theme
    @State private var showing = false

    var body: some View {
        IconButton(systemName: theme.isDark ? "sun.max" : "moon", help: "Theme") { showing.toggle() }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                ThemePickerList()
                    .frame(width: 300, height: 520)
                    .background(theme.elevatedColor)
            }
    }
}
