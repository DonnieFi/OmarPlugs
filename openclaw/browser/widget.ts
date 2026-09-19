import { html, nothing, render } from "lit";
import type { ControlUiHost, ControlUiWidget } from "openclaw/plugin-sdk/control-ui";
import type { LanarchyDashboardSnapshot } from "../src/contract.js";
import {
  flowPacketCount,
  flowSpeedPxPerSec,
  layoutMap,
  pointAlong,
  segmentLengths,
  snapshotToGraph,
  type MapGraph,
  type MapLayout,
  type MapNode,
} from "./map-graph.js";

const REFRESH_MS = 15_000;

function statusLabel(value: string): string {
  if (value === "up") {
    return "UP";
  }
  if (value === "down") {
    return "DOWN";
  }
  return value.toUpperCase();
}

function rate(value: number | null): string {
  if (value === null || !Number.isFinite(value)) {
    return "—";
  }
  if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1)} MB/s`;
  }
  if (value >= 1_000) {
    return `${(value / 1_000).toFixed(1)} kB/s`;
  }
  return `${Math.round(value)} B/s`;
}

function updatedAt(value: string | null): string {
  if (!value) {
    return "No snapshot yet";
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed)
    ? `Updated ${new Date(parsed).toLocaleTimeString()}`
    : "Snapshot time unknown";
}

function nodeRateLine(node: MapNode): string {
  const flow = node.rxBps !== null || node.txBps !== null;
  if (!flow) {
    return "idle · no counters";
  }
  const measured = node.rxBps !== null || node.txBps !== null;
  return `↓ ${rate(node.rxBps)} ↑ ${rate(node.txBps)}${measured ? " ● measured" : ""}`;
}

function mapNodeCard(node: MapNode) {
  const status = node.status === "seen" ? "unknown" : node.status;
  return html`
    <article
      class="lanarchy-node lanarchy-node--${status}${node.kind === "gateway" ? " lanarchy-node--gateway" : ""}"
      data-map-id=${node.id}
    >
      <span class="lanarchy-node__st">${statusLabel(node.status)}</span>
      <strong>${node.label}</strong>
      ${node.subline ? html`<small>${node.subline}</small>` : nothing}
      ${node.kind === "machine" ? html`<small class="lanarchy-node__rate">${nodeRateLine(node)}</small>` : nothing}
    </article>
  `;
}

function renderMapBoard(graph: MapGraph, layout: MapLayout) {
  const nodeById = new Map(graph.nodes.map((node) => [node.id, node]));
  const boxes = layout.boxes.map((box) => {
    const node = nodeById.get(box.id);
    if (!node) {
      return nothing;
    }
    return html`
      <div
        class="lanarchy-node-wrap"
        style="left:${box.x}px;top:${box.y}px;width:${box.w}px;height:${box.h}px"
      >
        ${mapNodeCard(node)}
      </div>
    `;
  });

  const gatewayBox = layout.wanAnchorId
    ? layout.boxes.find((box) => box.id === layout.wanAnchorId)
    : undefined;

  const wanArrow = gatewayBox
    ? html`
        <div
          class="lanarchy-wan"
          style="left:${gatewayBox.x}px;top:${gatewayBox.y + gatewayBox.h + 8}px;width:${gatewayBox.w}px"
        >
          <span>WAN</span>
          <span class="lanarchy-wan__shaft"></span>
          <span>${graph.wanLabel} ↗</span>
        </div>
      `
    : nothing;

  const routes = layout.routes.map((route) => {
    const points = route.points.map((p) => `${p.x},${p.y}`).join(" ");
    const classes = [
      "lanarchy-lane",
      route.down ? "lanarchy-lane--down" : "",
      route.measured && route.bps >= 1000 && !route.down ? "lanarchy-lane--hot" : "",
      route.kind === "service" || route.kind === "wan" ? "lanarchy-lane--dash" : "",
    ]
      .filter(Boolean)
      .join(" ");
    return html`<polyline class=${classes} points=${points} data-route-from=${route.from}></polyline>`;
  });

  const showLowerTag = graph.lowerNodeIds.length > 0;
  const lowerAnchor =
    layout.boxes.find((box) => box.id === graph.hubId) ??
    layout.boxes.find((box) => graph.lowerNodeIds.includes(box.id));
  const lowerTagTop = lowerAnchor ? lowerAnchor.y - 16 : layout.height - 40;

  return html`
    <div class="lanarchy-map" style="height:${layout.height}px" data-lanarchy-map>
      <header class="lanarchy-map__head">
        <strong>LANARCHY · MAP</strong>
        <small>${graph.machineIds.length} machines${graph.gatewayId ? " · gateway" : ""}</small>
      </header>
      <div class="lanarchy-map__board" style="width:${layout.width}px">
        <svg class="lanarchy-wires" viewBox="0 0 ${layout.width} ${layout.height}">
          ${routes}
        </svg>
        ${boxes}
        ${wanArrow}
        ${showLowerTag
          ? html`
              <div class="lanarchy-lower-tag" style="top:${lowerTagTop}px">VIA GATEWAY ↓ REVERSE PROXY + SERVICES</div>
            `
          : nothing}
      </div>
      <div class="lanarchy-legend">
        <span><i></i>unmeasured uplink</span>
        <span class="lanarchy-legend__hot"><i></i>measured flow</span>
        <span class="lanarchy-legend__down">─ down dims its lane</span>
      </div>
    </div>
  `;
}

function renderSnapshot(snapshot: LanarchyDashboardSnapshot, mapWidth: number) {
  const graph = snapshotToGraph(snapshot);
  const layout = layoutMap(graph, mapWidth);
  const headline = snapshot.stale
    ? "STALE"
    : snapshot.summary.down > 0
      ? `${snapshot.summary.down} down`
      : snapshot.summary.degraded > 0
        ? `${snapshot.summary.degraded} degraded`
        : "All clear";

  return html`
    <section class="lanarchy-widget" aria-label="Lanarchy homelab dashboard">
      <header class="lanarchy-widget__header">
        <div>
          <strong>Lanarchy</strong>
          <small>${updatedAt(snapshot.asOf)}</small>
        </div>
        <span class="lanarchy-pill ${snapshot.stale ? "lanarchy-pill--stale" : ""}">${headline}</span>
      </header>

      <div class="lanarchy-metrics">
        <div><b>${snapshot.summary.up}</b><span>up</span></div>
        <div><b>${snapshot.summary.down}</b><span>down</span></div>
        <div><b>${snapshot.summary.machines}</b><span>machines</span></div>
        <div><b>${snapshot.summary.services}</b><span>services</span></div>
      </div>

      ${renderMapBoard(graph, layout)}

      <footer class="lanarchy-widget__footer">
        <span>${snapshot.summary.newDevices} new · ${snapshot.summary.flapping} flapping</span>
        <span>${snapshot.events.length} recent changes · refresh 15s</span>
      </footer>
    </section>
  `;
}

type Packet = {
  routeIndex: number;
  lengths: number[];
  points: Array<{ x: number; y: number }>;
  offset: number;
  speed: number;
  el: SVGCircleElement;
};

function syncPackets(svg: SVGSVGElement, layout: MapLayout) {
  const existing = svg.querySelectorAll("circle.lanarchy-pkt");
  for (const node of existing) {
    node.remove();
  }
  const packets: Packet[] = [];
  layout.routes.forEach((route, routeIndex) => {
    if (!route.measured || route.bps < 1000 || route.down) {
      return;
    }
    const lengths = segmentLengths(route.points);
    const total = lengths[lengths.length - 1];
    if (!(total > 0)) {
      return;
    }
    const count = flowPacketCount(route.bps);
    const speed = flowSpeedPxPerSec(route.bps);
    for (let k = 0; k < count; k++) {
      const el = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      el.setAttribute("r", "3");
      el.setAttribute("class", "lanarchy-pkt");
      svg.appendChild(el);
      packets.push({
        routeIndex,
        lengths,
        points: route.points,
        offset: (k / count) * total,
        speed,
        el,
      });
    }
  });
  return packets;
}

function renderState(
  snapshot: LanarchyDashboardSnapshot | null,
  loading: boolean,
  error: string | null,
  canRead: boolean,
  mapWidth: number,
) {
  if (snapshot) {
    return renderSnapshot(snapshot, mapWidth);
  }
  return html`
    <section class="lanarchy-widget lanarchy-widget--state" aria-live="polite">
      <strong>${loading ? "Loading Lanarchy…" : "Lanarchy unavailable"}</strong>
      <small>${!canRead ? "The connected Control UI needs operator.read." : error || "Waiting for snapshot.json."}</small>
    </section>
  `;
}

export function createLanarchyWidget(activationHost: ControlUiHost): ControlUiWidget["mount"] {
  return (container, initialContext) => {
    let context = initialContext;
    let snapshot: LanarchyDashboardSnapshot | null = null;
    let loading = true;
    let error: string | null = null;
    let timer: ReturnType<typeof setInterval> | undefined;
    let disposed = false;
    let mapWidth = 640;
    let resizeObserver: ResizeObserver | undefined;
    let raf = 0;
    let lastTick = performance.now();
    let packets: Packet[] = [];
    let activeLayout: MapLayout | null = null;

    const tick = (now: number) => {
      if (disposed) {
        return;
      }
      const dt = Math.min(0.1, (now - lastTick) / 1000);
      lastTick = now;
      for (const packet of packets) {
        packet.offset += packet.speed * dt;
        const point = pointAlong(packet.points, packet.lengths, packet.offset);
        packet.el.setAttribute("cx", String(point.x));
        packet.el.setAttribute("cy", String(point.y));
      }
      raf = requestAnimationFrame(tick);
    };

    const wirePackets = () => {
      const svg = container.querySelector<SVGSVGElement>(".lanarchy-wires");
      if (!svg || !activeLayout) {
        packets = [];
        return;
      }
      packets = syncPackets(svg, activeLayout);
    };

    const draw = () => {
      if (disposed || !context.presented) {
        render(nothing, container);
        return;
      }
      render(renderState(snapshot, loading, error, context.host.connection.canRead, mapWidth), container);
      if (snapshot) {
        const graph = snapshotToGraph(snapshot);
        activeLayout = layoutMap(graph, mapWidth);
        wirePackets();
      } else {
        activeLayout = null;
        packets = [];
      }
      observeMap();
    };

    const load = async () => {
      if (
        disposed ||
        !context.presented ||
        !context.host.connection.connected ||
        !context.host.connection.canRead
      ) {
        draw();
        return;
      }
      loading = snapshot === null;
      draw();
      try {
        snapshot = await context.host.request<LanarchyDashboardSnapshot>("lanarchy.snapshot", {});
        error = null;
      } catch (cause) {
        error = cause instanceof Error ? cause.message : "Lanarchy snapshot unavailable";
      } finally {
        loading = false;
        if (!disposed) {
          draw();
        }
      }
    };

    const observeMap = () => {
      resizeObserver?.disconnect();
      const mapEl = container.querySelector<HTMLElement>("[data-lanarchy-map]");
      if (!mapEl) {
        return;
      }
      resizeObserver = new ResizeObserver((entries) => {
        const entry = entries[0];
        if (!entry) {
          return;
        }
        const next = Math.max(320, Math.floor(entry.contentRect.width));
        if (next !== mapWidth) {
          mapWidth = next;
          draw();
        }
      });
      resizeObserver.observe(mapEl);
    };

    const sync = () => {
      if (timer !== undefined) {
        clearInterval(timer);
        timer = undefined;
      }
      draw();
      observeMap();
      if (context.presented) {
        void load();
        timer = setInterval(() => void load(), REFRESH_MS);
      }
    };

    const connectionSubscription = activationHost.subscribe(() => {
      if (context.presented) {
        void load();
      }
    });

    raf = requestAnimationFrame(tick);
    sync();

    return {
      update(next) {
        context = next;
        sync();
      },
      dispose() {
        disposed = true;
        connectionSubscription();
        if (timer !== undefined) {
          clearInterval(timer);
        }
        if (raf) {
          cancelAnimationFrame(raf);
        }
        resizeObserver?.disconnect();
        render(nothing, container);
      },
    };
  };
}
