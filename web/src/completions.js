// LaTeX autocompletion: commands, environments, labels, citations, files and packages.
import { snippetCompletion } from "@codemirror/autocomplete";

export const projectData = {
  labels: [],   // [{label, file, line, context}]
  cites: [],    // [{key, title, author, year}]
  files: [],    // ["figures/plot.pdf", "sections/intro.tex", ...]
  commands: [], // user-defined: [{name, args}]
};

const ENVIRONMENTS = [
  "abstract", "align", "align*", "alignat", "array", "bmatrix", "cases", "center", "description",
  "document", "enumerate", "equation", "equation*", "figure", "figure*", "flushleft", "flushright",
  "frame", "gather", "gather*", "itemize", "lemma", "list", "longtable", "lstlisting", "matrix",
  "minipage", "multline", "pmatrix", "proof", "proposition", "quote", "quotation", "split",
  "subfigure", "tabular", "tabularx", "table", "table*", "thebibliography", "theorem", "tikzpicture",
  "titlepage", "verbatim", "vmatrix", "wrapfigure", "definition", "corollary", "remark", "example",
  "algorithm", "algorithmic", "columns", "column", "block", "appendices", "multicols",
];

const ENV_BODIES = {
  figure: "\\centering\n  \\includegraphics[width=\\linewidth]{${file}}\n  \\caption{${Caption}}\n  \\label{fig:${label}}",
  "figure*": "\\centering\n  \\includegraphics[width=\\textwidth]{${file}}\n  \\caption{${Caption}}\n  \\label{fig:${label}}",
  table: "\\centering\n  \\caption{${Caption}}\n  \\label{tab:${label}}\n  \\begin{tabular}{${lcc}}\n    \\toprule\n    ${A} & ${B} & ${C} \\\\\n    \\midrule\n    ${} \\\\\n    \\bottomrule\n  \\end{tabular}",
  itemize: "\\item ${}",
  enumerate: "\\item ${}",
  description: "\\item[${term}] ${}",
  equation: "${}\n  \\label{eq:${label}}",
  align: "${} &= ${} \\\\\n  ${} &= ${}",
  tabular: "${A} & ${B} \\\\\n  ${}",
  frame: "\\frametitle{${Title}}\n  ${}",
};

