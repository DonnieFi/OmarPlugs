import type {
  DashboardGroup,
  DashboardNode,
  LanarchyDashboardSnapshot,
} from "../src/contract.js";

export const GATEWAY_ID = "__gateway__";

export type MapNodeKind = "machine" | "gateway" | "hub" | "service" | "external";

export type MapNode = {
  id: string;
  label: string;
  kind: MapNodeKind;
  status: string;
  rttMs: number | null;
  host: string | null;
  ip: string | null;
  rxBps: number | null;
  txBps: number | null;
  subline: string | null;
};

export type MapEdge = {
  from: string;
  to: string;
  kind: "lan" | "service" | "wan";
  measured: boolean;
  bps: number;
};

export type MapBox = { id: string; x: number; y: number; w: number; h: number };

export type MapRoute = {
  from: string;
  to: string;
  points: Array<{ x: number; y: number }>;
  measured: boolean;
  bps: number;
  kind: string;
  down: boolean;
};

export type MapLayout = {
  width: number;
  height: number;
  boxes: MapBox[];
  routes: MapRoute[];
  rowLanes: number[];
  trunkX: number;
  wanAnchorId: string | null;
};

export type MapGraph = {
  nodes: MapNode[];
  edges: MapEdge[];
  gatewayId: string | null;
  hubId: string | null;
  machineIds: string[];
  lowerNodeIds: string[];
  wanLabel: string;
};

const CARD_H = 94;
const CARD_W_MAX = 150;
const CARD_MIN = 88;
const GAP_X = 8;
const GAP_Y_MACHINE = 30;
const GAP_Y_SERVICE = 10;
const TRUNK_COL = 30;
const GW_COL = 172;
const PAD_X = 16;
const PAD_TOP = 28;
const PAD_BOTTOM = 16;
const LOWER_GAP = 26;

function flowBps(rx: number | null, tx: number | null): { measured: boolean; bps: number } {
  if (rx === null && tx === null) {
    return { measured: false, bps: 0 };
  }
  const rxV = rx !== null && Number.isFinite(rx) ? Math.max(0, rx) : 0;
  const txV = tx !== null && Number.isFinite(tx) ? Math.max(0, tx) : 0;
  return { measured: true, bps: Math.max(rxV, txV) };
}

function hostLine(node: Pick<MapNode, "host" | "ip" | "rttMs">): string {
  const host = node.host || node.ip;
  const parts: string[] = [];
  if (host) {
    parts.push(host);
  }
  if (node.rttMs !== null && Number.isFinite(node.rttMs)) {
    parts.push(`${node.rttMs < 10 ? node.rttMs.toFixed(1) : Math.round(node.rttMs)} ms`);
  } else if (host) {
    parts.push("—");
  }
  return parts.join(" · ");
}

function machineSubline(node: DashboardNode): string | null {
  return hostLine({ host: node.host, ip: node.ip, rttMs: node.rttMs });
}

function dashboardToMapNode(
  id: string,
  label: string,
  kind: MapNodeKind,
  status: string,
  host: string | null,
  ip: string | null,
  rttMs: number | null,
  rxBps: number | null,
  txBps: number | null,
  subline: string | null,
): MapNode {
  return {
    id,
    label,
    kind,
    status,
    rttMs,
    host,
    ip,
    rxBps,
    txBps,
    subline,
  };
}

function hubGroup(groups: DashboardGroup[]): DashboardGroup | null {
  const caddy = groups.find((group) => /caddy/i.test(group.label));
  return caddy ?? groups[0] ?? null;
}

