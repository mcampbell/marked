// S1 position hook: scroll to and flash the deepest block at the first changed line.
function pickTarget(ranges, line) {
  let hit = -1;
  ranges.forEach((r, i) => { if (r.start <= line && line <= r.end) hit = i; });
  if (hit >= 0) return hit;
  const next = ranges.findIndex((r) => r.start > line);
  return next >= 0 ? next : ranges.length - 1;
}

if (typeof Marked !== "undefined") {
  Marked.hook("position", function scrollToChange({ changedLine }) {
    if (changedLine == null) return;
    const els = [...document.querySelectorAll("#content [data-sourcepos]")];
    const ranges = els.map((e) => {
      const m = e.dataset.sourcepos.match(/^(\d+):\d+-(\d+):/);
      return { start: +m[1], end: +m[2] };
    });
    const el = els[pickTarget(ranges, changedLine)];
    if (!el) return;
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    el.animate([{ background: "#fff3a0" }, { background: "transparent" }], { duration: 1200 });
  });
}

if (typeof module !== "undefined") module.exports = { pickTarget };
