import test from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";
const { renderAll } = createRequire(import.meta.url)("../../Resources/js/mermaid-hook.js");

test("all ok, in order", async () => {
  const calls = [];
  const r = await renderAll(["a", "b", "c"], async (id, src) => { calls.push(src); return "<svg>" + src + "</svg>"; });
  assert.deepEqual(calls, ["a", "b", "c"]);
  assert.deepEqual(r, [{ svg: "<svg>a</svg>" }, { svg: "<svg>b</svg>" }, { svg: "<svg>c</svg>" }]);
});

test("a throw gives {error} at its index, rest still render", async () => {
  const r = await renderAll(["a", "b", "c"], async (id, src) => {
    if (src === "b") throw new Error("bad");
    return src;
  });
  assert.deepEqual(r, [{ svg: "a" }, { error: "bad" }, { svg: "c" }]);
});

test("non-Error throw uses String(e)", async () => {
  const r = await renderAll(["a"], async () => { throw "oops"; });
  assert.deepEqual(r, [{ error: "oops" }]);
});

test("sequential, no overlap", async () => {
  const ev = [];
  await renderAll(["a", "b", "c"], async (id, src) => {
    ev.push("start " + src);
    await new Promise((res) => setTimeout(res, 5));
    ev.push("end " + src);
    return src;
  });
  assert.deepEqual(ev, ["start a", "end a", "start b", "end b", "start c", "end c"]);
});

test("ids unique across calls", async () => {
  const ids = [];
  const render = async (id) => { ids.push(id); return ""; };
  await renderAll(["a", "b"], render);
  await renderAll(["c", "d"], render);
  assert.equal(new Set(ids).size, 4);
  assert.ok(ids.every((i) => /^mmd-\d+$/.test(i)));
});

test("empty input", async () => {
  let called = false;
  assert.deepEqual(await renderAll([], async () => { called = true; }), []);
  assert.equal(called, false);
});
