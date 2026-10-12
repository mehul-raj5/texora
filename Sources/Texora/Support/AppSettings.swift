import Foundation
import Observation

enum TexEngine: String, CaseIterable, Identifiable, Codable {
    case pdflatex, xelatex, lualatex, tectonic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pdflatex: return "pdfLaTeX"
        case .xelatex: return "XeLaTeX"
        case .lualatex: return "LuaLaTeX"
        case .tectonic: return "Tectonic"
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case auto = "", fable, opus, sonnet, haiku
    var id: String { rawValue.isEmpty ? "auto" : rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fable: return "Fable"
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }
}

enum ClaudeAccess: String, CaseIterable, Identifiable {
    case project, full
    var id: String { rawValue }
    var label: String { self == .project ? "Project folder only" : "Full machine access" }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let d = UserDefaults.standard

    var projectsFolder: String { didSet { d.set(projectsFolder, forKey: "projectsFolder") } }
    var defaultEngine: TexEngine { didSet { d.set(defaultEngine.rawValue, forKey: "defaultEngine") } }
    var autoCompile: Bool { didSet { d.set(autoCompile, forKey: "autoCompile") } }
    var autoSave: Bool { didSet { d.set(autoSave, forKey: "autoSave") } }
    var claudeModel: ClaudeModel { didSet { d.set(claudeModel.rawValue, forKey: "claudeModel") } }
    var claudeAccess: ClaudeAccess { didSet { d.set(claudeAccess.rawValue, forKey: "claudeAccess") } }
    var allowScripts: Bool { didSet { d.set(allowScripts, forKey: "allowScripts") } }
    var editorFontSize: Double { didSet { d.set(editorFontSize, forKey: "editorFontSize") } }
    var vimMode: Bool { didSet { d.set(vimMode, forKey: "vimMode") } }
    var lineWrap: Bool { didSet { d.set(lineWrap, forKey: "lineWrap") } }
    var pdfDarkMode: Bool { didSet { d.set(pdfDarkMode, forKey: "pdfDarkMode") } }
    var claudePathOverride: String { didSet { d.set(claudePathOverride, forKey: "claudePath") } }
    var texBinOverride: String { didSet { d.set(texBinOverride, forKey: "texBin") } }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        projectsFolder = d.string(forKey: "projectsFolder") ?? "\(home)/Documents/LaTeX Projects"
        defaultEngine = TexEngine(rawValue: d.string(forKey: "defaultEngine") ?? "") ?? .pdflatex
        autoCompile = d.object(forKey: "autoCompile") as? Bool ?? true
        autoSave = d.object(forKey: "autoSave") as? Bool ?? true
        claudeModel = ClaudeModel(rawValue: d.string(forKey: "claudeModel") ?? "") ?? .auto
        claudeAccess = ClaudeAccess(rawValue: d.string(forKey: "claudeAccess") ?? "") ?? .project
        allowScripts = d.object(forKey: "allowScripts") as? Bool ?? true
        editorFontSize = d.object(forKey: "editorFontSize") as? Double ?? 14
        vimMode = d.object(forKey: "vimMode") as? Bool ?? false
        lineWrap = d.object(forKey: "lineWrap") as? Bool ?? true
        pdfDarkMode = d.object(forKey: "pdfDarkMode") as? Bool ?? false
        claudePathOverride = d.string(forKey: "claudePath") ?? ""
        texBinOverride = d.string(forKey: "texBin") ?? ""
    }

    var projectsFolderURL: URL { URL(fileURLWithPath: (projectsFolder as NSString).expandingTildeInPath, isDirectory: true) }
}
