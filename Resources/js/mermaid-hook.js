// S5 Mermaid. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Reads the vendored global `mermaid` (vendor/mermaid.min.js) only at call time.
function renderAll(sources, render) { return Promise.resolve([]); }

if (typeof mermaid !== "undefined") {
  mermaid.initialize({ startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true });
}

if (typeof module !== "undefined") module.exports = { renderAll };