const COMMANDS = [
  // [name, snippet-or-null, detail]
  ["section", "\\section{${}}", "Section heading"],
  ["subsection", "\\subsection{${}}", "Subsection heading"],
  ["subsubsection", "\\subsubsection{${}}", "Sub-subsection heading"],
  ["chapter", "\\chapter{${}}", "Chapter heading"],
  ["paragraph", "\\paragraph{${}}", "Run-in heading"],
  ["textbf", "\\textbf{${}}", "Bold"],
  ["textit", "\\textit{${}}", "Italic"],
  ["emph", "\\emph{${}}", "Emphasis"],
  ["underline", "\\underline{${}}", "Underline"],
  ["texttt", "\\texttt{${}}", "Monospace"],
  ["textsc", "\\textsc{${}}", "Small caps"],
  ["textsf", "\\textsf{${}}", "Sans serif"],
  ["mathbf", "\\mathbf{${}}", "Bold math"],
  ["mathrm", "\\mathrm{${}}", "Upright math"],
  ["mathcal", "\\mathcal{${}}", "Calligraphic"],
  ["mathbb", "\\mathbb{${}}", "Blackboard bold"],
  ["boldsymbol", "\\boldsymbol{${}}", "Bold symbol"],
  ["frac", "\\frac{${num}}{${den}}", "Fraction"],
  ["sqrt", "\\sqrt{${}}", "Square root"],
  ["sum", "\\sum_{${i=1}}^{${N}}", "Sum"],
  ["prod", "\\prod_{${i=1}}^{${N}}", "Product"],
  ["int", "\\int_{${a}}^{${b}}", "Integral"],
  ["lim", "\\lim_{${x \\to \\infty}}", "Limit"],
  ["left", "\\left( ${} \\right)", "Sized delimiters"],
  ["label", "\\label{${}}", "Label"],
  ["ref", "\\ref{${}}", "Reference"],
  ["eqref", "\\eqref{${}}", "Equation reference"],
  ["autoref", "\\autoref{${}}", "Named reference"],
  ["cref", "\\cref{${}}", "Clever reference"],
  ["cite", "\\cite{${}}", "Citation"],
  ["citep", "\\citep{${}}", "Parenthetical citation"],
  ["citet", "\\citet{${}}", "Textual citation"],
  ["footnote", "\\footnote{${}}", "Footnote"],
  ["url", "\\url{${}}", "URL"],
  ["href", "\\href{${url}}{${text}}", "Hyperlink"],
  ["includegraphics", "\\includegraphics[width=${\\linewidth}]{${}}", "Insert image"],
  ["input", "\\input{${}}", "Insert file"],
  ["include", "\\include{${}}", "Include chapter"],
  ["usepackage", "\\usepackage{${}}", "Load package"],
  ["documentclass", "\\documentclass{${article}}", "Document class"],
  ["begin", null, "Begin environment"],
  ["end", null, "End environment"],
  ["item", "\\item ${}", "List item"],
  ["caption", "\\caption{${}}", "Caption"],
  ["centering", null, "Center content"],
  ["maketitle", null, "Print title"],
  ["tableofcontents", null, "Table of contents"],
  ["newcommand", "\\newcommand{\\${name}}[${1}]{${}}", "Define a command"],
  ["renewcommand", "\\renewcommand{\\${name}}{${}}", "Redefine a command"],
  ["title", "\\title{${}}", "Title"],
  ["author", "\\author{${}}", "Author"],
  ["date", "\\date{${\\today}}", "Date"],
  ["today", null, "Today's date"],
  ["bibliography", "\\bibliography{${refs}}", "Bibliography file"],
  ["bibliographystyle", "\\bibliographystyle{${plain}}", "Bibliography style"],
  ["printbibliography", null, "biblatex bibliography"],
  ["addbibresource", "\\addbibresource{${refs.bib}}", "biblatex resource"],
  ["hspace", "\\hspace{${1em}}", "Horizontal space"],
  ["vspace", "\\vspace{${1em}}", "Vertical space"],
  ["newpage", null, "New page"],
  ["clearpage", null, "Clear page"],
  ["noindent", null, "No indent"],
  ["linewidth", null, "Line width"],
  ["textwidth", null, "Text width"],
  ["columnwidth", null, "Column width"],
  ["toprule", null, "booktabs top rule"],
  ["midrule", null, "booktabs middle rule"],
  ["bottomrule", null, "booktabs bottom rule"],
  ["hline", null, "Horizontal line"],
  ["multicolumn", "\\multicolumn{${2}}{${c}}{${}}", "Span columns"],
  ["multirow", "\\multirow{${2}}{*}{${}}", "Span rows"],
  ["alpha"], ["beta"], ["gamma"], ["delta"], ["epsilon"], ["varepsilon"], ["zeta"], ["eta"],
  ["theta"], ["lambda"], ["mu"], ["nu"], ["xi"], ["pi"], ["rho"], ["sigma"], ["tau"], ["phi"],
  ["varphi"], ["chi"], ["psi"], ["omega"], ["Gamma"], ["Delta"], ["Theta"], ["Lambda"], ["Sigma"],
  ["Phi"], ["Psi"], ["Omega"], ["infty"], ["partial"], ["nabla"], ["cdot"], ["cdots"], ["ldots"],
  ["times"], ["leq"], ["geq"], ["neq"], ["approx"], ["sim"], ["equiv"], ["in"], ["notin"],
  ["subset"], ["subseteq"], ["cup"], ["cap"], ["forall"], ["exists"], ["to"], ["rightarrow"],
  ["leftarrow"], ["Rightarrow"], ["Leftrightarrow"], ["mapsto"], ["mathbb"], ["hat", "\\hat{${}}"],
  ["bar", "\\bar{${}}"], ["tilde", "\\tilde{${}}"], ["vec", "\\vec{${}}"], ["dot", "\\dot{${}}"],
  ["operatorname", "\\operatorname{${}}"], ["argmin", "\\arg\\min_{${}}"], ["argmax", "\\arg\\max_{${}}"],
  ["lVert"], ["rVert"], ["langle"], ["rangle"], ["quad"], ["qquad"], ["text", "\\text{${}}"],
  ["textcolor", "\\textcolor{${red}}{${}}"], ["color", "\\color{${red}}"],
  ["frametitle", "\\frametitle{${}}"], ["pause"], ["onslide", "\\onslide<${2-}>{${}}"],
];

const PACKAGES = [
  "amsmath", "amssymb", "amsthm", "graphicx", "hyperref", "booktabs", "geometry", "xcolor",
  "natbib", "biblatex", "cleveref", "tikz", "pgfplots", "subcaption", "caption", "float",
  "multirow", "tabularx", "longtable", "siunitx", "listings", "minted", "algorithm", "algorithmic",
  "algorithm2e", "algpseudocode", "enumitem", "fontenc", "inputenc", "lmodern", "microtype",
  "setspace", "titlesec", "fancyhdr", "url", "xspace", "array", "makecell", "wrapfig", "mathtools",
  "bm", "physics", "todonotes", "lipsum", "babel", "csquotes", "authblk", "appendix", "soul",
];

