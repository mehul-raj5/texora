import SwiftUI
import AppKit
import Observation

/// Tracks the chosen theme. In Auto mode it follows the Mac's light/dark setting and switches
/// between the chosen light and dark themes.
@MainActor
@Observable
final class ThemeManager {
    enum Mode: String { case auto, fixed }

    var mode: Mode { didSet { save(); apply() } }
    var fixedThemeID: String { didSet { save(); apply() } }
    var autoLightID: String { didSet { save(); apply() } }
    var autoDarkID: String { didSet { save(); apply() } }

    private(set) var systemIsDark: Bool = ThemeManager.readSystemDark()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: "theme.mode") ?? "") ?? .fixed
        fixedThemeID = d.string(forKey: "theme.fixed") ?? Themes.catppuccinMocha.id
        autoLightID = d.string(forKey: "theme.autoLight") ?? Themes.catppuccinLatte.id
        autoDarkID = d.string(forKey: "theme.autoDark") ?? Themes.catppuccinMocha.id
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemIsDark = ThemeManager.readSystemDark()
                self?.apply()
            }
        }
    }

    var current: Theme {
        switch mode {
        case .fixed: return Themes.byID(fixedThemeID) ?? Themes.catppuccinMocha
        case .auto:
            return systemIsDark
                ? (Themes.byID(autoDarkID) ?? Themes.catppuccinMocha)
                : (Themes.byID(autoLightID) ?? Themes.catppuccinLatte)
        }
    }

    /// Picking a theme from the list. In Auto mode it becomes the light or dark half of the pair.
    func select(_ theme: Theme) {
        if mode == .auto {
            if theme.isDark { autoDarkID = theme.id } else { autoLightID = theme.id }
        } else {
            fixedThemeID = theme.id
        }
    }

    /// The sun/moon button: flip between the light and dark theme of the pair.
    func toggleLightDark() {
        let cur = current
        mode = .fixed
        fixedThemeID = cur.isDark ? autoLightID : autoDarkID
    }

    func isSelected(_ theme: Theme) -> Bool {
        mode == .auto ? (theme.id == autoLightID || theme.id == autoDarkID) : theme.id == fixedThemeID
    }

    /// Keeps native controls (scrollbars, menus, caret) in step with the theme.
    func apply() {
        NSApp?.appearance = current.nsAppearance
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: "theme.mode")
        d.set(fixedThemeID, forKey: "theme.fixed")
        d.set(autoLightID, forKey: "theme.autoLight")
        d.set(autoDarkID, forKey: "theme.autoDark")
    }

    private static func readSystemDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }
}
