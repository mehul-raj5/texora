# Texora: build plan (v3, approved and built 2026-10-12)

A native macOS app for Apple Silicon. You can:
- Create a project, import a LaTeX project as a ZIP, or open a folder.
- Edit the source next to the live PDF and recompile.
- Chat with Claude about the whole project.
- Highlight text in the code or the PDF and ask Claude to change it.
- Browse the change history.
- Export as ZIP or PDF.

Claude runs through the **Claude Code CLI already installed on this Mac**. The user only sees a chat box, and the app drives Claude Code behind the scenes. Claude has full read/write access to the project's files.

**v2 changes** (from your second message):
- New project
- History of changes
- Select text → "Ask Claude" popup, in both the code and the PDF
- File outline
- Themes
- Interface modelled on your reference screenshot

---

## 1. What this machine already has

| Need | Status |
|---|---|
| Apple Silicon (arm64), macOS 27 | ✓ |
| Xcode 27 / Swift 6.4 | ✓ |
| Claude Code CLI | ✓ v2.1.296 at `~/.local/bin/claude`. Uses your existing login, so the app needs no API key |
| LaTeX engine | ✓ Tectonic 0.15. ✗ No TeX Live yet (no pdflatex/latexmk/biber). Plan: add TinyTeX, see §2 and §10 |

---

## 2. Tech stack (recommended)

**Swift + SwiftUI, with AppKit where needed. Built as a real arm64 `.app`, with no Electron and no browser.**

| Piece | Choice | Why |
|---|---|---|
| App shell / UI | SwiftUI, macOS 14+ target, hidden title bar with traffic lights in the sidebar (like your reference) | Native look, menus and shortcuts. Small app (~10 MB) |
| Code editor | **CodeMirror 6**, embedded offline in a native `WKWebView` panel. The JS bundle (~1 MB) ships inside the app, so it never touches the network | The engine Overleaf switched to. It draws only the visible lines, so typing stays smooth in very long papers. LaTeX-aware autocomplete, folding, multi-cursor and search come built in |
| PDF preview | **PDFKit** | Sharp Retina rendering, text selection, search, zoom |
| ZIP import/export | ZIPFoundation (Swift package) | Handles ZIPs in-process and guards against unsafe paths |
| Claude bridge | Long-running `claude -p` subprocess speaking **stream-json** over stdin/stdout | This is the same protocol the official Agent SDKs use, so the app needs no Node or Python runtime |
| Compile | **pdfLaTeX via latexmk from TinyTeX** (a small TeX Live installed in your user folder) by default. XeLaTeX/LuaLaTeX are per-project options, and Tectonic is the fallback | pdfLaTeX is the fastest engine and what conference templates expect. TinyTeX needs no admin rights, so the app can **auto-install a missing package** when a compile fails on it. latexmk reruns BibTeX/biber only when needed |
| History / undo | Hidden git repo per project, stored outside the project folder | Full change history and diffs without putting `.git` in your project |
| Themes | One theme-token system that drives the whole UI plus the editor syntax colours | The theme switches instantly everywhere |
| Packaging | Swift Package + `scripts/build-app.sh`, which builds `Texora.app` (arm64, ad-hoc signed) and an optional `.dmg` | One build command |

The app is not sandboxed because it must launch the local `claude` and `tectonic`. That means no App Store, which is fine for personal use.

---

## 3. Interface (modelled on your reference)

Look and feel:
- Dark, muted Catppuccin-style palette by default.
- Slim left sidebar with sections and counts, rounded selected rows, and Settings pinned at the bottom.
- Sidebar toggle and breadcrumb at the top, with a theme button at the top right.
- Generous spacing, soft rounded input boxes.

