#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://fogproject.org/

set -e

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing FOGProject"
cd /opt
curl -fsSL -o stable.tar.gz "https://github.com/FOGProject/fogproject/archive/stable.tar.gz"
tar xzf stable.tar.gz
cd fogproject-stable/bin
$STD sudo ./installfog.sh -y
msg_ok "Installed FOGProject"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f /opt/stable.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
