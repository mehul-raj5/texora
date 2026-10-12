# Texora

A native LaTeX editor for Apple Silicon Macs, with Claude built in.

- **Projects:** import a project ZIP (e.g. from Overleaf), open a folder, or start from a template (article, two-column, IEEE, ACM, thesis, Beamer, letter).
- **Editing:** a fast CodeMirror 6 editor next to a live PDF preview (Apple PDFKit), with a file outline, change history and 20 themes.
- **Claude chat:** talks to the Claude Code CLI installed on your Mac and uses your existing sign-in. Claude can read and edit every file in the project, compile to check its work, and use data you attach.
- **Ask Claude:** highlight text in the code *or* the PDF, press ⌘K, type what should change, and Claude edits the source.
- **Export:** the whole project as a ZIP (optionally with the PDF and the `.bbl` for arXiv), or just the PDF.

## Requirements
- macOS 15+ on Apple Silicon
- **Claude Code** (`claude`), signed in. Run `claude` once in Terminal to sign in.
- **A TeX engine.** Pick one:
  - TinyTeX: Settings → LaTeX → Install TinyTeX (~100 MB, no admin password). Gives the fastest builds (pdfLaTeX via latexmk), and missing packages install themselves on demand.
  - Tectonic (`brew install tectonic`). Used automatically when TinyTeX/MacTeX isn't installed.
  - MacTeX, detected automatically if present.

## Build and run
```bash
./scripts/build-app.sh            # builds dist/Texora.app (arm64, ad-hoc signed)
./scripts/build-app.sh --install  # …and copies it to /Applications
./scripts/build-app.sh --dmg      # …and makes dist/Texora.dmg
swift test                        # unit + integration tests
```

The editor bundle (`Resources/editor/editor.js`) is checked in. Rebuild it after changing `web/src` with:
```bash
cd web && npm install && npm run build
```

## Using it
| Action | How |
|---|---|
| New project / import ZIP / open folder | Home screen, or ⌘N / ⇧⌘I / ⌘O |
| Recompile | ⌘B (auto-compiles after saving by default) |
| Ask Claude about a selection | Select text in the code or PDF, then click **✦ Ask Claude** or press ⌘K |
| Send the selection to chat | ⌘L |
| Jump between code and PDF | ⌘-click in either one (SyncTeX) |
| Files / Outline / History | ⌘1 / ⌘2 / ⌘3 |
| Code / Split / PDF layout | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Toggle chat / sidebar | ⌥⌘C / ⌃⌘S |
| Export project ZIP | ⇧⌘E |
| Switch light/dark theme | ⌃⌘T, or the sun/moon button for the full list |

### Where things live
- **Projects:** `~/Documents/LaTeX Projects/<name>/` (configurable). Build output goes to a hidden `.build/` folder inside each project.
- **Chat attachments:** copied into `<project>/chatattachments/`, so Claude can read them. They're left out of exports unless you tick the option.
- **Library, chats and history:** `~/Library/Application Support/Texora/`. History is a private git repo per project, so your project folders never get a `.git`.

### What Claude can do
By default Claude can:
- read and edit anything **inside the project folder**
- run the LaTeX tools
- run Python and other scripts in the project

Anything outside the folder is denied. Settings → Claude can switch to "Full machine access" or turn scripts off.

Every Claude turn is snapshotted first, so each reply has **Undo** and **Diff**. History keeps every version and can restore a whole project or a single file.

## Architecture
```
Sources/Texora/
  App/         entry point, app state, menus
  Theme/       20 themes, picker
  Workspace/   WorkspaceModel (files, tabs, compile, outline, ask), ChatController, EditorBridge
  Services/    ClaudeSession (stream-json), CompileService, LogParser, SyncTeX,
               HistoryService (hidden git), ProjectImporter, ProjectIndex, ExportService, TinyTeXInstaller
  Views/       Home, Workspace (sidebar, outline, history, diff), Editor, PDF, Chat, Settings
web/src/       CodeMirror 6 editor: LaTeX tokenizer, folding, completions, Swift bridge
Resources/     editor bundle, project templates, app icon
```

Claude integration: one long-running `claude -p --input-format stream-json --output-format stream-json` process per chat. Replies stream token by token, and tool calls are shown as friendly status lines. Chats resume with `--resume <session-id>`.

## Development automation
Launch with `open dist/Texora.app --args --automation`, then drive it with `scripts/tx.sh <command> [arg]`, for example:
- `snapshot out.png`
- `open file.zip`
- `chat "…"`
- `dump state.json`

This mode is off in normal launches. See `DebugAutomation.swift` and `WorkspaceModel+Extras.swift` for the command list.