export function snapshotToGraph(snapshot: LanarchyDashboardSnapshot): MapGraph {
  const nodes: MapNode[] = [];
  const machineIds: string[] = [];
  const lowerNodeIds: string[] = [];

  for (const row of snapshot.nodes) {
    if (row.kind !== "machine") {
      continue;
    }
    machineIds.push(row.id);
    nodes.push(
      dashboardToMapNode(
        row.id,
        row.label,
        "machine",
        row.status,
        row.host,
        row.ip,
        row.rttMs,
        row.rxBps,
        row.txBps,
        machineSubline(row),
      ),
    );
  }

  let gatewayId: string | null = null;
  if (snapshot.gateway) {
    gatewayId = GATEWAY_ID;
    const gw = snapshot.gateway;
    const sub = [gw.host, gw.ip].filter(Boolean).join(" · ") || "gateway";
    nodes.push(
      dashboardToMapNode(
        GATEWAY_ID,
        gw.label,
        "gateway",
        gw.status,
        gw.host,
        gw.ip,
        gw.rttMs,
        null,
        null,
        sub,
      ),
    );
  }

  const hub = hubGroup(snapshot.groups);
  let hubId: string | null = null;
  const serviceGroupIds = new Set<string>();

  if (hub) {
    hubId = hub.id;
    const hubSub = `${hub.up}/${hub.total} up${hub.zone ? ` · ${hub.zone}` : ""}`;
    nodes.push(
      dashboardToMapNode(
        hub.id,
        hub.label,
        "hub",
        hub.status,
        null,
        null,
        null,
        null,
        null,
        hubSub,
      ),
    );
    lowerNodeIds.push(hub.id);
    serviceGroupIds.add(hub.id);

    for (const member of hub.members) {
      const memberId = `${hub.id}::${member.label}`;
      lowerNodeIds.push(memberId);
      nodes.push(
        dashboardToMapNode(
          memberId,
          member.label,
          "service",
          member.status,
          null,
          null,
          member.rttMs,
          null,
          null,
          member.role ? `via hub · ${member.role}` : "via hub",
        ),
      );
    }
  }

  for (const group of snapshot.groups) {
    if (serviceGroupIds.has(group.id)) {
      continue;
    }
    const zone = group.zone || "";
    const kind: MapNodeKind = zone === "external" ? "external" : "service";
    lowerNodeIds.push(group.id);
    nodes.push(
      dashboardToMapNode(
        group.id,
        group.label,
        kind,
        group.status,
        null,
        null,
        null,
        null,
        null,
        `${group.up}/${group.total} up`,
      ),
    );
  }

  const anchor = gatewayId ?? hubId;
  const edges: MapEdge[] = [];
  if (anchor) {
    for (const mid of machineIds) {
      if (mid === anchor) {
        continue;
      }
      const machine = nodes.find((node) => node.id === mid);
      const flow = machine ? flowBps(machine.rxBps, machine.txBps) : { measured: false, bps: 0 };
      edges.push({ from: mid, to: anchor, kind: "lan", measured: flow.measured, bps: flow.bps });
    }
    if (gatewayId && hubId && hubId !== gatewayId) {
      const hubNode = nodes.find((node) => node.id === hubId);
      const flow = hubNode ? flowBps(hubNode.rxBps, hubNode.txBps) : { measured: false, bps: 0 };
      edges.push({ from: hubId, to: gatewayId, kind: "lan", measured: flow.measured, bps: flow.bps });
    }
    for (const id of lowerNodeIds) {
      if (id === hubId || id === gatewayId) {
        continue;
      }
      const node = nodes.find((item) => item.id === id);
      const from = hubId ?? anchor;
      const kind = node?.kind === "external" ? "wan" : "service";
      edges.push({ from, to: id, kind, measured: false, bps: 0 });
    }
  }

  const wanLabel = snapshot.wan?.label || "Internet";

  return {
    nodes,
    edges,
    gatewayId,
    hubId,
    machineIds,
    lowerNodeIds,
    wanLabel,
  };
}

function boxById(boxes: MapBox[], id: string): MapBox | undefined {
  return boxes.find((box) => box.id === id);
}

function nodeById(graph: MapGraph, id: string): MapNode | undefined {
  return graph.nodes.find((node) => node.id === id);
}

function laneBelow(box: MapBox, rowLanes: number[]): number {
  const bottom = box.y + box.h;
  let best = -1;
  for (const ly of rowLanes) {
    if (ly > bottom + 1 && (best < 0 || ly < best)) {
      best = ly;
    }
  }
  return best;
}

function machineUplinkPoints(
  aBox: MapBox,
  bBox: MapBox,
  laneY: number,
  trunkX: number,
): Array<{ x: number; y: number }> | null {
  const aBottom = aBox.y + aBox.h;
  if (!(laneY > aBottom + 2)) {
    return null;
  }
  const aCx = aBox.x + aBox.w / 2;
  const enterY = bBox.y + bBox.h / 2;
  const enterX = bBox.x;
  if (!(trunkX > aBox.x + aBox.w) || !(trunkX < bBox.x)) {
    return null;
  }
  return [
    { x: aCx, y: aBottom },
    { x: aCx, y: laneY },
    { x: trunkX, y: laneY },
    { x: trunkX, y: enterY },
    { x: enterX, y: enterY },
  ];
}

