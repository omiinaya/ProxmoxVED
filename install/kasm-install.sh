#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.kasmweb.com/docs/1.10.0/install/single_server_install.html

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Kasm Workspaces"
KASM_VERSION=$(curl -s https://api.github.com/repos/kasmtech/kasm-release/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-3) }')

$STD curl -sSL https://kasm-static-content.s3.amazonaws.com/kasm_release_${KASM_VERSION}.tar.gz | tar -xz -C /opt
cd /opt/kasm_release
$STD bash install.sh -S -e
msg_ok "Installed Kasm Workspaces"

msg_info "Configuring Swap Space"
if [ ! -f /swapfile ]; then
    $STD fallocate -l 2G /swapfile
    $STD chmod 600 /swapfile
    $STD mkswap /swapfile
    $STD swapon /swapfile
    echo "/swapfile none swap sw 0 0" | $STD tee -a /etc/fstab
fi
msg_ok "Configured Swap Space"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
