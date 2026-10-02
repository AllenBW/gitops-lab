#!/usr/bin/env bash
# One-shot, re-runnable setup for the lab on macOS:
#   tools (Brewfile) -> Docker runtime (colima) -> git hooks.
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

step "Starting Docker runtime (colima, ${COLIMA_CPU} CPU / ${COLIMA_MEMORY} GiB)"
if colima status >/dev/null 2>&1; then
  echo "colima already running"
else
  colima start --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY"
fi
docker context use colima >/dev/null
docker info --format 'docker {{.ServerVersion}} on {{.OperatingSystem}}'

step "Enabling repo git hooks (blocks committing private/)"
git config core.hooksPath .githooks

step "Versions"
kind version
kubectl version --client | head -1
helm version --short
go version

cat <<'EOF'

Setup complete. Next, Phase 1 in README.md:
  make up                      # create the kind cluster
  helm lint charts/hello
EOF
