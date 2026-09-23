#!/usr/bin/env bash
set -euo pipefail

die() { printf '[duckdns] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "${DUCKDNS_URL:-}" ]] || die "DUCKDNS_URL is required."
[[ -n "${DUCKDNS_TOKEN:-}" ]] || die "DUCKDNS_TOKEN is required."

domain="${DUCKDNS_URL#https://}"
domain="${domain#http://}"
domain="${domain%/}"
domain="${domain,,}"
[[ "$domain" =~ ^[a-z0-9][a-z0-9-]*\.duckdns\.org$ ]] \
  || die "DUCKDNS_URL must be a DuckDNS hostname, such as myserver.duckdns.org."
subdomain="${domain%.duckdns.org}"

case "${1:-}" in
  sync)
    ip="${2:-}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "A VM public IPv4 address is required for sync."
    IFS=. read -r octet1 octet2 octet3 octet4 <<< "$ip"
    for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
      (( 10#$octet <= 255 )) || die "Invalid VM public IPv4 address."
    done
    request=(--data-urlencode "ip=$ip")
    ;;
  clear)
    request=(--data-urlencode 'clear=true')
    ;;
  *)
    die "Usage: update-duckdns.sh sync PUBLIC_IPV4 | clear"
    ;;
esac

if ! response="$(curl --fail --silent --show-error --max-time 20 --retry 2 --get \
  --data-urlencode "domains=$subdomain" \
  --data-urlencode "token=$DUCKDNS_TOKEN" \
  "${request[@]}" \
  https://www.duckdns.org/update)"; then
  die "DuckDNS request failed."
fi
[[ "$response" == "OK" ]] || die "DuckDNS rejected the request. Check DUCKDNS_URL and DUCKDNS_TOKEN."
printf '[duckdns] %s %s: OK\n' "${1}" "$domain"
