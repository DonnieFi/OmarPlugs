import { readLanarchySnapshot } from "./state-reader.js";

const MAX_NODES = 64;
const MAX_GROUPS = 64;
const MAX_MEMBERS = 32;
const MAX_EVENTS = 12;
const MAX_FLAPPING = 12;
const MAX_SPARK_POINTS = 32;
const STALE_AFTER_MS = 45_000;
const MAX_TEXT = 160;

export type DashboardStatus = "up" | "down" | "degraded" | "unknown" | "seen";

export type DashboardNode = {
  id: string;
  label: string;
  kind: "machine" | "lan" | "proxy";
  status: DashboardStatus;
  host: string | null;
  ip: string | null;
  rttMs: number | null;
  rxBps: number | null;
  txBps: number | null;
  uptimeS: number | null;
  link: { speedMbit: number | null; grade: string | null } | null;
  os: string | null;
  sparkline: number[];
};

export type DashboardMember = {
  label: string;
  role: string;
  status: DashboardStatus;
  rttMs: number | null;
};

export type DashboardGroup = {
  id: string;
  label: string;
  status: DashboardStatus;
  up: number;
  down: number;
  total: number;
  zone: string | null;
  members: DashboardMember[];
};

export type DashboardEndpoint = {
  label: string;
  status: DashboardStatus;
  host: string | null;
  ip: string | null;
  rttMs: number | null;
};

export type DashboardEvent = {
  label: string;
  from: DashboardStatus;
  to: DashboardStatus;
  changes: number;
  at: string | null;
};

export type DashboardFlapping = {
  label: string;
  changes: number;
};

export type LanarchyDashboardSnapshot = {
  schemaVersion: 1;
  asOf: string | null;
  stale: boolean;
  summary: {
    total: number;
    up: number;
    down: number;
    degraded: number;
    unknown: number;
    machines: number;
    services: number;
    newDevices: number;
    flapping: number;
  };
  gateway: DashboardEndpoint | null;
  wan: DashboardEndpoint | null;
  nodes: DashboardNode[];
  groups: DashboardGroup[];
  events: DashboardEvent[];
  flapping: DashboardFlapping[];
};

type RecordValue = Record<string, unknown>;

function record(value: unknown): RecordValue | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as RecordValue)
    : null;
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function text(value: unknown, fallback = ""): string {
  if (typeof value !== "string" && typeof value !== "number") {
    return fallback;
  }
  const cleaned = String(value)
    .replace(/[\u0000-\u001f\u007f]/gu, "")
    .trim()
    .slice(0, MAX_TEXT);
  return cleaned || fallback;
}

