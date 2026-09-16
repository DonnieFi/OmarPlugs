# Lanarchy (`donnie.homelab-mesh`)

Homelab status in the Omarchy bar. **Letterbox topology map** (default) plus a **Pulse-style list** tab. Setup edits v2 `inventory.json` (machines, LAN hosts, proxies).

- User config: `~/.config/omarchy/plugins/homelab-mesh/`
- Plugin id: `donnie.homelab-mesh` (rename optional later)
- Repo: [DonnieFi/OmarPlugs](https://github.com/DonnieFi/OmarPlugs)
- Architecture (history, notify, edges): [`docs/architecture.md`](docs/architecture.md)

Row density and keyboard panel patterns follow Omarchy's **Pulse** bar plugin. Viz tone references **Omastorm** (honest timestamps, quiet chrome).

## Enable

```bash
export OMARCHY_PATH=/path/to/omarchy
omarchy-shell shell rescanPlugins
omarchy-plugin-enable donnie.homelab-mesh
omarchy-shell shell summon donnie.homelab-mesh
```

Symlink or copy this folder to `~/.config/omarchy/plugins/homelab-mesh/`. Edit `inventory.json` there for your mesh.

## Commands

| Script | Role |
|--------|------|
| `probe.py` | Glance JSON (`machines`, `lan`, `proxies`); appends local history + notify streak sidecars |
| `inventory_cli.py` | `dump` / `migrate` / `write` for QML |
| `history_cli.py` | `sparkline --id <node>` for map sparklines |

## Preview asset

Catalog preview: add `preview.png` beside this README when map visuals are screenshot-ready (bead OmarPlugs-5oy.7).
