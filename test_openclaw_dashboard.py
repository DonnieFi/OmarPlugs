#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def main() -> int:
    plugin_dir = ROOT / "openclaw"
    manifest = json.loads((plugin_dir / "openclaw.plugin.json").read_text())
    assert manifest["id"] == "lanarchy"
    binding = manifest["dashboard"]["dataBindings"][0]
    assert binding["method"] == "lanarchy.snapshot"
    control_ui = manifest.get("controlUi")
    if control_ui is not None:
        assert control_ui["entry"].startswith("dist/control-ui/")
        assert control_ui["entry"].endswith("/index.js")
        assert all(style.startswith("dist/control-ui/") for style in control_ui["styles"])

    package = json.loads((plugin_dir / "package.json").read_text())
    assert package["openclaw"]["extensions"] == ["./dist/index.js"]
    assert package["openclaw"]["controlUi"] == "./browser/index.ts"
    assert package["scripts"]["build"]
    assert package["dependencies"]["lit"] == "3.3.3"

    entry = (plugin_dir / "index.ts").read_text()
    contract = (plugin_dir / "src" / "contract.ts").read_text()
    reader = (plugin_dir / "src" / "state-reader.ts").read_text()
    browser = (plugin_dir / "browser" / "index.ts").read_text()
    widget = (plugin_dir / "browser" / "widget.ts").read_text()
    for marker in (
        '"lanarchy.snapshot"',
        'scope: "operator.read"',
        "readLanarchyDashboardSnapshot(stateDir)",
        "defineFeaturePlugin",
        'surface: "widget"',
        'id: "mesh"',
        "registerControlUiDescriptor",
    ):
        assert marker in entry, marker
    for marker in (
        "MAX_SNAPSHOT_BYTES",
        "SNAPSHOT_FILE",
        "readFileSync",
        "statSync",
    ):
        assert marker in reader, marker
    for forbidden in ("probe.py", "spawn", "execFile", "child_process"):
        assert forbidden not in reader, forbidden
    for marker in ("MAX_NODES", "MAX_EVENTS", "projectLanarchySnapshot", "safeDashboardLabel"):
        assert marker in contract, marker
    for forbidden in ("row.ip", "row.mac", "row.public_ip", "raw.unifi"):
        assert forbidden not in contract, forbidden
    for marker in (
        'id: "mesh"',
        'id: "lanarchy"',
        "registerWidget",
    ):
        assert marker in browser, marker
    for marker in (
        '"lanarchy.snapshot"',
        "REFRESH_MS = 15_000",
        "operator.read",
        'aria-label="Lanarchy homelab dashboard"',
    ):
        assert marker in widget, marker
    assert not (plugin_dir / "src" / "http.ts").exists()
    print("OpenClaw dashboard contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
