FROM arm32v5/debian:12.10

COPY . /data

WORKDIR /data

RUN apt update && \
    apt install -y openssh-server sudo vim && \
    /bin/bash local-install.sh && \
    /bin/bash make_ssh_user.sh && \
    apt clean && \
    apt autoclean && \
    apt autoremove --yes && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/* /var/tmp/*

EXPOSE 53/udp 67/udp 123/udp 53/tcp 80/tcp 443/tcp

ENTRYPOINT ["/bin/sh", "-c", "/data/start.sh"]
