import test from "node:test";
import assert from "node:assert";
import fs from "node:fs";

const read = (p) => fs.readFileSync(new URL(`../../Resources/${p}`, import.meta.url), "utf8");
const vars = (css) => {
  const m = css.trim().match(/^:root\s*\{([^{}]*)\}$/);
  assert.ok(m, "exactly one :root rule, no other selectors");
  return Object.fromEntries(
    m[1].split(";").map((d) => d.trim()).filter(Boolean).map((d) => {
      const i = d.indexOf(":");
      return [d.slice(0, i).trim(), d.slice(i + 1).trim()];
    })
  );
};
const parsed = Object.fromEntries(["mono", "serif", "sans"].map((n) => [n, vars(read(`styles/${n}.css`))]));

test("each style defines only --font, --leading (text width follows the window)", () => {
  for (const [n, v] of Object.entries(parsed))
    assert.deepStrictEqual(Object.keys(v).sort(), ["--font", "--leading"], n);
});
test("mono font", () => assert.ok(parsed.mono["--font"].startsWith("ui-monospace")));
test("serif font", () => assert.ok(parsed.serif["--font"].includes("serif")));
test("sans equals base.css :root", () => {
  const base = read("base.css").match(/:root\s*\{[^{}]*\}/)[0];
  assert.deepStrictEqual(parsed.sans, vars(base));
});
test("content has no width cap, only a side margin", () => {
  const rule = read("base.css").match(/^#content\s*\{([^{}]*)\}/m)[1];
  assert.ok(!/max-width/.test(rule), rule);
  assert.match(rule, /padding:\s*2em clamp\(1\.5em, 5vw, 4em\)/);
});
