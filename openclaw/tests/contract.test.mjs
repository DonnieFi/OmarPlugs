import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  projectLanarchySnapshot,
  readLanarchyDashboardSnapshot,
} from "../dist/src/contract.js";

const asOf = new Date().toISOString();
const raw = {
  as_of: asOf,
  machines: [
    {
      id: "host-1",
      label: "builder",
      host: "10.0.0.7",
      ip: "10.0.0.7",
      mac: "aa:bb:cc:dd:ee:ff",
      status: "up",
      rtt_ms: 4,
      rates: { rx_bps: 2_000 },
    },
    {
      id: "host-2",
      label: "192.168.1.92",
      host: "192.168.1.92",
      status: "up",
      rtt_ms: 1.2,
    },
  ],
  groups: [
    {
      id: "svc-caddy",
      label: "Caddy",
      status: "degraded",
      up: 1,
      down: 1,
      total: 2,
      members: [{ id: "ha.lan", label: "ha.lan", status: "up", role: "http" }],
    },
  ],
  gateway: { label: "Gateway", ip: "192.168.1.1", status: "up" },
  wan: { label: "Internet", public_ip: "203.0.113.9", status: "up" },
  unifi: { apiKey: "must-not-leak" },
  events: [{ id: "host-1", from: "down", to: "up", changes: 2 }],
  flaps: { "host-1": 3 },
  new_devices: [{ ip: "10.0.0.8", mac: "de:ad:be:ef:00:01" }],
};

const snapshot = projectLanarchySnapshot(raw);
assert.equal(snapshot.stale, false);
assert.equal(snapshot.summary.up, 2);
assert.equal(snapshot.summary.degraded, 1);
assert.equal(snapshot.summary.newDevices, 1);
assert.equal(snapshot.events[0].label, "builder");
assert.equal(snapshot.flapping[0].label, "builder");
assert.equal(snapshot.nodes[0].host, "10.0.0.7");
assert.equal(snapshot.nodes[0].ip, "10.0.0.7");
assert.equal(snapshot.nodes[1].label, "192.168.1.92");
assert.equal(snapshot.gateway?.ip, "192.168.1.1");

const encoded = JSON.stringify(snapshot);
for (const visible of ["10.0.0.7", "192.168.1.92", "192.168.1.1"]) {
  assert.equal(encoded.includes(visible), true, `expected visible ${visible}`);
}
for (const secret of ["aa:bb:cc:dd:ee:ff", "203.0.113.9", "must-not-leak"]) {
  assert.equal(encoded.includes(secret), false, `expected withheld ${secret}`);
}

const state = mkdtempSync(join(tmpdir(), "lanarchy-contract-"));
writeFileSync(join(state, "snapshot.json"), JSON.stringify(raw));
assert.equal(readLanarchyDashboardSnapshot(state).nodes[0].label, "builder");

writeFileSync(join(state, "snapshot.json"), "not-json");
assert.throws(() => readLanarchyDashboardSnapshot(state), /unavailable/);
writeFileSync(join(state, "snapshot.json"), "x".repeat(2_000_001));
assert.throws(() => readLanarchyDashboardSnapshot(state), /too large/);

console.log("Lanarchy DTO contract ok");
