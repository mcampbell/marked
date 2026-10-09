// S8 ==highlight==. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
function splitHighlights(text) { return [{ text, mark: false }]; }

if (typeof module !== "undefined") module.exports = { splitHighlights };
