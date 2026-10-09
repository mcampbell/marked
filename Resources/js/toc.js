// S10 TOC API (not a hook). Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Contract: Marked.toc.headings() -> [{level: 1..6, text}] in document order; Marked.toc.go(i) -> boolean.
const TOC_SELECTOR = "h1, h2, h3, h4, h5, h6";

function tocHeadings(root) {
  if (!root) return [];
  return [...root.querySelectorAll(TOC_SELECTOR)].map((h) => ({
    level: Number(h.tagName[1]),
    text: h.textContent.replace(/\s+/g, " ").trim(),
  }));
}

// Same query as tocHeadings, so a sidebar row index names the same heading.
function tocGo(root, i) {
  if (!root || !Number.isInteger(i)) return false;
  const h = root.querySelectorAll(TOC_SELECTOR)[i];
  if (!h) return false;
  h.scrollIntoView({ block: "start" });
  return true;
}

if (typeof Marked !== "undefined") {
  const content = () => document.getElementById("content");
  Marked.toc = { headings: () => tocHeadings(content()), go: (i) => tocGo(content(), i) };
}

if (typeof module !== "undefined") module.exports = { tocHeadings, tocGo };
