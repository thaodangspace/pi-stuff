#!/usr/bin/env bash

# Quick setup for pi (a fresh VM/VPS included).
#
#   skills        -> ~/.pi/agent/skills
#   prompts       -> ~/.pi/agent/prompts
#   packages/*    -> registered as local pi packages in ~/.pi/agent/settings.json
#
# Packages are pi packages (package.json `pi` manifest). They are referenced in
# place, so their own dependencies must be present; declare runtime deps in
# package.json `dependencies` or run `npm install` in the package directory.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
PI_SKILLS_DIR="${PI_SKILLS_DIR:-$PI_AGENT_DIR/skills}"
PI_PROMPTS_DIR="${PI_PROMPTS_DIR:-$PI_AGENT_DIR/prompts}"
PI_SETTINGS_FILE="${PI_SETTINGS_FILE:-$PI_AGENT_DIR/settings.json}"
PACKAGES_DIR="${PACKAGES_DIR:-$ROOT_DIR/packages}"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

mkdir -p "$PI_SKILLS_DIR" "$PI_PROMPTS_DIR"

initialize_submodules() {
  if [[ "${PI_STUFF_SKIP_SUBMODULES:-0}" == "1" ]]; then
    warn "skipping submodule update (PI_STUFF_SKIP_SUBMODULES=1)"
    return 0
  fi
  [[ -f "$ROOT_DIR/.gitmodules" ]] || return 0

  # PI_STUFF_HTTPS=1 clones over https instead of the git@github.com: URLs in
  # .gitmodules. Useful on a VM without SSH keys (private repos still need a
  # credential helper or a token).
  local git_args=()
  if [[ "${PI_STUFF_HTTPS:-0}" == "1" ]]; then
    git_args+=(-c url."https://github.com/".insteadOf="git@github.com:")
  fi

  if ! git -C "$ROOT_DIR" "${git_args[@]}" submodule update --init --recursive; then
    warn "submodule update failed (missing SSH access?); continuing with local checkouts"
  fi
}

install_skill() {
  local skill_dir="$1"
  local name

  [[ -f "$skill_dir/SKILL.md" ]] || return 0

  name="$(basename "$skill_dir")"
  rm -rf "$PI_SKILLS_DIR/$name"
  cp -R "$skill_dir" "$PI_SKILLS_DIR/$name"
  info "Installed skill: $PI_SKILLS_DIR/$name"
}

