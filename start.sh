#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Pi-hole startup: %s\n' "$*" >&2
  return 1
}

detect_iface() {
  if ip link show dev veth1 >/dev/null 2>&1; then
    printf '%s\n' veth1
    return
  fi

  # Consume the full output to avoid SIGPIPE with pipefail enabled.
  ip -o link show up | awk -F': ' '
    { name = $2; sub(/@.*/, "", name) }
    name != "lo" && name != "" && !found { print name; found = 1 }
  '
}

configure_network() {
  local setup=$1 dns=$2 iface mode
  [[ -f "$setup" && -f "$dns" ]] || {
    fail 'Required Pi-hole configuration files are missing.'; return 1;
  }

  iface=${PIHOLE_INTERFACE:-$(detect_iface)}
  [[ -n "$iface" && "$iface" != lo && "$iface" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
    fail 'No valid network interface found; set PIHOLE_INTERFACE explicitly.'; return 1;
  }
  ip link show dev "$iface" >/dev/null 2>&1 || {
    fail "Interface '$iface' does not exist."; return 1;
  }

  mode=$(awk -F= '$1 == "DNSMASQ_LISTENING" { sub(/\r$/, "", $2); print $2; exit }' "$setup")
  # The bundled installer defaults to bind when the setting is absent.
  mode=${mode:-bind}
  case "$mode" in
    bind|single|local|all) ;;
    *) fail "Unsupported DNSMASQ_LISTENING value '$mode'."; return 1 ;;
  esac

  if grep -q '^PIHOLE_INTERFACE=' "$setup"; then
    sed -i "s/^PIHOLE_INTERFACE=.*/PIHOLE_INTERFACE=${iface}/" "$setup"
  else
    printf '\nPIHOLE_INTERFACE=%s\n' "$iface" >> "$setup"
  fi

  # local/all intentionally have no interface restriction. Preserve their config.
  case "$mode" in
    bind|single)
      if grep -q '^interface=' "$dns"; then
        sed -i "s/^interface=.*/interface=${iface}/" "$dns"
      else
        printf '\ninterface=%s\n' "$iface" >> "$dns"
      fi
      ;;
  esac
  printf 'Pi-hole startup: interface=%s, listening=%s\n' "$iface" "$mode"
}

start_services() {
  local name
  for name in pihole-FTL lighttpd ssh; do
    sudo service "$name" start || {
      fail "Failed to start $name."; return 1;
    }
  done
}

main() {
  configure_network /etc/pihole/setupVars.conf /etc/dnsmasq.d/01-pihole.conf
  start_services
  exec sleep infinity
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
