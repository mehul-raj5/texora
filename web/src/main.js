// Texora editor: CodeMirror 6 embedded in a WKWebView. Talks to Swift through
// window.webkit.messageHandlers.texora (JS → Swift) and window.texora (Swift → JS).
import { EditorState, Compartment, Annotation, StateEffect, StateField, EditorSelection } from "@codemirror/state";
import {
  EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter,
  highlightSpecialChars, drawSelection, dropCursor, rectangularSelection, crosshairCursor,
  Decoration, ViewPlugin,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab, toggleComment } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches, search, openSearchPanel } from "@codemirror/search";
import { autocompletion, completionKeymap, closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { syntaxHighlighting, bracketMatching, foldGutter, foldKeymap, indentOnInput } from "@codemirror/language";
import { setDiagnostics, lintGutter, lintKeymap } from "@codemirror/lint";
import { vim } from "@replit/codemirror-vim";
import { latexLanguage, latexHighlight, latexFolding, latexIndent } from "./latex.js";
import { latexCompletions, projectData } from "./completions.js";

const External = Annotation.define();

function post(msg) {
  try { window.webkit.messageHandlers.texora.postMessage(msg); } catch (e) { console.log("post", msg); }
}

// ---- Flash highlight (used after Claude edits or jumps) ------------------------------------

const flashEffect = StateEffect.define();
const clearFlashEffect = StateEffect.define();
const flashField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (e.is(flashEffect)) {
        const marks = [];
        for (let n = e.value.from; n <= e.value.to; n++) {
          if (n < 1 || n > tr.state.doc.lines) continue;
          marks.push(Decoration.line({ class: "tx-flash" }).range(tr.state.doc.line(n).from));
        }
        deco = Decoration.set(marks, true);
      }
      if (e.is(clearFlashEffect)) deco = Decoration.none;
    }
    return deco;
  },
  provide: f => EditorView.decorations.from(f),
});

// ---- Compartments ---------------------------------------------------------------------------

const vimC = new Compartment();
const wrapC = new Compartment();
const themeC = new Compartment();
const readOnlyC = new Compartment();
const spellC = new Compartment();

let options = { fontSize: 14, wrap: true, vim: false, dark: true, spell: false };

