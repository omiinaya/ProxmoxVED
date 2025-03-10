#!/usr/bin/env bash

# Copyright (c) 2024 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://wazuh.com/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sudo \
    mc \
    curl
msg_ok "Installed Dependencies"

msg_info "Setup Wazuh"
wget -q https://packages.wazuh.com/4.11/wazuh-install.sh
chmod +x wazuh-install.sh
bash ./wazuh-install.sh -a
msg_ok "Setup Wazuh"

motd_ssh
customize

msg_info "Cleaning up"
rm -f wazuh-*.sh
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
