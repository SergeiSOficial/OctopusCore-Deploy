#!/usr/bin/env bash
set -euo pipefail

REPO="${OCTOPUSCORE_DEPLOY_REPO:-SergeiSOficial/OctopusCore-Deploy}"
VERSION="${OCTOPUSCORE_VERSION:-latest}"
INSTALL_DIR="${OCTOPUSCORE_MONITORING_INSTALL_DIR:-/opt/octopuscore-deploy/monitoring}"
ENV_FILE="${OCTOPUSCORE_MONITORING_ENV_FILE:-/etc/octopuscore/monitoring.env}"
ENABLE_NOW=false
DRY_RUN=false

fail() {
  printf 'install-monitoring: FAIL: %s\n' "$*" >&2
  exit 1
}

say() {
  printf 'install-monitoring: %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: install-monitoring.sh [options]

Options:
  --version TAG       GitHub release tag, or latest
  --install-dir PATH  Install directory
  --env-file PATH     Environment file path
  --enable-now        Start compose stack after install
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
OCTOPUSCORE_GRAFANA_HOST=${OCTOPUSCORE_GRAFANA_HOST:-grafana.example.invalid}
OCTOPUSCORE_METRICS_WRITE_HOST=${OCTOPUSCORE_METRICS_WRITE_HOST:-metrics-write.example.invalid}
ACME_EMAIL=${ACME_EMAIL:-ops@example.invalid}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-CHANGE_ME_GRAFANA}
REMOTE_WRITE_USER=${REMOTE_WRITE_USER:-remote_writer}
REMOTE_WRITE_PASSWORD_HASH=${REMOTE_WRITE_PASSWORD_HASH:-CHANGE_ME_HASH}
VM_RETENTION=${VM_RETENTION:-30d}
EOF
  chmod 0640 "$ENV_FILE"
}

require_ready_env() {
  for name in OCTOPUSCORE_GRAFANA_HOST OCTOPUSCORE_METRICS_WRITE_HOST GRAFANA_ADMIN_PASSWORD REMOTE_WRITE_PASSWORD_HASH; do
    value="${!name:-}"
    [ -n "$value" ] || fail "set $name before --enable-now"
    case "$value" in
      *example.invalid*|CHANGE_ME*) fail "$name is still a placeholder" ;;
    esac
  done
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
say "bundle_asset=octopuscore-monitoring-ubuntu.tar.gz"

download SHA256SUMS
download octopuscore-monitoring-ubuntu.tar.gz
verify_asset octopuscore-monitoring-ubuntu.tar.gz

if [ "$DRY_RUN" = true ]; then
  say "would install bundle to $INSTALL_DIR"
  say "would write env file $ENV_FILE"
  say "would run docker compose only with --enable-now"
  exit 0
fi

install -d -m 0755 "$INSTALL_DIR"
tar -xzf "$WORK/octopuscore-monitoring-ubuntu.tar.gz" -C "$INSTALL_DIR" --strip-components=1
write_env

if [ "$ENABLE_NOW" = true ]; then
  require_cmd docker
  docker compose version >/dev/null 2>&1 || fail "docker compose is required"
  require_ready_env
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  (cd "$INSTALL_DIR" && docker compose -f compose.server.yml up -d)
else
  say "installed files only"
  say "set DNS/env values in $ENV_FILE, then run:"
  say "set -a; . $ENV_FILE; set +a; cd $INSTALL_DIR && docker compose -f compose.server.yml up -d"
fi
