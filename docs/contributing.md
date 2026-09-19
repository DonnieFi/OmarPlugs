# Contributing to Lanarchy

Lanarchy (`donnie.homelab-mesh`) is an Omarchy Quickshell bar plugin. This repository root *is* the plugin (marketplace layout: `manifest.json` at root).

Agent instruction files (`AGENTS.md`, `CLAUDE.md`, and similar) must not live in this tree. `omarchy plugin add` installs the repo under `~/.config/omarchy/plugins/`, and coding agents can treat those filenames as trusted workspace policy.

## Layout

- `Panel.qml` + Python collectors — the plugin
- `README.md` — Install · Usage · Configure · Remove
- `docs/` — architecture, this guide, and panel-only screenshots (`docs/screenshots/*-0.X.Y.png`, keep in sync with `preview.png`)
- Runtime state is `~/.local/state/lanarchy/`, not the plugin tree — see `plugin_paths.state_dir()`
- Dotfiles (`.agents/`, `.beads/`, `.cursor/`, …) are gitignored — do not commit them

## Work

Before changing behaviour, read:

- [`README.md`](../README.md) — install, Search network, IPC
- [`architecture.md`](architecture.md) — inventory / history / notify sidecars

Runtime install path (usually a symlink to this tree):

`~/.config/omarchy/plugins/donnie.homelab-mesh/`

### Tests

```bash
./smoke.sh                 # validate + unit + probe + discover + refuse-empty
for t in test_*.py; do python3 "$t"; done
omarchy plugin validate .
```

After QML changes: `omarchy-restart-shell`, then summon and smoke the panel.

### Releasing

**Every user-visible change bumps `manifest.json` `version`, in the same commit.**
`manifest.json` is the single source of truth for which build a user has, so a
change that ships without it leaves no way to tell one build from another.

A release is three things, together:

1. bump `version` in `manifest.json` (semver: `0.3.13` → `0.4.0`, not `0.3.14`,
   when behaviour changes rather than a bug being fixed)
2. add a `CHANGELOG.md` entry under that exact version
3. update the version badge in `README.md`

The running panel exposes that same version via `omarchy-shell lanarchy version`.

A pull request that changes behaviour without a version bump is incomplete: the
user cannot tell which build they are running, and a bug report cannot be tied
to a release.

### Secrets

Never commit `unifi-secrets.json`, inventory dumps with keys, or snapshots from a live mesh. Examples only (e.g. `unifi-secrets.json.example`).

### Git

- Remote for this repo: `github` → `DonnieFi/OmarPlugs` (must be **public** for marketplace).
- Keep commits atomic; do not mix plugin code with unrelated docs unless asked.

## Style

- Prefer the Omarchy plugin develop guide shape for user-facing docs: Install · Usage · Configure · Remove · Dependencies · IPC
- Screenshots in docs must be panel-only (no desktop chrome)
- QML theming: use `Color` / `Style` / theme `colors.toml` — not hard-coded status greens

### Commits

Never add `Co-authored-by: Cursor` (or any Cursor/agent co-author trailer). Commits are the user's alone.
