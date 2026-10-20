#!/usr/bin/env bash
set -euo pipefail
# FTL v6 reads FTLCONF_* directly. PIHOLE_INTERFACE remains a convenience alias.
configure_interface() {
  local iface
  iface=${FTLCONF_dns_interface:-${PIHOLE_INTERFACE:-}}
  if [[ -z "$iface" ]]; then
      iface=$(ip -o link show up | awk -F': ' '{n=$2; sub(/@.*/, "", n)} n != "lo" && n != "" && !found {print n; found=1}')
  fi
  [[ -n "$iface" && "$iface" != lo && "$iface" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
      echo 'No valid interface; set FTLCONF_dns_interface.' >&2; exit 1;
  }
  ip link show dev "$iface" >/dev/null
  export FTLCONF_dns_interface="$iface"
}

main() {
  configure_interface
  mkdir -p /run/sshd /run/pihole /var/log/pihole
  ssh-keygen -A
  /usr/sbin/sshd -t
  service ssh start
  service cron start
  # Initialize gravity once, using upstream DNS from the container resolver.
  if [[ ! -s /etc/pihole/gravity.db ]]; then
      sudo -u pihole --preserve-env=FTLCONF_dns_upstreams bash /opt/pihole/gravity.sh
  fi
  bash /opt/pihole/pihole-FTL-prestart.sh
  # Foreground FTL lets Docker/RouterOS observe failures and deliver shutdown signals.
  exec setpriv --reuid=pihole --regid=pihole --init-groups \
      --inh-caps=+net_bind_service,+net_raw --ambient-caps=+net_bind_service,+net_raw \
      pihole-FTL no-daemon
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
