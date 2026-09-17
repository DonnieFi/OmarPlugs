# Lanarchy UX iteration log

Reference clones (gitignored under `.refs/`):

- [nixfred.pulse](https://github.com/nixfred/pulse) — local `~/.config/omarchy/plugins/nixfred.pulse`
- [wesleygrimes/omastorm](https://github.com/wesleygrimes/omastorm) — `.refs/omastorm`

## Iteration 1 (2026-09-16)

- Shipped inventory setup + Pulse-height list rows (5oy.1).
- Glance JSON three-band contract frozen.

## Iteration 2 (2026-09-16)

- Architecture sidecar (`docs/architecture.md`), history + notify Python.
- First letterbox map (small boxes, LAN capped at 12).
- HTML throwaway mock in `scratch/letterbox-map/`.

## Iteration 3 (2026-09-16)

- LAN **super-node** card (`__lan__`), hub-centered layout, edges collapse to cluster.
- Pulse tokens (`ink`, `card`, `cardEdge`, 14px card radius).
- Map / List `SegBtn` under header.

**Gap (user feedback):** Not Pulse/Omastorm enough. Map/list toggle easy to miss. Notify buried in detail strip, not on nodes.

## Iteration 4 (2026-09-16)

**Targets from reference code:**

| Pattern | Source | Apply to Lanarchy |
|---------|--------|-------------------|
| Page switcher `Action` pills | Pulse `Panel.qml` ~324–506 | Map / List in header row |
| Popup backdrop + heading rhythm | Pulse `KeyboardPanel` body `Rectangle` + `Heading` | Letterbox popover chrome |
| Status line + live dot | Omastorm `Popover.qml` ~100–107 | Header pill beside as-of |
| Map frame border | Omastorm `Popover.qml` ~108–113 | Letterbox canvas inset |
| Accent panel border | Omastorm `RadarBar.qml` `Border.flat(Color.accent, 2)` | Map mode `KeyboardPanel.borderSpec` |

**Interaction:** Per-node **notify chip** on each map card (click toggles inventory `notify`). LAN cluster opens list; no cluster-wide mute.

**Shipped:** Header Map/List `TabAction`, LIVE status pill, accent letterbox border, Omastorm-style map inset, ALERT/MUTE on nodes. Keys `m` / `l` / `r`.

**HTML mirror:** `scratch/letterbox-map/index.html` (iteration 4 — tabs, pill, super-node, hover tips, list panel). Open in Firefox alongside the live popover.

**Hover (Pulse-like):** `PanelToolTip` on map cards and list `MeshRow` rows (`mapCardTooltip` / `listRowTooltip`), card fill brightens on hover.

## Iteration 5 (2026-09-16)

User: old list was better (horizontal, colour lights, scroll if tall); HA missing; Bernie should be one thing; network is noisy so toggles matter; dash not beautific.

**Shipped:**
- Service groups (`groups_lib.py`): Home Assistant first, Bernie = host+443+api, Cameras/Frigate, Pi-hole pair, Caddy, etc.
- Default dash is **List**: 22px colour-light rows (green/amber/red), member dots on groups, link/rate/TTFB metrics.
- **LAN** / **PROXIES** toggles (keys `n` / `p`) show leftover noisy hosts only. Grouped twins stay off those lists.
- Map middle band is services, not 17 `.lan` names.
- Flickable list caps at 420px and scrolls.
- HTML mock `scratch/letterbox-map/index.html` rebuilt as the dash.

## Iteration 6 (2026-09-16)

User: iteration 5 list is fire; map took a step back.

**Cause:** Flat three-band of 9 service cards (no hub, no LAN cluster, MUTED-only chip). Opening the popover also forced Map over the list.

**Restore:** Letterbox again — machines on top, **Caddy hub** center (accent border), grouped services one row, leftover hosts as one **LAN cluster** with member lights. Click cluster → List with LAN on. ALERT/MUTE chips back. Open keeps the last tab. List unchanged.

## Bolts (2026-09-16)

Daemon owns probes. Panel reads `snapshot.json`. Cards: link/rate/uptime, amber if eth < 1G, LAN cluster shows dns/neighbors/unknown, SSH and Wake on the detail strip. Edges pulse from throughput when we have it.
