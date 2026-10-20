#!/usr/bin/env bash
# Run with sudo if needed for Docker. Leaves no containers or volumes behind.
set -euo pipefail
image=${1:-pihole-armv5:v6-test}
name="pihole-v6-smoke-$$"
tmp=$(mktemp -d)
cleanup() {
  status=$?
  if (( status != 0 )); then docker logs "$name" >&2 || true; fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
for tool in docker curl python3 sshpass ssh; do command -v "$tool" >/dev/null; done
docker run -d --name "$name" --platform linux/arm/v5 \
  -p 127.0.0.1::80 -p 127.0.0.1::443 -p 127.0.0.1::22 \
  -e QEMU_CPU=arm926 \
  -e "FTLCONF_dns_upstreams=${TEST_UPSTREAM:-1.1.1.1}" \
  -e "FTLCONF_dns_dnssec=${TEST_DNSSEC:-true}" "$image" >/dev/null
http_port=$(docker port "$name" 80/tcp | cut -d: -f2)
https_port=$(docker port "$name" 443/tcp | cut -d: -f2)
ssh_port=$(docker port "$name" 22/tcp | cut -d: -f2)
ready=false
for ((i=0; i<120; i++)); do
  if curl -fsS "http://127.0.0.1:$http_port/api/info/login" > /dev/null 2>&1; then
    ready=true; break
  fi
  [[ $(docker inspect -f '{{.State.Running}}' "$name") == true ]] || exit 1
  sleep 2
done
[[ "$ready" == true ]]
curl -fsSL "http://127.0.0.1:$http_port/admin/" > "$tmp/admin.html"
test -s "$tmp/admin.html"
curl -fkSs "https://127.0.0.1:$https_port/admin/" >/dev/null
curl -fsS "http://127.0.0.1:$http_port/api/auth" \
  -H 'Content-Type: application/json' -d '{"password":"piholearm32v5"}' \
  | python3 -c 'import json,sys; assert json.load(sys.stdin)["session"]["valid"]'
sshpass -p piholearm32v5 ssh -p "$ssh_port" \
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$tmp/known_hosts" \
  -o ConnectTimeout=10 pihole-admin@127.0.0.1 'test "$(id -un)" = pihole-admin'
# The scheduled updater must be able to read root-owned, pinned repositories.
for repo in /etc/.pihole /var/www/html/admin; do
  [[ $(docker exec -u pihole "$name" git -C "$repo" rev-parse --abbrev-ref HEAD) == master ]]
  docker exec -u pihole "$name" git -C "$repo" describe --tags --exact-match >/dev/null
done
docker exec "$name" pihole-FTL --version
docker exec "$name" sh -c 'pgrep -x cron && pgrep -x sshd'
# Install a deterministic local blocking rule, then test UDP and TCP DNS.
docker exec -u pihole "$name" pihole-FTL sqlite3 /etc/pihole/gravity.db \
  "INSERT INTO domainlist (type,domain,enabled) VALUES (1,'blocked.example.com',1);"
docker exec "$name" pihole reloaddns
sleep 2
for transport in +notcp +tcp; do
  answer=$(docker exec "$name" dig @127.0.0.1 blocked.example.com +short "$transport")
  [[ "$answer" == 0.0.0.0 ]]
  answer=$(docker exec "$name" dig @127.0.0.1 example.com +short "$transport")
  [[ -n "$answer" && "$answer" != 0.0.0.0 ]]
done
# Restart must retain the database and documented password.
docker restart --time 20 "$name" >/dev/null
# Docker may allocate a different ephemeral host port on restart.
http_port=$(docker port "$name" 80/tcp | cut -d: -f2)
for ((i=0; i<60; i++)); do
  if curl -fsS "http://127.0.0.1:$http_port/api/info/login" >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -fsS "http://127.0.0.1:$http_port/api/auth" \
  -H 'Content-Type: application/json' -d '{"password":"piholearm32v5"}' \
  | python3 -c 'import json,sys; assert json.load(sys.stdin)["session"]["valid"]'
[[ $(docker exec "$name" dig @127.0.0.1 blocked.example.com +short) == 0.0.0.0 ]]
echo 'PASS: HTTP, HTTPS, web password, SSH, cron, UDP/TCP DNS, blocking, restart'
