#!/usr/bin/env bash
set -euo pipefail

REPO="${OCTOPUSCORE_DEPLOY_REPO:-SergeiSOficial/OctopusCore-Deploy}"
VERSION="${OCTOPUSCORE_VERSION:-latest}"
INSTALL_DIR="${OCTOPUSCORE_INSTALLER_DIR:-/opt/octopuscore-deploy/controller}"
BIND_ADDR="${OCTOPUSCORE_BIND:-127.0.0.1:8088}"
CONTROL_GATEWAY="${OCTOPUSCORE_CONTROL_GATEWAY:-https://octopus.dedyn.io/v1}"
ENVIRONMENT="${OCTOPUSCORE_ENVIRONMENT:-development}"
ACCESS_POINTS_JSON="${OCTOPUSCORE_ACCESS_POINTS_JSON:-}"
DIRECTORY_VERSION="${OCTOPUSCORE_DIRECTORY_VERSION:-1}"
PUBLIC_BASE_URL="${OCTOPUSCORE_PUBLIC_BASE_URL:-https://octopus.dedyn.io}"
PUBLIC_UDP_GATEWAY="${OCTOPUSCORE_PUBLIC_UDP_GATEWAY:-udp://octopus.dedyn.io:443}"
PUBLIC_DCP_GATEWAYS="${OCTOPUSCORE_PUBLIC_DCP_GATEWAYS:-}"
PUBLIC_DCP_HTTPS_GATEWAYS="${OCTOPUSCORE_PUBLIC_DCP_HTTPS_GATEWAYS:-https://octopus.dedyn.io/v1/link/dcp-https}"
PUBLIC_DCP_DOH_GATEWAYS="${OCTOPUSCORE_PUBLIC_DCP_DOH_GATEWAYS:-https://octopus.dedyn.io/dns-query}"
PUBLIC_MASQUE_GATEWAYS="${OCTOPUSCORE_PUBLIC_MASQUE_GATEWAYS:-}"
PUBLIC_DCP_DNS_ZONES="${OCTOPUSCORE_PUBLIC_DCP_DNS_ZONES:-ocl.octopus.dedyn.io}"
DCP_HTTPS_UPSTREAM="${OCTOPUSCORE_DCP_HTTPS_UPSTREAM:-127.0.0.1:443}"
DCP_DNS_UDP_BIND="${OCTOPUSCORE_DCP_DNS_UDP_BIND:-}"
DCP_DNS_UPSTREAM="${OCTOPUSCORE_DCP_DNS_UPSTREAM:-127.0.0.1:443}"
DCP_DNS_MAX_QUERY_BYTES="${OCTOPUSCORE_DCP_DNS_MAX_QUERY_BYTES:-1232}"
DCP_DNS_MAX_RESPONSE_BYTES="${OCTOPUSCORE_DCP_DNS_MAX_RESPONSE_BYTES:-1232}"
MASQUE_UDP_BIND="${OCTOPUSCORE_MASQUE_UDP_BIND:-}"
MASQUE_TLS_CERT="${OCTOPUSCORE_MASQUE_TLS_CERT:-}"
MASQUE_TLS_KEY="${OCTOPUSCORE_MASQUE_TLS_KEY:-}"
SERVER_PUBLIC_KEY="${OCTOPUSCORE_SERVER_PUBLIC_KEY:-}"
TLS_PIN="${OCTOPUSCORE_TLS_PIN:-BVX+RGCG1xMcqwiYuLmB+/Fw/80T+RDuqkXC0S/G6yo=}"
ENABLE_NOW=true
DRY_RUN=false
SYNC_DATAPLANE=auto

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
  --control-gateway URL
  --environment MODE
  --access-points-json JSON
  --directory-version NUMBER
  --public-base-url URL
  --public-udp-gateway URL
  --public-dcp-gateways CSV
  --public-dcp-https-gateways CSV
  --public-dcp-doh-gateways CSV
  --public-masque-gateways CSV
  --public-dcp-dns-zones CSV
  --dcp-https-upstream HOST:PORT
  --dcp-dns-udp-bind ADDR:PORT
  --dcp-dns-upstream HOST:PORT
  --dcp-dns-max-query-bytes BYTES
  --dcp-dns-max-response-bytes BYTES
  --masque-udp-bind ADDR:PORT
  --masque-tls-cert PATH
  --masque-tls-key PATH
  --server-public-key BASE64
  --tls-pin BASE64
  --enable-now        Start service after install (default)
  --no-start          Install but do not start service
  --sync-dataplane    Install the same release on the colocated dataplane
  --no-sync-dataplane Do not update an installed colocated dataplane
  --dry-run           Print planned host changes
  -h, --help          Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    --bind) BIND_ADDR="$2"; shift ;;
    --control-gateway) CONTROL_GATEWAY="$2"; shift ;;
    --environment) ENVIRONMENT="$2"; shift ;;
    --access-points-json) ACCESS_POINTS_JSON="$2"; shift ;;
    --directory-version) DIRECTORY_VERSION="$2"; shift ;;
    --public-base-url) PUBLIC_BASE_URL="$2"; shift ;;
    --public-udp-gateway) PUBLIC_UDP_GATEWAY="$2"; shift ;;
    --public-dcp-gateways) PUBLIC_DCP_GATEWAYS="$2"; shift ;;
    --public-dcp-https-gateways) PUBLIC_DCP_HTTPS_GATEWAYS="$2"; shift ;;
    --public-dcp-doh-gateways) PUBLIC_DCP_DOH_GATEWAYS="$2"; shift ;;
    --public-masque-gateways) PUBLIC_MASQUE_GATEWAYS="$2"; shift ;;
    --public-dcp-dns-zones) PUBLIC_DCP_DNS_ZONES="$2"; shift ;;
    --dcp-https-upstream) DCP_HTTPS_UPSTREAM="$2"; shift ;;
    --dcp-dns-udp-bind) DCP_DNS_UDP_BIND="$2"; shift ;;
    --dcp-dns-upstream) DCP_DNS_UPSTREAM="$2"; shift ;;
    --dcp-dns-max-query-bytes) DCP_DNS_MAX_QUERY_BYTES="$2"; shift ;;
    --dcp-dns-max-response-bytes) DCP_DNS_MAX_RESPONSE_BYTES="$2"; shift ;;
    --masque-udp-bind) MASQUE_UDP_BIND="$2"; shift ;;
    --masque-tls-cert) MASQUE_TLS_CERT="$2"; shift ;;
    --masque-tls-key) MASQUE_TLS_KEY="$2"; shift ;;
    --server-public-key) SERVER_PUBLIC_KEY="$2"; shift ;;
    --tls-pin) TLS_PIN="$2"; shift ;;
    --enable-now) ENABLE_NOW=true ;;
    --no-start) ENABLE_NOW=false ;;
    --sync-dataplane) SYNC_DATAPLANE=true ;;
    --no-sync-dataplane) SYNC_DATAPLANE=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
  shift
