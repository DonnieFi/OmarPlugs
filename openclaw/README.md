# Lanarchy Dashboard for OpenClaw

This optional package registers a native **`lanarchy:mesh`** Control UI widget.
It reads the last atomic snapshot produced by the Lanarchy daemon and renders a
process-flow map of the mesh: machines, gateway, services, measured link rates,
and stale-state detection. Labels, hosts, and IPs from the snapshot stay visible.

It does **not** start `probe.py`, run a second collector, read inventory/history
or UniFi credentials, or edit the mesh. The Gateway method returns a bounded DTO
and requires `operator.read`.

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
requires `operator.read`. It receives the bounded dashboard DTO including host
and IP fields from the snapshot. Inventory files, history, notification state,
MAC addresses, UniFi credentials, and other secrets stay outside the method.
The dashboard is intentionally read-only.

## Local checks

The parent repository's `test_openclaw_dashboard.py` checks the manifest,
package metadata, method scope, and widget contract. The TypeScript projection
is bounded (size/count caps) and omits credential blobs before it crosses the
Gateway boundary; network identifiers from the snapshot are not redacted.

If `snapshot.json` is missing, run `python3 ../probe.py` from the OmarPlugs
root, or start the Omarchy daemon, before expecting the widget to show data.
