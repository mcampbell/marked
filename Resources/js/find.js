// S3 find. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Contract (frozen): Marked.find.{set(query), step(dir), restore(query, index), clear(), state()}
//   each return {count, index}; index -1 when count 0.
const none = () => ({ count: 0, index: -1 });

function matchOffsets(text, query) { return []; }
function step(index, count, dir) { return -1; }

if (typeof Marked !== "undefined") {
  Marked.find = { set: none, step: none, restore: none, clear: none, state: none };
}

if (typeof module !== "undefined") module.exports = { matchOffsets, step };
