#!/usr/bin/env bash
set -euo pipefail

REPO="${OCTOPUSCORE_DEPLOY_REPO:-SergeiSOficial/OctopusCore-Deploy}"
VERSION="${OCTOPUSCORE_VERSION:-latest}"
INSTALL_DIR="${OCTOPUSCORE_INSTALLER_DIR:-/opt/octopuscore-deploy/controller}"
BIND_ADDR="${OCTOPUSCORE_BIND:-127.0.0.1:8088}"
ENABLE_NOW=true
DRY_RUN=false

fail() {
  printf 'install-controller: FAIL: %s\n' "$*" >&2
  exit 1
}

say() {
  printf 'install-controller: %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: install-controller.sh [options]

Options:
  --version TAG       GitHub release tag, or latest
  --install-dir PATH  Temporary installer workspace
  --bind ADDR:PORT    Controller bind address
  --enable-now        Start service after install (default)
  --no-start          Install but do not start service
  --dry-run           Print planned host changes
  -h, --help          Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    --bind) BIND_ADDR="$2"; shift ;;
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

arch_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'ocpd-linux-amd64\n' ;;
    aarch64|arm64) printf 'ocpd-linux-arm64\n' ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
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
asset="$(arch_asset)"

say "release=$VERSION"
say "binary_asset=$asset"
say "bundle_asset=octopuscore-controller-ubuntu.tar.gz"

download SHA256SUMS
download "$asset"
download octopuscore-controller-ubuntu.tar.gz
verify_asset "$asset"
verify_asset octopuscore-controller-ubuntu.tar.gz

extract_dir="$INSTALL_DIR"
binary_path="$INSTALL_DIR/ocpd"
if [ "$DRY_RUN" = true ]; then
  extract_dir="$WORK/controller"
  binary_path="$WORK/$asset"
else
  install -d -m 0755 "$INSTALL_DIR"
  install -m 0755 "$WORK/$asset" "$binary_path"
fi
mkdir -p "$extract_dir"
tar -xzf "$WORK/octopuscore-controller-ubuntu.tar.gz" -C "$extract_dir" --strip-components=1

args=(--yes --binary "$binary_path" --bind "$BIND_ADDR")
if [ "$DRY_RUN" = true ]; then
  args=(--dry-run --binary "$binary_path" --bind "$BIND_ADDR")
elif [ "$ENABLE_NOW" = true ]; then
  args+=(--enable-now)
fi

"$extract_dir/scripts/install/install-main-controller-ubuntu.sh" "${args[@]}"
