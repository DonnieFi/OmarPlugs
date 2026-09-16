# Lanarchy (`donnie.homelab-mesh`)

Homelab status in the Omarchy bar. The **list dash** is the default: compact colour-light rows for machines and grouped services (Home Assistant, Bernie, Cameras, Pi-hole…). **LAN** / **PROXIES** toggles unhide leftover noisy hosts. Map is the letterbox of the same machines + services. Setup edits v2 `inventory.json`.

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

## UniFi

A local Cloud Gateway / UDM at `settings.unifi.url` (default `https://192.168.1.1`) is probed via `/api/system` with no key. That is enough for the UNIFI dash row (name, model).

To pull APs, switches, and clients, create a Network API key (UniFi OS → Network → Settings → Control Plane → Integrations) and drop it here — not in inventory:

```bash
cp unifi-secrets.json.example ~/.config/omarchy/plugins/homelab-mesh/unifi-secrets.json
# then: UNIFI_KEY=...   (JSON {"apiKey":"..."} also works)
```

UniFi clients that are not already inventory nodes land in `snapshot.unifi.discover` for Setup later. Nothing is auto-added.

## Commands

| Script | Role |
|--------|------|
| `daemon.py` | Singleton collector; writes `snapshot.json` every 15s |
| `probe.py` | One-shot glance + `wol <id\|mac>`; also used by the daemon |
| `inventory_cli.py` | `dump` / `migrate` / `write` for QML |
| `history_cli.py` | `sparkline --id <node>` for map sparklines |

## Preview asset

Catalog preview: add `preview.png` beside this README when map visuals are screenshot-ready (bead OmarPlugs-5oy.7).