function baseTheme(dark) {
  return EditorView.theme({
    "&": { height: "100%", backgroundColor: "var(--bg)", color: "var(--text)" },
    ".cm-scroller": { fontFamily: "var(--mono)", lineHeight: "1.62", fontSize: "var(--font-size)" },
    ".cm-content": { caretColor: "var(--accent)", padding: "14px 0 40vh 0" },
    ".cm-line": { padding: "0 16px 0 6px" },
    ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--accent)", borderLeftWidth: "2px" },
    ".cm-gutters": { backgroundColor: "var(--bg)", color: "var(--text-muted)", border: "none", paddingLeft: "8px" },
    ".cm-lineNumbers .cm-gutterElement": { minWidth: "32px", padding: "0 6px 0 0", fontSize: "0.86em" },
    ".cm-activeLine": { backgroundColor: "var(--hover)" },
    ".cm-activeLineGutter": { backgroundColor: "transparent", color: "var(--text-secondary)" },
    "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection":
      { backgroundColor: "color-mix(in srgb, var(--accent) 30%, transparent) !important" },
    ".cm-selectionMatch": { backgroundColor: "color-mix(in srgb, var(--accent) 14%, transparent)" },
    "&.cm-focused .cm-matchingBracket": { backgroundColor: "color-mix(in srgb, var(--accent) 22%, transparent)", outline: "none" },
    ".cm-nonmatchingBracket": { color: "var(--danger)" },
    ".cm-foldGutter .cm-gutterElement": { color: "var(--text-muted)", padding: "0 4px", cursor: "pointer" },
    ".cm-foldPlaceholder": { backgroundColor: "var(--surface)", border: "1px solid var(--border)", color: "var(--text-secondary)", borderRadius: "5px", padding: "0 6px", margin: "0 4px" },
    ".cm-tooltip": { backgroundColor: "var(--elevated)", border: "1px solid var(--border)", borderRadius: "9px", color: "var(--text)", boxShadow: "0 8px 30px rgba(0,0,0,0.25)", overflow: "hidden" },
    ".cm-tooltip-autocomplete > ul": { fontFamily: "var(--mono)", fontSize: "calc(var(--font-size) * 0.93)", maxHeight: "18em" },
    ".cm-tooltip-autocomplete > ul > li": { padding: "3px 10px !important", lineHeight: "1.5" },
    ".cm-tooltip-autocomplete > ul > li[aria-selected]": { backgroundColor: "var(--selection)", color: "var(--text)" },
    ".cm-completionDetail": { color: "var(--text-muted)", fontStyle: "normal", marginLeft: "1.2em", fontFamily: "var(--ui)" },
    ".cm-completionMatchedText": { textDecoration: "none", color: "var(--accent)", fontWeight: "600" },
    ".cm-completionInfo": { backgroundColor: "var(--elevated)", border: "1px solid var(--border)", borderRadius: "8px", padding: "8px 10px", fontFamily: "var(--ui)", maxWidth: "340px" },
    ".cm-panels": { backgroundColor: "var(--sidebar)", color: "var(--text)", borderColor: "var(--border) !important" },
    ".cm-panels-top": { borderBottom: "1px solid var(--border)" },
    ".cm-search": { fontFamily: "var(--ui)", fontSize: "13px", padding: "8px 10px" },
    ".cm-search input, .cm-search button, .cm-textfield": { backgroundColor: "var(--surface)", color: "var(--text)", border: "1px solid var(--border)", borderRadius: "6px", padding: "3px 8px", fontFamily: "var(--ui)" },
    ".cm-search button:hover": { backgroundColor: "var(--elevated)" },
    ".cm-search label": { color: "var(--text-secondary)" },
    ".cm-button": { backgroundImage: "none" },
    ".cm-searchMatch": { backgroundColor: "color-mix(in srgb, var(--warning) 30%, transparent)", outline: "1px solid color-mix(in srgb, var(--warning) 60%, transparent)" },
    ".cm-searchMatch-selected": { backgroundColor: "color-mix(in srgb, var(--accent) 40%, transparent)" },
    ".cm-lintRange-error": { backgroundImage: "none", textDecoration: "underline wavy var(--danger)", textUnderlineOffset: "3px" },
    ".cm-lintRange-warning": { backgroundImage: "none", textDecoration: "underline wavy var(--warning)", textUnderlineOffset: "3px" },
    ".cm-lint-marker": { width: "0.8em", height: "0.8em" },
    ".cm-diagnostic": { fontFamily: "var(--ui)", padding: "6px 10px", borderLeftWidth: "3px" },
    ".cm-diagnostic-error": { borderLeftColor: "var(--danger)" },
    ".cm-diagnostic-warning": { borderLeftColor: "var(--warning)" },
    ".tx-flash": { animation: "tx-flash 1.8s ease-out" },
    ".cm-fat-cursor": { background: "color-mix(in srgb, var(--accent) 60%, transparent) !important" },
    ".cm-vim-panel": { fontFamily: "var(--mono)", padding: "2px 10px" },
  }, { dark });
}

// ---- Documents ------------------------------------------------------------------------------

const states = new Map();   // path → EditorState
const dirty = new Set();    // paths edited since last collect
let currentPath = null;
let view = null;
let changeTimer = null;
let cursorTimer = null;

