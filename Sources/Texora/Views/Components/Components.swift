import SwiftUI

// Small themed building blocks shared across the app.

/// Shape language shared by the whole UI: generous radii, quiet borders, soft shadows.
enum Metrics {
    static let rowRadius: CGFloat = 9
    static let controlRadius: CGFloat = 9
    static let cardRadius: CGFloat = 14
    static let composerRadius: CGFloat = 22
}

extension Font {
    /// The system serif (New York) used for headlines and assistant prose.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// A soft, theme-aware drop shadow for floating cards such as composers and menus.
struct SoftShadow: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 18
    var y: CGFloat = 6
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.07), radius: radius, x: 0, y: y)
    }
}

extension View {
    func softShadow(radius: CGFloat = 18, y: CGFloat = 6) -> some View { modifier(SoftShadow(radius: radius, y: y)) }
}

struct HoverHighlight: ViewModifier {
    @Environment(\.theme) private var theme
    var selected: Bool = false
    var radius: CGFloat = Metrics.rowRadius
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? theme.selectionColor : (hovering ? theme.hoverColor : .clear))
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(selected: Bool = false, radius: CGFloat = Metrics.rowRadius) -> some View {
        modifier(HoverHighlight(selected: selected, radius: radius))
    }
}

/// A row in the sidebar: icon, title, optional count.
struct SidebarRow: View {
    @Environment(\.theme) private var theme
    var icon: String?
    var title: String
    var count: Int? = nil
    var selected: Bool = false
    var indent: CGFloat = 0
    var muted: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 20)
                        .foregroundStyle(selected ? theme.textColor : theme.secondaryColor)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(muted ? theme.mutedColor : (selected ? theme.textColor : theme.secondaryColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.mutedColor)
                }
            }
            .padding(.leading, 10 + indent)
            .padding(.trailing, 10)
            .frame(height: 33)
            .contentShape(Rectangle())
            .hoverHighlight(selected: selected)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarSectionLabel: View {
    @Environment(\.theme) private var theme
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.mutedColor)
            .padding(.leading, 12)
            .padding(.top, 18)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Borderless icon button with a hover background.
struct IconButton: View {
    @Environment(\.theme) private var theme
    var systemName: String
    var help: String
    var size: CGFloat = 14
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(active ? theme.accentColor : theme.secondaryColor)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
                .hoverHighlight(radius: 8)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Soft rounded button used in toolbars and the home screen.
struct PillButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var systemImage: String?
    var prominent: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(prominent ? theme.bgColor : theme.textColor)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(prominent ? theme.accentColor.opacity(hovering ? 0.9 : 1) : (hovering ? theme.hoverColor : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .stroke(prominent ? .clear : theme.borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

/// Compact segmented control matching the theme.
struct ThemedSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    var options: [(T, String)]
    @Binding var selection: T
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.system(size: fontSize, weight: selection == value ? .medium : .regular))
                        .foregroundStyle(selection == value ? theme.textColor : theme.secondaryColor)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == value ? theme.elevatedColor : .clear)
                                .shadow(color: .black.opacity(selection == value ? (theme.isDark ? 0.25 : 0.07) : 0), radius: 2, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceColor))
    }
}

/// A 1-pt line in the theme's border colour.
struct ThemedDivider: View {
    @Environment(\.theme) private var theme
    var vertical = false
    var body: some View {
        Rectangle()
            .fill(theme.borderColor)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Placeholder-capable plain text field.
struct PlainField: View {
    @Environment(\.theme) private var theme
    var placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 13
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.mutedColor))
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .foregroundStyle(theme.textColor)
            .onSubmit(onSubmit)
    }
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}
