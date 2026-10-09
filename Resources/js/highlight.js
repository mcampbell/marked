// S8 ==highlight==. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
const HIGHLIGHT_RE = /==([^\s=]|[^\s=][\s\S]*?[^\s=])==/g;

function splitHighlights(text) {
  if (!text.includes("==")) return [{ text, mark: false }];
  const parts = [];
  let last = 0;
  for (const m of text.matchAll(HIGHLIGHT_RE)) {
    if (m.index > last) parts.push({ text: text.slice(last, m.index), mark: false });
    parts.push({ text: m[1], mark: true });
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push({ text: text.slice(last), mark: false });
  return parts;
}

if (typeof Marked !== "undefined") {
  Marked.hook("transform", function markHighlights() {
    const walker = document.createTreeWalker(document.getElementById("content"), NodeFilter.SHOW_TEXT, {
      acceptNode: (node) =>
        node.data.includes("==") &&
        !node.parentElement.closest("pre, code, kbd, samp, div.mermaid, svg, script, style, textarea")
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT,
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const parts = splitHighlights(node.data);
      if (!parts.some((p) => p.mark)) continue;
      const frag = document.createDocumentFragment();
      for (const p of parts) {
        if (p.mark) {
          const el = document.createElement("mark");
          el.textContent = p.text;
          frag.appendChild(el);
        } else frag.appendChild(document.createTextNode(p.text));
      }
      node.replaceWith(frag);
    }
  });
}

if (typeof module !== "undefined") module.exports = { splitHighlights };
