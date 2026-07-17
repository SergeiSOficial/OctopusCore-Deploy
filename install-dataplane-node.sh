#!/usr/bin/env bash
set -euo pipefail

REPO="${OCTOPUSCORE_DEPLOY_REPO:-SergeiSOficial/OctopusCore-Deploy}"
VERSION="${OCTOPUSCORE_VERSION:-latest}"
INSTALL_DIR="${OCTOPUSCORE_DATAPLANE_INSTALL_DIR:-/opt/octopuscore-deploy/dataplane-node}"
ENV_FILE="${OCTOPUSCORE_DATAPLANE_ENV_FILE:-/etc/octopuscore/dataplane-node.env}"
previous_argument=""
for argument in "$@"; do
  if [ "$previous_argument" = "--env-file" ]; then
    ENV_FILE="$argument"
    break
  fi
  previous_argument="$argument"
done

CONTROL_URL="${OCTOPUSCORE_CONTROL_URL:-}"
PUBLIC_GATEWAY="${OCTOPUSCORE_NODE_PUBLIC_GATEWAY:-}"
CONTROL_RELAY_GATEWAY="${OCTOPUSCORE_CONTROL_RELAY_GATEWAY:-}"
NODE_ID="${OCTOPUSCORE_NODE_ID:-}"
NODE_ROLES="${OCTOPUSCORE_NODE_ROLES:-}"
NODE_INTERFACE="${OCTOPUSCORE_NODE_INTERFACE:-}"
TUN_ADDRESS="${OCTOPUSCORE_TUN_ADDRESS:-}"
ROUTE_ADDRESS="${OCTOPUSCORE_NODE_ROUTE_ADDRESS:-}"
CLIENT_POOL="${OCTOPUSCORE_CLIENT_POOL:-}"
LISTEN_PORT="${OCTOPUSCORE_NODE_LISTEN_PORT:-}"
MTU="${OCTOPUSCORE_NODE_MTU:-}"
EGRESS_INTERFACE="${OCTOPUSCORE_EGRESS_INTERFACE:-}"
GATEWAY_DNS_RESOLVER="${OCTOPUSCORE_GATEWAY_DNS_RESOLVER:-}"
SPEED_PROOF_PORT="${OCTOPUSCORE_SPEED_PROOF_PORT:-}"
SPEED_PROOF_BIN="${OCTOPUSCORE_SPEED_PROOF_BIN:-}"
KEY_FILE="${OCTOPUSCORE_NODE_KEY_FILE:-}"
TRANSPORT_PROFILE_FILE="${OCTOPUSCORE_TRANSPORT_PROFILE_FILE:-}"
JOIN_TOKEN="${OCTOPUSCORE_NODE_JOIN_TOKEN:-}"
CONFIG_POLL_SECONDS="${OCTOPUSCORE_CONFIG_POLL_SECONDS:-}"
HEALTH_SECONDS="${OCTOPUSCORE_HEALTH_SECONDS:-}"
TOKEN_UPSERT=true
ENABLE_NOW=true
DRY_RUN=false

fail() {
  printf 'install-dataplane-node: FAIL: %s\n' "$*" >&2
  exit 1
}

say() {
  printf 'install-dataplane-node: %s\n' "$*"
}

existing_value() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 0
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^["'\'']|["'\'']$/, "", value)
      print value
    }' "$ENV_FILE" | tail -n 1
}