### 3.1 Home window
```
┌──────────────┬───────────────────────────────────────────────────────────────┐
│ ● ● ●        │ ▢  Home                                                     ☼ │
│ ⌂ Home       │                                                               │
│ ▤ Projects 3 │      Good evening                                             │
│              │      ┌──────────────────────────────────────────────────────┐ │
│ Chats        │      │ ✦ Describe a new paper, or drop a .zip here   Create ↵│ │
│ ✎ New chat   │      └──────────────────────────────────────────────────────┘ │
│ ▾ Previous   │      [+ New project]  [⇪ Import ZIP]  [▢ Open folder]         │
│   chats…     │                                                               │
│              │      Recent                                                   │
│ Collections  │      ▢ Forecast paper      edited 2 h ago              │
│ + New coll.  │      ▢ Thesis draft               edited yesterday            │
│ ▾ ▢ Papers 1 │                                                               │
│    Forecast… │                                                               │
│ ⚙ Settings   │                                                               │
└──────────────┴───────────────────────────────────────────────────────────────┘
```
- **Sidebar:**
  - Home.
  - Projects, with a count.
  - Chats: New chat and Previous chats across projects.
  - Collections: folders to group projects, for example "Conference papers" or "Thesis".
  - Settings.
- **Big input:** type a description and press Enter. The app creates a new project and Claude scaffolds it. You can also drop a `.zip` onto the box.
- Below it: recent projects with a last-edited time. When there are none, it shows an empty-state invitation.

### 3.2 Project workspace
```
┌──────────────┬──────────────────────────────────────────────────────────────────────────┐
│ ● ● ●        │ ▢  Home › Forecast paper › main.tex    [Code|Split|PDF]  ⟳ Recompile  ⇪ Export ▾  ☼  ✦ │
│ ← Home       ├──────────────────────────┬──────────────────────────┬─────────────────────┤
│ Forecast paper   │ main.tex × intro.tex ×   │                          │ Chat · New ▾        │
│[Files|Outline│  12 \section{Intro}      │     PDF (PDFKit)         │ you: tighten abstr. │
│ |History]    │  13 Accurate forecasts …  │                          │ ✦ Editing abstract  │
│ ▾ Methodology│     ▔▔▔▔▔▔▔▔▔▔ selected  │                          │ Done. Changed 1 file│
│   Overview   │     ┌─────────────────┐  │                          │  [Undo] [Diff]      │
│   Notation   │     │ ✦ Ask Claude    │  │                          │                     │
│  ▾ Stage 1   │     │ "make it formal"│  │                          │                     │
│     Encoder  │     └─────────────────┘  │                          │ 📎 Message…       ↵ │
│ Chats (this) ├──────────────────────────┤                          │                     │
│ ⚙ Settings   │ Issues · 2 errors 5 warn │                          │                     │
└──────────────┴──────────────────────────┴──────────────────────────┴─────────────────────┘
```

**Sidebar** (contextual inside a project): ← Home, the project name, and a **Files | Outline | History** switch. Below that are this project's chats (New chat, Previous chats) and Settings.

**Top bar:**
- Breadcrumb.
- Layout switch: Code / Split / PDF.
- **Recompile** (⌘B).
- **Export ▾**: Project ZIP, or PDF.
- Theme button.
- Chat panel toggle.

**Center:** code editor tabs. The issues panel underneath lists errors and warnings, and clicking one jumps to the line.

**Right:** PDF preview, then the Claude chat panel, which can be collapsed. Every panel resizes, and the sidebar and chat collapse to give the code and PDF full width.

---

## 4. Features

### 4.1 Projects: create, import, open
- **New project:** choose a template, then name it.
  - Templates: Blank article, Two-column paper, IEEE conference, ACM (acmart), Thesis/report, Beamer slides, Letter/CV.
  - Or describe the project in the home box and Claude scaffolds it.
- **Import ZIP:** extracts to `~/Documents/LaTeX Projects/<name>/` (configurable).
  - Rejects unsafe `../` and absolute paths.
  - Skips `__MACOSX` and `.DS_Store`.
  - If the ZIP has a single top-level folder, uses it as the project root.
  - Renames on a name collision.
