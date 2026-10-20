#!/usr/bin/env bash
# Source only the pinned upstream installation helpers; never download an FTL binary.
set -eo pipefail
export SKIP_INSTALL=true USER=root
source '/etc/.pihole/automated install/basic-install.sh'
install -d /etc/pihole/listsCache /var/log/pihole /run/pihole
create_pihole_user
installScripts
installConfigs
installCron
installLogrotate
installDefaultBlocklists
chown -R pihole:pihole /etc/pihole /var/log/pihole /run/pihole
# Generate v6 defaults without starting services or fetching blocklists during build.
pihole-FTL --config webserver.api.password 'piholearm32v5'
pihole-FTL --config dns.upstreams '["1.1.1.1", "1.0.0.1"]'
pihole-FTL --config dns.listeningMode 'ALL'
pihole-FTL --config ntp.ipv4.active false
pihole-FTL --config ntp.ipv6.active false
pihole-FTL --config ntp.sync.active false
chown -R pihole:pihole /etc/pihole

# The updater runs as pihole, while these pinned repositories belong to root.
# Trust only these image-owned paths; master identifies the release channel.
for repo in /etc/.pihole /var/www/html/admin; do
    git config --system --add safe.directory "$repo"
    git -C "$repo" checkout -B master
done

# Populate local version metadata without querying mutable remote releases.
cat > /etc/pihole/versions <<VERSIONS
CORE_VERSION=${CORE_VERSION}
CORE_BRANCH=master
CORE_HASH=${CORE_COMMIT}
WEB_VERSION=${WEB_VERSION}
WEB_BRANCH=master
WEB_HASH=${WEB_COMMIT}
FTL_VERSION=$(pihole-FTL version)
FTL_BRANCH=$(pihole-FTL branch)
FTL_HASH=$(pihole-FTL --hash)
VERSIONS
chown pihole:pihole /etc/pihole/versions
chmod 0644 /etc/pihole/versions
