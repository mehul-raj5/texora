// LaTeX language support for CodeMirror 6: tokenizer, highlighting, folding and comment tokens.
import { StreamLanguage, HighlightStyle, foldService, indentUnit } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

const MATH_ENVS = new Set([
  "equation", "equation*", "align", "align*", "gather", "gather*", "multline", "multline*",
  "eqnarray", "eqnarray*", "displaymath", "math", "flalign", "flalign*", "alignat", "alignat*",
  "dmath", "dmath*",
]);
const SECTION_CMDS = new Set([
  "part", "part*", "chapter", "chapter*", "section", "section*", "subsection", "subsection*",
  "subsubsection", "subsubsection*", "paragraph", "paragraph*", "subparagraph", "title", "caption",
]);
const REF_CMDS = new Set([
  "label", "ref", "eqref", "pageref", "autoref", "cref", "Cref", "nameref", "vref",
  "cite", "citep", "citet", "citeauthor", "citeyear", "nocite", "parencite", "textcite",
  "autocite", "footcite", "Cite", "Citep", "Citet", "citealp", "citealt",
]);
const FILE_CMDS = new Set([
  "input", "include", "includegraphics", "bibliography", "addbibresource", "includeonly",
  "subfile", "import", "includepdf", "lstinputlisting",
]);
const PKG_CMDS = new Set([
  "usepackage", "documentclass", "RequirePackage", "LoadClass", "usetheme", "usecolortheme",
  "usefonttheme", "useinnertheme", "useoutertheme", "bibliographystyle",
]);
const KEYWORD_CMDS = new Set(["begin", "end", "item", "maketitle", "newcommand", "renewcommand", "def", "let"]);

function startState() {
  return {
    math: null,        // closing delimiter while in math: "$", "$$", "\\)", "\\]" or "env:<name>"
    pending: null,     // style for the next {...} argument: "env", "ref", "file", "pkg", "heading"
    argStyle: null,    // style applied to text inside the current special argument
    argDepth: 0,
    beginEnv: false,   // the pending argument belongs to \begin (to detect math environments)
    endEnv: false,
    inOptional: false, // inside [..] before a special argument
    argName: "",
  };
}

function copyState(s) {
  return { ...s };
}

function token(stream, state) {
  // Comments always win.
  if (stream.peek() === "%" ) {
    stream.skipToEnd();
    return "comment";
  }

  // Inside a special argument such as {figure}, {sec:intro} or {Introduction}.
  if (state.argStyle) {
    const ch = stream.peek();
    if (ch === "{") { stream.next(); state.argDepth++; return "bracket"; }
    if (ch === "}") {
      stream.next();
      if (state.argDepth > 0) { state.argDepth--; return "bracket"; }
      const name = state.argName || "";
      const wasBegin = state.beginEnv, wasEnd = state.endEnv;
      state.argStyle = null; state.argName = ""; state.beginEnv = false; state.endEnv = false;
      if (wasBegin && MATH_ENVS.has(name)) state.math = "env:" + name;
      if (wasEnd && state.math === "env:" + name) state.math = null;
      return "bracket";
    }
    if (state.argStyle === "heading") {
      // Headings may contain commands and math; tokenize those normally.
      if (ch === "\\") return tokenCommand(stream, state);
      if (ch === "$") { stream.next(); stream.match(/^[^$]*\$?/); return "math"; }
      stream.match(/^[^\\{}$%]+/) || stream.next();
      return "heading";
    }
    const m = stream.match(/^[^{}%]+/);
    if (m) { state.argName = (state.argName || "") + m[0]; return state.argStyle; }
    stream.next();
    return state.argStyle;
  }

  // Inside an optional [..] argument that precedes a special {..} argument.
  if (state.inOptional) {
    if (stream.peek() === "]") { stream.next(); state.inOptional = false; return "bracket"; }
    if (stream.peek() === "\\") return tokenCommand(stream, state);
    stream.match(/^[^\]\\%]+/) || stream.next();
    return null;
  }

  // A special argument may start after optional [..] arguments and spaces.
  if (state.pending) {
    if (stream.eatSpace()) return null;
    if (stream.peek() === "[") {
      stream.next();
      state.inOptional = true;
      return "bracket";
    }
    if (stream.peek() === "{") {
      stream.next();
      state.argStyle = state.pending;
      state.pending = null;
      state.argDepth = 0;
      state.argName = "";
      return "bracket";
    }
    if (stream.peek() !== "]") {
      state.pending = null; state.beginEnv = false; state.endEnv = false;
    }
  }

  if (state.math) return tokenMath(stream, state);

  const ch = stream.peek();
  if (ch === "\\") return tokenCommand(stream, state);
  if (ch === "$") {
    if (stream.match("$$")) { state.math = "$$"; return "mathDelim"; }
    stream.next(); state.math = "$"; return "mathDelim";
  }
  if (ch === "{" || ch === "}" || ch === "[" || ch === "]") { stream.next(); return "bracket"; }
  if (ch === "&" || ch === "~") { stream.next(); return "punct"; }
  if (stream.match(/^[^\\${}\[\]%&~]+/)) return null;
  stream.next();
  return null;
}

