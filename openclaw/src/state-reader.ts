import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const SNAPSHOT_FILE = "snapshot.json";
export const MAX_SNAPSHOT_BYTES = 2_000_000;

export function defaultLanarchyStateDir(): string {
  const xdgStateHome = process.env.XDG_STATE_HOME?.trim();
  return join(xdgStateHome || join(homedir(), ".local", "state"), "lanarchy");
}

/** Read only the daemon's atomic last-glance file; never run a collector here. */
export function readLanarchySnapshot(stateDir: string): unknown {
  const snapshotPath = join(stateDir, SNAPSHOT_FILE);
  let size: number;
  try {
    size = statSync(snapshotPath).size;
  } catch {
    throw new Error("Lanarchy snapshot unavailable");
  }
  if (size > MAX_SNAPSHOT_BYTES) {
    throw new Error("Lanarchy snapshot is too large");
  }
  try {
    const parsed: unknown = JSON.parse(readFileSync(snapshotPath, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid shape");
    }
    return parsed;
  } catch {
    throw new Error("Lanarchy snapshot unavailable");
  }
}
