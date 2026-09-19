import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function lanarchyStateDir() {
  const xdg = process.env.XDG_STATE_HOME;
  return xdg ? join(xdg, "lanarchy") : join(homedir(), ".local/state/lanarchy");
}

function parseJson(text, label) {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, error: `${label} is not JSON` };
  }
}

function gatewayCall(method) {
  const result = spawnSync("openclaw", ["gateway", "call", method, "--json"], {
    encoding: "utf8",
    timeout: 30_000,
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) {
    const timedOut = result.error.code === "ETIMEDOUT";
    return {
      ok: false,
      error: timedOut ? `${method} timed out` : `${method} failed to start`,
    };
  }
  if (result.status !== 0) {
    return { ok: false, error: `${method} exited ${result.status}` };
  }
  return parseJson(result.stdout, method);
}

const CHECKS = [
  {
    key: "snapshotPresent",
    evaluate: (ctx) =>
      ctx.snapshotPresent
        ? { ok: true }
        : { ok: false, error: "snapshot.json missing" },
  },
  {
    key: "rpcOk",
    evaluate: (ctx) => {
      if (!ctx.snapshotCall.ok) {
        return { ok: false, error: ctx.snapshotCall.error };
      }
      const payload = ctx.snapshotCall.value;
      if (isRecord(payload) && isRecord(payload.summary) && Array.isArray(payload.nodes)) {
        return { ok: true };
      }
      return { ok: false, error: "lanarchy.snapshot missing summary/nodes" };
    },
  },
  {
    key: "controlUiListed",
    evaluate: (ctx) => {
      if (!ctx.listCall.ok) {
        return { ok: false, error: ctx.listCall.error };
      }
      const payload = ctx.listCall.value;
      const plugins = isRecord(payload) && Array.isArray(payload.plugins) ? payload.plugins : [];
      const listed = plugins.some(
        (item) =>
          isRecord(item) &&
          item.pluginId === "lanarchy" &&
          typeof item.entryUrl === "string" &&
          item.entryUrl.length > 0,
      );
      return listed
        ? { ok: true }
        : { ok: false, error: "plugins.controlUi.list has no lanarchy entryUrl" };
    },
  },
];

function collectOutputs() {
  const snapshotCall = gatewayCall("lanarchy.snapshot");
  const listCall = gatewayCall("plugins.controlUi.list");
  return {
    snapshotPresent: existsSync(join(lanarchyStateDir(), "snapshot.json")),
    snapshotCall,
    listCall,
  };
}

function projectLiveSmoke(ctx) {
  const errors = [];
  const result = {
    snapshotPresent: false,
    rpcOk: false,
    controlUiListed: false,
    errors,
  };
  for (const check of CHECKS) {
    const verdict = check.evaluate(ctx);
    result[check.key] = verdict.ok;
    if (!verdict.ok) {
      errors.push(verdict.error);
    }
  }
  return result;
}

const result = projectLiveSmoke(collectOutputs());
process.stdout.write(`${JSON.stringify(result)}\n`);
process.exit(result.errors.length > 0 ? 1 : 0);
