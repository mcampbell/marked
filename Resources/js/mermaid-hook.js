// S5 Mermaid. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Reads the vendored global `mermaid` (vendor/mermaid.min.js) only at call time.
let mermaidIdSeq = 0;
async function renderAll(sources, render) {
  const out = [];
  for (const src of sources) {
    try { out.push({ svg: await render("mmd-" + mermaidIdSeq++, src) }); }
    catch (e) { out.push({ error: e instanceof Error ? e.message : String(e) }); }
  }
  return out;
}

if (typeof mermaid !== "undefined") {
  mermaid.initialize({ startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true });
}

if (typeof Marked !== "undefined") {
  // ponytail: no cache, every render re-renders every diagram; cache source -> svg if a measured render gets slow.
  const cleanup = (id) => {
    for (const i of [id, "d" + id]) {
      const el = document.getElementById(i);
      if (el && !el.closest("#content")) el.remove();
    }
  };
  const render = async (id, src) => {
    try { return (await mermaid.render(id, src)).svg; } finally { cleanup(id); }
  };
  Marked.hook("transform", async function renderMermaid() {
    const blocks = [...document.querySelectorAll("#content pre > code.language-mermaid")];
    const results = await renderAll(blocks.map((c) => c.textContent), render);
    blocks.forEach((code, i) => {
      const pre = code.parentElement, r = results[i];
      if ("svg" in r) {
        const div = document.createElement("div");
        div.className = "mermaid";
        if (pre.hasAttribute("data-sourcepos")) div.setAttribute("data-sourcepos", pre.getAttribute("data-sourcepos"));
        div.innerHTML = r.svg;
        pre.replaceWith(div);
      } else {
        const div = document.createElement("div");
        div.className = "mermaid-error";
        div.textContent = "Mermaid: " + r.error;
        pre.after(div);
      }
    });
  });
}

if (typeof module !== "undefined") module.exports = { renderAll };