load_existing_dataplane_config() {
  [ -f "$ENV_FILE" ] || return 0
  CONTROL_URL="${CONTROL_URL:-$(existing_value "OCTOPUSCORE_CONTROL_URL")}"
  NODE_ID="${NODE_ID:-$(existing_value "OCTOPUSCORE_NODE_ID")}"
  NODE_ROLES="${NODE_ROLES:-$(existing_value "OCTOPUSCORE_NODE_ROLES")}"
  JOIN_TOKEN="${JOIN_TOKEN:-$(existing_value "OCTOPUSCORE_NODE_JOIN_TOKEN")}"
  PUBLIC_GATEWAY="${PUBLIC_GATEWAY:-$(existing_value "OCTOPUSCORE_NODE_PUBLIC_GATEWAY")}"
  CONTROL_RELAY_GATEWAY="${CONTROL_RELAY_GATEWAY:-$(existing_value "OCTOPUSCORE_CONTROL_RELAY_GATEWAY")}"
  NODE_INTERFACE="${NODE_INTERFACE:-$(existing_value "OCTOPUSCORE_NODE_INTERFACE")}"
  TUN_ADDRESS="${TUN_ADDRESS:-$(existing_value "OCTOPUSCORE_TUN_ADDRESS")}"
  ROUTE_ADDRESS="${ROUTE_ADDRESS:-$(existing_value "OCTOPUSCORE_NODE_ROUTE_ADDRESS")}"
  CLIENT_POOL="${CLIENT_POOL:-$(existing_value "OCTOPUSCORE_CLIENT_POOL")}"
  LISTEN_PORT="${LISTEN_PORT:-$(existing_value "OCTOPUSCORE_NODE_LISTEN_PORT")}"
  MTU="${MTU:-$(existing_value "OCTOPUSCORE_NODE_MTU")}"
  EGRESS_INTERFACE="${EGRESS_INTERFACE:-$(existing_value "OCTOPUSCORE_EGRESS_INTERFACE")}"
  GATEWAY_DNS_RESOLVER="${GATEWAY_DNS_RESOLVER:-$(existing_value "OCTOPUSCORE_GATEWAY_DNS_RESOLVER")}"
  KEY_FILE="${KEY_FILE:-$(existing_value "OCTOPUSCORE_NODE_KEY_FILE")}"
  TRANSPORT_PROFILE_FILE="${TRANSPORT_PROFILE_FILE:-$(existing_value "OCTOPUSCORE_TRANSPORT_PROFILE_FILE")}"
  SPEED_PROOF_BIN="${SPEED_PROOF_BIN:-$(existing_value "OCTOPUSCORE_SPEED_PROOF_BIN")}"
  SPEED_PROOF_PORT="${SPEED_PROOF_PORT:-$(existing_value "OCTOPUSCORE_SPEED_PROOF_PORT")}"
  CONFIG_POLL_SECONDS="${CONFIG_POLL_SECONDS:-$(existing_value "OCTOPUSCORE_CONFIG_POLL_SECONDS")}"
  HEALTH_SECONDS="${HEALTH_SECONDS:-$(existing_value "OCTOPUSCORE_HEALTH_SECONDS")}"
  say "preserved existing dataplane configuration from $ENV_FILE"
}

load_existing_dataplane_config
CONTROL_URL="${CONTROL_URL:-http://127.0.0.1:8088/v1}"
PUBLIC_GATEWAY="${PUBLIC_GATEWAY:-octopus.dedyn.io:443}"
CONTROL_RELAY_GATEWAY="${CONTROL_RELAY_GATEWAY:-https://octopus.dedyn.io/relay/control}"
NODE_ID="${NODE_ID:-oci-exit-1}"
NODE_ROLES="${NODE_ROLES:-exit,relay}"
NODE_INTERFACE="${NODE_INTERFACE:-octopus0}"
TUN_ADDRESS="${TUN_ADDRESS:-10.111.0.1/24}"
ROUTE_ADDRESS="${ROUTE_ADDRESS:-10.111.0.1/32}"
CLIENT_POOL="${CLIENT_POOL:-10.111.0.0/24}"
LISTEN_PORT="${LISTEN_PORT:-443}"
MTU="${MTU:-1280}"
EGRESS_INTERFACE="${EGRESS_INTERFACE:-auto}"
GATEWAY_DNS_RESOLVER="${GATEWAY_DNS_RESOLVER:-169.254.169.254}"
SPEED_PROOF_PORT="${SPEED_PROOF_PORT:-51901}"
SPEED_PROOF_BIN="${SPEED_PROOF_BIN:-/usr/local/lib/octopuscore/octopuscore-speed-proof}"
KEY_FILE="${KEY_FILE:-/etc/octopuscore/dataplane-node.key}"
TRANSPORT_PROFILE_FILE="${TRANSPORT_PROFILE_FILE:-/etc/octopuscore/dataplane-transport.toml}"
CONFIG_POLL_SECONDS="${CONFIG_POLL_SECONDS:-5}"
HEALTH_SECONDS="${HEALTH_SECONDS:-15}"

