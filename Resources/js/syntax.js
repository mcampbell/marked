// S11 syntax highlight. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Uses the vendored highlight.js global `hljs` (Resources/vendor/highlight.min.js).
function codeLangOf(className) {
  const m = /(?:^|\s)language-(\S+)/.exec(className);
  return m ? m[1].toLowerCase() : null;
}

// Escaped highlight.js HTML for a labeled fence, or null to leave it plain.
function syntaxHTML(hljs, className, text) {
  const lang = codeLangOf(className);
  if (!lang || lang === "mermaid" || !hljs.getLanguage(lang)) return null;
  return hljs.highlight(text, { language: lang, ignoreIllegals: true }).value;
}

if (typeof Marked !== "undefined") {
  // ponytail: re-highlights every fence on every render; cache per fence text if a measured render gets slow.
  Marked.hook("transform", function colorCode() {
    for (const code of document.querySelectorAll("#content pre > code")) {
      const html = syntaxHTML(hljs, code.className, code.textContent);
      if (html === null) continue;
      code.innerHTML = html;
      code.classList.add("hljs");
    }
  });
}

if (typeof module !== "undefined") module.exports = { codeLangOf, syntaxHTML };
