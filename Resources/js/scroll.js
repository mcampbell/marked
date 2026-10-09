// S1 position hook: scroll to and flash the deepest block at the first changed line.
function pickTarget(ranges, line) {
  let hit = -1;
  ranges.forEach((r, i) => { if (r.start <= line && line <= r.end) hit = i; });
  if (hit >= 0) return hit;
  const next = ranges.findIndex((r) => r.start > line);
  return next >= 0 ? next : ranges.length - 1;
}

// Raw HTML in a document can set its own data-sourcepos, so a bad value yields null, not a throw.
function rangeOf(sourcepos) {
  const m = /^(\d+):\d+-(\d+):/.exec(sourcepos || "");
  return m ? { start: +m[1], end: +m[2] } : null;
}

if (typeof Marked !== "undefined") {
  Marked.hook("position", function scrollToChange({ changedLine }) {
    if (changedLine == null) return;
    const blocks = [...document.querySelectorAll("#content [data-sourcepos]")]
      .map((el) => ({ el, range: rangeOf(el.dataset.sourcepos) }))
      .filter((b) => b.range);
    const el = blocks[pickTarget(blocks.map((b) => b.range), changedLine)]?.el;
    if (!el) return;
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    el.animate([{ background: "#fff3a0" }, { background: "transparent" }], { duration: 1200 });
  });
}

if (typeof module !== "undefined") module.exports = { pickTarget, rangeOf };
