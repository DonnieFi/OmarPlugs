# Lanarchy architecture (OmarPlugs-5oy.9)

Product name **Lanarchy**. Plugin id remains `donnie.homelab-mesh` until an optional rename bead lands.

This document signs the sidecar formats that **5oy.2**, **5oy.3**, and **5oy.6** share. The bar **glance probe JSON stays unchanged** (`as_of`, `machines`, `lan`, `proxies`).

## Config paths

All user-writable state lives under:

`~/.config/omarchy/plugins/homelab-mesh/`

| File | Purpose |
|------|---------|
| `inventory.json` | v2 node list (source of truth for probes + UI) |
| `history.json` | Ring buffer of RTT samples and status events |
| `notify-state.json` | Ephemeral fail-streak counters (rebuilt from history on miss) |

Repo-shipped `homelab-mesh/inventory.json` is the default template copied on first enable.

## Inventory v2 extension

Root shape stays `{ "schemaVersion": 2, "nodes": [...] }`.

Optional **root** fields (v2.1, ignored by readers that only know v2):

```json
{
  "schemaVersion": 2,
  "settings": {
    "failStreakThreshold": 3
  },
  "edges": [
    { "from": "deba", "to": "git.lan", "kind": "hub" }
  ],
  "nodes": []
}
```

Per-node optional fields:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `notify` | boolean | `true` | When `false`, no fail-streak alerts for this id |
| `mapBand` | string | derived from `type` | Override band key for letterbox layout (`machine`, `host`, `proxy`) |
| `mapOrder` | integer | list order | Stable sort within band |

Normalization rules:

- Missing `notify` → treat as `true`.
- Unknown keys on nodes are preserved through load/save when present in file (forward-compatible).
- `edges[]` is **curated**, not auto N². Empty or missing → derive default hub edges (see below).

## Edge graph (v1)

**Purpose:** Letterbox map draws lines between ids. Pulse period uses **RTT at endpoints**, not throughput (**5oy.5** adds real metrics later).

Default derivation when `edges` is absent:

1. Pick **hub** = first `type: proxy` with `check: http` and label containing `caddy`, else first proxy, else first machine id.
2. For each `machine`, add `{ from: machine.id, to: hub, kind: "hub" }`.
3. For each `host`, add `{ from: hub, to: host.id, kind: "lan" }` (cap at 24 hosts in UI; rest in LAN super-node clip).
4. Optional `edges` in inventory **replace** defaults when non-empty.

Edge record:

```json
{ "from": "kiritsuke", "to": "caddy-health", "kind": "hub" }
```

`kind` is cosmetic for stroke style only in v1.

## History ring (`history.json`)

Single JSON file, append-friendly structure, rewritten atomically (`.tmp` + rename) like inventory.

```json
{
  "schemaVersion": 1,
  "retentionHours": 24,
  "probeIntervalSec": 15,
  "series": {
    "deba": {
      "samples": [
        { "ts": "2026-09-16T19:00:00-03:00", "status": "up", "rtt_ms": 1.2 }
      ]
    }
  },
  "events": [
    {
      "ts": "2026-09-16T18:55:00-03:00",
      "id": "deba",
      "from": "up",
      "to": "down"
    }
  ]
}
```

**Retention:** Target ~24h wall clock at the configured probe interval.

- Cap **samples per node** at `max(96, retentionHours * 3600 / probeIntervalSec)` (96 ≈ 24h @ 15s).
- On save, drop oldest samples and events older than `retentionHours`.
- Optional future compaction: merge samples older than 6h into 5-minute buckets (not required for v1 proof).

**Writers:** `probe.py` (or a small `history_cli.py append` invoked from probe after each run) appends one sample per probed machine/host with RTT; proxies append status-only samples (`rtt_ms` omitted).

**Readers:** QML via `python3 history_cli.py sparkline --id deba --n 32` → JSON array of numbers for sparkline; map/detail strip uses last sample status + RTT.

## Notify (5oy.2)

**Policy:**

- Fail-streak threshold **N** = `settings.failStreakThreshold` or **3**.
- Consecutive probe results with `status === "down"` for a node id increment streak in `notify-state.json`.
- When streak reaches N and `notify !== false` on that node, emit **one** notification via `omarchy-notification-send`, then set `alerted: true` on that node entry until status returns to `up`.
- Recovery to `up` clears streak and `alerted`.

`notify-state.json`:

```json
{
  "schemaVersion": 1,
  "nodes": {
    "deba": { "downStreak": 2, "alerted": false, "lastStatus": "down" }
  }
}
```

Inventory `notify: false` skips increment and send for that id.

## Glance vs sidecars

| Surface | Contract |
|---------|----------|
| `probe.py` stdout | Unchanged three-band glance |
| Inventory | Nodes + optional edges/settings/notify |
| History | RTT + transitions |
| Notify state | Streaks only |

Panel merges glance rows with inventory `notify` for toggles in map and Setup.

## 5oy.5 traffic (deferred)

No fake throughput on edges. Real inter-host metrics require a signed data source (daemon, SNMP, or agent). Until then, edge animation uses `max(rtt_ms(from), rtt_ms(to))` from the latest glance/history sample.
