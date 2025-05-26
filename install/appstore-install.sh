#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
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
# Generate SSH key pair for root user
SSH_KEY_PATH="/root/.ssh/id_rsa"
$STD ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "container-ssh-key"
msg_ok "Generated SSH key pair"

msg_info "Setting up store"
# Fetch the latest release tag
RELEASE=$(curl -fsSL https://api.github.com/repos/community-scripts/ProxmoxVE/releases/latest | jq -r .tag_name | sed 's/^v//')

#https://github.com/community-scripts/ProxmoxVE/archive/refs/tags/2025-05-25.tar.gz
# Download the release tarball
TARBALL_URL="https://github.com/community-scripts/ProxmoxVE/archive/refs/tags/${RELEASE}.tar.gz"
curl -fsSL -o "/tmp/ProxmoxVE-${RELEASE}.tar.gz" "$TARBALL_URL"

# Extract only the frontend folder's contents to /opt/appstore
mkdir -p /opt/appstore
tar -xzf "/tmp/ProxmoxVE-${RELEASE}.tar.gz" --strip-components=2 -C /opt/appstore "ProxmoxVE-${RELEASE}/frontend"/*

msg_ok "Store setup complete"

motd_ssh
customize

msg_info "Cleaning up"
#rm -f "$TARBALL"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
