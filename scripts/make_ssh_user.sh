#!/usr/bin/env bash

USERNAME="pihole-admin"
DEFAULT_PASSWORD="piholearm32v5"

useradd -m -s /bin/bash "$USERNAME"
usermod -aG sudo "$USERNAME"
echo "$USERNAME:$DEFAULT_PASSWORD" | chpasswd