- **Open Folder:** opens any existing LaTeX directory.
- **Main-file detection:** checks `% !TEX root`, then `\documentclass` + `\begin{document}`, then common names (main/paper/thesis). If more than one file matches, the app asks. You can change the main file later from the toolbar.
- **Collections:** group projects in the sidebar, by drag-and-drop or a right-click menu.
- **Per-project metadata** lives in Application Support, so the project folder stays clean. It stores the main file, engine, chats, collection and history ID.

### 4.2 Editor (CodeMirror 6)
- LaTeX syntax colours, taken from the current theme.
- Line numbers, current-line highlight, bracket matching, auto-closing of `{}`, `$$` and `\begin…\end`.
- **Autocomplete:**
  - `\commands`
  - environments
  - `\ref{}` / `\eqref{}` from your `\label`s
  - `\cite{}` from your `.bib` keys (showing title and author)
  - file paths in `\includegraphics` / `\input`
- Folding of sections and environments, multi-cursor, ⌘F find/replace (regex), ⌘/ comment, auto-indent.
- Spell-check that skips LaTeX commands. Optional Vim keybindings.
- Smooth on very long files, because only the visible lines are drawn.
- Tabs with unsaved dots, ⌘S, and optional autosave.
- **Live reload** when files change on disk, for example after Claude edits them. The cursor and scroll position are kept. If you have unsaved edits in the same file, a conflict banner offers "Keep mine" or "Take Claude's".

### 4.3 File outline (sidebar → Outline)
- A collapsible tree of `\part`, `\chapter`, `\section`, `\subsection`, `\subsubsection` and `\paragraph`, matching your screenshot: chevrons, indent guide lines, and a rounded highlight on the active row.
- It follows `\input` and `\include` from the main file, so a multi-file paper reads as one document.
- **The current section is highlighted** as you move the cursor. Click a heading to jump to it in the code, and the PDF scrolls to match (via SyncTeX).
- Simple inline maths is shown readably, so `$\to$` displays as →. It updates live as you type or Claude edits.

### 4.4 Compile & PDF preview
- **Recompile** with ⌘B. Optional auto-compile runs 1 s after each save. The app also recompiles automatically after any Claude change.
- Output goes to a hidden `.build/` folder, so no aux or log clutter appears in the project.
- The log is parsed into clickable errors, warnings and bad boxes. A **"Fix with Claude"** button sends the errors to chat.
- Engine picker: Tectonic, or pdfLaTeX/XeLaTeX/LuaLaTeX via latexmk.
- The PDF keeps its page and zoom on reload. There's an optional **dark PDF** mode that tints pages to match dark themes.
- **SyncTeX:** ⌘-click in the PDF jumps to the source line, and ⌘-click in the code shows the spot in the PDF.

### 4.5 Claude chat (the abstraction)
How it works behind the scenes:
```
claude -p --input-format stream-json --output-format stream-json --verbose
          --include-partial-messages  --permission-mode acceptEdits
          --allowedTools Read Edit Write Glob Grep "Bash(tectonic:*)" "Bash(latexmk:*)"
          --append-system-prompt "<project root, main file, how to compile, be concise>"
          --model <chosen>  [--resume <session-id>]
   (working directory = project folder)
```
- **What you see:**
  - One long-running Claude process per open chat, with replies streaming token by token.
  - Claude's actions show as small friendly status lines ("Reading main.tex…", "Editing intro.tex", "Compiling…"). Raw tool output is never shown.
