import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { slugger } = createRequire(import.meta.url)("../../Resources/js/anchors.js");

test("basic slug", () => assert.equal(slugger().slug("Intro"), "intro"));
test("collisions", () => {
  const s = slugger();
  assert.deepEqual([s.slug("Intro"), s.slug("Intro"), s.slug("Intro")], ["intro", "intro-1", "intro-2"]);
});
test("punctuation stripped", () => assert.equal(slugger().slug("C++ & Go!"), "c--go"));
test("spaces and hyphens kept", () => assert.equal(slugger().slug("a - b  c"), "a---b--c"));
test("no trim", () => assert.equal(slugger().slug(" a "), "-a-"));
test("unicode letters kept", () => {
  assert.equal(slugger().slug("Café Ünï"), "café-ünï");
  assert.equal(slugger().slug("ⓐ"), "ⓐ");
});
test("digits and underscore kept", () => assert.equal(slugger().slug("A_1"), "a_1"));
test("empty text", () => {
  const s = slugger();
  assert.deepEqual([s.slug(""), s.slug("")], ["", "-1"]);
});
test("reserve forces suffix", () => {
  const s = slugger();
  s.reserve("intro");
  assert.equal(s.slug("Intro"), "intro-1");
});
test("suffix collision loops", () => {
  const s = slugger();
  s.reserve("a");
  s.reserve("a-1");
  assert.equal(s.slug("A"), "a-2");
});
test("separate sluggers independent", () => {
  slugger().slug("x");
  assert.equal(slugger().slug("x"), "x");
});

// Remaining s6-plan K2.1 cases.
test("CJK kept", () => assert.equal(slugger().slug("日本語 見出し"), "日本語-見出し"));
test("Other_Number dropped", () => assert.equal(slugger().slug("x²"), "x"));
test("alphabetic symbol lowercased and kept", () => assert.equal(slugger().slug("Ⓐ"), "ⓐ"));
test("emoji dropped", () => assert.equal(slugger().slug("Ship 🚀 it"), "ship--it"));
test("explicit suffix heading does not collide", () => {
  const s = slugger();
  assert.deepEqual([s.slug("Intro"), s.slug("Intro-1"), s.slug("Intro")], ["intro", "intro-1", "intro-2"]);
});
test("reserved suffix skipped", () => {
  const s = slugger();
  s.reserve("intro-1");
  assert.deepEqual([s.slug("Intro"), s.slug("Intro")], ["intro", "intro-2"]);
});
