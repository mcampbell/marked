import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const hljs = require("../../Resources/vendor/highlight.min.js");
const { codeLangOf, syntaxHTML } = require("../../Resources/js/syntax.js");

// Highlighted HTML minus hljs's own spans, entities decoded → the source text again.
const plain = (html) =>
  html.replace(/<\/?span[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#x27;/g, "'").replace(/&amp;/g, "&");

for (const [cls, lang] of [["language-swift", "swift"], ["language-JS", "js"], ["foo language-ts bar", "ts"],
  ["language-a language-b", "a"]])
  test("codeLangOf " + JSON.stringify(cls), () => assert.equal(codeLangOf(cls), lang));
for (const cls of ["", "lang-x", "xlanguage-y"])
  test("codeLangOf null " + JSON.stringify(cls), () => assert.equal(codeLangOf(cls), null));

test("swift highlights, text round-trips", () => {
  const out = syntaxHTML(hljs, "language-swift", "let x = 1");
  assert.ok(out.includes("hljs-keyword"));
  assert.equal(plain(out), "let x = 1");
});
for (const cls of ["language-js", "language-sh"])
  test("alias " + cls, () => assert.notEqual(syntaxHTML(hljs, cls, "echo 1"), null));
for (const cls of ["language-mermaid", "language-nosuchlang", ""])
  test("plain " + JSON.stringify(cls), () => assert.equal(syntaxHTML(hljs, cls, "graph TD"), null));

const EVIL = "<script>alert(1)</script><img src=x onerror=1>";
for (const cls of ["language-html", "language-swift"])
  test("escaped under " + cls, () => {
    const out = syntaxHTML(hljs, cls, EVIL);
    assert.ok(!out.includes("<script") && !out.includes("<img"));
    assert.ok(!out.replace(/<\/?span[^>]*>/g, "").includes("<"));
    assert.equal(plain(out), EVIL);
  });
// className comes from the document (raw HTML too): prototype keys must not resolve to a language.
for (const cls of ["language-__proto__", "language-constructor", "language-toString"])
  test("prototype key plain " + cls, () => assert.equal(syntaxHTML(hljs, cls, "x"), null));
