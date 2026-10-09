// Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Wire shape (frozen): Marked.render(html, changedLine) resolves exactly
//   {ok: boolean, errors: string[]}, each error "<hook name>: <message>".
//   Success = {ok: true, errors: []}. It never rejects.
const hooks = { transform: [], decorate: [], position: [] };
window.Marked = {
  ping: () => "pong",
  token: crypto.randomUUID(),
  hook(phase, fn) {
    if (!hooks[phase]) throw new Error("unknown phase: " + phase);
    hooks[phase].push({ name: fn.name || "anonymous", fn });
  },
  async render(html, changedLine) {
    const errors = [];
    const msg = (e) => (e && e.message) || String(e);
    try {
      const content = document.getElementById("content");
      content.innerHTML = html;
      for (const phase of ["transform", "decorate", "position"]) {
        await Promise.all(hooks[phase].map(async (h) => {
          try { await h.fn({ changedLine }); }
          catch (e) { errors.push(h.name + ": " + msg(e)); }
        }));
      }
      if (errors.length) {
        const box = document.createElement("div");
        box.className = "render-error";
        for (const m of errors) {
          const d = document.createElement("div");
          d.textContent = m;
          box.appendChild(d);
        }
        content.prepend(box);
      }
    } catch (e) {
      errors.push("render: " + msg(e));
    }
    return { ok: errors.length === 0, errors };
  },
  setStyle(css) { document.getElementById("style").textContent = css; },
};
