import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { splitHighlights } = createRequire(import.meta.url)("../../Resources/js/highlight.js");

// Parts joined, with the removed "==" delimiters put back, must equal the input.
const split = (input) => {
  const parts = splitHighlights(input);
  assert.equal(parts.map((p) => (p.mark ? "==" + p.text + "==" : p.text)).join(""), input);
  return parts;
};
const L = (text) => ({ text, mark: false });
const M = (text) => ({ text, mark: true });

test("middle mark", () => assert.deepEqual(split("a ==b== c"), [L("a "), M("b"), L(" c")]));
test("whole input", () => assert.deepEqual(split("==x=="), [M("x")]));
test("two marks", () => assert.deepEqual(split("==a== and ==b=="), [M("a"), L(" and "), M("b")]));
test("adjacent marks", () => assert.deepEqual(split("==a====b=="), [M("a"), M("b")]));
test("mid-word", () => assert.deepEqual(split("a==b==c"), [L("a"), M("b"), L("c")]));
for (const s of ["== x ==", "====", "=====", "==", "x == y"])
  test("literal " + JSON.stringify(s), () => assert.deepEqual(split(s), [L(s)]));
test("lazy rule", () => assert.deepEqual(split("==a == b=="), [M("a == b")]));
test("unicode", () => assert.deepEqual(split("==é 日本=="), [M("é 日本")]));
test("LF kept", () => assert.deepEqual(split("==a\nb=="), [M("a\nb")]));
test("CRLF kept", () => assert.deepEqual(split("==a\r\nb=="), [M("a\r\nb")]));
test("no delimiter", () => assert.deepEqual(split("plain"), [L("plain")]));
test("empty", () => assert.deepEqual(split(""), [L("")]));
