#!/usr/bin/env bash
# One-shot, re-runnable setup for the lab on macOS:
#   tools (Brewfile) -> Docker runtime (colima) -> git hooks.
# colima runs as a login service, so Docker survives reboots.
# It stops short of creating the cluster: `make up` is Phase 1, step 1.
set -euo pipefail
cd "$(dirname "$0")/.."

# kind runs 3 nodes, and Argo CD adds ~7 pods. colima's default 2 CPU / 2 GiB is too small.
COLIMA_CPU="${COLIMA_CPU:-4}"
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"

step() { printf '\n==> %s\n' "$*"; }

[[ "$(uname)" == "Darwin" ]] || { echo "This script is macOS-only. See the Brewfile for the tool list."; exit 1; }
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }

step "Installing tools from Brewfile"
brew bundle --file=Brewfile --no-upgrade   # install what is missing; never upgrade what you have

step "Configuring the docker CLI (~/.docker/config.json)"
DOCKER_CONFIG_FILE="$HOME/.docker/config.json"
mkdir -p "$(dirname "$DOCKER_CONFIG_FILE")"
[[ -f "$DOCKER_CONFIG_FILE" ]] || echo '{}' > "$DOCKER_CONFIG_FILE"

# A removed Docker Desktop leaves "credsStore": "desktop" behind, and every pull then fails
# with "docker-credential-desktop: executable file not found". Point it at the Keychain instead.
store=$(yq -p json -o yaml '.credsStore // ""' "$DOCKER_CONFIG_FILE")
if [[ -n "$store" ]] && ! command -v "docker-credential-$store" >/dev/null; then
  yq -i -p json -o json '.credsStore = "osxkeychain"' "$DOCKER_CONFIG_FILE"
  echo "credsStore was '$store' (helper missing); set to osxkeychain"
fi

# Homebrew installs buildx outside docker's default plugin path. Without it, `docker build`
# falls back to the deprecated legacy builder.
PLUGINS_DIR="$(brew --prefix)/lib/docker/cli-plugins"
PLUGINS_DIR="$PLUGINS_DIR" yq -i -p json -o json \
  '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [strenv(PLUGINS_DIR)] | unique)' "$DOCKER_CONFIG_FILE"

step "Starting Docker runtime (colima as a login service, ${COLIMA_CPU} CPU / ${COLIMA_MEMORY} GiB)"
# First run only: create the VM at the lab's size. colima saves the size in its config,
# and the service reuses it. (To resize later: colima stop; colima start --cpu N --memory N.)
if [[ ! -f "$HOME/.colima/default/colima.yaml" ]]; then
  colima start --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY"
fi
# Run colima under launchd so Docker, and the kind cluster on it, come back after a reboot.
# A colima started by hand would fight the service, so stop it and hand it over.
if ! brew services list | grep -qE '^colima +started'; then
  if colima status >/dev/null 2>&1; then colima stop; fi
  brew services start colima
fi
printf 'waiting for Docker'
for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; printf '.'; sleep 3; done
echo
docker context use colima >/dev/null
docker info --format 'docker {{.ServerVersion}} on {{.OperatingSystem}}'

step "Enabling repo git hooks (blocks committing private/)"
git config core.hooksPath .githooks

step "Versions"
kind version
docker buildx version
kubectl version --client | head -1
helm version --short
go version

cat <<'EOF'

Setup complete. Next, Phase 1 in README.md:
  make up                      # create the kind cluster
  helm lint charts/hello
EOF
