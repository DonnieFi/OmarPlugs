#!/usr/bin/env python3
"""Live homelab mesh projection. Glance JSON unchanged: {as_of, machines, lan, proxies}."""
from __future__ import annotations

import json
import re
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from inventory_lib import load_inventory, nodes_by_type, probe_target

HERE = Path(__file__).resolve().parent
INVENTORY = HERE / "inventory.json"
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


def probe_proxy_node(node: dict) -> dict:
    check = str(node.get("check") or "tcp").lower()
    label = str(node.get("label") or node.get("id") or "proxy")
    pid = str(node.get("id") or label)
    host, port, url = probe_target(node)
    if check == "http":
        status = check_http(url or "")
    else:
        status = check_tcp(host or "", int(port or 0))
    return {
        "id": pid,
        "label": label,
        "status": status,
        "check": check if check in ("http", "tcp") else "tcp",
    }


def main() -> int:
    try:
        inv = load_inventory(INVENTORY)
    except Exception as e:
        print(json.dumps({"error": f"inventory: {e}"}, indent=2))
        return 1
    grouped = nodes_by_type(inv.get("nodes") or [])
    payload = {
        "as_of": now_iso(),
        "machines": [probe_rtt_node(x) for x in grouped["machines"]],
        "lan": [probe_rtt_node(x) for x in grouped["lan"]],
        "proxies": [probe_proxy_node(x) for x in grouped["proxies"]],
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