function commandOptions() {
  const user = projectData.commands.map(c => ({
    label: "\\" + c.name, type: "function", detail: c.args ? `${c.args} args · yours` : "yours", boost: 2,
  }));
  const builtin = COMMANDS.map(([name, snippet, detail]) => {
    if (snippet) return snippetCompletion(snippet, { label: "\\" + name, type: "function", detail: detail || "" });
    return { label: "\\" + name, type: "keyword", detail: detail || "" };
  });
  return user.concat(builtin);
}

function envOptions() {
  return ENVIRONMENTS.map(env => {
    const body = ENV_BODIES[env] || "${}";
    return snippetCompletion(`${env}}\n  ${body}\n\\end{${env}}`, { label: env, type: "type" });
  });
}

/** Finds the command whose {...} argument the cursor is in, e.g. "cite" in \cite{ab|}. */
function argumentContext(context) {
  const line = context.state.doc.lineAt(context.pos);
  const before = line.text.slice(0, context.pos - line.from);
  const m = /\\([a-zA-Z]+\*?)(\[[^\]]*\])*\{([^{}]*)$/.exec(before);
  if (!m) return null;
  const typed = m[3];
  const lastComma = typed.lastIndexOf(",");
  const word = typed.slice(lastComma + 1).trimStart();
  return { command: m[1].replace(/\*$/, ""), from: context.pos - word.length, word };
}

const REF_CMDS = new Set(["ref", "eqref", "pageref", "autoref", "cref", "Cref", "nameref", "vref", "labelcref"]);
const CITE_CMDS = new Set(["cite", "citep", "citet", "citeauthor", "citeyear", "nocite", "parencite",
  "textcite", "autocite", "footcite", "Cite", "Citep", "Citet", "citealp", "citealt", "fullcite"]);

export function latexCompletions(context) {
  const arg = argumentContext(context);
  if (arg) {
    if (REF_CMDS.has(arg.command)) {
      return {
        from: arg.from,
        options: projectData.labels.map(l => ({
          label: l.label, type: "variable", detail: l.file ? `${l.file}:${l.line}` : "", info: l.context || undefined,
        })),
        validFor: /^[^,}\s]*$/,
      };
    }
    if (CITE_CMDS.has(arg.command)) {
      return {
        from: arg.from,
        options: projectData.cites.map(c => ({
          label: c.key, type: "text",
          detail: [c.author, c.year].filter(Boolean).join(", "),
          info: c.title || undefined,
          apply: c.key,
        })),
        validFor: /^[^,}\s]*$/,
      };
    }
    if (arg.command === "begin" || arg.command === "end") {
      if (arg.command === "end") {
        return { from: arg.from, options: ENVIRONMENTS.map(e => ({ label: e, type: "type", apply: e + "}" })), validFor: /^[\w*]*$/ };
      }
      return { from: arg.from, options: envOptions(), validFor: /^[\w*]*$/ };
    }
    if (arg.command === "usepackage" || arg.command === "RequirePackage") {
      return { from: arg.from, options: PACKAGES.map(p => ({ label: p, type: "namespace" })), validFor: /^[\w-]*$/ };
    }
    if (["includegraphics", "input", "include", "bibliography", "addbibresource", "includepdf", "lstinputlisting", "subfile"].includes(arg.command)) {
      const wantTex = ["input", "include", "subfile"].includes(arg.command);
      const wantBib = ["bibliography", "addbibresource"].includes(arg.command);
      const wantImg = arg.command === "includegraphics";
      const files = projectData.files.filter(f => {
        const ext = f.split(".").pop().toLowerCase();
        if (wantTex) return ext === "tex";
        if (wantBib) return ext === "bib";
        if (wantImg) return ["png", "jpg", "jpeg", "pdf", "eps", "svg"].includes(ext);
        return true;
      });
      return {
        from: arg.from,
        options: files.map(f => {
          let apply = f;
          if (wantTex) apply = f.replace(/\.tex$/, "");
          if (arg.command === "bibliography") apply = f.replace(/\.bib$/, "");
          return { label: f, type: "text", apply };
        }),
        validFor: /^[^,}]*$/,
      };
    }
    return null;
  }

  const cmd = context.matchBefore(/\\[a-zA-Z@]*/);
  if (cmd && (cmd.from !== cmd.to || context.explicit)) {
    return { from: cmd.from, options: commandOptions(), validFor: /^\\[a-zA-Z@]*$/ };
  }
  return null;
}