- **What Claude can access:** read/write on everything inside the project, and it can run the compiler to check its work. It can't reach anything outside the project. Edits are auto-accepted with no pop-ups. An optional "full machine access" toggle is in Settings.
- **Context Claude gets automatically:** project path, main file, the open file and selection, and the latest compile errors.
- **What you can give Claude:**
  - Typed or pasted text and code.
  - Dropped files (CSV/data, images, PDFs, `.bib`, code). They're copied into a dedicated **`<project>/chatattachments/`** folder. It's deliberately not named plain `attachments/`, so it never clashes with a folder the project already has, and chat inputs stay separate from paper sources. Claude can read everything in it, and images are also sent inline so Claude can see them.
  - ⌘L sends the editor selection to chat.
- **Chat controls:**
  - **Multiple chats per project:** New chat, and a Previous chats list, as in your reference. Each chat resumes after an app restart.
  - Stop: interrupts the current turn.
  - Model picker: Opus / Sonnet / Haiku.
- **Every turn:** open files are auto-saved first and a history snapshot is taken. After the turn:
  - The reply shows "Changed N files", with **Undo** and **Diff**.
  - Editors reload.
  - The PDF recompiles.

### 4.6 Select → "Ask Claude" popup (code *and* PDF)
1. Select text in the editor **or in the PDF**. A small **✦ Ask Claude** pill appears next to the selection. You can also press ⌘K.
2. A popover opens, anchored at the selection. It shows:
   - The quoted text.
   - A box asking "What should change?".
   - Quick chips: *Improve wording · Fix grammar · Make concise · More formal · Explain · Turn into table*.
3. Claude receives:
   - Your instruction.
   - The selected text.
   - The file and line range. For a PDF selection, SyncTeX maps it to the source and the text is matched to pin the exact lines.
   - Surrounding context.
4. Claude edits the source. The popover streams progress, then shows **"Done · intro.tex L42–48"** with **Undo** and **Open in chat**. The PDF recompiles, and the changed lines briefly flash in the editor.
5. Every popup request is also recorded in the project's current chat and in History.

### 4.7 History of changes (sidebar → History)
- A timeline of every change to the project, newest first:
  - ✦ **Claude turns**, labelled with your request ("Tighten the abstract").
  - ✎ **Your edits**, grouped automatically (e.g. "Edited intro.tex, refs.bib"; saves within 5 minutes are merged into one entry).
  - Imports, project creation and restores.
  - Optional named checkpoints, for example "Before submission".
- Each entry shows time, author (you or Claude), files changed and `+/-` line counts.
- Click an entry to open a **diff viewer** with a per-file side-by-side diff in theme colours.
- Actions on each entry:
  - Restore the whole project to that point.
  - Restore just one file.
  - Compare with the current version.
- **Restoring never destroys anything:** the restore itself becomes a new history entry, so you can undo the undo.