usage() {
  cat <<'EOF'
Usage: install-dataplane-node.sh [options]

Options:
  --version TAG            GitHub release tag, or latest
  --install-dir PATH       Install directory
  --env-file PATH          Environment file path
  --control-url URL        Coordinator API base URL, default http://127.0.0.1:8088/v1
  --gateway HOST:PORT      Public DCP gateway, default octopus.dedyn.io:443
  --node-id ID             Node id, default oci-exit-1
  --listen-port PORT       UDP listen port, default 443
  --egress-if IFACE        Public egress interface, default auto
  --dns-resolver ADDRESS   Gateway DNS resolver for client DNS, default 169.254.169.254
  --join-token TOKEN       Existing join token id
  --no-token-upsert        Do not create/update token through local coordinator API
  --enable-now             Start systemd service after install (default)
  --no-start               Install files only
  --dry-run                Print planned changes
  -h, --help               Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    --env-file) ENV_FILE="$2"; shift ;;
    --control-url) CONTROL_URL="$2"; shift ;;
    --gateway) PUBLIC_GATEWAY="$2"; shift ;;
    --node-id) NODE_ID="$2"; shift ;;
    --listen-port) LISTEN_PORT="$2"; shift ;;
    --egress-if) EGRESS_INTERFACE="$2"; shift ;;
    --dns-resolver) GATEWAY_DNS_RESOLVER="$2"; shift ;;
    --join-token) JOIN_TOKEN="$2"; shift ;;
    --no-token-upsert) TOKEN_UPSERT=false ;;
    --enable-now) ENABLE_NOW=true ;;
    --no-start) ENABLE_NOW=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
  shift
done

SPEED_PROOF_INSTALL_DIR="$(dirname "$SPEED_PROOF_BIN")"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

detect_egress_if() {
  if [ "$EGRESS_INTERFACE" != "auto" ]; then
    printf '%s\n' "$EGRESS_INTERFACE"
    return 0
  fi
  ip route get 1.1.1.1 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "dev" && (i + 1) <= NF) {
          print $(i + 1)
          exit
        }
      }
    }'
}

delete_dns_dnat_rules() {
  local gateway_dns="$GATEWAY_DNS_RESOLVER:53"
  while iptables -t nat -D PREROUTING -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p udp --dport 53 -j DNAT --to-destination "$gateway_dns" 2>/dev/null; do
    :
  done
  while iptables -t nat -D PREROUTING -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p tcp --dport 53 -j DNAT --to-destination "$gateway_dns" 2>/dev/null; do
    :
  done
}

write_gateway_dns_resolved_dropin() {
  local listen_ip resolved_dir resolved_conf
  listen_ip="${TUN_ADDRESS%%/*}"
  resolved_dir="/etc/systemd/resolved.conf.d"
  resolved_conf="$resolved_dir/octopuscore-gateway.conf"

  install -d -m 0755 "$resolved_dir"
  cat > "$resolved_conf" <<EOF
[Resolve]
DNS=$GATEWAY_DNS_RESOLVER
DNSStubListener=yes
DNSStubListenerExtra=$listen_ip
EOF
}

checksum() {
  sha256sum "$1" | awk '{print $1}'
}

release_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) fail "unsupported dataplane architecture: $(uname -m)" ;;
  esac
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

install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      iproute2 \
      iptables \
      python3 \
      tar \
      wireguard-tools
  fi
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    od -An -tx1 -N24 /dev/urandom | tr -d ' \n'
  fi
}

env_value() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 0
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^["'\'']|["'\'']$/, "", value)
      print value
    }' "$file" | tail -n 1
}

ensure_key() {
  install -d -m 0750 "$(dirname "$KEY_FILE")"
  if [ ! -s "$KEY_FILE" ]; then
    (umask 077 && wg genkey > "$KEY_FILE")
    chmod 0600 "$KEY_FILE"
  fi
}

public_key() {
  wg pubkey < "$KEY_FILE"
}

