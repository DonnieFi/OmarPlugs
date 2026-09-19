import { html, nothing, render } from "lit";
import type { ControlUiHost, ControlUiWidget } from "openclaw/plugin-sdk/control-ui";
import type {
  DashboardEndpoint,
  DashboardGroup,
  DashboardNode,
  DashboardStatus,
  LanarchyDashboardSnapshot,
} from "../src/contract.js";

const REFRESH_MS = 15_000;

function statusLabel(value: DashboardStatus): string {
  return value === "up" ? "UP" : value === "down" ? "DOWN" : value.toUpperCase();
}

function statusClass(value: DashboardStatus): string {
  return `lanarchy-status lanarchy-status--${value}`;
}

function metric(value: number | null, suffix = ""): string {
  if (value === null || !Number.isFinite(value)) {
    return "—";
  }
  return `${Math.round(value)}${suffix}`;
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

function endpointCard(item: DashboardEndpoint | null, fallback: string) {
  const endpoint = item || { label: fallback, status: "unknown" as const, rttMs: null };
  return html`
    <article class="lanarchy-topology__node">
      <span class="${statusClass(endpoint.status)}">${statusLabel(endpoint.status)}</span>
      <strong>${endpoint.label}</strong>
      <small>${endpoint.rttMs === null ? "RTT —" : `RTT ${metric(endpoint.rttMs, " ms")}`}</small>
    </article>
  `;
}

function nodeRow(item: DashboardNode) {
  return html`
    <li class="lanarchy-row">
      <span class="${statusClass(item.status)}">${statusLabel(item.status)}</span>
      <span class="lanarchy-row__main">
        <strong>${item.label}</strong>
        <small>${item.os || item.kind}${item.link?.speedMbit ? ` · ${item.link.speedMbit} Mbit` : ""}</small>
      </span>
      <span class="lanarchy-row__metric">${item.rttMs === null ? "—" : metric(item.rttMs, " ms")}</span>
      <span class="lanarchy-row__metric">↓ ${rate(item.rxBps)} · ↑ ${rate(item.txBps)}</span>
    </li>
  `;
}

function groupRow(item: DashboardGroup) {
  return html`
    <li class="lanarchy-row">
      <span class="${statusClass(item.status)}">${statusLabel(item.status)}</span>
      <span class="lanarchy-row__main">
        <strong>${item.label}</strong>
        <small>${item.total} checks · ${item.zone || "internal"}</small>
      </span>
      <span class="lanarchy-row__metric">${item.up}/${item.total} up</span>
      <span class="lanarchy-row__metric">${item.down ? `${item.down} down` : "healthy"}</span>
    </li>
  `;
}

function renderSnapshot(snapshot: LanarchyDashboardSnapshot) {
  const visibleNodes = [...snapshot.nodes]
    .sort(
      (left, right) =>
        Number(right.status === "down") - Number(left.status === "down") ||
        left.label.localeCompare(right.label),
    )
    .slice(0, 12);
  const visibleGroups = [...snapshot.groups]
    .sort(
      (left, right) =>
        Number(right.status === "down") - Number(left.status === "down") ||
        left.label.localeCompare(right.label),
    )
    .slice(0, 10);
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

      <div class="lanarchy-topology" aria-label="Network path">
        <article class="lanarchy-topology__node">
          <span class="lanarchy-topology__count">${snapshot.summary.machines}</span>
          <strong>Machines</strong>
          <small>${snapshot.summary.unknown} unknown</small>
        </article>
        <span class="lanarchy-topology__link" aria-hidden="true">→</span>
        ${endpointCard(snapshot.gateway, "Gateway")}
        <span class="lanarchy-topology__link" aria-hidden="true">→</span>
        ${endpointCard(snapshot.wan, "Internet")}
      </div>

      ${visibleNodes.length
        ? html`<section class="lanarchy-section"><h2>Nodes</h2><ul class="lanarchy-list">${visibleNodes.map(nodeRow)}</ul></section>`
        : nothing}
      ${visibleGroups.length
        ? html`<section class="lanarchy-section"><h2>Services</h2><ul class="lanarchy-list">${visibleGroups.map(groupRow)}</ul></section>`
        : nothing}

      <footer class="lanarchy-widget__footer">
        <span>${snapshot.summary.newDevices} new · ${snapshot.summary.flapping} flapping</span>
        <span>${snapshot.events.length} recent changes · refresh 15s</span>
      </footer>
    </section>
  `;
}

function renderState(
  snapshot: LanarchyDashboardSnapshot | null,
  loading: boolean,
  error: string | null,
  canRead: boolean,
) {
  if (snapshot) {
    return renderSnapshot(snapshot);
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

    const draw = () => {
      if (disposed || !context.presented) {
        render(nothing, container);
        return;
      }
      render(renderState(snapshot, loading, error, context.host.connection.canRead), container);
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

    const sync = () => {
      if (timer !== undefined) {
        clearInterval(timer);
        timer = undefined;
      }
      draw();
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
        render(nothing, container);
      },
    };
  };
}