done

should_sync_colocated_dataplane() {
  case "$SYNC_DATAPLANE" in
    true) return 0 ;;
    false) return 1 ;;
    auto)
      [ -f /etc/systemd/system/octopuscore-dataplane-node.service ] ||
        systemctl list-unit-files octopuscore-dataplane-node.service >/dev/null 2>&1
      ;;
    *) fail "invalid dataplane synchronization mode: $SYNC_DATAPLANE" ;;
  esac
}

verify_colocated_dataplane() {
  local env_file speed_bin speed_port
  env_file="/etc/octopuscore/dataplane-node.env"
  speed_bin="/usr/local/lib/octopuscore/octopuscore-speed-proof"
  speed_port="51901"
  if [ -f "$env_file" ]; then
    speed_bin="$(awk -F= '$1 == "OCTOPUSCORE_SPEED_PROOF_BIN" { print substr($0, index($0, "=") + 1) }' "$env_file" | tail -n 1)"
    speed_port="$(awk -F= '$1 == "OCTOPUSCORE_SPEED_PROOF_PORT" { print substr($0, index($0, "=") + 1) }' "$env_file" | tail -n 1)"
    speed_bin="${speed_bin:-/usr/local/lib/octopuscore/octopuscore-speed-proof}"
    speed_port="${speed_port:-51901}"
  fi
  systemctl is-active --quiet octopuscore-dataplane-node.service ||
    fail "colocated dataplane service is not active"
  [ -x "$speed_bin" ] || fail "missing Link speed service executable $speed_bin"
  ss -H -ltn | awk -v port=":$speed_port" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ port "$") {
          found = 1
        }
      }
    }
    END { exit found ? 0 : 1 }' ||
    fail "Link speed TCP listener is unavailable on port $speed_port"
  ss -H -lun | awk -v port=":$speed_port" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ port "$") {
          found = 1
        }
      }
    }
    END { exit found ? 0 : 1 }' ||
    fail "Link speed UDP listener is unavailable on port $speed_port"
  say "verified colocated dataplane and octopuscore-speed-proof listeners"
}

existing_dataplane_public_key() {
  local env_file="/etc/octopuscore/dataplane-node.env"
  [ -f "$env_file" ] || return 0
  awk -F= '$1 == "OCTOPUSCORE_NODE_PUBLIC_KEY" { print substr($0, index($0, "=") + 1) }' \
    "$env_file" | tail -n 1
}

