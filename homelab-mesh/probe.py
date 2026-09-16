#!/usr/bin/env python3
"""Live homelab mesh projection. Glance JSON unchanged: {as_of, machines, lan, proxies}."""
from __future__ import annotations

import json
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from history_lib import (
    append_probe_sample,
    last_counters,
    load_history,
    node_meta,
    save_history,
    set_last_counters,
    set_node_meta,
)
from groups_lib import attach_status, group_nodes, leftover_rows
from inventory_lib import load_inventory, nodes_by_type, probe_target
from notify_lib import process_probe_glance
from plugin_paths import atomic_write_json, inventory_path, load_json_or, probe_lock, snapshot_path
from unifi_lib import collect_unifi
from telemetry_lib import (
    collect_machine,
    dns_time_ms,
    http_timing,
    link_grade,
    neighbors,
    primary_link,
    rates_from,
    resolve_ipv4,
    send_wol,
    tcp_timing,
)

HERE = Path(__file__).resolve().parent
INVENTORY = inventory_path() if inventory_path().is_file() else HERE / "inventory.json"
PING_TIMEOUT_S = 1.5
HTTP_TIMEOUT_S = 2.0


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def ping_host(host: str) -> tuple[str, float | None]:
    """ICMP ping → (status, rtt_ms). unknown if probe can't run."""
    if not host:
        return "unknown", None
    try:
        proc = subprocess.run(
            ["ping", "-c", "1", "-W", "1", host],
            capture_output=True,
            text=True,
            timeout=PING_TIMEOUT_S + 1.0,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return "unknown", None
    out = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        return "down", None
    m = re.search(r"time[=<]([0-9.]+)\s*ms", out, re.I)
    if not m:
        return "up", None
    try:
        return "up", float(m.group(1))
    except ValueError:
        return "up", None


def check_tcp(host: str, port: int) -> str:
    try:
        with socket.create_connection((host, int(port)), timeout=HTTP_TIMEOUT_S):
            return "up"
    except OSError:
        return "down"


def check_http(url: str) -> str:
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            return "up" if 200 <= int(resp.status) < 500 else "down"
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError, ValueError):
        return "down"


def probe_rtt_node(node: dict) -> dict:
    host, _port, _url = probe_target(node)
    host = host or ""
    status, rtt = ping_host(host)
    return {
        "id": str(node.get("id") or host),
        "label": str(node.get("label") or node.get("id") or host),
        "host": host,
        "status": status,
        "rtt_ms": rtt,
    }


def probe_machine_node(node: dict, hist: dict, ts_now: float) -> dict:
    """Ping plus SSH/local telemetry: link speed, throughput delta, uptime."""
    row = probe_rtt_node(node)
    if row["status"] != "up" or node.get("telemetry") is False:
        return row
    report = collect_machine(row["host"], node.get("sshUser"))
    if not report:
        return row
    link = primary_link(report)
    if link:
        row["link"] = {
            "iface": link["iface"],
            "speed_mbit": link["speed_mbit"],
            "duplex": link["duplex"],
            "kind": link["kind"],
            "grade": link_grade(link),
        }
    if report.get("uptime_s") is not None:
        row["uptime_s"] = report["uptime_s"]
    prev = last_counters(hist, row["id"])
    rates = rates_from(prev, prev.get("ts_epoch") if prev else None, report, ts_now)
    if rates:
        row["rates"] = rates
    row["_counters"] = {"rx_bytes": report.get("rx_bytes"), "tx_bytes": report.get("tx_bytes"), "ts_epoch": ts_now}
    return row


def probe_proxy_node(node: dict) -> dict:
    check = str(node.get("check") or "tcp").lower()
    label = str(node.get("label") or node.get("id") or "proxy")
    pid = str(node.get("id") or label)
    host, port, url = probe_target(node)
    row = {"id": pid, "label": label, "check": check if check in ("http", "tcp") else "tcp"}
    if check == "http":
        timing = http_timing(url or "")
        code = timing.get("http_code")
        row["status"] = "up" if code and 200 <= int(code) < 500 else "down"
        if timing:
            row["connect_ms"] = timing["connect_ms"]
            row["ttfb_ms"] = timing["ttfb_ms"]
            row["http_code"] = code
    else:
        ms = tcp_timing(host or "", int(port or 0))
        row["status"] = "up" if ms is not None else "down"
        if ms is not None:
            row["connect_ms"] = ms
    return row


def lan_meta(nodes: list[dict], ts_now: float) -> dict:
    """Neighbor discovery + DNS health for the LAN cluster card."""
    neigh = neighbors()
    known_ips: set[str] = set()
    for n in nodes:
        ip = n.get("ip")
        if ip:
            known_ips.add(str(ip))
        dns = n.get("dns")
        if dns:
            r = resolve_ipv4(str(dns))
            if r:
                known_ips.add(r)
    unknown = [r for r in neigh if r["ip"] not in known_ips]
    dns_ms = None
    sample = next((str(n.get("dns")) for n in nodes if n.get("type") == "host" and n.get("dns")), None)
    if sample:
        dns_ms = dns_time_ms(sample)
    return {
        "neighbors": len(neigh),
        "unknown": len(unknown),
        "unknown_hosts": unknown[:8],
        "dns_ms": dns_ms,
        "dns_probe": sample,
    }


