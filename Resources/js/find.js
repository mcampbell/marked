// S3 find. Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Contract (frozen): Marked.find.{set(query), step(dir), restore(query, index), clear(), state()}
//   each return {count, index}; index -1 when count 0.
// Backend: CSS Custom Highlight API (W3.4 spike).
function matchOffsets(text, query) {
  const parts = query.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return [];
  const src = parts.map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("\\s+");
  const out = [];
  for (const m of text.matchAll(new RegExp(src, "giu"))) {
    if (m[0].length) out.push([m.index, m.index + m[0].length]);
  }
  return out;
}

function step(index, count, dir) {
  return count ? (((index + dir) % count) + count) % count : -1;
}

// Offsets arrive in ascending order, so one forward pointer keeps the walk O(nodes + matches).
// A start goes to the last node that begins at or before it; an end to the last node that begins before it.
function locator(starts) {
  let j = 0;
  return (off, isEnd) => {
    while (j + 1 < starts.length && (isEnd ? off > starts[j + 1] : off >= starts[j + 1])) j++;
    return [j, off - starts[j]];
  };
}

if (typeof Marked !== "undefined") {
  const SKIP = "div.mermaid, svg, script, style, .render-error";
  const BLOCKS = new Set(["P", "LI", "H1", "H2", "H3", "H4", "H5", "H6", "PRE", "BLOCKQUOTE", "TD", "TH",
    "DT", "DD", "DIV", "TABLE", "UL", "OL", "DL", "SECTION", "ARTICLE", "BODY", "FIGURE", "FIGCAPTION", "HR"]);
  let query = "";
  let index = -1;
  let ranges = [];

  const blockOf = (node, root) => {
    let el = node.parentElement;
    while (el && el !== root && !BLOCKS.has(el.tagName)) el = el.parentElement;
    return el;
  };

  function buildRanges() {
    const root = document.getElementById("content");
    if (!root) return [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.parentElement.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    const nodes = []; // {node, start}
    let text = "";
    let prev = null;
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const b = blockOf(n, root);
      if (prev && b !== prev) text += "\u0000";
      prev = b;
      nodes.push({ node: n, start: text.length });
      text += n.data;
    }
    const at = locator(nodes.map((n) => n.start));
    const locate = (off, isEnd) => {
      const [j, o] = at(off, isEnd);
      return [nodes[j].node, o];
    };
    return matchOffsets(text, query).map(([s, e]) => {
      const r = new Range();
      r.setStart(...locate(s, false));
      r.setEnd(...locate(e, true));
      return r;
    });
  }

  function paint() {
    CSS.highlights.set("find-hit", new Highlight(...ranges));
    const cur = new Highlight(...(ranges[index] ? [ranges[index]] : []));
    cur.priority = 1;
    CSS.highlights.set("find-current", cur);
  }

  function apply(q, i) {
    query = q;
    ranges = buildRanges();
    index = ranges.length ? Math.min(Math.max(i, 0), ranges.length - 1) : -1;
    paint();
  }

  function scrollCurrent() {
    const r = ranges[index];
    if (!r) return;
    const rect = r.getBoundingClientRect();
    window.scrollBy({ top: rect.top + rect.height / 2 - innerHeight / 2, behavior: "smooth" });
  }

  const state = () => ({ count: ranges.length, index });
  const clear = () => {
    CSS.highlights.delete("find-hit");
    CSS.highlights.delete("find-current");
    query = "";
    ranges = [];
    index = -1;
    return state();
  };

  Marked.find = {
    set(q) {
      if (!q.trim()) return clear();
      apply(q, 0);
      scrollCurrent();
      return state();
    },
    step(dir) {
      if (!query) return state();
      index = step(index, ranges.length, dir);
      paint();
      scrollCurrent();
      return state();
    },
    restore(q, i) {
      if (!q.trim()) return clear();
      apply(q, i);
      return state();
    },
    clear,
    state,
  };

  // innerHTML was replaced: old Ranges are stale. Re-apply, keep index (clamped), no scroll.
  Marked.hook("decorate", function refindAfterRender() {
    if (query) apply(query, index);
  });
}

if (typeof module !== "undefined") module.exports = { matchOffsets, step, locator };