create_join_token() {
  local body out code expires uses
  expires="${OCTOPUSCORE_NODE_JOIN_TOKEN_EXPIRES_AT:-4102444800}"
  uses="${OCTOPUSCORE_NODE_JOIN_TOKEN_USES:-1000000}"
  body="$WORK/join-token.json"
  out="$WORK/join-token-response.json"
  python3 - "$body" "$JOIN_TOKEN" "$expires" "$uses" <<'PY'
import json
import sys

out, token_id, expires, uses = sys.argv[1:5]
body = {
    "token": {
        "token_id": token_id,
        "allowed_roles": ["exit", "relay"],
        "expires_at_unix": int(expires),
        "uses_remaining": int(uses),
    }
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(body, handle, separators=(",", ":"))
PY
  code="$(curl -sS -o "$out" -w '%{http_code}' \
    -X POST \
    -H 'content-type: application/json' \
    --data-binary @"$body" \
    --max-time 8 \
    "${CONTROL_URL%/}/tokens" || true)"
  case "$code" in
    200|201) say "created or refreshed local join token" ;;
    *) say "join token upsert returned HTTP $code: $(cat "$out" 2>/dev/null || true)" ;;
  esac
}

ensure_firewall_rules() {
  local egress_if
  egress_if="$(detect_egress_if)"
  [ -n "$egress_if" ] || fail "could not detect egress interface"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  iptables -C INPUT -p udp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p udp --dport "$LISTEN_PORT" -j ACCEPT
  iptables -C FORWARD -i "$NODE_INTERFACE" -o "$egress_if" -s "$CLIENT_POOL" -j ACCEPT 2>/dev/null \
    || iptables -I FORWARD 1 -i "$NODE_INTERFACE" -o "$egress_if" -s "$CLIENT_POOL" -j ACCEPT
  iptables -C FORWARD -i "$egress_if" -o "$NODE_INTERFACE" -d "$CLIENT_POOL" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -I FORWARD 1 -i "$egress_if" -o "$NODE_INTERFACE" -d "$CLIENT_POOL" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -C POSTROUTING -s "$CLIENT_POOL" -o "$egress_if" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "$CLIENT_POOL" -o "$egress_if" -j MASQUERADE
  delete_dns_dnat_rules
  iptables -C INPUT -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p udp --dport 53 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p udp --dport 53 -j ACCEPT
  iptables -C INPUT -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p tcp --dport 53 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p tcp --dport 53 -j ACCEPT
  iptables -C INPUT -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p tcp --dport "$SPEED_PROOF_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p tcp --dport "$SPEED_PROOF_PORT" -j ACCEPT
  iptables -C INPUT -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p udp --dport "$SPEED_PROOF_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -i "$NODE_INTERFACE" -s "$CLIENT_POOL" -p udp --dport "$SPEED_PROOF_PORT" -j ACCEPT
}

write_transport_profile() {
  install -d -m 0750 "$(dirname "$TRANSPORT_PROFILE_FILE")"
  install -m 0644 "$INSTALL_DIR/transport-dcp-v3.toml" "$TRANSPORT_PROFILE_FILE"
}

write_env() {
  local node_public_key
  node_public_key="$(public_key)"
  install -d -m 0750 "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
OCTOPUSCORE_CONTROL_URL=$CONTROL_URL
OCTOPUSCORE_NODE_ID=$NODE_ID
OCTOPUSCORE_NODE_ROLES=$NODE_ROLES
OCTOPUSCORE_NODE_JOIN_TOKEN=$JOIN_TOKEN
OCTOPUSCORE_NODE_PUBLIC_KEY=$node_public_key
OCTOPUSCORE_NODE_PUBLIC_GATEWAY=$PUBLIC_GATEWAY
OCTOPUSCORE_CONTROL_RELAY_GATEWAY=$CONTROL_RELAY_GATEWAY
OCTOPUSCORE_NODE_INTERFACE=$NODE_INTERFACE
OCTOPUSCORE_TUN_ADDRESS=$TUN_ADDRESS
OCTOPUSCORE_NODE_ROUTE_ADDRESS=$ROUTE_ADDRESS
OCTOPUSCORE_CLIENT_POOL=$CLIENT_POOL
OCTOPUSCORE_NODE_LISTEN_PORT=$LISTEN_PORT
OCTOPUSCORE_NODE_MTU=$MTU
OCTOPUSCORE_EGRESS_INTERFACE=$EGRESS_INTERFACE
OCTOPUSCORE_GATEWAY_DNS_RESOLVER=$GATEWAY_DNS_RESOLVER
OCTOPUSCORE_NODE_KEY_FILE=$KEY_FILE
OCTOPUSCORE_TRANSPORT_PROFILE_FILE=$TRANSPORT_PROFILE_FILE
OCTOPUSCORE_GOTATUN_BIN=/usr/local/bin/gotatun
OCTOPUSCORE_SPEED_PROOF_BIN=$SPEED_PROOF_BIN
OCTOPUSCORE_SPEED_PROOF_PORT=$SPEED_PROOF_PORT
OCTOPUSCORE_CONFIG_POLL_SECONDS=$CONFIG_POLL_SECONDS
OCTOPUSCORE_HEALTH_SECONDS=$HEALTH_SECONDS
EOF
  chmod 0600 "$ENV_FILE"
}