function tokenCommand(stream, state) {
  stream.next(); // backslash
  if (stream.match(/^[a-zA-Z@]+\*?/)) {
    const name = stream.current().slice(1);
    const bare = name.replace(/\*$/, "");
    if (bare === "begin" || bare === "end") {
      state.pending = "env";
      state.beginEnv = bare === "begin";
      state.endEnv = bare === "end";
      return "keyword";
    }
    if (SECTION_CMDS.has(name)) { state.pending = "heading"; return "keyword"; }
    if (REF_CMDS.has(bare)) { state.pending = "ref"; return "command"; }
    if (FILE_CMDS.has(bare)) { state.pending = "file"; return "command"; }
    if (PKG_CMDS.has(bare)) { state.pending = "pkg"; return "command"; }
    if (KEYWORD_CMDS.has(bare)) return "keyword";
    return state.math ? "mathCommand" : "command";
  }
  if (stream.match("(")) { state.math = "\\)"; return "mathDelim"; }
  if (stream.match("[")) { state.math = "\\]"; return "mathDelim"; }
  if (state.math === "\\)" && stream.match(")")) { state.math = null; return "mathDelim"; }
  if (state.math === "\\]" && stream.match("]")) { state.math = null; return "mathDelim"; }
  stream.next(); // escaped char such as \% \$ \\ \,
  return state.math ? "mathCommand" : "command";
}

function tokenMath(stream, state) {
  const end = state.math;
  if (end === "$$" && stream.match("$$")) { state.math = null; return "mathDelim"; }
  if (end === "$" && stream.match("$")) { state.math = null; return "mathDelim"; }
  const ch = stream.peek();
  if (ch === "\\") {
    if (end.startsWith("env:") && stream.match(/^\\end\b/, false)) {
      stream.match(/^\\end/);
      state.pending = "env"; state.endEnv = true;
      return "keyword";
    }
    return tokenCommand(stream, state);
  }
  if (ch === "{" || ch === "}" || ch === "[" || ch === "]") { stream.next(); return "mathBracket"; }
  if (ch === "&") { stream.next(); return "punct"; }
  if (stream.match(/^[0-9]+(\.[0-9]+)?/)) return "number";
  if (stream.match(/^[^\\${}\[\]%&0-9]+/)) return "math";
  stream.next();
  return "math";
}

