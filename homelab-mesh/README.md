# Homelab Mesh (v1)

Omarchy Quickshell **panel** plugin — status-only flowchart of the home mesh.

- Path: `~/.config/omarchy/plugins/homelab-mesh/`
- Id: `donnie.homelab-mesh`
- Probe: live projection only (`probe.py` + `inventory.json`). No DB.

## Enable (on a machine with Omarchy shell running)

```bash
export PATH="/mnt/adata/opt/omarchy/bin:$PATH"
export OMARCHY_PATH=/mnt/adata/opt/omarchy
omarchy-shell shell rescanPlugins
omarchy-plugin-enable donnie.homelab-mesh
omarchy-shell shell summon donnie.homelab-mesh
```

Edit `inventory.json` for curated machines / LAN / proxies (red owns inventory).

## Layout lock

Machines row → LAN cluster → Proxies strip. `unknown` / null RTT → muted `—`. Proxies status-only. `as_of` muted corner.