sync_controller_public_key() {
  local controller_env="/etc/octopuscore/octopuscore.env"
  local node_public_key tmp
  [ -f "$controller_env" ] || return 0
  node_public_key="$(public_key)"
  tmp="$(mktemp)"
  awk -F= -v value="$node_public_key" '
    BEGIN { updated = 0 }
    $1 == "OCTOPUSCORE_SERVER_PUBLIC_KEY" {
      print "OCTOPUSCORE_SERVER_PUBLIC_KEY=" value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) print "OCTOPUSCORE_SERVER_PUBLIC_KEY=" value
    }
  ' "$controller_env" > "$tmp"
  install -m 0600 "$tmp" "$controller_env"
  rm -f "$tmp"
  if systemctl list-unit-files octopuscore.service >/dev/null 2>&1; then
    systemctl restart octopuscore.service
  fi
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
say "bundle_asset=octopuscore-dataplane-node-ubuntu.tar.gz"
say "binary_asset=gotatun-linux-amd64"
SPEED_PROOF_ASSET="octopuscore-speed-proof-linux-$(release_arch)"
say "speed-proof-binary-asset=$SPEED_PROOF_ASSET"

download SHA256SUMS
download gotatun-linux-amd64
download "$SPEED_PROOF_ASSET"
download octopuscore-dataplane-node-ubuntu.tar.gz
verify_asset gotatun-linux-amd64
verify_asset "$SPEED_PROOF_ASSET"
verify_asset octopuscore-dataplane-node-ubuntu.tar.gz

if [ "$DRY_RUN" = true ]; then
  say "would install gotatun to /usr/local/bin/gotatun"
  say "would install Link speed service to $SPEED_PROOF_BIN"
  say "would install bundle to $INSTALL_DIR"
  say "would write env file $ENV_FILE"
  say "would start octopuscore-dataplane-node.service when --enable-now is active"
  exit 0
fi

install_packages
require_cmd wg
require_cmd ip
require_cmd iptables
require_cmd python3
require_cmd sha256sum

install -d -m 0755 "$INSTALL_DIR"
install -d -m 0755 "$SPEED_PROOF_INSTALL_DIR"
tar -xzf "$WORK/octopuscore-dataplane-node-ubuntu.tar.gz" -C "$INSTALL_DIR" --strip-components=1
install -m 0755 "$WORK/gotatun-linux-amd64" /usr/local/bin/gotatun
install -m 0755 "$WORK/$SPEED_PROOF_ASSET" "$SPEED_PROOF_BIN"
chmod +x "$INSTALL_DIR/run-dataplane-node.sh"

ensure_key
if [ -z "$JOIN_TOKEN" ]; then
  JOIN_TOKEN="$(env_value /etc/octopuscore/octopuscore.env OCTOPUSCORE_JOIN_TOKEN)"
fi
if [ -z "$JOIN_TOKEN" ]; then
  JOIN_TOKEN="$(random_token)"
fi

write_transport_profile
write_env
sync_controller_public_key
write_gateway_dns_resolved_dropin
ensure_firewall_rules

if [ "$TOKEN_UPSERT" = true ]; then
  create_join_token
fi

install -m 0644 "$INSTALL_DIR/octopuscore-dataplane-node.service" /etc/systemd/system/octopuscore-dataplane-node.service
systemctl daemon-reload

if [ "$ENABLE_NOW" = true ]; then
  systemctl enable --now octopuscore-dataplane-node.service
  systemctl restart octopuscore-dataplane-node.service
else
  say "installed files; start with: systemctl enable --now octopuscore-dataplane-node.service"
fi
