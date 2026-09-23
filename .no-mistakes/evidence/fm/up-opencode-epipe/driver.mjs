// usage: <runtime> driver.mjs <variant fixed|base> <mode> [iterations]
const [variant, mode, itersArg] = process.argv.slice(2);
const L = "/tmp/fm-epipe-lab";
const plugins = `${L}/${variant}/.opencode/plugins`;
const { FmPrimaryTurnendGuard } = await import(`${plugins}/fm-primary-turnend-guard.js`);
const { encodeFirstmateOperationalInput } = await import(`${plugins}/lib/fm-operational-input.js`);
const runtime = typeof Bun !== "undefined" ? `bun ${Bun.version}` : `node ${process.version}`;
const log = (...a) => console.log(`[${runtime} ${variant} ${mode}]`, ...a);
const big = "RECOVERY-PROMPT ".repeat(131072); // 2 MiB body, far above a pipe buffer

if (mode === "encode-real") {
  const out = await encodeFirstmateOperationalInput(`${L}/primary`, "turn-end-guard", big);
  log("real encoder returned", out.length, "bytes; header ok:",
    out.startsWith("⁣FIRSTMATE_OP: v1 turn-end-guard: RECOVERY-PROMPT"), "body intact:", out.endsWith(big));
} else if (mode === "encode-early-close") {
  try {
    await encodeFirstmateOperationalInput(`${L}/earlyenc`, "turn-end-guard", big);
    log("UNEXPECTED resolve");
  } catch (e) { log("promise rejected cleanly:", JSON.stringify(e.message)); }
  log("process survived");
} else if (mode === "guard-normal") {
  const prompts = [];
  const client = { session: { promptAsync: async (req) => { prompts.push(req); } } };
  const hooks = await FmPrimaryTurnendGuard({ client, directory: `${L}/primary`, worktree: `${L}/primary` });
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "ses_lab" } } });
  log("promptAsync calls:", prompts.length);
  const p = prompts[0];
  log("session:", p?.path?.id, "\n--- delivered text ---\n" + p?.body?.parts?.[0]?.text + "\n--- end ---");
} else if (mode === "guard-early-close") {
  const iters = Number(itersArg || 20);
  const client = { session: { promptAsync: async () => {} } };
  const hooks = await FmPrimaryTurnendGuard({ client, directory: `${L}/earlyguard`, worktree: `${L}/earlyguard` });
  await Promise.all(Array.from({ length: iters }, (_, i) =>
    hooks.event({ event: { type: "session.idle", properties: { sessionID: `ses_${i}` } } })));
  log(`completed ${iters} idle events; process survived`);
}
