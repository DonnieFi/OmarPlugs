# Lanarchy Control UI map — design decision

**Winner: Map A (Manhattan trunk/gutter).** Build that one.

## Why A wins (experience-first)

1. **It answers "what is my network doing" at a glance.** The left-to-right
   machine → trunk → gateway → WAN-arrow chain matches the physical truth
   (`rebuildMapEdges`: every machine reaches the internet through the default
   gateway) and reads in one sweep. B's three stacked stages force three
   separate left-to-right scans plus vertical handoff tracing.
2. **It is the Omarchy view, shrunk.** Users coming from the plugin see the
   same spatial model — grid, trunk, gateway, arrow — so there is nothing new
   to learn. B invents a pipeline metaphor the plugin never had.
3. **It scales down honestly.** When machines wrap to more rows, A grows
   downward (one gutter lane per row, trunk extends). B's single LAN rail
   stretches full-width per chip and the rail-overlap trick (one glowing
   segment per measured host) turns to mud past ~4 hosts.
4. **Failure is localized in A, smeared in B.** A down host dims exactly its
   own route to the trunk. In B the dead chip still sits on the shared rail,
   so "which wire is broken" needs reading labels; the rail is always lit.
5. **Motion means bytes in both, but A shows direction.** Packets walk the
   card → trunk → gateway path, so rx-vs-tx direction is visible topology. In
   B everything converges on one rail and direction collapses to "moving right".

## What to steal from B anyway

- Stage tags (`STAGE n · NAME`) as an accessibility/aria label pattern for the
  widget's regions — cheap orientation win, no layout cost.
- The dashed service-drop styling for unmeasured hub→service links (already
  folded into A's lower-section wiring).

## Layout algorithm sketch (for the Lit implementer)

Port of `recalcMapLayout` + `machineUplinkPoints`, DOM-measured instead of
QML-placed (widget cell width is unknown until render):

```
measure(cellWidth):
  gwW    = 172                                  # fixed gateway column
  trunkW = 30                                   # reserved corridor, never drawn in
  gridW  = cellWidth - gwW - trunkW - gaps
  cols   = max(1, floor((gridW + gapX) / (minCardW + gapX)))
  place machine cards in row-major order, cardH fixed, gutterH = 26
  laneY[r] = bottom(row r) + gutterH/2          # one lane per row, own gutter
  trunkX   = gridW + trunkW/2
  gateway  = vertically centered vs machine band
  hub/services below machine band (flow from actual band bottom)

route(card, gateway):                            # machineUplinkPoints
  aCx = card.cx; lane = first laneY below card.bottom
  return [ (aCx, card.bottom), (aCx, lane), (trunkX, lane),
           (trunkX, gateway.midY), (gateway.left, gateway.midY) ]

edge visual:
  flow = measured iff either endpoint has rates (edgeFlow); else static lane
  width = edgeFlowWidth(bps); speed = flowSpeedPxPerSec(bps)
  count = flowPacketCount(bps); down endpoint => dim lane, zero packets
  service links (hub->service): dashed, unmeasured unless rates exist
  WAN: arrow off gateway, never an edge, never packets
```

Recompute on resize (ResizeObserver) and on snapshot refresh; keep packet
`off` offsets across rebuilds so flow does not visibly restart.

## Typed MapGraph (implementer contract)

Project `LanarchyDashboardSnapshot` → `MapGraph` in one pure function so the
Lit renderer never re-parses raw snapshot shape. `host`/`ip` are already on
the DTO (`contract.ts`); address redaction was removed. Do not reintroduce it.

```ts
type MapStatus = "up" | "down" | "degraded" | "unknown" | "seen";

type MapNode = {
  id: string;
  label: string;
  kind: "machine" | "gateway" | "hub" | "service" | "external";
  status: MapStatus;
  rttMs: number | null;
  host?: string;      // NEW — needs contract.ts extension (currently redacted)
  ip?: string;        // NEW — needs contract.ts extension (currently redacted)
  rxBps?: number | null;
  txBps?: number | null;
  subline?: string;   // second line under label, e.g. "192.168.1.7 · 0.4 ms"
};

type MapEdge = {
  from: string;
  to: string;
  kind: "lan" | "service" | "wan";
  measured: boolean;  // false => static lane, no packets, ever
  bps: number;        // max(rx,tx) of busier endpoint, 0 when unmeasured
};

type MapGraph = {
  nodes: MapNode[];
  edges: MapEdge[];
  asOf: string | null;
  stale: boolean;
  summary: { up: number; down: number; machines: number; services: number };
};
```

Projection rules (mirror `rebuildMapEdges`): every machine → gateway `lan`
edge (skip self); hub → gateway `lan` edge when hub ≠ gateway; hub/anchor →
each service group (`service`, or `wan` when `zone === "external"`); no edge
to the internet. `measured`/`bps` via the `edgeFlow` busier-endpoint rule.

## Prototypes

- `map-a-manhattan.html` — winner, faithful trunk/gutter.
- `map-b-swimlane.html` — rejected alternate, kept for the rail/aria ideas.
- Both are throwaway: vanilla HTML/SVG/rAF, shared fixture
  (`deba 192.168.1.7` hot-measured, `aka 192.168.1.20` down,
  gateway `redUltra 192.168.1.1`, WAN arrow, caddy + 3 services).