function mapEdgePoints(
  aBox: MapBox,
  bBox: MapBox,
  kind: string,
): Array<{ x: number; y: number }> {
  const aCx = aBox.x + aBox.w / 2;
  const aCy = aBox.y + aBox.h / 2;
  const bCx = bBox.x + bBox.w / 2;
  const bCy = bBox.y + bBox.h / 2;
  const stub = 10;
  const aBot = aBox.y + aBox.h;
  const bBot = bBox.y + bBox.h;
  const aAbove = aBot <= bBox.y + 2;
  const bAbove = bBot <= aBox.y + 2;

  let a0: { x: number; y: number };
  let b0: { x: number; y: number };

  if (aAbove) {
    a0 = { x: aCx, y: aBot };
    b0 = { x: bCx, y: bBox.y };
  } else if (bAbove) {
    a0 = { x: aCx, y: aBox.y };
    b0 = { x: bCx, y: bBot };
  } else if (aCx <= bCx) {
    a0 = { x: aBox.x + aBox.w, y: aCy };
    b0 = { x: bBox.x, y: bCy };
  } else {
    a0 = { x: aBox.x, y: aCy };
    b0 = { x: bBox.x + bBox.w, y: bCy };
  }

  const stubOut = (p: { x: number; y: number }, toward: "left" | "right" | "top" | "bottom") => {
    if (toward === "left") {
      return { x: p.x - stub, y: p.y };
    }
    if (toward === "right") {
      return { x: p.x + stub, y: p.y };
    }
    if (toward === "top") {
      return { x: p.x, y: p.y - stub };
    }
    return { x: p.x, y: p.y + stub };
  };

  const aSide = aAbove ? "bottom" : bAbove ? "top" : aCx <= bCx ? "right" : "left";
  const bSide = aAbove ? "top" : bAbove ? "bottom" : aCx <= bCx ? "left" : "right";
  const a1 = stubOut(a0, aSide);
  const b1 = stubOut(b0, bSide);
  const pts = [a0, a1];

  if (Math.abs(a1.x - b1.x) < 1.5 || Math.abs(a1.y - b1.y) < 1.5) {
    pts.push(b1);
  } else if (aAbove || bAbove) {
    const gapLo = aAbove ? aBot : bBot;
    const gapHi = aAbove ? bBox.y : aBox.y;
    const midY = (gapLo + gapHi) / 2;
    pts.push({ x: a1.x, y: midY }, { x: b1.x, y: midY }, b1);
  } else {
    const gapL = aCx <= bCx ? aBox.x + aBox.w : bBox.x + bBox.w;
    const gapR = aCx <= bCx ? bBox.x : aBox.x;
    const midX = (gapL + gapR) / 2;
    pts.push({ x: midX, y: a1.y }, { x: midX, y: b1.y }, b1);
  }
  pts.push(b0);
  if (kind === "wan") {
    return pts;
  }
  return pts;
}

function colBand(
  ids: string[],
  y: number,
  colW: number,
  kind: "machine" | "service",
  boxes: MapBox[],
  rowLanes: number[],
): number {
  const n = ids.length;
  if (n <= 0) {
    return y;
  }
  const gapY = kind === "machine" ? GAP_Y_MACHINE : GAP_Y_SERVICE;
  const perRow = Math.max(1, Math.floor((colW + GAP_X) / (CARD_MIN + GAP_X)));
  const rowsUsed = Math.ceil(n / perRow);
  const columns = Math.max(1, Math.ceil(n / rowsUsed));
  const cw = Math.max(CARD_MIN, Math.min(CARD_W_MAX, (colW - GAP_X * (columns - 1)) / columns));
  const spanW = cw * columns + GAP_X * (columns - 1);
  const startX = Math.max(0, (colW - spanW) / 2);

  if (kind === "machine") {
    rowLanes.length = 0;
    for (let r = 0; r < rowsUsed; r++) {
      rowLanes.push(y + (r + 1) * CARD_H + r * gapY + gapY / 2);
    }
  }

  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / columns);
    const c = i % columns;
    boxes.push({
      id: ids[i],
      x: PAD_X + startX + c * (cw + GAP_X),
      y: y + r * (CARD_H + gapY),
      w: cw,
      h: CARD_H,
    });
  }
  return y + rowsUsed * CARD_H + (rowsUsed - 1) * gapY;
}