install_skills() {
  local source_dir="$ROOT_DIR/skills"
  local entry skill_dir

  [[ -d "$source_dir" ]] || return 0

  # Support skills stored directly in this repository.
  for entry in "$source_dir"/*; do
    [[ -d "$entry" ]] || continue
    install_skill "$entry"

    # A CLI submodule may publish one or more agent skills here.
    for skill_dir in "$entry/skills"/*; do
      [[ -d "$skill_dir" ]] || continue
      install_skill "$skill_dir"
    done
  done
}

install_prompts() {
  local source_dir="$ROOT_DIR/prompts"
  local prompt_file name

  [[ -d "$source_dir" ]] || return 0

  for prompt_file in "$source_dir"/*.md; do
    [[ -f "$prompt_file" ]] || continue

    name="$(basename "$prompt_file")"
    # Replace existing files or symlinks instead of following them.
    rm -f "$PI_PROMPTS_DIR/$name"
    cp "$prompt_file" "$PI_PROMPTS_DIR/$name"
    info "Installed prompt: $PI_PROMPTS_DIR/$name"
  done
}

# Register every pi package in packages/ with the user settings file.
# Existing entries for the same package name are replaced, so re-running setup
# never double-loads an extension that was also added by hand or via `pi install`.
register_packages() {
  local package_dirs=() dir entry

  # Point pi at working copies instead of the submodules, e.g. while hacking on
  # an extension: PI_STUFF_PACKAGE_PATHS=$HOME/code/pi-loop:$HOME/code/pi-hc-subagents
  if [[ -n "${PI_STUFF_PACKAGE_PATHS:-}" ]]; then
    IFS=':' read -r -a package_dirs <<<"$PI_STUFF_PACKAGE_PATHS"
  elif [[ -d "$PACKAGES_DIR" ]]; then
    for dir in "$PACKAGES_DIR"/*; do
      [[ -f "$dir/package.json" ]] || continue
      package_dirs+=("$(cd "$dir" && pwd)")
    done
  fi

  local resolved=()
  for entry in ${package_dirs[@]+"${package_dirs[@]}"}; do
    if [[ -f "$entry/package.json" ]]; then
      resolved+=("$(cd "$entry" && pwd)")
    else
      warn "skipping package path without package.json: $entry"
    fi
  done
  package_dirs=(${resolved[@]+"${resolved[@]}"})

  if [[ ${#package_dirs[@]} -eq 0 ]]; then
    return 0
  fi

  command -v node >/dev/null 2>&1 || die "node is required to update $PI_SETTINGS_FILE"

  node - "$PI_SETTINGS_FILE" "${package_dirs[@]}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [settingsFile, ...dirs] = process.argv.slice(2);
const options = { space: 2 };
let settings = {};
let existed = false;

if (fs.existsSync(settingsFile)) {
  const raw = fs.readFileSync(settingsFile, "utf8");
  if (raw.trim() !== "") {
    try {
      settings = JSON.parse(raw);
    } catch (error) {
      console.error(`error: cannot parse ${settingsFile}: ${error.message}`);
      process.exit(1);
    }
  }
  existed = true;
}

const readName = (dir) => {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8")).name;
  } catch {
    return undefined;
  }
};

const sourceOf = (entry) =>
  typeof entry === "string" ? entry : entry && typeof entry === "object" ? entry.source : undefined;

// Best-effort package name for a settings entry that is not one of ours.
const nameOfSource = (source) => {
  if (typeof source !== "string") return undefined;
  if (source.startsWith("npm:")) {
    return source.slice(4).replace(/@[^@/]*$/, "");
  }
  if (fs.existsSync(source)) return readName(source) ?? path.basename(source);
  const base = source.split("@")[0].replace(/\/+$/, "").split("/").pop();
  return base || undefined;
};

const newNames = new Set(dirs.map(readName).filter(Boolean));
const newDirs = new Set(dirs);

const current = Array.isArray(settings.packages) ? settings.packages : [];
const kept = current.filter((entry) => {
  const source = sourceOf(entry);
  if (typeof source === "string" && newDirs.has(path.resolve(source))) return false;
  const name = nameOfSource(source);
  return !(name && newNames.has(name));
});

const removed = current.length - kept.length;
settings.packages = [...kept, ...dirs];

if (existed && removed === 0 && JSON.stringify(current) === JSON.stringify(settings.packages)) {
  process.exit(0);
}

fs.mkdirSync(path.dirname(settingsFile), { recursive: true });
fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
for (const dir of dirs) process.stdout.write(`Registered package: ${dir}\n`);
if (removed > 0) process.stdout.write(`Replaced ${removed} stale package entr${removed === 1 ? "y" : "ies"}.\n`);
NODE
}

check_environment() {
  if ! command -v pi >/dev/null 2>&1; then
    warn "pi is not on PATH; install it, then re-run this script"
  fi
  # pi-hc-subagents needs a herdr-core endpoint at runtime.
  if [[ -f "$PACKAGES_DIR/pi-hc-subagents/package.json" ]] && ! command -v hc >/dev/null 2>&1; then
    warn "hc (herdr-core) is not on PATH; pi-hc-subagents needs it to spawn subagents"
  fi
}

initialize_submodules
install_skills
install_prompts
register_packages
check_environment

info ""
info "Done. Restart pi or run /reload to pick up the changes."
