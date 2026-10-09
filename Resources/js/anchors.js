// S6 heading ids. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
const SLUG_STRIP = /[^\p{Alphabetic}\p{M}\p{Nd}\p{Nl}\p{Pc} -]/gu;

function slugger() {
  const used = new Set();
  return {
    slug(text) {
      const base = text.toLowerCase().replace(SLUG_STRIP, "").replace(/ /g, "-");
      let id = base;
      for (let n = 1; used.has(id); n++) id = base + "-" + n;
      used.add(id);
      return id;
    },
    reserve: (id) => used.add(id),
  };
}

if (typeof Marked !== "undefined") {
  Marked.hook("decorate", function addHeadingIds() {
    const { slug, reserve } = slugger();
    const hs = document.querySelectorAll("#content h1, #content h2, #content h3, #content h4, #content h5, #content h6");
    hs.forEach((h) => { if (h.id) reserve(h.id); });
    hs.forEach((h) => { if (!h.id) { const s = slug(h.textContent); if (s) h.id = s; } });
  });
}

if (typeof module !== "undefined") module.exports = { slugger };
