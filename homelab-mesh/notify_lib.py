"""Fail-streak notifications (OmarPlugs-5oy.2)."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from inventory_lib import load_inventory
from plugin_paths import atomic_write_json, inventory_path, load_json_or, notify_state_path

NOTIFY_SCHEMA = 1
DEFAULT_THRESHOLD = 3


def empty_notify_state() -> dict:
    return {"schemaVersion": NOTIFY_SCHEMA, "nodes": {}}


def load_notify_state(path: Path | None = None) -> dict:
    raw = load_json_or(path or notify_state_path(), None)
    if not isinstance(raw, dict):
        return empty_notify_state()
    raw.setdefault("schemaVersion", NOTIFY_SCHEMA)
    raw.setdefault("nodes", {})
    return raw


def save_notify_state(state: dict, path: Path | None = None) -> Path:
    return atomic_write_json(path or notify_state_path(), state)


def fail_streak_threshold(inv: dict) -> int:
    settings = inv.get("settings")
    if isinstance(settings, dict):
        n = settings.get("failStreakThreshold")
        try:
            v = int(n)
            if v >= 1:
                return v
        except (TypeError, ValueError):
            pass
    return DEFAULT_THRESHOLD


def node_notify_enabled(inv: dict, node_id: str) -> bool:
    for n in inv.get("nodes") or []:
        if str(n.get("id") or "") == str(node_id):
            if n.get("notify") is False:
                return False
            return True
    return True


def _send_notification(title: str, body: str) -> None:
    try:
        subprocess.run(
            ["omarchy-notification-send", title, body],
            check=False,
            capture_output=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass


def apply_status_updates(
    state: dict,
    inv: dict,
    updates: list[tuple[str, str, str]],
) -> list[dict[str, Any]]:
    """Apply (node_id, label, status) rows; return notifications emitted."""
    threshold = fail_streak_threshold(inv)
    nodes = state.setdefault("nodes", {})
    sent: list[dict[str, Any]] = []
    for nid, label, status in updates:
        if not nid:
            continue
        entry = nodes.setdefault(nid, {"downStreak": 0, "alerted": False, "lastStatus": status})
        entry["lastStatus"] = status
        if status == "down":
            entry["downStreak"] = int(entry.get("downStreak") or 0) + 1
            if (
                node_notify_enabled(inv, nid)
                and int(entry["downStreak"]) >= threshold
                and not entry.get("alerted")
            ):
                title = f"Lanarchy: {label or nid} down"
                body = f"{threshold} consecutive probe failures"
                _send_notification(title, body)
                entry["alerted"] = True
                sent.append({"id": nid, "title": title, "body": body})
        elif status == "up":
            entry["downStreak"] = 0
            entry["alerted"] = False
        # unknown / other: leave streak and alerted alone
    return sent


def process_probe_glance(
    glance: dict,
    *,
    inv_path: Path | None = None,
    state_path: Path | None = None,
) -> dict:
    inv = load_inventory(inv_path or inventory_path())
    state = load_notify_state(state_path)
    updates: list[tuple[str, str, str]] = []
    for band in ("machines", "lan", "proxies"):
        for row in glance.get(band) or []:
            if not isinstance(row, dict):
                continue
            updates.append(
                (
                    str(row.get("id") or ""),
                    str(row.get("label") or row.get("id") or ""),
                    str(row.get("status") or "unknown"),
                )
            )
    sent = apply_status_updates(state, inv, updates)
    save_notify_state(state, state_path)
    return {"notified": sent}
