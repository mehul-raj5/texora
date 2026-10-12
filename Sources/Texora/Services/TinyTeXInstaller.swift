import Foundation
import Observation

/// Installs TinyTeX (a small TeX Live in ~/Library/TinyTeX, no admin rights needed) plus the
/// packages most papers use. Missing packages are also installed on demand during compiles.
@MainActor
@Observable
final class TinyTeXInstaller {
    var isInstalling = false
    var log = ""
    var step: String?
    var failed = false

    static let commonPackages = [
        "latexmk", "biber", "biblatex", "synctex", "texcount", "booktabs", "microtype", "natbib", "cleveref",
        "siunitx", "subcaption", "caption", "multirow", "enumitem", "xcolor", "hyperref", "geometry", "amsmath",
        "amsfonts", "ieeetran", "acmart", "beamer", "beamertheme-metropolis", "pgf", "pgfplots", "algorithms",
        "algorithmicx", "listings", "float", "wrapfig", "lipsum", "setspace", "titlesec", "fancyhdr",
        "tcolorbox", "environ", "trimspaces", "etoolbox", "xstring", "lm", "cm-super", "csquotes", "makecell",
        "threeparttable", "sttools", "xpatch", "comment", "totpages", "ncctools", "hyperxmp", "ifmtarg",
        "preprint", "authblk", "mathtools", "bm", "dvipng", "fontawesome5", "lastpage", "babel-english",
        "hyphen-english", "fontaxes", "libertine", "inconsolata", "newtx", "txfonts", "times", "helvetic",
        "zref", "draftwatermark", "everyshi", "pdfcomment", "soul", "todonotes",
    ]

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: ToolLocator.tinyTeXBin + "/pdflatex")
    }

    func install(tools: ToolLocator) async {
        guard !isInstalling else { return }
        isInstalling = true
        failed = false
        log = ""
        defer { isInstalling = false; step = nil }

        if !Self.isInstalled {
            step = "Downloading and installing TinyTeX (about 100 MB)…"
            let ok = await stream("/bin/sh", ["-c", "curl -fsSL https://yihui.org/tinytex/install-bin-unix.sh | sh"], env: tools.environment)
            guard ok, Self.isInstalled else {
                failed = true
                step = nil
                log += "\nTinyTeX installation failed."
                return
            }
        }
        tools.invalidate()
        step = "Installing common LaTeX packages…"
        let tlmgr = ToolLocator.tinyTeXBin + "/tlmgr"
        _ = await stream(tlmgr, ["install"] + Self.commonPackages, env: tools.environment)
        tools.invalidate()
        log += "\nDone."
    }

    /// Runs a command and appends its output to `log` as it arrives.
    private func stream(_ exe: String, _ args: [String], env: [String: String]) async -> Bool {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                if data.isEmpty { h.readabilityHandler = nil; return }
                let s = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    guard let self else { return }
                    self.log = String((self.log + s).suffix(20000))
                }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: proc.terminationStatus == 0)
            }
            do { try p.run() } catch {
                cont.resume(returning: false)
            }
        }
    }
}
