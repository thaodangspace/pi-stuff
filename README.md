# pi-stuff

Personal pi setup: skills, prompt templates, and the pi extensions I use daily
(`pi-loop`, `pi-hc-subagents`). One script bootstraps a fresh machine or VM.

## What it installs

| What | Where |
|---|---|
| Skills in `skills/` | `~/.pi/agent/skills/<name>` |
| Prompt templates in `prompts/*.md` | `~/.pi/agent/prompts/<name>.md` |
| pi packages in `packages/` (git submodules) | registered as local paths in `~/.pi/agent/settings.json` → `packages` |

Packages are listed in place, so pi loads `packages/pi-loop` and
`packages/pi-hc-subagents` directly, including the skills/agents they bundle.

## Requirements

- Node.js >= 22
- pi: `curl -fsSL https://pi.dev/install.sh | sh`
- `hc` (herdr-core) >= 0.1.16 — only needed by `pi-hc-subagents`

## Quick setup (fresh VM/VPS)

```bash
git clone --recurse-submodules git@github.com:<you>/pi-stuff.git
cd pi-stuff
./setup.sh
```

Already cloned? `./setup.sh` initializes submodules itself.

Without SSH keys, clone over HTTPS (a token is needed for private repos):

```bash
PI_STUFF_HTTPS=1 ./setup.sh
```

Restart pi or run `/reload` afterwards to pick up prompts/skills/packages.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PI_AGENT_DIR` | `~/.pi/agent` | pi user config dir |
| `PI_SKILLS_DIR` | `$PI_AGENT_DIR/skills` | skill install target |
| `PI_PROMPTS_DIR` | `$PI_AGENT_DIR/prompts` | prompt install target |
| `PI_SETTINGS_FILE` | `$PI_AGENT_DIR/settings.json` | settings file edited for `packages` |
| `PACKAGES_DIR` | `./packages` | directory scanned for pi packages |
| `PI_STUFF_PACKAGE_PATHS` | unset | colon-separated package dirs to register instead of `packages/*` |
| `PI_STUFF_HTTPS` | `0` | `1` = clone submodules over https |
| `PI_STUFF_SKIP_SUBMODULES` | `0` | `1` = do not touch submodules |

Re-running the script is safe: same-name package entries are replaced instead of
duplicated, so an entry added by `pi install` never double-loads.

### Developing an extension

To run pi against working copies instead of the submodule checkouts:

```bash
PI_STUFF_PACKAGE_PATHS="$HOME/code/github.com/pi-loop:$HOME/code/github.com/pi-hc-subagents" ./setup.sh
```

## Notes

- pi does not install dependencies for local packages. Extensions must have their
  runtime `dependencies` present in the package directory (`npm install` there,
  or keep them host-provided as `peerDependencies`).
- `pi-hc-subagents` needs a reachable herdr-core socket. Inside an `hc` terminal
  it uses `HC_TERMINAL_*` automatically; outside, set `hc.socketPath` in
  `~/.pi/agent/hc-subagents.json` or `PI_HC_SUBAGENTS_SOCKET`.