### 4.8 Export
- **Export ▾ → Project as ZIP:** the *whole project*, including all `.tex`, `.bib` and `.cls`/`.sty` files, figures and data. It excludes `.build/`, aux files and `.DS_Store`. Options:
  - ☐ include `chatattachments/` (files you gave Claude in chat; off by default because they aren't paper sources)
  - ☐ include compiled PDF
  - ☐ include `.bbl` (arXiv-ready)
- **Export ▾ → PDF.**
- **Reveal in Finder**, since projects are ordinary folders.

### 4.9 Themes
- **Picker** (☼ button in the top bar, also in Settings): a popover like your screenshots.
  - **Auto** (follows your Mac) at the top, then **Light** and **Dark** sections.
  - Each row has a mini swatch icon showing the background and accent colours, and a ✓ on the current theme.
- **Light:** Default Light, Paper, Catppuccin Latte, One Light, Gruvbox Light, Solarized Light, Rosé Pine Dawn, GitHub Light.
- **Dark:** Default Dark, **Catppuccin Mocha (default)**, Catppuccin Macchiato, One Dark, Gruvbox Dark, Dracula, Nord, Tokyo Night, Solarized Dark, Rosé Pine, Rosé Pine Moon, GitHub Dark.
- A theme recolours **everything**: sidebar, panels, chat, popovers, editor syntax colours and the diff viewer. It can also tint the PDF.
- In Auto mode, you choose which light theme and which dark theme it switches between.
- "Yomu Light/Dark" in your screenshot are that app's own house themes. Ours are "Default Light/Dark".

### 4.10 Settings
- Paths to `claude`, `tectonic` and `latexmk` (auto-detected, because Mac GUI apps don't inherit your shell PATH).
- Default engine, auto-compile.
- Projects folder.
- Claude model and access level.
- Theme.
- Editor font and size.

---

## 5. Keyboard shortcuts
| Action | Keys |
|---|---|
| Save | ⌘S |
| Recompile | ⌘B |
| Ask Claude about selection | ⌘K |
| Toggle chat panel | ⌥⌘C |
| Toggle sidebar | ⌃⌘S |
| Files / Outline / History | ⌘1 / ⌘2 / ⌘3 |
| Code / Split / PDF layout | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Export project ZIP | ⇧⌘E |
| New project | ⌘N |
| Find | ⌘F |

---

## 6. Code layout
```
latexEditor/
├── Package.swift
├── PLAN.md  PROGRESS.md
├── scripts/build-app.sh                 # release build → Texora.app (+ dmg)
├── Resources/  Info.plist, AppIcon.icns, Templates/ (new-project templates)
├── Sources/LatexEditor/
│   ├── App/        LatexEditorApp, AppState, Commands (menus & shortcuts)
│   ├── Theme/      Theme tokens, all theme definitions, ThemePicker
│   ├── Views/
│   │   ├── Home/       HomeView, Sidebar, RecentProjects, Collections
│   │   ├── Workspace/  WorkspaceView, TopBar, FileTree, OutlineView, HistoryView, DiffView
│   │   ├── Editor/     EditorTabs, CodeMirrorView (WKWebView + Swift↔JS bridge)
│   │   ├── PDF/        PDFPane (PDFKit), selection handling
│   │   ├── Chat/       ChatPanel, MessageView, AskClaudePopover
│   │   └── Settings/
│   ├── Services/
│   │   ├── ProjectStore     # create / import zip / open folder, templates, collections, FSEvents watcher
│   │   ├── OutlineParser    # sections across \input/\include
│   │   ├── CompileService   # tectonic / latexmk, LogParser, SyncTeX parser
│   │   ├── ClaudeService    # subprocess, stream-json, chats/sessions, interrupt
│   │   ├── HistoryService   # hidden git repo: snapshots, timeline, diffs, restore
│   │   └── ExportService    # project zip / pdf
│   └── Support/    ToolLocator, Settings, Process helpers
├── Tests/LatexEditorTests/   # zip safety, main-file detection, outline parser, log parser,
│                             # stream-json parser, synctex mapping, history restore, export filter
└── Fixtures/                 # sample projects: multi-file paper (figs + bib + csv), broken one
```

---

## 7. Milestones (each ends with a working app you can open)

| # | Milestone | Done when |
|---|---|---|
| M0 | **Scaffold + theme system:** Swift package, window with hidden title bar, theme tokens + 2 themes, `build-app.sh`, PROGRESS.md, own git repo | `Texora.app` launches and the theme switches live |
| M1 | **Home + projects:** sidebar (Home/Projects/Chats/Collections/Settings), greeting home, New project (templates), Import ZIP, Open folder, recents, collections | You can create, import and open projects from the Home screen |
| M2 | **Workspace + editor + outline:** contextual sidebar, file tree, tabs, highlighting, find, save, live reload, **Outline** tab | Edit and save works, and the outline tracks the cursor and jumps on click |
| M3 | **Compile + PDF:** engines, Recompile, auto-compile, PDFKit pane, issues panel, layout switch, **SyncTeX** both ways | Fixture compiles side by side, and clicking an error or ⌘-click jumps correctly |
| M4 | **Claude chat:** ClaudeService, streaming chat panel, status lines, `chatattachments/` drop-in, stop, model, **multiple chats + previous chats** | "Rewrite the abstract" edits the file and the PDF updates |
| M5 | **Ask-Claude popup:** selection pill + popover in the editor **and the PDF** | Highlighting text in the PDF → instruction → correct source lines change |
| M6 | **History:** snapshots, timeline, diff viewer, restore project/file, per-turn Undo, conflict banner | Any past state can be viewed and restored, and restores are undoable |
| M7 | **Export + themes + polish:** ZIP/PDF export, full theme set + picker, dark PDF, Settings, shortcuts, app icon, DMG | Daily-driver ready |

PROGRESS.md is updated after every step, so a session cutoff loses nothing.

---

## 8. How I'll verify each step
- **Unit tests** (`swift test`) cover:
  - ZIP path-traversal rejection and single-folder unwrap.
  - Main-file detection and the outline parser.
  - TeX log parsing and stream-json parsing.
  - SyncTeX mapping.
  - History snapshot/restore round-trip.
  - Export filters.
- **Fixture projects:** a realistic multi-file paper (sections in separate files, figures, `.bib`, a CSV) and a deliberately broken one.
- **End-to-end on the built `.app`:**
  1. Create, import and compile a project.
  2. Ask Claude in chat and via the popup, from both the code and the PDF.
  3. Check that the reload, recompile, History entry and Undo all work.
  4. Restore an old version.
  5. Export, re-import and compile again.
- **Screenshots** of the running app to check the layout against your reference in several themes.

---

## 8b. Disk space (measured on this Mac on 2026-10-12: **~44 GB free**)

| Item | New space | Notes |
|---|---|---|
| Xcode 27, Claude Code (230 MB), Node, Tectonic (15 MB + 43 MB cache) | **0** | Already installed |
| **Texora.app** | ~20 MB | Swift binary + CodeMirror bundle + templates + icon |
| **TinyTeX** (pdfLaTeX, latexmk, biber + common paper packages) | ~0.3–1 GB | Grows only as missing packages get installed |
| Swift build cache while I develop (`.build/`) | ~0.5–1.5 GB | Temporary. `swift package clean` frees it |
| CodeMirror npm packages (`node_modules`, build-time only) | ~50 MB | Can be deleted after bundling |
| Swift package downloads (ZIPFoundation) | <5 MB | |
| **Total during development** | **≈ 1–2.5 GB** | |
| **Total after cleanup (app + TinyTeX)** | **≈ 0.3–1 GB** | |

Ongoing, per project:
- The project itself.
- `.build/`: about 1–2× the PDF size.
- History repo: git-compressed, roughly the project size plus small deltas, and more if figures change often.
- Chat transcripts: a few MB, stored by Claude Code in `~/.claude/projects`.

Not chosen: full MacTeX would add a 6.4 GB download and ~9 GB installed (~20% of your free space) for packages you'd mostly never use.

---

## 9. Not in v1 (can add later)
- Real-time collaboration.
- Overleaf sync.
- A Git/GitHub UI.
- Windows or Intel builds.
- Advanced LaTeX autocompletion.
- Multiple windows on the same project.

---

## 10. Decisions (resolved 2026-10-12)
1. **Stack:** native SwiftUI app + CodeMirror 6 editor + PDFKit preview ("whatever looks smooth and very good").
2. **Claude's access:** read/write on the project folder, plus running the TeX tools **and Python or other scripts inside the project** (user said yes). A "full machine access" toggle is available in Settings.
3. **TeX:** TinyTeX + pdfLaTeX via latexmk, with Tectonic as the fallback (default kept; not objected to).
4. **Projects folder:** `~/Documents/LaTeX Projects/`.
5. **App name:** **Texora**.

Note: `~` is itself a git repo, so the project has its own repo in `latexEditor/`. I don't commit unless asked.