def remember_macs(hist: dict, rows: list[dict]) -> None:
    """Capture MAC per node while it is up so Wake-on-LAN can target it later."""
    by_ip = {r["ip"]: r["mac"] for r in neighbors()}
    for row in rows:
        ip = resolve_ipv4(str(row.get("host") or ""))
        mac = by_ip.get(ip or "")
        if mac:
            set_node_meta(hist, row["id"], {"mac": mac, "ip": ip})


def cmd_wol(target: str) -> int:
    """Wake a machine by inventory id or MAC."""
    mac = str(target or "").strip()
    if ":" not in mac and "-" not in mac:
        mac = str(node_meta(load_history(), mac).get("mac") or "")
        snap = load_json_or(snapshot_path(), {}) or {}
        for row in snap.get("machines") or []:
            if str(row.get("id") or "") == str(target or "") and row.get("mac"):
                mac = str(row["mac"])
                break
    ok = send_wol(mac)
    print(json.dumps({"ok": ok, "mac": mac}))
    return 0 if ok else 1


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "wol":
        return cmd_wol(sys.argv[2] if len(sys.argv) > 2 else "")
    with probe_lock() as acquired:
        if not acquired:
            print(json.dumps({"error": "another probe is still running"}, indent=2))
            return 1
        run_probe(write_stdout=True)
        return 0


def run_probe(*, write_stdout: bool = True) -> dict:
    try:
        inv = load_inventory(INVENTORY)
    except Exception as e:
        err = {"error": f"inventory: {e}"}
        if write_stdout:
            print(json.dumps(err, indent=2))
        return err
    nodes = inv.get("nodes") or []
    grouped = nodes_by_type(nodes)
    hist = load_history()
    ts_now = time.time()
    with ThreadPoolExecutor(max_workers=8) as pool:
        machines_f = [pool.submit(probe_machine_node, x, hist, ts_now) for x in grouped["machines"]]
        lan_f = [pool.submit(probe_rtt_node, x) for x in grouped["lan"]]
        proxies_f = [pool.submit(probe_proxy_node, x) for x in grouped["proxies"]]
        meta_f = pool.submit(lan_meta, nodes, ts_now)
        unifi_f = pool.submit(collect_unifi, inv, nodes)
        machines = [f.result() for f in machines_f]
        lan = [f.result() for f in lan_f]
        proxies = [f.result() for f in proxies_f]
        meta = meta_f.result()
        try:
            unifi = unifi_f.result()
        except Exception as e:
            unifi = {"ok": False, "auth": "none", "error": str(e)[:160], "devices": [], "clients": [], "discover": []}
    by_id: dict[str, dict] = {}
    for row in machines + lan + proxies:
        by_id[str(row.get("id") or "")] = row
    dash = group_nodes(nodes)
    quiet_lan, quiet_proxies = leftover_rows(nodes, by_id, dash["grouped_ids"])
    payload = {
        "as_of": now_iso(),
        "machines": machines,
        "lan": lan,
        "proxies": proxies,
        "groups": attach_status(dash, by_id),
        "quiet_lan": quiet_lan,
        "quiet_proxies": quiet_proxies,
        "lan_meta": meta,
        "unifi": unifi,
    }
    ts = payload["as_of"]
    for row in machines:
        counters = row.pop("_counters", None)
        if counters:
            set_last_counters(hist, row["id"], counters)
    for row in machines + lan:
        append_probe_sample(
            hist,
            str(row.get("id") or ""),
            status=str(row.get("status") or "unknown"),
            rtt_ms=row.get("rtt_ms"),
            ts=ts,
            extra={k: row[k] for k in ("rates",) if k in row},
        )
    for row in proxies:
        append_probe_sample(
            hist,
            str(row.get("id") or ""),
            status=str(row.get("status") or "unknown"),
            rtt_ms=row.get("ttfb_ms", row.get("connect_ms")),
            ts=ts,
        )
    remember_macs(hist, [r for r in machines + lan if r.get("status") == "up"])
    for row in machines + lan:
        meta_row = node_meta(hist, row["id"])
        if meta_row.get("mac"):
            row["mac"] = meta_row["mac"]
    try:
        save_history(hist)
    except OSError:
        pass
    try:
        process_probe_glance(payload)
    except Exception:
        pass
    try:
        atomic_write_json(snapshot_path(), payload, indent=None)
    except OSError:
        pass
    if write_stdout:
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return payload


if __name__ == "__main__":
    raise SystemExit(main())
