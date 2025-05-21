#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Adapted for Lyrion Music Server
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://lyrion.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Lyrion Music Server"
DEB_URL="https://downloads.lms-community.org/LyrionMusicServer_v9.0.2/lyrionmusicserver_9.0.2_amd64.deb"
DEB_FILE="/tmp/lyrionmusicserver_9.0.2_amd64.deb"
curl -fsSL -o "$DEB_FILE" "$DEB_URL" 2>&1 | tee -a ~/lyrion-install.log
$STD apt install "$DEB_FILE" -y 2>&1 | tee -a ~/lyrion-install.log
msg_ok "Installed Lyrion Music Server"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f "$DEB_FILE"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
