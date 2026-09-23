import { pathToFileURL } from "node:url";
const N = Number(process.env.N || 200), C = Number(process.env.C || 50);
const handlers = new Map();
const mod = await import(pathToFileURL(process.env.EXT).href);
mod.default({ on(e, h) { handlers.set(e, h); }, sendMessage() {} });
const stop = handlers.get("session_stop");
const tally = {};
const rec = (r) => { const k = r?.continue === true ? "continue" : JSON.stringify(r ?? "undefined"); tally[k] = (tally[k] || 0) + 1; return r; };
const t0 = Date.now();
for (let i = 0; i < N; i++) rec(await stop({ type: "session_stop", stop_hook_active: false }, {}));
for (let b = 0; b < C; b++) (await Promise.all(Array.from({ length: 20 }, () => stop({ type: "session_stop", stop_hook_active: false }, {})))).forEach(rec);
const sample = await stop({ type: "session_stop", stop_hook_active: false }, {});
const flagged = await stop({ type: "session_stop", stop_hook_active: true }, {});
console.log(JSON.stringify({ mode: process.env.MODE, runtime: (globalThis.Bun ? `bun ${Bun.version}` : `node ${process.version}`), calls: N + C * 20, sequential: N, concurrent: `${C}x20`, tally, ms: Date.now() - t0,
  sampleContinuation: sample?.continue === true ? sample.additionalContext.slice(0, 160) : sample, flaggedStop: flagged === undefined ? "undefined (stands down)" : flagged }, null, 1));
console.log("HOST SURVIVED: pid", process.pid, "exiting normally");