function extensions() {
  return [
    vimC.of(options.vim ? vim() : []),
    lineNumbers(),
    foldGutter({ markerDOM: open => { const s = document.createElement("span"); s.className = "tx-fold" + (open ? "" : " closed"); s.textContent = "›"; return s; } }),
    lintGutter(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    EditorView.clickAddsSelectionRange.of(e => e.altKey),
    indentOnInput(),
    latexLanguage,
    latexIndent,
    latexFolding,
    syntaxHighlighting(latexHighlight),
    bracketMatching(),
    closeBrackets(),
    autocompletion({ override: [latexCompletions], icons: false, activateOnTypingDelay: 60, maxRenderedOptions: 80 }),
    rectangularSelection(),
    crosshairCursor({ key: "Alt" }),
    highlightActiveLine(),
    highlightSelectionMatches({ minSelectionLength: 3 }),
    search({ top: true }),
    flashField,
    wrapC.of(options.wrap ? EditorView.lineWrapping : []),
    themeC.of(baseTheme(options.dark)),
    readOnlyC.of([]),
    spellC.of(EditorView.contentAttributes.of({ spellcheck: options.spell ? "true" : "false", autocorrect: "off", autocapitalize: "off" })),
    keymap.of([
      { key: "Mod-s", run: () => { requestSave(); return true; } },
      { key: "Mod-b", run: () => { flushChanges(); post({ type: "command", name: "compile" }); return true; } },
      { key: "Mod-Enter", run: () => { flushChanges(); post({ type: "command", name: "compile" }); return true; } },
      { key: "Mod-k", run: () => { askClaude(); return true; } },
      { key: "Mod-l", run: () => { sendSelectionToChat(); return true; } },
      { key: "Mod-/", run: toggleComment },
      { key: "Mod-i", run: v => wrapSelection(v, "\\textit{", "}") },
      { key: "Mod-Shift-b", run: v => wrapSelection(v, "\\textbf{", "}") },
      { key: "Mod-f", run: openSearchPanel },
      ...closeBracketsKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
      ...lintKeymap,
      indentWithTab,
    ]),
    EditorView.domEventHandlers({
      mousedown(e, v) {
        if (e.metaKey && !e.altKey) {
          const pos = v.posAtCoords({ x: e.clientX, y: e.clientY });
          if (pos != null) {
            const line = v.state.doc.lineAt(pos).number;
            post({ type: "syncToPdf", path: currentPath, line, column: pos - v.state.doc.lineAt(pos).from });
          }
          e.preventDefault();
          return true;
        }
        hidePill();
        return false;
      },
      mouseup() { setTimeout(maybeShowPill, 10); return false; },
      scroll() { positionPill(); return false; },
    }),
    EditorView.updateListener.of(update => {
      if (update.docChanged) {
        const external = update.transactions.some(tr => tr.annotation(External));
        if (!external) {
          dirty.add(currentPath);
          clearTimeout(changeTimer);
          changeTimer = setTimeout(flushChanges, 180);
        }
      }
      if (update.selectionSet || update.docChanged) {
        clearTimeout(cursorTimer);
        cursorTimer = setTimeout(reportCursor, 90);
        if (update.selectionSet && !update.view.state.selection.main.empty) {
          clearTimeout(pillTimer);
          pillTimer = setTimeout(maybeShowPill, 380);
        } else if (update.view.state.selection.main.empty) {
          hidePill();
        }
      }
      if (update.geometryChanged || update.viewportChanged) positionPill();
    }),
  ];
}

function wrapSelection(v, before, after) {
  v.dispatch(v.state.changeByRange(range => ({
    changes: [{ from: range.from, insert: before }, { from: range.to, insert: after }],
    range: EditorSelection.range(range.from + before.length, range.to + before.length),
  })));
  return true;
}

function flushChanges() {
  clearTimeout(changeTimer);
  if (!view || !currentPath) return;
  states.set(currentPath, view.state);
  for (const p of dirty) {
    const st = p === currentPath ? view.state : states.get(p);
    if (st) post({ type: "change", path: p, text: st.doc.toString() });
  }
  dirty.clear();
}

function requestSave() {
  flushChanges();
  post({ type: "command", name: "save" });
}

function selectionInfo() {
  if (!view) return null;
  const sel = view.state.selection.main;
  const doc = view.state.doc;
  const fromLine = doc.lineAt(sel.from).number;
  const toLine = doc.lineAt(sel.to).number;
  const a = view.coordsAtPos(sel.from), b = view.coordsAtPos(sel.to);
  let rect = null;
  if (a && b) {
    const left = Math.min(a.left, b.left), right = Math.max(a.right, b.right);
    rect = { x: left, y: a.top, width: Math.max(right - left, 2), height: b.bottom - a.top };
    if (fromLine !== toLine) { rect.x = view.contentDOM.getBoundingClientRect().left; rect.width = view.contentDOM.clientWidth; }
  }
  return {
    path: currentPath, from: sel.from, to: sel.to, fromLine, toLine,
    text: doc.sliceString(sel.from, sel.to), rect,
  };
}

function reportCursor() {
  const info = selectionInfo();
  if (!info) return;
  const line = view.state.doc.lineAt(view.state.selection.main.head);
  post({ type: "cursor", path: info.path, line: line.number, column: view.state.selection.main.head - line.from,
    fromLine: info.fromLine, toLine: info.toLine, selText: info.text.length > 20000 ? info.text.slice(0, 20000) : info.text });
}

function askClaude() {
  const info = selectionInfo();
  if (!info) return;
  hidePill();
  if (!info.text.trim()) {
    // No selection: use the current line.
    const line = view.state.doc.lineAt(view.state.selection.main.head);
    view.dispatch({ selection: { anchor: line.from, head: line.to } });
    const again = selectionInfo();
    post({ type: "askClaude", ...again });
    return;
  }
  post({ type: "askClaude", ...info });
}

function sendSelectionToChat() {
  const info = selectionInfo();
  if (info) post({ type: "sendToChat", ...info });
}

// ---- "Ask Claude" pill shown next to a selection -------------------------------------------

let pill = null;
let pillTimer = null;

function ensurePill() {
  if (pill) return pill;
  pill = document.createElement("button");
  pill.className = "tx-pill";
  pill.innerHTML = '<span class="tx-spark">✦</span> Ask Claude <span class="tx-kbd">⌘K</span>';
  pill.addEventListener("mousedown", e => { e.preventDefault(); e.stopPropagation(); });
  pill.addEventListener("click", e => { e.preventDefault(); askClaude(); });
  document.body.appendChild(pill);
  return pill;
}

function maybeShowPill() {
  if (!view) return;
  const sel = view.state.selection.main;
  if (sel.empty || view.state.sliceDoc(sel.from, sel.to).trim().length < 2) { hidePill(); return; }
  ensurePill().classList.add("visible");
  positionPill();
}

function positionPill() {
  if (!pill || !pill.classList.contains("visible") || !view) return;
  const sel = view.state.selection.main;
  const end = view.coordsAtPos(sel.head === sel.from ? sel.from : sel.to);
  if (!end) { pill.style.opacity = "0"; return; }
  const scroller = view.scrollDOM.getBoundingClientRect();
  let top = end.bottom + 8;
  if (top > scroller.bottom - 40) top = end.top - 38;
  let left = Math.min(end.left - 20, window.innerWidth - pill.offsetWidth - 12);
  left = Math.max(left, scroller.left + 8);
  const visible = end.bottom > scroller.top && end.top < scroller.bottom;
  pill.style.opacity = visible ? "1" : "0";
  pill.style.pointerEvents = visible ? "auto" : "none";
  pill.style.top = `${top}px`;
  pill.style.left = `${left}px`;
}

function hidePill() {
  clearTimeout(pillTimer);
  if (pill) pill.classList.remove("visible");
}

// ---- Swift → JS API -----------------------------------------------------------------------

function makeState(text) {
  return EditorState.create({ doc: text, extensions: extensions() });
}

function minimalChange(oldText, newText) {
  let start = 0;
  const minLen = Math.min(oldText.length, newText.length);
  while (start < minLen && oldText.charCodeAt(start) === newText.charCodeAt(start)) start++;
  let endOld = oldText.length, endNew = newText.length;
  while (endOld > start && endNew > start && oldText.charCodeAt(endOld - 1) === newText.charCodeAt(endNew - 1)) { endOld--; endNew--; }
  return { from: start, to: endOld, insert: newText.slice(start, endNew) };
}

window.texora = {
  init(opts) {
    options = { ...options, ...opts };
    applyCSSOptions();
    view = new EditorView({ state: makeState(""), parent: document.getElementById("editor") });
    view.dom.style.visibility = "hidden";
    post({ type: "ready" });
  },

  /** Shows a document. Creates its state on first open; keeps undo history per file. */
  open(path, text, line) {
    if (!view) return;
    if (currentPath && currentPath !== path) states.set(currentPath, view.state);
    let st = states.get(path);
    if (!st) { st = makeState(text); states.set(path, st); }
    else if (text != null && st.doc.toString() !== text && !dirty.has(path)) {
      // Disk changed while the tab was in the background.
      st = st.update({ changes: minimalChange(st.doc.toString(), text), annotations: External.of(true) }).state;
      states.set(path, st);
    }
    currentPath = path;
    view.setState(st);
    syncCompartments();
    view.dom.style.visibility = "visible";
    if (line) this.reveal(line, line);
    hidePill();
    reportCursor();
  },

  /** Replaces a document's text from outside (disk change, Claude edit), keeping the cursor. */
  setText(path, text, flash) {
    if (path === currentPath && view) {
      const old = view.state.doc.toString();
      if (old === text) return;
      const ch = minimalChange(old, text);
      view.dispatch({ changes: ch, annotations: External.of(true) });
      states.set(path, view.state);
      if (flash) {
        const doc = view.state.doc;
        const fromLine = doc.lineAt(Math.min(ch.from, doc.length)).number;
        const toLine = doc.lineAt(Math.min(ch.from + ch.insert.length, doc.length)).number;
        this.flash(fromLine, toLine, true);
      }
    } else if (states.has(path)) {
      const st = states.get(path);
      states.set(path, st.update({ changes: minimalChange(st.doc.toString(), text), annotations: External.of(true) }).state);
    }
    dirty.delete(path);
  },

  close(path) {
    states.delete(path);
    dirty.delete(path);
    if (path === currentPath) { currentPath = null; view.dom.style.visibility = "hidden"; }
  },

  rename(oldPath, newPath) {
    if (states.has(oldPath)) { states.set(newPath, states.get(oldPath)); states.delete(oldPath); }
    if (currentPath === oldPath) currentPath = newPath;
  },

  /** Returns {path: text} for every document edited since the last collect. */
  collect() {
    clearTimeout(changeTimer);
    if (view && currentPath) states.set(currentPath, view.state);
    const out = {};
    for (const p of dirty) { const st = states.get(p); if (st) out[p] = st.doc.toString(); }
    dirty.clear();
    return out;
  },

  getText(path) {
    const st = path === currentPath ? view.state : states.get(path);
    return st ? st.doc.toString() : null;
  },

  reveal(fromLine, toLine, select) {
    if (!view) return;
    const doc = view.state.doc;
    const a = doc.line(Math.max(1, Math.min(fromLine, doc.lines)));
    const b = doc.line(Math.max(1, Math.min(toLine || fromLine, doc.lines)));
    view.dispatch({
      selection: select ? { anchor: a.from, head: b.to } : { anchor: a.from },
      effects: EditorView.scrollIntoView(a.from, { y: "center" }),
    });
    this.flash(a.number, b.number, false);
    view.focus();
  },

  flash(fromLine, toLine) {
    if (!view) return;
    view.dispatch({ effects: flashEffect.of({ from: fromLine, to: toLine }) });
    setTimeout(() => view && view.dispatch({ effects: clearFlashEffect.of(null) }), 1900);
  },

  setTheme(vars, dark) {
    const root = document.documentElement;
    for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v);
    root.style.colorScheme = dark ? "dark" : "light";
    if (options.dark !== dark) {
      options.dark = dark;
      if (view) view.dispatch({ effects: themeC.reconfigure(baseTheme(dark)) });
      refreshAllStates();
    }
  },

  setOptions(opts) {
    const prev = options;
    options = { ...options, ...opts };
    applyCSSOptions();
    if (!view) return;
    const effects = [];
    if (prev.wrap !== options.wrap) effects.push(wrapC.reconfigure(options.wrap ? EditorView.lineWrapping : []));
    if (prev.vim !== options.vim) effects.push(vimC.reconfigure(options.vim ? vim() : []));
    if (prev.spell !== options.spell) effects.push(spellC.reconfigure(EditorView.contentAttributes.of({ spellcheck: options.spell ? "true" : "false", autocorrect: "off", autocapitalize: "off" })));
    if (effects.length) { view.dispatch({ effects }); refreshAllStates(); }
    view.requestMeasure();
  },

  setReadOnly(ro) {
    if (view) view.dispatch({ effects: readOnlyC.reconfigure(ro ? EditorState.readOnly.of(true) : []) });
  },

  setCompletions(data) {
    Object.assign(projectData, data);
  },

  /** diagnostics: [{line, severity, message}] for the current file. */
  setDiagnostics(path, diags) {
    if (!view || path !== currentPath) return;
    const doc = view.state.doc;
    const list = diags.filter(d => d.line >= 1 && d.line <= doc.lines).map(d => {
      const l = doc.line(d.line);
      const text = l.text;
      const firstNonSpace = text.search(/\S/);
      return { from: l.from + Math.max(0, firstNonSpace), to: l.to, severity: d.severity, message: d.message };
    });
    view.dispatch(setDiagnostics(view.state, list));
  },

  insert(text) {
    if (!view) return;
    view.dispatch(view.state.replaceSelection(text));
    view.focus();
  },

  focus() { if (view) view.focus(); },

  selection() { return selectionInfo(); },

  hidePill() { hidePill(); },
};

/** Background documents keep their own undo history; options are re-applied when they are shown. */
function refreshAllStates() {}

function syncCompartments() {
  if (!view) return;
  view.dispatch({ effects: [
    themeC.reconfigure(baseTheme(options.dark)),
    wrapC.reconfigure(options.wrap ? EditorView.lineWrapping : []),
    vimC.reconfigure(options.vim ? vim() : []),
    spellC.reconfigure(EditorView.contentAttributes.of({ spellcheck: options.spell ? "true" : "false", autocorrect: "off", autocapitalize: "off" })),
  ] });
}

function applyCSSOptions() {
  document.documentElement.style.setProperty("--font-size", `${options.fontSize}px`);
}

window.addEventListener("resize", positionPill);
