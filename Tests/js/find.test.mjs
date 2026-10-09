import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { matchOffsets, step } = createRequire(import.meta.url)("../../Resources/js/find.js");

test("case-insensitive", () => assert.deepEqual(matchOffsets("Foo foo", "FOO"), [[0, 3], [4, 7]]));
test("unicode", () => assert.deepEqual(matchOffsets("café CAFÉ", "cafÉ"), [[0, 4], [5, 9]]));
test("metacharacters literal", () => {
  assert.deepEqual(matchOffsets("a.b axb", "a.b"), [[0, 3]]);
  assert.deepEqual(matchOffsets("f(x) fx", "(x)"), [[1, 4]]);
  assert.deepEqual(matchOffsets("a\\b", "\\"), [[1, 2]]);
  assert.deepEqual(matchOffsets("a-b a/b", "-"), [[1, 2]]);
});
test("whitespace runs match any whitespace run", () =>
  assert.deepEqual(matchOffsets("should\n  render", "should   render"), [[0, 15]]));
test("non-overlapping", () => assert.deepEqual(matchOffsets("aaaa", "aa"), [[0, 2], [2, 4]]));
test("NUL blocks a match", () => assert.deepEqual(matchOffsets("end.\u0000Start", "end. start"), []));
test("empty and whitespace-only query", () => {
  assert.deepEqual(matchOffsets("abc", ""), []);
  assert.deepEqual(matchOffsets("a b", "  "), []);
});
test("offsets point into original text", () => {
  const t = "xx Hello  World";
  const [[s, e]] = matchOffsets(t, "hello world");
  assert.equal(t.slice(s, e), "Hello  World");
});
test("step wraps forward", () => assert.equal(step(2, 3, 1), 0));
test("step wraps back", () => assert.equal(step(0, 3, -1), 2));
test("step plain", () => assert.equal(step(1, 3, 1), 2));
test("step count 0", () => assert.equal(step(0, 0, 1), -1));

const { locator } = createRequire(import.meta.url)("../../Resources/js/find.js");
test("locator maps ascending offsets to [node, offset]", () => {
  const at = locator([0, 5, 5, 10]); // node 2 is empty
  assert.deepEqual(at(0, false), [0, 0]);
  assert.deepEqual(at(5, true), [0, 5]);   // an end at a boundary stays in the earlier node
  assert.deepEqual(at(5, false), [2, 0]);  // a start at a boundary goes to the last node there
  assert.deepEqual(at(12, true), [3, 2]);
});
