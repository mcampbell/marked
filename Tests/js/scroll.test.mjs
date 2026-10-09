import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { pickTarget } = createRequire(import.meta.url)("../../Resources/js/scroll.js");

const r = (start, end) => ({ start, end });

test("inside one block", () => assert.equal(pickTarget([r(1, 3), r(5, 8)], 6), 1));
test("nested list item picks deepest", () =>
  assert.equal(pickTarget([r(1, 10), r(2, 4), r(3, 3), r(12, 14)], 3), 2));
test("gap line picks next block", () => assert.equal(pickTarget([r(1, 3), r(6, 8)], 4), 1));
test("past end picks last", () => assert.equal(pickTarget([r(1, 3), r(5, 8)], 99), 1));
test("empty", () => assert.equal(pickTarget([], 1), -1));
test("frontmatter", () => assert.equal(pickTarget([r(1, 4), r(6, 7)], 2), 0));

const { rangeOf } = createRequire(import.meta.url)("../../Resources/js/scroll.js");
test("rangeOf parses cmark sourcepos", () => assert.deepEqual(rangeOf("3:1-5:2"), { start: 3, end: 5 }));
test("rangeOf rejects malformed (raw HTML can set data-sourcepos)", () => {
  assert.equal(rangeOf("x"), null);
  assert.equal(rangeOf(""), null);
  assert.equal(rangeOf(undefined), null);
});
