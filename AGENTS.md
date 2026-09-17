# Agent Instructions

OmarPlugs is a monorepo of Omarchy Quickshell plugins. The shipped plugin today is **Lanarchy** under `homelab-mesh/` (manifest id `donnie.homelab-mesh`).

`CLAUDE.md` is a pointer here — keep project guidance in this file only.

## Layout

- `homelab-mesh/` — Lanarchy (QML panel, Python collectors, tests, docs)
- `README.md` — repo front page; deep docs live in `homelab-mesh/README.md`
- Dotfiles (`.agents/`, `.beads/`, `.cursor/`, …) are gitignored — do not commit them

## Lanarchy work

Before changing behaviour, read:

- [`homelab-mesh/README.md`](homelab-mesh/README.md) — install, Search network, IPC
- [`homelab-mesh/docs/architecture.md`](homelab-mesh/docs/architecture.md) — inventory / history / notify sidecars

Runtime install path (usually a symlink to this tree):

`~/.config/omarchy/plugins/homelab-mesh/`

### Tests

```bash
cd homelab-mesh
for t in test_*.py; do python3 "$t"; done
omarchy plugin validate ./homelab-mesh
```

After QML changes: `omarchy-restart-shell`, then summon and smoke the panel.

### Secrets

Never commit `unifi-secrets.json`, inventory dumps with keys, or snapshots from a live mesh. Examples only (e.g. `unifi-secrets.json.example`).

### Git

- Remote for this repo: `github` → `DonnieFi/OmarPlugs` (private). Do not assume `origin` (`git.lan`) works.
- Commit and push only when the user asks.
- Keep commits atomic; do not mix plugin code with unrelated docs unless asked.

## Style

- Prefer the Omarchy plugin develop guide shape for user-facing docs: Install · Usage · Configure · Remove · Dependencies · IPC
- Screenshots in docs must be panel-only (no desktop chrome)
- QML theming: use `Color` / `Style` / theme `colors.toml` — not hard-coded status greens
