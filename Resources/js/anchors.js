// S6 heading ids. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
function slugger() {
  return { slug: (text) => text, reserve: (id) => {} };
}

if (typeof module !== "undefined") module.exports = { slugger };
