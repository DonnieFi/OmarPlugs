#!/usr/bin/env python3
"""Single-owner collector. Writes snapshot.json; the panel only reads it."""
from __future__ import annotations

import fcntl
import os
import time

from plugin_paths import plugin_config_dir
from probe import run_probe

INTERVAL_S = 15.0


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
            time.sleep(INTERVAL_S)


if __name__ == "__main__":
    raise SystemExit(loop())
