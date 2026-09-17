#!/usr/bin/env python3
"""Single-owner collector. Writes snapshot.json; the panel only reads it."""
from __future__ import annotations

import fcntl
import os
import time

from inventory_lib import load_inventory
from plugin_paths import inventory_path, plugin_config_dir
from probe import HERE, run_probe

DEFAULT_INTERVAL_S = 15.0


def probe_interval_s() -> float:
    path = inventory_path() if inventory_path().is_file() else HERE / "inventory.json"
    try:
        inv = load_inventory(path)
        settings = inv.get("settings") if isinstance(inv, dict) else None
        raw = settings.get("probeIntervalSec") if isinstance(settings, dict) else None
        n = float(raw)
        if 5.0 <= n <= 120.0:
            return n
    except (TypeError, ValueError, OSError):
        pass
    return DEFAULT_INTERVAL_S


def loop() -> int:
    lock_path = plugin_config_dir() / ".daemon.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        fh.write(str(os.getpid()))
        fh.flush()
        while True:
            try:
                run_probe(write_stdout=False)
            except Exception as e:
                print(f"lanarchy daemon: {type(e).__name__}: {e}", flush=True)
            time.sleep(probe_interval_s())


if __name__ == "__main__":
    raise SystemExit(loop())
