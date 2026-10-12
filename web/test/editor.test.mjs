// Tests for the CodeMirror LaTeX support: tokenizer, completions, snippets and folding.
import { test } from "node:test";
import assert from "node:assert/strict";
import { EditorState } from "@codemirror/state";
import { ensureSyntaxTree, foldable } from "@codemirror/language";
import { CompletionContext } from "@codemirror/autocomplete";
import { latexLanguage, latexFolding } from "../src/latex.js";
import { latexCompletions, projectData } from "../src/completions.js";

function stateFor(doc) {
  return EditorState.create({ doc, extensions: [latexLanguage, latexFolding] });
}

/** Returns [tokenName, text] pairs for highlighted spans. */
function tokens(doc) {
  const state = stateFor(doc);
  const tree = ensureSyntaxTree(state, doc.length, 5000);
  const out = [];
  tree.iterate({
    enter(n) {
      if (n.from < n.to && n.node.parent) out.push([n.type.name, doc.slice(n.from, n.to)]);
    },
  });
  return out;
}

const has = (toks, name, text) => toks.some(([n, t]) => n === name && t === text);

test("commands, environments and headings", () => {
  const t = tokens("\\section{Intro}\n\\begin{itemize}\n\\item text \\textbf{bold}\n\\end{itemize}");
  assert.ok(has(t, "keyword", "\\section"));
  assert.ok(has(t, "heading", "Intro"));
  assert.ok(has(t, "keyword", "\\begin"));
  assert.ok(has(t, "env", "itemize"));
  assert.ok(has(t, "command", "\\textbf"));
});

test("labels, references, citations, packages and files", () => {
  const t = tokens("\\label{sec:a} \\ref{sec:a} \\cite{knuth} \\usepackage[x]{amsmath} \\input{sec/b}");
  assert.ok(has(t, "ref", "sec:a"));
  assert.ok(has(t, "ref", "knuth"));
  assert.ok(has(t, "pkg", "amsmath"));
  assert.ok(has(t, "file", "sec/b"));
});

test("inline and display math, including math environments", () => {
  const t = tokens("Let $x^2$ and \\[ y \\] then\n\\begin{equation}\na = b\n\\end{equation}\nafter");
  assert.ok(has(t, "mathDelim", "$"));
  assert.ok(t.some(([n, s]) => n === "math" && s.includes("x")));
  assert.ok(has(t, "mathDelim", "\\["));
  assert.ok(t.some(([n, s]) => n === "math" && s.includes("a = b")), "equation body is math");
  // Math state ends with \end{equation}: 'after' is plain text, not math.
  assert.ok(!t.some(([n, s]) => n === "math" && s.includes("after")));
});

test("comments and escaped percent signs", () => {
  const t = tokens("50\\% done % a comment");
  assert.ok(has(t, "comment", "% a comment"));
  assert.ok(!t.some(([n, s]) => n === "comment" && s.includes("50")));
});

function complete(doc, explicit = false) {
  return latexCompletions(new CompletionContext(stateFor(doc), doc.length, explicit));
}

test("completes commands after a backslash", () => {
  const r = complete("Text \\tex");
  assert.ok(r);
  assert.equal(r.from, 5);
  assert.ok(r.options.some(o => o.label === "\\textbf"));
});

test("completes labels inside \\ref and citations inside \\cite with multiple keys", () => {
  projectData.labels = [{ label: "sec:intro", file: "main.tex", line: 3 }];
  projectData.cites = [{ key: "knuth1984", title: "The TeXbook", author: "Knuth", year: "1984" }];
  const ref = complete("See \\ref{se");
  assert.deepEqual(ref.options.map(o => o.label), ["sec:intro"]);
  assert.equal(ref.from, "See \\ref{".length);
  const cite = complete("\\citep[p.~3]{lamport, kn");
  assert.deepEqual(cite.options.map(o => o.label), ["knuth1984"]);
  assert.equal(cite.from, "\\citep[p.~3]{lamport, ".length);
  assert.equal(cite.options[0].detail, "Knuth, 1984");
});

test("completes environments, packages and files by type", () => {
  projectData.files = ["figs/a.png", "sec/b.tex", "refs.bib", "data.csv"];
  assert.ok(complete("\\begin{fig").options.some(o => o.label === "figure"));
  assert.ok(complete("\\usepackage{ams").options.some(o => o.label === "amsmath"));
  assert.deepEqual(complete("\\includegraphics[width=1cm]{").options.map(o => o.label), ["figs/a.png"]);
  const input = complete("\\input{");
  assert.deepEqual(input.options.map(o => o.label), ["sec/b.tex"]);
  assert.equal(input.options[0].apply, "sec/b", "\\input completes without the .tex extension");
  assert.deepEqual(complete("\\bibliography{").options.map(o => o.apply), ["refs"]);
});

test("no completion in plain text unless explicitly requested", () => {
  assert.equal(complete("plain words"), null);
});

test("environment snippets produce valid LaTeX line breaks", async () => {
  const { snippet } = await import("@codemirror/autocomplete");
  const r = complete("\\begin{tab");
  const table = r.options.find(o => o.label === "table");
  assert.ok(table, "table snippet exists");
  // Apply the snippet to a document and inspect the inserted text.
  let state = stateFor("\\begin{tab");
  const fakeView = {
    get state() { return state; },
    dispatch(tr) { state = (tr.state ?? state.update(tr).state); },
  };
  table.apply(fakeView, table, r.from, state.doc.length);
  const text = state.doc.toString();
  assert.match(text, /\\begin\{table\}/);
  assert.match(text, /\\end\{table\}/);
  assert.ok(!text.includes("\\\\\\\\"), "rows end with \\\\ not \\\\\\\\");
  assert.ok(text.includes("\\\\"), "rows contain a LaTeX line break");
  assert.ok(snippet);
});

test("folds environments and sections", () => {
  const doc = "\\section{A}\ntext\n\\begin{itemize}\n\\item x\n\\end{itemize}\nmore\n\\section{B}\nb";
  const state = stateFor(doc);
  const sec = state.doc.line(1);
  const f1 = foldable(state, sec.from, sec.to);
  assert.ok(f1, "section folds");
  assert.equal(state.doc.lineAt(f1.to).number, 6, "section fold stops before the next section");
  const env = state.doc.line(3);
  const f2 = foldable(state, env.from, env.to);
  assert.ok(f2, "environment folds");
  assert.equal(state.doc.lineAt(f2.to).number, 5);
});

test("optional arguments don't break special-argument highlighting", () => {
  const t = tokens("\\includegraphics[width=0.5\\linewidth]{figs/a.png}\n\\section[Short]{Long title}");
  assert.ok(has(t, "file", "figs/a.png"));
  assert.ok(has(t, "heading", "Long title"));
  assert.ok(has(t, "command", "\\linewidth"));
});
