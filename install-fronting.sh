#!/usr/bin/env bash
set -euo pipefail

HOST="${OCTOPUSCORE_PUBLIC_HOST:-octopus.dedyn.io}"
UPSTREAM="${OCTOPUSCORE_FRONTING_UPSTREAM:-127.0.0.1:8088}"
CADDYFILE="${OCTOPUSCORE_CADDYFILE:-/etc/caddy/Caddyfile}"
ACME_EMAIL="${ACME_EMAIL:-}"
DESEC_DOMAIN="${OCTOPUSCORE_DESEC_DOMAIN:-}"
DESEC_TOKEN="${OCTOPUSCORE_DESEC_TOKEN:-${DESEC_TOKEN:-}}"
DESEC_TOKEN_FILE="${OCTOPUSCORE_DESEC_TOKEN_FILE:-}"
DESEC_IPV4="${OCTOPUSCORE_DESEC_IPV4:-${OCTOPUSCORE_PUBLIC_IPV4:-}}"
DESEC_PRESERVE_IPV6="${OCTOPUSCORE_DESEC_PRESERVE_IPV6:-true}"
SKIP_DESEC_UPDATE=false
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
  --host NAME              Public HTTPS hostname (default octopus.dedyn.io)
  --upstream ADDR         Local coordinator upstream (default 127.0.0.1:8088)
  --email EMAIL           Optional ACME contact email
  --desec-domain NAME     deSEC hostname to update (default: --host)
  --desec-token VALUE     deSEC dynDNS token; prefer --desec-token-file
  --desec-token-file PATH Read deSEC dynDNS token from a root-only file
  --desec-ip IPV4         Public IPv4 to publish; omit to let deSEC detect it
  --skip-desec-update     Do not update deSEC DNS before Caddy reload
  --dry-run               Print planned changes
  -h, --help              Show help
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
    --desec-domain)
      [ "$#" -ge 2 ] || fail "--desec-domain requires a value"
      DESEC_DOMAIN="$2"
      shift
      ;;
    --desec-token)
      [ "$#" -ge 2 ] || fail "--desec-token requires a value"
      DESEC_TOKEN="$2"
      shift
      ;;
    --desec-token-file)
      [ "$#" -ge 2 ] || fail "--desec-token-file requires a value"
      DESEC_TOKEN_FILE="$2"
      shift
      ;;
    --desec-ip)
      [ "$#" -ge 2 ] || fail "--desec-ip requires a value"
      DESEC_IPV4="$2"
      shift
      ;;
    --skip-desec-update) SKIP_DESEC_UPDATE=true ;;
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

read_desec_token() {
  if [ -n "$DESEC_TOKEN" ]; then
    printf '%s' "$DESEC_TOKEN"
    return 0
  fi
  if [ -n "$DESEC_TOKEN_FILE" ]; then
    [ -f "$DESEC_TOKEN_FILE" ] || fail "deSEC token file not found: $DESEC_TOKEN_FILE"
    tr -d '\r\n' < "$DESEC_TOKEN_FILE"
  fi
}

update_desec_dns() {
  local domain token response netrc_file
  local -a curl_args

  [ "$SKIP_DESEC_UPDATE" = false ] || {
    say "SKIP deSEC DNS update (--skip-desec-update)"
    return 0
  }

  domain="${DESEC_DOMAIN:-$HOST}"
  case "$domain" in
    *.dedyn.io) ;;
    *)
      say "SKIP deSEC DNS update: $domain is not a dedyn.io hostname"
      return 0
      ;;
  esac

  token="$(read_desec_token)"
  if [ -z "$token" ]; then
    say "SKIP deSEC DNS update: set OCTOPUSCORE_DESEC_TOKEN or --desec-token-file"
    return 0
  fi

  require_cmd curl
  if [ "$DRY_RUN" = true ]; then
    say "would update deSEC DNS for $domain using token=<redacted> ipv4=${DESEC_IPV4:-auto} ipv6=${DESEC_PRESERVE_IPV6}"
    return 0
  fi

  netrc_file="$(mktemp)"
  chmod 0600 "$netrc_file"
  printf 'machine update.dedyn.io login %s password %s\n' "$domain" "$token" > "$netrc_file"

  curl_args=(
    -fsS
    --get
    --netrc-file "$netrc_file"
    --data-urlencode "hostname=$domain"
  )
  if [ -n "$DESEC_IPV4" ]; then
    curl_args+=(--data-urlencode "myipv4=$DESEC_IPV4")
  fi
  if [ "$DESEC_PRESERVE_IPV6" = true ]; then
    curl_args+=(--data-urlencode "myipv6=preserve")
  fi

  if ! response="$(curl "${curl_args[@]}" https://update.dedyn.io/)"; then
    rm -f "$netrc_file"
    fail "deSEC DNS update request failed for $domain"
  fi
  rm -f "$netrc_file"

  [ "$response" = "good" ] || fail "deSEC DNS update failed for $domain: $response"
  say "deSEC DNS updated for $domain"
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
      printf '{\n\temail %s\n\tservers {\n\t\tprotocols h1 h2\n\t}\n}\n\n' "$ACME_EMAIL"
    else
      cat <<'EOF'
{
	servers {
		protocols h1 h2
	}
}

EOF
    fi
    cat <<EOF
$HOST {
	handle_path /client-updates/* {
		root * /var/lib/octopuscore/client-updates
		file_server
	}

	@public_api {
		path /healthz /v1/* /v3/* /dns-query
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
say "desec_domain=${DESEC_DOMAIN:-$HOST}"

if ! command -v caddy >/dev/null 2>&1; then
  require_cmd apt-get
  run_cmd apt-get update
  run_cmd apt-get install -y caddy
fi

update_desec_dns
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