if [ -z "$SERVER_PUBLIC_KEY" ]; then
  SERVER_PUBLIC_KEY="$(existing_dataplane_public_key)"
fi
if [ -z "$SERVER_PUBLIC_KEY" ]; then
  SERVER_PUBLIC_KEY="SUH0D3XJfvzk0nl7rtnUrE6mnf3lJdWaOA197yVGOUI="
fi

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

args=(
  --yes
  --binary "$binary_path"
  --bind "$BIND_ADDR"
  --control-gateway "$CONTROL_GATEWAY"
  --environment "$ENVIRONMENT"
  --access-points-json "$ACCESS_POINTS_JSON"
  --directory-version "$DIRECTORY_VERSION"
  --public-base-url "$PUBLIC_BASE_URL"
  --public-udp-gateway "$PUBLIC_UDP_GATEWAY"
  --public-dcp-gateways "$PUBLIC_DCP_GATEWAYS"
  --public-dcp-https-gateways "$PUBLIC_DCP_HTTPS_GATEWAYS"
  --public-dcp-doh-gateways "$PUBLIC_DCP_DOH_GATEWAYS"
  --public-masque-gateways "$PUBLIC_MASQUE_GATEWAYS"
  --public-dcp-dns-zones "$PUBLIC_DCP_DNS_ZONES"
  --dcp-https-upstream "$DCP_HTTPS_UPSTREAM"
  --dcp-dns-udp-bind "$DCP_DNS_UDP_BIND"
  --dcp-dns-upstream "$DCP_DNS_UPSTREAM"
  --dcp-dns-max-query-bytes "$DCP_DNS_MAX_QUERY_BYTES"
  --dcp-dns-max-response-bytes "$DCP_DNS_MAX_RESPONSE_BYTES"
  --masque-udp-bind "$MASQUE_UDP_BIND"
  --masque-tls-cert "$MASQUE_TLS_CERT"
  --masque-tls-key "$MASQUE_TLS_KEY"
  --server-public-key "$SERVER_PUBLIC_KEY"
  --tls-pin "$TLS_PIN"
)
if [ "$DRY_RUN" = true ]; then
  args=(
    --dry-run
    --binary "$binary_path"
    --bind "$BIND_ADDR"
    --control-gateway "$CONTROL_GATEWAY"
    --environment "$ENVIRONMENT"
    --access-points-json "$ACCESS_POINTS_JSON"
    --directory-version "$DIRECTORY_VERSION"
    --public-base-url "$PUBLIC_BASE_URL"
    --public-udp-gateway "$PUBLIC_UDP_GATEWAY"
    --public-dcp-gateways "$PUBLIC_DCP_GATEWAYS"
    --public-dcp-https-gateways "$PUBLIC_DCP_HTTPS_GATEWAYS"
    --public-dcp-doh-gateways "$PUBLIC_DCP_DOH_GATEWAYS"
    --public-masque-gateways "$PUBLIC_MASQUE_GATEWAYS"
    --public-dcp-dns-zones "$PUBLIC_DCP_DNS_ZONES"
    --dcp-https-upstream "$DCP_HTTPS_UPSTREAM"
    --dcp-dns-udp-bind "$DCP_DNS_UDP_BIND"
    --dcp-dns-upstream "$DCP_DNS_UPSTREAM"
    --dcp-dns-max-query-bytes "$DCP_DNS_MAX_QUERY_BYTES"
    --dcp-dns-max-response-bytes "$DCP_DNS_MAX_RESPONSE_BYTES"
    --masque-udp-bind "$MASQUE_UDP_BIND"
    --masque-tls-cert "$MASQUE_TLS_CERT"
    --masque-tls-key "$MASQUE_TLS_KEY"
    --server-public-key "$SERVER_PUBLIC_KEY"
    --tls-pin "$TLS_PIN"
  )
elif [ "$ENABLE_NOW" = true ]; then
  args+=(--enable-now)
fi

"$extract_dir/scripts/install/install-main-controller-ubuntu.sh" "${args[@]}"

if should_sync_colocated_dataplane; then
  if [ "$DRY_RUN" = true ]; then
    say "would synchronize installed colocated dataplane to release $VERSION"
  else
    dataplane_installer="$WORK/install-dataplane-node.sh"
    curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/install-dataplane-node.sh" \
      -o "$dataplane_installer"
    chmod +x "$dataplane_installer"
    dataplane_args=(--version "$VERSION")
    if [ "$ENABLE_NOW" = true ]; then
      dataplane_args+=(--enable-now)
    else
      dataplane_args+=(--no-start)
    fi
    "$dataplane_installer" "${dataplane_args[@]}"
    if [ "$ENABLE_NOW" = true ]; then
      verify_colocated_dataplane
    fi
  fi
fi
