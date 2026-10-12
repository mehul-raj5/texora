# Texora: progress log

Read this first when resuming. It's updated after every meaningful step. The plan is in [PLAN.md](PLAN.md).

## Status
- **All milestones M0–M7 built and verified end to end (2026-10-12).** Texora.app is installed in /Applications.
- **Next:**
  - Wait for user feedback.
  - Optional: install TinyTeX (needs the user's OK, since it downloads ~100 MB) for pdfLaTeX speed and full error lists.

## Environment facts (verified 2026-10-12)
- arm64, macOS 27, Xcode 27, Swift 6.4, Node 25, npm 11
- `claude` 2.1.296 at `~/.local/bin/claude`. Tectonic 0.15 at `/opt/homebrew/bin`. No TeX Live / TinyTeX yet.
- No `timeout` command on macOS. Use background process + kill.
- `~` is itself a git repo, so this project has its own `.git`. Don't commit unless the user asks.

## Claude CLI bridge: verified behaviour
Command:
```
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
  --permission-mode acceptEdits --permission-prompts none --strict-mcp-config
  --setting-sources project,local --disable-slash-commands --tools ... --allowedTools ... [--model X] [--resume ID]
```
- **stdin:** one JSON line per user turn: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}`
- **stdout:**
  - `system/init` (has `session_id`, sent each turn), then `system/status`
  - `stream_event`: `content_block_start` / `content_block_delta` (`text_delta`, `input_json_delta`, `thinking_delta`)
  - `assistant`: full message with `text` / `tool_use` blocks
  - `user`: `tool_result`
  - `rate_limit_event`
  - `system/task_summary`: has a friendly "Reading …" detail
  - `system/post_turn_summary`
  - `result` (`subtype` success, `total_cost_usd`, `session_id`)
- **Interrupt:** `{"type":"control_request","request_id":"req_1","request":{"subtype":"interrupt"}}`. Replies `control_response`, emits a `result`, and the process stays alive for the next turn. ✓ tested
- `codemirror-lang-latex` is AGPL, so it's not used. Highlighting comes from `@codemirror/legacy-modes` stex (MIT), plus our own completions and folding.

## Done
- [x] Plan v3 approved (name Texora; decisions in PLAN.md §10)
- [x] git init, folder layout
- [x] M0 scaffold:
  - Package.swift (tools 6.0, Swift 5 mode, macOS 15)
  - 20 themes and ThemeManager (auto/fixed)
  - hidden-titlebar window, sidebar, top bar
  - `scripts/build-app.sh` builds dist/Texora.app, about 1.8 MB
- [x] M1, mostly done:
  - Home screen (greeting, input box, actions, recents) and ProjectsListView
  - collections, NewProjectSheet with 7 templates
  - ZIP import (zip-slip and symlink checks, unwrap), open folder, main-file detection
- [x] Dev automation: launch with `open dist/Texora.app --args --automation`, then `scripts/tx.sh <cmd> [arg]`
  - `snapshot <png>`: in-app window render. Terminal `screencapture` is blocked because there's no Screen Recording permission.

## How to test visually
```
./scripts/build-app.sh && pkill -x Texora; open dist/Texora.app --args --automation
scripts/tx.sh snapshot /path/shot.png
```

## Done (continued, 2026-10-12)
- [x] M2: CodeMirror 6 bundle (`web/` → `Resources/editor/editor.js`, 550 KB)
  - own LaTeX tokenizer, folding, autocomplete (commands/envs/labels/cites/files/packages)
  - Ask pill; ⌘K/⌘L/⌘B/⌘S; ⌘-click → PDF
  - WorkspaceModel: tabs, autosave, FSEvents reload, conflicts; file tree with context menus; outline (follows \input, active section)
- [x] M3: CompileController
  - latexmk (TinyTeX/MacTeX) or Tectonic; auto-install missing packages via TinyTeX tlmgr
  - LogParser (handles Tectonic's `(sections/intro` without extension); SyncTeX parser
  - PDFKit pane: reload-in-place, ⌘-click inverse, highlight forward
  - issues panel, status strip, engine/main-file menus
- [x] M4: ClaudeSession (stream-json) + ChatController
  - streaming, friendly activity lines, chatattachments/, multiple chats, resume, stop, model picker
  - **Verified live:** abstract rewrite → History entry → auto recompile
- [x] M5: Ask Claude popup in the editor. **Verified live:** line 4 of intro.tex rewritten, Undo/Open in chat/Done shown.
- [x] M6 (code written): HistoryService (hidden git in App Support), History tab, DiffView (side by side), restore project/file, per-turn Undo, checkpoints
- [x] M7 (code written): ExportSheet/ExportService, Settings (5 tabs incl. TinyTeX installer), 20 themes + picker
- [x] Security check: Write/Edit NOT allow-listed, so writes outside the project are denied. Tested with CLI: outside write/read denied, inside allowed.

## Test setup (automation)
- Fixtures: `Fixtures/sample-paper` (+ .zip with __MACOSX), `Fixtures/broken-paper`
- Copy them to the scratchpad before importing (avoids Desktop/Documents permission prompts)
- `defaults write app.texora.Texora projectsFolder <scratch>/projects`
- tx commands: open, openProject, openFile, select (ask=1), ask, askPDF, chat, model, compile, dump, snapshot, export, restore, diff, undoLast, theme, layout, tab
- **Reset after testing:** `defaults delete app.texora.Texora projectsFolder; defaults write app.texora.Texora claudeModel ""` (testing used haiku and tectonic)

## Verified live in the built app (automation + snapshots)
- ZIP import (with __MACOSX junk), main-file detection, outline with →, Tectonic compile 12.9 s first run / 1.3 s after
- Chat edit → History → auto recompile; resume after restart; attachments → chatattachments/; Stop interrupts
- Ask popup from the editor (edits exactly the selected line); from the PDF (SyncTeX maps to intro.tex L4)
- Broken project: gutter marker + issues panel + error badge
- Export ZIP contents correct (PDF included, .build and aux excluded)
- Undo of a Claude turn, History timeline, side-by-side Diff sheet
- Themes (Mocha, Latte, GitHub Light, Tokyo Night), Home with recents, IEEE template project, Settings window
- `swift test`: 21 tests pass, including a real Tectonic SyncTeX round trip

## Cleanup done
Test projects/chats/history removed from App Support. Test defaults (haiku, tectonic, scratch projects folder) deleted.

## Known issues / leftovers
- Tectonic stops at the first error, so only one error is listed. pdfLaTeX via TinyTeX lists all of them.
- Spell-check is off by default (the browser spell-checker would flag LaTeX commands). A native LaTeX-aware spell-checker is a possible follow-up.
- Snapshots in automation mode can't capture the native theme popover (fine in the real UI).
- Each test chat left a Claude Code session transcript under ~/.claude/projects/ (harmless).
