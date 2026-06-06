#!/usr/bin/env bash
set -euo pipefail

REPO="${OCTOPUSCORE_DEPLOY_REPO:-SergeiSOficial/OctopusCore-Deploy}"
VERSION="${OCTOPUSCORE_VERSION:-latest}"
INSTALL_DIR="${OCTOPUSCORE_NODE_INSTALL_DIR:-/opt/octopuscore-deploy/node-agent}"
ENV_FILE="${OCTOPUSCORE_NODE_ENV_FILE:-/etc/octopuscore/node-agent.env}"
ENABLE_NOW=true
DRY_RUN=false

fail() {
  printf 'install-node: FAIL: %s\n' "$*" >&2
  exit 1
}

say() {
  printf 'install-node: %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: install-node.sh [options]

Options:
  --version TAG       GitHub release tag, or latest
  --install-dir PATH  Install directory
  --env-file PATH     Environment file path
  --enable-now        Start compose stack after install (default)
  --no-start          Install files only
  --dry-run           Print planned changes
  -h, --help          Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    --env-file) ENV_FILE="$2"; shift ;;
    --enable-now) ENABLE_NOW=true ;;
    --no-start) ENABLE_NOW=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

checksum() {
  sha256sum "$1" | awk '{print $1}'
}

latest_tag() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

asset_url() {
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$REPO" "$VERSION" "$1"
}

download() {
  local name="$1"
  curl -fsSL "$(asset_url "$name")" -o "$WORK/$name"
}

verify_asset() {
  local name="$1"
  local expected actual
  expected="$(awk -v n="$name" '$2 == n { print $1 }' "$WORK/SHA256SUMS")"
  [ -n "$expected" ] || fail "missing checksum for $name"
  actual="$(checksum "$WORK/$name")"
  [ "$actual" = "$expected" ] || fail "checksum mismatch for $name"
}

write_env() {
  local dir
  dir="$(dirname "$ENV_FILE")"
  install -d -m 0750 "$dir"
  cat > "$ENV_FILE" <<EOF
REMOTE_WRITE_URL=${REMOTE_WRITE_URL:-https://metrics-write.example.invalid/api/v1/write}
REMOTE_WRITE_USER=${REMOTE_WRITE_USER:-remote_writer}
REMOTE_WRITE_PASSWORD=${REMOTE_WRITE_PASSWORD:-CHANGE_ME_REMOTE_WRITE}
OCTOPUSCORE_NODE_ID=${OCTOPUSCORE_NODE_ID:-octopus-node}
OCTOPUSCORE_NODE_ROLE=${OCTOPUSCORE_NODE_ROLE:-node}
OCTOPUSCORE_NODE_REGION=${OCTOPUSCORE_NODE_REGION:-unknown}
OCTOPUSCORE_MESH_ID=${OCTOPUSCORE_MESH_ID:-octopus-production}
EOF
  chmod 0640 "$ENV_FILE"
}

require_non_placeholder_env() {
  [ "${REMOTE_WRITE_URL:-}" != "" ] || fail "set REMOTE_WRITE_URL"
  [ "${REMOTE_WRITE_PASSWORD:-}" != "" ] || fail "set REMOTE_WRITE_PASSWORD"
  case "${REMOTE_WRITE_URL:-}" in
    *example.invalid*) fail "REMOTE_WRITE_URL still points to example.invalid" ;;
  esac
  case "${REMOTE_WRITE_PASSWORD:-}" in
    CHANGE_ME*|"") fail "REMOTE_WRITE_PASSWORD must be set" ;;
  esac
}

require_cmd curl
require_cmd tar
require_cmd sha256sum

if [ "$VERSION" = "latest" ]; then
  VERSION="$(latest_tag)"
  [ -n "$VERSION" ] || fail "could not resolve latest release"
fi

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" = false ]; then
  fail "real install requires root; rerun with sudo"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "release=$VERSION"
say "bundle_asset=octopuscore-node-agent-ubuntu.tar.gz"

download SHA256SUMS
download octopuscore-node-agent-ubuntu.tar.gz
verify_asset octopuscore-node-agent-ubuntu.tar.gz

if [ "$DRY_RUN" = true ]; then
  say "would install bundle to $INSTALL_DIR"
  say "would write env file $ENV_FILE"
  say "would run docker compose when --enable-now is active"
  exit 0
fi

install -d -m 0755 "$INSTALL_DIR"
tar -xzf "$WORK/octopuscore-node-agent-ubuntu.tar.gz" -C "$INSTALL_DIR" --strip-components=1
write_env

if [ "$ENABLE_NOW" = true ]; then
  require_cmd docker
  docker compose version >/dev/null 2>&1 || fail "docker compose is required"
  require_non_placeholder_env
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  (cd "$INSTALL_DIR" && docker compose -f compose.node.yml up -d)
else
  say "installed files; start with: set -a; . $ENV_FILE; set +a; cd $INSTALL_DIR && docker compose -f compose.node.yml up -d"
fi
