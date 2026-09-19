# Lanarchy Dashboard for OpenClaw

This optional package registers a native **`lanarchy:mesh`** Control UI widget.
It reads the last atomic snapshot produced by the Lanarchy daemon and renders a
compact, responsive dashboard: overall health, Machines → Gateway → Internet,
service groups, recent changes, and stale-state detection.

It does **not** start `probe.py`, run a second collector, read inventory/history
or UniFi credentials, edit the mesh, or expose raw IP/MAC/client data. The
Gateway method returns a bounded DTO and requires `operator.read`.

## Install

From the OmarPlugs checkout on the same host as the Gateway:

```bash
cd openclaw
npm install
npm run build
openclaw plugins validate --json
openclaw plugins install .
openclaw plugins enable lanarchy
```

The build compiles the Gateway entry and creates the immutable native Control UI
assets under `dist/control-ui/`. The plugin defaults to
`$XDG_STATE_HOME/lanarchy` or `~/.local/state/lanarchy`, matching the Omarchy
collector. Set `XDG_STATE_HOME` for the Gateway process if it runs with a
different state root.

Native plugin UI is trusted browser code. For a user-installed plugin, enable
**Settings → Labs → Custom plugin UI** in OpenClaw, restart the Gateway, reload
the Control UI, and then add the **Lanarchy mesh** widget to a dashboard. The
registered plugin kind is `lanarchy:mesh`.

## Security boundary

The native widget uses the authenticated Gateway method `lanarchy.snapshot` and
requires `operator.read`. It receives only the bounded dashboard DTO; inventory,
history, notification state, private IP/MAC/client detail, and secrets remain
outside the method. The dashboard is intentionally read-only.

## Local checks

The parent repository's `test_openclaw_dashboard.py` checks the manifest,
package metadata, method scope, and widget contract. The pure TypeScript
projection is intentionally bounded and redacted before it crosses the
Gateway boundary.

If `snapshot.json` is missing, run `python3 ../probe.py` from the OmarPlugs
root, or start the Omarchy daemon, before expecting the widget to show data.
