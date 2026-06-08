#!/usr/bin/env bash
set -euo pipefail

HOST="${OCTOPUSCORE_PUBLIC_HOST:-octopuscore.duckdns.org}"
UPSTREAM="${OCTOPUSCORE_FRONTING_UPSTREAM:-127.0.0.1:8088}"
CADDYFILE="${OCTOPUSCORE_CADDYFILE:-/etc/caddy/Caddyfile}"
ACME_EMAIL="${ACME_EMAIL:-}"
DRY_RUN=false

fail() {
  printf 'install-fronting: FAIL: %s\n' "$*" >&2
  exit 1
}

say() {
  printf 'install-fronting: %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: install-fronting.sh [options]

Options:
  --host NAME         Public HTTPS hostname (default octopuscore.duckdns.org)
  --upstream ADDR    Local coordinator upstream (default 127.0.0.1:8088)
  --email EMAIL      Optional ACME contact email
  --dry-run          Print planned changes
  -h, --help         Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)
      [ "$#" -ge 2 ] || fail "--host requires a value"
      HOST="$2"
      shift
      ;;
    --upstream)
      [ "$#" -ge 2 ] || fail "--upstream requires a value"
      UPSTREAM="$2"
      shift
      ;;
    --email)
      [ "$#" -ge 2 ] || fail "--email requires a value"
      ACME_EMAIL="$2"
      shift
      ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown option $1" ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

write_caddyfile() {
  if [ "$DRY_RUN" = true ]; then
    say "would write $CADDYFILE for host=$HOST upstream=$UPSTREAM"
    return 0
  fi

  install -d -m 0755 "$(dirname "$CADDYFILE")"
  tmp="$(mktemp)"
  {
    if [ -n "$ACME_EMAIL" ]; then
      printf '{\n\temail %s\n}\n\n' "$ACME_EMAIL"
    fi
    cat <<EOF
$HOST {
	@public_api {
		path /healthz /v1/*
	}

	handle @public_api {
		reverse_proxy $UPSTREAM
	}

	respond 404
}
EOF
  } > "$tmp"
  install -m 0644 "$tmp" "$CADDYFILE"
  rm -f "$tmp"
}

open_host_firewall() {
  if command -v iptables >/dev/null 2>&1; then
    for port in 80 443; do
      if iptables -C INPUT -p tcp -m tcp --dport "$port" -m state --state NEW -j ACCEPT >/dev/null 2>&1; then
        say "iptables already allows tcp/$port"
      else
        run_cmd iptables -I INPUT 5 -p tcp -m tcp --dport "$port" -m state --state NEW -j ACCEPT
      fi
    done
    if [ "$DRY_RUN" = false ] && command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save >/dev/null || say "warning: failed to persist iptables rules"
    elif [ "$DRY_RUN" = false ] && [ -d /etc/iptables ] && command -v iptables-save >/dev/null 2>&1; then
      iptables-save > /etc/iptables/rules.v4 || say "warning: failed to persist iptables rules"
    fi
  else
    say "SKIP host firewall: iptables unavailable"
  fi
}

[ -n "$HOST" ] || fail "host is required"
[ -n "$UPSTREAM" ] || fail "upstream is required"

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" = false ]; then
  fail "real install requires root; rerun with sudo"
fi

say "host=$HOST"
say "upstream=$UPSTREAM"
say "caddyfile=$CADDYFILE"

if ! command -v caddy >/dev/null 2>&1; then
  require_cmd apt-get
  run_cmd apt-get update
  run_cmd apt-get install -y caddy
fi

write_caddyfile
open_host_firewall

if [ "$DRY_RUN" = true ]; then
  say "would validate and restart caddy"
  exit 0
fi

require_cmd caddy
caddy validate --config "$CADDYFILE" >/dev/null
systemctl enable --now caddy.service >/dev/null
systemctl reload caddy.service 2>/dev/null || systemctl restart caddy.service

say "health check: curl -fsS https://$HOST/healthz"
say "public config: curl -fsS https://$HOST/v1/config.json"
