#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: Omar Minaya
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"

$STD apt-get install -y \
    openssh-client \
    jq

msg_ok "Installed Dependencies"

msg_info "Generating SSH key pair"

SSH_KEY_PATH="/root/.ssh/id_rsa"
$STD ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "container-ssh-key"

msg_ok "Generated SSH key pair"

msg_info "Setting up store"

RELEASE=$(curl -fsSL https://api.github.com/repos/community-scripts/ProxmoxVE/releases/latest | jq -r .tag_name | sed 's/^v//')
TARBALL_URL="https://github.com/community-scripts/ProxmoxVE/archive/refs/tags/${RELEASE}.tar.gz"
curl -fsSL -o "/tmp/ProxmoxVE-${RELEASE}.tar.gz" "$TARBALL_URL"
mkdir -p /opt/appstore
tar -xzf "/tmp/ProxmoxVE-${RELEASE}.tar.gz" --wildcards --strip-components=2 -C /opt/appstore '*/frontend/*'

msg_ok "Store setup complete"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "/tmp/ProxmoxVE-${RELEASE}.tar.gz"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