export const latexLanguage = StreamLanguage.define({
  name: "latex",
  startState,
  copyState,
  token,
  blankLine(state) {
    // A blank line ends inline math (TeX would error anyway); keeps highlighting sane while typing.
    if (state.math === "$") state.math = null;
  },
  languageData: {
    commentTokens: { line: "%" },
    closeBrackets: { brackets: ["(", "[", "{", "$"] },
    indentOnInput: /^\s*\\end\{[^}]*\}$/,
  },
  tokenTable: {
    command: t.macroName,
    keyword: t.keyword,
    env: t.typeName,
    ref: t.labelName,
    file: t.url,
    pkg: t.namespace,
    heading: t.heading,
    math: t.special(t.string),
    mathCommand: t.special(t.macroName),
    mathDelim: t.processingInstruction,
    mathBracket: t.special(t.bracket),
    bracket: t.bracket,
    punct: t.punctuation,
    number: t.number,
    comment: t.comment,
  },
});

export const latexHighlight = HighlightStyle.define([
  { tag: t.macroName, color: "var(--syn-command)" },
  { tag: t.keyword, color: "var(--syn-keyword)", fontWeight: "500" },
  { tag: t.typeName, color: "var(--syn-env)" },
  { tag: t.labelName, color: "var(--syn-string)" },
  { tag: t.url, color: "var(--syn-string)" },
  { tag: t.namespace, color: "var(--syn-env)" },
  { tag: t.heading, color: "var(--text)", fontWeight: "650" },
  { tag: t.special(t.string), color: "var(--syn-math)" },
  { tag: t.special(t.macroName), color: "var(--syn-math)", fontWeight: "500" },
  { tag: t.processingInstruction, color: "var(--syn-math)", fontWeight: "600" },
  { tag: t.special(t.bracket), color: "var(--syn-math)" },
  { tag: t.bracket, color: "var(--syn-bracket)" },
  { tag: t.punctuation, color: "var(--syn-number)" },
  { tag: t.number, color: "var(--syn-number)" },
  { tag: t.comment, color: "var(--syn-comment)", fontStyle: "italic" },
]);

// ---- Folding: \begin…\end blocks and sections -------------------------------------------

const SECTION_LEVEL = {
  part: 0, chapter: 1, section: 2, subsection: 3, subsubsection: 4, paragraph: 5, subparagraph: 6,
};

function sectionLevel(text) {
  const m = /^\s*\\(part|chapter|section|subsection|subsubsection|paragraph|subparagraph)\*?\s*[\[{]/.exec(text);
  return m ? SECTION_LEVEL[m[1]] : -1;
}

export const latexFolding = foldService.of((state, lineStart, lineEnd) => {
  const line = state.doc.lineAt(lineStart);
  const text = line.text;

  const begin = /\\begin\{([^}]+)\}/.exec(text);
  if (begin && !/^\s*%/.test(text)) {
    const env = begin[1];
    const endRe = new RegExp("\\\\(begin|end)\\{" + env.replace(/[*]/g, "\\*") + "\\}", "g");
    let depth = 0;
    for (let n = line.number; n <= state.doc.lines; n++) {
      const l = state.doc.line(n);
      const s = n === line.number ? l.text.slice(begin.index) : l.text;
      endRe.lastIndex = 0;
      let m;
      while ((m = endRe.exec(s))) {
        depth += m[1] === "begin" ? 1 : -1;
        if (depth === 0) {
          if (n === line.number) return null;
          return { from: line.to, to: state.doc.line(n).from + (n === line.number ? 0 : l.text.indexOf("\\end")) };
        }
      }
      if (n - line.number > 5000) break;
    }
    return null;
  }

  const level = sectionLevel(text);
  if (level >= 0) {
    let lastContent = line.number;
    for (let n = line.number + 1; n <= state.doc.lines; n++) {
      const l = state.doc.line(n);
      const lv = sectionLevel(l.text);
      if ((lv >= 0 && lv <= level) || /^\s*\\end\{document\}/.test(l.text) || /^\s*\\(bibliography|appendix)\b/.test(l.text)) break;
      if (l.text.trim() !== "") lastContent = n;
    }
    if (lastContent > line.number) return { from: line.to, to: state.doc.line(lastContent).to };
  }
  return null;
});

export const latexIndent = indentUnit.of("  ");
