"""Slow discover job: mDNS + ARP neigh candidates for Setup. Reads only; probe puts the list in snapshot.discover[].

Candidate: {source: mdns|neigh|unifi, type: machine|host, label, host, ip, mac, services[]}
"""
from __future__ import annotations

import re
import subprocess
import time
from typing import Any

from history_lib import node_meta
from telemetry_lib import neighbors
from unifi_lib import fmt_mac, known_from

AVAHI_CMD = ["avahi-browse", "-a", "-t", "-r", "-p", "-k"]
AVAHI_TIMEOUT_S = 20.0
MIN_INTERVAL_S = 60.0
MAX_CANDIDATES = 48

# mDNS service type → what it says about the box. machine: something you ssh into. host: a service endpoint.
# noise: pairing chatter from phones/TVs/laptops whose instance names are opaque ids, never a label.
SERVICE_ROLE = {
    "_workstation._tcp": "machine",
    "_ssh._tcp": "machine",
    "_sftp-ssh._tcp": "machine",
    "_http._tcp": "host",
    "_https._tcp": "host",
    "_home-assistant._tcp": "host",
    "_esphomelib._tcp": "host",
    "_printer._tcp": "host",
    "_ipp._tcp": "host",
    "_smb._tcp": "host",
    "_androidtvremote2._tcp": "host",
    "_companion-link._tcp": "noise",
    "_airplay._tcp": "noise",
    "_raop._tcp": "noise",
    "_googlecast._tcp": "noise",
    "_googcrossdevice._tcp": "noise",
    "_ghp._tcp": "noise",
    "_meshcop._udp": "noise",
}
LABEL_ORDER = ("machine", "host", None)

_ESCAPE = re.compile(r"\\(\d{3})")
_BRACKET_MAC = re.compile(r"\s*\[([0-9a-fA-F:]{17})\]\s*$")

_cache: dict[str, Any] = {"ts": float("-inf"), "rows": []}


def unescape(name: str) -> str:
    return _ESCAPE.sub(lambda m: chr(int(m.group(1))), name).replace("\\.", ".").replace("\\\\", "\\")


def parse_avahi(text: str) -> list[dict]:
    """Resolved IPv4 lines of `avahi-browse -a -t -r -p -k` → [{name, type, host, ip}]."""
    rows: list[dict] = []
    for line in text.splitlines():
        parts = line.split(";", 9)
        if len(parts) < 8 or parts[0] != "=" or parts[2] != "IPv4":
            continue
        rows.append(
            {
                "name": unescape(parts[3]),
                "type": parts[4],
                "host": unescape(parts[6]).removesuffix(".local") or None,
                "ip": parts[7] or None,
            }
        )
    return rows


def mdns_candidates(records: list[dict], mac_by_ip: dict[str, str]) -> list[dict]:
    groups: dict[str, list[dict]] = {}
    for r in records:
        if r.get("ip"):
            groups.setdefault(r["ip"], []).append(r)
    out: list[dict] = []
    for ip, recs in groups.items():
        services = list(dict.fromkeys(r["type"] for r in recs))
        roles = {SERVICE_ROLE.get(s) for s in services}
        mapped = {SERVICE_ROLE[s] for s in services if s in SERVICE_ROLE}
        if mapped and mapped <= {"noise"}:
            continue
        pick = next((r for role in LABEL_ORDER for r in recs if SERVICE_ROLE.get(r["type"]) == role), None)
        label = pick["name"] if pick else None
        host = (pick or {}).get("host") or next((r["host"] for r in recs if r.get("host")), None)
        mac = mac_by_ip.get(ip)
        for r in recs:
            m = _BRACKET_MAC.search(r["name"])
            if m and not mac:
                mac = fmt_mac(m.group(1))
        out.append(
            {
                "source": "mdns",
                "type": "machine" if "machine" in roles else "host",
                "label": _BRACKET_MAC.sub("", label) if label else (host or ip),
                "host": host,
                "ip": ip,
                "mac": mac,
                "services": services,
            }
        )
    return out


def neigh_candidates(neigh: list[dict], taken_ips: set[str]) -> list[dict]:
    return [
        {"source": "neigh", "type": "host", "label": n["ip"], "host": None, "ip": n["ip"], "mac": n["mac"], "services": []}
        for n in neigh
        if n["ip"] not in taken_ips
    ]


def known_targets(nodes: list[dict], hist: dict) -> dict[str, set[str]]:
    """Inventory dns/ip/mac plus the ip/mac history remembered per node while it was up."""
    known = known_from(nodes)
    for n in nodes:
        meta = node_meta(hist, str(n.get("id") or ""))
        if meta.get("ip"):
            known["ips"].add(str(meta["ip"]))
        if meta.get("mac"):
            known["macs"].add(fmt_mac(str(meta["mac"])) or "")
    known["macs"].discard("")
    return known


def is_known(c: dict, known: dict[str, set[str]]) -> bool:
    if c.get("ip") and c["ip"] in known["ips"]:
        return True
    if c.get("mac") and c["mac"] in known["macs"]:
        return True
    for name in (c.get("host"), c.get("label")):
        n = str(name or "").strip().lower().removesuffix(".local")
        if n and (n in known["hosts"] or n.split()[0] in known["hosts"]):
            return True
    return False


def same_device(a: dict, b: dict) -> bool:
    if a.get("mac") and b.get("mac"):
        return a["mac"] == b["mac"]
    ah, bh = str(a.get("host") or "").lower(), str(b.get("host") or "").lower()
    if ah and bh:
        return ah == bh
    return bool(a.get("ip")) and a.get("ip") == b.get("ip")


def merge_discover(*lists: list[dict], known: dict[str, set[str]]) -> list[dict]:
    """Union of candidate lists minus inventory, deduped by mac, then hostname, then ip. First record wins."""
    out: list[dict] = []
    for c in (x for lst in lists for x in lst):
        if is_known(c, known):
            continue
        dup = next((o for o in out if same_device(o, c)), None)
        if dup is None:
            out.append(dict(c))
            continue
        for key in ("host", "ip", "mac"):
            if not dup.get(key) and c.get(key):
                dup[key] = c[key]
    return out[:MAX_CANDIDATES]


def collect_discover() -> list[dict]:
    """mDNS + neigh candidates, re-scanned at most every MIN_INTERVAL_S. Soft-fails to neigh-only without avahi."""
    now = time.monotonic()
    if now - _cache["ts"] < MIN_INTERVAL_S:
        return _cache["rows"]
    text = ""
    try:
        text = subprocess.run(AVAHI_CMD, capture_output=True, text=True, timeout=AVAHI_TIMEOUT_S).stdout
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    neigh = neighbors()
    mdns = mdns_candidates(parse_avahi(text), {n["ip"]: n["mac"] for n in neigh})
    rows = mdns + neigh_candidates(neigh, {c["ip"] for c in mdns})
    _cache.update(ts=now, rows=rows)
    return rows
