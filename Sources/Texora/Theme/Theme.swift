import SwiftUI
import AppKit

/// A complete colour scheme for the app chrome and the code editor.
/// Colours are stored as hex strings so they can be sent to the CodeMirror web view as CSS variables.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool

    // App chrome
    let bg: String            // main content background
    let sidebar: String       // sidebar background
    let surface: String       // input boxes, cards, chips
    let elevated: String      // popovers, menus
    let border: String
    let text: String
    let textSecondary: String
    let textMuted: String
    let accent: String
    let selection: String     // selected row / text selection
    let success: String
    let warning: String
    let danger: String

    // Editor syntax
    let synCommand: String    // \foo
    let synKeyword: String    // \begin \end \section …
    let synEnv: String        // {environment} names, atoms
    let synMath: String       // $…$
    let synComment: String
    let synBracket: String
    let synNumber: String
    let synString: String

    // Light surfaces that sit on top of the background (hover etc.) are derived.
    var hoverHex: String { isDark ? "#FFFFFF12" : "#0000000D" }

    var cssVariables: [String: String] {
        [
            "--bg": bg, "--sidebar": sidebar, "--surface": surface, "--elevated": elevated,
            "--border": border, "--text": text, "--text-secondary": textSecondary,
            "--text-muted": textMuted, "--accent": accent, "--selection": selection,
            "--success": success, "--warning": warning, "--danger": danger,
            "--syn-command": synCommand, "--syn-keyword": synKeyword, "--syn-env": synEnv,
            "--syn-math": synMath, "--syn-comment": synComment, "--syn-bracket": synBracket,
            "--syn-number": synNumber, "--syn-string": synString,
            "--hover": hoverHex,
        ]
    }
}

// MARK: - SwiftUI accessors

extension Theme {
    var bgColor: Color { Color(hex: bg) }
    var sidebarColor: Color { Color(hex: sidebar) }
    var surfaceColor: Color { Color(hex: surface) }
    var elevatedColor: Color { Color(hex: elevated) }
    var borderColor: Color { Color(hex: border) }
    var textColor: Color { Color(hex: text) }
    var secondaryColor: Color { Color(hex: textSecondary) }
    var mutedColor: Color { Color(hex: textMuted) }
    var accentColor: Color { Color(hex: accent) }
    var selectionColor: Color { Color(hex: selection) }
    var hoverColor: Color { Color(hex: hoverHex) }
    var successColor: Color { Color(hex: success) }
    var warningColor: Color { Color(hex: warning) }
    var dangerColor: Color { Color(hex: danger) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var nsAppearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }
}

extension Color {
    /// Accepts #RGB, #RRGGBB or #RRGGBBAA.
    init(hex: String) {
        let ns = NSColor(hex: hex)
        self.init(nsColor: ns)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = Themes.catppuccinMocha
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
