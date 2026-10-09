import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { tocHeadings, tocGo } = createRequire(import.meta.url)("../../Resources/js/toc.js");

function fake(headings) {
  const root = { seen: null, querySelectorAll(sel) { root.seen = sel; return headings; } };
  return root;
}
const heading = (tagName, textContent = "x") => {
  const h = { tagName, textContent, calls: [], scrollIntoView(o) { h.calls.push(o); } };
  return h;
};

test("selector is every heading level", () => {
  const root = fake([]);
  tocHeadings(root);
  assert.equal(root.seen, "h1, h2, h3, h4, h5, h6");
});

test("levels from tag names, order kept", () => {
  const hs = ["H1", "H2", "H3", "H4", "H5", "H6", "H2"].map((t, i) => heading(t, String(i)));
  assert.deepEqual(tocHeadings(fake(hs)), [1, 2, 3, 4, 5, 6, 2].map((level, i) => ({ level, text: String(i) })));
});

test("text whitespace collapsed and trimmed", () => {
  const hs = [heading("H1", "  a\n\tb  "), heading("H2", "a  b"), heading("H3", "")];
  assert.deepEqual(tocHeadings(fake(hs)).map((h) => h.text), ["a b", "a b", ""]);
});

test("null root gives no headings", () => assert.deepEqual(tocHeadings(null), []));

test("go scrolls only the target heading to the top", () => {
  const hs = [heading("H1"), heading("H2"), heading("H3")];
  assert.equal(tocGo(fake(hs), 1), true);
  assert.deepEqual(hs.map((h) => h.calls), [[], [{ block: "start" }], []]);
});

test("go rejects bad indexes without scrolling", () => {
  const hs = [heading("H1"), heading("H2"), heading("H3")];
  for (const i of [-1, 3, 1.5, "0", NaN]) assert.equal(tocGo(fake(hs), i), false, String(i));
  assert.deepEqual(hs.map((h) => h.calls), [[], [], []]);
  assert.equal(tocGo(null, 0), false);
});

const { tocCurrent, tocSpy } = createRequire(import.meta.url)("../../Resources/js/toc.js");
const at = (tops, atEnd = false, height = 700) => ({ tops, height, atEnd });

test("current = last heading at or above the edge", () => {
  const cases = [[[], -1], [[20, 500], -1], [[8, 500], 0], [[9], -1], [[-300, 5, 400], 1], [[-900, -300, -10], 2], [[0, 0], 1]];
  for (const [tops, want] of cases) assert.equal(tocCurrent(at(tops)), want, JSON.stringify(tops));
  assert.equal(tocCurrent(at([30]), 40), 0);
});

test("bottom rule: at the end, last heading inside the viewport", () => {
  const cases = [[[-500, 300, 600], 2], [[-500, 800], 0], [[-500, 700], 0], [[], -1], [[20, 300], 1]];
  for (const [tops, want] of cases) assert.equal(tocCurrent(at(tops, true)), want, JSON.stringify(tops));
});

test("spy posts only changes; reset forces a post", () => {
  let reading = at([20]);
  const posts = [];
  const spy = tocSpy(() => reading, (i) => posts.push(i));
  spy.update();
  assert.deepEqual(posts, [-1]);
  spy.update();
  assert.deepEqual(posts, [-1]);
  reading = at([0, 400]);
  spy.update();
  assert.deepEqual(posts, [-1, 0]);
  reading = at([-50, 300]);
  spy.update();
  assert.deepEqual(posts, [-1, 0]);
  spy.reset();
  assert.deepEqual(posts, [-1, 0, 0]);
  assert.ok(posts.every(Number.isInteger));
});
