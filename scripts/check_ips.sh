#!/usr/bin/env bash
set -u

get_ip() {
  local cmd="$1"
  local out
  if out=$(eval "$cmd" 2>/dev/null); then
    out=$(printf "%s" "$out" | tr -d '[:space:]')
    if [[ -n "$out" ]]; then
      printf "%s" "$out"
      return 0
    fi
  fi
  printf "No Data"
}

host_v4_cmd="curl -4 -s https://ifconfig.io"
host_v6_cmd="curl -6 -s https://ifconfig.io"

vpn_v4_cmd="docker exec gluetun wget -qO- -4 https://ifconfig.io"
vpn_v6_cmd="docker exec gluetun wget -qO- -6 https://ifconfig.io"

printf "Streamlab IPv4: %s\n" "$(get_ip "$host_v4_cmd")"
printf "Streamlab IPv6: %s\n\n" "$(get_ip "$host_v6_cmd")"

printf "VPN IPv4: %s\n" "$(get_ip "$vpn_v4_cmd")"
printf "VPN IPv6: %s\n" "$(get_ip "$vpn_v6_cmd")"


exit 0