function number(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

function integer(value: unknown): number {
  const parsed = number(value);
  return parsed === null ? 0 : Math.max(0, Math.round(parsed));
}

function status(value: unknown): DashboardStatus {
  switch (value) {
    case "up":
    case "down":
    case "degraded":
    case "seen":
      return value;
    default:
      return "unknown";
  }
}

function dashboardLabel(value: unknown, fallback: string): string {
  return text(value, fallback) || fallback;
}

function rawStatusRow(value: unknown): RecordValue | null {
  return record(value);
}

function rawSparkline(rawSparks: RecordValue | null, rawId: string): number[] {
  const spark = record(rawSparks?.[rawId]);
  return array(spark?.values)
    .map(number)
    .filter((value): value is number => value !== null)
    .slice(-MAX_SPARK_POINTS);
}

function endpoint(value: unknown, fallback: string): DashboardEndpoint | null {
  const row = record(value);
  if (!row) {
    return null;
  }
  return {
    label: dashboardLabel(row.label, fallback),
    status: status(row.status),
    host: text(row.host) || null,
    ip: text(row.ip) || null,
    rttMs: number(row.rtt_ms),
  };
}

function node(
  value: unknown,
  kind: DashboardNode["kind"],
  index: number,
  rawSparks: RecordValue | null,
): DashboardNode | null {
  const row = rawStatusRow(value);
  if (!row) {
    return null;
  }
  const rawId = text(row.id);
  const rates = record(row.rates);
  const rawLink = record(row.link);
  const rawOs = record(row.os);
  return {
    id: `${kind}-${index + 1}`,
    label: dashboardLabel(row.label, `${kind} ${index + 1}`),
    kind,
    status: status(row.status),
    host: text(row.host) || null,
    ip: text(row.ip) || null,
    rttMs: number(row.rtt_ms) ?? number(row.ttfb_ms) ?? number(row.connect_ms),
    rxBps: number(rates?.rx_bps),
    txBps: number(rates?.tx_bps),
    uptimeS: number(row.uptime_s),
    link: rawLink
      ? {
          speedMbit: number(rawLink.speed_mbit),
          grade: text(rawLink.grade) || null,
        }
      : null,
    os: rawOs ? dashboardLabel(rawOs.name ?? rawOs.release, "") || null : null,
    sparkline: rawId ? rawSparkline(rawSparks, rawId) : [],
  };
}

function member(value: unknown): DashboardMember | null {
  const row = record(value);
  if (!row) {
    return null;
  }
  return {
    label: dashboardLabel(row.label, "Service member"),
    role: text(row.role, "check"),
    status: status(row.status),
    rttMs: number(row.rtt_ms) ?? number(row.ttfb_ms) ?? number(row.connect_ms),
  };
}

function group(value: unknown, index: number): DashboardGroup | null {
  const row = record(value);
  if (!row) {
    return null;
  }
  const members = array(row.members)
    .slice(0, MAX_MEMBERS)
    .map(member)
    .filter((item): item is DashboardMember => item !== null);
  return {
    id: `service-${index + 1}`,
    label: dashboardLabel(row.label, `Service ${index + 1}`),
    status: status(row.status),
    up: integer(row.up),
    down: integer(row.down),
    total: integer(row.total) || members.length,
    zone: text(row.zone) || null,
    members,
  };
}

function event(value: unknown, labels: Map<string, string>): DashboardEvent | null {
  const row = record(value);
  if (!row) {
    return null;
  }
  const rawId = text(row.id);
  return {
    label: labels.get(rawId) || "Network node",
    from: status(row.from),
    to: status(row.to),
    changes: integer(row.changes) || 1,
    at: text(row.ts) || null,
  };
}

function flapping(value: unknown, labels: Map<string, string>): DashboardFlapping | null {
  if (!Array.isArray(value) || value.length !== 2) {
    return null;
  }
  const rawId = text(value[0]);
  const changes = integer(value[1]);
  if (!rawId || changes < 1) {
    return null;
  }
  return { label: labels.get(rawId) || "Network node", changes };
}

function collectLabels(raw: RecordValue): Map<string, string> {
  const labels = new Map<string, string>();
  for (const collection of [raw.machines, raw.auto, raw.lan, raw.quiet_lan, raw.proxies, raw.quiet_proxies]) {
    for (const value of array(collection)) {
      const row = record(value);
      const id = text(row?.id);
      if (id) {
        labels.set(id, dashboardLabel(row?.label, "Network node"));
      }
    }
  }
  for (const value of array(raw.groups)) {
    const row = record(value);
    const id = text(row?.id);
    if (id) {
      labels.set(id, dashboardLabel(row?.label, "Service"));
    }
    for (const child of array(row?.members)) {
      const memberRow = record(child);
      const memberId = text(memberRow?.id);
      if (memberId) {
        labels.set(memberId, dashboardLabel(memberRow?.label, "Service member"));
      }
    }
  }
  const gateway = record(raw.gateway);
  const wan = record(raw.wan);
  if (gateway?.id) {
    labels.set(text(gateway.id), dashboardLabel(gateway.label, "Gateway"));
  }
  if (wan?.id) {
    labels.set(text(wan.id), dashboardLabel(wan.label, "Internet"));
  }
  return labels;
}

function counts(nodes: DashboardNode[], groups: DashboardGroup[]) {
  const statuses = [...nodes.map((item) => item.status), ...groups.map((item) => item.status)];
  return {
    total: statuses.length,
    up: statuses.filter((item) => item === "up").length,
    down: statuses.filter((item) => item === "down").length,
    degraded: statuses.filter((item) => item === "degraded").length,
    unknown: statuses.filter((item) => item === "unknown" || item === "seen").length,
  };
}

export function projectLanarchySnapshot(
  input: unknown,
  now = Date.now(),
): LanarchyDashboardSnapshot {
  const raw = record(input) || {};
  const labels = collectLabels(raw);
  const rawSparks = record(raw.sparks);
  const nodes: DashboardNode[] = [];
  const addNodes = (values: unknown, kind: DashboardNode["kind"]) => {
    for (const value of array(values)) {
      if (nodes.length >= MAX_NODES) {
        return;
      }
      const kindIndex = nodes.filter((candidate) => candidate.kind === kind).length;
      const item = node(value, kind, kindIndex, rawSparks);
      if (item) {
        nodes.push(item);
      }
    }
  };
  addNodes(raw.machines, "machine");
  addNodes(raw.auto, "machine");
  addNodes(raw.lan ?? raw.quiet_lan, "lan");
  addNodes(raw.proxies ?? raw.quiet_proxies, "proxy");

  const groups = array(raw.groups)
    .slice(0, MAX_GROUPS)
    .map((value, index) => group(value, index))
    .filter((item): item is DashboardGroup => item !== null);
  const summaryCounts = counts(nodes, groups);
  const rawAsOf = text(raw.as_of) || null;
  const parsedAsOf = rawAsOf ? Date.parse(rawAsOf) : Number.NaN;
  const stale = !Number.isFinite(parsedAsOf) || now - parsedAsOf > STALE_AFTER_MS;
  const rawNewDevices = array(raw.new_devices);
  const rawFlaps = Object.entries(record(raw.flaps) || {})
    .sort(([, left], [, right]) => integer(right) - integer(left))
    .slice(0, MAX_FLAPPING);
  const flappingRows = rawFlaps
    .map(([id, value]) => flapping([id, value], labels))
    .filter((item): item is DashboardFlapping => item !== null);
  const events = array(raw.events)
    .slice(0, MAX_EVENTS)
    .map((value) => event(value, labels))
    .filter((item): item is DashboardEvent => item !== null);

  return {
    schemaVersion: 1,
    asOf: rawAsOf,
    stale,
    summary: {
      ...summaryCounts,
      machines: nodes.filter((item) => item.kind === "machine").length,
      services: groups.length,
      newDevices: rawNewDevices.length,
      flapping: flappingRows.length,
    },
    gateway: endpoint(raw.gateway, "Gateway"),
    wan: endpoint(raw.wan, "Internet"),
    nodes,
    groups,
    events,
    flapping: flappingRows,
  };
}

export function readLanarchyDashboardSnapshot(
  stateDir: string,
  now = Date.now(),
): LanarchyDashboardSnapshot {
  return projectLanarchySnapshot(readLanarchySnapshot(stateDir), now);
}
