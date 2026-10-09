// S10 TOC API (not a hook). Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Contract: Marked.toc.headings() -> [{level: 1..6, text}] in document order; Marked.toc.go(i) -> boolean.
const TOC_SELECTOR = "h1, h2, h3, h4, h5, h6";
const TOC_EDGE = 8;

function tocHeadings(root) {
  if (!root) return [];
  return [...root.querySelectorAll(TOC_SELECTOR)].map((h) => ({
    level: Number(h.tagName[1]),
    text: h.textContent.replace(/\s+/g, " ").trim(),
  }));
}

// Same query as tocHeadings, so a sidebar row index names the same heading.
function tocGo(root, i) {
  if (!root || !Number.isInteger(i)) return false;
  const h = root.querySelectorAll(TOC_SELECTOR)[i];
  if (!h) return false;
  h.scrollIntoView({ block: "start" });
  return true;
}

// S13 scroll-spy. Current = last heading whose top is at or above the edge. Bottom rule (D47): a scrollable
// page scrolled to its end → last heading whose top is inside the viewport, when that is later.
function tocCurrent({ tops, height, atEnd }, edge = TOC_EDGE) {
  let cur = -1;
  tops.forEach((t, i) => { if (t <= edge || (atEnd && t < height)) cur = i; });
  return cur;
}

// Posts the current index only when it changes; reset() forgets the last post so the next one always goes out.
function tocSpy(read, post) {
  let last;
  const update = () => {
    const cur = tocCurrent(read());
    if (cur !== last) { last = cur; post(cur); }
  };
  return { update, reset() { last = undefined; update(); } };
}

if (typeof Marked !== "undefined") {
  const content = () => document.getElementById("content");
  Marked.toc = { headings: () => tocHeadings(content()), go: (i) => tocGo(content(), i) };

  // ponytail: one rect read per heading per frame while scrolling; IntersectionObserver if thousands of headings get slow.
  const html = document.documentElement;
  const spy = tocSpy(() => ({
    tops: [...content().querySelectorAll(TOC_SELECTOR)].map((h) => h.getBoundingClientRect().top),
    height: innerHeight,
    atEnd: html.scrollHeight > innerHeight && scrollY + innerHeight >= html.scrollHeight - 1,
  }), (i) => window.webkit?.messageHandlers?.toc?.postMessage(i));
  let queued = false;
  const gate = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; spy.update(); });
  };
  addEventListener("scroll", gate, { passive: true });
  addEventListener("resize", gate, { passive: true });
  new ResizeObserver(gate).observe(content());
  Marked.hook("position", function tocSpyReset() { spy.reset(); });
}

if (typeof module !== "undefined") module.exports = { tocHeadings, tocGo, tocCurrent, tocSpy };
