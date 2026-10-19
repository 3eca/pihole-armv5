# About
The project was created with the purpose of using pi-hole on mikrotik hex refresh.
According to [documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container) of the manufacturer this model has a limitation to run containers due to the EN7562CT processor.

You can only run containers for the armv5 platform. [Thanks to them for the link to a repository of available containers.](https://hub.docker.com/u/arm32v5)

Thanks to [article](https://podarok66.livejournal.com/24911.html) and the availability of the FTL v5.x binary, this solution allows to run pi-hole for the armv5 platform.

# Source code used
* [pi-hole-5.11.4](https://github.com/pi-hole/pi-hole/releases/tag/v5.11.4)
Original [license](https://github.com/pi-hole/pi-hole/blob/master/LICENSE)
* [FTL-5.16.1](https://github.com/pi-hole/FTL/releases/download/v5.16.1/pihole-FTL-armv5-linux-gnueabi)
Original [license](https://github.com/pi-hole/FTL/blob/master/LICENSE)
* [web-5.13](https://github.com/pi-hole/web/releases/tag/v5.13)
Original [license](https://github.com/pi-hole/pi-hole/blob/master/LICENSE)

# Default WEB password

```
piholearm32v5
```

# Default SSH user\password
```
pihole-admin
piholearm32v5
```

# Mikrotik container
```bash
/container/add remote-image=holynash/pihole-armv5:latest hostname="pihole" interface=veth1 logging=yes root-dir=<storage_path> start-on-boot=yes
# wait to extract
/container/start number=0
```
To access the web interface, open the IP address assigned to the veth1 interface in your browser.

If you're using static IP addresses, be sure to set the Pi-hole container's IP as the DNS server on each client.

If you're using DHCP, go to IP -> DHCP Server -> Networks and set the DNS server to the Pi-hole container's IP.

# Docker Hub
https://hub.docker.com/r/holynash/pihole-armv5
Enjoy.

# Runtime network interface

At container startup, `start.sh` uses `PIHOLE_INTERFACE` from the environment
when supplied. Otherwise it prefers an existing `veth1`, then the first UP
interface other than loopback. The selected interface must exist; an invalid
selection stops startup before configuration files are changed.

The selected name is saved in `/etc/pihole/setupVars.conf`. For the `bind` and
`single` listening modes, the `interface=` setting in dnsmasq is updated too.
The `local` and `all` modes retain their existing dnsmasq configuration.

Startup reports service errors and exits if FTL, lighttpd, or SSH cannot start.
It does not monitor service health after startup.

# Startup tests

Run `python3 -m unittest discover -s tests -v`. Tests use temporary configuration
files and mocked commands; they do not start services or require RouterOS.