export function layoutMap(graph: MapGraph, width: number): MapLayout {
  const boxes: MapBox[] = [];
  const rowLanes: number[] = [];
  const innerW = Math.max(320, width);
  const gridW = Math.max(200, innerW - TRUNK_COL - GW_COL - GAP_X - PAD_X * 2);
  const trunkX = PAD_X + gridW + TRUNK_COL / 2;
  const barX = PAD_X + gridW + TRUNK_COL + GAP_X;
  const gatewayW = Math.min(GW_COL, Math.max(150, GW_COL));

  let machineBottom = colBand(graph.machineIds, PAD_TOP, gridW, "machine", boxes, rowLanes);

  const gridTop = PAD_TOP;
  const egressY = Math.max(
    gridTop,
    gridTop + (machineBottom - gridTop - CARD_H) / 2,
  );

  if (graph.gatewayId) {
    boxes.push({
      id: graph.gatewayId,
      x: barX + (gatewayW - Math.min(gatewayW, 150)) / 2,
      y: egressY,
      w: Math.max(150, gatewayW - 6),
      h: CARD_H,
    });
  }

  let cursorY = machineBottom + LOWER_GAP;
  const leftW = gridW + TRUNK_COL + GAP_X;

  if (graph.hubId) {
    const hubW = 120;
    const hubH = 100;
    boxes.push({
      id: graph.hubId,
      x: PAD_X + (leftW - hubW) / 2,
      y: cursorY,
      w: hubW,
      h: hubH,
    });
    cursorY += hubH + LOWER_GAP;
  }

  const serviceIds = graph.lowerNodeIds.filter((id) => id !== graph.hubId);
  if (serviceIds.length) {
    cursorY = colBand(serviceIds, cursorY, leftW, "service", boxes, rowLanes) + LOWER_GAP;
  }

  const gutterY = rowLanes.length ? rowLanes[rowLanes.length - 1] : machineBottom;
  let lowest = gutterY;
  for (const box of boxes) {
    lowest = Math.max(lowest, box.y + box.h);
  }
  const height = Math.max(lowest + PAD_BOTTOM, 280);

  const routes: MapRoute[] = [];
  for (const edge of graph.edges) {
    const aBox = boxById(boxes, edge.from);
    const bBox = boxById(boxes, edge.to);
    if (!aBox || !bBox) {
      continue;
    }
    const rowA = nodeById(graph, edge.from);
    const rowB = nodeById(graph, edge.to);
    const down = rowA?.status === "down" || rowB?.status === "down";
    let points: Array<{ x: number; y: number }> | null = null;
    if (edge.kind === "lan" && graph.machineIds.includes(edge.from)) {
      const laneY = laneBelow(aBox, rowLanes);
      if (laneY > 0) {
        points = machineUplinkPoints(aBox, bBox, laneY, trunkX);
      }
    }
    if (!points) {
      points = mapEdgePoints(aBox, bBox, edge.kind);
    }
    routes.push({
      from: edge.from,
      to: edge.to,
      points,
      measured: edge.measured,
      bps: edge.bps,
      kind: edge.kind,
      down,
    });
  }

  return {
    width: innerW,
    height,
    boxes,
    routes,
    rowLanes,
    trunkX,
    wanAnchorId: graph.gatewayId,
  };
}

export function flowSpeedPxPerSec(bps: number): number {
  if (bps < 1000) {
    return 0;
  }
  const t = Math.min(1, Math.log10(1 + bps / 1000) / 3.5);
  return 12 + 188 * t;
}

export function flowPacketCount(bps: number): number {
  if (bps < 1000) {
    return 0;
  }
  return Math.max(1, Math.min(6, 1 + Math.round(Math.log10(bps / 1000) * 1.8)));
}

export function polylineLength(points: Array<{ x: number; y: number }>): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y);
  }
  return total;
}

export function pointAlong(
  points: Array<{ x: number; y: number }>,
  lengths: number[],
  distance: number,
): { x: number; y: number } {
  const total = lengths[lengths.length - 1] ?? 0;
  let d = ((distance % total) + total) % total;
  for (let i = 1; i < points.length; i++) {
    if (d <= lengths[i]) {
      const span = Math.max(1e-6, lengths[i] - lengths[i - 1]);
      const t = (d - lengths[i - 1]) / span;
      return {
        x: points[i - 1].x + (points[i].x - points[i - 1].x) * t,
        y: points[i - 1].y + (points[i].y - points[i - 1].y) * t,
      };
    }
  }
  return points[points.length - 1] ?? { x: 0, y: 0 };
}

export function segmentLengths(points: Array<{ x: number; y: number }>): number[] {
  const lengths = [0];
  for (let i = 1; i < points.length; i++) {
    lengths.push(lengths[i - 1] + Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y));
  }
  return lengths;
}
